import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/main.dart' as app;

// ignore_for_file: slash_for_doc_comments

/**
 * 在真实 Windows Flutter 窗口中点击 HDR 动态映射并验证可回滚两态。
 *
 * 测试使用隔离数据目录，不打开媒体、不运行 Compute 压测；压测由设备基线测试负责。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('主设置页确认开启并关闭 HDR 动态映射', (tester) async {
    final outputPath =
        Platform.environment['LOCAL_TAG_PLAYER_SCREENSHOT_DIR']?.trim();
    if (outputPath == null || outputPath.isEmpty) {
      throw StateError('缺少 LOCAL_TAG_PLAYER_SCREENSHOT_DIR');
    }
    final outputDirectory = Directory(outputPath)..createSync(recursive: true);
    // 窗口采证必须绑定本次测试进程，不能按同名窗口猜测。
    File('${outputDirectory.path}\\process.pid')
        .writeAsStringSync(pid.toString(), flush: true);
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 8));

    final settingsEntry = find.text('设置');
    expect(settingsEntry, findsOneWidget);
    await tester.tap(settingsEntry);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _signalDesktopCapture('settings-playback-split');

    final qualityEntry = find.text('视频画质与增强');
    expect(qualityEntry, findsOneWidget);
    await tester.tap(qualityEntry);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _signalDesktopCapture('video-quality-page');

    final experiment = find.byKey(
      const ValueKey('settings.playbackQuality.hdrMappingExperiment'),
    );
    expect(experiment, findsOneWidget);
    await tester.ensureVisible(experiment);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    final switchFinder = find.descendant(
      of: experiment,
      matching: find.byType(Switch),
    );
    if (tester.widget<Switch>(switchFinder).value) {
      // 隔离目录若被中断测试复用，先回到明确关闭态再验证完整开启路径。
      await tester.tap(experiment);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
    }

    await tester.tap(experiment);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('开启 HDR 动态映射？'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey('settings.playbackQuality.hdrMappingConfirm'),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    await _signalDesktopCapture('hdr-mapping-enabled');

    await tester.tap(experiment);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(tester.widget<Switch>(switchFinder).value, isFalse);
    expect(find.text('开启 HDR 动态映射？'), findsNothing);
    await _signalDesktopCapture('hdr-mapping-rollback');
  });
}

/** 通知外部像素截图器捕获当前真实窗口，不启用 Windows UIA。 */
Future<void> _signalDesktopCapture(String name) async {
  final outputPath = Platform.environment['LOCAL_TAG_PLAYER_SCREENSHOT_DIR'];
  if (outputPath == null || outputPath.isEmpty) {
    throw StateError('缺少 LOCAL_TAG_PLAYER_SCREENSHOT_DIR');
  }
  final directory = Directory(outputPath)..createSync(recursive: true);
  File('${directory.path}\\$name.ready').writeAsStringSync('ready');
  await Future<void>.delayed(const Duration(seconds: 2));
}
