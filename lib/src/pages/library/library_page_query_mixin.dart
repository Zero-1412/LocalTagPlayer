import 'package:flutter/material.dart';
import '../../core/tag_rules.dart';
import '../../features/library/domain/library_query_snapshot.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../services/library/library_application_facade.dart';
import '../../services/tags/tag_query_service.dart';
import '../../widgets/library/library_folder_tag_discovery.dart';

import 'library_page_state_host.dart';

// ignore_for_file: slash_for_doc_comments

/** LibraryPageQueryMixin 按既有一致性边界承载页面协调逻辑，不复制业务状态 owner。 */
mixin LibraryPageQueryMixin<T extends StatefulWidget>
    on LibraryPageStateHost<T> {
  /**
   * 构建用于诊断和播放器队列标题的完整筛选表达式。
   */
  @override
  String filterExpression({
    required LibraryApplicationFacade store,
    required int resultCount,
    required int totalCount,
  }) {
    final parts = <String>[];
    final keyword = runtime.searchController.text.trim();
    if (keyword.isNotEmpty) {
      parts.add('keyword:"$keyword"');
    }
    final primaryTags = runtime.selectedTags.toList()..sort();
    parts.addAll(primaryTags.map((tag) => 'legacy:$tag'));
    final childTags = runtime.selectedChildTags.toList()..sort();
    if (childTags.isNotEmpty) {
      parts.add('child:(${childTags.join('|')})');
    }
    final groupsById = {
      for (final group in tagGroupsForSidebar(store)) group.id: group
    };
    final selectedEntries = runtime.selectedGroupTagIds.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in selectedEntries) {
      final tagLabels = [
        for (final id in entry.value)
          if (store.tagsById[id] != null) tagLabel(store.tagsById[id]!),
      ]..sort();
      if (tagLabels.isEmpty) {
        continue;
      }
      final group = groupsById[entry.key];
      parts.add(
        '${group == null ? entry.key : groupLabel(group)}:(${tagLabels.join('|')})',
      );
    }
    parts.addAll(excludedTagItems(store).map((tag) => '-${tagLabel(tag)}'));
    if (runtime.showFavoritesOnly) {
      parts.add('favorite');
    }
    final expression =
        parts.isEmpty ? '\u5168\u90e8\u89c6\u9891' : parts.join(' AND ');
    return '$expression  |  $resultCount / $totalCount';
  }

  /**
   * 构建面向用户的短筛选摘要。
   */
  @override
  String filterSummary({
    required LibraryApplicationFacade store,
    required int resultCount,
    required int totalCount,
  }) {
    final parts = <String>[];
    final hierarchyParts = <String>[];
    final keyword = runtime.searchController.text.trim();
    hierarchyParts.addAll(runtime.selectedTags.toList()..sort());
    hierarchyParts.addAll(runtime.selectedChildTags.toList()..sort());
    final selectedItems = selectedGroupTagItems(store);
    hierarchyParts.addAll([
      for (final tag in selectedItems)
        if (tag.groupId == 'folder.primary' || tag.groupId == 'folder.child')
          tag.displayName ?? tag.name,
    ]);
    if (hierarchyParts.isNotEmpty) {
      parts.add(hierarchyParts.toSet().join(' / '));
    }
    final otherLabels = [
      for (final tag in selectedItems)
        if (tag.groupId != 'folder.primary' && tag.groupId != 'folder.child')
          tag.displayName ?? tag.name,
    ]..sort();
    parts.addAll(otherLabels);
    if (keyword.isNotEmpty) {
      parts.add('关键词 $keyword');
    }
    final excludedCount = runtime.excludedTagIds.length;
    if (excludedCount > 0) {
      parts.add('NOT $excludedCount');
    }
    if (runtime.showFavoritesOnly) {
      parts.add('favorite');
    }
    final label = parts.isEmpty ? '全部视频' : parts.join(' + ');
    return '$label · $resultCount 个结果';
  }

  /**
   * 切换排序方向，并只重排当前结果。
   */
  void toggleSortDirection() {
    applySortChange(
      sortDirection: runtime.sortController.oppositeDirection,
    );
  }

  @override
  void scheduleFilterRefresh({
    bool refreshCounts = false,
    Iterable<VideoItem>? changedVideos,
  }) {
    final store = runtime.store;
    if (store == null) {
      return;
    }
    if (!refreshCounts) {
      runtime.facetCountController.cancelPending();
    }
    final query = currentFilterQuery();
    final resultEpoch = this.resultEpoch(query);
    final countEpoch = this.countEpoch(query);
    runtime.queryController.configure(
      engine: TagQueryService(
        videos: store.videos.values,
        tagContext: store.tagQueryContext,
      ),
      totalCount: store.videos.length,
      dataRevision: runtime.libraryDataRevision,
      sortFingerprint: runtime.sortController.fingerprint,
      compare: runtime.sortController.compare,
      sortVideos: runtime.sortController.sort,
    );
    runtime.queryController.schedule(
      query: query,
      expectedEpoch: resultEpoch,
      changedVideos: changedVideos,
      isStillCurrent: (candidate) =>
          mounted &&
          runtime.store == store &&
          candidate == this.resultEpoch(currentFilterQuery()),
      onMeasured: changedVideos == null
          ? null
          : (elapsed) => runtime.activeScanUiDiagnostics?.recordStage(
                'ui.filter_delta_apply',
                elapsed,
                itemCount: changedVideos.length,
              ),
      onAccepted: (nextState) {
        if (!mounted || runtime.store != store) {
          return;
        }
        setState(() {
          runtime.isRefreshingVideos = false;
        });
        // 真正的可见窗口由虚拟列表滚动停止后驱动；固定取结果前 36 条会在深度滚动时
        // 抢占错误项目，因此这里不再猜测可见范围。
        if (!refreshCounts) {
          return;
        }
        runtime.facetCountController.scheduleVisible(
          epoch: countEpoch,
          query: query,
          compute: store.resultCounts,
          isStillCurrent: (epoch) =>
              mounted &&
              runtime.store == store &&
              epoch == this.countEpoch(currentFilterQuery()),
          onAccepted: (epoch, nextCounts) {
            if (!mounted || epoch != countEpoch || runtime.store != store) {
              return;
            }
            setState(() {
              runtime.isRefreshingCounts = false;
            });
          },
        );
      },
    );
  }

  /** 返回当前查询可发布的结果版本。 */
  @override
  LibraryResultEpoch resultEpoch(FilterQuery query) =>
      LibraryResultEpoch.fromQuery(
        dataRevision: runtime.libraryDataRevision,
        query: query,
        presentationSort: runtime.sortController.fingerprint,
      );

  /** 返回当前查询可发布的计数版本；标签定义使用独立代次。 */
  @override
  LibraryCountEpoch countEpoch(FilterQuery query) =>
      LibraryCountEpoch.fromQuery(
        dataRevision: runtime.libraryDataRevision,
        tagDefinitionRevision: runtime.tagDefinitionRevision,
        query: query,
      );

  @override
  FilterQuery currentFilterQuery() {
    final store = runtime.store;
    final parentTag = activeChildParentTag;
    final selectedChildTag = activeChildTagName;
    return FilterQuery(
      keyword: runtime.searchController.text,
      primaryTagId: parentTag,
      childTagId: parentTag == null ? null : selectedChildTag,
      folderRoots: parentTag == null
          ? const <String>[]
          : store?.roots ?? const <String>[],
      selectedGroupTagIds: {
        for (final entry in runtime.selectedGroupTagIds.entries)
          if (entry.value.isNotEmpty &&
              entry.key != 'folder.primary' &&
              entry.key != 'folder.child')
            entry.key: {...entry.value},
      },
      excludeTagIds: {...runtime.excludedTagIds},
      favoriteOnly: runtime.showFavoritesOnly,
    );
  }

  @override
  List<TagGroup> tagGroupsForSidebar(LibraryApplicationFacade store) {
    final cacheKey = (
      runtime.libraryDataRevision,
      store.tagsById.length,
      rootsSignature(store.roots),
    );
    if (runtime.tagGroupsCacheKey == cacheKey) {
      return runtime.tagGroupsCache;
    }
    final rebuildWatch = Stopwatch()..start();
    final folderGroups = folderTagGroupsFromLibraryPaths(
      videos: store.videos.values,
      roots: store.roots,
      templates: store.tagGroups,
    );
    final folderGroupById = {for (final group in folderGroups) group.id: group};
    final itemsByGroup = <String, List<TagItem>>{};
    for (final tag in store.allTagItems.where((tag) => !tag.isHidden)) {
      final groupId = tag.groupId ?? 'manual';
      if (groupId == 'folder.primary' || groupId == 'folder.child') {
        continue;
      }
      (itemsByGroup[groupId] ??= <TagItem>[]).add(tag);
    }
    final groups = <TagGroup>[];
    final knownGroupIds = <String>{};
    for (final group in store.tagGroups) {
      knownGroupIds.add(group.id);
      final folderGroup = folderGroupById[group.id];
      if (folderGroup != null) {
        groups.add(folderGroup);
        continue;
      }
      final items = itemsByGroup[group.id] ?? const <TagItem>[];
      groups.add(_copyGroupWithItems(group, items));
    }
    for (final folderGroup in folderGroups) {
      if (!knownGroupIds.contains(folderGroup.id)) {
        groups.add(folderGroup);
        knownGroupIds.add(folderGroup.id);
      }
    }
    for (final entry in itemsByGroup.entries) {
      if (knownGroupIds.contains(entry.key)) {
        continue;
      }
      groups.add(
        TagGroup(
          id: entry.key,
          name: entry.key,
          displayName: entry.key,
          sortOrder: 999,
          items: sortedTagItems(entry.value),
        ),
      );
    }
    groups.removeWhere((group) => group.items.isEmpty);
    groups.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) {
        return byOrder;
      }
      return groupLabel(a).compareTo(groupLabel(b));
    });
    runtime.tagGroupsCacheKey = cacheKey;
    runtime.tagGroupsCache = List<TagGroup>.unmodifiable(groups);
    rebuildWatch.stop();
    runtime.activeScanUiDiagnostics?.recordStage(
      'ui.folder_sidebar_rebuild',
      rebuildWatch.elapsed,
      itemCount: store.videos.length,
    );
    return runtime.tagGroupsCache;
  }

  String rootsSignature(Iterable<String> roots) {
    final normalized = [
      for (final root in roots) TagRules.pathKey(root),
    ]..sort();
    return normalized.join('|');
  }

  TagGroup _copyGroupWithItems(TagGroup group, Iterable<TagItem> items) {
    return TagGroup(
      id: group.id,
      name: group.name,
      displayName: group.displayName,
      sortOrder: group.sortOrder,
      allowMultiSelect: group.allowMultiSelect,
      defaultLogic: group.defaultLogic,
      items: sortedTagItems(items),
      excludedItems: group.excludedItems,
    );
  }

  List<TagItem> sortedTagItems(Iterable<TagItem> items) {
    final sorted = items.toList();
    sorted.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) {
        return byOrder;
      }
      final byUsage = b.usageCount.compareTo(a.usageCount);
      if (byUsage != 0) {
        return byUsage;
      }
      return tagLabel(a).compareTo(tagLabel(b));
    });
    return sorted;
  }

  String groupLabel(TagGroup group) => group.displayName ?? group.name;

  @override
  String tagLabel(TagItem tag) => tag.displayName ?? tag.name;

  bool get hasActiveFilters => !currentFilterQuery().isEmpty;
}
