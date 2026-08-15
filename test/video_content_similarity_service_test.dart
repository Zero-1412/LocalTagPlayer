import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:local_tag_player/src/models/external_media_tools_state.dart';
import 'package:local_tag_player/src/models/media_details.dart';
import 'package:local_tag_player/src/models/video_item.dart';
import 'package:local_tag_player/src/models/video_visual_signature.dart';
import 'package:local_tag_player/src/platform/platform_interfaces.dart';
import 'package:local_tag_player/src/repositories/repository_interfaces.dart';
import 'package:local_tag_player/src/services/library/video_content_similarity_service.dart';
import 'package:local_tag_player/src/services/media/thumbnail_service.dart';

void main() {
  test('distributes candidate pairs across duration-dense videos', () async {
    final thumbnailService = ThumbnailService.forDirectory(
      Directory.systemTemp,
      _NoopFFmpegBackend(),
    );
    final videos = <VideoItem>[
      for (var index = 0; index < 60; index++)
        _video(
          'dense-$index',
          Duration(seconds: 120 + (index % 2)),
        ),
    ];

    final result = await VideoContentSimilarityService(thumbnailService)
        .findNearDuplicateGroups(videos, maxCandidatePairs: 200);

    // 旧实现会在第一个左端视频上直接消耗全局上限 48；新实现按每个视频
    // 交错邻居，能覆盖完整时长密集区而不是只覆盖开头少量记录。
    expect(result.candidatePairCount, greaterThan(48));
    expect(result.candidatePairCount, lessThanOrEqualTo(200));
  });

  test('uses the last playback duration when media details are absent',
      () async {
    final thumbnailService = ThumbnailService.forDirectory(
      Directory.systemTemp,
      _NoopFFmpegBackend(),
    );
    final first = _video('first', const Duration(seconds: 90));
    final second = _video('second', const Duration(seconds: 90));
    first.mediaDetails = null;
    second.mediaDetails = null;

    final result = await VideoContentSimilarityService(thumbnailService)
        .findNearDuplicateGroups([first, second], maxCandidatePairs: 4);

    expect(result.candidatePairCount, 1);
  });

  test('keeps candidates with moderate duration drift for visual review',
      () async {
    final thumbnailService = ThumbnailService.forDirectory(
      Directory.systemTemp,
      _NoopFFmpegBackend(),
    );
    final first = _video('first-drift', const Duration(seconds: 100));
    final second = _video('second-drift', const Duration(seconds: 111));

    final result = await VideoContentSimilarityService(thumbnailService)
        .findNearDuplicateGroups([first, second], maxCandidatePairs: 4);

    // 旧 6% 窗口会把 11% 的片头/片尾差异直接排除；视觉候选必须先进入
    // 多帧复核，不能在元数据预筛阶段静默丢失。
    expect(result.candidatePairCount, 1);
  });

  test('uses normalized title lane when duration metadata is missing',
      () async {
    final thumbnailService = ThumbnailService.forDirectory(
      Directory.systemTemp,
      _NoopFFmpegBackend(),
    );
    final first = _video('1671374536_1080p', const Duration(seconds: 90));
    final second =
        _video('1671374536_1080p_Source', const Duration(seconds: 90));
    first
      ..mediaDetails = null
      ..playbackDuration = Duration.zero;
    second
      ..mediaDetails = null
      ..playbackDuration = Duration.zero;

    final result = await VideoContentSimilarityService(thumbnailService)
        .findNearDuplicateGroups([first, second], maxCandidatePairs: 4);

    expect(result.candidatePairCount, 1);
  });

  test('keeps Japanese title tokens in the normalized lane', () async {
    final thumbnailService = ThumbnailService.forDirectory(
      Directory.systemTemp,
      _NoopFFmpegBackend(),
    );
    final japanese = _video('魔法少女えれな', const Duration(seconds: 90));
    final sourceCopy = _video('魔法少女えれな_Source', const Duration(seconds: 90));

    final result = await VideoContentSimilarityService(thumbnailService)
        .findNearDuplicateGroups([japanese, sourceCopy], maxCandidatePairs: 4);

    expect(result.candidatePairCount, 1);
  });

  test('keeps a nearby crop or letterbox candidate despite aspect-ratio drift',
      () async {
    final thumbnailService = ThumbnailService.forDirectory(
      Directory.systemTemp,
      _NoopFFmpegBackend(),
    );
    final first = _video('shape-a', const Duration(seconds: 90));
    final second = _video('shape-b', const Duration(seconds: 90));
    second.mediaDetails = const MediaDetails(
      width: 1440,
      height: 1080,
      duration: Duration(seconds: 90),
    );

    final result = await VideoContentSimilarityService(thumbnailService)
        .findNearDuplicateGroups([first, second], maxCandidatePairs: 4);

    expect(result.candidatePairCount, 1);
  });

  test('cancellation returns a non-applicable result without groups', () async {
    final thumbnailService = ThumbnailService.forDirectory(
      Directory.systemTemp,
      _NoopFFmpegBackend(),
    );
    final result = await VideoContentSimilarityService(thumbnailService)
        .findNearDuplicateGroups(
      [_video('cancelled', const Duration(seconds: 90))],
      isCancelled: () => true,
    );

    expect(result.cancelled, isTrue);
    expect(result.groups, isEmpty);
  });

  test('reuses a valid persisted visual signature before starting deep frames',
      () async {
    final thumbnailService = ThumbnailService.forDirectory(
      Directory.systemTemp,
      _NoopFFmpegBackend(),
    );
    final first = _video('persisted-a', const Duration(seconds: 90));
    final second = _video('persisted-b', const Duration(seconds: 90));
    final cache =
        _FakeVisualSignatureCache(<String, VideoVisualSignatureCacheEntry>{
      first.videoId: _signature(first),
      second.videoId: _signature(second),
    });
    final stale = _signature(first);
    first.modifiedMs = 2;
    expect(stale.matches(first), isFalse);
    first.modifiedMs = 1;

    final result = await VideoContentSimilarityService(
      thumbnailService,
      visualSignatureCache: cache,
    ).findNearDuplicateGroups([first, second], maxCandidatePairs: 4);

    expect(result.groups, hasLength(1));
    expect(cache.bulkLoadCalls, 1);
    expect(
        cache.loadCalls, containsAll(<String>[first.videoId, second.videoId]));
    expect(cache.saved, isEmpty);
  });

  test(
      'does not let shared opening and closing frames create a duplicate group',
      () async {
    final thumbnailService = ThumbnailService.forDirectory(
      Directory.systemTemp,
      _NoopFFmpegBackend(),
    );
    final first = _video('single-frame-a', const Duration(seconds: 90));
    final second = _video('single-frame-b', const Duration(seconds: 90));
    final cache = _FakeVisualSignatureCache(
      <String, VideoVisualSignatureCacheEntry>{
        first.videoId: _signatureWithHashes(
          first,
          const <int>[0, 1, 2, 3],
        ),
        // 首帧和末尾模板相同，但三个主体采样点不同；边缘模板不能把同作者
        // 的不同作品压成 100% 视觉重复。
        second.videoId: _signatureWithHashes(
          second,
          <int>[0, 0xffffffffffffffff, 0xffffffffffffffff, 3],
        ),
      },
    );

    final result = await VideoContentSimilarityService(
      thumbnailService,
      visualSignatureCache: cache,
    ).findNearDuplicateGroups([first, second], maxCandidatePairs: 4);

    expect(result.groups, isEmpty);
  });

  test('reports candidate-building and frame-comparison phases', () async {
    final thumbnailService = ThumbnailService.forDirectory(
      Directory.systemTemp,
      _NoopFFmpegBackend(),
    );
    final progress = <VideoVisualScanProgress>[];

    await VideoContentSimilarityService(thumbnailService)
        .findNearDuplicateGroups(
      [
        for (var index = 0; index < 20; index++)
          _video('progress-$index', const Duration(seconds: 90)),
      ],
      maxCandidatePairs: 64,
      onProgress: progress.add,
    );

    expect(
      progress.any(
        (item) => item.phase == VideoVisualScanPhase.buildingCandidates,
      ),
      isTrue,
    );
    expect(
      progress.any(
        (item) => item.phase == VideoVisualScanPhase.comparingCandidates,
      ),
      isTrue,
    );
    expect(
      progress.any(
        (item) => item.phase == VideoVisualScanPhase.extractingSignatures,
      ),
      isTrue,
    );
    final extractionProgress = progress
        .where(
            (item) => item.phase == VideoVisualScanPhase.extractingSignatures)
        .toList(growable: false);
    expect(extractionProgress.first.processed, 0);
    expect(extractionProgress.last.processed, extractionProgress.last.total);
    expect(extractionProgress.last.total, lessThanOrEqualTo(64));
    expect(progress.last.processed, progress.last.total);
    expect(progress.every((item) => item.elapsed >= Duration.zero), isTrue);
    expect(progress.any((item) => item.elapsed > Duration.zero), isTrue);

    final source = File(
      'lib/src/services/library/video_content_similarity_service.dart',
    ).readAsStringSync();
    expect(source,
        contains('final workerCount = _visualComparisonWorkerCount();'));
    expect(source,
        contains('final signatureTasks = <String, Future<List<int>?>>{}'));
    expect(source, contains('Future.wait<int?>('));
    expect(source, contains('estimatedRemaining: remaining'));
  });

  test('extracts each deep video once instead of batching candidate pairs',
      () async {
    final thumbnailService = ThumbnailService.forDirectory(
      Directory.systemTemp,
      _NoopFFmpegBackend(),
    );
    final progress = <VideoVisualScanProgress>[];
    final videos = <VideoItem>[
      for (var index = 0; index < 4; index++)
        _video('unique-deep-$index', const Duration(seconds: 90)),
    ];

    final result = await VideoContentSimilarityService(thumbnailService)
        .findNearDuplicateGroups(
      videos,
      maxCandidatePairs: 16,
      onProgress: progress.add,
    );

    final extractionProgress = progress
        .where(
          (item) => item.phase == VideoVisualScanPhase.extractingSignatures,
        )
        .toList(growable: false);
    expect(result.candidatePairCount, greaterThan(4));
    expect(extractionProgress.last.total, lessThan(result.candidatePairCount));
    expect(extractionProgress.last.total, videos.length);
    expect(extractionProgress.last.processed, videos.length);
  });

  test('allows a partial visual signature instead of requiring every sample',
      () {
    final source = File(
      'lib/src/services/library/video_content_similarity_service.dart',
    ).readAsStringSync();

    expect(
        source, contains('final result = hashes.length < 3 ? null : hashes;'));
    expect(
        source,
        contains(
            'final cachedFrame = await _thumbnailService.thumbnailFor(item);'));
    expect(source, isNot(contains('ensureThumbnailFor(item)')));
    expect(source, contains('similarityPreviewFrameFor(item, position)'));
    expect(source, contains('Future.wait<File?>'));
    expect(source, contains('onSignatureReady: enqueueSignatureWrite'));
    expect(source, contains('_compareDeepWorkEstimate'));
  });

  test('builds candidates asynchronously so dense libraries can yield', () {
    final source = File(
      'lib/src/services/library/video_content_similarity_service.dart',
    ).readAsStringSync();

    expect(source, contains('final candidates = await _buildCandidates('));
    expect(
        source, contains('Future<List<_VisualCandidate>?> _buildCandidates('));
    expect(source, contains('await Future<void>.delayed(Duration.zero);'));
    expect(source, contains('bool Function()? shouldYield'));
    expect(source, contains('_waitForScheduler(isCancelled, shouldYield)'));
  });
}

