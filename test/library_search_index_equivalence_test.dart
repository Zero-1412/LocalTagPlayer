import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/models/platform_models.dart';
import 'package:local_tag_player/src/models/video_item.dart';
import 'package:local_tag_player/src/services/library/library_query_compiler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ignore_for_file: slash_for_doc_comments

/** 只统计真实事务次数，不替换 SQLite 的查询或重建实现。 */
class _CountingSearchIndex extends LibrarySearchIndex {
  var rebuildCount = 0;

  @override
  Future<void> rebuild(Database db) async {
    rebuildCount++;
    await super.rebuild(db);
  }
}

/** 隔离的真实 SQLite fixture；比较候选加最终校验与完整查询的 stable-ID 集合。 */
void main() {
  late Database db;
  late LibrarySearchIndex index;
  late VideoItem video;
  late TagItem tag;
  const compiler = LibraryQueryCompiler();
  const profile = LibraryQueryProfile(videoCount: 2000, fts5Available: true);

  setUpAll(() {
    if (Platform.isWindows) {
      DynamicLibrary.open(
          File('windows/tools/sqlite/sqlite3.dll').absolute.path);
    }
    sqfliteFfiInit();
  });
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    index = LibrarySearchIndex();
    await db
        .execute('CREATE TABLE videos(video_id TEXT PRIMARY KEY, title TEXT, '
            'path TEXT, relative_path TEXT, folder TEXT)');
    await db.execute('CREATE TABLE tags(id TEXT PRIMARY KEY, name TEXT, '
        'display_name TEXT, aliases_json TEXT)');
    await db.execute('CREATE TABLE video_tags(video_id TEXT, tag_id TEXT)');
    video = VideoItem(
        videoId: 'stable',
        path: '/library/pathword.mp4',
        title: 'nature 😀a 😀ab 中文测试',
        folder: '/library',
        tags: {},
        addedAt: DateTime.utc(2026));
    tag = const TagItem(
        id: 'manual:identifier',
        name: 'tagname',
        displayName: 'displayword',
        groupId: 'manual',
        source: TagSource.manual,
        aliases: ['say"hello', r'back\slash', 'plainalias']);
    await db.insert('videos', {
      'video_id': video.videoId,
      'title': video.title,
      'path': video.path,
      'folder': video.folder
    });
    await db.insert('tags', {
      'id': tag.id,
      'name': tag.name,
      'display_name': tag.displayName,
      'aliases_json': jsonEncode(tag.aliases)
    });
    await db
        .insert('video_tags', {'video_id': video.videoId, 'tag_id': tag.id});
  });
  tearDown(() async => db.close());

  Future<void> equivalent(String keyword,
      {int revision = 1, bool present = true}) async {
    final query = FilterQuery(keyword: keyword);
    final context = TagQueryContext(tagsById: {
      tag.id: tag
    }, videoTagIdsByVideoId: {
      video.videoId: {tag.id}
    });
    final all = present ? [video] : <VideoItem>[];
    final expected = all
        .where((v) => query.matches(v, tagContext: context))
        .map((v) => v.videoId)
        .toSet();
    final plan = compiler.compile(query, profile);
    var candidates = all;
    if (plan.hasSqlCandidate) {
      expect(await index.ensureFresh(db, revision: revision), isTrue);
      final rows = await db.rawQuery(
          'SELECT video_id FROM videos WHERE ${plan.whereSql}', plan.whereArgs);
      final ids = rows.map((row) => row['video_id']).toSet();
      candidates = all.where((v) => ids.contains(v.videoId)).toList();
    }
    final actual = candidates
        .where((v) => query.matches(v, tagContext: context))
        .map((v) => v.videoId)
        .toSet();
    expect(actual, expected, reason: '关键词 $keyword 在 revision $revision 不得漏项');
  }

  for (final keyword in [
    '😀a',
    '😀a nature',
    '😀ab',
    '中文',
    '中文测',
    'say"hello',
    r'back\slash',
    'plainalias',
    'identifier',
    'tagname',
    'displayword',
    'pathword',
    'nature',
    'absent'
  ]) {
    test('真实 FTS 与完整查询等价：$keyword', () => equivalent(keyword));
  }

  test('新增改名别名修改及删除后索引随 revision 刷新', () async {
    await equivalent('plainalias');
    video.title = 'renamed';
    await db.update('videos', {'title': video.title});
    await equivalent('renamed', revision: 2);
    await equivalent('nature', revision: 2);
    tag = const TagItem(
        id: 'manual:identifier',
        name: 'tagname',
        groupId: 'manual',
        source: TagSource.manual,
        aliases: ['new"alias']);
    await db.update('tags', {'aliases_json': jsonEncode(tag.aliases)});
    await equivalent('new"alias', revision: 3);
    await equivalent('plainalias', revision: 3);
    await db.delete('video_tags');
    await db.delete('videos');
    await equivalent('renamed', revision: 4, present: false);
    await db.insert('videos', {
      'video_id': video.videoId,
      'title': video.title,
      'path': video.path,
      'folder': video.folder
    });
    await equivalent('renamed', revision: 5);
  });

  test('索引重建失败回滚派生数据并允许修复后重试', () async {
    expect(await index.ensureFresh(db, revision: 1), isTrue);
    await db.update('tags', {'aliases_json': 'invalid json'});
    expect(await index.ensureFresh(db, revision: 2), isFalse);
    // 失败不能提交前面的清空动作，也不能把失败 revision 记为已完成。
    expect(await db.query(LibrarySearchIndex.tableName), hasLength(1));
    expect(await db.query('videos'), hasLength(1));
    await db.update('tags', {'aliases_json': jsonEncode(tag.aliases)});
    await equivalent('say"hello', revision: 2);
  });

  test('同 revision 的并发查询只重建一次且新 revision 独立刷新', () async {
    final counted = _CountingSearchIndex();
    expect(
        await Future.wait(
            List.generate(8, (_) => counted.ensureFresh(db, revision: 1))),
        everyElement(isTrue));
    expect(counted.rebuildCount, 1);
    await db.update('videos', {'title': 'changed'});
    expect(
        await Future.wait(
            List.generate(8, (_) => counted.ensureFresh(db, revision: 2))),
        everyElement(isTrue));
    expect(counted.rebuildCount, 2);
    final rows = await db.rawQuery(
        "SELECT video_id FROM library_search_fts WHERE library_search_fts MATCH 'changed'");
    expect(rows.single['video_id'], video.videoId);
  });

  test('不同 revision 等待旧事务结束且失败的合并请求可以重试', () async {
    final counted = _CountingSearchIndex();
    expect(
        await Future.wait([
          counted.ensureFresh(db, revision: 1),
          counted.ensureFresh(db, revision: 2),
          counted.ensureFresh(db, revision: 2),
        ]),
        everyElement(isTrue));
    expect(counted.rebuildCount, 2);
    await db.update('tags', {'aliases_json': 'invalid'});
    expect(
        await Future.wait(
            List.generate(8, (_) => counted.ensureFresh(db, revision: 3))),
        everyElement(isFalse));
    expect(counted.rebuildCount, 3);
    await db.update('tags', {'aliases_json': jsonEncode(tag.aliases)});
    expect(await counted.ensureFresh(db, revision: 3), isTrue);
    expect(counted.rebuildCount, 4);
  });
}
