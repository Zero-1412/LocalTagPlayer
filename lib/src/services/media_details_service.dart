part of '../../main.dart';

class MediaDetailsService {
  MediaDetailsService({this.onUpdated});

  final Future<void> Function(VideoItem item, MediaDetails details, String? fingerprint)? onUpdated;
  final Map<String, Future<MediaDetails>> _inFlight = {};
  final Map<String, MediaDetails> _cache = {};
  final Set<String> _queuedPaths = {};
  var _activeReads = 0;
  var _completedThisRun = 0;
  var _failedThisRun = 0;
  Future<void> _queue = Future<void>.value();

  int get queuedReads => _queuedPaths.length;
  int get activeReads => _activeReads;
  int get completedThisRun => _completedThisRun;
  int get failedThisRun => _failedThisRun;

  Future<MediaDetails> detailsFor(VideoItem item) {
    final cached = _cache[item.path] ?? item.mediaDetails;
    if (cached != null) {
      _cache[item.path] = cached;
      return Future.value(cached);
    }

    return _inFlight.putIfAbsent(item.path, () {
      _queuedPaths.add(item.path);
      final task = _queue.then((_) async {
        _queuedPaths.remove(item.path);
        _activeReads++;
        try {
          final details = await _read(item);
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

  Future<MediaDetails> _read(VideoItem item) async {
    final path = item.path;
    final fingerprint = await LibraryStore.mediaFingerprintFor(path);
    try {
      final details = await ExternalMediaTools.probe(item);
      if (details != null) {
        item.mediaDetailsError = null;
        _cache[path] = details;
        await onUpdated?.call(item, details, fingerprint);
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
      final widthFuture = player.stream.width.firstWhere((value) => value != null).timeout(
            const Duration(seconds: 4),
            onTimeout: () => player.state.width,
          );
      final heightFuture = player.stream.height.firstWhere((value) => value != null).timeout(
            const Duration(seconds: 4),
            onTimeout: () => player.state.height,
          );
      final tracksFuture = player.stream.tracks.firstWhere((tracks) {
        return tracks.video.any(_isRealVideoTrack) || tracks.audio.any(_isRealAudioTrack);
      }).timeout(
        const Duration(seconds: 4),
        onTimeout: () => player.state.tracks,
      );

      final width = await widthFuture;
      final height = await heightFuture;
      final tracks = await tracksFuture;
      final videoCodec = tracks.video.where(_isRealVideoTrack).firstOrNull?.codec;
      final audioCodec = tracks.audio.where(_isRealAudioTrack).firstOrNull?.codec;
      final details = MediaDetails(
        videoCodec: videoCodec,
        audioCodec: audioCodec,
        width: width,
        height: height,
      );
      item.mediaDetailsError = null;
      _cache[path] = details;
      await onUpdated?.call(item, details, fingerprint);
      return details;
    } catch (error) {
      const details = MediaDetails();
      item.mediaDetailsError = 'media_kit: $error';
      _cache[path] = details;
      await onUpdated?.call(item, details, fingerprint);
      return details;
    } finally {
      await player.dispose();
    }
  }

  bool _isRealVideoTrack(VideoTrack track) => track.id != 'auto' && track.id != 'no';
  bool _isRealAudioTrack(AudioTrack track) => track.id != 'auto' && track.id != 'no';
}


