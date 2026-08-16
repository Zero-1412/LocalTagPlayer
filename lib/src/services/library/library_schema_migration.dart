import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/tag_rules.dart';
import '../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/** Phase 2 之后 videos 表的稳定身份主表定义。 */
String stableVideosTableSql(String tableName) => '''
  CREATE TABLE IF NOT EXISTS $tableName (
    video_id TEXT PRIMARY KEY NOT NULL,
    path TEXT NOT NULL UNIQUE,
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
    last_played_at TEXT,
    is_missing INTEGER NOT NULL DEFAULT 0,
    is_detached INTEGER NOT NULL DEFAULT 0,
    playback_position_ms INTEGER NOT NULL DEFAULT 0,
    playback_duration_ms INTEGER NOT NULL DEFAULT 0,
    playback_completed INTEGER NOT NULL DEFAULT 0,
    playback_position_updated_at TEXT
  )
''';

/** Phase 2 之后 video_tags 以 stable videoId 作为关系身份。 */
String stableVideoTagsTableSql(String tableName) => '''
  CREATE TABLE IF NOT EXISTS $tableName (
    video_id TEXT NOT NULL,
    video_path TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    source TEXT NOT NULL,
    locked INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (video_id, tag_id, source)
  )
''';

/** 创建新库使用的 stable identity 两张核心表。 */
Future<void> createStableIdentityTables(Database db) async {
  await db.execute(stableVideosTableSql('videos'));
  await db.execute(stableVideoTagsTableSql('video_tags'));
}

/**
 * 将 path-keyed 旧库重建为 videoId 主身份 schema。
 *
 * SQLite 不能直接把既有 PRIMARY KEY 改列，因此采用同一事务内“读取 → 新表写入 →
 * 原子换表”。旧 path、标签、收藏、播放状态和未知扩展列以可证明的列映射保留；
 * 无法解析的标签关系直接中止事务，避免静默丢失用户数据。重复关系按稳定身份去重，
 * 保留 locked、最早创建时间和最新更新时间。
 */
Future<void> migrateToStableIdentitySchema(Database db) async {
  if (!await _tableExists(db, 'videos')) {
    return;
  }
  final videoInfo = await db.rawQuery('PRAGMA table_info(videos)');
  final tagInfo = await db.rawQuery('PRAGMA table_info(video_tags)');
  if (_isStableVideosSchema(videoInfo) && _isStableTagsSchema(tagInfo)) {
    return;
  }

  await db.transaction((transaction) async {
    final oldVideos = await transaction.query(
      'videos',
      orderBy: 'added_at ASC, path ASC',
    );
    final oldTags = tagInfo.isNotEmpty
        ? await transaction.query('video_tags')
        : const <Map<String, Object?>>[];
    final idByPathKey = <String, String>{};
    final pathById = <String, String>{};
    final videoRows = <Map<String, Object?>>[];
    for (final oldRow in oldVideos) {
      final path = (oldRow['path'] as String? ?? '').trim();
      if (path.isEmpty) {
        throw StateError('Phase 2 migration found a video row without path');
      }
      final pathKey = TagRules.pathKey(path);
      if (idByPathKey.containsKey(pathKey)) {
        throw StateError('Phase 2 migration found duplicate video path');
      }
      var videoId = (oldRow['video_id'] as String? ?? '').trim();
      if (videoId.isEmpty || pathById.containsKey(videoId)) {
        videoId = VideoItem.newVideoId();
        while (pathById.containsKey(videoId)) {
          videoId = VideoItem.newVideoId();
        }
      }
      idByPathKey[pathKey] = videoId;
      pathById[videoId] = path;
      videoRows.add(_stableVideoRow(oldRow, videoId, path));
    }

    final tagRowsByIdentity =
        <(String, String, String), Map<String, Object?>>{};
    for (final oldRow in oldTags) {
      final tagId = (oldRow['tag_id'] as String? ?? '').trim();
      final source = (oldRow['source'] as String? ?? '').trim();
      if (tagId.isEmpty || source.isEmpty) {
        throw StateError('Phase 2 migration found an invalid video tag row');
      }
      final oldVideoId = (oldRow['video_id'] as String? ?? '').trim();
      final oldPath = (oldRow['video_path'] as String? ?? '').trim();
      final videoId = pathById.containsKey(oldVideoId)
          ? oldVideoId
          : idByPathKey[TagRules.pathKey(oldPath)];
      if (videoId == null) {
        throw StateError('Phase 2 migration found an orphan video tag row');
      }
      final key = (videoId, tagId, source);
      final existing = tagRowsByIdentity[key];
      final candidate = <String, Object?>{
        'video_id': videoId,
        'video_path': pathById[videoId],
        'tag_id': tagId,
        'source': source,
        'locked': (oldRow['locked'] as int? ?? 0) == 1 ? 1 : 0,
        'created_at': oldRow['created_at'] as String? ?? '',
        'updated_at': oldRow['updated_at'] as String? ?? '',
      };
      if (existing == null) {
        tagRowsByIdentity[key] = candidate;
      } else {
        existing['locked'] = ((existing['locked'] as int? ?? 0) == 1 ||
                (candidate['locked'] as int? ?? 0) == 1)
            ? 1
            : 0;
        existing['created_at'] = _earliestTimestamp(
          existing['created_at'] as String,
          candidate['created_at'] as String,
        );
        existing['updated_at'] = _latestTimestamp(
          existing['updated_at'] as String,
          candidate['updated_at'] as String,
        );
      }
    }

    await transaction.execute(stableVideosTableSql('videos__phase2'));
    await transaction.execute(stableVideoTagsTableSql('video_tags__phase2'));
    final batch = transaction.batch();
    for (final row in videoRows) {
      batch.insert('videos__phase2', row);
    }
    for (final row in tagRowsByIdentity.values) {
      batch.insert('video_tags__phase2', row);
    }
    await batch.commit(noResult: true);

    if (tagInfo.isNotEmpty) {
      await transaction.execute('DROP TABLE video_tags');
    }
    await transaction
        .execute('ALTER TABLE video_tags__phase2 RENAME TO video_tags');
    await transaction.execute('DROP TABLE videos');
    await transaction.execute('ALTER TABLE videos__phase2 RENAME TO videos');
  });
}

