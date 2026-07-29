import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/layout_size.dart';
import '../../models/library_sort.dart';
import '../../models/platform_models.dart';
import '../app_theme_tokens.dart';
import 'library_reference_top_bar_layout.dart';
import 'library_smoke_keys.dart';
import 'library_top_bar_filter_status.dart';

export 'library_reference_top_bar_layout.dart';
export 'library_scroll_responsive_header.dart';
export 'library_smart_list_draft_dialog.dart';

/** 顶栏搜索框在主布局或窄行中占据剩余宽度，防止动作按钮溢出。 */
bool referenceTopBarSearchShouldFillRow(
  LayoutSize layoutSize,
  double rowWidth,
) {
  return layoutSize != LayoutSize.expanded || rowWidth < 1120;
}

/**
 * 顶栏与首行视频卡片之间的垂直留白。
 *
 * 搜索、筛选状态和结果卡片属于不同视觉层级，保留明确间距可以避免首行缩略图紧贴
 * 搜索表面；该值只影响布局，不改变搜索输入或筛选刷新链路。
 */
const double libraryTopBarBottomSpacing = 18;

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

class ReferenceTopBar extends StatelessWidget {
  const ReferenceTopBar({
    required this.controller,
    required this.searchFocusNode,
    required this.videoCount,
    this.resultCountLabel,
    required this.keyword,
    required this.selectedTags,
    required this.selectedChildTags,
    required this.selectedGroupTags,
    required this.excludedTags,
    required this.defaultChipLabel,
    required this.showFavoritesOnly,
    required this.refreshing,
    required this.progressLabel,
    required this.progressValue,
    required this.sortMode,
    required this.sortDirection,
    required this.layoutSize,
    required this.hasActiveFilters,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onSortDirectionToggle,
    required this.denseResultGrid,
    required this.onResultViewChanged,
    required this.onOpenTagManager,
    required this.onOpenFilters,
    this.tagPanelOpen = false,
    this.onToggleTagPanel,
    required this.onRemovePrimaryTag,
    required this.onRemoveChildTag,
    required this.onRemoveGroupTag,
    required this.onRemoveExcludedTag,
    required this.onClearKeyword,
    required this.onClearFavoritesOnly,
    required this.onClearAll,
    this.progressPaused = false,
    this.onToggleProgressPaused,
    this.onCancelProgress,
    this.selectionMode = false,
    this.selectedCount = 0,
    this.allSelected = false,
    this.onEnterSelectionMode,
    this.onToggleSelectAll,
    this.onDeleteSelected,
    this.onCancelSelectionMode,
  });

  final TextEditingController controller;

  /**
   * 主搜索框焦点节点。
   *
   * 顶部栏内部处理 `Ctrl+K` 时只请求该节点焦点，不直接改写搜索业务状态；
   * 文本变化仍统一从 TextField 的 controller / onChanged 进入筛选链路。
   */
  final FocusNode searchFocusNode;

  /** 当前可见结果数量；与搜索和 chips 同处一个结果状态区域。 */
  final int videoCount;

  /** 本地目录等混合来源的精确统计文案。 */
  final String? resultCountLabel;

  /** 当前关键词只保留在真实输入框中，不重复渲染为 chip。 */
  final String keyword;

  /** 当前一级 folder 标签筛选。 */
  final List<String> selectedTags;

  /** 当前二级 folder 标签筛选。 */
  final List<String> selectedChildTags;

  /** 当前分组标签筛选。 */
  final List<TagItem> selectedGroupTags;

  /** 当前排除标签筛选。 */
  final List<TagItem> excludedTags;

  /** 最近播放、本地收藏或本地目录等非全库结果来源名称。 */
  final String defaultChipLabel;

  /** 是否启用收藏筛选。 */
  final bool showFavoritesOnly;

  /** 当前结果或标签计数是否正在后台刷新。 */
  final bool refreshing;

  /** 扫描或媒体解析时替代普通结果数量的状态。 */
  final String? progressLabel;

  /** 已知总量任务的进度值。 */
  final double? progressValue;

  final SortMode sortMode;

  final SortDirection sortDirection;

  final LayoutSize layoutSize;

  final bool hasActiveFilters;

  final ValueChanged<String> onSearchChanged;

  final ValueChanged<SortMode> onSortChanged;

  final VoidCallback onSortDirectionToggle;

  final bool denseResultGrid;

  final ValueChanged<bool> onResultViewChanged;

  final VoidCallback onOpenTagManager;

  final VoidCallback onOpenFilters;

  /** expanded 桌面布局中的标签浏览面板是否已经展开。 */
  final bool tagPanelOpen;

  /** 从页面标题区展开或收起标签浏览面板；中小布局继续使用底部筛选面板。 */
  final VoidCallback? onToggleTagPanel;

  final ValueChanged<String> onRemovePrimaryTag;

  final ValueChanged<String> onRemoveChildTag;

  final ValueChanged<TagItem> onRemoveGroupTag;

  final ValueChanged<TagItem> onRemoveExcludedTag;

  final VoidCallback onClearKeyword;

  final VoidCallback onClearFavoritesOnly;

  final VoidCallback? onClearAll;

  /** true 时暂停按钮切换为继续图标。 */
  final bool progressPaused;

  /** 后台媒体解析存在时提供暂停/继续入口。 */
  final VoidCallback? onToggleProgressPaused;

  /** 扫描期间提供取消入口；其它后台任务保持为空。 */
  final VoidCallback? onCancelProgress;

  /** true 时整条顶栏替换为批量选择状态。 */
  final bool selectionMode;

