import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/core/app_paths.dart';
import 'package:local_tag_player/src/models/library_scan_models.dart';
import 'package:local_tag_player/src/models/platform_models.dart';
import 'package:local_tag_player/src/models/video_item.dart';
import 'package:local_tag_player/src/platform/database_provider.dart';
import 'package:local_tag_player/src/services/library/library_performance_trace.dart';
import 'package:local_tag_player/src/services/library/library_query_compiler.dart';
import 'package:local_tag_player/src/services/library/library_scan_backend.dart';
import 'package:local_tag_player/src/services/library/library_scan_service.dart';
import 'package:local_tag_player/src/services/library/library_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ignore_for_file: slash_for_doc_comments

/** 只控制后端结束时机；提交、标签命令、FTS 及最终过滤均执行生产实现。 */
class _UnchangedBackend implements LibraryScanBackend {
  Completer<void>? gate;
  Completer<void>? started;
  List<LibraryScannedVideo> modified = [];
  bool cancelled = false;
  @override
  Future<LibraryScanDelta> scan(
      {required int generationId,
      required List<String> roots,
      required Map<String, LibraryScanKnownMetadata> knownMetadata,
      LibraryScanProgressCallback? onProgress}) async {
    started?.complete();
    if (gate != null) await gate!.future;
    return LibraryScanDelta(
        generationId: generationId,
        added: const [],
        modified: modified,
        seenPathKeys: knownMetadata.keys,
        scannedRootKeys: const {},
        unchangedCount: knownMetadata.length,
        cancelled: cancelled);
  }

  @override
  void cancelGeneration(int generationId) {}
  @override
  Future<void> setPaused(bool paused) async {}
}

void main() {
  late Directory directory;
  late LibraryStore store;
  late _UnchangedBackend backend;
  setUpAll(() {
    if (Platform.isWindows) {
      DynamicLibrary.open(
          File('windows/tools/sqlite/sqlite3.dll').absolute.path);
    }
    sqfliteFfiInit();
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ltp_scan_index_');
    backend = _UnchangedBackend();
    store = await LibraryStore.load(
        scanBackend: backend,
        databaseProvider: SqfliteDatabaseProvider(
            paths: AppPaths(dataDirectoryOverride: directory),
            factory: databaseFactoryFfi),
        dataBackupEnabled: false);
    await store.upsertVideos(List.generate(
        2001,
        (n) => VideoItem(
            videoId: 'stable-$n',
            path: '${directory.path}/clip-$n.mp4',
            title: 'original-$n',
            folder: directory.path,
            tags: {},
            addedAt: DateTime.utc(2026))));
    LibraryPerformanceTrace.start();
  });
  tearDown(() async {
    LibraryPerformanceTrace.stop();
    await store.close();
    await directory.delete(recursive: true);
  });
  int rebuilds() => (LibraryPerformanceTrace.snapshot()['events'] as List)
      .where((dynamic e) =>
          e['operation'] == 'index' && e['stage'] == 'commit_return')
      .length;
  Future<void> equivalent(String keyword) async {
    final query = FilterQuery(keyword: keyword);
    final candidates = await store.queryCandidatesFor(query);
    expect(candidates, isNotNull, reason: '必须执行真实 SQLite 候选路径');
    Set<String> ids(Iterable<VideoItem> items) => items
        .where((v) => query.matches(v, tagContext: store.tagQueryContext))
        .map((v) => v.videoId)
        .toSet();
    expect(ids(candidates!), ids(store.videos.values));
  }

  test('可搜索字段逐项未变的扫描仍推进查询 epoch，但不重建 FTS', () async {
    await equivalent('original');
    final before =
        await store.database.rawQuery(LibrarySearchIndex.sourceSelectSql);
    final revision = store.dataRevision;
    for (var n = 0; n < 3; n++) {
      expect((await store.scanWithChanges()).changedVideos, isEmpty);
      expect(await store.database.rawQuery(LibrarySearchIndex.sourceSelectSql),
          before);
      await equivalent('original');
    }
    expect(store.dataRevision, revision + 3);
    expect(rebuilds(), 1);
  });
  test('零视频差量扫描期间别名变化不能复用旧索引', () async {
    final video = store.videosById['stable-0']!;
    await store.replaceManualTags(video, manualTags: ['manualword']);
    final tag = store.tagsById.values.firstWhere((t) => t.name == 'manualword');
    await equivalent('manualword');
    backend.started = Completer<void>();
    backend.gate = Completer<void>();
    final scan = store.scanWithChanges();
    await backend.started!.future;
    await store.updateTagDetails(tag, aliases: ['newalias']);
    backend.gate!.complete();
    expect((await scan).changedVideos, isEmpty);
    await equivalent('newalias');
    expect(
        (await store
                .queryCandidatesFor(const FilterQuery(keyword: 'newalias')))!
            .map((v) => v.videoId),
        contains('stable-0'));
    expect(rebuilds(), 2);
  });
  test('新增改名标签及删除后仍失效，真实候选与完整集合一致', () async {
    await equivalent('original');
    final video = store.videosById['stable-0']!;
    video.title = 'renamedword';
    await store.upsertVideo(video);
    await equivalent('renamedword');
    await store.replaceManualTags(video, manualTags: ['newtagword']);
    await equivalent('newtagword');
    await store.upsertVideo(VideoItem(
        videoId: 'added',
        path: '${directory.path}/added.mp4',
        title: 'addedword',
        folder: directory.path,
        tags: {},
        addedAt: DateTime.utc(2026)));
    await equivalent('addedword');
    await store.deleteVideoById(video.videoId);
    await equivalent('renamedword');
    await equivalent('newtagword');
    expect(rebuilds(), 5);
  });
  test('扫描真实写入文本后必须重建，后续空扫描复用且 manual 标签保留', () async {
    final video = store.videosById['stable-0']!;
    await store.replaceManualTags(video, manualTags: ['manualword']);
    await equivalent('original');
    backend.modified = [
      LibraryScannedVideo(
          path: video.path,
          title: 'scanrenamedword',
          folder: directory.path,
          rootPath: directory.path,
          relativePath: 'clip-0.mp4',
          tags: const {},
          childTags: const {},
          fileSize: 5,
          modifiedMs: 123,
          mediaFingerprint: 'changed-content')
    ];
    expect((await store.scanWithChanges()).changedVideos, hasLength(1));
    await equivalent('scanrenamedword');
    await equivalent('manualword');
    expect(
        (await store
                .queryCandidatesFor(const FilterQuery(keyword: 'manualword')))!
            .map((v) => v.videoId),
        contains('stable-0'));
    backend.modified = [];
    expect((await store.scanWithChanges()).changedVideos, isEmpty);
    await equivalent('scanrenamedword');
    expect(rebuilds(), 2);
  });
  test('取消扫描没有证明内容不变，保持保守失效', () async {
    await equivalent('original');
    final revision = store.dataRevision;
    backend.cancelled = true;
    expect((await store.scanWithChanges()).cancelled, isTrue);
    await equivalent('original');
    expect(store.dataRevision, revision + 1);
    expect(rebuilds(), 2);
  });
}
