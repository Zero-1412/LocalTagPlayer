import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/src/features/player/application/player_seek_coordinator.dart';
import 'package:local_tag_player/src/platform/platform_interfaces.dart';
import 'package:local_tag_player/src/services/player/media_kit_player_backend.dart';
import 'package:local_tag_player/src/services/player/player_hardware_acceleration.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 为 Windows 桌面像素探针提供真实的正式 Texture 会话。
 *
 * 测试本身不伪造 seek 输入：它只在实际 Debug 窗口中挂载正式 `MediaKitPlayerBackend`、
 * 打开匿名本地样本并暂停。外部 `invoke_player_desktop_pixel_probe.ps1` 必须在同一进程
 * 标题/PID 上发送 Win32 键盘事件，然后从桌面合成结果读取像素变化。这样可以明确区分
 * Flutter 测试泵、libmpv 帧号代理和用户实际可见的新画面。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('正式 Texture 的输入到桌面像素呈现门禁', (tester) async {
    final samplePath = _requiredEnvironment('LOCAL_TAG_PLAYER_PIXEL_SAMPLE');
    final outputRoot = _requiredEnvironment('LOCAL_TAG_PLAYER_PIXEL_OUTPUT');
    final windowTitle =
        Platform.environment['LOCAL_TAG_PLAYER_PIXEL_WINDOW_TITLE']?.trim() ??
            'LocalTagPlayer Desktop Pixel QA';
    final requestedSamples = int.tryParse(
          Platform.environment['LOCAL_TAG_PLAYER_PIXEL_SAMPLES'] ?? '',
        ) ??
        7;
    final optionalP95Budget = int.tryParse(
      Platform.environment['LOCAL_TAG_PLAYER_PIXEL_P95_BUDGET_MS'] ?? '',
    );
    if (!File(samplePath).existsSync()) {
      throw StateError('桌面像素门禁样本不存在');
    }
    final outputDirectory = Directory(outputRoot);
    if (!outputDirectory.existsSync()) {
      throw StateError('桌面像素门禁输出根目录不存在');
    }

    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();
    await windowManager.setTitle(windowTitle);

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
    final focusNode = FocusNode(debugLabel: 'desktop-pixel-qa-input');
    addTearDown(focusNode.dispose);
    final keyboard = _createKeyboardSeekController(backend);
    final inputEventsPath =
        '${outputDirectory.path}${Platform.pathSeparator}received-key-events.jsonl';

    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Focus(
            autofocus: true,
            focusNode: focusNode,
            onKeyEvent: (_, event) {
              // 专用进程不接收用户文本；记录全部到达 Focus 的键可区分“注入未抵达”与
              // “抵达后策略未处理”，同时不保存视频内容或路径。
              File(inputEventsPath).writeAsStringSync(
                '${jsonEncode(<String, Object?>{
                      'event': event.runtimeType.toString(),
                      'logicalKey': event.logicalKey.keyLabel,
                      'physicalKey': event.physicalKey.debugName,
                      'utcUs': DateTime.now().toUtc().microsecondsSinceEpoch,
                    })}\n',
                mode: FileMode.append,
                flush: true,
              );
              final result = _handleSeekKeyEvent(keyboard, event);
              return result;
            },
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                backend.buildVideoSurface(
                  controls: const SizedBox.expand(),
                  fit: BoxFit.contain,
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: 220,
                      height: 48,
                      child: Listener(
                        onPointerDown: (_) => _appendInputEvidence(
                          inputEventsPath,
                          'pointer_down',
                        ),
                        onPointerUp: (_) => _appendInputEvidence(
                          inputEventsPath,
                          'pointer_up',
                        ),
                        child: ElevatedButton(
                          key: const ValueKey<String>(
                            'desktop-pixel-qa.seek-backward',
                          ),
                          onPressed: () async {
                            // 专用 QA 鼠标入口与正式拖动相同地使用交互式关键帧语义；
                            // 只用于把真实 Win32 点击与桌面像素对齐，不写用户位置或设置。
                            final target = backend.state.position -
                                const Duration(seconds: 5);
                            _appendInputEvidence(
                              inputEventsPath,
                              'pointer_seek_backward',
                              targetMilliseconds: target.inMilliseconds,
                            );
                            await backend.seekInteractive(
                              target > Duration.zero ? target : Duration.zero,
                            );
                          },
                          child: const Text('QA 反向交互 seek'),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    await backend.openPath(samplePath);
    await backend.play();
    await _pumpUntil(
      tester,
      () =>
          backend.textureId.value != null &&
          backend.state.duration > const Duration(seconds: 12) &&
          backend.state.position > const Duration(seconds: 7),
      const Duration(seconds: 30),
      operation: '正式 Texture 首帧与时长',
    );
    // 短按与快退的像素测量只能从静态画面开始，避免自然播放被误判为输入后首帧。
    await backend.pause();
    await _pumpUntil(
      tester,
      () => !backend.state.playing,
      const Duration(seconds: 5),
      operation: '暂停像素基线',
    );
    await tester.pump(const Duration(milliseconds: 400));

    final readyPath =
        '${outputDirectory.path}${Platform.pathSeparator}ready.json';
    File(readyPath).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'testProcessId': pid,
        'windowTitle': windowTitle,
        'backend': 'media-kit-flutter-texture',
        'state': 'paused-static-baseline-ready',
        'focusReady': focusNode.hasFocus,
        'textureGenerationCount':
            backend.videoSurfaceDiagnostics.textureGenerationCount,
      }),
      flush: true,
    );

    final reportPath =
        '${outputDirectory.path}${Platform.pathSeparator}desktop-pixels${Platform.pathSeparator}desktop-pixel-summary.json';
    final failurePath =
        '${outputDirectory.path}${Platform.pathSeparator}desktop-pixel-probe-failure.txt';
    await _pumpUntil(
      tester,
      () => File(reportPath).existsSync() || File(failurePath).existsSync(),
      const Duration(minutes: 4),
      operation: '外部桌面像素探针报告',
    );
    if (File(failurePath).existsSync()) {
      throw StateError(File(failurePath).readAsStringSync());
    }
    final summary =
        jsonDecode(File(reportPath).readAsStringSync()) as Map<String, Object?>;
    expect(summary['evidence'], 'desktop-composited-pixel-change');
    expect(summary['captureRatePassed'], isTrue);
    expect(summary['successfulSamples'], requestedSamples);
    expect(summary['timedOutSamples'], 0);
    final p95 = (summary['p95InputDownToPixelMs'] as num).toInt();
    if (optionalP95Budget != null) {
      expect(
        p95,
        lessThanOrEqualTo(optionalP95Budget),
        reason: '桌面像素 p95 超出该素材与动作的显式预算',
      );
    }
    // ignore: avoid_print
    print(
      'PLAYER_DESKTOP_PIXEL_GATE ${jsonEncode(<String, Object?>{
            'backend': 'media-kit-flutter-texture',
            'hwdec': await backend.getProperty('hwdec-current'),
            'textureGenerationCount':
                backend.videoSurfaceDiagnostics.textureGenerationCount,
            'desktop': summary,
          })}',
    );

    await backend.dispose();
    await backend.released;
    disposed = true;
  }, timeout: const Timeout(Duration(minutes: 6)));
}

