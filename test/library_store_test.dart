import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ignore_for_file: slash_for_doc_comments

var _sqliteConfigured = false;

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
  AppPaths.debugUseDataDirectoryForTesting(directory);
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
Future<LibraryStore> _loadTrackedStore(List<LibraryStore> stores) async {
  final store = await LibraryStore.load();
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
  tearDown(() {
    AppPaths.debugUseDataDirectoryForTesting(null);
  });

  test('legacy path-keyed schema backfills stable video identity', () async {
    final stores = <LibraryStore>[];
    final dataDir = await _prepareStoreTestDirectory('identity_migration');
    addTearDown(() async {
      await _closeTrackedStores(stores);
      await dataDir.delete(recursive: true);
    });
    final databaseFile = await AppPaths.libraryDatabaseFile();
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
    expect(migrated.videoTagIdsByPathKey[TagRules.pathKey(legacyPath)],
        contains('manual:legacy'));
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
    expect(relinked.isMissing, isFalse);
    expect(store.videoTagIdsByPathKey[TagRules.pathKey(moved.path)],
        contains(manual.id));

    final reloaded = await _loadTrackedStore(stores);
    final persisted = _videoByPath(reloaded, moved.path);
    expect(persisted.videoId, videoId);
    expect(persisted.playbackPosition, const Duration(seconds: 37));
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
