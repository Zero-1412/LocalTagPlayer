import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/src/features/player/application/player_seek_coordinator.dart';
import 'package:local_tag_player/src/services/player/media_kit_player_backend.dart';
import 'package:local_tag_player/src/services/player/player_hardware_acceleration.dart';
import 'package:media_kit/media_kit.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 用真实 MediaKit Texture 验证连续 seek 会更新最终画面，而不只改变 Dart 目标位置。
 *
 * 片源由隔离 QA 环境变量提供；测试只比较内存截图摘要、位置与掉帧计数，不写入媒体路径、
 * 截图或用户资料库数据。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('连续快进快退后 Texture 跟随最终目标画面', (tester) async {
    final samplePath =
        Platform.environment['LOCAL_TAG_PLAYER_SEEK_SAMPLE']?.trim();
    if (samplePath == null ||
        samplePath.isEmpty ||
        !File(samplePath).existsSync()) {
      throw StateError('连续 seek 门禁缺少存在的隔离视频样本');
    }

    MediaKit.ensureInitialized();
    final backend = MediaKitPlayerBackend(
      hwdec: PlayerHardwareAcceleration.resolve('d3d11va-copy'),
      enableHardwareAcceleration: true,
    );
    var disposed = false;
    addTearDown(() async {
      if (!disposed) {
        await backend.dispose();
        await backend.released;
      }
    });

    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: backend.buildVideoSurface(
            controls: const SizedBox.expand(),
            fit: BoxFit.contain,
          ),
        ),
      ),
    );

    await backend.openPath(samplePath);
    await backend.play();
    await _pumpUntil(
      tester,
      () =>
          backend.textureId.value != null &&
          backend.state.duration > const Duration(seconds: 2) &&
          backend.state.position > Duration.zero,
      const Duration(seconds: 30),
      operation: '真实视频首帧',
    );

    final duration = backend.state.duration;
    final initialTarget = _fractionOf(duration, 0.18);
    await backend.seek(initialTarget);
    await _pumpUntilPosition(
      tester,
      backend,
      initialTarget,
      const Duration(seconds: 8),
    );
    await tester.pump(const Duration(milliseconds: 250));
    final initialFrame = await backend.screenshot(format: 'image/png');
    expect(initialFrame, isNotNull);
    expect(initialFrame, isNotEmpty);

    final droppedBefore =
        int.tryParse(await backend.getProperty('frame-drop-count')) ?? 0;
    final targets = <Duration>[
      for (final fraction in <double>[
        0.28,
        0.42,
        0.31,
        0.55,
        0.38,
        0.68,
        0.47,
        0.76,
      ])
        _fractionOf(duration, fraction),
    ];
    final coordinator = PlayerSeekCoordinator(
      // 模拟正式页面的进度条/连续按键路径，必须走关键帧优先的交互式随机跳转。
      submit: backend.seekInteractive,
      readPosition: () => backend.state.position,
      readDuration: () => backend.state.duration,
      isExiting: () => false,
      onLatency: (_) {},
    );

    final worker = coordinator.request(targets.first);
    for (final target in targets.skip(1)) {
      unawaited(coordinator.request(target));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await _pumpFutureUntilComplete(
      tester,
      worker,
      const Duration(seconds: 10),
      operation: '连续 seek 工作器',
    );

    final finalTarget = targets.last;
    await _pumpUntilPosition(
      tester,
      backend,
      finalTarget,
      const Duration(seconds: 8),
    );
    await tester.pump(const Duration(milliseconds: 350));
    final finalFrame = await backend.screenshot(format: 'image/png');
    expect(finalFrame, isNotNull);
    expect(finalFrame, isNotEmpty);
    expect(
      sha256.convert(finalFrame!).toString(),
      isNot(sha256.convert(initialFrame!).toString()),
    );
    expect(
      (backend.state.position - finalTarget).abs(),
      lessThanOrEqualTo(const Duration(milliseconds: 750)),
    );
    final advancingPosition = backend.state.position;
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      backend.state.position,
      greaterThan(advancingPosition),
      reason: '播放态随机 seek 后应立即继续推进，不能只停在已确认目标',
    );
    await backend.pause();
    await _pumpUntil(
      tester,
      () => !backend.state.playing,
      const Duration(seconds: 2),
      operation: '暂停状态确认',
    );
    final pausedTarget = _fractionOf(duration, 0.36);
    await backend.seekInteractive(pausedTarget);
    await _pumpUntil(
      tester,
      () =>
          (backend.state.position - advancingPosition).abs() >
          const Duration(seconds: 1),
      const Duration(seconds: 8),
      operation: '暂停态交互式 seek 位置变化',
    );
    expect(
      backend.state.playing,
      isFalse,
      reason: '交互式 seek 只优化随机访问延迟，不能擅自改变用户暂停意图',
    );
    final droppedAfter =
        int.tryParse(await backend.getProperty('frame-drop-count')) ??
            droppedBefore;
    expect(droppedAfter - droppedBefore, lessThanOrEqualTo(5));

    await backend.dispose();
    await backend.released;
    disposed = true;
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/** 按媒体时长生成避开开头、结尾的确定性绝对位置。 */
Duration _fractionOf(Duration duration, double fraction) => Duration(
      milliseconds: (duration.inMilliseconds * fraction).round(),
    );

/** 持续推进 Flutter 帧直到 [predicate] 成立或 [timeout] 到期。 */
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate,
  Duration timeout, {
  required String operation,
}) async {
  final stopwatch = Stopwatch()..start();
  while (!predicate() && stopwatch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (!predicate()) {
    throw TimeoutException('$operation 未在门禁时限内完成', timeout);
  }
}

/** 等待真实后端位置接近目标，证明播放器已经响应而非仅接收命令。 */
Future<void> _pumpUntilPosition(
  WidgetTester tester,
  MediaKitPlayerBackend backend,
  Duration target,
  Duration timeout,
) =>
    _pumpUntil(
      tester,
      () =>
          (backend.state.position - target).abs() <=
          const Duration(milliseconds: 750),
      timeout,
      operation: '真实视频位置确认',
    );

/** 等待依赖 Flutter 帧时钟的 Future，同时保留原始异常堆栈。 */
Future<void> _pumpFutureUntilComplete(
  WidgetTester tester,
  Future<void> future,
  Duration timeout, {
  required String operation,
}) async {
  var completed = false;
  Object? failure;
  StackTrace? failureStack;
  unawaited(
    future.then<void>(
      (_) => completed = true,
      onError: (Object error, StackTrace stackTrace) {
        failure = error;
        failureStack = stackTrace;
        completed = true;
      },
    ),
  );
  await _pumpUntil(
    tester,
    () => completed,
    timeout,
    operation: operation,
  );
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureStack!);
  }
}
