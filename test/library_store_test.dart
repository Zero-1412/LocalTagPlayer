import 'dart:async';
import 'dart:ffi';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ignore_for_file: slash_for_doc_comments

var _sqliteConfigured = false;
late AppPaths _testPaths;
late DatabaseProvider _testDatabaseProvider;

/** 可控扫描后端，用于验证页面取消会推进代次并解除暂停。 */
class _BlockingLibraryScanBackend implements LibraryScanBackend {
  final Completer<void> started = Completer<void>();
  final Completer<LibraryScanDelta> _result = Completer<LibraryScanDelta>();
  final List<bool> pausedStates = <bool>[];
  int? cancelledGeneration;

  @override
  Future<LibraryScanDelta> scan({
    required int generationId,
    required List<String> roots,
    required Map<String, LibraryScanKnownMetadata> knownMetadata,
    LibraryScanProgressCallback? onProgress,
  }) {
    if (!started.isCompleted) {
      started.complete();
    }
    return _result.future;
  }

  @override
  void cancelGeneration(int generationId) {
    cancelledGeneration = generationId;
    if (!_result.isCompleted) {
      _result.complete(
        LibraryScanDelta(
          generationId: generationId,
          added: const <LibraryScannedVideo>[],
          modified: const <LibraryScannedVideo>[],
          seenPathKeys: const <String>{},
          scannedRootKeys: const <String>{},
          unchangedCount: 0,
          cancelled: true,
        ),
      );
    }
  }

  @override
  Future<void> setPaused(bool paused) async {
    pausedStates.add(paused);
  }
}

/**
 * 为 `LibraryStore` focused tests 准备一次性数据目录和 SQLite FFI。
 *
 * 每个测试都使用独立临时目录，避免扫描、标签索引和持久化读写污染真实媒体库。
 */
Future<Directory> _prepareStoreTestDirectory(String name) async {
  if (!_sqliteConfigured) {
    DynamicLibrary.open(
      File(
        'windows${Platform.pathSeparator}tools${Platform.pathSeparator}sqlite${Platform.pathSeparator}sqlite3.dll',
      ).absolute.path,
    );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _sqliteConfigured = true;
  }
  final directory = await Directory.systemTemp.createTemp('ltp_${name}_');
  _testPaths = AppPaths(dataDirectoryOverride: directory);
  _testDatabaseProvider = SqfliteDatabaseProvider(
    paths: _testPaths,
    factory: databaseFactoryFfi,
  );
  return directory;
}

/**
 * 在临时媒体根目录内创建一个轻量视频占位文件。
 *
 * `LibraryStore.scan` 只依赖扩展名和文件 stat，本测试不需要真实视频编码内容。
 */
Future<File> _writeVideoPlaceholder(
  Directory root,
  List<String> segments,
) async {
  final file = File([root.path, ...segments].join(Platform.pathSeparator));
  await file.parent.create(recursive: true);
  await file.writeAsBytes([1, 2, 3, 4, 5]);
  return file;
}

/**
 * 按路径 key 读取扫描后的单条视频，确保测试断言不依赖平台路径大小写。
 */
VideoItem _videoByPath(LibraryStore store, String path) {
  final item = store.videos[TagRules.pathKey(path)];
  expect(item, isNotNull);
  return item!;
}

/**
 * 加载并登记待关闭的媒体库实例，避免 SQLite 句柄阻塞临时目录清理。
 */
Future<LibraryStore> _loadTrackedStore(
  List<LibraryStore> stores, {
  bool dataBackupEnabled = false,
  LibraryScanBackend? scanBackend,
}) async {
  final store = await LibraryStore.load(
    scanBackend: scanBackend ?? DartLibraryScanBackend(),
    databaseProvider: _testDatabaseProvider,
    dataBackupEnabled: dataBackupEnabled,
  );
  stores.add(store);
  return store;
}

/**
 * 关闭测试中打开过的所有媒体库连接。
 */
Future<void> _closeTrackedStores(List<LibraryStore> stores) async {
  for (final store in stores.reversed) {
    await store.close();
  }
}

