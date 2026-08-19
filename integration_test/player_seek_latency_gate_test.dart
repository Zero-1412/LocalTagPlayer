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
    // 反向长尾不能只看最后一个 p95。这个只读 trace 将命令、位置状态确认、帧代理、
    // 缓存/VO/硬解和 Texture 状态拆开，桌面像素证据仍由独立 Windows 探针提供。
    final reverseSeekTrace = await _measureReverseKeyframeTrace(
      tester,
      backend,
      presentation,
    );
    // 反向连续播放只在显式 Debug QA 环境尝试。mpv 官方把 backward playback 标为
    // fragile/slow，不能把它暗中变成正式默认行为；本实验只记录位置、cache、掉帧、
    // 硬解和 Texture 运行态，失败时仍保持当前 latest-only 快退合同。
    final reverseDirectionExperiment =
        Platform.environment['LOCAL_TAG_PLAYER_REVERSE_DIRECTION_QA'] == '1' &&
                !usesChildHwnd
            ? await _measureReverseDirectionExperiment(tester, backend)
            : const <String, Object?>{
                'enabled': false,
                'status': 'not-run',
                'evidence': 'backend-runtime-only',
              };
    expect(
      reverseSeekTrace['successfulSamples'],
      reverseSeekTrace['sampleCount'],
      reason: '反向关键帧 trace 不能以部分成功样本生成 p95；失败必须保留为门禁失败',
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
            'reverseKeyframeTrace': reverseSeekTrace,
            'reverseDirectionExperiment': reverseDirectionExperiment,
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
 * 显式 Debug-only 的 mpv backward playback 可行性实验。
 *
 * 这不是正式快退实现：官方文档说明反向播放脆弱且更慢，所以实验失败时必须保留
 * 当前 latest-only keyframe preview，不把一次属性试验偷偷升级为用户默认行为。实验
 * 在同一个已打开的 MediaKit Player 上记录反向期间的位置、cache、decoder/VO、硬解和
 * Texture 快照，并在 finally 中恢复方向、呈现属性与倍速。
 */
Future<Map<String, Object?>> _measureReverseDirectionExperiment(
  WidgetTester tester,
  PlayerBackend backend,
) async {
  final duration = backend.state.duration;
  final target = _fractionOf(duration, 0.72);
  final positions = <int>[];
  final baseline = <String, Object?>{};
  Map<String, Object?>? during;
  Map<String, Object?>? restored;
  var status = 'not-started';
  var failure = <String, Object?>{};
  var originalRate = 1.0;
  var originalDirection = 'forward';
  var originalWasPlaying = backend.state.playing;

  try {
    await backend.seek(target);
    await _waitForPosition(tester, backend, target);
    originalWasPlaying = backend.state.playing;
    await backend.play();
    final snapshot = await _readReverseSeekRuntimeSnapshot(backend);
    baseline.addAll(snapshot);
    final mpv = snapshot['mpv'] as Map<Object?, Object?>?;
    String read(String key) => (mpv?[key] ?? 'unavailable').toString();
    final parsedRate = double.tryParse(read('speed'));
    if (parsedRate != null && parsedRate.isFinite && parsedRate > 0) {
      originalRate = parsedRate;
    }
    originalDirection = read('play-direction');
    if (originalDirection.isEmpty || originalDirection == 'unavailable') {
      originalDirection = 'forward';
    }

    await backend.setProperty('play-direction', 'backward');
    await backend.setProperty('video-sync', 'audio');
    await backend.setProperty('interpolation', 'no');
    await backend.setProperty('framedrop', 'vo');
    await backend.setProperty('audio-pitch-correction', 'no');
    await backend.setRate(originalRate);
    await backend.play();
    status = 'running';

    for (var index = 0; index < 20; index++) {
      await tester.pump(const Duration(milliseconds: 100));
      positions.add(backend.state.position.inMilliseconds);
    }
    during = await _readReverseSeekRuntimeSnapshot(backend);
    final baselinePositionMs = target.inMilliseconds;
    final minimumPositionMs = positions.isEmpty
        ? null
        : positions.reduce((left, right) => left < right ? left : right);
    final backwardDistanceMs =
        minimumPositionMs == null ? 0 : baselinePositionMs - minimumPositionMs;
    final decreasingSampleCount =
        positions.where((position) => position < baselinePositionMs).length;
    status = backwardDistanceMs >= 250 && decreasingSampleCount >= 2
        ? 'decreasing-position-observed'
        : 'no-sustained-backward-position';
    failure = <String, Object?>{
      'propertyReadback': read('play-direction'),
      'duringPlayDirection':
          ((during['mpv'] as Map<Object?, Object?>?)?['play-direction'] ??
                  'unavailable')
              .toString(),
    };
  } catch (_) {
    status = 'property-or-playback-rejected';
    failure = const <String, Object?>{'kind': 'reverse-direction-unavailable'};
  } finally {
    // 实验无论成功与否都恢复当前会话；恢复失败只记录为 QA 失败，不让旧方向穿透
    // 后续 seek/播放测试。读取不到旧属性时，forward 是安全的正式默认值。
    try {
      await backend.setRate(originalRate);
      final baselineMpv = baseline['mpv'] as Map<Object?, Object?>?;
      for (final property in <String>[
        'audio-pitch-correction',
        'framedrop',
        'video-sync',
        'interpolation',
      ]) {
        final value = baselineMpv?[property]?.toString();
        if (value != null && value.isNotEmpty && value != 'unavailable') {
          await backend.setProperty(property, value);
        }
      }
      await backend.setProperty('play-direction', originalDirection);
      if (originalWasPlaying) {
        await backend.play();
      } else {
        await backend.pause();
      }
    } catch (_) {
      failure = <String, Object?>{
        ...failure,
        'restore': 'failed',
      };
    }
    restored = await _readReverseSeekRuntimeSnapshot(backend);
  }

  final baselineMpv = baseline['mpv'] as Map<Object?, Object?>?;
  final restoredMpv = restored['mpv'] as Map<Object?, Object?>?;
  final restoredDirection =
      (restoredMpv?['play-direction'] ?? 'unavailable').toString();
  final baselinePositionMs = target.inMilliseconds;
  final minimumPositionMs = positions.isEmpty
      ? null
      : positions.reduce((left, right) => left < right ? left : right);
  final maximumPositionMs = positions.isEmpty
      ? null
      : positions.reduce((left, right) => left > right ? left : right);
  final backwardDistanceMs =
      minimumPositionMs == null ? 0 : baselinePositionMs - minimumPositionMs;
  final decreasingSampleCount =
      positions.where((position) => position < baselinePositionMs).length;
  return <String, Object?>{
    'enabled': true,
    'status': status,
    'failure': failure,
    'evidence': 'backend-runtime-only',
    'targetPositionMs': target.inMilliseconds,
    'positionSamplesMs': positions,
    'minimumPositionMs': minimumPositionMs,
    'maximumPositionMs': maximumPositionMs,
    'backwardDistanceMs': backwardDistanceMs,
    'decreasingSampleCount': decreasingSampleCount,
    'originalDirection': baselineMpv?['play-direction'] ?? 'unavailable',
    'restoredDirection': restoredDirection,
    'restoredDirectionMatches': restoredDirection == originalDirection,
    'baselineRuntime': baseline,
    'duringRuntime': during,
    'restoredRuntime': restored,
  };
}

/**
 * 以正式 [PlayerKeyboardSeekController] 重放短按、长按前进与长按后退，不直接调用
 * 后端绕过输入策略。这里会先等待 coordinator 的位置确认再读取帧号代理，故它是
 * “控制器完成后的帧代理”回归指标，不能替代 Windows 输入到桌面像素的真实体验指标。
 */
Future<Map<String, Object?>> _measureKeyboardExperience(
  WidgetTester tester,
  PlayerBackend backend,
  PlayerSeekAudioGate playbackGate,
  _FramePresentationProbe presentation,
) async {
  final segmentTraceEnabled =
      Platform.environment['LOCAL_TAG_PLAYER_SEEK_SEGMENT_TRACE_QA'] == '1';
  final segmentTraceLines = <String>[];
  final segmentTrace = segmentTraceEnabled
      ? PlayerSeekTraceLogger(
          output: (line) {
            segmentTraceLines.add(line);
            debugPrint(line);
          },
        )
      : null;
  final keyboardPlaybackGate = segmentTraceEnabled
      ? _createAudioGate(tester, presentation, trace: segmentTrace)
      : playbackGate;
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
    // 关键帧预览的正式页面合同是命令返回即完成，不等待逻辑位置精确收敛；
    // 否则长 GOP 后退会在 750ms 容差之外人为等待默认 3 秒，重现旧的约 2.7s
    // “长尾”。最终画面仍由下面的帧代理等待单独计时，不能把位置确认伪装成呈现延迟。
    confirmationTimeout: Duration.zero,
    trace: segmentTrace,
    readTraceId: () => keyboardPlaybackGate.activeTraceId,
    readTraceRuntimeSnapshot: segmentTraceEnabled
        ? () => _readKeyboardScanRuntimeSnapshot(backend)
        : null,
    readPresentedFrame: presentation.readFrame,
    readFrameEvidence: () => presentation.lastEvidence,
  );
  PlayerKeyboardSeekController createKeyboard() => PlayerKeyboardSeekController(
        coordinator: coordinator,
        readPosition: () => backend.state.position,
        readDuration: () => backend.state.duration,
        isExiting: () => false,
        onLatency: (_) {},
        previewAudioGate: keyboardPlaybackGate,
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
        trace: segmentTrace,
        readScanTraceSnapshot: segmentTraceEnabled
            ? () => _readKeyboardScanRuntimeSnapshot(backend)
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
  if (segmentTraceEnabled) {
    await coordinator.flushTraceRuntimeSnapshots();
  }
  final smoothScanSummary = _summarizeSmoothScanTrace(segmentTraceLines);
  return <String, Object?>{
    'sampleCount': 7,
    'coordinatorCompletionThenFrameProxy': <String, Object?>{
      'shortForward': _summarizeLatency(shortForward),
      'shortBackward': _summarizeLatency(shortBackward),
      'longForwardScan': _summarizeLatency(longForward),
      'longBackwardPreview': _summarizeLatency(longBackward),
    },
    'frameEvidence': presentation.lastEvidence,
    'smoothScanTrace': <String, Object?>{
      'enabled': segmentTraceEnabled,
      'evidence': 'backend-runtime-snapshot-not-desktop-pixels',
      'summary': smoothScanSummary,
      'lines': segmentTraceLines,
    },
  };
}

/**
 * 将连续扫描的匿名运行态行收敛为可直接比较的阶段摘要。
 *
 * 原始行仍保留供审查；这里额外按 trace id 对齐 start/command/stop 和 runtime
 * 快照，避免把 cache 增长、VO 掉帧或恢复耗时埋在一条超长 JSON 日志里。该摘要只
 * 是后端运行态，不能升级为桌面 DWM 呈现证据。
 */
Map<String, Object?> _summarizeSmoothScanTrace(List<String> lines) {
  final eventsByTrace = <int, List<Map<String, String>>>{};
  for (final line in lines) {
    final marker = 'PLAYER_SEEK_TRACE ';
    final markerIndex = line.indexOf(marker);
    if (markerIndex < 0) continue;
    final fields = <String, String>{};
    for (final token in line
        .substring(markerIndex + marker.length)
        .trim()
        .split(RegExp(r'\s+'))) {
      final separator = token.indexOf('=');
      if (separator <= 0 || separator >= token.length - 1) continue;
      fields[token.substring(0, separator)] = token.substring(separator + 1);
    }
    final trace = int.tryParse(fields['trace'] ?? '');
    final stage = fields['stage'];
    final monoUs = int.tryParse(fields['mono_us'] ?? '');
    if (trace == null || stage == null || monoUs == null) continue;
    if (!stage.startsWith('smooth_scan_') &&
        stage != 'audio_restore_complete' &&
        stage != 'seek_command_complete' &&
        stage != 'seek_command_complete_runtime' &&
        stage != 'native_rendered_frame' &&
        stage != 'native_rendered_frame_runtime' &&
        stage != 'presented_frame_fallback' &&
        stage != 'presented_frame_fallback_runtime' &&
        stage != 'native_rendered_frame_timeout' &&
        stage != 'native_rendered_frame_timeout_runtime') {
      continue;
    }
    fields['__mono_us'] = '$monoUs';
    (eventsByTrace[trace] ??= <Map<String, String>>[]).add(fields);
  }

  int? timestamp(List<Map<String, String>> events, String stage) => events
      .where((event) => event['stage'] == stage)
      .map((event) => int.tryParse(event['__mono_us'] ?? ''))
      .whereType<int>()
      .firstOrNull;

  String? snapshot(List<Map<String, String>> events, String stage, String key) {
    final event =
        events.where((candidate) => candidate['stage'] == stage).firstOrNull;
    return event?['snapshot_$key'];
  }

  double? snapshotDouble(
    List<Map<String, String>> events,
    String stage,
    String key,
  ) =>
      double.tryParse(snapshot(events, stage, key) ?? '');

  int? snapshotInt(
    List<Map<String, String>> events,
    String stage,
    String key,
  ) =>
      int.tryParse(snapshot(events, stage, key) ?? '') ??
      double.tryParse(snapshot(events, stage, key) ?? '')?.round();

  final segments = <Map<String, Object?>>[];
  for (final entry in eventsByTrace.entries) {
    final events = entry.value
      ..sort((left, right) {
        final leftUs = int.tryParse(left['__mono_us'] ?? '') ?? 0;
        final rightUs = int.tryParse(right['__mono_us'] ?? '') ?? 0;
        return leftUs.compareTo(rightUs);
      });
    final startUs = timestamp(events, 'smooth_scan_start');
    final commandUs = timestamp(events, 'smooth_scan_command_complete');
    final stopStartUs = timestamp(events, 'smooth_scan_stop_start');
    final stopCompleteUs = timestamp(events, 'smooth_scan_stop_complete');
    if (startUs == null ||
        commandUs == null ||
        stopStartUs == null ||
        stopCompleteUs == null) {
      continue;
    }
    final restoreUs = timestamp(events, 'audio_restore_complete');
    const stopRuntimeStage = 'smooth_scan_stop_complete_runtime';
    segments.add(<String, Object?>{
      'traceId': entry.key,
      'startToCommandMs': (commandUs - startUs) / 1000,
      'commandToStopStartMs': (stopStartUs - commandUs) / 1000,
      'stopStartToCompleteMs': (stopCompleteUs - stopStartUs) / 1000,
      'commandToAudioRestoreMs':
          restoreUs == null ? null : (restoreUs - commandUs) / 1000,
      'cacheDurationAtStopCompleteS':
          snapshotDouble(events, stopRuntimeStage, 'cache_duration_s'),
      'decoderDropFramesAtStopComplete':
          snapshotInt(events, stopRuntimeStage, 'decoder_drop_frames'),
      'voDropFramesAtStopComplete':
          snapshotInt(events, stopRuntimeStage, 'vo_drop_frames'),
      'totalDropFramesAtStopComplete':
          snapshotInt(events, stopRuntimeStage, 'total_drop_frames'),
      'textureGenerationAtStopComplete':
          snapshot(events, stopRuntimeStage, 'texture_generation'),
      'hwdecAtStopComplete':
          snapshot(events, stopRuntimeStage, 'hwdec_current'),
      'frameEvidenceAtStopComplete':
          snapshot(events, stopRuntimeStage, 'frame_presentation_evidence'),
    });
  }

  // 反向 latest-only 预览没有 smooth_scan_* 生命周期；单独保留命令完成、首个后端
  // 帧和 timeout 的分段快照，避免 2.7 秒长尾再次被折叠成一个总耗时。
  final keyframeSegments = <Map<String, Object?>>[];
  for (final entry in eventsByTrace.entries) {
    final events = entry.value;
    final commandUs = timestamp(events, 'seek_command_complete');
    if (commandUs == null) continue;
    final frameEvent = events
        .where(
          (event) =>
              event['stage'] == 'native_rendered_frame' ||
              event['stage'] == 'presented_frame_fallback' ||
              event['stage'] == 'native_rendered_frame_timeout',
        )
        .firstOrNull;
    final frameUs =
        frameEvent == null ? null : int.tryParse(frameEvent['__mono_us'] ?? '');
    final frameStage = frameEvent?['stage'];
    String? stageSnapshot(String? stage, String key) =>
        stage == null ? null : snapshot(events, '${stage}_runtime', key);
    keyframeSegments.add(<String, Object?>{
      'traceId': entry.key,
      'commandCompleteUs': commandUs,
      'frameStage': frameStage,
      'commandToFrameStageMs':
          frameUs == null ? null : (frameUs - commandUs) / 1000,
      'cacheDurationAtCommandS': snapshotDouble(
          events, 'seek_command_complete_runtime', 'cache_duration_s'),
      'cacheDurationAtFrameS': stageSnapshot(frameStage, 'cache_duration_s'),
      'decoderDropFramesAtCommand': snapshotInt(
          events, 'seek_command_complete_runtime', 'decoder_drop_frames'),
      'voDropFramesAtCommand': snapshotInt(
          events, 'seek_command_complete_runtime', 'vo_drop_frames'),
      'textureGenerationAtCommand': snapshot(
          events, 'seek_command_complete_runtime', 'texture_generation'),
      'textureGenerationAtFrame':
          stageSnapshot(frameStage, 'texture_generation'),
      'hwdecAtCommand':
          snapshot(events, 'seek_command_complete_runtime', 'hwdec_current'),
      'hwdecAtFrame': stageSnapshot(frameStage, 'hwdec_current'),
      'frameEvidenceAtFrame':
          stageSnapshot(frameStage, 'frame_presentation_evidence'),
    });
  }

  double? maximum(String key) {
    final values = segments
        .map((segment) => segment[key])
        .whereType<num>()
        .map((value) => value.toDouble())
        .toList();
    if (values.isEmpty) return null;
    return values.reduce((left, right) => left > right ? left : right);
  }

  final totalStarts = eventsByTrace.values
      .where((events) =>
          events.any((event) => event['stage'] == 'smooth_scan_start'))
      .length;
  return <String, Object?>{
    'sampleCount': totalStarts,
    'successfulSamples': segments.length,
    'failedSamples': totalStarts - segments.length,
    'maxStartToCommandMs': maximum('startToCommandMs'),
    'maxCommandToStopStartMs': maximum('commandToStopStartMs'),
    'maxStopStartToCompleteMs': maximum('stopStartToCompleteMs'),
    'maxCommandToAudioRestoreMs': maximum('commandToAudioRestoreMs'),
    'maxCacheDurationAtStopCompleteS': maximum('cacheDurationAtStopCompleteS'),
    'maxTotalDropFramesAtStopComplete':
        maximum('totalDropFramesAtStopComplete'),
    'keyframeSegmentSampleCount': keyframeSegments.length,
    'keyframeSegments': keyframeSegments,
    'evidence': 'backend-runtime-snapshot-not-desktop-pixels',
    'segments': segments,
  };
}

/**
 * 模拟一次进度条拖动：同一次手势中的中间目标只保留 latest。此回归指标同样在
 * coordinator 完成后才读取帧号代理，不能冒充手势输入到实际像素的呈现时延。
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
    'coordinatorCompletionThenFrameProxy': _summarizeLatency(samples),
    'frameEvidence': presentation.lastEvidence,
  };
}

/**
 * 对同一真实后端执行多次“先到源位置、再向后 keyframe seek”的分段只读 trace。
 *
 * 每次采样先在暂停状态下把“源位置”的新帧交付到表面，才发起反向 seek。只确认
 * `state.position` 会让源位置 seek 与被测反向 seek 争用同一解码链，制造并不存在于
 * 单次用户输入的长尾。`commandToFrameProxyMs` 包含解码与后端交付，不等价于桌面已合成；报告中的
 * `desktop-composited-pixel-change` 必须由独立 Windows 像素探针给出。这里保留
 * demuxer cache、硬解、VO/decoder 掉帧和 Texture 快照，才能区分命令阻塞、定位
 * 收敛、后端新帧与 Flutter 合成之间的长尾，而不是把所有等待称为“seek 慢”。
 */
Future<Map<String, Object?>> _measureReverseKeyframeTrace(
  WidgetTester tester,
  PlayerBackend backend,
  _FramePresentationProbe presentation,
) async {
  final duration = backend.state.duration;
  final records = <Map<String, Object?>>[];
  final commandDurations = <int>[];
  final frameProxyDurations = <int>[];
  final keyframeLandingOffsets = <int>[];
  // trace 需要先消除正常播放帧的自然变化；否则“帧号变了”可能只是播放时钟前进，
  // 而不是刚刚提交的反向 seek 已经显示新画面。
  await backend.pause();
  await _pumpUntil(
    tester,
    () => !backend.state.playing,
    const Duration(seconds: 5),
    operation: '反向 seek trace 暂停静止画面',
  );
  for (final sourceFraction in <double>[
    0.82,
    0.71,
    0.63,
    0.54,
    0.46,
    0.37,
    0.29
  ]) {
    final source = _fractionOf(duration, sourceFraction);
    // 每个向后样本都从单独的中后段源位置发起，避免靠近 0 秒或 EOF 造成的无效结论。
    final target = source - const Duration(seconds: 5);
    if (target <= const Duration(seconds: 1)) continue;
    final sourceSetupWatch = Stopwatch()..start();
    final previousSourceFrame = await presentation.readFrame();
    await backend.seek(source);
    await _waitForPosition(tester, backend, source);
    // 只有这个帧代理已改变，才说明源位置帧已经在后端表面就绪；若它尚未交付，紧接着
    // 提交反向 seek 会测到人为的双随机访问队列，而不是用户单次反向输入。
    await presentation.waitForNewFrame(
      tester,
      previousSourceFrame,
      const Duration(seconds: 8),
    );
    await tester.pump(const Duration(milliseconds: 120));
    sourceSetupWatch.stop();
    final before = await _readReverseSeekRuntimeSnapshot(backend);
    final previousFrame = await presentation.readFrame();
    final watch = Stopwatch()..start();
    var commandMilliseconds = -1;
    var stateAcknowledgedAtCommand = false;
    var frameProxyMilliseconds = -1;
    String? failure;
    try {
      if (backend is PlayerInteractiveSeekBoundary) {
        await (backend as PlayerInteractiveSeekBoundary)
            .seekInteractive(target);
      } else {
        await backend.seek(target);
      }
      commandMilliseconds = watch.elapsedMilliseconds;
      // absolute+keyframes 可以立即把状态推进到请求目标，也可以很快改成前一关键帧。
      // 这是交互预览的语义，不可拿“750ms 内精确命中目标”当作成功条件。
      stateAcknowledgedAtCommand = (backend.state.position - target).abs() <=
          const Duration(milliseconds: 750);
      final postCommandSnapshotWatch = Stopwatch()..start();
      final postCommand = await _readReverseSeekRuntimeSnapshot(backend);
      postCommandSnapshotWatch.stop();
      final frameProxyWatch = Stopwatch()..start();
      await presentation.waitForNewFrame(
        tester,
        previousFrame,
        const Duration(seconds: 8),
      );
      frameProxyWatch.stop();
      frameProxyMilliseconds = watch.elapsedMilliseconds;
      final postFrameSnapshotWatch = Stopwatch()..start();
      final postFrame = await _readReverseSeekRuntimeSnapshot(backend);
      postFrameSnapshotWatch.stop();
      final keyframeLandingOffset = _keyframeLandingOffsetMilliseconds(
        postFrame,
        target,
      );
      final textureGenerationDelta = _textureGenerationDelta(before, postFrame);
      final runtimeDeltas = _reverseSeekRuntimeDeltas(
        before: before,
        postCommand: postCommand,
        postFrame: postFrame,
      );
      final segmentTrace = _reverseSeekSegmentTrace(
        commandCompleteMs: commandMilliseconds,
        frameProxyMs: frameProxyMilliseconds,
        frameProxyWaitMs: frameProxyWatch.elapsedMilliseconds,
        postCommandSnapshotMs: postCommandSnapshotWatch.elapsedMilliseconds,
        postFrameSnapshotMs: postFrameSnapshotWatch.elapsedMilliseconds,
        textureGenerationDelta: textureGenerationDelta,
        frameEvidence: presentation.lastEvidence,
        runtimeDeltas: runtimeDeltas,
      );
      commandDurations.add(commandMilliseconds);
      frameProxyDurations.add(frameProxyMilliseconds);
      if (keyframeLandingOffset != null) {
        keyframeLandingOffsets.add(keyframeLandingOffset);
      }
      records.add(<String, Object?>{
        'sourceMs': source.inMilliseconds,
        'targetMs': target.inMilliseconds,
        'sourceSetupFrameProxyMs': sourceSetupWatch.elapsedMilliseconds,
        'commandCompleteMs': commandMilliseconds,
        'stateAcknowledgedAtCommand': stateAcknowledgedAtCommand,
        'frameProxyMs': frameProxyMilliseconds,
        'frameEvidence': presentation.lastEvidence,
        // 负值表示关键帧预览合法地停在请求目标之前；这解释“画面跳跃”，但不能与
        // 首帧等待或桌面合成延迟混成同一个“卡顿毫秒数”。
        'keyframeLandingOffsetMs': keyframeLandingOffset,
        'textureGenerationDelta': textureGenerationDelta,
        // 不能用单个计数器给长尾归因：这里把 cache、decoder/VO 计数和 Texture
        // 代次明确分段，并保留 unavailable 而不是强制写零。
        'runtimeDeltas': runtimeDeltas,
        // segmentTrace 是供 QA/矩阵直接消费的分段视图；DWM 明确标为未观测，
        // 必须由独立桌面像素侧车补齐，不能把 backend frame proxy 当成屏幕呈现。
        'segmentTrace': segmentTrace,
        'before': before,
        'postCommand': postCommand,
        'postFrameProxy': postFrame,
      });
    } on TimeoutException catch (error) {
      failure = error.message?.toString() ?? 'timeout';
    } catch (error) {
      failure = error.toString();
    } finally {
      watch.stop();
    }
    if (failure != null) {
      records.add(<String, Object?>{
        'sourceMs': source.inMilliseconds,
        'targetMs': target.inMilliseconds,
        'sourceSetupFrameProxyMs': sourceSetupWatch.elapsedMilliseconds,
        'commandCompleteMs': commandMilliseconds,
        'stateAcknowledgedAtCommand': stateAcknowledgedAtCommand,
        'frameProxyMs': frameProxyMilliseconds,
        'frameEvidence': presentation.lastEvidence,
        'failure': failure,
        'before': before,
        'afterFailure': await _readReverseSeekRuntimeSnapshot(backend),
      });
    }
  }
  return <String, Object?>{
    'evidence': 'backend-frame-proxy-not-desktop-pixels',
    'sampleCount': records.length,
    'successfulSamples': commandDurations.length,
    'commandComplete': _summarizeLatencyOrNull(commandDurations),
    'commandToFrameProxy': _summarizeLatencyOrNull(frameProxyDurations),
    'keyframeLandingOffset': keyframeLandingOffsets.isEmpty
        ? null
        : <String, int>{
            // 负数即首帧停在目标之前；越小代表 GOP 的可见跳跃越大。
            'earliestOffsetMs': keyframeLandingOffsets.reduce(
              (left, right) => left < right ? left : right,
            ),
            'latestOffsetMs': keyframeLandingOffsets.reduce(
              (left, right) => left > right ? left : right,
            ),
          },
    'records': records,
  };
}

/**
 * 将反向 seek 的三次运行态快照和两个时钟边界整理成分段证据。
 *
 * cache/decoder/VO 来自 before、postCommand、postFrameProxy 的属性快照与计数差；
 * texture 来自首个后端帧代理和 Texture 代次；DWM 不在 integration_test 中观测，
 * 明确写 unavailable，等待独立 Windows 像素门禁按 UTC/QPC 侧车关联。
 */
Map<String, Object?> _reverseSeekSegmentTrace({
  required int commandCompleteMs,
  required int frameProxyMs,
  required int frameProxyWaitMs,
  required int postCommandSnapshotMs,
  required int postFrameSnapshotMs,
  required int? textureGenerationDelta,
  required String frameEvidence,
  required Map<String, Object?> runtimeDeltas,
}) {
  return <String, Object?>{
    'timing': <String, int?>{
      'seekCommandCompleteMs': commandCompleteMs,
      'commandToFrameProxyMs': frameProxyMs,
      'frameProxyWaitMs': frameProxyWaitMs,
      'postCommandRuntimeSnapshotMs': postCommandSnapshotMs,
      'postFrameRuntimeSnapshotMs': postFrameSnapshotMs,
    },
    'cache': runtimeDeltas['cache'],
    'decoderVo': runtimeDeltas['decodeAndVoDrops'],
    'effectivePipeline': runtimeDeltas['effectivePipeline'],
    'texture': <String, Object?>{
      'frameProxyEvidence': frameEvidence,
      'textureGenerationDelta': textureGenerationDelta,
      'surfaceObservedAtFrameProxy': true,
    },
    'dwm': const <String, Object?>{
      'evidence': 'unavailable-in-integration-test',
      'requiresDesktopPixelCorrelation': true,
    },
  };
}

/**
 * 连续扫描 trace 使用的固定字段扁平快照；它只来自同一后端，不代表桌面像素呈现。
 */
Future<Map<String, String>> _readKeyboardScanRuntimeSnapshot(
  PlayerBackend backend,
) async {
  final snapshot = await _readReverseSeekRuntimeSnapshot(backend);
  final mpv = snapshot['mpv'] as Map<Object?, Object?>? ?? const {};
  final texture = snapshot['texture'] as Map<Object?, Object?>? ?? const {};
  String readMpv(String property) =>
      (mpv[property] ?? 'unavailable').toString();
  String readTexture(String property) =>
      (texture[property] ?? 'unavailable').toString();
  return <String, String>{
    'cache_duration_s': readMpv('demuxer-cache-duration'),
    'cache_buffering_state': readMpv('cache-buffering-state'),
    'decoder_drop_frames': readMpv('decoder-frame-drop-count'),
    'vo_drop_frames': readMpv('vo-drop-frame-count'),
    'total_drop_frames': readMpv('frame-drop-count'),
    'mistimed_frames': readMpv('mistimed-frame-count'),
    'vo_delayed_frames': readMpv('vo-delayed-frame-count'),
    'hwdec_current': readMpv('hwdec-current'),
    'current_vo': readMpv('current-vo'),
    'video_sync': readMpv('video-sync'),
    'interpolation': readMpv('interpolation'),
    'framedrop': readMpv('framedrop'),
    'texture_supported': readTexture('supported'),
    'texture_generation': readTexture('textureGenerationCount'),
    'texture_width_px': readTexture('textureWidthPx'),
    'texture_height_px': readTexture('textureHeightPx'),
    'texture_resize_state': readTexture('textureResizeState'),
    'frame_presentation_evidence': snapshot['backend'] is Map<Object?, Object?>
        ? (snapshot['backend'] as Map<Object?, Object?>)['firstFrameEvidence']
                ?.toString() ??
            'unavailable'
        : 'unavailable',
  };
}

/** 读取路径无关的原生运行态；读取失败也保留 `unavailable`，不能用空值掩盖。 */
Future<Map<String, Object?>> _readReverseSeekRuntimeSnapshot(
  PlayerBackend backend,
) async {
  const properties = <String>[
    'time-pos',
    'speed',
    'estimated-frame-number',
    'hwdec-current',
    'current-vo',
    'video-sync',
    'interpolation',
    'framedrop',
    'audio-pitch-correction',
    'play-direction',
    'demuxer-cache-duration',
    'cache-buffering-state',
    'decoder-frame-drop-count',
    'vo-drop-frame-count',
    'frame-drop-count',
    'mistimed-frame-count',
    'vo-delayed-frame-count',
  ];
  final values = await Future.wait<String>(
    properties.map((property) async {
      try {
        return await backend.getProperty(property);
      } catch (_) {
        return 'unavailable';
      }
    }),
  );
  final mpv = <String, String>{
    for (var index = 0; index < properties.length; index++)
      properties[index]: values[index],
  };
  final surface = backend is PlayerVideoSurfaceDiagnosticsBoundary
      ? (backend as PlayerVideoSurfaceDiagnosticsBoundary)
          .videoSurfaceDiagnostics
          .toJson()
      : const <String, Object?>{'supported': false};
  final telemetry = backend is PlayerBackendTelemetryBoundary
      ? (backend as PlayerBackendTelemetryBoundary).telemetry
      : null;
  return <String, Object?>{
    'mpv': mpv,
    'texture': surface,
    'backend': <String, Object?>{
      'telemetrySupported': telemetry?.supported ?? false,
      'openGeneration': telemetry?.openGeneration,
      'hwdecCurrent': telemetry?.hwdecCurrent,
      'firstFrameEvidence': telemetry?.firstFrameEvidence,
    },
  };
}

/**
 * 从三个时点的只读快照生成可直接比较的运行时差分。
 *
 * `postCommand` 代表 native seek Future 已返回、后端帧代理尚未确认的边界；`postFrame`
 * 代表帧代理变化后的边界。桌面最终呈现由独立像素探针负责，因此不把此处的零代次差
 * 写成“没有合成开销”。
 */
Map<String, Object?> _reverseSeekRuntimeDeltas({
  required Map<String, Object?> before,
  required Map<String, Object?> postCommand,
  required Map<String, Object?> postFrame,
}) {
  String readMpv(Map<String, Object?> snapshot, String property) =>
      ((snapshot['mpv'] as Map<Object?, Object?>?)?[property] ?? 'unavailable')
          .toString();

  int? readInt(Map<String, Object?> snapshot, String property) =>
      int.tryParse(readMpv(snapshot, property)) ??
      double.tryParse(readMpv(snapshot, property))?.round();

  int? delta(String property) {
    final initial = readInt(before, property);
    final finalValue = readInt(postFrame, property);
    if (initial == null || finalValue == null) return null;
    return finalValue - initial;
  }

  return <String, Object?>{
    'cache': <String, String>{
      'beforeDuration': readMpv(before, 'demuxer-cache-duration'),
      'postCommandDuration': readMpv(postCommand, 'demuxer-cache-duration'),
      'postFrameDuration': readMpv(postFrame, 'demuxer-cache-duration'),
      'beforeBufferingState': readMpv(before, 'cache-buffering-state'),
      'postCommandBufferingState':
          readMpv(postCommand, 'cache-buffering-state'),
      'postFrameBufferingState': readMpv(postFrame, 'cache-buffering-state'),
    },
    'decodeAndVoDrops': <String, int?>{
      'decoderFrameDropDelta': delta('decoder-frame-drop-count'),
      'voDropDelta': delta('vo-drop-frame-count'),
      'totalFrameDropDelta': delta('frame-drop-count'),
      'mistimedFrameDelta': delta('mistimed-frame-count'),
      'voDelayedFrameDelta': delta('vo-delayed-frame-count'),
    },
    'effectivePipeline': <String, String>{
      'hwdecBefore': readMpv(before, 'hwdec-current'),
      'hwdecPostFrame': readMpv(postFrame, 'hwdec-current'),
      'voBefore': readMpv(before, 'current-vo'),
      'voPostFrame': readMpv(postFrame, 'current-vo'),
      'videoSyncBefore': readMpv(before, 'video-sync'),
      'videoSyncPostFrame': readMpv(postFrame, 'video-sync'),
      'frameDropPolicyBefore': readMpv(before, 'framedrop'),
      'frameDropPolicyPostFrame': readMpv(postFrame, 'framedrop'),
    },
  };
}

/** 从 trace 快照读取实际落点；空/不支持属性不伪造为零毫秒。 */
int? _keyframeLandingOffsetMilliseconds(
  Map<String, Object?> snapshot,
  Duration target,
) {
  final seconds = double.tryParse(
    ((snapshot['mpv'] as Map<Object?, Object?>?)?['time-pos'] ?? '').toString(),
  );
  if (seconds == null || !seconds.isFinite) return null;
  return (seconds * Duration.millisecondsPerSecond).round() -
      target.inMilliseconds;
}

/** Texture generation 只在可读的两个快照间计算，避免 unsupported 被误报为零重建。 */
int? _textureGenerationDelta(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  int? read(Map<String, Object?> snapshot) {
    final texture = snapshot['texture'] as Map<Object?, Object?>?;
    final raw = texture?['textureGenerationCount'];
    return raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  }

  final previous = read(before);
  final current = read(after);
  if (previous == null || current == null) return null;
  return current - previous;
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

/** 失败样本不能虚构 p50/p95；空集合以 null 显式保留。 */
Map<String, int>? _summarizeLatencyOrNull(List<int> samples) =>
    samples.isEmpty ? null : _summarizeLatency(samples);

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
  _FramePresentationProbe presentation, {
  PlayerSeekTraceLogger? trace,
}) =>
    PlayerSeekAudioGate(
      readDesiredVolume: () => 100,
      setVolume: presentation.backend.setVolume,
      readPresentedFrame: presentation.readFrame,
      waitForNewFrame: (previousFrame, timeout) =>
          presentation.waitForNewFrame(tester, previousFrame, timeout),
      framePresentationTimeout: () => const Duration(milliseconds: 1800),
      isExiting: () => false,
      readFrameEvidence: () => presentation.lastEvidence,
      trace: trace,
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
      // child HWND 同样会维护 native-rendered-frames，但它不经过 Flutter
      // Texture 复制；必须把两种原生输出证据分开，避免把 HWND 的 native render
      // 计数误报成正式 Texture 已呈现。
      lastEvidence = usesChildHwnd
          ? 'native-rendered-child-hwnd'
          : 'native-rendered-texture';
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
