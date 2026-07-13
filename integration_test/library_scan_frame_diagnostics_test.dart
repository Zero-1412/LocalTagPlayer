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
 * 使用隔离媒体库副本连续采样大量修改差量和零差量扫描。
 *
 * 测试只通过 Flutter Finder / VM Service 点击真实窗口，不创建 Windows UIA
 * 客户端。调用方必须设置 `LOCAL_TAG_PLAYER_DATA_DIR` 指向可丢弃副本。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('大量差量与零差量帧耗时对照', (tester) async {
    final profilePath = Platform.environment['LOCAL_TAG_PLAYER_DATA_DIR'];
    if (profilePath == null || profilePath.trim().isEmpty) {
      throw StateError('必须使用 LOCAL_TAG_PLAYER_DATA_DIR 隔离真实媒体库');
    }
    await _prepareLargeDeltaProfile(profilePath);
    final diagnostics = File(
      '${Directory.systemTemp.path}\\local_tag_player_scan_ui_diagnostics.jsonl',
    );
    if (diagnostics.existsSync()) {
      diagnostics.deleteSync();
    }

    await app.main();
    await _pumpUntilFound(
        tester, find.byKey(const ValueKey('smoke.sidebar.rescan')));

    await tester.tap(find.byKey(const ValueKey('smoke.sidebar.rescan')));
    await _pumpUntilDiagnosticsCount(tester, diagnostics, 1);

    await tester.tap(find.byKey(const ValueKey('smoke.sidebar.rescan')));
    await _pumpUntilDiagnosticsCount(tester, diagnostics, 2);
    await _captureLargestRepaintBoundary(tester);

    final rows = diagnostics
        .readAsLinesSync()
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, Object?>)
        .toList();
    expect(rows, hasLength(2));
    expect(rows.first['scenario'], 'large_delta');
    expect(rows.last['scenario'], 'zero_delta');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/** 从 Flutter 渲染树导出最大像素边界，不依赖桌面 UIA 或平台截图插件。 */
Future<void> _captureLargestRepaintBoundary(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  final boundaries = find
      .byType(RepaintBoundary)
      .evaluate()
      .map((element) => element.renderObject)
      .whereType<RenderRepaintBoundary>()
      .where((boundary) => boundary.attached)
      .toList();
  if (boundaries.isEmpty) {
    throw StateError('找不到可截取的 RepaintBoundary');
  }
  boundaries.sort((left, right) {
    final leftArea = left.size.width * left.size.height;
    final rightArea = right.size.width * right.size.height;
    return rightArea.compareTo(leftArea);
  });
  final image = await boundaries.first.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) {
    throw StateError('无法编码 Flutter 像素截图');
  }
  await File('${Directory.systemTemp.path}\\ltp_thumbnail_after.png')
      .writeAsBytes(bytes.buffer.asUint8List(), flush: true);
}

/** 只修改隔离数据库的路径上下文，使首轮扫描稳定产生大量差量。 */
Future<void> _prepareLargeDeltaProfile(String profilePath) async {
  final databaseFile = File('$profilePath\\library.db');
  if (!databaseFile.existsSync()) {
    throw StateError('隔离 profile 缺少 library.db');
  }
  DynamicLibrary.open(
    File('windows/tools/sqlite/sqlite3.dll').absolute.path,
  );
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final database = await databaseFactory.openDatabase(databaseFile.path);
  try {
    await database.update(
      'videos',
      <String, Object?>{'root_path': '', 'relative_path': ''},
    );
  } finally {
    await database.close();
  }
}

/** 以 50ms 连续驱动帧，避免把 pump 步长误当超时。 */
Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

/** 继续驱动真实帧，直到诊断 JSONL 写入指定轮数。 */
Future<void> _pumpUntilDiagnosticsCount(
  WidgetTester tester,
  File diagnostics,
  int expectedCount,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (diagnostics.existsSync() &&
        diagnostics
                .readAsLinesSync()
                .where((line) => line.trim().isNotEmpty)
                .length >=
            expectedCount) {
      return;
    }
  }
  fail('扫描帧诊断未在时限内写入第 $expectedCount 轮');
}
