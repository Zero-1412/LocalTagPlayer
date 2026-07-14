import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import 'library_metadata_persistence.dart';
import 'library_scan_backend.dart';
import 'library_tag_persistence.dart';
import 'library_video_persistence.dart';

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
  int get scanGeneration;
  List<String> get roots;
  List<String> get favoriteTags;
  Map<String, VideoItem> get videos;
  Map<String, TagItem> get tagsById;
  Map<String, Set<String>> get videoTagIdsByPathKey;
  LibraryMetadataPersistence get metadataPersistence;
  LibraryVideoPersistence get videoPersistence;
  LibraryTagPersistence get tagPersistence;
}
