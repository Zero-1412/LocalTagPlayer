import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/src/app.dart';
import 'package:local_tag_player/src/features/player/application/player_fullscreen_lifecycle_controller.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 使用隔离样本验证本机视频插件的真实 Windows 页面挂载。
 *
 * 测试不读取用户媒体库、不写播放设置；外部环境负责选择实验后端、绝对插件路径
 * 与可选故障注入，本测试只点击正式齿轮/诊断入口并验证播放继续推进。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('本机视频增强插件真实播放与回退', (tester) async {
    final samplePath =
        Platform.environment['LOCAL_TAG_PLAYER_VIDEO_PLUGIN_SAMPLE']?.trim();
    final outputPath =
        Platform.environment['LOCAL_TAG_PLAYER_VIDEO_PLUGIN_OUTPUT']?.trim();
    final expectFailure =
        Platform.environment['LOCAL_TAG_PLAYER_VIDEO_PLUGIN_EXPECT_FAILURE'] ==
            '1';
    if (samplePath == null ||
        samplePath.isEmpty ||
        !File(samplePath).existsSync()) {
      throw StateError('缺少本机视频插件隔离样本');
    }
    if (outputPath == null || outputPath.isEmpty) {
      throw StateError('缺少本机视频插件 QA 输出目录');
    }

    final output = Directory(outputPath)..createSync(recursive: true);
    final backend = WindowsNativePlayerBackend(mode: 'mpv');
    final thumbnailService = ThumbnailService.forDirectory(
      Directory('${output.path}\\thumbnail-cache'),
      DesktopFFmpegBackend(),
    );
    final item = VideoItem(
      videoId: 'local-video-plugin-smoke',
      path: samplePath,
      title: '本机视频插件隔离样本',
      folder: 'isolated-local-video-plugin',
      tags: const <String>{'QA'},
      addedAt: DateTime.utc(2026, 7, 27),
    );
    final disposalCompleter = Completer<void>();
    final playerKey = GlobalKey<PlayerPageState>();
    final captureKey = GlobalKey();

    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          home: PlayerPage(
            key: playerKey,
            initialItem: item,
            playlist: <VideoItem>[item],
            thumbnailService: thumbnailService,
            playbackSettings: PlaybackSettings.defaults,
            onPlaybackSettingsChanged: (_) async {},
            activeTags: const <String>['QA'],
            activeChildTag: null,
            queueTitle: '本机插件隔离 QA',
            onDeleteVideo: (_, __) async {},
            onToggleFavorite: (_) async {},
            onRenameFile: (_, __) async {},
            onEditManualTags: (_) async {},
            onRelinkMissing: (_) async => false,
            onPlaybackProgressUpdated: (_, __, ___, ____) async {},
            onMediaDetailsUpdated: (_, __, ___) async {},
            disposalCompleter: disposalCompleter,
            fileSystem: const DesktopFileSystemAdapter(),
            playerServiceFactory: ({
              required String hwdec,
              required bool enableHardwareAcceleration,
              required PlayerRendererPreference rendererPreference,
            }) =>
                PlayerService(backend: backend),
            mediaProbeBackendFactory: () =>
                createMediaProbeBackend(DesktopFFmpegBackend()),
            fullscreenSessionController: PlayerFullscreenSessionController(),
          ),
        ),
      ),
    );

    final expectedState = expectFailure ? 'process-failed' : 'active';
    await _pumpUntilProperty(
      tester,
      backend,
      'native-video-plugin-state',
      expectedState,
      const Duration(seconds: 30),
    );
    expect(
      await backend.getProperty('native-video-plugin-name'),
      'ltp-d3d11-round-trip-probe',
    );
    if (expectFailure) {
      expect(
        int.parse(
          await backend.getProperty('native-video-plugin-fallbacks'),
        ),
        greaterThanOrEqualTo(1),
      );
    } else {
      expect(
        int.parse(await backend.getProperty('native-video-plugin-frames')),
        greaterThan(0),
      );
    }

    // 故障后继续观察播放头，防止“回退”只停在诊断状态而实际视频已冻结。
    final before = backend.state.position;
    await _pumpContinuously(tester, const Duration(seconds: 2));
    expect(backend.state.position, greaterThan(before));
    expect(
      int.tryParse(await backend.getProperty('frame-drop-count')),
      0,
    );

    final videoSurface =
        find.byKey(const ValueKey<String>('player.video.surface'));
    final videoRect = tester.getRect(videoSurface);
    final controlsHotspot = Offset(videoRect.center.dx, videoRect.bottom - 40);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: controlsHotspot);
    await mouse.moveTo(controlsHotspot);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(
      find.byKey(const ValueKey<String>('player.settings')).hitTestable(),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.byKey(const ValueKey<String>('player.settings.dialog')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 350));
    await mouse.removePointer();

    // 正式诊断入口属于视频右键菜单；齿轮只验证播放器设置仍可达。
    final contextMenuGesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    final surfaceCenter = tester.getCenter(videoSurface);
    await contextMenuGesture.addPointer(location: surfaceCenter);
    await contextMenuGesture.down(surfaceCenter);
    await contextMenuGesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('诊断检查'));
    await _pumpContinuously(tester, const Duration(seconds: 2));

    final pluginStateLine = find
        .textContaining('本机增强插件: ltp-d3d11-round-trip-probe · $expectedState');
    expect(pluginStateLine, findsOneWidget);
    expect(find.textContaining('本机增强插件帧:'), findsOneWidget);
    final diagnosticsScroll = find.descendant(
      of: find.byKey(
        const ValueKey<String>('player.diagnostics.dialog'),
      ),
      matching: find.byType(SingleChildScrollView),
    );
    await tester.drag(diagnosticsScroll, const Offset(0, -1600));
    await tester.pump(const Duration(milliseconds: 250));
    await _captureBoundary(
      captureKey,
      File(
        '${output.path}\\${expectFailure ? 'fallback' : 'active'}-diagnostics.png',
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('player.diagnostics.close')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await contextMenuGesture.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await disposalCompleter.future.timeout(const Duration(seconds: 12));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/** 持续驱动真实 Windows 帧，直到指定原生诊断属性达到目标值。 */
Future<void> _pumpUntilProperty(
  WidgetTester tester,
  PlayerBackend backend,
  String property,
  String expected,
  Duration timeout,
) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 100));
    if (await backend.getProperty(property) == expected) return;
  }
  throw StateError(
    '等待 $property=$expected 超时，实际值 ${await backend.getProperty(property)}',
  );
}

/** 以短周期驱动 Flutter，确保播放头和原生轮询在等待期间持续运行。 */
Future<void> _pumpContinuously(
  WidgetTester tester,
  Duration duration,
) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < duration) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/** 保存正式页面的 Flutter 合成截图，供诊断弹窗位置、遮挡和对比度复核。 */
Future<void> _captureBoundary(GlobalKey key, File output) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('诊断截图编码失败');
  await output.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
}
