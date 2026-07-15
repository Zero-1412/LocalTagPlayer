import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/main.dart' as app;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 在真实 Windows 窗口中验证冷 fingerprint 扫描与播放器不会争抢到应用冻结。
 *
 * 调用方必须传入可丢弃的真实数据库副本；测试只清空副本 fingerprint 以延长扫描窗口，
 * 不修改用户 profile 或媒体文件。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('扫描期间点击播放会暂停扫描并在返回后继续', (tester) async {
    final profilePath = Platform.environment['LOCAL_TAG_PLAYER_DATA_DIR'];
    if (profilePath == null || profilePath.trim().isEmpty) {
      throw StateError('必须使用 LOCAL_TAG_PLAYER_DATA_DIR 隔离真实媒体库');
    }
    await _clearFingerprintsInProfile(profilePath);
    final diagnostics = File(
      '${Directory.systemTemp.path}\\local_tag_player_scan_ui_diagnostics.jsonl',
    );
    if (diagnostics.existsSync()) {
      diagnostics.deleteSync();
    }

    await app.main();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('smoke.sidebar.rescan')),
    );
    final play = await _firstVisiblePlayButton(tester);

    await tester.tap(find.byKey(const ValueKey('smoke.sidebar.rescan')));
    await tester.pump(const Duration(milliseconds: 50));
    await _pumpUntilFound(
      tester,
      find.textContaining('校验文件'),
      timeout: const Duration(seconds: 3),
    );
    await _pumpContinuously(tester, const Duration(milliseconds: 250));
    await _captureLargestRepaintBoundary('ltp_scan_fingerprint.png');
    await tester.tap(play, warnIfMissed: false);
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('player.video.surface')),
      timeout: const Duration(seconds: 20),
    );

    // 播放器保持两秒可响应，且扫描诊断尚未完成，证明 sidecar 停在原候选位置让盘。
    await _pumpContinuously(tester, const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('player.video.surface')), findsOneWidget);
    expect(diagnostics.existsSync(), isFalse);
    await _captureLargestRepaintBoundary('ltp_scan_playing.png');

    await tester.tap(find.byKey(const ValueKey('player.back')));
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('smoke.sidebar.rescan')),
      timeout: const Duration(seconds: 20),
    );
    await _pumpUntilDiagnostics(tester, diagnostics);
    await _captureLargestRepaintBoundary('ltp_scan_resumed.png');

    final row =
        jsonDecode(diagnostics.readAsLinesSync().last) as Map<String, Object?>;
    final phases =
        (row['scanPhases'] as List<Object?>).cast<Map<String, Object?>>();
    expect(
      phases.map((phase) => phase['phase']),
      containsAll(<String>['discovering', 'fingerprinting', 'committing']),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/** 只清空隔离数据库 fingerprint，使下一次扫描覆盖真实冷路径。 */
Future<void> _clearFingerprintsInProfile(String profilePath) async {
  DynamicLibrary.open(
    File('windows/tools/sqlite/sqlite3.dll').absolute.path,
  );
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final database = await databaseFactory.openDatabase(
    '$profilePath${Platform.pathSeparator}library.db',
  );
  try {
    await database.update(
      'videos',
      <String, Object?>{'media_fingerprint': null},
    );
  } finally {
    await database.close();
  }
}

/** 找到首屏实际可点击的视频播放入口。 */
Future<Finder> _firstVisiblePlayButton(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final finder = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          (key.value.startsWith('smoke.card.play:') ||
              key.value.startsWith('smoke.list.play:'));
    }).hitTestable();
    if (finder.evaluate().isNotEmpty) {
      return finder.first;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  throw StateError('首屏没有可点击视频');
}

/** 连续驱动真实帧，等待稳定 key 出现。 */
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

/** 以 50ms 步长维持窗口输入和渲染响应。 */
Future<void> _pumpContinuously(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/** 等待扫描完成并写出分阶段诊断。 */
Future<void> _pumpUntilDiagnostics(
  WidgetTester tester,
  File diagnostics,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (diagnostics.existsSync() && diagnostics.lengthSync() > 0) {
      return;
    }
  }
  throw StateError('扫描返回后未写出阶段诊断');
}

/** 从真实 Flutter 窗口导出最大绘制边界截图。 */
Future<void> _captureLargestRepaintBoundary(String name) async {
  final boundaries = find
      .byType(RepaintBoundary)
      .evaluate()
      .map((element) => element.renderObject)
      .whereType<RenderRepaintBoundary>()
      .where((boundary) => boundary.attached)
      .toList()
    ..sort((left, right) => (right.size.width * right.size.height)
        .compareTo(left.size.width * left.size.height));
  if (boundaries.isEmpty) {
    throw StateError('找不到可截图的绘制边界');
  }
  final image = await boundaries.first.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) {
    throw StateError('截图编码失败');
  }
  await File('${Directory.systemTemp.path}\\$name').writeAsBytes(
    bytes.buffer.asUint8List(),
    flush: true,
  );
}
