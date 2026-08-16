import 'dart:async';

// ignore_for_file: slash_for_doc_comments

/** 需要共享本地 I/O/解码预算的资源类别。 */
enum ResourceKind { scan, probe, thumbnail, visual, backup }

/** 资源请求的调度优先级；前台请求只越过尚未启动的后台任务。 */
enum ResourcePriority { foreground, background }

/** ResourceScheduler 的可观测计数，不包含路径、videoId 或媒体内容。 */
class ResourceSchedulerSnapshot {
  const ResourceSchedulerSnapshot({
    required this.playbackActive,
    required this.activeTotal,
    required this.queuedTotal,
    required this.activeByKind,
    required this.queuedByKind,
  });

  final bool playbackActive;
  final int activeTotal;
  final int queuedTotal;
  final Map<ResourceKind, int> activeByKind;
  final Map<ResourceKind, int> queuedByKind;
}

class _ResourceRequest {
  _ResourceRequest({
    required this.kind,
    required this.priority,
    required this.allowDuringPlayback,
    required this.completer,
    required this.sequence,
  });

  final ResourceKind kind;
  final ResourcePriority priority;
  final bool allowDuringPlayback;
  final Completer<ResourceLease> completer;
  final int sequence;
}

/** 一次受控资源占用；释放幂等，避免异常路径重复归还预算。 */
class ResourceLease {
  ResourceLease._(this.kind, this._release);

  final ResourceKind kind;
  final void Function() _release;
  var _released = false;

  bool get isReleased => _released;

  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _release();
  }
}

/**
 * 扫描、探测、缩略图、视觉和备份共用的轻量资源调度器。
 *
 * 它只负责排队和预算，不拥有任何平台后端，也不复制业务状态。播放激活时默认
 * 阻止后台资源，前台请求可以显式越过；当前已取得的 lease 允许自然收尾，避免
 * 中断 FFmpeg/SQLite 批次造成半成品缓存或游标。
 */
class ResourceScheduler {
  ResourceScheduler({
    Map<ResourceKind, int>? budgets,
    int? totalBudget,
  })  : _budgets = _normalizeBudgets(budgets),
        _totalBudget = totalBudget ?? _defaultTotalBudget {
    if (_totalBudget <= 0) {
      throw ArgumentError.value(totalBudget, 'totalBudget', '必须大于 0');
    }
  }

  static const int _defaultTotalBudget = 4;
  static const Map<ResourceKind, int> _defaultBudgets = {
    ResourceKind.scan: 1,
    ResourceKind.probe: 1,
    ResourceKind.thumbnail: 2,
    ResourceKind.visual: 1,
    ResourceKind.backup: 1,
  };

  static Map<ResourceKind, int> _normalizeBudgets(
    Map<ResourceKind, int>? budgets,
  ) {
    final normalized = <ResourceKind, int>{
      ..._defaultBudgets,
      ...?budgets,
    };
    for (final entry in normalized.entries) {
      if (entry.value <= 0) {
        throw ArgumentError.value(
          entry.value,
          'budgets[${entry.key}]',
          '必须大于 0',
        );
      }
    }
    return Map<ResourceKind, int>.unmodifiable(normalized);
  }

  final Map<ResourceKind, int> _budgets;
  final int _totalBudget;
  final List<_ResourceRequest> _waiting = <_ResourceRequest>[];
  final Map<ResourceKind, int> _activeByKind = <ResourceKind, int>{};
  var _activeTotal = 0;
  var _sequence = 0;
  var _playbackActive = false;
  var _disposed = false;

  bool get playbackActive => _playbackActive;

  /** 播放会话切换时只影响尚未取得 lease 的后台请求。 */
  void setPlaybackActive(bool active) {
    if (_playbackActive == active) {
      return;
    }
    _playbackActive = active;
    _pump();
  }

  /** 取得一个资源预算；调用方必须在 finally 中释放返回的 lease。 */
  Future<ResourceLease> acquire(
    ResourceKind kind, {
    ResourcePriority priority = ResourcePriority.background,
    bool allowDuringPlayback = false,
  }) {
    if (_disposed) {
      return Future<ResourceLease>.error(StateError('资源调度器已关闭'));
    }
    final request = _ResourceRequest(
      kind: kind,
      priority: priority,
      allowDuringPlayback: allowDuringPlayback,
      completer: Completer<ResourceLease>(),
      sequence: _sequence++,
    );
    _waiting.add(request);
    _pump();
    return request.completer.future;
  }

  /** 在一次资源占用中执行动作，保证成功和异常路径都归还预算。 */
  Future<T> run<T>(
    ResourceKind kind,
    Future<T> Function() action, {
    ResourcePriority priority = ResourcePriority.background,
    bool allowDuringPlayback = false,
  }) async {
    final lease = await acquire(
      kind,
      priority: priority,
      allowDuringPlayback: allowDuringPlayback,
    );
    try {
      return await action();
    } finally {
      lease.release();
    }
  }

  ResourceSchedulerSnapshot get snapshot => ResourceSchedulerSnapshot(
        playbackActive: _playbackActive,
        activeTotal: _activeTotal,
        queuedTotal: _waiting.length,
        activeByKind: Map<ResourceKind, int>.unmodifiable(_activeByKind),
        queuedByKind: Map<ResourceKind, int>.unmodifiable({
          for (final kind in ResourceKind.values)
            kind: _waiting.where((request) => request.kind == kind).length,
        }),
      );

  void _pump() {
    if (_disposed) {
      return;
    }
    while (_activeTotal < _totalBudget) {
      final index = _nextEligibleIndex();
      if (index < 0) {
        return;
      }
      final request = _waiting.removeAt(index);
      final active = _activeByKind[request.kind] ?? 0;
      _activeByKind[request.kind] = active + 1;
      _activeTotal++;
      final lease = ResourceLease._(request.kind, () {
        final current = _activeByKind[request.kind] ?? 0;
        if (current <= 1) {
          _activeByKind.remove(request.kind);
        } else {
          _activeByKind[request.kind] = current - 1;
        }
        _activeTotal--;
        _pump();
      });
      request.completer.complete(lease);
    }
  }

  int _nextEligibleIndex() {
    var bestIndex = -1;
    _ResourceRequest? best;
    for (var index = 0; index < _waiting.length; index++) {
      final candidate = _waiting[index];
      if (!_canStart(candidate)) {
        continue;
      }
      if (best == null ||
          candidate.priority.index < best.priority.index ||
          (candidate.priority == best.priority &&
              candidate.sequence < best.sequence)) {
        best = candidate;
        bestIndex = index;
      }
    }
    return bestIndex;
  }

  bool _canStart(_ResourceRequest request) {
    if (_playbackActive &&
        request.priority == ResourcePriority.background &&
        !request.allowDuringPlayback) {
      return false;
    }
    return (_activeByKind[request.kind] ?? 0) < _budgets[request.kind]!;
  }

  /** 关闭后拒绝尚未开始的任务；已取得资源仍由 owner 自行收尾。 */
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final error = StateError('资源调度器已关闭');
    for (final request in _waiting) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(error);
      }
    }
    _waiting.clear();
  }
}
