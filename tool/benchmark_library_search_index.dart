import 'dart:convert';
import 'dart:io';

import 'package:local_tag_player/src/services/library/library_query_compiler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ignore_for_file: slash_for_doc_comments

/** 记录真实索引事务次数与等待耗时，不替换数据库行为。 */
class _MeasuredIndex extends LibrarySearchIndex {
  var rebuilds = 0;
  final durations = <double>[];
  @override
  Future<void> rebuild(Database db) async {
    rebuilds++;
    final watch = Stopwatch()..start();
    await super.rebuild(db);
    durations.add(watch.elapsedMicroseconds / 1000);
  }
}

/**
 * 用法：dart run tool/benchmark_library_search_index.dart <隔离 profile> <输出 JSON>。
 * 调用方先以 SQLite backup 创建副本并写入 .query-baseline-profile 标记。
 * Windows 调用方需把 sqlite3.dll 目录加入 PATH；脚本不读取媒体文件。
 * 这是 Dart JIT 索引维护基准，不能代替 Flutter profile 帧时序或用户交互基线。
 */
Future<void> main(List<String> args) async {
  if (args.length != 2) throw ArgumentError('需要隔离 profile 与输出 JSON 路径');
  final directory = Directory(args.first).absolute;
  final file = File('${directory.path}/library.db');
  if (!File('${directory.path}/.query-baseline-profile').existsSync() ||
      !file.existsSync()) {
    throw StateError('拒绝打开没有隔离标记或没有 library.db 的目录');
  }
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(file.path);
  try {
    final index = _MeasuredIndex();
    final watch = Stopwatch()..start();
    final results = await Future.wait(
        List.generate(8, (_) => index.ensureFresh(db, revision: 1)));
    watch.stop();
    if (results.any((ready) => !ready)) throw StateError('索引重建失败');
    final warm = <double>[];
    for (var n = 0; n < 30; n++) {
      final sample = Stopwatch()..start();
      if (!await index.ensureFresh(db, revision: 1)) throw StateError('热索引不可用');
      warm.add(sample.elapsedMicroseconds / 1000);
    }
    warm.sort();
    final report = {
      'kind': 'isolated-library-index-dart-jit',
      'rows':
          (await db.rawQuery('SELECT COUNT(*) AS n FROM videos')).single['n'],
      'requests': 8,
      'rebuilds': index.rebuilds,
      'burstMs': watch.elapsedMicroseconds / 1000,
      'rebuildMs': index.durations,
      'warmN': warm.length,
      'warmP50Ms': warm[14],
      'warmP95Ms': warm[28],
      'warmP99Ms': warm[29],
    };
    await File(args.last)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    // 只输出规模与耗时，不暴露真实路径、标题、标签或别名。
    stdout.writeln(jsonEncode(report));
  } finally {
    await db.close();
  }
}
