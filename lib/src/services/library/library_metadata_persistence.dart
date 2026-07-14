part of '../../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库 metadata 表的持久化边界。
 *
 * metadata 目前只保存根目录列表和常用标签列表；单独拆出后，扫描、目录管理和
 * 用户偏好保存都不需要直接拼写 SQLite 行结构。
 */
class LibraryMetadataPersistence {
  /**
   * 创建 metadata 持久化 helper。
   *
   * [_db] 由 `LibraryStore` 统一管理生命周期，本类只使用连接读写 metadata 表。
   */
  const LibraryMetadataPersistence(this._db);

  /** 当前媒体库数据库连接。 */
  final Database _db;

  /**
   * 从 metadata 表加载根目录和常用标签。
   *
   * 加载时沿用 `LibraryStore` 的去重规则，避免旧数据中的重复目录或大小写重复标签继续扩散。
   */
  Future<LibraryMetadataSnapshot> load() async {
    final metadata = <String, String>{};
    for (final row in await _db.query('metadata')) {
      metadata[row['key'] as String] = row['value'] as String;
    }
    return LibraryMetadataSnapshot(
      roots: LibraryStore._dedupeRoots(
          ((jsonDecode(metadata['roots'] ?? '[]') as List?) ?? const [])
              .cast<String>()),
      favoriteTags: LibraryStore._dedupeTags(
          ((jsonDecode(metadata['favoriteTags'] ?? '[]') as List?) ?? const [])
              .cast<String>()),
    );
  }

  /**
   * 在批处理中保存 metadata。
   *
   * 扫描流程需要和视频增量写入共用一个 batch，因此这里提供批处理版本。
   */
  void saveInBatch(
    Batch batch, {
    required Iterable<String> roots,
    required Iterable<String> favoriteTags,
  }) {
    batch.insert(
      'metadata',
      {'key': 'roots', 'value': jsonEncode(LibraryStore._dedupeRoots(roots))},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    batch.insert(
      'metadata',
      {
        'key': 'favoriteTags',
        'value': jsonEncode(LibraryStore._dedupeTags(favoriteTags)),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /**
   * 直接保存 metadata。
   *
   * 目录管理和设置类操作只更新 metadata，不需要触发视频表写入。
   */
  Future<void> save({
    required Iterable<String> roots,
    required Iterable<String> favoriteTags,
  }) async {
    final batch = _db.batch();
    saveInBatch(batch, roots: roots, favoriteTags: favoriteTags);
    await batch.commit(noResult: true);
  }
}

/**
 * metadata 表加载后的内存快照。
 */
class LibraryMetadataSnapshot {
  const LibraryMetadataSnapshot({
    required this.roots,
    required this.favoriteTags,
  });

  /** 已规范化并去重的媒体库根目录。 */
  final List<String> roots;

  /** 已规范化并去重的常用标签。 */
  final List<String> favoriteTags;
}
