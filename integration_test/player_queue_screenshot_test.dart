import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/main.dart' as app;

// ignore: slash_for_doc_comments
// ignore: slash_for_doc_comments
/**
 * 在真实 Windows Flutter 窗口中验证播放队列折叠和恢复。
 *
 * 测试只通过 Flutter Finder 与 VM Service 操作应用，不创建 Windows UIA 客户端。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('折叠并恢复播放器筛选队列', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 8));

    // 隔离样本的标题固定，使用语义标签进入真实播放器页面。
    final playButton = find.bySemanticsLabel('qa.video.play.purple-grid');
    expect(playButton, findsOneWidget);
    await tester.tap(playButton);
    await tester.pumpAndSettle(const Duration(seconds: 8));
    await _signalDesktopCapture('player-queue-initial');

    final toggle = find.byKey(const ValueKey('player.queue.toggle'));
    expect(toggle, findsOneWidget);
    expect(find.byKey(const ValueKey('player.queue.sidebar')), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(toggle));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(toggle);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _signalDesktopCapture('player-queue-collapsed');

    await mouse.moveTo(tester.getCenter(toggle));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(toggle);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _signalDesktopCapture('player-queue-restored');

    final volume = find.byKey(const ValueKey('player.volume'));
    final volumeBefore = tester.widget<Slider>(volume).value;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(volume),
        scrollDelta: const Offset(0, 20),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<Slider>(volume).value, lessThan(volumeBefore));

    await mouse.moveTo(const Offset(2, 2));
    await tester.pump(const Duration(seconds: 4));
    final controlsOpacity = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('player.controls.opacity')),
    );
    expect(controlsOpacity.opacity, 0);
    await _signalDesktopCapture('player-controls-hidden');

    await mouse.moveTo(const Offset(800, 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('player.fullscreen.toggle')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await mouse.moveTo(tester.getCenter(toggle));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(toggle);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(
      find.byKey(const ValueKey('player.fullscreenQueue')),
      findsOneWidget,
    );
    await _signalDesktopCapture('player-fullscreen-queue');
    await mouse.removePointer();
  });
}

// ignore: slash_for_doc_comments
/**
 * 通知外部真实桌面截图器捕获当前窗口，并保留足够的像素采集时间。
 */
Future<void> _signalDesktopCapture(String name) async {
  final outputPath = Platform.environment['LOCAL_TAG_PLAYER_SCREENSHOT_DIR'];
  if (outputPath == null || outputPath.isEmpty) {
    throw StateError('缺少 LOCAL_TAG_PLAYER_SCREENSHOT_DIR');
  }
  final outputDirectory = Directory(outputPath)..createSync(recursive: true);
  File('${outputDirectory.path}\\$name.ready').writeAsStringSync('ready');
  await Future<void>.delayed(const Duration(seconds: 4));
}
