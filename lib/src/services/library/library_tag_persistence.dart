part of '../../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库标签表与视频标签关联表的持久化边界。
 *
 * 本类只处理 `tags`、`tag_aliases`、`video_tags` 的读写副作用；标签来源语义、
 * folder/manual 分离规则和 UI 查询仍由 `LibraryStore` 与 `TagQueryService` 负责。
 */
class LibraryTagPersistence {
  /**
   * 创建标签持久化 helper。
   *
   * [tagsById] 与 [videoTagIdsByPathKey] 是 `LibraryStore` 的内存索引，本类在写入
   * SQLite 时同步维护它们，保证后续查询无需重新加载数据库。
   */
  const LibraryTagPersistence(
    this._db,
    this._tagsById,
    this._videoTagIdsByPathKey,
  );

  /** 当前媒体库数据库连接。 */
  final Database _db;

  /** 以 tagId 为键的内存标签索引。 */
  final Map<String, TagItem> _tagsById;

  /** 以规范化视频路径为键的视频到标签索引。 */
  final Map<String, Set<String>> _videoTagIdsByPathKey;

  /**
   * 持久化单个标签及其别名。
   *
   * 别名表先清后写，避免用户删除别名后旧别名继续参与关键词匹配。
   */
  Future<void> saveTag(TagItem tag) async {
    _tagsById[tag.id] = tag;
    final batch = _db.batch();
    upsertTagInBatch(batch, tag, replace: true);
    batch.delete('tag_aliases', where: 'tag_id = ?', whereArgs: [tag.id]);
    for (final alias in LibraryStore._dedupeTags(tag.aliases)) {
      batch.insert(
        'tag_aliases',
        {'tag_id': tag.id, 'alias': alias},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  /**
   * 在批处理中写入标签主表。
   *
   * [replace] 为 `false` 时保留已有标签元数据，适合扫描派生的 folder 标签；为
   * `true` 时用于用户显式编辑后的完整覆盖。
   */
  void upsertTagInBatch(Batch batch, TagItem tag, {required bool replace}) {
    batch.insert(
      'tags',
      tagToRow(tag),
      conflictAlgorithm:
          replace ? ConflictAlgorithm.replace : ConflictAlgorithm.ignore,
    );
  }

  /**
   * 将标签模型转成 `tags` 表行。
   *
   * 来源字段必须写入真实 `TagSource`，不能只靠名称推断，以免 folder/manual 同名标签混淆。
   */
  static Map<String, Object?> tagToRow(TagItem tag) => {
        'id': tag.id,
        'name': tag.name,
        'display_name': tag.displayName,
        'group_id': tag.groupId,
        'parent_id': tag.parentId,
        'color': tag.color,
        'source': tag.source.name,
        'aliases_json': jsonEncode(tag.aliases),
        'usage_count': tag.usageCount,
        'is_favorite': tag.isFavorite ? 1 : 0,
        'is_hidden': tag.isHidden ? 1 : 0,
        'sort_order': tag.sortOrder,
      };

  /**
   * 删除指定来源的标签关联。
   *
   * 扫描重建 folder 标签时只移除 folder 来源，手动标签必须保留。
   */
  void removeVideoTagSourceInBatch(
    Batch batch,
    VideoItem video,
    TagSource source,
  ) {
    batch.delete(
      'video_tags',
      where: 'video_id = ? AND source = ?',
      whereArgs: [video.videoId, source.name],
    );
    final key = TagRules.pathKey(video.path);
    final retained = _videoTagIdsByPathKey[key];
    if (retained != null) {
      retained.removeWhere((tagId) => _tagsById[tagId]?.source == source);
      if (retained.isEmpty) {
        _videoTagIdsByPathKey.remove(key);
      }
    }
  }

  /**
   * 删除手动标签的指定作用域关联。
   *
   * [parentTag] 为空时只处理一级手动标签；非空时只处理该一级标签下的手动二级标签，
   * 从而避免编辑一个分组时误删另一个分组的用户数据。
   */
  void removeManualTagScopeInBatch(
    Batch batch,
    VideoItem video, {
    String? parentTag,
  }) {
    final key = TagRules.pathKey(video.path);
    final retained = _videoTagIdsByPathKey[key];
    if (retained == null || retained.isEmpty) {
      return;
    }
    final removed = <String>[];
    for (final tagId in retained) {
      final tag = _tagsById[tagId];
      if (tag == null || tag.source != TagSource.manual) {
        continue;
      }
      final sameScope =
          parentTag == null ? tag.parentId == null : tag.parentId == parentTag;
      if (!sameScope) {
        continue;
      }
      removed.add(tagId);
      batch.delete(
        'video_tags',
        where: 'video_id = ? AND tag_id = ? AND source = ?',
        whereArgs: [video.videoId, tagId, TagSource.manual.name],
      );
    }
    retained.removeAll(removed);
    if (retained.isEmpty) {
      _videoTagIdsByPathKey.remove(key);
    }
  }

  /**
   * 在批处理中建立视频与标签来源的关联。
   *
   * 关联表的主键包含 source，因此同名 tagId 在不同来源的写入需要显式指定来源。
   */
  void attachTagInBatch(
    Batch batch,
    VideoItem video,
    TagItem tag, {
    required TagSource source,
    bool locked = false,
  }) {
    upsertTagInBatch(batch, tag, replace: false);
    final now = DateTime.now().toIso8601String();
    batch.insert(
      'video_tags',
      {
        'video_path': video.path,
        'video_id': video.videoId,
        'tag_id': tag.id,
        'source': source.name,
        'locked': locked ? 1 : 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    (_videoTagIdsByPathKey[TagRules.pathKey(video.path)] ??= <String>{})
        .add(tag.id);
  }

  /**
   * 删除视频的所有标签关联。
   *
   * 删除视频文件或记录前显式清理关联，保护未启用外键的旧环境。
   */
  Future<void> deleteVideoLinks(VideoItem video) async {
    _videoTagIdsByPathKey.remove(TagRules.pathKey(video.path));
    await _db.delete(
      'video_tags',
      where: 'video_id = ?',
      whereArgs: [video.videoId],
    );
  }

  /**
   * 在批处理中删除视频的所有标签关联。
   *
   * 扫描清理缺失视频时需要和视频表删除同批提交，避免中间状态留下悬空关联。
   */
  void deleteVideoLinksInBatch(
    Batch batch,
    VideoItem video, {
    bool updateMemoryIndex = true,
  }) {
    // 需要等待外层事务成功时，先只排入 SQLite 删除，避免提交失败后内存索引先丢失。
    if (updateMemoryIndex) {
      _videoTagIdsByPathKey.remove(TagRules.pathKey(video.path));
    }
    batch.delete(
      'video_tags',
      where: 'video_id = ?',
      whereArgs: [video.videoId],
    );
  }

  /** 文件移动后只更新兼容 path，标签关系仍以 videoId 保持不变。 */
  void relinkVideoPathInBatch(
    Batch batch,
    VideoItem video,
  ) {
    batch.update(
      'video_tags',
      {'video_path': video.path},
      where: 'video_id = ?',
      whereArgs: [video.videoId],
    );
  }

  /**
   * 统计标签被多少视频引用。
   *
   * 该方法属于持久化边界，因为它直接读取关联表，不复制过滤查询语义。
   */
  Future<int> countTagReferences(TagItem tag) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM video_tags WHERE tag_id = ?',
      [tag.id],
    );
    return rows.isEmpty ? 0 : rows.first['count'] as int? ?? 0;
  }
}
