import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ignore_for_file: avoid_print, slash_for_doc_comments

/**
 * 真实大库 SQLite hydration 与首屏生成分阶段基准。
 *
 * 调用方必须把真实 `library.db` 复制到独立 `LOCAL_TAG_PLAYER_DATA_DIR` 后再启用；
 * 测试会执行兼容迁移和必要索引修复，因此绝不能直接指向用户正在使用的 profile。
 * 输出只包含耗时与数量，不包含路径、标题或标签内容。
 */
void main() {
  final enabled =
      Platform.environment['LOCAL_TAG_PLAYER_LOAD_BENCHMARK'] == '1';
  test(
    'measures SQLite hydration and first-screen generation stages',
    () async {
      DynamicLibrary.open(
        File('windows/tools/sqlite/sqlite3.dll').absolute.path,
      );
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final outputPath =
          Platform.environment['LOCAL_TAG_PLAYER_LOAD_BENCHMARK_OUTPUT'];
      expect(outputPath, isNotNull);

      final diagnostics = LibraryLoadDiagnostics();
      final totalWatch = Stopwatch()..start();
      final store = await LibraryStore.load(
        diagnostics: diagnostics,
        scanBackend: DartLibraryScanBackend(),
      );
      addTearDown(store.close);
      final sortPreferences = await LibrarySortPreferences.load();
      final firstScreenVideos = diagnostics.measureSync(
        'ui.first_screen_list_sort',
        () => sortedLibraryVideos(
          store.videos.values,
          sortMode: sortPreferences.mode,
          sortDirection: sortPreferences.direction,
        ),
        itemCount: (items) => items.length,
      );
      final initialCounts = diagnostics.measureSync(
        'ui.initial_tag_result_counts',
        () => store.resultCounts(const FilterQuery()),
        itemCount: (counts) => counts.length,
      );
      totalWatch.stop();

      expect(firstScreenVideos.length, store.videos.length);
      expect(initialCounts.length, store.tagsById.length);
      final totalUs = totalWatch.elapsedMicroseconds;
      final stages = <Map<String, Object?>>[
        for (final stage in diagnostics.stages)
          <String, Object?>{
            ...stage.toJson(),
            'sharePercent': totalUs == 0
                ? 0
                : double.parse(
                    (stage.elapsed.inMicroseconds * 100 / totalUs)
                        .toStringAsFixed(2),
                  ),
          },
      ];
      final summary = <String, Object?>{
        'totalMs': double.parse(
          (totalUs / 1000).toStringAsFixed(3),
        ),
        'indexedRecords': store.videos.length,
        'tagRecords': store.tagsById.length,
        'videoTagPathRecords': store.videoTagIdsByPathKey.length,
        'stages': stages,
      };
      await File(outputPath!).writeAsString(
        const JsonEncoder.withIndent('  ').convert(summary),
      );
      print('LTP_LIBRARY_LOAD_BENCHMARK ${jsonEncode(summary)}');
    },
    skip: enabled ? false : '仅由显式真实媒体库隔离基准命令启用',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
