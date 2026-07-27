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
          'native-nvidia-vsr-state': 'active',
          'native-nvidia-hdr-state': 'active',
          'video-params/primaries': 'bt.709',
          'video-params/gamma': 'bt.1886',
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
    expect(arguments['top'], 64);
    expect(arguments['width'], 800);
    expect(arguments['height'], 408);
    expect(arguments['viewWidth'], 800);
    expect(arguments['viewHeight'], 600);
    expect(arguments['visible'], isTrue);
    expect(
        await backend.getProperty('current-vo'), 'gpu-next-d3d11-child-hwnd');
    expect(await backend.getProperty('mpv-version'), 'mpv 0.41.0');
    expect(await backend.getProperty('vf'), contains('scaling-mode=nvidia'));
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
    expect(await backend.getProperty('video-sync'), 'display-resample');
    expect(await backend.getProperty('interpolation'), 'yes');
    expect(await backend.getProperty('tscale'), 'oversample');
    expect(await backend.getProperty('display-sync-active'), 'true');

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

    await backend.setFlutterOverlayVisible(true);
    await backend.setFlutterOverlayVisible(false);
    final occlusionCalls =
        calls.where((call) => call.method == 'setSurfaceOccluded').toList();
    expect(occlusionCalls, hasLength(2));
    expect(
      (occlusionCalls.first.arguments! as Map<Object?, Object?>)['occluded'],
      isTrue,
    );
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
}
