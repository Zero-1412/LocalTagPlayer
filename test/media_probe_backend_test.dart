import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';
import 'dart:async';

// ignore_for_file: slash_for_doc_comments

/** 用于确认媒体详情服务只传数据库已有元数据且会取消旧 generation。 */
class _RecordingProbeBackend implements MediaProbeBackend {
  final List<MediaProbeRequest> requests = <MediaProbeRequest>[];
  final List<int> batchSizes = <int>[];
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
    batchSizes.add(requests.length);
    this.requests.addAll(requests);
    return requests
        .map((request) => MediaProbeResult(
              videoId: request.videoId,
              details: const MediaDetails(
                videoCodec: 'h264',
                audioCodec: 'aac',
                width: 1920,
                height: 1080,
                duration: Duration(minutes: 2),
              ),
            ))
        .toList(growable: false);
  }
}

/** 用阻塞首项确认可视请求能越过尚未执行的扫描后台任务。 */
class _PriorityProbeBackend implements MediaProbeBackend {
  final List<String> executionOrder = <String>[];
  final Completer<void> firstStarted = Completer<void>();
  final Completer<void> releaseFirst = Completer<void>();

  @override
  Future<void> cancelGeneration(int generationId) async {}

  @override
  Future<List<MediaProbeResult>> probeBatch({
    required int generationId,
    required List<MediaProbeRequest> requests,
  }) async {
    final request = requests.single;
    executionOrder.add(request.videoId);
    if (executionOrder.length == 1) {
      firstStarted.complete();
      await releaseFirst.future;
    }
    return <MediaProbeResult>[
      MediaProbeResult(
        videoId: request.videoId,
        details: const MediaDetails(
          videoCodec: 'h264',
          audioCodec: 'aac',
          width: 1920,
          height: 1080,
        ),
      ),
    ];
  }
}

/** 用可控批次确认暂停只阻止后续任务，活动小批次仍能安全完成。 */
class _PausableProbeBackend implements MediaProbeBackend {
  final List<int> batchSizes = <int>[];
  final List<Completer<void>> _releaseGates = <Completer<void>>[];
  final Completer<void> firstStarted = Completer<void>();
  final Completer<void> secondStarted = Completer<void>();

  @override
  Future<void> cancelGeneration(int generationId) async {}

  @override
  Future<List<MediaProbeResult>> probeBatch({
    required int generationId,
    required List<MediaProbeRequest> requests,
  }) async {
    batchSizes.add(requests.length);
    final gate = Completer<void>();
    _releaseGates.add(gate);
    if (batchSizes.length == 1) {
      firstStarted.complete();
    } else if (batchSizes.length == 2) {
      secondStarted.complete();
    }
    await gate.future;
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

  /** 释放指定原生批次，模拟该批媒体读取自然完成。 */
  void releaseBatch(int index) => _releaseGates[index].complete();
}

/** 创建不依赖真实文件的媒体探测测试条目。 */
VideoItem _probeItem(String id) => VideoItem(
      videoId: id,
      path: 'Z:/virtual/$id.mp4',
      title: id,
      folder: 'Z:/virtual',
      tags: const <String>{},
      addedAt: DateTime.utc(2026, 7, 14),
    );

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
    expect(details.duration, const Duration(minutes: 2));
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

  test('background probe backfills old cached details without duration',
      () async {
    final backend = _RecordingProbeBackend();
    final completed = Completer<void>();
    final item = _probeItem('legacy-duration')
      ..mediaDetails = const MediaDetails(
        videoCodec: 'h264',
        audioCodec: 'aac',
        width: 1920,
        height: 1080,
      );
    final service = MediaDetailsService(
      probeBackend: backend,
      onProgress: (progress) {
        if (progress.isComplete && !completed.isCompleted) {
          completed.complete();
        }
      },
    );

    service.prefetchAll(<VideoItem>[item]);
    await completed.future;
    service.dispose();

    expect(backend.requests.single.videoId, item.videoId);
  });

