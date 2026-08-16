import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/core/tag_rules.dart';
import 'package:local_tag_player/src/models/platform_models.dart';
import 'package:local_tag_player/src/models/video_item.dart';
import 'package:local_tag_player/src/services/library/library_schema_migration.dart';
import 'package:local_tag_player/src/services/library/video_identity_index.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/legacy_library_fixture.dart';

// ignore_for_file: slash_for_doc_comments

var _sqliteReady = false;

void _configureSqlite() {
  if (_sqliteReady) {
    return;
  }
  DynamicLibrary.open(
    File(
      'windows${Platform.pathSeparator}tools${Platform.pathSeparator}'
      'sqlite${Platform.pathSeparator}sqlite3.dll',
    ).absolute.path,
  );
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _sqliteReady = true;
}

void main() {
  setUpAll(_configureSqlite);

  test('video identity index keeps ID primary and path auxiliary views aligned',
      () {
    final first = VideoItem(
      videoId: 'stable-1',
      path: 'C:/media/first.mp4',
      title: 'first',
      folder: 'C:/media',
      tags: <String>{},
      addedAt: DateTime.utc(2026, 8, 1),
    );
    final index = VideoIdentityIndex(<VideoItem>[first]);

    expect(index.byId('stable-1'), same(first));
    expect(index[TagRules.pathKey(first.path)], same(first));

    first.path = 'C:/media/renamed.mp4';
    index.put(first);

    expect(index.byId('stable-1'), same(first));
    expect(index[TagRules.pathKey('C:/media/first.mp4')], isNull);
    expect(index[TagRules.pathKey(first.path)], same(first));

    final replacement = VideoItem(
      videoId: 'stable-1',
      path: 'C:/media/reloaded.mp4',
      title: 'reloaded',
      folder: 'C:/media',
      tags: <String>{},
      addedAt: DateTime.utc(2026, 8, 2),
    );
    index[TagRules.pathKey(replacement.path)] = replacement;
    expect(index.length, 1);
    expect(index.byId('stable-1'), same(replacement));
    expect(index[TagRules.pathKey(first.path)], isNull);
  });

  test('tag queries prefer stable videoId relations after path changes', () {
    final item = VideoItem(
      videoId: 'stable-tagged',
      path: 'C:/media/old.mp4',
      title: 'tagged',
      folder: 'C:/media',
      tags: <String>{},
      addedAt: DateTime.utc(2026, 8, 1),
    )..path = 'C:/media/new.mp4';
    const tag = TagItem(
      id: 'manual:keep',
      name: 'keep',
      source: TagSource.manual,
      groupId: 'manual',
    );
    final context = TagQueryContext(
      tagsById: <String, TagItem>{tag.id: tag},
      videoTagIdsByVideoId: <String, Set<String>>{
        item.videoId: <String>{tag.id},
      },
      videoTagIdsByPathKey: <String, Set<String>>{
        TagRules.pathKey('C:/media/old.mp4'): <String>{'stale:path-tag'},
      },
    );

    expect(context.videoHasTagId(item, tag.id), isTrue);
    expect(context.tagsFor(item), contains(tag));
  });

  test('legacy schema migrates to stable primary keys and is idempotent',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'ltp_phase2_migration_',
    );
    final database = await databaseFactoryFfi.openDatabase(
      '${directory.path}${Platform.pathSeparator}legacy.db',
    );
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    await LegacyLibraryFixture.createSchema(database);
    await LegacyLibraryFixture.seed(database);
    await migrateToStableIdentitySchema(database);

    final videos = await database.query('videos');
    final tags = await database.query('video_tags');
    expect(videos, hasLength(1));
    expect(tags, hasLength(1));
    final video = videos.single;
    expect(video['video_id'], startsWith('vid_'));
    expect(video['path'], LegacyLibraryFixture.samplePath);
    expect(video['is_favorite'], 1);
    expect(tags.single['video_id'], video['video_id']);
    expect(tags.single['video_path'], LegacyLibraryFixture.samplePath);

    final videoInfo = await database.rawQuery('PRAGMA table_info(videos)');
    final tagInfo = await database.rawQuery('PRAGMA table_info(video_tags)');
    final videoColumns = {
      for (final row in videoInfo) row['name'] as String: row,
    };
    final tagColumns = {
      for (final row in tagInfo) row['name'] as String: row,
    };
    expect(videoColumns['video_id']?['pk'], 1);
    expect(videoColumns['video_id']?['notnull'], 1);
    expect(videoColumns['path']?['pk'], 0);
    expect(videoColumns['path']?['notnull'], 1);
    expect(tagColumns['video_id']?['pk'], 1);
    expect(tagColumns['video_id']?['notnull'], 1);

    final before = await database.rawQuery(
      'SELECT video_id, path, is_favorite FROM videos',
    );
    await migrateToStableIdentitySchema(database);
    expect(
      await database.rawQuery(
        'SELECT video_id, path, is_favorite FROM videos',
      ),
      before,
    );
  });
}
