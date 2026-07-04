part of '../../main.dart';

class _ThumbnailJob {
  const _ThumbnailJob({
    required this.cacheKey,
    required this.run,
    required this.isBackground,
  });

  final String cacheKey;
  final Future<void> Function() run;
  final bool isBackground;
}

class ThumbnailService {
  ThumbnailService._(this._directory);
  static const _maxBackgroundQueuedJobs = 500;

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
  final Set<String> _activeCacheKeys = {};
  final Set<String> _backgroundQueued = {};
  final Set<String> _priorityQueued = {};
  final Queue<_ThumbnailJob> _priorityJobs = Queue();
  final Queue<_ThumbnailJob> _backgroundJobs = Queue();
  var _activeJobs = 0;
  var _activeBackgroundJobs = 0;
  var _completed = 0;
  var _failed = 0;
  var _ffmpegCompleted = 0;
  var _fallbackCompleted = 0;
  var _totalGenerateMs = 0;
  var _isPaused = false;

  bool get isPaused => _isPaused;
  int get activeJobs => _activeJobs;
  int get queuedJobs => _priorityQueued.length + _backgroundQueued.length;
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
  }

  static Future<ThumbnailService> create() async {
    final directory = await AppPaths.thumbnailDirectory();
    return ThumbnailService._(directory);
  }

  Future<File?> thumbnailFor(VideoItem item) async {
    final cacheKey = await _cacheKeyFor(item.path);
    if (cacheKey == null) {
      return null;
    }
    if (_memoryCache.containsKey(cacheKey)) {
      final cached = _memoryCache[cacheKey];
      if (cached == null) {
        return null;
      }
      if (await _isValidThumbnailFile(cached)) {
        return cached;
      }
      _memoryCache.remove(cacheKey);
      return null;
    }

    final file = File(p.join(_directory.path, '$cacheKey.jpg'));
    if (await _isValidThumbnailFile(file)) {
      _memoryCache[cacheKey] = file;
      return file;
    }

    return null;
  }

  void prefetchAll(Iterable<VideoItem> items, {bool allowPlayerFallback = false}) {
    for (final item in items) {
      unawaited(_queuePrefetch(item, allowPlayerFallback: allowPlayerFallback));
      if (_backgroundQueued.length >= _maxBackgroundQueuedJobs) {
        break;
      }
    }
  }

  void prefetchVisible(Iterable<VideoItem> items) {
    for (final item in items) {
      unawaited(_queuePrefetch(item, priority: true, allowPlayerFallback: true));
    }
  }

  Future<void> _queuePrefetch(
    VideoItem item, {
    bool priority = false,
    bool allowPlayerFallback = false,
  }) async {
    final cacheKey = await _cacheKeyFor(item.path);
    if (cacheKey == null) {
      return;
    }
    final file = File(p.join(_directory.path, '$cacheKey.jpg'));
    if (_memoryCache.containsKey(cacheKey)) {
      final cached = _memoryCache[cacheKey];
      if (cached == null || await _isValidThumbnailFile(cached)) {
        return;
      }
      _memoryCache.remove(cacheKey);
    }
    if (await _isValidThumbnailFile(file)) {
      _memoryCache[cacheKey] = file;
      return;
    }
    if (_activeCacheKeys.contains(cacheKey)) {
      return;
    }

    if (priority) {
      if (_priorityQueued.contains(cacheKey)) {
        return;
      }
      if (_backgroundQueued.remove(cacheKey)) {
        _backgroundJobs.removeWhere((job) => job.cacheKey == cacheKey);
      }
      _priorityQueued.add(cacheKey);
      _priorityJobs.add(
        _ThumbnailJob(
          cacheKey: cacheKey,
          isBackground: false,
          run: () async {
            try {
              await _generate(item, file, cacheKey, allowPlayerFallback);
            } finally {
              _priorityQueued.remove(cacheKey);
            }
          },
        ),
      );
    } else {
      if (_backgroundQueued.length >= _maxBackgroundQueuedJobs) {
        return;
      }
      if (_backgroundQueued.contains(cacheKey) || _priorityQueued.contains(cacheKey)) {
        return;
      }
      _backgroundQueued.add(cacheKey);
      _backgroundJobs.add(
        _ThumbnailJob(
          cacheKey: cacheKey,
          isBackground: true,
          run: () async {
            try {
              await _generate(item, file, cacheKey, allowPlayerFallback);
            } finally {
              _backgroundQueued.remove(cacheKey);
            }
          },
        ),
      );
    }
    _drainQueue();
  }

  void _drainQueue() {
    if (_isPaused) {
      return;
    }
    while (_activeJobs < _maxConcurrentJobs && (_priorityJobs.isNotEmpty || _backgroundJobs.isNotEmpty)) {
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
        job.run().whenComplete(() {
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

  _ThumbnailJob? _nextJob() {
    if (_priorityJobs.isNotEmpty) {
      return _priorityJobs.removeFirst();
    }
    if (_backgroundJobs.isNotEmpty && _activeBackgroundJobs < _maxBackgroundJobs) {
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
      return null;
    }

    try {
      final file = await ExternalMediaTools.createThumbnail(item, output);
      if (file != null) {
        item.thumbnailError = null;
        _completed++;
        _ffmpegCompleted++;
        _totalGenerateMs += stopwatch.elapsedMilliseconds;
        _memoryCache[cacheKey] = file;
        return file;
      }
    } catch (error) {
      item.thumbnailError = 'ffmpeg: $error';
    }

    if (!allowPlayerFallback) {
      item.thumbnailError ??= 'ffmpeg: \u672a\u627e\u5230 FFmpeg\uff0c\u540e\u53f0\u6279\u91cf\u7f13\u5b58\u5df2\u8df3\u8fc7\u64ad\u653e\u5668\u515c\u5e95';
      _failed++;
      _totalGenerateMs += stopwatch.elapsedMilliseconds;
      _memoryCache[cacheKey] = null;
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
      item.thumbnailError = null;
      _completed++;
      _fallbackCompleted++;
      _totalGenerateMs += stopwatch.elapsedMilliseconds;
      _memoryCache[cacheKey] = output;
      return output;
    } catch (error) {
      item.thumbnailError = 'media_kit: $error';
      _failed++;
      _totalGenerateMs += stopwatch.elapsedMilliseconds;
      _memoryCache[cacheKey] = null;
      return null;
    } finally {
      await player.dispose();
    }
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
      queued: _priorityQueued.length + _backgroundQueued.length,
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
      averageMs: _completed + _failed == 0 ? 0 : (_totalGenerateMs / (_completed + _failed)).round(),
    );
  }

  Future<void> retryFailed(Iterable<VideoItem> items) async {
    for (final item in items.where((item) => item.thumbnailError != null)) {
      final cacheKey = await _cacheKeyFor(item.path);
      if (cacheKey != null) {
        _memoryCache.remove(cacheKey);
      }
      item.thumbnailError = null;
      await _queuePrefetch(item);
      if (_backgroundQueued.length >= _maxBackgroundQueuedJobs) {
        break;
      }
    }
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

  Future<String?> _cacheKeyFor(String videoPath) async {
    final file = File(videoPath);
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        return null;
      }
      final fingerprint = '$videoPath|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
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






