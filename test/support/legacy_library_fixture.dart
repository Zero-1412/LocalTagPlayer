import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * Phase 2 migration 使用的最小旧库 fixture。
 *
 * 该 fixture 只描述 path-keyed schema，不创建真实文件，也不写入用户路径或媒体内容。
 * 迁移测试可以在临时 SQLite 文件上调用 [createSchema] 与 [seed]，验证旧库升级后的
 * stable videoId、标签关系和用户数据保留。
 */
class LegacyLibraryFixture {
  const LegacyLibraryFixture._();

  static const String samplePath = 'C:/fixture/Series/legacy.mp4';
  static const String sampleTagId = 'manual:legacy';
  static const String sampleAddedAt = '2026-07-01T00:00:00.000Z';

  /** 迁移前只包含 path 身份的最小 videos/video_tags schema。 */
  static Future<void> createSchema(Database database) async {
    await database.execute('''
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
    await database.execute('''
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
  }

  /** 写入一条包含收藏和 manual 标签的确定性旧库记录。 */
  static Future<void> seed(Database database) async {
    await database.insert('videos', <String, Object?>{
      'path': samplePath,
      'title': 'legacy',
      'folder': 'C:/fixture/Series',
      'root_path': 'C:/fixture',
      'relative_path': 'Series/legacy.mp4',
      'file_size': 123,
      'modified_ms': 1782864000000,
      'tags_json': '[]',
      'child_tags_json': '{}',
      'is_favorite': 1,
      'media_fingerprint': '5|123',
      'added_at': sampleAddedAt,
      'last_played_at': null,
    });
    await database.insert('video_tags', <String, Object?>{
      'video_path': samplePath,
      'tag_id': sampleTagId,
      'source': 'manual',
      'locked': 0,
      'created_at': sampleAddedAt,
      'updated_at': sampleAddedAt,
    });
  }
}
