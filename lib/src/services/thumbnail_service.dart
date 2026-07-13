part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

class _ThumbnailJob {
  const _ThumbnailJob({
    required this.cacheKey,
    required this.run,
    required this.isBackground,
  });

  final String cacheKey;
  /** 生成完成后返回可显示文件；失败时返回 null。 */
  final Future<File?> Function() run;
  final bool isBackground;
}

/**
 * 缩略图缓存统计快照，供设置/诊断页展示当前缓存队列状态。
 */
class CacheStats {
  const CacheStats({
    required this.total,
    required this.cached,
    required this.missing,
    required this.errors,
    required this.queued,
    required this.pendingBackgroundRequests,
    required this.active,
    required this.activeBackground,
    required this.maxConcurrent,
    required this.maxBackground,
    required this.maxBackgroundQueued,
    required this.paused,
    required this.completedThisRun,
    required this.failedThisRun,
    required this.ffmpegCompleted,
    required this.fallbackCompleted,
    required this.averageMs,
  });

  final int total;
  final int cached;
  final int missing;
  final int errors;
  final int queued;
  /** 包含 cache key/JPEG 验证与已入队生成的后台请求数。 */
  final int pendingBackgroundRequests;
  final int active;
  final int activeBackground;
  final int maxConcurrent;
  final int maxBackground;
  final int maxBackgroundQueued;
  final bool paused;
  final int completedThisRun;
  final int failedThisRun;
  final int ffmpegCompleted;
  final int fallbackCompleted;
  final int averageMs;
}

class ThumbnailService {
  ThumbnailService._(this._directory);
  static const _maxBackgroundQueuedJobs = 500;
  static const _maxBackgroundRequestsInFlight = 24;

  final Directory _directory;
  static int get _maxConcurrentJobs {
    final cores = Platform.numberOfProcessors;
    if (cores >= 12) {
      return 4;
    }
    if (cores >= 8) {
      return 3;
    }
    return 2;
  }

  static int get _maxBackgroundJobs {
    return Platform.numberOfProcessors >= 8 ? 2 : 1;
  }

  final Map<String, File?> _memoryCache = {};
  /**
   * 已验证缩略图按媒体路径保存的同步视图，供页面切换首帧直接复用。
   *
   * 真正的有效性检查仍由 [thumbnailFor] 完成；这里只返回本次进程内已经验证过的文件，
   * 避免播放器队列即使命中缓存也必须先绘制一帧占位背景。
   */
  final Map<String, File?> _pathMemoryCache = {};
  final Set<String> _activeCacheKeys = {};
  final Set<String> _backgroundQueued = {};
  final Set<String> _priorityQueued = {};
  /** 删除发生在生成期间时阻止旧任务把已删除视频的 JPEG 重新写回缓存。 */
  final Set<String> _suppressedActiveCacheKeys = {};
  /** 同一 cache key 的可见卡片与预取任务共享一个完成信号。 */
  final Map<String, Completer<File?>> _jobCompletions =
      <String, Completer<File?>>{};
  final Queue<_ThumbnailJob> _priorityJobs = Queue();
  final Queue<_ThumbnailJob> _backgroundJobs = Queue();
  /** 尚未执行 cache key/JPEG 校验的后台候选，避免一次扫描同时唤醒 500 个文件 I/O Future。 */
  final Queue<VideoItem> _backgroundCandidates = Queue();
  final Set<String> _backgroundCandidatePaths = {};
  var _activeJobs = 0;
  var _activeBackgroundJobs = 0;
  /** 已接受但尚未结束的后台请求，包含 cache key 与 JPEG 验证阶段。 */
  var _backgroundRequestsInFlight = 0;
  var _completed = 0;
  var _failed = 0;
  var _ffmpegCompleted = 0;
  var _fallbackCompleted = 0;
  var _totalGenerateMs = 0;
  var _isPaused = false;

