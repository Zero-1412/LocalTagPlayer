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
}