/** 仅映射正式页面默认 `J/L`，外部输入必须经过 Flutter 的真实 KeyEvent 链。 */
KeyEventResult _handleSeekKeyEvent(
  PlayerKeyboardSeekController keyboard,
  KeyEvent event,
) {
  final direction = switch (event.logicalKey) {
    LogicalKeyboardKey.keyL => 1,
    LogicalKeyboardKey.keyJ => -1,
    _ => 0,
  };
  if (direction == 0) return KeyEventResult.ignored;
  if (event is KeyUpEvent) {
    unawaited(keyboard.settlePreview());
    return KeyEventResult.handled;
  }
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  keyboard.requestRelative(
    Duration(seconds: direction * (event is KeyRepeatEvent ? 2 : 5)),
    mutePreview: event is KeyRepeatEvent,
    isRepeat: event is KeyRepeatEvent,
  );
  return KeyEventResult.handled;
}

/** 保持和正式键盘策略相同的短按单次预览、前进长按扫描和后退 latest-only 合同。 */
PlayerKeyboardSeekController _createKeyboardSeekController(
  PlayerBackend backend,
) {
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
  return PlayerKeyboardSeekController(
    coordinator: coordinator,
    readPosition: () => backend.state.position,
    readDuration: () => backend.state.duration,
    isExiting: () => false,
    onLatency: (_) {},
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
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate,
  Duration timeout, {
  required String operation,
}) async {
  final watch = Stopwatch()..start();
  while (!predicate() && watch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 25));
  }
  if (!predicate()) throw TimeoutException('$operation 未在时限内完成', timeout);
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('桌面像素门禁缺少环境变量 $name');
  }
  return value;
}

/** 专用 QA 输入链证据；只存事件类型和匿名目标时间，不存像素、路径或用户文本。 */
void _appendInputEvidence(
  String path,
  String event, {
  int? targetMilliseconds,
}) {
  File(path).writeAsStringSync(
    '${jsonEncode(<String, Object?>{
          'event': event,
          'utcUs': DateTime.now().toUtc().microsecondsSinceEpoch,
          if (targetMilliseconds != null) 'targetMs': targetMilliseconds,
        })}\n',
    mode: FileMode.append,
    flush: true,
  );
}