  /** 当前完整结果范围内已选择的视频数量。 */
  final int selectedCount;

  /** 当前完整结果是否已全部选择。 */
  final bool allSelected;

  /** 进入多选模式；为空时当前结果来源不支持批量删除。 */
  final VoidCallback? onEnterSelectionMode;

  /** 切换完整当前结果的全选状态。 */
  final VoidCallback? onToggleSelectAll;

  /** 删除已选视频；未选择时页面传入 null。 */
  final VoidCallback? onDeleteSelected;

  /** 退出多选并清空临时选择。 */
  final VoidCallback? onCancelSelectionMode;

  @override
  Widget build(BuildContext context) {
    final compact = layoutSize == LayoutSize.compact;
    final accessibility = AppAccessibilityScope.of(context);
    // 只在非紧凑桌面工具栏扩展结果状态宽度；125%/150% 下完整保留
    // “11163 个视频”这类关键反馈，同时不改变筛选、排序或搜索语义。
    final resultTextScaleAllowance = compact
        ? 0.0
        : (accessibility.textScaler.scale(1).clamp(1.0, 1.5) - 1) * 160;
    final keywordActive = keyword.trim().isNotEmpty;
    final activeFilters = <LibraryFilterToolbarEntry>[
      if (showFavoritesOnly)
        LibraryFilterToolbarEntry(
          label: '\u672c\u5730\u6536\u85cf',
          icon: Icons.favorite_rounded,
          onRemove: onClearFavoritesOnly,
        ),
      for (final tag in selectedTags)
        LibraryFilterToolbarEntry(
          label: tag,
          onRemove: () => onRemovePrimaryTag(tag),
        ),
      for (final tag in selectedChildTags)
        LibraryFilterToolbarEntry(
          label: tag,
          onRemove: () => onRemoveChildTag(tag),
        ),
      for (final tag in selectedGroupTags)
        LibraryFilterToolbarEntry(
          label: tag.displayName ?? tag.name,
          onRemove: () => onRemoveGroupTag(tag),
        ),
      for (final tag in excludedTags)
        LibraryFilterToolbarEntry(
          label: 'NOT ${tag.displayName ?? tag.name}',
          onRemove: () => onRemoveExcludedTag(tag),
        ),
    ];
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            const FocusLibrarySearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          FocusLibrarySearchIntent: CallbackAction<FocusLibrarySearchIntent>(
            onInvoke: (_) {
              searchFocusNode.requestFocus();
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
              // 顶部栏单独作为 smoke 宿主时也补一次下一帧聚焦，保持与真实页面一致。
              WidgetsBinding.instance.addPostFrameCallback((_) {
                searchFocusNode.requestFocus();
                controller.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: controller.text.length,
                );
              });
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                layoutSize == LayoutSize.expanded ? 20 : 12,
                12,
                layoutSize == LayoutSize.expanded ? 20 : 12,
                libraryTopBarBottomSpacing,
              ),
              child: DecoratedBox(
                key: LibrarySmokeKeys.libraryResultToolbar,
                decoration: BoxDecoration(
                  color: layoutSize == LayoutSize.expanded
                      ? Colors.transparent
                      : librarySurface,
                  borderRadius: BorderRadius.circular(AppRadius.panel),
                  border: layoutSize == LayoutSize.expanded
                      ? null
                      : Border.all(color: libraryBorder),
                ),
                child: Padding(
                  // expanded 主界面改用“标题 + 操作 + 状态”的分层结构，不再把所有功能
                  // 塞进一个后台工具条式容器；中小布局仍保留紧凑单行，避免占用结果空间。
                  padding: layoutSize == LayoutSize.expanded
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                  child: LibraryReferenceTopBarLayout(
                    controller: controller,
                    searchFocusNode: searchFocusNode,
                    videoCount: videoCount,
                    resultCountLabel: resultCountLabel,
                    keywordActive: keywordActive,
                    defaultChipLabel: defaultChipLabel,
                    refreshing: refreshing,
                    progressLabel: progressLabel,
                    progressValue: progressValue,
                    progressPaused: progressPaused,
                    sortMode: sortMode,
                    sortDirection: sortDirection,
                    layoutSize: layoutSize,
                    hasActiveFilters: hasActiveFilters,
                    activeFilters: activeFilters,
                    resultTextScaleAllowance: resultTextScaleAllowance,
                    onSearchChanged: onSearchChanged,
                    onSortChanged: onSortChanged,
                    onSortDirectionToggle: onSortDirectionToggle,
                    denseResultGrid: denseResultGrid,
                    onResultViewChanged: onResultViewChanged,
                    onOpenTagManager: onOpenTagManager,
                    onOpenFilters: onOpenFilters,
                    tagPanelOpen: tagPanelOpen,
                    onToggleTagPanel: onToggleTagPanel,
                    onClearKeyword: onClearKeyword,
                    onClearAll: onClearAll,
                    onToggleProgressPaused: onToggleProgressPaused,
                    onCancelProgress: onCancelProgress,
                    selectionMode: selectionMode,
                    selectedCount: selectedCount,
                    allSelected: allSelected,
                    onEnterSelectionMode: onEnterSelectionMode,
                    onToggleSelectAll: onToggleSelectAll,
                    onDeleteSelected: onDeleteSelected,
                    onCancelSelectionMode: onCancelSelectionMode,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/**
 * 顶部搜索框聚焦意图。
 *
 * 独立 intent 让快捷键层只负责焦点转移，不复制搜索和筛选逻辑。
 */
class FocusLibrarySearchIntent extends Intent {
  const FocusLibrarySearchIntent();
}
