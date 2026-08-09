import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/tag_rules.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import 'library_store_access.dart';

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
  final LibraryStoreAccess _store;

  /**
   * 替换单个视频的手动标签作用域。
   *
   * [parentTag] 为空时处理一级 manual 标签；非空时只处理该一级标签下的二级 manual 标签。
   */
  Future<void> replaceManualTags(
    VideoItem item, {
    String? parentTag,
    Iterable<String>? manualTags,
  }) async {
    final pathKey = TagRules.pathKey(item.path);
    final previousLinks = _store.videoTagIdsByPathKey[pathKey] == null
        ? null
        : <String>{..._store.videoTagIdsByPathKey[pathKey]!};
    final previousTagIds = <String>{..._store.tagsById.keys};
    final batch = _store.database.batch();
    try {
      syncManualTagsInBatch(
        batch,
        item,
        parentTag: parentTag,
        manualTags: manualTags,
      );
      _store.videoPersistence.insertInBatch(batch, item);
      await batch.commit(noResult: true);
    } catch (_) {
      // batch 失败时恢复同步阶段提前维护的内存索引；VideoItem 由上层 command 恢复。
      if (previousLinks == null) {
        _store.videoTagIdsByPathKey.remove(pathKey);
      } else {
        _store.videoTagIdsByPathKey[pathKey] = previousLinks;
      }
      _store.tagsById.removeWhere(
        (tagId, _) => !previousTagIds.contains(tagId),
      );
      rethrow;
    }
  }

  /**
   * 将历史上挂在 folder 父级下的 manual 关联提升为独立顶层关联。
   *
   * 早期版本允许 manual 使用二级层级，导致同一个用户标签按不同父目录分裂，候选列表
   * 与顶层筛选都会遗漏其中一部分视频。迁移只移动实际关系并保留旧标签定义，因而可重复
   * 执行、不会删除用户数据；当前模型与后续保存都只消费新的顶层 manual tagId。
   */
  Future<List<VideoItem>> promoteLegacyManualTagsToRoot() async {
    final legacyTags = _store.tagsById.values
        .where(
          (tag) =>
              tag.source == TagSource.manual &&
              tag.parentId != null &&
              tag.parentId!.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (legacyTags.isEmpty) {
      return const <VideoItem>[];
    }

    final itemsByPathKey = <String, VideoItem>{
      ..._store.videos,
      ..._store.detachedVideos,
    };
    final previousLinks = <String, Set<String>>{
      for (final entry in _store.videoTagIdsByPathKey.entries)
        entry.key: <String>{...entry.value},
    };
    final previousTagIds = <String>{..._store.tagsById.keys};
    final itemSnapshots =
        <VideoItem, ({Set<String> tags, Map<String, Set<String>> childTags})>{};
    final affected = <VideoItem>{};
    final batch = _store.database.batch();

    try {
      for (final legacyTag in legacyTags) {
        final linkedPathKeys = [
          for (final entry in _store.videoTagIdsByPathKey.entries)
            if (entry.value.contains(legacyTag.id)) entry.key,
        ];
        for (final pathKey in linkedPathKeys) {
          final item = itemsByPathKey[pathKey];
          // 未加载的孤立关系不应被自动删除，等关联视频恢复后再迁移。
          if (item == null) {
            continue;
          }
          itemSnapshots.putIfAbsent(
            item,
            () => (
              tags: <String>{...item.tags},
              childTags: <String, Set<String>>{
                for (final entry in item.childTags.entries)
                  entry.key: <String>{...entry.value},
              },
            ),
          );
          final rootTag = _independentManualTag(legacyTag);
          _removeManualTagFromItem(item, legacyTag);
          _addManualTagToItem(item, rootTag);
          _store.tagPersistence.attachTagInBatch(
            batch,
            item,
            rootTag,
            source: TagSource.manual,
          );
          batch.delete(
            'video_tags',
            where: 'video_id = ? AND tag_id = ? AND source = ?',
            whereArgs: [item.videoId, legacyTag.id, TagSource.manual.name],
          );
          _store.videoTagIdsByPathKey[pathKey]?.remove(legacyTag.id);
          affected.add(item);
        }
      }
      for (final item in affected) {
        _store.videoPersistence.insertInBatch(batch, item);
      }
      if (affected.isNotEmpty) {
        await batch.commit(noResult: true);
      }
      return affected.toList(growable: false);
    } catch (_) {
      _store.videoTagIdsByPathKey
        ..clear()
        ..addAll(previousLinks);
      _store.tagsById.removeWhere(
        (tagId, _) => !previousTagIds.contains(tagId),
      );
      for (final entry in itemSnapshots.entries) {
        entry.key.tags
          ..clear()
          ..addAll(entry.value.tags);
        entry.key.childTags
          ..clear()
          ..addAll(entry.value.childTags);
      }
      rethrow;
    }
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
    final independentTag = _independentManualTag(tag);
    final batch = _store.database.batch();
    for (final item in videosToUpdate) {
      _addManualTagToItem(item, independentTag);
      _store.videoPersistence.insertInBatch(batch, item);
      _store.tagPersistence.attachTagInBatch(
        batch,
        item,
        independentTag,
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
    final independentTag = tag.parentId == null
        ? tag
        : _store.tagsById[TagRules.tagIdFor(
            name: tag.name, groupId: tag.groupId ?? 'manual')];
    final batch = _store.database.batch();
    var changed = 0;
    for (final item in videosToUpdate) {
      final pathKey = TagRules.pathKey(item.path);
      final linkedTagIds = <String>{
        if (independentTag != null) independentTag.id,
        tag.id,
      };
      var changedCompat = false;
      for (final tagId in linkedTagIds) {
        final hadManualLink =
            _store.videoTagIdsByPathKey[pathKey]?.contains(tagId) ?? false;
        if (independentTag != null && tagId == independentTag.id) {
          changedCompat =
              _removeManualTagFromItem(item, independentTag) || changedCompat;
        } else {
          changedCompat = _removeManualTagFromItem(item, tag) || changedCompat;
        }
        batch.delete(
          'video_tags',
          where: 'video_id = ? AND tag_id = ? AND source = ?',
          whereArgs: [item.videoId, tagId, TagSource.manual.name],
        );
        _store.videoTagIdsByPathKey[pathKey]?.remove(tagId);
        if (hadManualLink) {
          changedCompat = true;
        }
      }
      if (_store.videoTagIdsByPathKey[pathKey]?.isEmpty ?? false) {
        _store.videoTagIdsByPathKey.remove(pathKey);
      }
      if (changedCompat) {
        changed++;
      }
      _store.videoPersistence.insertInBatch(batch, item);
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
    _store.tagPersistence
        .removeVideoTagSourceInBatch(batch, item, TagSource.folder);
    for (final tag in item.tags) {
      _store.tagPersistence.attachTagInBatch(
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
        _store.tagPersistence.attachTagInBatch(
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
   * 调用方提供 [manualTags] 时，按该来源明确的集合写入；同名 folder/manual
   * 可以同时存在，不能再由名称推断来源。旧调用方未提供时才兼容排除 folder 名称。
   */
  void syncManualTagsInBatch(
    Batch batch,
    VideoItem item, {
    String? parentTag,
    Iterable<String>? manualTags,
  }) {
    if (parentTag == null) {
      // 顶层 manual 是独立用户数据；保存时顺便提升历史二级 manual 关系，
      // 但保留由当前文件树派生的 child folder 标签。
      _promoteLegacyManualChildTagsToRoot(item);
      _store.tagPersistence.removeAllManualTagsInBatch(batch, item);
      final tagsToPersist = manualTags ??
          item.tags.where(
            (tag) => !_folderTagsForItem(item)
                .any((folderTag) => TagRules.sameTag(folderTag, tag)),
          );
      for (final tag in tagsToPersist) {
        _store.tagPersistence.attachTagInBatch(
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
    _store.tagPersistence.removeManualTagScopeInBatch(
      batch,
      item,
      parentTag: parentTag,
    );
    final folderChildTags = _folderChildTagsForItem(item, parentTag);
    for (final child in item.childTags[parentTag] ?? const <String>{}) {
      if (folderChildTags
          .any((folderTag) => TagRules.sameTag(folderTag, child))) {
        continue;
      }
      _store.tagPersistence.attachTagInBatch(
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

  /** 将旧版挂在文件夹父级下的 manual 标签提升为独立顶层标签。 */
  void _promoteLegacyManualChildTagsToRoot(VideoItem item) {
    final rootPath = item.rootPath;
    if (rootPath == null || rootPath.isEmpty) {
      return;
    }
    final entries = item.childTags.entries.toList(growable: false);
    for (final entry in entries) {
      final folderChildren = _folderChildTagsForItem(item, entry.key);
      final legacyManualChildren = entry.value
          .where(
            (child) => !folderChildren.any(
              (folderChild) => TagRules.sameTag(folderChild, child),
            ),
          )
          .toList(growable: false);
      if (legacyManualChildren.isEmpty) {
        continue;
      }
      item.tags.addAll(legacyManualChildren);
      entry.value.removeAll(legacyManualChildren);
      if (entry.value.isEmpty) {
        item.childTags.remove(entry.key);
      }
    }
  }

  /**
   * 为内存视频模型添加 manual 标签兼容字段。
   */
  void _addManualTagToItem(VideoItem item, TagItem tag) {
    item.tags.add(tag.name);
  }

  /** 将批量入口收到的历史二级 manual 标签归一为独立顶层标签。 */
  TagItem _independentManualTag(TagItem tag) {
    if (tag.parentId == null) {
      return tag;
    }
    final groupId = tag.groupId ?? 'manual';
    final id = TagRules.tagIdFor(name: tag.name, groupId: groupId);
    final existing = _store.tagsById[id];
    if (existing != null) {
      return existing;
    }
    final promoted = TagItem(
      id: id,
      name: tag.name,
      displayName: tag.displayName ?? tag.name,
      groupId: groupId,
      source: TagSource.manual,
      aliases: tag.aliases,
      isFavorite: tag.isFavorite,
      isHidden: tag.isHidden,
      sortOrder: tag.sortOrder,
    );
    _store.tagsById[id] = promoted;
    return promoted;
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