bool _isStableVideosSchema(List<Map<String, Object?>> rows) {
  final byName = {
    for (final row in rows) row['name'] as String: row,
  };
  return (byName['video_id']?['pk'] as int? ?? 0) == 1 &&
      (byName['video_id']?['notnull'] as int? ?? 0) == 1 &&
      (byName['path']?['pk'] as int? ?? 0) == 0 &&
      (byName['path']?['notnull'] as int? ?? 0) == 1;
}

bool _isStableTagsSchema(List<Map<String, Object?>> rows) {
  final byName = {
    for (final row in rows) row['name'] as String: row,
  };
  return (byName['video_id']?['pk'] as int? ?? 0) == 1 &&
      (byName['video_id']?['notnull'] as int? ?? 0) == 1 &&
      (byName['video_path']?['notnull'] as int? ?? 0) == 1;
}

Map<String, Object?> _stableVideoRow(
  Map<String, Object?> oldRow,
  String videoId,
  String path,
) {
  String text(String key, String fallback) =>
      (oldRow[key] as String? ?? fallback).isEmpty
          ? fallback
          : oldRow[key] as String;
  return <String, Object?>{
    'video_id': videoId,
    'path': path,
    'title': text('title', path),
    'folder': text('folder', ''),
    'root_path': oldRow['root_path'] as String?,
    'relative_path': oldRow['relative_path'] as String?,
    'file_size': oldRow['file_size'] as int?,
    'modified_ms': oldRow['modified_ms'] as int?,
    'tags_json': text('tags_json', '[]'),
    'child_tags_json': text('child_tags_json', '{}'),
    'is_favorite': oldRow['is_favorite'] as int? ?? 0,
    'media_details_json': oldRow['media_details_json'] as String?,
    'media_fingerprint': oldRow['media_fingerprint'] as String?,
    'thumbnail_error': oldRow['thumbnail_error'] as String?,
    'media_details_error': oldRow['media_details_error'] as String?,
    'added_at': text('added_at', DateTime.now().toIso8601String()),
    'last_played_at': oldRow['last_played_at'] as String?,
    'is_missing': oldRow['is_missing'] as int? ?? 0,
    'is_detached': oldRow['is_detached'] as int? ?? 0,
    'playback_position_ms': oldRow['playback_position_ms'] as int? ?? 0,
    'playback_duration_ms': oldRow['playback_duration_ms'] as int? ?? 0,
    'playback_completed': oldRow['playback_completed'] as int? ?? 0,
    'playback_position_updated_at':
        oldRow['playback_position_updated_at'] as String?,
  };
}

String _earliestTimestamp(String first, String second) {
  if (first.isEmpty) return second;
  if (second.isEmpty) return first;
  return first.compareTo(second) <= 0 ? first : second;
}

String _latestTimestamp(String first, String second) {
  if (first.isEmpty) return second;
  if (second.isEmpty) return first;
  return first.compareTo(second) >= 0 ? first : second;
}

Future<bool> _tableExists(Database db, String tableName) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    <Object?>[tableName],
  );
  return rows.isNotEmpty;
}
