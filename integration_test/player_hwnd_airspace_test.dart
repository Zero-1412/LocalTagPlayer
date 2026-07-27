import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/src/app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 使用匿名低码率样本验证 Flutter child HWND、D3D11VA 与正式播放器页面挂载。
 *
 * 测试不读取用户媒体库，也不改变播放设置；外部脚本可通过手动观察窗口的等待时间
 * 完成真实鼠标 airspace QA。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('child HWND 非 copy 硬解与 airspace 门禁', (tester) async {
    final samplePath =
        Platform.environment['LOCAL_TAG_PLAYER_HWND_SAMPLE']?.trim();
    final outputPath =
        Platform.environment['LOCAL_TAG_PLAYER_HWND_OUTPUT']?.trim();
    final manualSeconds = int.tryParse(
          Platform.environment['LOCAL_TAG_PLAYER_HWND_MANUAL_SECONDS'] ?? '',
        ) ??
        0;
    if (samplePath == null ||
        samplePath.isEmpty ||
        !File(samplePath).existsSync()) {
      throw StateError('缺少 child HWND 匿名 QA 片源');
    }
    if (outputPath == null || outputPath.isEmpty) {
      throw StateError('缺少 child HWND QA 输出目录');
    }

    final output = Directory(outputPath)..createSync(recursive: true);
    File('${output.path}\\process.pid')
        .writeAsStringSync(pid.toString(), flush: true);
    final backend = WindowsNativePlayerBackend(mode: 'hwnd');
    final thumbnailService = ThumbnailService.forDirectory(
      Directory('${output.path}\\thumbnail-cache'),
      DesktopFFmpegBackend(),
    );
    final item = VideoItem(
      videoId: 'child-hwnd-airspace',
      path: samplePath,
      title: 'child HWND 隔离样本',
      folder: 'isolated-child-hwnd',
      tags: const <String>{'QA'},
      addedAt: DateTime.utc(2026, 7, 27),
    );
    final disposalCompleter = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          initialItem: item,
          playlist: <VideoItem>[item],
          thumbnailService: thumbnailService,
          // HWND 门禁必须固定非 copy D3D11VA，避免默认设置在页面初始化后覆写原生选项。
          playbackSettings:
              PlaybackSettings.defaults.copyWith(hwdec: 'd3d11va'),
          onPlaybackSettingsChanged: (_) async {},
          activeTags: const <String>['QA'],
          activeChildTag: null,
          queueTitle: 'child HWND airspace QA',
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
          }) =>
              PlayerService(backend: backend),
          mediaProbeBackendFactory: () =>
              createMediaProbeBackend(DesktopFFmpegBackend()),
          fullscreenSessionController: PlayerFullscreenSessionController(),
        ),
      ),
    );

    await _pumpUntilProperty(
      tester,
      backend,
      'hwdec-current',
      'd3d11va',
      const Duration(seconds: 30),
    );
    await _pumpUntilProperty(
      tester,
      backend,
      'native-surface-visible',
      'true',
      const Duration(seconds: 10),
    );
    // 物理点击阶段可能包含构建与截图等待；循环隔离样本，避免结束态污染 airspace 结论。
    await backend.setProperty('loop-file', 'inf');
    expect(
        await backend.getProperty('current-vo'), 'gpu-next-d3d11-child-hwnd');
    expect(await backend.getProperty('native-surface-kind'), 'child-hwnd');
    expect(await backend.getProperty('native-input-forwarding'), 'true');
    expect(
      await backend.getProperty('native-input-mode'),
      'hit-test-transparent',
    );
    expect(await backend.getProperty('native-texture-copies'), '0');

    final before = backend.state.position;
    await _pumpContinuously(tester, const Duration(seconds: 3));
    expect(backend.state.position, greaterThan(before));
    expect(int.tryParse(await backend.getProperty('frame-drop-count')), 0);

    // 页面级挂载证明正式控制条和设置对话框仍在 Flutter 树中；真实 HWND 命中测试
    // 由外部可见窗口阶段使用物理鼠标复核，不能用 tester.tap 冒充 airspace 结论。
    final videoSurface =
        find.byKey(const ValueKey<String>('player.video.surface'));
    final videoRect = tester.getRect(videoSurface);
    final controlsHotspot = Offset(videoRect.center.dx, videoRect.bottom - 40);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: controlsHotspot);
    await mouse.moveTo(controlsHotspot);
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(const ValueKey<String>('player.settings')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('player.settings')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('player.settings.dialog')),
      findsOneWidget,
    );
    expect(await backend.getProperty('native-surface-occluded'), 'true');
    expect(await backend.getProperty('native-surface-visible'), 'false');
    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('player.settings.dialog')),
      findsNothing,
    );
    expect(await backend.getProperty('native-surface-occluded'), 'false');
    expect(await backend.getProperty('native-surface-visible'), 'true');

    final readyPath = '${output.path}\\ready.json';
    File(readyPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schemaVersion': 1,
        'status': 'ready-for-physical-click',
        'backend': 'windows-native-hwnd',
        'expectedHwdec': 'd3d11va',
        'expectedTextureCopies': 0,
        'surfaceLeft': await backend.getProperty('native-surface-left'),
        'surfaceTop': await backend.getProperty('native-surface-top'),
        'surfaceWidth': await backend.getProperty('native-surface-width'),
        'surfaceHeight': await backend.getProperty('native-surface-height'),
        'topAirspace': await backend.getProperty('native-airspace-inset-top'),
        'bottomAirspace':
            await backend.getProperty('native-airspace-inset-bottom'),
      }),
      flush: true,
    );
    if (manualSeconds > 0) {
      await _pumpContinuously(tester, Duration(seconds: manualSeconds));
    }

    final report = <String, Object?>{
      'schemaVersion': 1,
      'backend': 'windows-native-hwnd',
      'currentVo': await backend.getProperty('current-vo'),
      'hwdecCurrent': await backend.getProperty('hwdec-current'),
      'surfaceKind': await backend.getProperty('native-surface-kind'),
      'surfaceVisible': await backend.getProperty('native-surface-visible'),
      'surfaceOccluded': await backend.getProperty('native-surface-occluded'),
      'inputForwarding': await backend.getProperty('native-input-forwarding'),
      'inputMode': await backend.getProperty('native-input-mode'),
      'textureCopies':
          int.tryParse(await backend.getProperty('native-texture-copies')),
      'frameDropCount':
          int.tryParse(await backend.getProperty('frame-drop-count')),
      'positionMs': backend.state.position.inMilliseconds,
      'controlsMounted': find
          .byKey(const ValueKey<String>('player.settings'))
          .evaluate()
          .isNotEmpty,
    };
    File('${output.path}\\result.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );

    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await disposalCompleter.future.timeout(const Duration(seconds: 12));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/** 持续驱动真实 Windows 帧，直到指定原生属性达到目标值。 */
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
  final lifecycle = await backend.getProperty('native-lifecycle');
  throw StateError(
    '等待 $property=$expected 超时，实际值 ${await backend.getProperty(property)}，'
    '生命周期 $lifecycle',
  );
}

/** 以短周期驱动 Flutter 与原生轮询，避免长等待期间冻结测试窗口。 */
Future<void> _pumpContinuously(WidgetTester tester, Duration duration) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < duration) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