void main() {
  test('data backup settings default on and persist explicit opt-out',
      () async {
    final dataDir = await _prepareStoreTestDirectory('backup_settings');
    addTearDown(() => dataDir.delete(recursive: true));

    expect((await DataBackupSettings.load(_testPaths)).enabled, isTrue);
    await const DataBackupSettings(enabled: false).save(_testPaths);
    expect((await DataBackupSettings.load(_testPaths)).enabled, isFalse);
  });

  test(
      'active scan cancellation advances generation and resumes paused backend',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('cancel_active_scan');
    final backend = _BlockingLibraryScanBackend();
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final store = await _loadTrackedStore(
      stores,
      scanBackend: backend,
    );

    final scan = store.scanWithChanges();
    await backend.started.future;
    await store.setScanPaused(true);
    await store.cancelActiveScan();
    final result = await scan;

    expect(result.cancelled, isTrue);
    expect(backend.cancelledGeneration, 1);
    expect(store.scanGeneration, 2);
    expect(backend.pausedStates, <bool>[true, false]);
  });

  test('late playback state write cannot resurrect a deleted video row',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('playback_delete_race');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final store = await _loadTrackedStore(stores);
    final item = VideoItem(
      path: p.join(dataDir.path, 'deleted.mp4'),
      title: 'deleted',
      folder: dataDir.path,
      tags: const <String>{},
      addedAt: DateTime.utc(2026, 7, 17),
      lastPlayedAt: DateTime.utc(2026, 7, 17, 12),
      playbackPosition: const Duration(seconds: 42),
    );
    await store.upsertVideo(item);
    await store.deleteVideo(item.path);

    // 删除提交之后到达的继续观看异步写入必须被丢弃，不能重新创建同一稳定身份行。
    item.playbackPosition = const Duration(seconds: 43);
    await store.upsertPlaybackStates(<VideoItem>[item]);

    expect(store.videos[TagRules.pathKey(item.path)], isNull);
    expect(
      await store.database.query(
        'videos',
        where: 'video_id = ?',
        whereArgs: <Object?>[item.videoId],
      ),
      isEmpty,
    );
  });

  test(
      'automatic cleanup removes only marked missing or existing unreadable records',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('unavailable_cleanup');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final store = await _loadTrackedStore(stores);
    final readableFile =
        await _writeVideoPlaceholder(dataDir, <String>['readable.mp4']);
    final unreadablePath = p.join(dataDir.path, 'unreadable.mp4');
    await Directory(unreadablePath).create();
    final missingPath = p.join(dataDir.path, 'missing.mp4');
    final offlinePath = p.join(dataDir.path, 'offline.mp4');
    VideoItem item(String path, String title, {bool missing = false}) =>
        VideoItem(
          path: path,
          title: title,
          folder: dataDir.path,
          tags: const <String>{},
          addedAt: DateTime.utc(2026, 7, 24),
          isMissing: missing,
        );
    final readable = item(readableFile.path, 'readable');
    final unreadable = item(unreadablePath, 'unreadable');
    final missing = item(missingPath, 'missing', missing: true);
    final offline = item(offlinePath, 'offline');
    await store.upsertVideos(
      <VideoItem>[readable, unreadable, missing, offline],
    );

    expect(await store.removeMissingOrUnreadableVideos(), 2);
    expect(store.videos, contains(TagRules.pathKey(readable.path)));
    expect(store.videos, contains(TagRules.pathKey(offline.path)));
    expect(store.videos, isNot(contains(TagRules.pathKey(missing.path))));
    expect(store.videos, isNot(contains(TagRules.pathKey(unreadable.path))));
    expect(await readableFile.exists(), isTrue);
    expect(await Directory(unreadablePath).exists(), isTrue);
    expect(
      await store.database.query(
        'videos',
        where: 'video_id IN (?, ?)',
        whereArgs: <Object?>[missing.videoId, unreadable.videoId],
      ),
      isEmpty,
    );
  });

  test('batch root import persists all roots and scans only after registration',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('batch_roots');
    final firstRoot = Directory(p.join(dataDir.path, 'first'));
    final secondRoot = Directory(p.join(dataDir.path, 'second'));
    final first = await _writeVideoPlaceholder(firstRoot, ['first.mp4']);
    final second = await _writeVideoPlaceholder(secondRoot, ['second.mkv']);
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });

    final store = await _loadTrackedStore(stores);
    final result = await store.addRootsAndScanWithChanges(<String>[
      firstRoot.path,
      secondRoot.path,
      '${firstRoot.path}${Platform.pathSeparator}',
    ]);

    expect(result.addedCount, 2);
    expect(store.roots, <String>[firstRoot.path, secondRoot.path]);
    expect(store.videos, contains(TagRules.pathKey(first.path)));
    expect(store.videos, contains(TagRules.pathKey(second.path)));
  });

  test('root-level videos do not repeat empty folder-tag coverage writes',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('root_coverage');
    final mediaRoot = Directory(p.join(dataDir.path, 'media'));
    await mediaRoot.create();
    final direct = await _writeVideoPlaceholder(mediaRoot, ['direct.mp4']);
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });

    final store = await _loadTrackedStore(stores);
    expect(await store.addRootAndScan(mediaRoot.path), 1);
    expect(
      store.videoTagIdsByPathKey[TagRules.pathKey(direct.path)],
      isNull,
    );
    await store.close();
    stores.remove(store);

    final diagnostics = LibraryLoadDiagnostics();
    final reloaded = await LibraryStore.load(
      diagnostics: diagnostics,
      scanBackend: DartLibraryScanBackend(),
      databaseProvider: _testDatabaseProvider,
    );
    stores.add(reloaded);
    final coverage = diagnostics.stages.singleWhere(
      (stage) => stage.name == 'dart.folder_tag_coverage_evaluation',
    );
    expect(coverage.itemCount, 0);
    expect(
      diagnostics.stages
          .where((stage) => stage.name == 'sqlite.folder_tag_coverage_write'),
      isEmpty,
    );
  });

  test('legacy path-keyed schema backfills stable video identity', () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('identity_migration');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final databaseFile = await _testPaths.libraryDatabaseFile();
    final legacyDb = await databaseFactory.openDatabase(databaseFile.path);
    await legacyDb.execute('''
      CREATE TABLE videos (
        path TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        folder TEXT NOT NULL,
        root_path TEXT,
        relative_path TEXT,
        file_size INTEGER,
        modified_ms INTEGER,
        tags_json TEXT NOT NULL,
        child_tags_json TEXT NOT NULL,
        is_favorite INTEGER NOT NULL,
        media_details_json TEXT,
        media_fingerprint TEXT,
        thumbnail_error TEXT,
        media_details_error TEXT,
        added_at TEXT NOT NULL,
        last_played_at TEXT
      )
    ''');
    await legacyDb.execute('''
      CREATE TABLE video_tags (
        video_path TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        source TEXT NOT NULL,
        locked INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (video_path, tag_id, source)
      )
    ''');
    final legacyPath = '${dataDir.path}${Platform.pathSeparator}legacy.mp4';
    await legacyDb.insert('videos', {
      'path': legacyPath,
      'title': 'legacy',
      'folder': dataDir.path,
      'tags_json': '[]',
      'child_tags_json': '{}',
      'is_favorite': 1,
      'media_fingerprint': '5|123',
      'added_at': DateTime.utc(2026, 7, 1).toIso8601String(),
    });
    await legacyDb.insert('video_tags', {
      'video_path': legacyPath,
      'tag_id': 'manual:legacy',
      'source': 'manual',
      'locked': 0,
      'created_at': DateTime.utc(2026, 7, 1).toIso8601String(),
      'updated_at': DateTime.utc(2026, 7, 1).toIso8601String(),
    });
    await legacyDb.close();

    final migrated = await _loadTrackedStore(stores);
    final item = _videoByPath(migrated, legacyPath);
    expect(item.videoId, startsWith('vid_'));
    expect(item.isFavorite, isTrue);
    expect(item.isMissing, isFalse);
    expect(item.playbackPosition, Duration.zero);
    expect(item.playbackDuration, Duration.zero);
    expect(item.playbackCompleted, isFalse);
    expect(migrated.videoTagIdsByPathKey[TagRules.pathKey(legacyPath)],
        contains('manual:legacy'));
    final migratedColumns = await migrated.database.rawQuery(
      'PRAGMA table_info(videos)',
    );
    expect(
      migratedColumns.map((row) => row['name']),
      contains('is_detached'),
    );
    expect(
      (await migrated.database.query(
        'videos',
        columns: const <String>['is_detached'],
        where: 'video_id = ?',
        whereArgs: <Object?>[item.videoId],
      ))
          .single['is_detached'],
      0,
    );
  });

  test('scan derives folder tags and persists scanned videos', () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('scan');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}media');
    final nested = await _writeVideoPlaceholder(
      mediaRoot,
      ['Series', 'Album', 'clip.mp4'],
    );
    final defaultAlbum = await _writeVideoPlaceholder(
      mediaRoot,
      ['Series', 'loose.mkv'],
    );

    final store = await _loadTrackedStore(stores);
    final added = await store.addRootAndScan(mediaRoot.path);

    expect(added, 2);
    expect(store.roots, [mediaRoot.path]);
    final nestedItem = _videoByPath(store, nested.path);
    expect(nestedItem.tags, contains('Series'));
    expect(nestedItem.childTags['Series'], contains('Album'));
    expect(nestedItem.relativePath,
        'Series${Platform.pathSeparator}Album${Platform.pathSeparator}clip.mp4');
    final defaultItem = _videoByPath(store, defaultAlbum.path);
    expect(defaultItem.childTags['Series'], contains(TagRules.defaultAlbumTag));
    expect(
      store.tagsById.values.where((tag) => tag.source == TagSource.folder),
      isNotEmpty,
    );

    final reloaded = await _loadTrackedStore(stores);
    expect(reloaded.roots, [mediaRoot.path]);
    expect(reloaded.videos.length, 2);
    expect(_videoByPath(reloaded, nested.path).childTags['Series'],
        contains('Album'));
  });

  test('manual tag maintenance preserves folder-derived tags', () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('manual');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}media');
    final file = await _writeVideoPlaceholder(
      mediaRoot,
      ['Series', 'Album', 'manual.mp4'],
    );

    final store = await _loadTrackedStore(stores);
    await store.addRootAndScan(mediaRoot.path);
    final item = _videoByPath(store, file.path);
    final tag = await store.createManualTag(name: 'Series', groupId: 'manual');

    expect(await store.batchAddManualTag(tag, [item]), 1);
    expect(item.tags, contains('Series'));
    expect(store.videoTagIdsByPathKey[TagRules.pathKey(item.path)],
        contains(tag.id));
    expect((await store.tagUsageSummaries())[tag.id]?.manual, 1);

    expect(await store.batchRemoveManualTag(tag, [item]), 1);
    expect(item.tags, contains('Series'));
    expect(
      store.videoTagIdsByPathKey[TagRules.pathKey(item.path)]
              ?.contains(tag.id) ??
          false,
      isFalse,
    );
  });

  test('same-directory rename preserves stable identity and user data',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('rename_video_path');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot = Directory(p.join(dataDir.path, 'media'));
    final original = await _writeVideoPlaceholder(
      mediaRoot,
      <String>['Series', 'Album', 'before.mp4'],
    );
    final store = await _loadTrackedStore(stores);
    await store.addRootAndScan(mediaRoot.path);
    final item = _videoByPath(store, original.path)
      ..isFavorite = true
      ..playbackPosition = const Duration(seconds: 37)
      ..playbackDuration = const Duration(minutes: 2);
    await store.upsertVideo(item);
    final manual = await store.createManualTag(
      name: '手动保留',
      groupId: 'manual',
    );
    await store.batchAddManualTag(manual, <VideoItem>[item]);
    final stableVideoId = item.videoId;
    final renamedPath = p.join(original.parent.path, 'after.mp4');
    await original.rename(renamedPath);

    await store.renameVideoPath(item, renamedPath);

    expect(item.videoId, stableVideoId);
    expect(item.path, p.normalize(renamedPath));
    expect(item.title, 'after');
    expect(item.isFavorite, isTrue);
    expect(item.playbackPosition, const Duration(seconds: 37));
    expect(item.tags, containsAll(<String>['Series', '手动保留']));
    expect(store.videos[TagRules.pathKey(original.path)], isNull);
    expect(
      store.videoTagIdsByPathKey[TagRules.pathKey(renamedPath)],
      contains(manual.id),
    );

    final reloaded = await _loadTrackedStore(stores);
    final persisted = _videoByPath(reloaded, renamedPath);
    expect(persisted.videoId, stableVideoId);
    expect(persisted.title, 'after');
    expect(persisted.isFavorite, isTrue);
    expect(persisted.playbackPosition, const Duration(seconds: 37));
    expect(
      reloaded.videoTagIdsByPathKey[TagRules.pathKey(renamedPath)],
      contains(manual.id),
    );
  });

  test('save and load preserve metadata and playback fields', () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('persist');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}media');
    final file = await _writeVideoPlaceholder(
      mediaRoot,
      ['Series', 'Album', 'persist.mp4'],
    );

    final store = await _loadTrackedStore(stores);
    await store.addRootAndScan(mediaRoot.path);
    final item = _videoByPath(store, file.path);
    final playedAt = DateTime.utc(2026, 7, 8, 10, 20, 30);
    store.favoriteTags.add('Series');
    item.isFavorite = true;
    item.lastPlayedAt = playedAt;
    await store.save();

    final reloaded = await _loadTrackedStore(stores);
    final reloadedItem = _videoByPath(reloaded, file.path);
    expect(reloaded.roots, [mediaRoot.path]);
    expect(reloaded.favoriteTags, ['Series']);
    expect(reloadedItem.isFavorite, isTrue);
    expect(reloadedItem.lastPlayedAt?.toUtc(), playedAt);
    expect(reloadedItem.tags, contains('Series'));
    expect(reloadedItem.childTags['Series'], contains('Album'));
  });

  test('tag repository persists aliases and visibility flags', () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('tag_metadata');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });

    final store = await _loadTrackedStore(stores);
    final tag = await store.createManualTag(
      name: 'favorite-set',
      groupId: 'manual',
      displayName: '收藏集合',
    );

    await store.updateTagDetails(
      tag,
      displayName: '本地收藏集合',
      aliases: const ['fav', '收藏', 'fav'],
      isFavorite: true,
      isHidden: true,
      sortOrder: 42,
    );

    final reloaded = await _loadTrackedStore(stores);
    final persisted = reloaded.tagsById[tag.id];
    expect(persisted, isNotNull);
    expect(persisted!.displayName, '本地收藏集合');
    expect(persisted.aliases, ['fav', '收藏']);
    expect(persisted.isFavorite, isTrue);
    expect(persisted.isHidden, isTrue);
    expect(persisted.sortOrder, 42);
  });

  test('manual child tag persistence keeps folder child tags separate',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('manual_child');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}media');
    final file = await _writeVideoPlaceholder(
      mediaRoot,
      ['Series', 'Album', 'child.mp4'],
    );

    final store = await _loadTrackedStore(stores);
    await store.addRootAndScan(mediaRoot.path);
    final item = _videoByPath(store, file.path);
    final manualChild = const TagItem(
      id: 'manual:series:manual-child',
      name: 'manual-child',
      displayName: '手动子标签',
      groupId: 'manual',
      parentId: 'Series',
      source: TagSource.manual,
    );
    await store.saveTag(manualChild);
    item.childTags['Series'] = <String>{'Album', 'manual-child'};

    await store.replaceManualTags(item, parentTag: 'Series');

    final reloaded = await _loadTrackedStore(stores);
    final reloadedItem = _videoByPath(reloaded, file.path);
    final pathKey = TagRules.pathKey(file.path);
    expect(reloadedItem.childTags['Series'],
        containsAll(['Album', 'manual-child']));
    expect(reloaded.videoTagIdsByPathKey[pathKey], contains(manualChild.id));
    final summaries = await reloaded.tagUsageSummaries();
    expect(summaries[manualChild.id]?.manual, 1);
    expect(
      reloaded.tagsById.values.where((tag) =>
          tag.source == TagSource.folder &&
          tag.parentId == 'Series' &&
          tag.name == 'Album'),
      isNotEmpty,
    );
  });

  test('video repository persists direct upserts and deletes tag links',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('video_repo');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}media');
    final file = await _writeVideoPlaceholder(
      mediaRoot,
      ['Direct', 'upsert.mp4'],
    );

    final store = await _loadTrackedStore(stores);
    final addedAt = DateTime.utc(2026, 7, 8, 11, 30);
    final direct = VideoItem(
      path: file.path,
      title: 'upsert',
      folder: file.parent.path,
      rootPath: mediaRoot.path,
      relativePath: 'Direct${Platform.pathSeparator}upsert.mp4',
      fileSize: await file.length(),
      modifiedMs: (await file.lastModified()).millisecondsSinceEpoch,
      tags: {'Direct'},
      childTags: const <String, Set<String>>{},
      isFavorite: true,
      mediaFingerprint: 'fingerprint-1',
      addedAt: addedAt,
      lastPlayedAt: addedAt.add(const Duration(minutes: 5)),
    );

    await store.upsertVideo(direct);
    final reloaded = await _loadTrackedStore(stores);
    final persisted = _videoByPath(reloaded, file.path);
    expect(persisted.isFavorite, isTrue);
    expect(persisted.mediaFingerprint, 'fingerprint-1');
    expect(persisted.relativePath, 'Direct${Platform.pathSeparator}upsert.mp4');

    final tag =
        await reloaded.createManualTag(name: 'manual', groupId: 'manual');
    expect(await reloaded.batchAddManualTag(tag, [persisted]), 1);
    expect(
      reloaded.videoTagIdsByPathKey[TagRules.pathKey(file.path)],
      contains(tag.id),
    );

    await reloaded.deleteVideo(file.path);
    final deleted = await _loadTrackedStore(stores);
    expect(deleted.videos[TagRules.pathKey(file.path)], isNull);
    expect(deleted.videoTagIdsByPathKey[TagRules.pathKey(file.path)], isNull);
    expect((await deleted.tagUsageSummaries())[tag.id]?.manual ?? 0, 0);
  });

  test('metadata repository dedupes roots and favorite tags on reload',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('metadata_repo');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}media');
    await mediaRoot.create(recursive: true);

    final store = await _loadTrackedStore(stores);
    store.roots
      ..add(mediaRoot.path)
      ..add('${mediaRoot.path}${Platform.pathSeparator}');
    store.favoriteTags
      ..add('alpha')
      ..add('Alpha')
      ..add('beta');
    await store.saveMetadata();

    final reloaded = await _loadTrackedStore(stores);
    expect(reloaded.roots, [mediaRoot.path]);
    expect(reloaded.favoriteTags, ['alpha', 'beta']);

    await reloaded.removeRoot('${mediaRoot.path}${Platform.pathSeparator}');
    final withoutRoot = await _loadTrackedStore(stores);
    expect(withoutRoot.roots, isEmpty);
    expect(withoutRoot.favoriteTags, ['alpha', 'beta']);
  });

  test('removing and readding root preserves detached identity and user data',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('remove_root_records');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}media');
    final file = await _writeVideoPlaceholder(
      mediaRoot,
      ['Series', 'detached.mp4'],
    );

    final store = await _loadTrackedStore(stores);
    expect(await store.addRootAndScan(mediaRoot.path), 1);
    final item = _videoByPath(store, file.path)
      ..isFavorite = true
      ..lastPlayedAt = DateTime.utc(2026, 7, 16, 8)
      ..playbackPosition = const Duration(seconds: 41)
      ..playbackDuration = const Duration(minutes: 2)
      ..playbackPositionUpdatedAt = DateTime.utc(2026, 7, 16, 8, 1);
    final stableVideoId = item.videoId;
    await store.upsertVideo(item);
    final manual =
        await store.createManualTag(name: '保留性测试', groupId: 'manual');
    expect(await store.batchAddManualTag(manual, [item]), 1);

    final removed = await store.removeRoot(mediaRoot.path);
    expect(removed.map((item) => item.videoId), [item.videoId]);
    expect(store.videos, isEmpty);
    expect(await file.exists(), isTrue);

    final reloaded = await _loadTrackedStore(stores);
    expect(reloaded.roots, isEmpty);
    expect(reloaded.videos, isEmpty);
    final detached = reloaded.detachedVideos[TagRules.pathKey(file.path)];
    expect(detached?.videoId, stableVideoId);
    expect(detached?.isFavorite, isTrue);
    expect(detached?.playbackPosition, const Duration(seconds: 41));
    expect(
      reloaded.videoTagIdsByPathKey[TagRules.pathKey(file.path)],
      contains(manual.id),
    );
    // 标签管理器继续显示归档引用，避免用户误删 detached 视频仍依赖的手动标签。
    expect((await reloaded.tagUsageSummaries())[manual.id]?.manual ?? 0, 1);
    await reloaded.upsertVideo(detached!);
    await reloaded.upsertVideos(<VideoItem>[detached]);
    await reloaded.rebuildTagIndex();
    expect(reloaded.videos, isEmpty);
    expect(
      (await reloaded.database.query(
        'videos',
        columns: const <String>['is_detached'],
        where: 'video_id = ?',
        whereArgs: <Object?>[stableVideoId],
      ))
          .single['is_detached'],
      1,
    );
    expect(
      reloaded.videoTagIdsByPathKey[TagRules.pathKey(file.path)],
      contains(manual.id),
    );

    expect(await reloaded.addRootAndScan(mediaRoot.path), 0);
    final restored = _videoByPath(reloaded, file.path);
    expect(restored.videoId, stableVideoId);
    expect(restored.isFavorite, isTrue);
    expect(restored.playbackPosition, const Duration(seconds: 41));
    expect(restored.playbackDuration, const Duration(minutes: 2));
    expect(
      reloaded.videoTagIdsByPathKey[TagRules.pathKey(file.path)],
      contains(manual.id),
    );
    expect(reloaded.detachedVideos, isEmpty);
    expect((await reloaded.tagUsageSummaries())[manual.id]?.manual ?? 0, 1);

    final restoredReload = await _loadTrackedStore(stores);
    final persisted = _videoByPath(restoredReload, file.path);
    expect(persisted.videoId, stableVideoId);
    expect(persisted.isFavorite, isTrue);
    expect(persisted.playbackPosition, const Duration(seconds: 41));
    expect(restoredReload.detachedVideos, isEmpty);
  });

  test('removing parent root keeps videos covered by a nested root', () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('remove_overlap_root');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final parentRoot = Directory(p.join(dataDir.path, 'media'));
    final nestedRoot = Directory(p.join(parentRoot.path, 'nested'));
    final file = await _writeVideoPlaceholder(nestedRoot, ['covered.mp4']);
    final store = await _loadTrackedStore(stores);
    store.roots.addAll([parentRoot.path, nestedRoot.path]);
    await store.saveMetadata();
    final item = VideoItem(
      path: file.path,
      title: 'covered',
      folder: nestedRoot.path,
      rootPath: nestedRoot.path,
      relativePath: 'covered.mp4',
      fileSize: await file.length(),
      modifiedMs: (await file.lastModified()).millisecondsSinceEpoch,
      tags: const <String>{},
      addedAt: DateTime.utc(2026, 7, 13),
    );
    await store.upsertVideo(item);

    final removed = await store.removeRoot(parentRoot.path);
    expect(removed, isEmpty);
    expect(store.roots, [nestedRoot.path]);
    expect(store.videos[TagRules.pathKey(file.path)]?.videoId, item.videoId);

    final reloaded = await _loadTrackedStore(stores);
    expect(reloaded.roots, [nestedRoot.path]);
    expect(reloaded.videos[TagRules.pathKey(file.path)]?.videoId, item.videoId);
  });

  test('adding a moved root relinks detached video by unique fingerprint',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('detached_root_relink');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final sourceRoot = Directory(p.join(dataDir.path, 'source'));
    final destinationRoot = Directory(p.join(dataDir.path, 'destination'));
    final original = await _writeVideoPlaceholder(
      sourceRoot,
      ['Series', 'moving.mp4'],
    );
    final store = await _loadTrackedStore(stores);
    expect(await store.addRootAndScan(sourceRoot.path), 1);
    final item = _videoByPath(store, original.path)..isFavorite = true;
    final stableVideoId = item.videoId;
    final manual =
        await store.createManualTag(name: 'detached-move', groupId: 'manual');
    await store.batchAddManualTag(manual, <VideoItem>[item]);
    await store.upsertVideo(item);

    await store.removeRoot(sourceRoot.path);
    final moved = File(p.join(destinationRoot.path, 'Renamed', 'moved.mp4'));
    await moved.parent.create(recursive: true);
    await original.rename(moved.path);

    expect(await store.addRootAndScan(destinationRoot.path), 0);

    final relinked = _videoByPath(store, moved.path);
    expect(relinked.videoId, stableVideoId);
    expect(relinked.isFavorite, isTrue);
    expect(store.detachedVideos, isEmpty);
    expect(
      store.videoTagIdsByPathKey[TagRules.pathKey(moved.path)],
      contains(manual.id),
    );
    expect(store.videos[TagRules.pathKey(original.path)], isNull);

    final reloaded = await _loadTrackedStore(stores);
    final persisted = _videoByPath(reloaded, moved.path);
    expect(persisted.videoId, stableVideoId);
    expect(persisted.isFavorite, isTrue);
    expect(reloaded.detachedVideos, isEmpty);
  });

  test(
      'independent backup restores favorite and manual tags after identity loss',
      () async {
    final stores = <LibraryStore>[];
    final dataDir =
        await _prepareStoreTestDirectory('dependency_backup_restore');
    final mediaRoot = Directory(p.join(dataDir.path, 'media'));
    final file = await _writeVideoPlaceholder(
      mediaRoot,
      <String>['Series', 'backup.mp4'],
    );
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });

    final store = await _loadTrackedStore(
      stores,
      dataBackupEnabled: true,
    );
    await store.addRootAndScan(mediaRoot.path);
    final item = _videoByPath(store, file.path)
      ..isFavorite = true
      ..playbackPosition = const Duration(seconds: 37)
      ..playbackDuration = const Duration(minutes: 3)
      ..lastPlayedAt = DateTime.utc(2026, 7, 16, 10);
    final originalVideoId = item.videoId;
    final tag = await store.createManualTag(
      name: '备份恢复标签',
      groupId: 'manual',
    );
    await store.batchAddManualTag(tag, <VideoItem>[item]);
    await store.upsertVideo(item);
    await store.dataBackupService.flush();
    expect(
      (await store.dataBackupService.database.query(
        'video_dependency_backups',
      )),
      hasLength(1),
    );

    await store.close();
    stores.remove(store);
    final libraryFile = await _testPaths.libraryDatabaseFile();
    final database = await databaseFactoryFfi.openDatabase(libraryFile.path);
    await database.delete('video_tags',
        where: 'video_id = ?', whereArgs: [originalVideoId]);
    await database
        .delete('videos', where: 'video_id = ?', whereArgs: [originalVideoId]);
    await database.close();

    final rebuilt = await _loadTrackedStore(
      stores,
      dataBackupEnabled: true,
    );
    await rebuilt.scanWithChanges();
    final restored = _videoByPath(rebuilt, file.path);
    expect(restored.videoId, originalVideoId);
    expect(restored.isFavorite, isTrue);
    expect(restored.playbackPosition, const Duration(seconds: 37));
    expect(
      rebuilt.videoTagIdsByPathKey[TagRules.pathKey(file.path)],
      contains(tag.id),
    );

    await rebuilt.deleteVideo(file.path);
    expect(
      await rebuilt.dataBackupService.database.query(
        'video_dependency_backups',
        where: 'video_id = ?',
        whereArgs: <Object?>[originalVideoId],
      ),
      isEmpty,
    );
  });

  test('backup pauses for playback and resumes unfinished cursor after restart',
      () async {
    final stores = <LibraryStore>[];
    final dataDir =
        await _prepareStoreTestDirectory('dependency_backup_resume');
    final mediaRoot = Directory(p.join(dataDir.path, 'media'));
    for (var index = 0; index < 70; index += 1) {
      await _writeVideoPlaceholder(
        mediaRoot,
        <String>['batch', 'video_$index.mp4'],
      );
    }
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });

    final source = await _loadTrackedStore(stores);
    await source.addRootAndScan(mediaRoot.path);
    await source.close();
    stores.remove(source);

    final firstRun = await _loadTrackedStore(
      stores,
      dataBackupEnabled: true,
    );
    await firstRun.dataBackupService.pauseForPlayback();
    expect(
      firstRun.dataBackupStatus.phase,
      DataBackupPhase.pausedForPlayback,
    );
    final pausedCount = (await firstRun.dataBackupService.database.rawQuery(
      'SELECT COUNT(*) AS count FROM video_dependency_backups',
    ))
        .single['count'];
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(
      (await firstRun.dataBackupService.database.rawQuery(
        'SELECT COUNT(*) AS count FROM video_dependency_backups',
      ))
          .single['count'],
      pausedCount,
    );
    await firstRun.close();
    stores.remove(firstRun);

    final resumed = await _loadTrackedStore(
      stores,
      dataBackupEnabled: true,
    );
    await resumed.dataBackupService.flush();
    expect(
      (await resumed.dataBackupService.database.rawQuery(
        'SELECT COUNT(*) AS count FROM video_dependency_backups',
      ))
          .single['count'],
      70,
    );
    await resumed.dataBackupService.runNow();
    await resumed.dataBackupService.flush();
    expect(
      (await resumed.dataBackupService.database.query(
        'backup_control',
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object?>['full_sync_in_progress'],
      ))
          .single['value'],
      '0',
    );
  });

  test('backup integrity detects stale data and portable export omits paths',
      () async {
    final stores = <LibraryStore>[];
    final dataDir =
        await _prepareStoreTestDirectory('dependency_backup_integrity');
    final mediaRoot = Directory(p.join(dataDir.path, 'media'));
    final file = await _writeVideoPlaceholder(
      mediaRoot,
      <String>['Series', 'integrity.mp4'],
    );
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });

    final store = await _loadTrackedStore(
      stores,
      dataBackupEnabled: true,
    );
    await store.addRootAndScan(mediaRoot.path);
    await store.dataBackupService.flush();

    final healthy = await store.checkDataBackupIntegrity();
    expect(healthy.isHealthy, isTrue);
    expect(healthy.backupRecords, 1);
    expect(healthy.currentVideos, 1);

    // usage_count 是全库派生统计，不属于单视频用户依赖；改变它不能让所有引用视频误报 stale。
    await store.database.update(
      'tags',
      <String, Object?>{'usage_count': 999999},
    );
    final usageCountOnlyChanged = await store.checkDataBackupIntegrity();
    expect(usageCountOnlyChanged.isHealthy, isTrue);
    expect(usageCountOnlyChanged.staleCurrentSnapshots, 0);

    final exportBytes = await store.createDataBackupExport();
    final exportText = utf8.decode(exportBytes);
    final exportDocument =
        (jsonDecode(exportText) as Map).cast<String, Object?>();
    expect(
      exportDocument['format'],
      'local_tag_player_video_dependency_backup',
    );
    expect(exportDocument['recordCount'], 1);
    expect(exportText, isNot(contains(file.path)));
    expect(exportText, isNot(contains('"path"')));

    final item = _videoByPath(store, file.path);
    await store.database.update(
      'videos',
      <String, Object?>{'is_favorite': 1},
      where: 'video_id = ?',
      whereArgs: <Object?>[item.videoId],
    );
    final stale = await store.checkDataBackupIntegrity();
    expect(stale.isHealthy, isFalse);
    expect(stale.staleCurrentSnapshots, 1);

    await store.runDataBackupNow();
    await store.dataBackupService.flush();
    expect((await store.checkDataBackupIntegrity()).isHealthy, isTrue);
  });

  test('clean restart skips full reconciliation and preserves snapshot writes',
      () async {
    final stores = <LibraryStore>[];
    final dataDir =
        await _prepareStoreTestDirectory('dependency_backup_clean_restart');
    final mediaRoot = Directory(p.join(dataDir.path, 'media'));
    for (var index = 0; index < 3; index += 1) {
      await _writeVideoPlaceholder(
        mediaRoot,
        <String>['clean', 'video_$index.mp4'],
      );
    }
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });

    final first = await _loadTrackedStore(
      stores,
      dataBackupEnabled: true,
    );
    await first.addRootAndScan(mediaRoot.path);
    await first.dataBackupService.flush();
    final beforeRows = await first.dataBackupService.database.query(
      'video_dependency_backups',
      columns: const <String>['video_id', 'updated_at'],
      orderBy: 'video_id ASC',
    );
    final beforeCompleted = (await first.dataBackupService.database.query(
      'backup_control',
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: const <Object?>['last_completed_at'],
    ))
        .single['value'];
    await first.close();
    stores.remove(first);

    final reopened = await _loadTrackedStore(
      stores,
      dataBackupEnabled: true,
    );
    await reopened.dataBackupService.flush();
    final afterRows = await reopened.dataBackupService.database.query(
      'video_dependency_backups',
      columns: const <String>['video_id', 'updated_at'],
      orderBy: 'video_id ASC',
    );
    final afterCompleted = (await reopened.dataBackupService.database.query(
      'backup_control',
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: const <Object?>['last_completed_at'],
    ))
        .single['value'];
    expect(afterRows, beforeRows);
    expect(afterCompleted, beforeCompleted);
    expect(
      (await reopened.dataBackupService.database.query(
        'backup_control',
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object?>['full_sync_in_progress'],
      ))
          .single['value'],
      '0',
    );

    await reopened.runDataBackupNow();
    await reopened.dataBackupService.flush();
    expect(
      await reopened.dataBackupService.database.query(
        'video_dependency_backups',
        columns: const <String>['video_id', 'updated_at'],
        orderBy: 'video_id ASC',
      ),
      beforeRows,
    );
  });

  test(
      'enabling backup after disabled startup performs required reconciliation',
      () async {
    final stores = <LibraryStore>[];
    final dataDir =
        await _prepareStoreTestDirectory('dependency_backup_reenable');
    final mediaRoot = Directory(p.join(dataDir.path, 'media'));
    await _writeVideoPlaceholder(
      mediaRoot,
      <String>['reenable', 'video.mp4'],
    );
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });

    final store = await _loadTrackedStore(stores);
    await store.addRootAndScan(mediaRoot.path);
    expect(
      await store.dataBackupService.database.query(
        'video_dependency_backups',
      ),
      isEmpty,
    );

    await store.setDataBackupEnabled(true);
    await store.dataBackupService.flush();
    expect(
      await store.dataBackupService.database.query(
        'video_dependency_backups',
      ),
      hasLength(1),
    );
  });

  test('scan coordinator marks missing videos and preserves manual tags',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('scan_remove');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}media');
    final kept = await _writeVideoPlaceholder(
      mediaRoot,
      ['Series', 'Album', 'kept.mp4'],
    );
    final removed = await _writeVideoPlaceholder(
      mediaRoot,
      ['Series', 'Album', 'removed.mp4'],
    );

    final store = await _loadTrackedStore(stores);
    expect(await store.addRootAndScan(mediaRoot.path), 2);
    final keptItem = _videoByPath(store, kept.path);
    final removedItem = _videoByPath(store, removed.path);
    final manual =
        await store.createManualTag(name: 'manual', groupId: 'manual');
    expect(await store.batchAddManualTag(manual, [keptItem, removedItem]), 2);

    await removed.delete();
    expect(await store.scan(), 0);

    expect(store.videos[TagRules.pathKey(removed.path)]?.isMissing, isTrue);
    expect(store.videoTagIdsByPathKey[TagRules.pathKey(removed.path)],
        contains(manual.id));
    expect(store.videoTagIdsByPathKey[TagRules.pathKey(kept.path)],
        contains(manual.id));

    final reloaded = await _loadTrackedStore(stores);
    expect(reloaded.videos[TagRules.pathKey(removed.path)]?.isMissing, isTrue);
    expect(reloaded.videoTagIdsByPathKey[TagRules.pathKey(removed.path)],
        contains(manual.id));
    expect(reloaded.videoTagIdsByPathKey[TagRules.pathKey(kept.path)],
        contains(manual.id));
  });

  test('scan coordinator clears stale media cache after content changes',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('scan_content_change');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}media');
    final file = await _writeVideoPlaceholder(
      mediaRoot,
      ['Series', 'Album', 'changed.mp4'],
    );

    final store = await _loadTrackedStore(stores);
    await store.addRootAndScan(mediaRoot.path);
    final item = _videoByPath(store, file.path);
    final oldFingerprint = item.mediaFingerprint;
    item.mediaDetails = const MediaDetails(videoCodec: 'h264');
    item.mediaDetailsError = 'old details error';
    item.thumbnailError = 'old thumbnail error';
    await store.upsertVideo(item);

    await Future<void>.delayed(const Duration(milliseconds: 2));
    await file.writeAsBytes([9, 8, 7, 6, 5, 4]);
    await store.scan();

    final rescanned = _videoByPath(store, file.path);
    expect(rescanned.mediaFingerprint, isNot(oldFingerprint));
    expect(rescanned.mediaDetails, isNull);
    expect(rescanned.mediaDetailsError, isNull);
    expect(rescanned.thumbnailError, isNull);
  });

  test('unique fingerprint relink preserves stable identity and user data',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('stable_relink');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}media');
    final original = await _writeVideoPlaceholder(
      mediaRoot,
      ['OldSeries', 'Album', 'moving.mp4'],
    );

    final store = await _loadTrackedStore(stores);
    await store.addRootAndScan(mediaRoot.path);
    final item = _videoByPath(store, original.path);
    final videoId = item.videoId;
    final manual =
        await store.createManualTag(name: 'keep-me', groupId: 'manual');
    await store.batchAddManualTag(manual, [item]);
    item
      ..isFavorite = true
      ..lastPlayedAt = DateTime.utc(2026, 7, 11, 8)
      ..playbackPosition = const Duration(seconds: 37)
      ..playbackDuration = const Duration(minutes: 3)
      ..playbackCompleted = false
      ..playbackPositionUpdatedAt = DateTime.utc(2026, 7, 11, 8, 1);
    await store.upsertVideo(item);

    final moved = File(
      [mediaRoot.path, 'NewSeries', 'Renamed', 'moved.mp4']
          .join(Platform.pathSeparator),
    );
    await moved.parent.create(recursive: true);
    await original.rename(moved.path);
    await store.scan();

    expect(store.videos[TagRules.pathKey(original.path)], isNull);
    final relinked = _videoByPath(store, moved.path);
    expect(relinked.videoId, videoId);
    expect(relinked.isFavorite, isTrue);
    expect(relinked.playbackPosition, const Duration(seconds: 37));
    expect(relinked.playbackDuration, const Duration(minutes: 3));
    expect(relinked.playbackCompleted, isFalse);
    expect(videoIsContinueWatching(relinked), isTrue);
    expect(relinked.isMissing, isFalse);
    expect(store.videoTagIdsByPathKey[TagRules.pathKey(moved.path)],
        contains(manual.id));

    final reloaded = await _loadTrackedStore(stores);
    final persisted = _videoByPath(reloaded, moved.path);
    expect(persisted.videoId, videoId);
    expect(persisted.playbackPosition, const Duration(seconds: 37));
    expect(persisted.playbackDuration, const Duration(minutes: 3));
    expect(persisted.playbackCompleted, isFalse);
    expect(persisted.isFavorite, isTrue);
    expect(persisted.lastPlayedAt, isNotNull);
    expect(videoIsContinueWatching(persisted), isTrue);
    expect(reloaded.videoTagIdsByPathKey[TagRules.pathKey(moved.path)],
        contains(manual.id));
  });

  test('manual missing relink preserves identity and rejects wrong content',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('manual_relink');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}media');
    final original =
        await _writeVideoPlaceholder(mediaRoot, ['Series', 'original.mp4']);
    final store = await _loadTrackedStore(stores);
    await store.addRootAndScan(mediaRoot.path);
    final item = _videoByPath(store, original.path);
    final videoId = item.videoId;
    final manual =
        await store.createManualTag(name: 'manual-keep', groupId: 'manual');
    await store.batchAddManualTag(manual, [item]);
    await original.delete();
    await store.scan();
    expect(item.isMissing, isTrue);

    final wrong = await _writeVideoPlaceholder(
      Directory('${dataDir.path}${Platform.pathSeparator}outside'),
      ['wrong.mp4'],
    );
    await wrong.writeAsBytes([9, 9, 9]);
    await expectLater(
      store.relinkMissingVideo(item, wrong.path),
      throwsA(isA<StateError>()),
    );
    expect(item.isMissing, isTrue);

    final replacement = await _writeVideoPlaceholder(
      Directory('${dataDir.path}${Platform.pathSeparator}replacement'),
      ['renamed.mp4'],
    );
    await store.relinkMissingVideo(item, replacement.path);
    final relinked = _videoByPath(store, replacement.path);
    expect(relinked.videoId, videoId);
    expect(relinked.isMissing, isFalse);
    expect(store.videoTagIdsByPathKey[TagRules.pathKey(replacement.path)],
        contains(manual.id));
  });

  test('cross-drive bulk relink soak preserves stable user data', () async {
    if (!Platform.isWindows || !await Directory('E:\\').exists()) {
      return;
    }
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('cross_drive_soak');
    final targetRoot = Directory(
      'E:\\LocalTagPlayerSoak_${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
      if (await targetRoot.exists()) {
        await targetRoot.delete(recursive: true);
      }
    });
    final sourceRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}source');
    final originals = <File>[];
    for (var index = 0; index < 20; index++) {
      originals.add(await _writeVideoPlaceholder(
        sourceRoot,
        ['Series', 'Album', 'soak_$index.mp4'],
      ));
    }
    final store = await _loadTrackedStore(stores);
    await store.addRootAndScan(sourceRoot.path);
    final manual =
        await store.createManualTag(name: 'cross-drive', groupId: 'manual');
    final originalIds = <String>{};
    for (final item in store.videos.values) {
      originalIds.add(item.videoId);
      await store.batchAddManualTag(manual, [item]);
      item
        ..isFavorite = true
        ..lastPlayedAt = DateTime.utc(2026, 7, 11, 14)
        ..playbackPosition = const Duration(seconds: 12)
        ..playbackDuration = const Duration(minutes: 2);
      await store.upsertVideo(item);
    }

    for (final original in originals) {
      final relative = p.relative(original.path, from: sourceRoot.path);
      final target = File(p.join(targetRoot.path, relative));
      await target.parent.create(recursive: true);
      await original.copy(target.path);
      await original.delete();
    }
    await store.scan();
    expect(store.videos.values.every((item) => item.isMissing), isTrue);

    final previews = await const BulkPathRelinkService().preview(
      store: store,
      oldPrefix: sourceRoot.path,
      newPrefix: targetRoot.path,
    );
    expect(previews, hasLength(20));
    expect(previews.every((entry) => entry.status == BulkRelinkStatus.ready),
        isTrue);
    final execution = await const BulkPathRelinkService().execute(
      store: store,
      previews: previews,
      oldPrefix: sourceRoot.path,
      newPrefix: targetRoot.path,
    );
    expect(execution.succeededCount, 20);
    expect(execution.failedVideoIds, isEmpty);

    final reloaded = await _loadTrackedStore(stores);
    expect(reloaded.videos.length, 20);
    expect(reloaded.roots, [TagRules.normalizeRootPath(targetRoot.path)]);
    expect(reloaded.videos.values.map((item) => item.videoId).toSet(),
        originalIds);
    for (final item in reloaded.videos.values) {
      expect(item.isMissing, isFalse);
      expect(item.isFavorite, isTrue);
      expect(item.playbackPosition, const Duration(seconds: 12));
      expect(reloaded.videoTagIdsByPathKey[TagRules.pathKey(item.path)],
          contains(manual.id));
    }
  });

  test('bulk relink retains stale preview failures for retry', () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('bulk_retry');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final oldRoot = Directory(p.join(dataDir.path, 'old'));
    final newRoot = Directory(p.join(dataDir.path, 'new'));
    final original = await _writeVideoPlaceholder(oldRoot, ['retry.mp4']);
    final target = await _writeVideoPlaceholder(newRoot, ['retry.mp4']);
    final store = await _loadTrackedStore(stores);
    await store.addRootAndScan(oldRoot.path);
    final item = _videoByPath(store, original.path);
    await original.delete();
    await store.scan();
    final previews = await const BulkPathRelinkService().preview(
      store: store,
      oldPrefix: oldRoot.path,
      newPrefix: newRoot.path,
    );
    expect(previews.single.status, BulkRelinkStatus.ready);

    await target.delete();
    final failed = await const BulkPathRelinkService().execute(
      store: store,
      previews: previews,
      oldPrefix: oldRoot.path,
      newPrefix: newRoot.path,
    );
    expect(failed.succeededCount, 0);
    expect(failed.failedVideoIds, {item.videoId});
    expect(item.isMissing, isTrue);

    await _writeVideoPlaceholder(newRoot, ['retry.mp4']);
    final retried = await const BulkPathRelinkService().execute(
      store: store,
      previews: previews,
      oldPrefix: oldRoot.path,
      newPrefix: newRoot.path,
    );
    expect(retried.succeededCount, 1);
    expect(retried.failedVideoIds, isEmpty);
  });

  test('ambiguous fingerprints never auto-relink user data', () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('ambiguous_relink');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}media');
    final first = await _writeVideoPlaceholder(mediaRoot, ['A', 'first.mp4']);
    final second = await _writeVideoPlaceholder(mediaRoot, ['B', 'second.mp4']);
    final sharedModified = DateTime.utc(2026, 7, 11, 9);
    await first.setLastModified(sharedModified);
    await second.setLastModified(sharedModified);

    final store = await _loadTrackedStore(stores);
    await store.addRootAndScan(mediaRoot.path);
    final originalIds = {
      _videoByPath(store, first.path).videoId,
      _videoByPath(store, second.path).videoId,
    };
    final moved = File(
      [mediaRoot.path, 'C', 'moved.mp4'].join(Platform.pathSeparator),
    );
    await moved.parent.create(recursive: true);
    await first.rename(moved.path);
    await second.delete();
    await store.scan();

    final imported = _videoByPath(store, moved.path);
    expect(originalIds, isNot(contains(imported.videoId)));
    expect(store.videos.values.where((item) => item.isMissing).length, 2);
  });

  test('scan service ignores inaccessible or missing roots without deleting',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('scan_missing_root');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}media');
    final missingRoot = '${dataDir.path}${Platform.pathSeparator}missing-root';
    final file = await _writeVideoPlaceholder(
      mediaRoot,
      ['Series', 'Album', 'kept.mp4'],
    );

    final store = await _loadTrackedStore(stores);
    await store.addRootAndScan(mediaRoot.path);
    store.roots
      ..clear()
      ..add(missingRoot);

    expect(await store.scan(), 0);
    expect(store.videos[TagRules.pathKey(file.path)], isNotNull);
  });

  test(
      'tag maintenance removes manual child link without deleting folder child',
      () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('tag_strategy');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}media');
    final file = await _writeVideoPlaceholder(
      mediaRoot,
      ['Series', 'Album', 'strategy.mp4'],
    );

    final store = await _loadTrackedStore(stores);
    await store.addRootAndScan(mediaRoot.path);
    final item = _videoByPath(store, file.path);
    final manualChild = const TagItem(
      id: 'manual:series:album',
      name: 'Album',
      displayName: 'manual Album',
      groupId: 'manual',
      parentId: 'Series',
      source: TagSource.manual,
    );
    await store.saveTag(manualChild);
    expect(await store.batchAddManualTag(manualChild, [item]), 1);
    expect(store.videoTagIdsByPathKey[TagRules.pathKey(file.path)],
        contains(manualChild.id));

    expect(await store.batchRemoveManualTag(manualChild, [item]), 1);

    expect(item.childTags['Series'], contains('Album'));
    expect(
      store.videoTagIdsByPathKey[TagRules.pathKey(file.path)]
              ?.contains(manualChild.id) ??
          false,
      isFalse,
    );
    final reloaded = await _loadTrackedStore(stores);
    final reloadedItem = _videoByPath(reloaded, file.path);
    expect(reloadedItem.childTags['Series'], contains('Album'));
    expect(
      reloaded.videoTagIdsByPathKey[TagRules.pathKey(file.path)]
              ?.contains(manualChild.id) ??
          false,
      isFalse,
    );
  });

  test('tag maintenance rejects non-manual tags in batch operations', () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('tag_reject_source');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final mediaRoot =
        Directory('${dataDir.path}${Platform.pathSeparator}media');
    final file = await _writeVideoPlaceholder(
      mediaRoot,
      ['Series', 'Album', 'reject.mp4'],
    );

    final store = await _loadTrackedStore(stores);
    await store.addRootAndScan(mediaRoot.path);
    final item = _videoByPath(store, file.path);
    final folderTag = store.tagsById.values.firstWhere(
      (tag) => tag.source == TagSource.folder && tag.groupId == 'folder.child',
    );

    await expectLater(
      store.batchAddManualTag(folderTag, [item]),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      store.batchRemoveManualTag(folderTag, [item]),
      throwsA(isA<StateError>()),
    );
  });
}
