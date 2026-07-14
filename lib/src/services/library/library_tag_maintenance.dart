part of '../../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库标签维护策略。
 *
 * 本类维护 folder/manual 标签来源分离规则，并把具体 SQLite 写入委托给
 * `LibraryTagPersistence` 与 `LibraryVideoPersistence`，避免 `LibraryStore` 同时承载策略和持久化细节。
 */
class LibraryTagMaintenance {
  /**
   * 创建围绕当前 store 的标签维护策略对象。
   *
   * [_store] 提供内存索引和持久化 helper，本类不拥有数据库连接生命周期。
   */
  const LibraryTagMaintenance(this._store);

  /** 当前媒体库 store。 */
  final LibraryStore _store;

  /**
   * 替换单个视频的手动标签作用域。
   *
   * [parentTag] 为空时处理一级 manual 标签；非空时只处理该一级标签下的二级 manual 标签。
   */
  Future<void> replaceManualTags(
    VideoItem item, {
    String? parentTag,
  }) async {
    final batch = _store._db.batch();
    syncManualTagsInBatch(batch, item, parentTag: parentTag);
    _store._videoPersistence.insertInBatch(batch, item);
    await batch.commit(noResult: true);
  }

  /**
   * 批量添加 manual 标签。
   *
   * 只允许 manual 来源标签，避免把 folder 派生标签当作用户维护数据写入。
   */
  Future<int> batchAddManualTag(
    TagItem tag,
    Iterable<VideoItem> items,
  ) async {
    if (tag.source != TagSource.manual) {
      throw StateError('批量添加只支持 manual 标签');
    }
    final videosToUpdate = items.toList();
    if (videosToUpdate.isEmpty) {
      return 0;
    }
    final batch = _store._db.batch();
    for (final item in videosToUpdate) {
      _addManualTagToItem(item, tag);
      _store._videoPersistence.insertInBatch(batch, item);
      _store._tagPersistence.attachTagInBatch(
        batch,
        item,
        tag,
        source: TagSource.manual,
      );
    }
    await batch.commit(noResult: true);
    return videosToUpdate.length;
  }

  /**
   * 批量移除 manual 标签。
   *
   * 只删除 `source=manual` 的关联；如果同名 folder 标签仍由路径派生，兼容字段会保留。
   */
  Future<int> batchRemoveManualTag(
    TagItem tag,
    Iterable<VideoItem> items,
  ) async {
    if (tag.source != TagSource.manual) {
      throw StateError('批量移除只支持 manual 标签');
    }
    final videosToUpdate = items.toList();
    if (videosToUpdate.isEmpty) {
      return 0;
    }
    final batch = _store._db.batch();
    var changed = 0;
    for (final item in videosToUpdate) {
      final hadManualLink = _store
              .videoTagIdsByPathKey[TagRules.pathKey(item.path)]
              ?.contains(tag.id) ??
          false;
      final changedCompat = _removeManualTagFromItem(item, tag);
      batch.delete(
        'video_tags',
        where: 'video_id = ? AND tag_id = ? AND source = ?',
        whereArgs: [item.videoId, tag.id, TagSource.manual.name],
      );
      _store.videoTagIdsByPathKey[TagRules.pathKey(item.path)]?.remove(tag.id);
      if (_store.videoTagIdsByPathKey[TagRules.pathKey(item.path)]?.isEmpty ??
          false) {
        _store.videoTagIdsByPathKey.remove(TagRules.pathKey(item.path));
      }
      if (hadManualLink || changedCompat) {
        changed++;
      }
      _store._videoPersistence.insertInBatch(batch, item);
    }
    await batch.commit(noResult: true);
    return changed;
  }

  /**
   * 在批处理中刷新 folder 来源标签索引。
   *
   * 只移除并重建 folder 来源关联，不会触碰用户维护的 manual 标签。
   */
  void syncFolderTagsInBatch(Batch batch, VideoItem item) {
    _store._tagPersistence
        .removeVideoTagSourceInBatch(batch, item, TagSource.folder);
    for (final tag in item.tags) {
      _store._tagPersistence.attachTagInBatch(
        batch,
        item,
        _tagFor(
          name: tag,
          groupId: 'folder.primary',
          source: TagSource.folder,
        ),
        source: TagSource.folder,
      );
    }
    for (final entry in item.childTags.entries) {
      for (final child in entry.value) {
        _store._tagPersistence.attachTagInBatch(
          batch,
          item,
          _tagFor(
            name: child,
            groupId: 'folder.child',
            source: TagSource.folder,
            parentId: entry.key,
          ),
          source: TagSource.folder,
        );
      }
    }
  }

