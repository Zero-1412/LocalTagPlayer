import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:local_tag_player/src/models/external_media_tools_state.dart';
import 'package:local_tag_player/src/models/media_details.dart';
import 'package:local_tag_player/src/models/video_item.dart';
import 'package:local_tag_player/src/platform/platform_interfaces.dart';
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

  test('allows a partial visual signature instead of requiring every sample',
      () {
    final source = File(
      'lib/src/services/library/video_content_similarity_service.dart',
    ).readAsStringSync();

    expect(
        source, contains('final result = hashes.length < 2 ? null : hashes;'));
    expect(
        source,
        contains(
            'final cachedFrame = await _thumbnailService.thumbnailFor(item);'));
    expect(source, isNot(contains('ensureThumbnailFor(item)')));
  });

  test('builds candidates asynchronously so dense libraries can yield', () {
    final source = File(
      'lib/src/services/library/video_content_similarity_service.dart',
    ).readAsStringSync();

    expect(source, contains('final candidates = await _buildCandidates('));
    expect(
        source, contains('Future<List<_VisualCandidate>?> _buildCandidates('));
    expect(source, contains('await Future<void>.delayed(Duration.zero);'));
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
