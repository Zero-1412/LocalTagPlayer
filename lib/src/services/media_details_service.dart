part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

class MediaDetailsService {
  MediaDetailsService({
    this.onUpdated,
    MediaProbeBackend? probeBackend,
  })  : _probeBackend = probeBackend ?? createMediaProbeBackend(),
        _generation = _nextGeneration++;

  /** 进程内递增代号，避免多个播放器页面取消同一个原生 generation。 */
  static int _nextGeneration = 1;

  final Future<void> Function(
      VideoItem item, MediaDetails details, String? fingerprint)? onUpdated;
  /** 批量媒体探测平台边界；SQLite 写回仍由 [onUpdated] 所在 Repository 完成。 */
  final MediaProbeBackend _probeBackend;
  final Map<String, Future<MediaDetails>> _inFlight = {};
  final Map<String, MediaDetails> _cache = {};
  final Set<String> _queuedPaths = {};
  var _activeReads = 0;
  var _completedThisRun = 0;
  var _failedThisRun = 0;
  Future<void> _queue = Future<void>.value();
  int _generation;
  var _disposed = false;

  int get queuedReads => _queuedPaths.length;
  int get activeReads => _activeReads;
  int get completedThisRun => _completedThisRun;
  int get failedThisRun => _failedThisRun;

  /** 当前服务是否已经退出播放器生命周期。 */
  bool get isDisposed => _disposed;

  /**
   * 仅读取内存或视频模型中已经持久化的详情，不启动 FFprobe 或 media_kit。
   */
  MediaDetails? cachedDetailsFor(VideoItem item) {
    return _cache[item.path] ?? item.mediaDetails;
  }

  Future<MediaDetails> detailsFor(VideoItem item) {
    final cached = cachedDetailsFor(item);
    if (cached != null) {
      _cache[item.path] = cached;
      return Future.value(cached);
    }
    if (_disposed) {
      return Future.value(const MediaDetails());
    }

    return _inFlight.putIfAbsent(item.path, () {
      final generation = _generation;
      _queuedPaths.add(item.path);
      final task = _queue.then((_) async {
        _queuedPaths.remove(item.path);
        if (_disposed || generation != _generation) {
          return cachedDetailsFor(item) ?? const MediaDetails();
        }
        _activeReads++;
        try {
          final details = await _read(item, generation);
          if (_disposed || generation != _generation) {
            return details;
          }
          if (item.mediaDetailsError == null) {
            _completedThisRun++;
          } else {
            _failedThisRun++;
          }
          return details;
        } finally {
          _activeReads--;
        }
      });
      _queue = task.then((_) {}, onError: (_) {});
      // Map.remove 会返回被移除的 Future；必须用块体丢弃返回值，否则 whenComplete 会等待自身形成闭环。
      return task.whenComplete(() {
        _inFlight.remove(item.path);
      });
    });
  }

  /**
   * 读取单条媒体详情；[generation] 用于阻止旧播放器任务回写新页面状态。
   */
  Future<MediaDetails> _read(VideoItem item, int generation) async {
    final path = item.path;
    // 扫描阶段已经保存 fingerprint、大小和修改时间，播放器详情不得再次 stat 或读取首尾样本。
    final fingerprint = item.mediaFingerprint;
    try {
      final results = await _probeBackend.probeBatch(
        generationId: generation,
        requests: <MediaProbeRequest>[
          MediaProbeRequest(
            videoId: item.videoId,
            path: path,
            knownSize: item.fileSize,
            knownModifiedAt: item.modifiedMs,
          ),
        ],
      );
      final result = results.firstOrNull;
      if (result?.cancelled == true || _disposed || generation != _generation) {
        return const MediaDetails();
      }
      final details = result?.details;
      if (details != null && result?.error == null) {
        item.mediaDetailsError = null;
        _cache[path] = details;
        await _notifyUpdated(item, details, fingerprint, generation);
        return details;
      }
      item.mediaDetailsError = result?.error ?? 'media probe unavailable';
    } catch (error) {
      item.mediaDetailsError = 'media probe: ${error.runtimeType}';
    }
    const details = MediaDetails();
    _cache[path] = details;
    await _notifyUpdated(item, details, fingerprint, generation);
    return details;
  }

  /** 仅允许当前播放器代际把详情写回媒体库。 */
  Future<void> _notifyUpdated(
    VideoItem item,
    MediaDetails details,
    String? fingerprint,
    int generation,
  ) async {
    if (_disposed || generation != _generation) {
      return;
    }
    await onUpdated?.call(item, details, fingerprint);
  }

  /**
   * 立即丢弃尚未开始的读取和所有后续回调。
   *
   * 已经交给外部 FFprobe 的单个进程不能由当前兼容接口强杀，但完成后不会再写回；
   * 队列中其余任务会通过代际检查直接短路。
   */
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    // 纯 Dart/widget test 没有 Windows runner 通道；取消仍应 best-effort，不能在 dispose 后抛出异步异常。
    unawaited(
      _probeBackend.cancelGeneration(_generation).then<void>(
            (_) {},
            onError: (_) {},
          ),
    );
    _generation++;
    _queuedPaths.clear();
    _inFlight.clear();
    _cache.clear();
  }
}