  /**
   * 根据当前 root 与路径计算该视频应具备的 folder 来源 tagId。
   *
   * 该集合专供启动覆盖检查使用；root 直属视频返回空集合，表示“无需 folder 关系”，
   * 而不是“索引损坏”。tagId 仍包含 group 与 parent，避免同名层级标签混淆。
   */
  Set<String> expectedFolderTagIds(VideoItem item) {
    final rootPath = item.rootPath;
    if (rootPath == null || rootPath.isEmpty) {
      return const <String>{};
    }
    final ids = <String>{};
    for (final tag in TagRules.parentTagsFor(rootPath, item.path)) {
      ids.add(TagRules.tagIdFor(
        name: tag,
        groupId: 'folder.primary',
      ));
    }
    for (final entry in TagRules.childTagsFor(rootPath, item.path).entries) {
      for (final child in entry.value) {
        ids.add(TagRules.tagIdFor(
          name: child,
          groupId: 'folder.child',
          parentId: entry.key,
        ));
      }
    }
    return ids;
  }

  /**
   * 在批处理中刷新 manual 来源标签索引。
   *
   * folder 派生标签会被排除，避免同名 folder 标签被误写成 manual 来源。
   */
  void syncManualTagsInBatch(
    Batch batch,
    VideoItem item, {
    String? parentTag,
  }) {
    _store._tagPersistence.removeManualTagScopeInBatch(
      batch,
      item,
      parentTag: parentTag,
    );
    if (parentTag == null) {
      final folderTags = _folderTagsForItem(item);
      for (final tag in item.tags) {
        if (folderTags.any((folderTag) => TagRules.sameTag(folderTag, tag))) {
          continue;
        }
        _store._tagPersistence.attachTagInBatch(
          batch,
          item,
          _tagFor(
            name: tag,
            groupId: 'manual',
            source: TagSource.manual,
          ),
          source: TagSource.manual,
        );
      }
      return;
    }
    final folderChildTags = _folderChildTagsForItem(item, parentTag);
    for (final child in item.childTags[parentTag] ?? const <String>{}) {
      if (folderChildTags
          .any((folderTag) => TagRules.sameTag(folderTag, child))) {
        continue;
      }
      _store._tagPersistence.attachTagInBatch(
        batch,
        item,
        _tagFor(
          name: child,
          groupId: 'manual',
          source: TagSource.manual,
          parentId: parentTag,
        ),
        source: TagSource.manual,
      );
    }
  }

  /**
   * 为内存视频模型添加 manual 标签兼容字段。
   */
  void _addManualTagToItem(VideoItem item, TagItem tag) {
    final parentId = tag.parentId;
    if (parentId == null) {
      item.tags.add(tag.name);
      return;
    }
    (item.childTags[parentId] ??= <String>{}).add(tag.name);
  }

  /**
   * 从内存视频模型移除 manual 标签兼容字段。
   *
   * 如果同名标签仍由 folder 路径派生，兼容字段必须保留，只删除 manual 关联。
   */
  bool _removeManualTagFromItem(VideoItem item, TagItem tag) {
    final parentId = tag.parentId;
    if (parentId == null) {
      final folderTags = _folderTagsForItem(item);
      final shouldKeepFolder =
          folderTags.any((folderTag) => TagRules.sameTag(folderTag, tag.name));
      if (shouldKeepFolder) {
        return false;
      }
      final before = item.tags.length;
      item.tags.removeWhere((value) => TagRules.sameTag(value, tag.name));
      return item.tags.length != before;
    }
    final folderChildren = _folderChildTagsForItem(item, parentId);
    final shouldKeepFolder = folderChildren
        .any((folderTag) => TagRules.sameTag(folderTag, tag.name));
    if (shouldKeepFolder) {
      return false;
    }
    final children = item.childTags[parentId];
    if (children == null) {
      return false;
    }
    final before = children.length;
    children.removeWhere((value) => TagRules.sameTag(value, tag.name));
    if (children.isEmpty) {
      item.childTags.remove(parentId);
    }
    return children.length != before;
  }

  /**
   * 根据视频路径重新计算 folder 来源一级标签。
   */
  Set<String> _folderTagsForItem(VideoItem item) {
    final rootPath = item.rootPath;
    if (rootPath == null || rootPath.isEmpty) {
      return const <String>{};
    }
    return TagRules.parentTagsFor(rootPath, item.path);
  }

  /**
   * 根据视频路径重新计算指定一级标签下的 folder 来源二级标签。
   */
  Set<String> _folderChildTagsForItem(VideoItem item, String parentTag) {
    final rootPath = item.rootPath;
    if (rootPath == null || rootPath.isEmpty) {
      return const <String>{};
    }
    return TagRules.childTagsFor(rootPath, item.path)[parentTag] ??
        const <String>{};
  }

  /**
   * 获取或创建内存标签模型。
   *
   * tagId 包含 group 与 parentId，避免 folder/manual 同名标签混淆。
   */
  TagItem _tagFor({
    required String name,
    required String groupId,
    required TagSource source,
    String? parentId,
  }) {
    final id =
        TagRules.tagIdFor(name: name, groupId: groupId, parentId: parentId);
    final existing = _store.tagsById[id];
    if (existing != null) {
      return existing;
    }
    final item = TagItem(
      id: id,
      name: name,
      displayName: name,
      groupId: groupId,
      parentId: parentId,
      source: source,
    );
    _store.tagsById[id] = item;
    return item;
  }
}
