import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/media_details.dart';
import '../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库视频表的持久化边界。
 *
 * `LibraryStore` 负责扫描、标签语义和内存状态协调；本类只负责 `videos`
 * 表的行映射与写入/删除，避免 SQLite 字段细节继续散落在业务流程中。
 */
class LibraryVideoPersistence {
  /**
   * 创建一个围绕当前 SQLite 连接的视频持久化 helper。
   *
   * [_db] 必须由 `LibraryStore` 打开和关闭，本类不拥有连接生命周期。
   */
  const LibraryVideoPersistence(this._db);

  /** 当前媒体库数据库连接。 */
  final Database _db;

  /**
   * 将 `videos` 表行恢复为内存中的视频模型。
   *
   * JSON 字段只承载兼容旧数据所需的标签快照；真实标签来源仍以
   * `video_tags` 关联表为准。
   */
  static VideoItem videoFromRow(Map<String, Object?> row) {
    final mediaDetailsJson = row['media_details_json'] as String?;
    return VideoItem(
      videoId: row['video_id'] as String?,
      path: row['path'] as String,
      title: row['title'] as String,
      folder: row['folder'] as String,
      tags: ((jsonDecode(row['tags_json'] as String) as List?) ?? const [])
          .cast<String>()
          .toSet(),
      childTags:
          ((jsonDecode(row['child_tags_json'] as String) as Map?) ?? const {})
              .map(
        (key, value) => MapEntry(key as String,
            ((value as List?) ?? const []).cast<String>().toSet()),
      ),
      rootPath: row['root_path'] as String?,
      relativePath: row['relative_path'] as String?,
      fileSize: row['file_size'] as int?,
      modifiedMs: row['modified_ms'] as int?,
      isFavorite: (row['is_favorite'] as int? ?? 0) == 1,
      mediaDetails: mediaDetailsJson == null || mediaDetailsJson.isEmpty
          ? null
          : MediaDetails.fromJson(
              (jsonDecode(mediaDetailsJson) as Map).cast<String, Object?>()),
      mediaFingerprint: row['media_fingerprint'] as String?,
      thumbnailError: row['thumbnail_error'] as String?,
      mediaDetailsError: row['media_details_error'] as String?,
      addedAt:
          DateTime.tryParse(row['added_at'] as String? ?? '') ?? DateTime.now(),
      lastPlayedAt: DateTime.tryParse(row['last_played_at'] as String? ?? ''),
      isMissing: (row['is_missing'] as int? ?? 0) == 1,
      playbackPosition:
          Duration(milliseconds: row['playback_position_ms'] as int? ?? 0),
      playbackDuration:
          Duration(milliseconds: row['playback_duration_ms'] as int? ?? 0),
      playbackCompleted: (row['playback_completed'] as int? ?? 0) == 1,
      playbackPositionUpdatedAt: DateTime.tryParse(
          row['playback_position_updated_at'] as String? ?? ''),
    );
  }

  /**
   * 将视频模型转成 `videos` 表行。
   *
   * 标签快照保持排序后写入，确保同一业务状态不会产生不必要的持久化差异。
   */
  static Map<String, Object?> videoToRow(VideoItem item) => {
        'video_id': item.videoId,
        'path': item.path,
        'title': item.title,
        'folder': item.folder,
        'root_path': item.rootPath,
        'relative_path': item.relativePath,
        'file_size': item.fileSize,
        'modified_ms': item.modifiedMs,
        'tags_json': jsonEncode(item.tags.toList()..sort()),
        'child_tags_json': jsonEncode(item.childTags
            .map((key, value) => MapEntry(key, value.toList()..sort()))),
        'is_favorite': item.isFavorite ? 1 : 0,
        'media_details_json': item.mediaDetails == null
            ? null
            : jsonEncode(item.mediaDetails!.toJson()),
        'media_fingerprint': item.mediaFingerprint,
        'thumbnail_error': item.thumbnailError,
        'media_details_error': item.mediaDetailsError,
        'added_at': item.addedAt.toIso8601String(),
        'last_played_at': item.lastPlayedAt?.toIso8601String(),
        'is_missing': item.isMissing ? 1 : 0,
        // 正常 upsert 都代表视频处于 active root；解除管理只能走显式 detached 方法。
        'is_detached': 0,
        'playback_position_ms': item.playbackPosition.inMilliseconds,
        'playback_duration_ms': item.playbackDuration.inMilliseconds,
        'playback_completed': item.playbackCompleted ? 1 : 0,
        'playback_position_updated_at':
            item.playbackPositionUpdatedAt?.toIso8601String(),
      };

  /**
   * 在外层批处理中写入单个视频。
   *
   * 调用方继续控制同一批次内的标签索引同步，避免视频和标签写入顺序被隐藏。
   */
  void insertInBatch(Batch batch, VideoItem item) {
    batch.insert(
      'videos',
      videoToRow(item),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /**
   * 直接写入单个视频行。
   *
   * 该方法不更新标签索引；调用方如需标签来源同步，应继续使用
   * `LibraryStore` 的标签维护流程。
   */
  Future<void> upsert(VideoItem item) async {
    await _db.insert(
      'videos',
      videoToRow(item),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /**
   * 在一个 SQLite batch 中写入多条视频字段更新。
   *
   * 媒体探测会连续完成大量条目；批量提交可显著减少平台通道和事务往返，同时继续
   * 由 Dart Repository 独占数据库写入。
   */
  Future<void> upsertAll(Iterable<VideoItem> items) async {
    final batch = _db.batch();
    var hasItems = false;
    for (final item in items) {
      hasItems = true;
      insertInBatch(batch, item);
    }
    if (hasItems) {
      await batch.commit(noResult: true);
    }
  }

  /**
   * 删除视频行。
   *
   * 关联标签行由 `LibraryTagPersistence.deleteVideoLinks` 先清理，避免旧数据库未启用
   * 外键时留下悬空引用。
   */
  Future<void> delete(String path) async {
    await _db.delete(
      'videos',
      where: Platform.isWindows ? 'path = ? COLLATE NOCASE' : 'path = ?',
      whereArgs: [path],
    );
  }

  /**
   * 在外层批处理中删除视频行。
   *
   * 扫描清理缺失文件时与标签关联删除同批提交，保持视频表和关联表一致。
   */
  void deleteInBatch(Batch batch, String path) {
    batch.delete(
      'videos',
      where: Platform.isWindows ? 'path = ? COLLATE NOCASE' : 'path = ?',
      whereArgs: [path],
    );
  }

  /**
   * 在 root 生命周期事务中切换解除管理状态。
   *
   * 这里只修改管理可见性，不删除视频行或标签关系，因此收藏、播放记录和稳定 videoId
   * 可以在相同 root 重新加入或 fingerprint relink 后继续使用。
   */
  void markDetachedInBatch(Batch batch, String videoId, bool detached) {
    batch.update(
      'videos',
      <String, Object?>{'is_detached': detached ? 1 : 0},
      where: 'video_id = ?',
      whereArgs: <Object?>[videoId],
    );
  }

  /** 在同一批次中删除旧 path 行并用相同 videoId 写入新位置。 */
  void relinkInBatch(Batch batch, String oldPath, VideoItem item) {
    deleteInBatch(batch, oldPath);
    insertInBatch(batch, item);
  }
}