VideoItem _video(String title, Duration duration) {
  return VideoItem(
    videoId: title,
    path: '/not-a-real-video/$title.mp4',
    title: title,
    folder: '/not-a-real-video',
    tags: <String>{},
    addedAt: DateTime(2024),
    fileSize: 1000000,
    modifiedMs: 1,
    mediaDetails: MediaDetails(
      width: 1920,
      height: 1080,
      duration: duration,
    ),
    playbackDuration: duration,
  );
}

VideoVisualSignatureCacheEntry _signature(VideoItem item) {
  return _signatureWithHashes(item, const <int>[0, 0, 0]);
}

VideoVisualSignatureCacheEntry _signatureWithHashes(
  VideoItem item,
  List<int> hashes,
) {
  return VideoVisualSignatureCacheEntry(
    videoId: item.videoId,
    algorithm: videoVisualSignatureAlgorithm,
    hashes: hashes,
    fileSize: item.fileSize,
    modifiedMs: item.modifiedMs,
  );
}

class _FakeVisualSignatureCache implements VisualSignatureCacheRepository {
  _FakeVisualSignatureCache(this.entries);

  final Map<String, VideoVisualSignatureCacheEntry> entries;
  final List<String> loadCalls = <String>[];
  final List<VideoVisualSignatureCacheEntry> saved =
      <VideoVisualSignatureCacheEntry>[];
  var bulkLoadCalls = 0;

