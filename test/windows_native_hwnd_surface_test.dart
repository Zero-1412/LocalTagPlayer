import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/services/player/windows_gpu_capability_channel.dart';
import 'package:local_tag_player/src/services/player/windows_native_player_backend.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 验证 child HWND 原型只在显式后端模式挂载，并把 Flutter 逻辑布局转换为物理矩形。
 */
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HWND 占位面保留控制区并同步原生矩形', (tester) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windowsNativePlayerChannel,
        (call) async {
      calls.add(call);
      if (call.method == 'command') {
        return null;
      }
      if (call.method == 'create' || call.method == 'state') {
        return <String, Object?>{
          'textureId': -1,
          'positionMs': 0,
          'durationMs': 1000,
          'playing': false,
          'buffering': false,
          'volume': 100.0,
          'lifecycle': 'mpv_hwnd_ready',
          'native-surface-kind': 'child-hwnd',
          'mpv-version': 'mpv 0.41.0',
          'vf': 'd3d11vpp=scale=2:scaling-mode=nvidia:format=nv12',
          'deband': 'no',
          'deband-iterations': '1',
          'deband-threshold': '24',
          'deband-range': '12',
          'deband-grain': '8',
          'native-nvidia-vsr-state': 'active',
          'native-nvidia-hdr-state': 'active',
          'video-params/primaries': 'bt.709',
          'video-params/gamma': 'bt.1886',
          'video-params/colorlevels': 'limited',
          'video-params/colormatrix': 'bt.709',
          'video-output-levels': 'full',
          'video-target-params/colorlevels': 'full',
          'video-params/w': 1920,
          'video-params/h': 1080,
          'video-sync': 'display-resample',
          'interpolation': 'yes',
          'tscale': 'oversample',
          'display-sync-active': 'true',
        };
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(windowsNativePlayerChannel, null);
    });

    final backend = WindowsNativePlayerBackend(mode: 'hwnd');
    addTearDown(backend.dispose);
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: backend.buildVideoSurface(
            reserveBottomControlArea: true,
            controls: const Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                key: ValueKey<String>('protected-controls'),
                height: 96,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.byKey(
        const ValueKey<String>('windows-native.hwnd.placeholder'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('protected-controls')),
      findsOneWidget,
    );
    final rectCall = calls.lastWhere((call) => call.method == 'setSurfaceRect');
    final arguments = rectCall.arguments! as Map<Object?, Object?>;
    expect(arguments['left'], 0);
    expect(arguments['top'], 0);
    expect(arguments['width'], 800);
    expect(arguments['height'], 600);
    expect(arguments['viewWidth'], 800);
    expect(arguments['viewHeight'], 600);
    expect(arguments['airspaceTop'], 0);
    expect(arguments['airspaceBottom'], 128);
    expect(arguments['visible'], isTrue);
    expect(
        await backend.getProperty('current-vo'), 'gpu-next-d3d11-child-hwnd');
    expect(await backend.getProperty('mpv-version'), 'mpv 0.41.0');
    expect(await backend.getProperty('vf'), contains('scaling-mode=nvidia'));
    expect(await backend.getProperty('deband'), 'no');
    expect(await backend.getProperty('deband-iterations'), '1');
    expect(await backend.getProperty('deband-threshold'), '24');
    expect(await backend.getProperty('deband-range'), '12');
    expect(await backend.getProperty('deband-grain'), '8');
    expect(
      await backend.getProperty('native-nvidia-vsr-state'),
      'active',
    );
    expect(
      await backend.getProperty('native-nvidia-hdr-state'),
      'active',
    );
    expect(await backend.getProperty('video-params/primaries'), 'bt.709');
    expect(await backend.getProperty('video-params/gamma'), 'bt.1886');
    expect(await backend.getProperty('video-params/colorlevels'), 'limited');
    expect(await backend.getProperty('video-params/colormatrix'), 'bt.709');
    expect(await backend.getProperty('video-output-levels'), 'full');
    expect(
      await backend.getProperty('video-target-params/colorlevels'),
      'full',
    );
    expect(await backend.getProperty('video-params/w'), '1920');
    expect(await backend.getProperty('video-params/h'), '1080');
    expect(await backend.getProperty('video-sync'), 'display-resample');
    expect(await backend.getProperty('interpolation'), 'yes');
    expect(await backend.getProperty('tscale'), 'oversample');
    expect(await backend.getProperty('display-sync-active'), 'true');

    // 控制条收起后 HWND 尺寸保持不变，只把窗口 region 的底部让位收窄到细进度条。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: backend.buildVideoSurface(
            controls: const Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                key: ValueKey<String>('protected-controls'),
                height: 96,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    final hiddenControlsRectCall =
        calls.lastWhere((call) => call.method == 'setSurfaceRect');
    final hiddenControlsArguments =
        hiddenControlsRectCall.arguments! as Map<Object?, Object?>;
    expect(hiddenControlsArguments['height'], 600);
    expect(hiddenControlsArguments['airspaceBottom'], 3);

    // 全屏顶部队列语境仍须避让，切换状态只改变原生矩形而不重建后端。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: backend.buildVideoSurface(
            reserveTopControlArea: true,
            reserveBottomControlArea: true,
            controls: const Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                key: ValueKey<String>('protected-controls'),
                height: 96,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    final fullscreenRectCall =
        calls.lastWhere((call) => call.method == 'setSurfaceRect');
    final fullscreenArguments =
        fullscreenRectCall.arguments! as Map<Object?, Object?>;
    expect(fullscreenArguments['top'], 0);
    expect(fullscreenArguments['height'], 600);
    expect(fullscreenArguments['airspaceTop'], 64);
    expect(fullscreenArguments['airspaceBottom'], 128);

    final rectCountBeforeDpiChange =
        calls.where((call) => call.method == 'setSurfaceRect').length;
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      calls.where((call) => call.method == 'setSurfaceRect').length,
      rectCountBeforeDpiChange + 1,
      reason: '跨 DPI 移窗即使逻辑尺寸不变，也必须触发原生物理矩形重算',
    );

    await backend.setProperty('hwdec', 'd3d11va-copy');
    final hwdecCommand = calls.lastWhere((call) => call.method == 'command');
    expect(
      hwdecCommand.arguments,
      containsPair('text', 'hwdec=d3d11va'),
    );

    await backend.setFlutterOverlayVisible(
      true,
      overlayRect: const Rect.fromLTWH(500, 120, 260, 240),
      viewSize: const Size(800, 600),
    );
    await backend.setFlutterOverlayVisible(false);
    final occlusionCalls =
        calls.where((call) => call.method == 'setSurfaceOccluded').toList();
    expect(occlusionCalls, hasLength(2));
    expect(
      (occlusionCalls.first.arguments! as Map<Object?, Object?>)['occluded'],
      isTrue,
    );
    expect(occlusionCalls.first.arguments, containsPair('partial', true));
    expect(occlusionCalls.first.arguments, containsPair('overlayLeft', 500));
    expect(
      (occlusionCalls.last.arguments! as Map<Object?, Object?>)['occluded'],
      isFalse,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await backend.dispose();
    expect(
      calls.where((call) => call.method == 'dispose'),
      hasLength(1),
    );
  });

  test('MPV Texture 将 D3D11VA 请求收敛为 copy-back 硬解', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windowsNativePlayerChannel,
        (call) async {
      calls.add(call);
      if (call.method == 'create' || call.method == 'state') {
        return <String, Object?>{
          'textureId': 7,
          'positionMs': 0,
          'durationMs': 1000,
          'playing': false,
          'buffering': false,
          'volume': 100.0,
          'lifecycle': 'mpv_texture_ready',
        };
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(windowsNativePlayerChannel, null);
    });

    final backend = WindowsNativePlayerBackend(mode: 'mpv');
    await backend.setProperty('hwdec', 'd3d11va');
    final command = calls.lastWhere((call) => call.method == 'command');
    expect(command.arguments, containsPair('text', 'hwdec=d3d11va-copy'));

    await backend.setProperties(const <String, String>{
      'hwdec': 'd3d11va',
      'vf': '',
    });
    final batch = calls.lastWhere((call) => call.method == 'setProperties');
    final properties = (batch.arguments as Map<Object?, Object?>)['properties']
        as List<Object?>;
    expect(properties, hasLength(2));
    expect(
      properties.first,
      containsPair('value', 'd3d11va-copy'),
    );
    expect(properties.last, containsPair('property', 'vf'));
    await backend.dispose();
  });
}
