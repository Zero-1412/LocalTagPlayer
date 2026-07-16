import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import 'library_metadata_persistence.dart';
import 'library_scan_backend.dart';
import 'library_tag_persistence.dart';
import 'library_video_persistence.dart';
import 'library_data_backup_service.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * Store 内部协作服务使用的最小可写端口。
 *
 * 该契约只在 repository 实现层使用，不向页面暴露数据库连接；目的是让扫描与标签协调器
 * 成为独立 library，同时仍由唯一 [LibraryStoreAccess] 实现持有 SQLite 写权限。
 */
abstract interface class LibraryStoreAccess {
  Database get database;
  LibraryScanBackend get scanBackend;

  /** 扫描提交前查询恢复快照、提交后排入增量备份的独立服务。 */
  LibraryDataBackupService get dataBackupService;
  int get scanGeneration;
  List<String> get roots;
  List<String> get favoriteTags;
  /** 当前由 active root 管理、可以进入查询与播放队列的视频。 */
  Map<String, VideoItem> get videos;
  /** 已解除 root 管理但仍保留稳定身份和用户数据的视频。 */
  Map<String, VideoItem> get detachedVideos;
  /** 标签分组定义；备份恢复自定义标签时需要在同一事务中补齐。 */
  List<TagGroup> get tagGroups;
  Map<String, TagItem> get tagsById;
  Map<String, Set<String>> get videoTagIdsByPathKey;
  LibraryMetadataPersistence get metadataPersistence;
  LibraryVideoPersistence get videoPersistence;
  LibraryTagPersistence get tagPersistence;
}
