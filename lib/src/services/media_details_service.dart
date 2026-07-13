part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

class MediaDetailsService {
  MediaDetailsService({this.onUpdated});

  final Future<void> Function(
      VideoItem item, MediaDetails details, String? fingerprint)? onUpdated;
  final Map<String, Future<MediaDetails>> _inFlight = {};
  final Map<String, MediaDetails> _cache = {};
  final Set<String> _queuedPaths = {};
  var _activeReads = 0;
  var _completedThisRun = 0;
  var _failedThisRun = 0;
  Future<void> _queue = Future<void>.value();
  var _generation = 0;
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
      return task.whenComplete(() => _inFlight.remove(item.path));
    });
  }

  /**
   * 读取单条媒体详情；[generation] 用于阻止旧播放器任务回写新页面状态。
   */
  Future<MediaDetails> _read(VideoItem item, int generation) async {
    final path = item.path;
    final fingerprint = await LibraryStore.mediaFingerprintFor(path);
    try {
      final details = await ExternalMediaTools.probe(item);
      if (details != null) {
        item.mediaDetailsError = null;
        _cache[path] = details;
        await _notifyUpdated(item, details, fingerprint, generation);
        return details;
      }
    } catch (error) {
      item.mediaDetailsError = 'ffprobe: $error';
    }

    final player = Player(
      configuration: const PlayerConfiguration(bufferSize: 4 * 1024 * 1024),
    );
    try {
      await player.open(Media(path), play: false).timeout(
            const Duration(seconds: 8),
          );
      final widthFuture =
          player.stream.width.firstWhere((value) => value != null).timeout(
                const Duration(seconds: 4),
                onTimeout: () => player.state.width,
              );
      final heightFuture =
          player.stream.height.firstWhere((value) => value != null).timeout(
                const Duration(seconds: 4),
                onTimeout: () => player.state.height,
              );
      final tracksFuture = player.stream.tracks.firstWhere((tracks) {
        return tracks.video.any(_isRealVideoTrack) ||
            tracks.audio.any(_isRealAudioTrack);
      }).timeout(
        const Duration(seconds: 4),
        onTimeout: () => player.state.tracks,
      );

      final width = await widthFuture;
      final height = await heightFuture;
      final tracks = await tracksFuture;
      final videoCodec =
          tracks.video.where(_isRealVideoTrack).firstOrNull?.codec;
      final audioCodec =
          tracks.audio.where(_isRealAudioTrack).firstOrNull?.codec;
      final details = MediaDetails(
        videoCodec: videoCodec,
        audioCodec: audioCodec,
        width: width,
        height: height,
      );
      item.mediaDetailsError = null;
      _cache[path] = details;
      await _notifyUpdated(item, details, fingerprint, generation);
      return details;
    } catch (error) {
      const details = MediaDetails();
      item.mediaDetailsError = 'media_kit: $error';
      _cache[path] = details;
      await _notifyUpdated(item, details, fingerprint, generation);
      return details;
    } finally {
      await player.dispose();
    }
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
    _generation++;
    _queuedPaths.clear();
    _inFlight.clear();
    _cache.clear();
  }

  bool _isRealVideoTrack(VideoTrack track) =>
      track.id != 'auto' && track.id != 'no';
  bool _isRealAudioTrack(AudioTrack track) =>
      track.id != 'auto' && track.id != 'no';
}
