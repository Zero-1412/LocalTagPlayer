import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/platform_models.dart';
import 'library_metadata_persistence.dart';
import 'library_query_compiler.dart';
import 'library_tag_persistence.dart';
import 'library_video_persistence.dart';
import 'video_identity_index.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * LibraryRepository 的共享状态与事务上下文。
 *
 * 该对象不拥有连接生命周期，也不实现业务命令；它只把同一个 SQLite connection、
 * stable/path 双索引、标签关系索引和三个持久化 helper 作为一个不可替代的组合单元，
 * 防止 Phase 3 拆分时意外创建第二个数据库或第二套内存身份。
 */
class LibraryRepositoryContext {
  LibraryRepositoryContext({
    required this.database,
    required this.roots,
    required this.videos,
    required this.detachedVideos,
    required this.favoriteTags,
    required this.tagGroups,
    required this.tagsById,
    required this.videoTagIdsByPathKey,
    required this.videoTagIdsByVideoId,
    bool fts5Available = false,
  })  : videoPersistence = LibraryVideoPersistence(database),
        metadataPersistence = LibraryMetadataPersistence(database),
        tagPersistence = LibraryTagPersistence(
          database,
          tagsById,
          videoTagIdsByPathKey,
          videoTagIdsByVideoId,
        ),
        queryProfile = LibraryQueryProfile(
          videoCount: videos.length,
          fts5Available: fts5Available,
        );

  /** 当前媒体库唯一 SQLite connection。 */
  final Database database;
  final List<String> roots;
  /** active 视频的 stable 主索引与 path 兼容视图。 */
  final VideoIdentityIndex videos;
  /** detached 视频的 stable 主索引与 path 兼容视图。 */
  final VideoIdentityIndex detachedVideos;
  final List<String> favoriteTags;
  final List<TagGroup> tagGroups;
  final Map<String, TagItem> tagsById;
  /** pathKey 辅助标签视图。 */
  final Map<String, Set<String>> videoTagIdsByPathKey;
  /** stable videoId 主标签关系索引。 */
  final Map<String, Set<String>> videoTagIdsByVideoId;

  /** 当前库规模对应的查询执行 profile。 */
  final LibraryQueryProfile queryProfile;

  /** 视频行写入 owner；连接仍由 [database] 的组合根管理。 */
  final LibraryVideoPersistence videoPersistence;
  /** metadata 写入 owner。 */
  final LibraryMetadataPersistence metadataPersistence;
  /** 标签关系写入 owner。 */
  final LibraryTagPersistence tagPersistence;

  /**
   * 为需要跨 videos/tags/metadata 的命令提供统一事务入口。
   *
   * 具体业务仍由命令 service 决定；所有事务都必须使用这个连接，不允许 helper 自己打开库。
   */
  Future<T> transaction<T>(Future<T> Function(Transaction transaction) action) {
    return database.transaction(action);
  }
}
