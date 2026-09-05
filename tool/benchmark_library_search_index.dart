import 'dart:convert';
import 'dart:io';

import 'package:local_tag_player/src/services/library/library_query_compiler.dart';
import 'package:local_tag_player/src/services/library/library_performance_trace.dart';
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
 * 追加 --decompose 执行 10 对生产 SQL/分步临时表实验，后者不能当作生产内部精确归因。
 * 这是 Dart JIT 索引维护基准，不能代替 Flutter profile 帧时序或用户交互基线。
 */
Future<void> main(List<String> args) async {
  if (args.length != 2 && !(args.length == 3 && args[2] == '--decompose')) {
    throw ArgumentError('需要隔离 profile、输出 JSON 路径及可选 --decompose');
  }
  final directory = Directory(args.first).absolute;
  final file = File('${directory.path}/library.db');
  if (!File('${directory.path}/.query-baseline-profile').existsSync() ||
      !file.existsSync()) {
    throw StateError('拒绝打开没有隔离标记或没有 library.db 的目录');
  }
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(file.path);
  try {
    if (args.length == 3) {
      await _decompose(db, args[1]);
      return;
    }
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

/**
 * 交替顺序降低热缓存偏差。分步方法增加临时物化，绝不以相减方式冒称原语句内部 CPU 时间。
 * 所有操作都在隔离连接；临时表不持久化，原视频与标签只读。
 */
Future<void> _decompose(Database db, String output) async {
  final index = LibrarySearchIndex();
  if (!await index.ensureSchema(db)) throw StateError('FTS 不可用');
  const source = LibrarySearchIndex.sourceSelectSql;
  const table = LibrarySearchIndex.tableName;
  await db.execute(
      'CREATE TEMP TABLE qa_index_stage AS SELECT * FROM ($source) LIMIT 0');
  LibraryPerformanceTrace.start();
  try {
    for (var pair = 0; pair < 10; pair++) {
      for (final mode in pair.isEven ? [0, 1] : [1, 0]) {
        final span = LibraryPerformanceTrace.begin(
            mode == 0 ? 'experiment.combined' : 'experiment.staged',
            fields: {'pair': pair})!;
        await db.transaction((tx) async {
          span.step('transaction_enter');
          await tx.delete(table);
          span.step('delete');
          if (mode == 0) {
            await tx.execute('INSERT INTO $table $source');
            span.step('aggregate_and_fts_write');
          } else {
            await tx.execute('DELETE FROM qa_index_stage');
            span.step('stage_clear');
            await tx.execute('INSERT INTO qa_index_stage $source');
            span.step('aggregate_to_temp');
            await tx.execute('INSERT INTO $table SELECT * FROM qa_index_stage');
            span.step('fts_from_temp');
          }
        });
        span.finish('commit_return');
        // 比对全部索引字段，既验证 stable ID，也防止分步实验遗漏别名聚合文本。
        final mismatch = await db.rawQuery('''
          SELECT COUNT(*) n FROM (
            SELECT * FROM $table EXCEPT $source
          )
        ''');
        final counts = await db.rawQuery(
            'SELECT (SELECT COUNT(*) FROM $table) index_count, COUNT(*) source_count FROM videos');
        if (mismatch.single['n'] != 0 ||
            counts.single['index_count'] != counts.single['source_count']) {
          throw StateError('分步索引与生产聚合不一致');
        }
      }
    }
    await File(output)
        .writeAsString(const JsonEncoder.withIndent('  ').convert({
      'kind': 'counterfactual-sql-decomposition-dart-jit',
      'rows': (await db.rawQuery('SELECT COUNT(*) n FROM videos')).single['n'],
      'pairs': 10,
      'allIndexFieldsEquivalent': true,
      'trace': LibraryPerformanceTrace.snapshot(),
    }));
    stdout.writeln('SQL 分步实验 10 对完成，全部索引字段一致');
  } finally {
    LibraryPerformanceTrace.stop();
    await db.execute('DROP TABLE qa_index_stage');
  }
}
