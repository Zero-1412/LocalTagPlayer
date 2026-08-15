import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:local_tag_player/src/models/external_media_tools_state.dart';
import 'package:local_tag_player/src/models/media_details.dart';
import 'package:local_tag_player/src/models/video_item.dart';
import 'package:local_tag_player/src/platform/platform_interfaces.dart';
import 'package:local_tag_player/src/services/media/thumbnail_service.dart';

void main() {
  test('相似视频前台取帧使用有界并发，离开前台降为单并发', () async {
    final directory =
        await Directory.systemTemp.createTemp('ltp_similarity_queue_');
    addTearDown(() => directory.delete(recursive: true));
    final backend = _ConcurrentPreviewBackend();
    final service = ThumbnailService.forDirectory(directory, backend)
      ..setSimilarityScanForeground(true);
    final item = _video(directory.path);

    await Future.wait<File?>([
      for (var index = 0; index < 4; index++)
        service.similarityPreviewFrameFor(
          item,
          Duration(seconds: index + 1),
        ),
    ]);
    expect(backend.calls, 4);
    // 服务按 CPU 核数取 2–4 路，测试环境至少应证明没有退化成旧的单串行队列。
    expect(backend.maxActive, greaterThanOrEqualTo(2));

    backend.reset();
    service.setSimilarityScanForeground(false);
    await Future.wait<File?>([
      for (var index = 0; index < 3; index++)
        service.similarityPreviewFrameFor(
          item,
          Duration(seconds: index + 10),
        ),
    ]);
    expect(backend.calls, 3);
    expect(backend.maxActive, 1);
  });

  test('播放暂停时不启动相似视频取帧，恢复后继续队列', () async {
    final directory =
        await Directory.systemTemp.createTemp('ltp_similarity_pause_');
    addTearDown(() => directory.delete(recursive: true));
    final backend = _ConcurrentPreviewBackend();
    final service = ThumbnailService.forDirectory(directory, backend)
      ..setSimilarityScanForeground(true)
      ..pause(allowPriorityRequests: true);
    final pending = service.similarityPreviewFrameFor(
      _video(directory.path),
      const Duration(seconds: 30),
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(backend.calls, 0);
    service.resume();
    expect(await pending, isNotNull);
    expect(backend.calls, 1);
  });

  test('相似取帧队列在视频之间轮转，避免单视频时间点占满尾部', () async {
    final directory =
        await Directory.systemTemp.createTemp('ltp_similarity_fair_');
    addTearDown(() => directory.delete(recursive: true));
    final backend = _ConcurrentPreviewBackend();
    final service = ThumbnailService.forDirectory(directory, backend)..pause();
    final first = _video(directory.path, id: 'similarity-a');
    final second = _video(directory.path, id: 'similarity-b');
    final pending = <Future<File?>>[
      for (var index = 0; index < 3; index++)
        service.similarityPreviewFrameFor(
          first,
          Duration(seconds: index + 1),
        ),
      for (var index = 0; index < 3; index++)
        service.similarityPreviewFrameFor(
          second,
          Duration(seconds: index + 10),
        ),
    ];

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(backend.calls, 0);
    service.resume();
    await Future.wait(pending);

    expect(
      backend.videoIds.take(4),
      <String>['similarity-a', 'similarity-b', 'similarity-a', 'similarity-b'],
    );
  });

  test('相似复核消费字节快照，不受临时帧 LRU 清理影响', () async {
    final directory =
        await Directory.systemTemp.createTemp('ltp_similarity_bytes_');
    addTearDown(() => directory.delete(recursive: true));
    final backend = _ConcurrentPreviewBackend();
    final service = ThumbnailService.forDirectory(directory, backend)
      ..setSimilarityScanForeground(true);
    final item = _video(directory.path, id: 'similarity-bytes');

    final frames = await Future.wait<Uint8List?>([
      for (var index = 0; index < 32; index++)
        service.similarityPreviewBytesFor(
          item,
          Duration(seconds: index + 1),
        ),
    ]);
    // 超过 24 项后会触发预览 LRU；调用方仍应拿到已读取的内容快照，
    // 而不是在消费临时 File 路径时收到 PathNotFoundException。
    expect(frames.whereType<Uint8List>(), hasLength(32));
  });
}

VideoItem _video(String directory, {String id = 'similarity-queue'}) {
  return VideoItem(
    videoId: id,
    path: '$directory/$id.mp4',
    title: id,
    folder: directory,
    tags: <String>{},
    addedAt: DateTime(2024),
    fileSize: 100,
    modifiedMs: 1,
    mediaDetails: const MediaDetails(
      width: 1920,
      height: 1080,
      duration: Duration(seconds: 90),
    ),
    playbackDuration: const Duration(seconds: 90),
  );
}

class _ConcurrentPreviewBackend implements FFmpegBackend {
  int active = 0;
  int maxActive = 0;
  int calls = 0;
  final List<String> videoIds = <String>[];

  void reset() {
    active = 0;
    maxActive = 0;
    calls = 0;
    videoIds.clear();
  }

  @override
  Future<ExternalMediaToolsState> locateTools() async =>
      const ExternalMediaToolsState();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> version() async => 'test';

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
  }) async {
    active++;
    calls++;
    videoIds.add(item.videoId);
    if (active > maxActive) {
      maxActive = active;
    }
    try {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await output.writeAsBytes(const <int>[0xff, 0xd8, 0xff, 0xd9]);
      return output;
    } finally {
      active--;
    }
  }

  @override
  Future<MediaDetails?> probe(VideoItem item) async => null;
}
