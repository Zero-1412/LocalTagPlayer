import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/models/external_media_tools_state.dart';
import 'package:local_tag_player/src/models/media_details.dart';
import 'package:local_tag_player/src/models/video_item.dart';
import 'package:local_tag_player/src/platform/platform_interfaces.dart';
import 'package:local_tag_player/src/services/media/thumbnail_service.dart';

void main() {
  test('后台生产源超过 500 项时按窗口继续推进而不截断', () async {
    final directory =
        await Directory.systemTemp.createTemp('ltp_thumbnail_backfill_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}source.mp4');
    await source.writeAsBytes(const <int>[1, 2, 3]);
    final backend = _BackgroundQueueBackend();
    final service = ThumbnailService.forDirectory(directory, backend);
    final items = <VideoItem>[
      for (var index = 0; index < 501; index++)
        VideoItem(
          videoId: 'backfill-$index',
          path: source.path,
          title: 'backfill-$index',
          folder: directory.path,
          tags: <String>{},
          addedAt: DateTime(2026),
          mediaFingerprint: 'fingerprint-$index',
          fileSize: 3,
          modifiedMs: 1,
        ),
    ];

    service.prefetchAll(items);
    final initial = await service.statsFor(items);
    expect(initial.pendingBackgroundRequests,
        lessThanOrEqualTo(initial.maxBackgroundQueued));

    for (var attempt = 0;
        attempt < 200 &&
            (backend.calls < items.length ||
                backend.activeCalls > 0 ||
                service.activeJobs > 0);
        attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(backend.calls, items.length);
    expect(backend.activeCalls, 0);
    expect(service.activeJobs, 0);
    final completed = await service.statsFor(items);
    expect(completed.cached, items.length);
    expect(completed.backgroundGenerationActive, isFalse);
  });

  test('后台生成使用受控的多核并发，而不是只运行一个 worker', () async {
    final directory =
        await Directory.systemTemp.createTemp('ltp_thumbnail_throughput_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}source.mp4');
    await source.writeAsBytes(const <int>[1, 2, 3]);
    final backend = _BackgroundQueueBackend(
      delay: const Duration(milliseconds: 10),
    );
    final service = ThumbnailService.forDirectory(directory, backend);
    final items = <VideoItem>[
      for (var index = 0; index < 24; index++)
        VideoItem(
          videoId: 'throughput-$index',
          path: source.path,
          title: 'throughput-$index',
          folder: directory.path,
          tags: <String>{},
          addedAt: DateTime(2026),
          mediaFingerprint: 'throughput-fingerprint-$index',
          fileSize: 3,
          modifiedMs: 1,
        ),
    ];

    service.prefetchAll(items);
    for (var attempt = 0;
        attempt < 200 &&
            (backend.calls < items.length ||
                backend.activeCalls > 0 ||
                service.activeJobs > 0);
        attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(backend.calls, items.length);
    expect(backend.activeCalls, 0);
    expect(service.activeJobs, 0);
    expect(backend.maxActiveCalls, service.maxBackgroundJobs);
    expect(
        backend.maxActiveCalls, lessThanOrEqualTo(service.maxConcurrentJobs));
  });

  test('显式缺失补全跳过 missing 记录并只允许一个生产源', () async {
    final directory =
        await Directory.systemTemp.createTemp('ltp_thumbnail_missing_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}source.mp4');
    await source.writeAsBytes(const <int>[1, 2, 3]);
    final backend = _BackgroundQueueBackend(
      delay: const Duration(milliseconds: 50),
    );
    final service = ThumbnailService.forDirectory(directory, backend);
    final item = VideoItem(
      videoId: 'missing-backfill',
      path: source.path,
      title: 'missing-backfill',
      folder: directory.path,
      tags: <String>{},
      addedAt: DateTime(2026),
      mediaFingerprint: 'missing-fingerprint',
      fileSize: 3,
      modifiedMs: 1,
    );
    final missing = VideoItem(
      videoId: 'unavailable-record',
      path: '${directory.path}${Platform.pathSeparator}gone.mp4',
      title: 'unavailable-record',
      folder: directory.path,
      tags: <String>{},
      addedAt: DateTime(2026),
      isMissing: true,
    );

    service.generateMissing(<VideoItem>[item, missing]);
    // 让生产源先耗尽但让 FFmpeg 仍保持活动，覆盖“源已结束、任务未结束”窗口。
    await Future<void>.delayed(const Duration(milliseconds: 10));
    service.generateMissing(<VideoItem>[item]);
    for (var attempt = 0; attempt < 100 && backend.calls == 0; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(backend.calls, 1);
    expect(missing.thumbnailError, isNull);
  });

  test('已有预取源运行时登记缺失补全不会被静默丢弃', () async {
    final directory =
        await Directory.systemTemp.createTemp('ltp_thumbnail_deferred_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}source.mp4');
    await source.writeAsBytes(const <int>[1, 2, 3]);
    final backend = _BackgroundQueueBackend(
      delay: const Duration(milliseconds: 20),
    );
    final service = ThumbnailService.forDirectory(directory, backend);
    final items = <VideoItem>[
      for (var index = 0; index < 2; index++)
        VideoItem(
          videoId: 'deferred-$index',
          path: source.path,
          title: 'deferred-$index',
          folder: directory.path,
          tags: <String>{},
          addedAt: DateTime(2026),
          mediaFingerprint: 'deferred-fingerprint-$index',
          fileSize: 3,
          modifiedMs: 1,
        ),
    ];

    service.prefetchAll(<VideoItem>[items.first]);
    service.generateMissing(<VideoItem>[items.last]);
    for (var attempt = 0;
        attempt < 200 &&
            (backend.calls < items.length ||
                backend.activeCalls > 0 ||
                service.activeJobs > 0);
        attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(backend.calls, items.length);
    expect((await service.statsFor(items)).backgroundGenerationActive, isFalse);
  });

  test('失败重试超过 500 项时也持续推进而不截断', () async {
    final directory =
        await Directory.systemTemp.createTemp('ltp_thumbnail_retry_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}source.mp4');
    await source.writeAsBytes(const <int>[1, 2, 3]);
    final backend = _BackgroundQueueBackend();
    final service = ThumbnailService.forDirectory(directory, backend);
    final items = <VideoItem>[
      for (var index = 0; index < 501; index++)
        VideoItem(
          videoId: 'retry-$index',
          path: source.path,
          title: 'retry-$index',
          folder: directory.path,
          tags: <String>{},
          addedAt: DateTime(2026),
          mediaFingerprint: 'retry-fingerprint-$index',
          fileSize: 3,
          modifiedMs: 1,
          thumbnailError: 'old failure',
        ),
    ];

    expect(await service.retryFailed(items), items.length);
    for (var attempt = 0;
        attempt < 200 && backend.calls < items.length;
        attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(backend.calls, items.length);
    expect(items.every((item) => item.thumbnailError == null), isTrue);
  });
}

class _BackgroundQueueBackend implements FFmpegBackend {
  _BackgroundQueueBackend({this.delay = const Duration(milliseconds: 1)});

  final Duration delay;
  var calls = 0;
  var activeCalls = 0;
  var maxActiveCalls = 0;

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
  }) async {
    calls++;
    activeCalls++;
    if (activeCalls > maxActiveCalls) {
      maxActiveCalls = activeCalls;
    }
    try {
      await Future<void>.delayed(delay);
      await output.parent.create(recursive: true);
      await output.writeAsBytes(const <int>[0xff, 0xd8, 0xff, 0xd9]);
      return output;
    } finally {
      activeCalls--;
    }
  }

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