  bool get isPaused => _isPaused;
  int get activeJobs => _activeJobs;
  int get queuedJobs =>
      _priorityQueued.length +
      _backgroundQueued.length +
      _backgroundCandidates.length;
  int get maxBackgroundQueuedJobs => _maxBackgroundQueuedJobs;
  int get maxConcurrentJobs => _maxConcurrentJobs;
  int get activeBackgroundJobs => _activeBackgroundJobs;
  int get maxBackgroundJobs => _maxBackgroundJobs;

  void pause() {
    _isPaused = true;
  }

  void resume() {
    if (!_isPaused) {
      return;
    }
    _isPaused = false;
    _drainQueue();
    _pumpBackgroundCandidates(allowPlayerFallback: false);
  }

  static Future<ThumbnailService> create() async {
    final directory = await AppPaths.thumbnailDirectory();
    return ThumbnailService._(directory);
  }

  Future<File?> thumbnailFor(VideoItem item) async {
    final cacheKey = await _cacheKeyFor(item);
    if (cacheKey == null) {
      return null;
    }
    if (_memoryCache.containsKey(cacheKey)) {
      final cached = _memoryCache[cacheKey];
      if (cached == null) {
        _pathMemoryCache[item.path] = null;
        return null;
      }
      if (await _isValidThumbnailFile(cached)) {
        _pathMemoryCache[item.path] = cached;
        return cached;
      }
      _memoryCache.remove(cacheKey);
      _pathMemoryCache.remove(item.path);
      return null;
    }

    final file = File(p.join(_directory.path, '$cacheKey.jpg'));
    if (await _isValidThumbnailFile(file)) {
      _memoryCache[cacheKey] = file;
      _pathMemoryCache[item.path] = file;
      return file;
    }

    _pathMemoryCache[item.path] = null;
    return null;
  }

  /** 返回本次进程内已验证的缩略图，不触发文件系统访问。 */
  File? cachedThumbnailFor(VideoItem item) => _pathMemoryCache[item.path];

  void prefetchAll(Iterable<VideoItem> items,
      {bool allowPlayerFallback = false}) {
    for (final item in items) {
      if (_backgroundCandidates.length + _backgroundRequestsInFlight >=
          _maxBackgroundQueuedJobs) {
        break;
      }
      if (_backgroundCandidatePaths.add(item.path)) {
        _backgroundCandidates.add(item);
      }
    }
    _pumpBackgroundCandidates(allowPlayerFallback: allowPlayerFallback);
  }

  /**
   * 小批量推进后台 cache key/JPEG 校验。
   *
   * 生成并发仍由 `_drainQueue` 限制；这里额外限制进入异步文件校验的 Future 数量，
   * 防止扫描完成后数百个 completion 同时抢占 Flutter 事件循环。
   */
  void _pumpBackgroundCandidates({required bool allowPlayerFallback}) {
    while (!_isPaused &&
        _backgroundRequestsInFlight < _maxBackgroundRequestsInFlight &&
        _backgroundCandidates.isNotEmpty) {
      final item = _backgroundCandidates.removeFirst();
      _backgroundCandidatePaths.remove(item.path);
      _backgroundRequestsInFlight++;
      unawaited(
        _queuePrefetch(item, allowPlayerFallback: allowPlayerFallback)
            .whenComplete(() {
          _backgroundRequestsInFlight--;
          _pumpBackgroundCandidates(
            allowPlayerFallback: allowPlayerFallback,
          );
        }),
      );
    }
  }

  void prefetchVisible(Iterable<VideoItem> items) {
    for (final item in items) {
      unawaited(
          _queuePrefetch(item, priority: true, allowPlayerFallback: true));
    }
  }