  @override
  Future<VideoVisualSignatureCacheEntry?> loadVisualSignature(
    String videoId,
  ) async {
    loadCalls.add(videoId);
    return entries[videoId];
  }

  @override
  Future<Map<String, VideoVisualSignatureCacheEntry>> loadVisualSignatures(
    Iterable<String> videoIds,
  ) async {
    bulkLoadCalls++;
    final ids = videoIds.toList(growable: false);
    loadCalls.addAll(ids);
    return <String, VideoVisualSignatureCacheEntry>{
      for (final id in ids)
        if (entries[id] != null) id: entries[id]!,
    };
  }

  @override
  Future<void> saveVisualSignature(VideoVisualSignatureCacheEntry entry) async {
    saved.add(entry);
    entries[entry.videoId] = entry;
  }
}

class _NoopFFmpegBackend implements FFmpegBackend {
  @override
  Future<ExternalMediaToolsState> locateTools() async =>
      const ExternalMediaToolsState();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<String?> version() async => null;

  @override
  Future<File?> createThumbnail({
    required VideoItem item,
    required File output,
    bool allowFallback = true,
  }) async =>
      null;

  @override
  Future<File?> createFramePreview({
    required VideoItem item,
    required File output,
    required Duration position,
  }) async =>
      null;

  @override
  Future<MediaDetails?> probe(VideoItem item) async => null;
}
