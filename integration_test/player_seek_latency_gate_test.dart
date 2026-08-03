import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/src/features/player/application/player_seek_coordinator.dart';
import 'package:local_tag_player/src/services/player/media_kit_player_backend.dart';
import 'package:local_tag_player/src/services/player/player_hardware_acceleration.dart';
import 'package:media_kit/media_kit.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 使用正式 MediaKit Texture 与真实媒体建立单样本 seek 延迟门禁。
 *
 * 样本的编码、分辨率和 GOP 由外部矩阵脚本先用 ffprobe 核验；测试不记录路径，
 * 只输出匿名 case、实际解码器和 p50/p95/max。短按路径复用正式
 * [PlayerKeyboardSeekController]，确保它没有悄悄恢复为预览加精确 seek 的双跳转。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实媒体 seek 延迟满足单样本 p95 门禁', (tester) async {
    final samplePath = _requiredEnvironment('LOCAL_TAG_PLAYER_SEEK_SAMPLE');
    final caseId = _requiredEnvironment('LOCAL_TAG_PLAYER_SEEK_CASE');
    final p95BudgetMs = int.parse(
      _requiredEnvironment('LOCAL_TAG_PLAYER_SEEK_P95_BUDGET_MS'),
    );
    if (!File(samplePath).existsSync()) {
      throw StateError('seek 延迟门禁样本不存在');
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
          backend.state.duration > const Duration(seconds: 12) &&
          backend.state.position > Duration.zero,
      const Duration(seconds: 30),
      operation: '真实媒体首帧与时长',
    );
    final playbackGate = _createAudioGate(tester, backend);

    final duration = backend.state.duration;
    // 先完成两次不计分的预热，避免把打开后首个随机访问当成稳态交互延迟。
    for (final fraction in <double>[0.18, 0.72]) {
      await _seekAndConfirm(
        tester,
        backend,
        playbackGate,
        _fractionOf(duration, fraction),
      );
    }

    final samples = <int>[];
    for (final fraction in <double>[0.31, 0.64, 0.43, 0.81, 0.26, 0.55, 0.37]) {
      final elapsed = await _seekAndConfirm(
        tester,
        backend,
        playbackGate,
        _fractionOf(duration, fraction),
      );
      samples.add(elapsed);
    }

    await _verifyShortAndLongKeyboardPaths(tester, backend, playbackGate);
    final sorted = List<int>.of(samples)..sort();
    final p50 = sorted[sorted.length ~/ 2];
    final p95 = sorted[((sorted.length - 1) * 0.95).round()];
    final maximum = sorted.last;
    final codec = await backend.getProperty('video-codec');
    final hwdec = await backend.getProperty('hwdec-current');
    // 输出中不包含本地路径；脚本只保存用于回归比较的匿名元数据和延迟统计。
    // ignore: avoid_print
    print(
      'PLAYER_SEEK_LATENCY ${jsonEncode(<String, Object?>{
            'case': caseId,
            'samples': samples.length,
            'p50Ms': p50,
            'p95Ms': p95,
            'maxMs': maximum,
            'budgetMs': p95BudgetMs,
            'codec': codec,
            'hwdec': hwdec,
          })}',
    );
    expect(
      p95,
      lessThanOrEqualTo(p95BudgetMs),
      reason: '真实 seek p95 超出该编码/分辨率/GOP case 的预算',
    );

    await backend.dispose();
    await backend.released;
    disposed = true;
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/** 短按必须只有一次精确 seek；长按才允许关键帧预览后精确收敛。 */
Future<void> _verifyShortAndLongKeyboardPaths(
  WidgetTester tester,
  MediaKitPlayerBackend backend,
  PlayerSeekAudioGate playbackGate,
) async {
  final previews = <Duration>[];
  final exacts = <Duration>[];
  final coordinator = PlayerSeekCoordinator(
    submit: (target) async {
      previews.add(target);
      await backend.seekInteractive(target);
    },
    readPosition: () => backend.state.position,
    readDuration: () => backend.state.duration,
    isExiting: () => false,
    onLatency: (_) {},
    confirmationTimeout: const Duration(seconds: 3),
  );
  final keyboard = PlayerKeyboardSeekController(
    coordinator: coordinator,
    settle: (target) async {
      exacts.add(target);
      await backend.seek(target);
      await _waitForPosition(tester, backend, target);
    },
    readPosition: () => backend.state.position,
    readDuration: () => backend.state.duration,
    isExiting: () => false,
    onLatency: (_) {},
    previewAudioGate: playbackGate,
  );

  final shortTarget = keyboard.requestRelative(
    const Duration(seconds: 3),
    submitPreview: false,
  );
  await keyboard.settle();
  await _waitForPosition(tester, backend, shortTarget);
  expect(previews, isEmpty, reason: '短按不得先提交关键帧预览');
  expect(exacts, hasLength(1), reason: '短按必须只提交一次精确 seek');

  final longTarget = keyboard.requestRelative(
    const Duration(seconds: 3),
    submitPreview: false,
  );
  final finalLongTarget = keyboard.requestRelative(const Duration(seconds: 1));
  await keyboard.settle();
  await _waitForPosition(tester, backend, finalLongTarget);
  expect(longTarget, lessThan(finalLongTarget));
  expect(previews, hasLength(1), reason: '长按重复时应有一条关键帧预览');
  expect(exacts, hasLength(2), reason: '长按 KeyUp 仍只精确收敛一次');
}

