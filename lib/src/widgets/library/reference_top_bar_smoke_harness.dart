import 'package:flutter/material.dart';

import '../../core/layout_size.dart';
import '../../models/library_sort.dart';
import '../../models/platform_models.dart';
import '../app_theme_tokens.dart';
import 'library_widgets.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 顶部搜索栏 focused test 入口。
 *
 * 只暴露真实顶栏搜索输入链路，避免测试复制搜索 UI 后漏掉桌面输入问题。
 */
@visibleForTesting
Widget referenceTopBarSearchSmokeHarness({
  required TextEditingController controller,
  required ValueChanged<String> onSearchChanged,
  FocusNode? searchFocusNode,
  int videoCount = 0,
  String? resultCountLabel,
  String? keyword,
  List<String> selectedTags = const <String>[],
  List<String> selectedChildTags = const <String>[],
  List<TagItem> selectedGroupTags = const <TagItem>[],
  List<TagItem> excludedTags = const <TagItem>[],
  String defaultChipLabel = '\u5168\u90e8\u89c6\u9891',
  bool showFavoritesOnly = false,
  bool refreshing = false,
  String? progressLabel,
  double? progressValue,
  bool progressPaused = false,
  VoidCallback? onToggleProgressPaused,
  VoidCallback? onCancelProgress,
  LayoutSize layoutSize = LayoutSize.expanded,
  SortDirection sortDirection = SortDirection.descending,
  ValueChanged<SortMode>? onSortChanged,
  VoidCallback? onSortDirectionToggle,
  ValueChanged<String>? onRemovePrimaryTag,
  ValueChanged<String>? onRemoveChildTag,
  ValueChanged<TagItem>? onRemoveGroupTag,
  ValueChanged<TagItem>? onRemoveExcludedTag,
  VoidCallback? onClearKeyword,
  VoidCallback? onClearFavoritesOnly,
  VoidCallback? onClearAll,
  bool selectionMode = false,
  int selectedCount = 0,
  bool allSelected = false,
  AppAccessibilityData? accessibility,
  VoidCallback? onEnterSelectionMode,
  VoidCallback? onToggleSelectAll,
  VoidCallback? onDeleteSelected,
  VoidCallback? onCancelSelectionMode,
  bool tagPanelOpen = false,
  VoidCallback? onToggleTagPanel,
}) {
  final app = MaterialApp(
    builder: accessibility == null
        ? null
        : (context, child) {
            // 文字缩放同时进入 MediaQuery 与设计策略作用域，避免假验收。
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(textScaler: accessibility.textScaler),
              child: child!,
            );
          },
    home: Scaffold(
      body: ReferenceTopBar(
        controller: controller,
        searchFocusNode:
            searchFocusNode ?? FocusNode(debugLabel: 'search-smoke-field'),
        videoCount: videoCount,
        resultCountLabel: resultCountLabel,
        keyword: keyword ?? controller.text,
        selectedTags: selectedTags,
        selectedChildTags: selectedChildTags,
        selectedGroupTags: selectedGroupTags,
        excludedTags: excludedTags,
        defaultChipLabel: defaultChipLabel,
        showFavoritesOnly: showFavoritesOnly,
        refreshing: refreshing,
        progressLabel: progressLabel,
        progressValue: progressValue,
        progressPaused: progressPaused,
        onToggleProgressPaused: onToggleProgressPaused,
        onCancelProgress: onCancelProgress,
        sortMode: SortMode.recent,
        sortDirection: sortDirection,
        layoutSize: layoutSize,
        hasActiveFilters: (keyword ?? controller.text).trim().isNotEmpty ||
            showFavoritesOnly ||
            selectedTags.isNotEmpty ||
            selectedChildTags.isNotEmpty ||
            selectedGroupTags.isNotEmpty ||
            excludedTags.isNotEmpty,
        onSearchChanged: onSearchChanged,
        onSortChanged: onSortChanged ?? (_) {},
        onSortDirectionToggle: onSortDirectionToggle ?? () {},
        denseResultGrid: false,
        onResultViewChanged: (_) {},
        onOpenTagManager: () {},
        onOpenFilters: () {},
        tagPanelOpen: tagPanelOpen,
        onToggleTagPanel: onToggleTagPanel,
        onRemovePrimaryTag: onRemovePrimaryTag ?? (_) {},
        onRemoveChildTag: onRemoveChildTag ?? (_) {},
        onRemoveGroupTag: onRemoveGroupTag ?? (_) {},
        onRemoveExcludedTag: onRemoveExcludedTag ?? (_) {},
        onClearKeyword: onClearKeyword ?? () {},
        onClearFavoritesOnly: onClearFavoritesOnly ?? () {},
        onClearAll: onClearAll,
        selectionMode: selectionMode,
        selectedCount: selectedCount,
        allSelected: allSelected,
        onEnterSelectionMode: onEnterSelectionMode,
        onToggleSelectAll: onToggleSelectAll,
        onDeleteSelected: onDeleteSelected,
        onCancelSelectionMode: onCancelSelectionMode,
      ),
    ),
  );
  if (accessibility == null) {
    return app;
  }
  return AppAccessibilityScope(data: accessibility, child: app);
}
