import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/core/app_paths.dart';
import 'package:local_tag_player/src/models/platform_models.dart';
import 'package:local_tag_player/src/models/video_item.dart';
import 'package:local_tag_player/src/platform/database_provider.dart';
import 'package:local_tag_player/src/services/library/library_scan_backend.dart';
import 'package:local_tag_player/src/services/library/library_store.dart';
import 'package:local_tag_player/src/services/tags/tag_query_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 在隔离数据库副本上比较完整内存筛选与 FTS5 候选+最终校验。
 *
 * 该基准默认跳过。显式启用时只复制 [LOCAL_TAG_PLAYER_LIBRARY_QUERY_BENCHMARK_SOURCE]
 * 指向的真实 profile，不会打开或写回用户正在使用的数据库；结果只输出数量和耗时，
 * 用来决定 profile 的阈值与是否保留 FTS5 默认路径。
 */
void main() {
  final source =
      Platform.environment['LOCAL_TAG_PLAYER_LIBRARY_QUERY_BENCHMARK_SOURCE'];
  final output =
      Platform.environment['LOCAL_TAG_PLAYER_LIBRARY_QUERY_BENCHMARK_OUTPUT'];
  final enabled = source != null &&
      source.trim().isNotEmpty &&
      Platform.environment['LOCAL_TAG_PLAYER_LIBRARY_QUERY_BENCHMARK'] == '1';

  test(
    'benchmarks full query against FTS5 candidate query on a real library',
    () async {
      final sourceDirectory = Directory(source!.trim());
      final sourceDatabase =
          File('${sourceDirectory.path}${Platform.pathSeparator}library.db');
      expect(sourceDatabase.existsSync(), isTrue);

      final isolatedDirectory = await Directory.systemTemp.createTemp(
        'ltp_library_query_benchmark_',
      );
      addTearDown(() async {
        if (isolatedDirectory.existsSync()) {
          await isolatedDirectory.delete(recursive: true);
        }
      });
      // SQLite 可能正在使用 WAL；一并复制伴随文件，仍然只对副本做 schema/FTS 写入。
      for (final file in sourceDirectory.listSync().whereType<File>()) {
        if (file.path == sourceDatabase.path ||
            file.path.startsWith('${sourceDatabase.path}-')) {
          await file.copy(
            '${isolatedDirectory.path}${Platform.pathSeparator}${file.uri.pathSegments.last}',
          );
        }
      }

      if (Platform.isWindows) {
        DynamicLibrary.open(
          File('windows/tools/sqlite/sqlite3.dll').absolute.path,
        );
      }
      sqfliteFfiInit();
      final provider = SqfliteDatabaseProvider(
        paths: AppPaths(dataDirectoryOverride: isolatedDirectory),
        factory: databaseFactoryFfi,
      );
      final store = await LibraryStore.load(
        scanBackend: DartLibraryScanBackend(),
        databaseProvider: provider,
      );
      addTearDown(store.close);
      expect(store.videos.length, greaterThanOrEqualTo(2000));

      final engine = TagQueryService(
        videos: store.videos.values,
        tagContext: store.tagQueryContext,
      );
      final keywords = <String>[];
      for (final item in store.videos.values) {
        for (final token in item.title.split(RegExp(r'[^\p{L}\p{N}]+'))) {
          if (token.length >= 3 && !keywords.contains(token)) {
            keywords.add(token);
          }
          if (keywords.length == 3) break;
        }
        if (keywords.length == 3) break;
      }
      expect(keywords, isNotEmpty, reason: '真实库需要至少一个三字符关键词');

      // 首次调用包含派生索引重建，单独记录，不能冒充稳定态查询耗时。
      final coldWatch = Stopwatch()..start();
      final firstCandidates = await store.queryCandidatesFor(
        FilterQuery(keyword: keywords.first),
      );
      coldWatch.stop();
      expect(firstCandidates, isNotNull);

      const repetitions = 5;
      final rows = <Map<String, Object?>>[];
      for (final keyword in keywords) {
        final query = FilterQuery(keyword: keyword);
        final fullWatch = Stopwatch()..start();
        List<VideoItem>? fullResult;
        for (var index = 0; index < repetitions; index += 1) {
          fullResult = engine.filter(query);
        }
        fullWatch.stop();

        final candidateWatch = Stopwatch()..start();
        List<VideoItem>? candidateResult;
        for (var index = 0; index < repetitions; index += 1) {
          final candidates = await store.queryCandidatesFor(query);
          expect(candidates, isNotNull);
          candidateResult = TagQueryService(
            videos: candidates!,
            tagContext: store.tagQueryContext,
          ).filter(query);
        }
        candidateWatch.stop();

        final fullIds = fullResult!.map((item) => item.videoId).toSet();
        final candidateIds =
            candidateResult!.map((item) => item.videoId).toSet();
        expect(candidateIds, fullIds, reason: 'FTS 候选不得改变最终筛选语义');
        rows.add(<String, Object?>{
          'fullAvgMs': fullWatch.elapsedMicroseconds / repetitions / 1000,
          'candidateAndVerifyAvgMs':
              candidateWatch.elapsedMicroseconds / repetitions / 1000,
          'fullResultCount': fullIds.length,
          'candidateCount': (await store.queryCandidatesFor(query))!.length,
        });
      }

      final fullAverage = rows
              .map((row) => row['fullAvgMs'] as double)
              .reduce((left, right) => left + right) /
          rows.length;
      final candidateAverage = rows
              .map((row) => row['candidateAndVerifyAvgMs'] as double)
              .reduce((left, right) => left + right) /
          rows.length;
      final summary = <String, Object?>{
        'indexedRecords': store.videos.length,
        'coldIndexBuildMs': coldWatch.elapsedMicroseconds / 1000,
        'fullAverageMs': fullAverage,
        'candidateAndVerifyAverageMs': candidateAverage,
        'candidatePathWins': candidateAverage < fullAverage,
        'repetitionsPerKeyword': repetitions,
        'queries': rows.length,
      };
      if (output != null && output.trim().isNotEmpty) {
        await File(output.trim()).writeAsString(
          const JsonEncoder.withIndent('  ').convert(summary),
        );
      }
      // 只输出基准结论，不输出真实标题、标签或路径。
      // ignore: avoid_print
      print('LTP_LIBRARY_QUERY_BENCHMARK ${jsonEncode(summary)}');
      expect(candidateAverage, lessThan(fullAverage));
    },
    skip: enabled ? false : '仅由显式隔离真实媒体库基准命令启用',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
