import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/src/features/player/application/player_seek_coordinator.dart';
import 'package:local_tag_player/src/services/player/media_kit_player_backend.dart';
import 'package:local_tag_player/src/services/player/player_hardware_acceleration.dart';
import 'package:local_tag_player/src/services/player/windows_native_player_backend.dart';
import 'package:local_tag_player/src/platform/platform_interfaces.dart';
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
    final backendName =
        Platform.environment['LOCAL_TAG_PLAYER_SEEK_BACKEND']?.trim() ??
            'mediaKit';
    final usesChildHwnd = backendName == 'hwnd';
    if (backendName != 'mediaKit' && !usesChildHwnd) {
      throw StateError('seek 延迟门禁后端只能是 mediaKit 或 hwnd');
    }
    if (!File(samplePath).existsSync()) {
      throw StateError('seek 延迟门禁样本不存在');
    }

    if (!usesChildHwnd) MediaKit.ensureInitialized();
    final PlayerBackend backend = usesChildHwnd
        ? WindowsNativePlayerBackend(mode: 'hwnd')
        : MediaKitPlayerBackend(
            hwdec: PlayerHardwareAcceleration.resolve('d3d11va-copy'),
            enableHardwareAcceleration: true,
          );
    final presentation = _FramePresentationProbe(
      backend,
      usesChildHwnd: usesChildHwnd,
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

    final firstPlaybackWatch = Stopwatch()..start();
    await backend.openPath(samplePath);
    await backend.play();
    await _pumpUntil(
      tester,
      () =>
          (usesChildHwnd || backend.textureId.value != null) &&
          backend.state.duration > const Duration(seconds: 12) &&
          backend.state.position > Duration.zero,
      const Duration(seconds: 30),
      operation: '真实媒体首帧与时长',
    );
    await presentation.waitForNewFrame(
      tester,
      null,
      const Duration(seconds: 8),
    );
    firstPlaybackWatch.stop();
    final playbackGate = _createAudioGate(tester, presentation);

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

    final keyboardExperience = await _measureKeyboardExperience(
      tester,
      backend,
      playbackGate,
      presentation,
    );
    final dragExperience = await _measureDragExperience(
      tester,
      backend,
      presentation,
    );
    final sorted = List<int>.of(samples)..sort();
    final p50 = sorted[sorted.length ~/ 2];
    final p95 = sorted[((sorted.length - 1) * 0.95).round()];
    final maximum = sorted.last;
    final codec = await backend.getProperty('video-codec');
    final hwdec = await backend.getProperty('hwdec-current');
    final telemetry = backend is PlayerBackendTelemetryBoundary
        ? (backend as PlayerBackendTelemetryBoundary).telemetry
        : null;
    final textureGenerationCount =
        backend is PlayerVideoSurfaceDiagnosticsBoundary
            ? (backend as PlayerVideoSurfaceDiagnosticsBoundary)
                .videoSurfaceDiagnostics
                .textureGenerationCount
            : null;
    // 输出中不包含本地路径；脚本只保存用于回归比较的匿名元数据和延迟统计。
    // ignore: avoid_print
    print(
      'PLAYER_SEEK_LATENCY ${jsonEncode(<String, Object?>{
            'case': caseId,
            'backend': backendName,
            'samples': samples.length,
            'p50Ms': p50,
            'p95Ms': p95,
            'maxMs': maximum,
            'budgetMs': p95BudgetMs,
            'codec': codec,
            'hwdec': hwdec,
            // 首次播放和随机 seek 必须分开记录：前者反映打开、解码器建链与
            // Texture 就绪，后者反映用户已经观看过程中的跳转体验。
            // evidence 会明确标出是否只能取得 mpv 估算帧号，避免把它写成
            // 已由 Windows 合成器实际呈现的同等级证据。
            'firstFrameMs': telemetry?.firstFrameLatency?.inMilliseconds ??
                firstPlaybackWatch.elapsedMilliseconds,
            'firstFrameEvidence':
                telemetry?.firstFrameEvidence ?? presentation.lastEvidence,
            'textureGenerationCount': textureGenerationCount,
            'keyboardExperience': keyboardExperience,
            'dragExperience': dragExperience,
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

/**
 * 以正式 [PlayerKeyboardSeekController] 重放短按、长按前进与长按后退，不直接调用
 * 后端绕过输入策略。数值从请求开始到帧号代理变化；证据等级随报告一并输出。
 */
Future<Map<String, Object?>> _measureKeyboardExperience(
  WidgetTester tester,
  PlayerBackend backend,
  PlayerSeekAudioGate playbackGate,
  _FramePresentationProbe presentation,
) async {
  final previews = <Duration>[];
  final coordinator = PlayerSeekCoordinator(
    submit: (target) async {
      previews.add(target);
      if (backend is PlayerInteractiveSeekBoundary) {
        await (backend as PlayerInteractiveSeekBoundary)
            .seekInteractive(target);
      } else {
        await backend.seek(target);
      }
    },
    readPosition: () => backend.state.position,
    readDuration: () => backend.state.duration,
    isExiting: () => false,
    onLatency: (_) {},
    confirmationTimeout: const Duration(seconds: 3),
  );
  PlayerKeyboardSeekController createKeyboard() => PlayerKeyboardSeekController(
        coordinator: coordinator,
        readPosition: () => backend.state.position,
        readDuration: () => backend.state.duration,
        isExiting: () => false,
        onLatency: (_) {},
        previewAudioGate: playbackGate,
        // 与页面物理 KeyDown/KeyRepeat/KeyUp 路径一致：短按延后到 KeyUp，首个前进
        // KeyRepeat 进入连续扫描；快退仍保留 latest-only 关键帧预览。
        deferInitialPreviewUntilRelease: true,
        readPlaybackRate: () => 1,
        setTemporaryPlaybackRate: backend.setRate,
        beginFastForwardScan: backend is PlayerFastForwardScanBoundary
            ? (backend as PlayerFastForwardScanBoundary).beginFastForwardScan
            : null,
        endFastForwardScan: backend is PlayerFastForwardScanBoundary
            ? (backend as PlayerFastForwardScanBoundary).endFastForwardScan
            : null,
      );

  final shortForward = <int>[];
  final shortBackward = <int>[];
  final longForward = <int>[];
  final longBackward = <int>[];
  for (var index = 0; index < 7; index++) {
    final forward = createKeyboard();
    shortForward.add(
      await _measureUntilFrameProxy(
        tester,
        presentation,
        () async {
          forward.requestRelative(
            const Duration(seconds: 3),
            mutePreview: false,
          );
          await forward.settlePreview();
        },
      ),
    );
    final backward = createKeyboard();
    shortBackward.add(
      await _measureUntilFrameProxy(
        tester,
        presentation,
        () async {
          backward.requestRelative(
            const Duration(seconds: -3),
            mutePreview: false,
          );
          await backward.settlePreview();
        },
      ),
    );
    final forwardScan = createKeyboard();
    longForward.add(
      await _measureUntilFrameProxy(
        tester,
        presentation,
        () async {
          forwardScan.requestRelative(
            const Duration(seconds: 3),
            mutePreview: false,
          );
          forwardScan.requestRelative(
            const Duration(seconds: 2),
            mutePreview: true,
            isRepeat: true,
          );
          await tester.pump(const Duration(milliseconds: 80));
          await forwardScan.settlePreview();
        },
      ),
    );
    final backwardScan = createKeyboard();
    longBackward.add(
      await _measureUntilFrameProxy(
        tester,
        presentation,
        () async {
          backwardScan.requestRelative(
            const Duration(seconds: -3),
            mutePreview: false,
          );
          for (var repeat = 0; repeat < 3; repeat++) {
            backwardScan.requestRelative(
              const Duration(seconds: -2),
              mutePreview: true,
              isRepeat: true,
            );
          }
          await backwardScan.settlePreview();
        },
      ),
    );
  }
  expect(previews, isNotEmpty, reason: '键盘短按和快退必须提交正式交互式 seek');
  return <String, Object?>{
    'sampleCount': 7,
    'shortForward': _summarizeLatency(shortForward),
    'shortBackward': _summarizeLatency(shortBackward),
    'longForwardScan': _summarizeLatency(longForward),
    'longBackwardPreview': _summarizeLatency(longBackward),
    'frameEvidence': presentation.lastEvidence,
  };
}

/**
 * 模拟一次进度条拖动：同一次手势中的中间目标只保留 latest，最终目标到帧号代理变化
 * 作为该次拖动的完成点。该口径不把多次 Dart 命令完成误写成画面已更新。
 */
Future<Map<String, Object?>> _measureDragExperience(
  WidgetTester tester,
  PlayerBackend backend,
  _FramePresentationProbe presentation,
) async {
  final coordinator = PlayerSeekCoordinator(
    submit: (target) async {
      if (backend is PlayerInteractiveSeekBoundary) {
        await (backend as PlayerInteractiveSeekBoundary)
            .seekInteractive(target);
      } else {
        await backend.seek(target);
      }
    },
    readPosition: () => backend.state.position,
    readDuration: () => backend.state.duration,
    isExiting: () => false,
    onLatency: (_) {},
  );
  final duration = backend.state.duration;
  final samples = <int>[];
  for (final base in <double>[0.14, 0.26, 0.38, 0.51, 0.63, 0.74, 0.82]) {
    samples.add(
      await _measureUntilFrameProxy(
        tester,
        presentation,
        () async {
          Future<void> latest =
              coordinator.request(_fractionOf(duration, base));
          for (final offset in <double>[0.025, 0.052, 0.078]) {
            latest = coordinator.request(_fractionOf(duration, base + offset));
            await tester.pump(const Duration(milliseconds: 32));
          }
          await latest;
        },
      ),
    );
  }
  return <String, Object?>{
    'sampleCount': samples.length,
    'latestOnlyDrag': _summarizeLatency(samples),
    'frameEvidence': presentation.lastEvidence,
  };
}

/** 从输入动作开始，等到后端的帧号代理变化；超时保留为失败而非把命令 Future 当成功。 */
Future<int> _measureUntilFrameProxy(
  WidgetTester tester,
  _FramePresentationProbe presentation,
  Future<void> Function() action,
) async {
  final previous = await presentation.readFrame();
  final watch = Stopwatch()..start();
  await action();
  await presentation.waitForNewFrame(
    tester,
    previous,
    const Duration(seconds: 8),
  );
  watch.stop();
  return watch.elapsedMilliseconds;
}

/** 统一输出 p50/p95/max，样本数不足或超时不能被平均值掩盖。 */
Map<String, int> _summarizeLatency(List<int> samples) {
  final sorted = List<int>.of(samples)..sort();
  return <String, int>{
    'p50Ms': sorted[sorted.length ~/ 2],
    'p95Ms': sorted[((sorted.length - 1) * 0.95).round()],
    'maxMs': sorted.last,
  };
}

/** 对正式后端发送一次精确 seek，并等待画面位置真实接近目标。 */
Future<int> _seekAndConfirm(
  WidgetTester tester,
  PlayerBackend backend,
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
  _FramePresentationProbe presentation,
) =>
    PlayerSeekAudioGate(
      readDesiredVolume: () => 100,
      setVolume: presentation.backend.setVolume,
      readPresentedFrame: presentation.readFrame,
      waitForNewFrame: (previousFrame, timeout) =>
          presentation.waitForNewFrame(tester, previousFrame, timeout),
      framePresentationTimeout: () => const Duration(milliseconds: 1800),
      isExiting: () => false,
      readFrameEvidence: () => presentation.lastEvidence,
    );

/**
 * 把“帧号发生变化”与“真实 Windows 桌面已经采样到像素”明确区分。
 *
 * 正式 Texture 可能只提供 mpv 估算帧号回退；child HWND 还需要同时观察到原生窗口
 * 可见。两者都是后端到表面的呈现代理，而不是桌面捕获证据，报告会保留 evidence，
 * 不能同专业播放器的屏幕级呈现统计混算。
 */
class _FramePresentationProbe {
  _FramePresentationProbe(this.backend, {required this.usesChildHwnd});

  final PlayerBackend backend;
  final bool usesChildHwnd;
  String lastEvidence = 'unavailable';

  Future<int?> readFrame() async {
    final nativeRendered = int.tryParse(
      (await backend.getProperty('native-rendered-frames')).trim(),
    );
    // HWND 不创建 Flutter Texture，零值不能作为“纹理已呈现”的证据；必须回退到
    // mpv 帧号，并在下方额外核验 child HWND 已挂载可见。
    if (nativeRendered != null && nativeRendered > 0) {
      lastEvidence = 'native-rendered-texture';
      return nativeRendered;
    }
    final estimatedFrame = int.tryParse(
      (await backend.getProperty('estimated-frame-number')).trim(),
    );
    if (estimatedFrame == null) return null;
    if (!usesChildHwnd) {
      lastEvidence = 'estimated-frame-number-fallback';
      return estimatedFrame;
    }
    final surfaceVisible =
        (await backend.getProperty('native-surface-visible')).trim() == 'true';
    if (!surfaceVisible) return null;
    lastEvidence = 'child-hwnd-visible+estimated-frame-number-proxy';
    return estimatedFrame;
  }

  Future<bool> waitForNewFrame(
    WidgetTester tester,
    int? previousFrame,
    Duration timeout,
  ) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < timeout) {
      final currentFrame = await readFrame();
      if (currentFrame != null &&
          (previousFrame == null || currentFrame != previousFrame)) {
        return true;
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    throw TimeoutException('精确 seek 后未观察到新视频帧代理', timeout);
  }
}

Future<void> _waitForPosition(
  WidgetTester tester,
  PlayerBackend backend,
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