  /**
   * 删除一个视频对应的内存缓存、等待任务与磁盘 JPEG。
   *
   * cache key 优先复用扫描阶段持久化的 size/mtime，不为正常数据库记录重复 stat 原视频。
   */
  Future<void> deleteThumbnailFor(VideoItem item) async {
    _backgroundCandidates.removeWhere(
      (candidate) => candidate.path == item.path,
    );
    _backgroundCandidatePaths.remove(item.path);
    final cacheKey = await _cacheKeyFor(item);
    _pathMemoryCache.remove(item.path);
    if (cacheKey == null) {
      return;
    }

    _priorityJobs.removeWhere((job) => job.cacheKey == cacheKey);
    _backgroundJobs.removeWhere((job) => job.cacheKey == cacheKey);
    _priorityQueued.remove(cacheKey);
    _backgroundQueued.remove(cacheKey);
    _memoryCache.remove(cacheKey);
    if (_activeCacheKeys.contains(cacheKey)) {
      // 活动 FFmpeg/media_kit 任务不能强杀；完成写入时由抑制标记立即丢弃结果。
      _suppressedActiveCacheKeys.add(cacheKey);
    } else {
      final completion = _jobCompletions.remove(cacheKey);
      if (completion != null && !completion.isCompleted) {
        completion.complete(null);
      }
    }

    final file = File(p.join(_directory.path, '$cacheKey.jpg'));
    PaintingBinding.instance.imageCache.evict(FileImage(file));
    for (final candidate in <File>[file, File('${file.path}.tmp.jpg')]) {
      try {
        if (await candidate.exists()) {
          await candidate.delete();
        }
      } on FileSystemException {
        // 图片仍被解码器短暂持有时由后续缓存清理重试；数据库删除不应因此失败。
      }
    }
  }

  /** 批量清理已从媒体库移除的视频缩略图，避免一次创建无界 Future 列表。 */
  Future<void> deleteThumbnailsFor(Iterable<VideoItem> items) async {
    for (final item in items) {
      await deleteThumbnailFor(item);
    }
  }

  /**
   * 优先返回已验证缓存；未命中时等待该视频的优先生成任务。
   *
   * 可见卡片必须绑定到真正的生成 Future，否则 FFmpeg 完成后界面不会自动更新。
   * 并发上限仍由全局队列约束，不会为每张卡片直接启动 FFmpeg。
   */
  Future<File?> ensureThumbnailFor(VideoItem item) {
    return _queuePrefetch(
      item,
      priority: true,
      allowPlayerFallback: true,
    );
  }

