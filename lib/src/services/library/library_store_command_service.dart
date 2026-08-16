import '../../core/tag_rules.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import 'library_collection_rules.dart';
import 'library_store_access.dart';
import 'library_tag_maintenance.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * LibraryStore 的标签、收藏和 root 元数据命令 owner。
 *
 * 这里承载实际规范化、事务 helper 调用和失败后的内存回滚边界；不复制任何索引，
 * 也不打开第二个 SQLite 连接。视频删除、扫描和 relink 等跨表流程分别由 Store 的
 * persistence owner 与 [LibraryStoreCoordinatorService] 组合完成。
 */
class LibraryStoreCommandService {
  LibraryStoreCommandService({required LibraryStoreAccess repository})
      : _repository = repository,
        _tagMaintenance = LibraryTagMaintenance(repository);

  final LibraryStoreAccess _repository;
  final LibraryTagMaintenance _tagMaintenance;

  Future<void> addFavoriteTag(String tag) async {
    final normalized = TagRules.normalizeTag(tag);
    if (normalized.isEmpty || _repository.favoriteTags.contains(normalized)) {
      return;
    }
    _repository.favoriteTags.add(normalized);
    await saveMetadata();
  }

  Future<void> removeFavoriteTag(String tag) async {
    _repository.favoriteTags
        .removeWhere((value) => TagRules.sameTag(value, tag));
    await saveMetadata();
  }

  Future<void> replaceRoot(String oldRoot, String newRoot) async {
    final oldKey = TagRules.pathKey(TagRules.normalizeRootPath(oldRoot));
    final normalizedNewRoot = TagRules.normalizeRootPath(newRoot);
    final index = _repository.roots.indexWhere(
      (root) => TagRules.pathKey(root) == oldKey,
    );
    if (index < 0 || normalizedNewRoot.isEmpty) {
      return;
    }
    final previousRoot = _repository.roots[index];
    _repository.roots[index] = normalizedNewRoot;
    try {
      await saveMetadata();
    } catch (_) {
      _repository.roots[index] = previousRoot;
      rethrow;
    }
  }

  Future<void> replaceManualTags(
    VideoItem item, {
    String? parentTag,
    Iterable<String>? manualTags,
  }) async {
    await _tagMaintenance.replaceManualTags(
      item,
      parentTag: parentTag,
      manualTags: manualTags,
    );
    _repository.repositoryContext.markDataChanged();
    await _repository.dataBackupService.enqueueVideoBestEffort(item.videoId);
  }

  Future<void> saveTag(TagItem tag) async {
    await _repository.tagPersistence.saveTag(tag);
    _repository.repositoryContext.markDataChanged();
    await _repository.dataBackupService.enqueueTagDependents(tag.id);
  }

  Future<TagItem> createManualTag({
    required String name,
    required String groupId,
    String? displayName,
  }) async {
    final normalized = TagRules.normalizeTag(name);
    if (normalized.isEmpty) {
      throw ArgumentError('tag name is empty');
    }
    final id = TagRules.tagIdFor(name: normalized, groupId: groupId);
    final existing = _repository.tagsById[id];
    if (existing != null && existing.source != TagSource.manual) {
      throw StateError('manual tag conflicts with an existing non-manual tag');
    }
    final tag = existing ??
        TagItem(
          id: id,
          name: normalized,
          displayName: normalized,
          groupId: groupId,
          source: TagSource.manual,
        );
    final updated = TagItem(
      id: tag.id,
      name: tag.name,
      displayName: displayName == null || displayName.trim().isEmpty
          ? tag.displayName
          : displayName.trim(),
      groupId: groupId,
      parentId: tag.parentId,
      color: tag.color,
      source: TagSource.manual,
      aliases: tag.aliases,
      usageCount: tag.usageCount,
      isFavorite: tag.isFavorite,
      isHidden: tag.isHidden,
      sortOrder: tag.sortOrder,
    );
    await saveTag(updated);
    return updated;
  }

  Future<void> updateTagDetails(
    TagItem tag, {
    String? displayName,
    Iterable<String>? aliases,
    String? groupId,
    bool? isHidden,
    bool? isFavorite,
    int? sortOrder,
  }) {
    return saveTag(
      TagItem(
        id: tag.id,
        name: tag.name,
        displayName: displayName,
        groupId: groupId ?? tag.groupId,
        parentId: tag.parentId,
        color: tag.color,
        source: tag.source,
        aliases: aliases == null ? tag.aliases : dedupeLibraryTags(aliases),
        usageCount: tag.usageCount,
        isFavorite: isFavorite ?? tag.isFavorite,
        isHidden: isHidden ?? tag.isHidden,
        sortOrder: sortOrder ?? tag.sortOrder,
      ),
    );
  }

  Future<int> batchAddManualTag(
    TagItem tag,
    Iterable<VideoItem> items,
  ) async {
    final targets = items.toList(growable: false);
    final changed = await _tagMaintenance.batchAddManualTag(tag, targets);
    if (changed > 0) {
      _repository.repositoryContext.markDataChanged();
      await _repository.dataBackupService
          .enqueueVideos(targets.map((item) => item.videoId));
    }
    return changed;
  }

  Future<int> batchRemoveManualTag(
    TagItem tag,
    Iterable<VideoItem> items,
  ) async {
    final targets = items.toList(growable: false);
    final changed = await _tagMaintenance.batchRemoveManualTag(tag, targets);
    if (changed > 0) {
      _repository.repositoryContext.markDataChanged();
      await _repository.dataBackupService
          .enqueueVideos(targets.map((item) => item.videoId));
    }
    return changed;
  }

  Future<void> saveMetadata() async {
    await _repository.metadataPersistence.save(
      roots: _repository.roots,
      favoriteTags: _repository.favoriteTags,
    );
    _repository.repositoryContext.markDataChanged();
  }

  Future<List<VideoItem>> promoteLegacyManualTagsToRoot() async {
    final affected = await _tagMaintenance.promoteLegacyManualTagsToRoot();
    if (affected.isNotEmpty) {
      _repository.repositoryContext.markDataChanged();
      await _repository.dataBackupService.enqueueVideos(
        affected.map((item) => item.videoId),
      );
    }
    return affected;
  }
}
