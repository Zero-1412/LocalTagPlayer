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
}