  Future<File?> _queuePrefetch(
    VideoItem item, {
    bool priority = false,
    bool allowPlayerFallback = false,
  }) async {
    final verified = cachedThumbnailFor(item);
    if (verified != null) {
      // 进程内快照只会在 JPEG 完整性校验成功后写入；卡片重建不应重复打开文件。
      return verified;
    }
    final cacheKey = await _cacheKeyFor(item);
    if (cacheKey == null) {
      return null;
    }
    final file = File(p.join(_directory.path, '$cacheKey.jpg'));
    if (_memoryCache.containsKey(cacheKey)) {
      final cached = _memoryCache[cacheKey];
      if (cached == null || await _isValidThumbnailFile(cached)) {
        _pathMemoryCache[item.path] = cached;
        return cached;
      }
      _memoryCache.remove(cacheKey);
      _pathMemoryCache.remove(item.path);
    }
    if (await _isValidThumbnailFile(file)) {
      _memoryCache[cacheKey] = file;
      _pathMemoryCache[item.path] = file;
      return file;
    }
    final completion = _jobCompletions.putIfAbsent(
      cacheKey,
      Completer<File?>.new,
    );
    if (_activeCacheKeys.contains(cacheKey)) {
      return completion.future;
    }

    if (priority) {
      if (_priorityQueued.contains(cacheKey)) {
        // 快速滚动停止后，把当前可见项从旧可见队列中提升到队首。
        _ThumbnailJob? queuedJob;
        _priorityJobs.removeWhere((job) {
          if (job.cacheKey != cacheKey) {
            return false;
          }
          queuedJob = job;
          return true;
        });
        if (queuedJob != null) {
          _priorityJobs.addFirst(queuedJob!);
        }
        return completion.future;
      }
      if (_backgroundQueued.remove(cacheKey)) {
        _backgroundJobs.removeWhere((job) => job.cacheKey == cacheKey);
      }
      _priorityQueued.add(cacheKey);
      // 最新构建的可见卡片优先于快速滚动遗留的离屏任务。
      _priorityJobs.addFirst(
        _ThumbnailJob(
          cacheKey: cacheKey,
          isBackground: false,
          run: () async {
            try {
              return await _generate(
                item,
                file,
                cacheKey,
                allowPlayerFallback,
              );
            } finally {
              _priorityQueued.remove(cacheKey);
            }
          },
        ),
      );
    } else {
      if (_backgroundQueued.length >= _maxBackgroundQueuedJobs) {
        _jobCompletions.remove(cacheKey);
        if (!completion.isCompleted) {
          completion.complete(null);
        }
        return null;
      }
      if (_backgroundQueued.contains(cacheKey) ||
          _priorityQueued.contains(cacheKey)) {
        return completion.future;
      }
      _backgroundQueued.add(cacheKey);
      _backgroundJobs.add(
        _ThumbnailJob(
          cacheKey: cacheKey,
          isBackground: true,
          run: () async {
            try {
              return await _generate(
                item,
                file,
                cacheKey,
                allowPlayerFallback,
              );
            } finally {
              _backgroundQueued.remove(cacheKey);
            }
          },
        ),
      );
    }
    _drainQueue();
    return completion.future;
  }

  void _drainQueue() {
    if (_isPaused) {
      return;
    }
    while (_activeJobs < _maxConcurrentJobs &&
        (_priorityJobs.isNotEmpty || _backgroundJobs.isNotEmpty)) {
      final job = _nextJob();
      if (job == null) {
        return;
      }
      _activeJobs++;
      _activeCacheKeys.add(job.cacheKey);
      if (job.isBackground) {
        _activeBackgroundJobs++;
      }
      unawaited(
        job
            .run()
            .then<void>(
              (file) => _completeJob(job.cacheKey, file),
              onError: (_) => _completeJob(job.cacheKey, null),
            )
            .whenComplete(() {
          _activeJobs--;
          if (job.isBackground) {
            _activeBackgroundJobs--;
          }
          _activeCacheKeys.remove(job.cacheKey);
          _drainQueue();
        }),
      );
    }
  }

  /** 完成所有等待同一 cache key 的可见卡片，并立即释放信号。 */
  void _completeJob(String cacheKey, File? file) {
    final completion = _jobCompletions.remove(cacheKey);
    if (completion != null && !completion.isCompleted) {
      completion.complete(file);
    }
  }

  _ThumbnailJob? _nextJob() {
    if (_priorityJobs.isNotEmpty) {
      return _priorityJobs.removeFirst();
    }
    if (_backgroundJobs.isNotEmpty &&
        _activeBackgroundJobs < _maxBackgroundJobs) {
      return _backgroundJobs.removeFirst();
    }
    return null;
  }