/** 对正式后端发送一次精确 seek，并等待画面位置真实接近目标。 */
Future<int> _seekAndConfirm(
  WidgetTester tester,
  MediaKitPlayerBackend backend,
  PlayerSeekAudioGate playbackGate,
  Duration target,
) async {
  final stopwatch = Stopwatch()..start();
  // 矩阵测量走与页面相同的临时静音会话：视频时钟不停，最终新帧交付后才恢复音频。
  await playbackGate.run(() async {
    await backend.seek(target);
    await _waitForPosition(tester, backend, target);
  });
  stopwatch.stop();
  return stopwatch.elapsedMilliseconds;
}

/** 为真实 Texture 测量构建与页面一致的临时静音与帧交付门。 */
PlayerSeekAudioGate _createAudioGate(
  WidgetTester tester,
  MediaKitPlayerBackend backend,
) =>
    PlayerSeekAudioGate(
      readDesiredVolume: () => 100,
      setVolume: backend.setVolume,
      readPresentedFrame: () => _readPresentedFrame(backend),
      waitForNewFrame: (previousFrame, timeout) =>
          _waitForNewFrame(tester, backend, previousFrame, timeout),
      framePresentationTimeout: () => const Duration(milliseconds: 1800),
      isExiting: () => false,
    );

Future<int?> _readPresentedFrame(MediaKitPlayerBackend backend) async =>
    int.tryParse((await backend.getProperty('estimated-frame-number')).trim());

Future<bool> _waitForNewFrame(
  WidgetTester tester,
  MediaKitPlayerBackend backend,
  int? previousFrame,
  Duration timeout,
) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    final currentFrame = await _readPresentedFrame(backend);
    if (currentFrame != null &&
        (previousFrame == null || currentFrame != previousFrame)) {
      return true;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  throw TimeoutException('精确 seek 后未观察到新视频帧', timeout);
}

Future<void> _waitForPosition(
  WidgetTester tester,
  MediaKitPlayerBackend backend,
  Duration target,
) =>
    _pumpUntil(
      tester,
      () =>
          (backend.state.position - target).abs() <=
          const Duration(milliseconds: 750),
      const Duration(seconds: 8),
      operation: '真实后端 seek 位置确认',
    );

Duration _fractionOf(Duration duration, double fraction) => Duration(
      milliseconds: (duration.inMilliseconds * fraction).round(),
    );

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate,
  Duration timeout, {
  required String operation,
}) async {
  final stopwatch = Stopwatch()..start();
  while (!predicate() && stopwatch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 25));
  }
  if (!predicate()) {
    throw TimeoutException('$operation 未在门禁时限内完成', timeout);
  }
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('seek 延迟门禁缺少环境变量 $name');
  }
  return value;
}
