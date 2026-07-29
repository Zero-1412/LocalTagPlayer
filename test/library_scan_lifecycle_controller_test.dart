import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_scan_lifecycle_controller.dart';
import 'package:local_tag_player/src/models/library_scan_models.dart';

// ignore_for_file: slash_for_doc_comments

/** 创建不包含数据副作用的扫描结果，专门验证 lifecycle generation。 */
LibraryScanCommitResult _result(
  int generation, {
  bool cancelled = false,
}) {
  if (cancelled) {
    return LibraryScanCommitResult.cancelled(generation);
  }
  return LibraryScanCommitResult(
    generationId: generation,
    addedCount: 0,
    modifiedCount: 0,
    missingCount: 0,
    relinkedCount: 0,
    changedVideos: const [],
    probeCandidates: const [],
  );
}

/** 创建指定后端 generation 的确定型扫描进度。 */
LibraryScanProgress _progress(
  int generation, {
  bool paused = false,
}) =>
    LibraryScanProgress(
      generationId: generation,
      phase: LibraryScanPhase.fingerprinting,
      processed: 1,
      discovered: 2,
      total: 2,
      isPaused: paused,
    );

void main() {
  test('扫描只接受同一操作与后端 generation 的进度和结果', () async {
    final controller = LibraryScanLifecycleController<String>();
    final states = <LibraryScanLifecycleState<String>>[];
    LibraryScanProgressCallback? publishProgress;
    final result = Completer<LibraryScanCommitResult>();
    var accepted = 0;

    final running = controller.run(
      action: (onProgress) {
        publishProgress = onProgress;
        return result.future;
      },
      onAccepted: (_) {
        accepted += 1;
        expect(controller.state.isScanning, isTrue);
      },
      onFailure: (_, __) {},
      onChanged: states.add,
    );
    publishProgress!(_progress(7));
    publishProgress!(_progress(8));
    result.complete(_result(7));
    expect(await running, isTrue);

    expect(accepted, 1);
    expect(
      states
          .where((state) => state.scanProgress != null)
          .map((state) => state.scanProgress!.generationId),
      everyElement(7),
    );
    expect(controller.state.isScanning, isFalse);
  });

  test('后端 generation 不一致的结果被拒绝且并发扫描被限流', () async {
    final controller = LibraryScanLifecycleController<String>();
    final result = Completer<LibraryScanCommitResult>();
    LibraryScanProgressCallback? publishProgress;
    var accepted = 0;
    final first = controller.run(
      action: (onProgress) {
        publishProgress = onProgress;
        return result.future;
      },
      onAccepted: (_) => accepted += 1,
      onFailure: (_, __) {},
      onChanged: (_) {},
    );
    final second = await controller.run(
      action: (_) async => _result(99),
      onAccepted: (_) => accepted += 1,
      onFailure: (_, __) {},
      onChanged: (_) {},
    );
    publishProgress!(_progress(11));
    result.complete(_result(12));

    expect(second, isFalse);
    expect(await first, isTrue);
    expect(accepted, 0);
  });

  test('暂停失败回滚且取消状态保持到扫描 Future 退出', () async {
    final controller = LibraryScanLifecycleController<String>();
    final result = Completer<LibraryScanCommitResult>();
    LibraryScanProgressCallback? publishProgress;
    final running = controller.run(
      action: (onProgress) {
        publishProgress = onProgress;
        return result.future;
      },
      onAccepted: (_) {},
      onFailure: (_, __) {},
      onChanged: (_) {},
    );
    publishProgress!(_progress(21));

    await expectLater(
      controller.toggleScanPaused(
        setPaused: (_) => Future<void>.error(StateError('pause failed')),
        onChanged: (_) {},
      ),
      throwsStateError,
    );
    expect(controller.state.scanProgress?.isPaused, isFalse);

    var cancelCalls = 0;
    expect(
      await controller.cancelScan(
        cancel: () async => cancelCalls += 1,
        onChanged: (_) {},
      ),
      isTrue,
    );
    expect(controller.state.isCancelling, isTrue);
    expect(cancelCalls, 1);
    result.complete(_result(21, cancelled: true));
    await running;
    expect(controller.state.isScanning, isFalse);
    expect(controller.state.isCancelling, isFalse);
  });

  test('路径检查和媒体解析都只允许最新 generation 发布', () async {
    final controller = LibraryScanLifecycleController<String>();
    final firstImport = controller.beginPathImportInspection();
    final secondImport = controller.beginPathImportInspection();
    expect(controller.isCurrentPathImport(firstImport), isFalse);
    expect(controller.isCurrentPathImport(secondImport), isTrue);

    final firstMedia = controller.beginMediaImport(onChanged: (_) {});
    final secondMedia = controller.beginMediaImport(onChanged: (_) {});
    controller.publishMediaImportProgress(
      generation: firstMedia,
      progress: '旧进度',
      isComplete: false,
      onChanged: (_) {},
    );
    expect(controller.state.mediaImportProgress, isNull);
    controller.publishMediaImportProgress(
      generation: secondMedia,
      progress: '当前进度',
      isComplete: false,
      onChanged: (_) {},
    );
    expect(controller.state.mediaImportProgress, '当前进度');
    controller.publishMediaImportProgress(
      generation: secondMedia,
      progress: '完成',
      isComplete: true,
      onChanged: (_) {},
    );
    expect(controller.state.mediaImportProgress, isNull);
  });

  test('dispose 后旧 Future、旧错误和旧媒体进度均不得发布', () async {
    final controller = LibraryScanLifecycleController<String>();
    final result = Completer<LibraryScanCommitResult>();
    var accepted = 0;
    var failures = 0;
    var changes = 0;
    final running = controller.run(
      action: (_) => result.future,
      onAccepted: (_) => accepted += 1,
      onFailure: (_, __) => failures += 1,
      onChanged: (_) => changes += 1,
    );
    final mediaGeneration = controller.beginMediaImport(
      onChanged: (_) => changes += 1,
    );
    controller.dispose();
    result.complete(_result(31));
    await running;
    controller.publishMediaImportProgress(
      generation: mediaGeneration,
      progress: 'late',
      isComplete: false,
      onChanged: (_) => changes += 1,
    );

    expect(accepted, 0);
    expect(failures, 0);
    expect(changes, 2);
    expect(controller.state.isScanning, isFalse);
    expect(controller.state.mediaImportProgress, isNull);
  });
}
