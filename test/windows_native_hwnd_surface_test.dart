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

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await backend.dispose();
    expect(
      calls.where((call) => call.method == 'dispose'),
      hasLength(1),
    );
  });
}
