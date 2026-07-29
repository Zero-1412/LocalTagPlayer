import 'package:flutter/material.dart';
import '../../core/tag_rules.dart';
import '../../models/platform_models.dart';
import '../../services/library/library_application_facade.dart';
import '../../widgets/library/library_widgets.dart';

import 'library_page_state_host.dart';

// ignore_for_file: slash_for_doc_comments

/** LibraryPageFilterMixin 按既有一致性边界承载页面协调逻辑，不复制业务状态 owner。 */
mixin LibraryPageFilterMixin<T extends StatefulWidget>
    on LibraryPageStateHost<T> {
  void toggleGroupTag(TagItem tag) {
    final groupId = tag.groupId ?? 'manual';
    if (groupId == 'folder.child') {
      toggleFolderChildTag(tag);
      return;
    }
    final selected = runtime.selectedGroupTagIds[groupId] ?? <String>{};
    mutateFilters(() {
      removeEquivalentLegacySelection(tag);
      runtime.excludedTagIds.remove(tag.id);
      if (selected.contains(tag.id)) {
        selected.remove(tag.id);
      } else {
        if (groupId == 'folder.primary' || groupId == 'folder.child') {
          selected.clear();
        }
        selected.add(tag.id);
      }
      if (groupId == 'folder.primary') {
        runtime.selectedChildTags.clear();
        runtime.selectedGroupTagIds.remove('folder.child');
      }
      if (selected.isEmpty) {
        runtime.selectedGroupTagIds.remove(groupId);
      } else {
        runtime.selectedGroupTagIds[groupId] = selected;
      }
    }, collapseTagPanel: true);
  }

  void toggleFolderChildTag(TagItem child) {
    final store = runtime.store;
    if (store == null) {
      return;
    }
    final primary = _folderPrimaryForChild(store, child);
    if (primary == null) {
      return;
    }
    mutateFilters(() {
      removeEquivalentLegacySelection(primary);
      removeEquivalentLegacySelection(child);
      runtime.excludedTagIds
        ..remove(primary.id)
        ..remove(child.id);
      runtime.selectedTags.clear();
      runtime.selectedChildTags.clear();
      runtime.selectedGroupTagIds['folder.primary'] = <String>{primary.id};
      final selectedChildIds =
          runtime.selectedGroupTagIds['folder.child'] ?? const <String>{};
      if (selectedChildIds.length == 1 && selectedChildIds.contains(child.id)) {
        runtime.selectedGroupTagIds.remove('folder.child');
      } else {
        runtime.selectedGroupTagIds['folder.child'] = <String>{child.id};
      }
    }, collapseTagPanel: true);
  }

  TagItem? _folderPrimaryForChild(
    LibraryApplicationFacade store,
    TagItem child,
  ) {
    final parent = child.parentId?.trim();
    if (parent == null || parent.isEmpty) {
      return null;
    }
    for (final group in tagGroupsForSidebar(store)) {
      if (group.id != 'folder.primary') {
        continue;
      }
      for (final primary in group.items) {
        if (primary.id == parent || TagRules.sameTag(primary.name, parent)) {
          return primary;
        }
      }
    }
    return null;
  }

  void selectFolderPrimaryChild(TagItem primary, TagItem? child) {
    mutateFilters(() {
      removeEquivalentLegacySelection(primary);
      if (child != null) {
        removeEquivalentLegacySelection(child);
      }
      runtime.excludedTagIds
        ..remove(primary.id)
        ..remove(child?.id);
      runtime.selectedTags.clear();
      runtime.selectedChildTags.clear();
      runtime.selectedGroupTagIds['folder.primary'] = <String>{primary.id};
      if (child == null) {
        runtime.selectedGroupTagIds.remove('folder.child');
        return;
      }
      final selectedChildIds =
          runtime.selectedGroupTagIds['folder.child'] ?? const <String>{};
      if (selectedChildIds.length == 1 && selectedChildIds.contains(child.id)) {
        runtime.selectedGroupTagIds.remove('folder.child');
      } else {
        runtime.selectedGroupTagIds['folder.child'] = <String>{child.id};
      }
    }, collapseTagPanel: true);
  }

  void toggleExcludedTag(TagItem tag) {
    mutateFilters(() {
      for (final selected in runtime.selectedGroupTagIds.values) {
        selected.remove(tag.id);
      }
      runtime.selectedGroupTagIds
          .removeWhere((_, selected) => selected.isEmpty);
      if (!runtime.excludedTagIds.remove(tag.id)) {
        runtime.excludedTagIds.add(tag.id);
      }
    }, collapseTagPanel: true);
  }

  void removeGroupTag(TagItem tag) {
    final groupId = tag.groupId ?? 'manual';
    mutateFilters(() {
      runtime.selectedGroupTagIds[groupId]?.remove(tag.id);
      runtime.selectedGroupTagIds
          .removeWhere((_, selected) => selected.isEmpty);
    });
  }

  void removeExcludedTag(TagItem tag) {
    mutateFilters(() => runtime.excludedTagIds.remove(tag.id));
  }

  void clearAllFilters() {
    mutateFilters(() {
      clearSearchSilently();
      runtime.selectedTags.clear();
      runtime.selectedChildTags.clear();
      runtime.selectedGroupTagIds.clear();
      runtime.excludedTagIds.clear();
      runtime.showFavoritesOnly = false;
    });
  }

  void removeEquivalentLegacySelection(TagItem tag) {
    if (tag.parentId == null) {
      runtime.selectedTags
          .removeWhere((selected) => TagRules.sameTag(selected, tag.name));
      if (runtime.selectedTags.isEmpty) {
        runtime.selectedChildTags.clear();
      }
      return;
    }
    if (runtime.selectedTags
        .any((selected) => TagRules.sameTag(selected, tag.parentId!))) {
      runtime.selectedChildTags
          .removeWhere((selected) => TagRules.sameTag(selected, tag.name));
    }
  }

  void removeEquivalentGroupSelection({
    required String tagName,
    String? parentTag,
  }) {
    final store = runtime.store;
    if (store == null) {
      return;
    }
    final removedIds = <String>{};
    for (final tag in store.allTagItems) {
      if (!TagRules.sameTag(tag.name, tagName)) {
        continue;
      }
      if (parentTag == null) {
        if (tag.parentId != null) {
          continue;
        }
      } else if (tag.parentId == null ||
          !TagRules.sameTag(tag.parentId!, parentTag)) {
        continue;
      }
      removedIds.add(tag.id);
    }
    if (removedIds.isEmpty) {
      return;
    }
    for (final selected in runtime.selectedGroupTagIds.values) {
      selected.removeAll(removedIds);
    }
    runtime.selectedGroupTagIds.removeWhere((_, selected) => selected.isEmpty);
    runtime.excludedTagIds.removeAll(removedIds);
  }

  // ignore: unused_element
  void showSaveSmartListTodo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '\u4fdd\u5b58\u5f53\u524d\u7b5b\u9009 / Smart List \u5c06\u5728\u540e\u7eed\u9636\u6bb5\u63a5\u5165\u6301\u4e45\u5316\u3002',
        ),
      ),
    );
  }

  // ignore: unused_element
  void showSmartListDraftDialog() {
    final store = runtime.store;
    if (store == null) {
      return;
    }
    final filterState =
        runtime.queryController.state ?? buildImmediateFilterState(store);
    final querySummary = filterSummary(
      store: store,
      resultCount: filterState.resultCount,
      totalCount: filterState.totalCount,
    );
    final queryExpression = filterExpression(
      store: store,
      resultCount: filterState.resultCount,
      totalCount: filterState.totalCount,
    );
    showDialog<void>(
      context: context,
      builder: (dialogContext) => SmartListDraftDialog(
        suggestedName: querySummary,
        querySummary: querySummary,
        queryExpression: queryExpression,
        resultCount: filterState.resultCount,
        totalCount: filterState.totalCount,
        onConfirmDraft: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Smart List \u6301\u4e45\u5316\u5c06\u5728\u540e\u7eed\u63a5\u5165\u3002',
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  List<TagItem> selectedGroupTagItems(LibraryApplicationFacade store) {
    final selectedIds =
        runtime.selectedGroupTagIds.values.expand((ids) => ids).toSet();
    final folderTagsById = {
      for (final group in tagGroupsForSidebar(store))
        for (final tag in group.items) tag.id: tag,
    };
    return [
      for (final id in selectedIds)
        if (folderTagsById[id] != null)
          folderTagsById[id]!
        else if (store.tagsById[id] != null)
          store.tagsById[id]!,
    ]..sort((a, b) => tagLabel(a).compareTo(tagLabel(b)));
  }

  @override
  List<TagItem> excludedTagItems(LibraryApplicationFacade store) {
    return [
      for (final id in runtime.excludedTagIds)
        if (store.tagsById[id] != null) store.tagsById[id]!,
    ]..sort((a, b) => tagLabel(a).compareTo(tagLabel(b)));
  }

  void toggleSingleSelection(Set<String> target, String tag) {
    final wasSelected = target.contains(tag);
    target.clear();
    if (!wasSelected) {
      target.add(tag);
    }
  }

  @override
  String? get activeChildParentTag {
    if (runtime.selectedTags.length == 1) {
      return runtime.selectedTags.first;
    }
    final store = runtime.store;
    final selectedFolderIds =
        runtime.selectedGroupTagIds['folder.primary'] ?? const <String>{};
    if (store == null || selectedFolderIds.length != 1) {
      return null;
    }
    return _folderDiscoveryTagById(store, selectedFolderIds.first)?.name ??
        store.tagQueryContext.findTag(selectedFolderIds.first)?.name;
  }

  @override
  String? get activeChildTagName {
    if (runtime.selectedChildTags.length == 1) {
      return runtime.selectedChildTags.first;
    }
    final store = runtime.store;
    final selectedChildIds =
        runtime.selectedGroupTagIds['folder.child'] ?? const <String>{};
    if (store == null || selectedChildIds.length != 1) {
      return null;
    }
    return _folderDiscoveryTagById(store, selectedChildIds.first)?.name ??
        store.tagQueryContext.findTag(selectedChildIds.first)?.name;
  }

  /**
   * 从真实路径派生的 folder 标签候选中按 id 查找标签。
   *
   * 该查找用于把 UI 选中态转换回 `primaryTagId/childTagId`，避免历史 SQLite tag id
   * 与当前文件树 root 不一致时影响筛选结果。
   */
  TagItem? _folderDiscoveryTagById(
    LibraryApplicationFacade store,
    String tagId,
  ) {
    for (final group in tagGroupsForSidebar(store)) {
      for (final tag in group.items) {
        if (tag.id == tagId) {
          return tag;
        }
      }
    }
    return null;
  }
}