  test('visible media details jump ahead of queued background probes',
      () async {
    final backend = _PriorityProbeBackend();
    final service = MediaDetailsService(probeBackend: backend);

    final first = service.detailsFor(_probeItem('background-first'));
    await backend.firstStarted.future;
    final second = service.detailsFor(_probeItem('background-second'));
    final visible = service.detailsFor(
      _probeItem('visible-now'),
      priority: true,
    );
    backend.releaseFirst.complete();

    await Future.wait(<Future<MediaDetails>>[first, second, visible]);
    service.dispose();

    expect(
      backend.executionOrder,
      <String>['background-first', 'visible-now', 'background-second'],
    );
  });

  test('background media details use bounded batches and report progress',
      () async {
    final backend = _RecordingProbeBackend();
    final completed = Completer<MediaDetailsProgress>();
    final persistedBatchSizes = <int>[];
    final progressSnapshots = <MediaDetailsProgress>[];
    final service = MediaDetailsService(
      probeBackend: backend,
      onBatchUpdated: (updates) async {
        persistedBatchSizes.add(updates.length);
      },
      onProgress: (progress) {
        progressSnapshots.add(progress);
        if (progress.isComplete && !completed.isCompleted) {
          completed.complete(progress);
        }
      },
    );

    service.prefetchAll(List<VideoItem>.generate(
      20,
      (index) => _probeItem('background-$index'),
    ));
    final finalProgress = await completed.future;
    service.dispose();

    expect(backend.batchSizes, <int>[8, 8, 4]);
    expect(persistedBatchSizes, <int>[8, 8, 4]);
    expect(progressSnapshots.first.total, 20);
    expect(finalProgress.processed, 20);
    expect(finalProgress.fraction, 1);
    expect(finalProgress.failed, 0);
    expect(finalProgress.itemsPerSecond, isNotNull);
    expect(finalProgress.estimatedRemaining, isNull);
    expect(
      libraryMediaImportProgressLabel(const MediaDetailsProgress(
        total: 20,
        completed: 7,
        failed: 1,
        queued: 4,
        active: 8,
      )),
      '媒体解析 8/20 · 40%',
    );
    expect(
      libraryMediaImportProgressLabel(const MediaDetailsProgress(
        total: 100,
        completed: 40,
        failed: 0,
        queued: 52,
        active: 8,
        itemsPerSecond: 25.4,
        estimatedRemaining: Duration(seconds: 142),
      )),
      '媒体解析 40/100 · 40% · 25个/秒 · 剩余2分22秒',
    );
    expect(
      libraryMediaImportProgressLabel(const MediaDetailsProgress(
        total: 100,
        completed: 40,
        failed: 0,
        queued: 60,
        active: 0,
        itemsPerSecond: 25.4,
        estimatedRemaining: Duration(seconds: 142),
        isPaused: true,
      )),
      '媒体解析 40/100 · 40% · 已暂停',
    );
  });

  test('paused media details finish the active batch then resume the queue',
      () async {
    final backend = _PausableProbeBackend();
    final pausedAfterFirstBatch = Completer<MediaDetailsProgress>();
    final completed = Completer<MediaDetailsProgress>();
    final service = MediaDetailsService(
      probeBackend: backend,
      onBatchUpdated: (_) async {},
      onProgress: (progress) {
        if (progress.isPaused &&
            progress.processed == 8 &&
            !pausedAfterFirstBatch.isCompleted) {
          pausedAfterFirstBatch.complete(progress);
        }
        if (progress.isComplete && !completed.isCompleted) {
          completed.complete(progress);
        }
      },
    );

    service.prefetchAll(List<VideoItem>.generate(
      12,
      (index) => _probeItem('pausable-$index'),
    ));
    await backend.firstStarted.future;
    service.pause();
    backend.releaseBatch(0);
    final paused = await pausedAfterFirstBatch.future;

    expect(service.isPaused, isTrue);
    expect(paused.active, 0);
    expect(paused.queued, 4);
    expect(backend.batchSizes, <int>[8]);

    service.resume();
    await backend.secondStarted.future;
    backend.releaseBatch(1);
    final finished = await completed.future;
    service.dispose();

    expect(backend.batchSizes, <int>[8, 4]);
    expect(finished.processed, 12);
    expect(finished.isPaused, isFalse);
  });
}
