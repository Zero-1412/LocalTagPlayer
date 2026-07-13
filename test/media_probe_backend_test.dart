import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';

// ignore_for_file: slash_for_doc_comments

/** 用于确认媒体详情服务只传数据库已有元数据且会取消旧 generation。 */
class _RecordingProbeBackend implements MediaProbeBackend {
  final List<MediaProbeRequest> requests = <MediaProbeRequest>[];
  final List<int> cancelled = <int>[];

  @override
  Future<void> cancelGeneration(int generationId) async {
    cancelled.add(generationId);
  }

  @override
  Future<List<MediaProbeResult>> probeBatch({
    required int generationId,
    required List<MediaProbeRequest> requests,
  }) async {
    this.requests.addAll(requests);
    return requests
        .map((request) => MediaProbeResult(
              videoId: request.videoId,
              details: const MediaDetails(
                videoCodec: 'h264',
                audioCodec: 'aac',
                width: 1920,
                height: 1080,
              ),
            ))
        .toList(growable: false);
  }
}

void main() {
  test('media details reuses indexed metadata and cancels its generation',
      () async {
    final backend = _RecordingProbeBackend();
    final item = VideoItem(
      videoId: 'stable-video-id',
      path: r'Z:\does-not-need-to-exist\clip.mp4',
      title: 'clip',
      folder: r'Z:\does-not-need-to-exist',
      tags: const <String>{},
      fileSize: 987654321,
      modifiedMs: 123456789,
      mediaFingerprint: 'v2:987654321:abc',
      addedAt: DateTime.utc(2026, 7, 13),
    );
    final service = MediaDetailsService(probeBackend: backend);

    final details = await service.detailsFor(item);
    service.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(details.resolution, '1920x1080');
    expect(backend.requests.single.videoId, 'stable-video-id');
    expect(backend.requests.single.knownSize, 987654321);
    expect(backend.requests.single.knownModifiedAt, 123456789);
    expect(backend.cancelled, hasLength(1));
    expect(backend.cancelled.single, greaterThan(0));
  });

  test('playback preflight refreshes an incomplete cached detail', () async {
    final backend = _RecordingProbeBackend();
    final item = VideoItem(
      videoId: 'incomplete-video-id',
      path: r'Z:\does-not-need-to-exist\incomplete.mp4',
      title: 'incomplete',
      folder: r'Z:\does-not-need-to-exist',
      tags: const <String>{},
      mediaDetails: const MediaDetails(videoCodec: 'h264'),
      addedAt: DateTime.utc(2026, 7, 14),
    );
    final service = MediaDetailsService(probeBackend: backend);

    final cached = await service.detailsFor(item);
    expect(cached.width, isNull);
    expect(backend.requests, isEmpty);

    final refreshed = await service.detailsFor(item, refreshIncomplete: true);
    service.dispose();

    expect(refreshed.resolution, '1920x1080');
    expect(backend.requests.single.videoId, 'incomplete-video-id');
  });
}
