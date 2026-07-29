import 'package:flutter/foundation.dart';

// ignore_for_file: slash_for_doc_comments

/** 定向重试一组缓存失败项，返回实际重新排队数。 */
typedef RetryCacheFailures<T> = Future<int> Function(Iterable<T> items);

/** 清除一组内存失败标记，返回实际清除数。 */
typedef ClearCacheFailures<T> = int Function(Iterable<T> items);

/** 通过 Repository 持久化失败标记变化。 */
typedef PersistCacheFailureChanges<T> = Future<void> Function(
  Iterable<T> items,
);

/** 判断重试命令是否已经清除条目的旧失败标记。 */
typedef IsCacheFailureResolved<T> = bool Function(T item);

/** Repository 写入失败时恢复条目的原失败原因。 */
typedef RestoreCacheFailure<T> = void Function(T item, String reason);

/** 缓存命令使用的稳定条目与原失败原因。 */
class CacheFailureCommandTarget<T> {
  const CacheFailureCommandTarget({
    required this.item,
    required this.reason,
  });

  /** 由调用方提供的稳定媒体对象。 */
  final T item;

  /** 命令开始前的失败原因，用于持久化失败回滚。 */
  final String reason;
}

/** 失败项重试完成后的可见摘要。 */
class CacheRetryOutcome {
  const CacheRetryOutcome({
    required this.requested,
    required this.retried,
  });

  /** 用户请求重试的失败项数量。 */
  final int requested;

  /** 受队列容量限制后实际重新排队的数量。 */
  final int retried;
}

/** 清除失败标记完成后的可见摘要。 */
class CacheClearOutcome {
  const CacheClearOutcome({required this.cleared});

  /** 实际清除并成功持久化的失败标记数量。 */
  final int cleared;
}

/**
 * 缓存诊断维护命令的一致性 owner。
 *
 * controller 串行化重试与清除，编排缓存服务和 Repository 写入，并在清除持久化失败时
 * 恢复原失败原因。它不持有 `BuildContext`、Route、Widget、读取 controller 或具体
 * 缓存实现；页面继续负责 SnackBar、确认入口和只读统计刷新。
 */
class CacheDiagnosticsMaintenanceController<T> extends ChangeNotifier {
  CacheDiagnosticsMaintenanceController({
    required RetryCacheFailures<T> retryFailures,
    required ClearCacheFailures<T> clearFailures,
    required PersistCacheFailureChanges<T> persistChanges,
    required IsCacheFailureResolved<T> isFailureResolved,
    required RestoreCacheFailure<T> restoreFailure,
  })  : _retryFailures = retryFailures,
        _clearFailures = clearFailures,
        _persistChanges = persistChanges,
        _isFailureResolved = isFailureResolved,
        _restoreFailure = restoreFailure;

  /** 缓存服务的失败项重试命令。 */
  final RetryCacheFailures<T> _retryFailures;

  /** 缓存服务的失败标记清除命令。 */
  final ClearCacheFailures<T> _clearFailures;

  /** Repository 的失败标记持久化命令。 */
  final PersistCacheFailureChanges<T> _persistChanges;

  /** 判断重试后哪些条目需要持久化。 */
  final IsCacheFailureResolved<T> _isFailureResolved;

  /** 清除写入失败时的内存补偿命令。 */
  final RestoreCacheFailure<T> _restoreFailure;

  /** 两类维护命令共用的互斥状态。 */
  var _busy = false;

  /** 页面释放后阻止新命令和异步完成通知。 */
  var _disposed = false;

  /** 是否已有缓存维护命令正在执行。 */
  bool get busy => _busy;

  /** 重试失败项；互斥或空输入时返回 null 且不执行命令。 */
  Future<CacheRetryOutcome?> retry(
    Iterable<CacheFailureCommandTarget<T>> failures,
  ) async {
    final targets = failures.toList(growable: false);
    if (!_begin(targets)) {
      return null;
    }
    try {
      final items =
          targets.map((target) => target.item).toList(growable: false);
      final retried = await _retryFailures(items);
      final changed = items.where(_isFailureResolved).toList(growable: false);
      if (changed.isNotEmpty) {
        await _persistChanges(changed);
      }
      return CacheRetryOutcome(requested: items.length, retried: retried);
    } finally {
      _finish();
    }
  }

  /**
   * 清除失败标记并持久化；写入失败时恢复全部原原因后把错误交给页面展示。
   */
  Future<CacheClearOutcome?> clear(
    Iterable<CacheFailureCommandTarget<T>> failures,
  ) async {
    final targets = failures.toList(growable: false);
    if (!_begin(targets)) {
      return null;
    }
    try {
      final items =
          targets.map((target) => target.item).toList(growable: false);
      final cleared = _clearFailures(items);
      try {
        await _persistChanges(items);
      } catch (_) {
        // 跨服务写入未提交时恢复缓存对象，避免 UI 与 Repository 状态分裂。
        for (final target in targets) {
          _restoreFailure(target.item, target.reason);
        }
        rethrow;
      }
      return CacheClearOutcome(cleared: cleared);
    } finally {
      _finish();
    }
  }

  /** 原子取得互斥门禁并发布 busy。 */
  bool _begin(List<CacheFailureCommandTarget<T>> targets) {
    if (_disposed || _busy || targets.isEmpty) {
      return false;
    }
    _busy = true;
    notifyListeners();
    return true;
  }

  /** 释放互斥门禁；页面销毁后不再通知。 */
  void _finish() {
    _busy = false;
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