  Future<File?> _generate(
    VideoItem item,
    File output,
    String cacheKey,
    bool allowPlayerFallback,
  ) async {
    final stopwatch = Stopwatch()..start();
    final videoPath = item.path;
    final source = File(videoPath);
    if (!await source.exists()) {
      item.thumbnailError = '\u6587\u4ef6\u4e0d\u5b58\u5728';
      _failed++;
      _totalGenerateMs += stopwatch.elapsedMilliseconds;
      _memoryCache[cacheKey] = null;
      _pathMemoryCache[item.path] = null;
      return null;
    }

    try {
      final file = await ExternalMediaTools.createThumbnail(item, output);
      if (file != null) {
        if (await _discardSuppressedOutput(cacheKey, output)) {
          return null;
        }
        item.thumbnailError = null;
        _completed++;
        _ffmpegCompleted++;
        _totalGenerateMs += stopwatch.elapsedMilliseconds;
        _memoryCache[cacheKey] = file;
        _pathMemoryCache[item.path] = file;
        return file;
      }
    } catch (error) {
      item.thumbnailError = 'ffmpeg: $error';
    }

    if (await _discardSuppressedOutput(cacheKey, output)) {
      return null;
    }

    if (!allowPlayerFallback) {
      item.thumbnailError ??=
          'ffmpeg: \u672a\u627e\u5230 FFmpeg\uff0c\u540e\u53f0\u6279\u91cf\u7f13\u5b58\u5df2\u8df3\u8fc7\u64ad\u653e\u5668\u515c\u5e95';
      _failed++;
      _totalGenerateMs += stopwatch.elapsedMilliseconds;
      _memoryCache[cacheKey] = null;
      _pathMemoryCache[item.path] = null;
      return null;
    }

    final player = Player(
      configuration: const PlayerConfiguration(bufferSize: 8 * 1024 * 1024),
    );
    final controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        width: 256,
        height: 144,
        hwdec: 'auto-safe',
        enableHardwareAcceleration: true,
      ),
    );

    try {
      await player.setVolume(0);
      await player.open(Media(videoPath), play: true).timeout(
            _thumbnailPlayerTimeout,
          );

      final duration = await player.stream.duration
          .firstWhere((value) => value > Duration.zero)
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => const Duration(seconds: 2),
          );
      final seekTo = duration > const Duration(seconds: 8)
          ? const Duration(seconds: 3)
          : const Duration(milliseconds: 800);

      await player.seek(seekTo).timeout(
            const Duration(seconds: 2),
            onTimeout: () {},
          );
      await controller.platform.future
          .then((platform) => platform.waitUntilFirstFrameRendered)
          .timeout(const Duration(seconds: 3), onTimeout: () {});
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await player.pause();

      final Uint8List? bytes = await player
          .screenshot(format: 'image/jpeg')
          .timeout(const Duration(seconds: 3));
      if (bytes == null || bytes.isEmpty) {
        item.thumbnailError = 'media_kit: \u622a\u56fe\u4e3a\u7a7a';
        _failed++;
        _totalGenerateMs += stopwatch.elapsedMilliseconds;
        _memoryCache[cacheKey] = null;
        _pathMemoryCache[item.path] = null;
        return null;
      }
      if (await _discardSuppressedOutput(cacheKey, output)) {
        return null;
      }
      await output.parent.create(recursive: true);
      final tempOutput = File('${output.path}.tmp.jpg');
      if (await tempOutput.exists()) {
        await tempOutput.delete();
      }
      await tempOutput.writeAsBytes(bytes, flush: true);
      if (await output.exists()) {
        await output.delete();
      }
      await tempOutput.rename(output.path);
      if (await _discardSuppressedOutput(cacheKey, output)) {
        return null;
      }
      item.thumbnailError = null;
      _completed++;
      _fallbackCompleted++;
      _totalGenerateMs += stopwatch.elapsedMilliseconds;
      _memoryCache[cacheKey] = output;
      _pathMemoryCache[item.path] = output;
      return output;
    } catch (error) {
      item.thumbnailError = 'media_kit: $error';
      _failed++;
      _totalGenerateMs += stopwatch.elapsedMilliseconds;
      _memoryCache[cacheKey] = null;
      _pathMemoryCache[item.path] = null;
      return null;
    } finally {
      await player.dispose();
    }
  }

  /** 活动生成被删除操作作废时清理其产物，并消费一次抑制标记。 */
  Future<bool> _discardSuppressedOutput(String cacheKey, File output) async {
    if (!_suppressedActiveCacheKeys.remove(cacheKey)) {
      return false;
    }
    try {
      if (await output.exists()) {
        await output.delete();
      }
      final temporary = File('${output.path}.tmp.jpg');
      if (await temporary.exists()) {
        await temporary.delete();
      }
    } on FileSystemException {
      // 删除竞态只影响已作废缓存文件，不能让生成队列失去推进能力。
    }
    _memoryCache.remove(cacheKey);
    return true;
  }

  Future<CacheStats> statsFor(Iterable<VideoItem> items) async {
    var cached = 0;
    var missing = 0;
    var errors = 0;
    for (final item in items) {
      final file = await thumbnailFor(item);
      if (file != null && await file.exists()) {
        cached++;
      } else {
        missing++;
      }
      if (item.thumbnailError != null) {
        errors++;
      }
    }
    return CacheStats(
      total: cached + missing,
      cached: cached,
      missing: missing,
      errors: errors,
      queued: queuedJobs,
      pendingBackgroundRequests:
          _backgroundRequestsInFlight + _backgroundCandidates.length,
      active: _activeJobs,
      activeBackground: _activeBackgroundJobs,
      maxConcurrent: _maxConcurrentJobs,
      maxBackground: _maxBackgroundJobs,
      maxBackgroundQueued: _maxBackgroundQueuedJobs,
      paused: _isPaused,
      completedThisRun: _completed,
      failedThisRun: _failed,
      ffmpegCompleted: _ffmpegCompleted,
      fallbackCompleted: _fallbackCompleted,
      averageMs: _completed + _failed == 0
          ? 0
          : (_totalGenerateMs / (_completed + _failed)).round(),
    );
  }

  Future<void> retryFailed(Iterable<VideoItem> items) async {
    for (final item in items.where((item) => item.thumbnailError != null)) {
      if (_backgroundCandidates.length + _backgroundRequestsInFlight >=
          _maxBackgroundQueuedJobs) {
        break;
      }
      final cacheKey = await _cacheKeyFor(item);
      if (cacheKey != null) {
        _memoryCache.remove(cacheKey);
      }
      item.thumbnailError = null;
      if (_backgroundCandidatePaths.add(item.path)) {
        _backgroundCandidates.add(item);
      }
    }
    _pumpBackgroundCandidates(allowPlayerFallback: false);
  }

  Future<bool> _isValidThumbnailFile(File file) async {
    try {
      if (!await file.exists()) {
        return false;
      }
      final length = await file.length();
      if (length < 4) {
        await file.delete();
        return false;
      }
      final handle = await file.open();
      try {
        final start = await handle.read(2);
        await handle.setPosition(length - 2);
        final end = await handle.read(2);
        final validJpeg = start.length == 2 &&
            end.length == 2 &&
            start[0] == 0xff &&
            start[1] == 0xd8 &&
            end[0] == 0xff &&
            end[1] == 0xd9;
        if (!validJpeg) {
          await file.delete();
        }
        return validJpeg;
      } finally {
        await handle.close();
      }
    } catch (_) {
      return false;
    }
  }

  Future<String?> _cacheKeyFor(VideoItem item) async {
    final videoPath = item.path;
    final knownSize = item.fileSize;
    final knownModifiedMs = item.modifiedMs;
    if (knownSize != null && knownModifiedMs != null) {
      // 扫描阶段已经持久化文件快照时直接复用，避免列表滚动反复访问原视频。
      return _stableKey('$videoPath|$knownSize|$knownModifiedMs');
    }
    final file = File(videoPath);
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        return null;
      }
      item.fileSize = stat.size;
      item.modifiedMs = stat.modified.millisecondsSinceEpoch;
      final fingerprint = '$videoPath|${item.fileSize}|${item.modifiedMs}';
      return _stableKey(fingerprint);
    } catch (_) {
      return null;
    }
  }

  String _stableKey(String value) {
    var hash = 0xcbf29ce484222325;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
