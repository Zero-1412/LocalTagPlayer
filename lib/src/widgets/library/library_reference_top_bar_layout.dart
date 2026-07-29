import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/layout_size.dart';
import '../../models/library_sort.dart';
import '../app_theme_tokens.dart';
import 'library_compact_top_sort_control.dart';
import 'library_reference_icon_button.dart';
import 'library_result_view_toggle.dart';
import 'library_selection_toolbar.dart';
import 'library_smoke_keys.dart';
import 'library_tag_discovery_header_button.dart';
import 'library_top_bar_filter_status.dart';
import 'library_top_bar_search_surface.dart';
import 'library_top_toolbar_text_button.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库顶栏的响应式内容布局。
 *
 * 只接收页面提供的只读快照与回调，在 expanded、medium、compact 三种布局间编排
 * 搜索、筛选状态、排序和多选工具；不持有筛选、扫描、队列或用户数据 owner。
 */
class LibraryReferenceTopBarLayout extends StatelessWidget {
  const LibraryReferenceTopBarLayout({
    super.key,
    required this.controller,
    required this.searchFocusNode,
    required this.videoCount,
    required this.resultCountLabel,
    required this.keywordActive,
    required this.defaultChipLabel,
    required this.refreshing,
    required this.progressLabel,
    required this.progressValue,
    required this.progressPaused,
    required this.sortMode,
    required this.sortDirection,
    required this.layoutSize,
    required this.hasActiveFilters,
    required this.activeFilters,
    required this.resultTextScaleAllowance,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onSortDirectionToggle,
    required this.denseResultGrid,
    required this.onResultViewChanged,
    required this.onOpenTagManager,
    required this.onOpenFilters,
    required this.tagPanelOpen,
    required this.onToggleTagPanel,
    required this.onClearKeyword,
    required this.onClearAll,
    required this.onToggleProgressPaused,
    required this.onCancelProgress,
    required this.selectionMode,
    required this.selectedCount,
    required this.allSelected,
    required this.onEnterSelectionMode,
    required this.onToggleSelectAll,
    required this.onDeleteSelected,
    required this.onCancelSelectionMode,
  });

  /** 稳定搜索输入链路使用的文本控制器。 */
  final TextEditingController controller;
  /** 搜索快捷键请求焦点时使用的节点。 */
  final FocusNode searchFocusNode;
  /** 当前可见视频数量快照。 */
  final int videoCount;
  /** 混合来源结果统计文案。 */
  final String? resultCountLabel;
  /** 当前关键词是否非空。 */
  final bool keywordActive;
  /** 当前资料库视图名称。 */
  final String defaultChipLabel;
  /** 筛选结果是否正在后台刷新。 */
  final bool refreshing;
  /** 扫描或解析任务状态文案。 */
  final String? progressLabel;
  /** 已知总量任务的进度快照。 */
  final double? progressValue;
  /** 后台任务是否暂停。 */
  final bool progressPaused;
  /** 当前排序字段。 */
  final SortMode sortMode;
  /** 当前排序方向。 */
  final SortDirection sortDirection;
  /** 当前响应式布局级别。 */
  final LayoutSize layoutSize;
  /** 是否存在会改变结果集的筛选条件。 */
  final bool hasActiveFilters;
  /** 已归一化的只读筛选展示项。 */
  final List<LibraryFilterToolbarEntry> activeFilters;
  /** 系统文字缩放为结果状态预留的额外宽度。 */
  final double resultTextScaleAllowance;
  /** 搜索文本变化回调。 */
  final ValueChanged<String> onSearchChanged;
  /** 排序字段变化回调。 */
  final ValueChanged<SortMode> onSortChanged;
  /** 排序方向切换回调。 */
  final VoidCallback onSortDirectionToggle;
  /** 是否使用紧凑结果网格。 */
  final bool denseResultGrid;
  /** 结果视图密度变化回调。 */
  final ValueChanged<bool> onResultViewChanged;
  /** 打开标签中心的回调。 */
  final VoidCallback onOpenTagManager;
  /** 打开窄布局筛选面板的回调。 */
  final VoidCallback onOpenFilters;
  /** expanded 标签浏览面板是否展开。 */
  final bool tagPanelOpen;
  /** expanded 标签浏览面板切换回调。 */
  final VoidCallback? onToggleTagPanel;
  /** 清空搜索关键词回调。 */
  final VoidCallback onClearKeyword;
  /** 清空全部筛选回调。 */
  final VoidCallback? onClearAll;
  /** 暂停或继续后台任务回调。 */
  final VoidCallback? onToggleProgressPaused;
  /** 取消后台任务回调。 */
  final VoidCallback? onCancelProgress;
  /** 当前是否处于批量选择模式。 */
  final bool selectionMode;
  /** 当前已选视频数量。 */
  final int selectedCount;
  /** 当前结果是否全部选中。 */
  final bool allSelected;
  /** 进入批量选择模式回调。 */
  final VoidCallback? onEnterSelectionMode;
  /** 切换全选状态回调。 */
  final VoidCallback? onToggleSelectAll;
  /** 删除已选视频回调。 */
  final VoidCallback? onDeleteSelected;
  /** 退出批量选择模式回调。 */
  final VoidCallback? onCancelSelectionMode;

  @override
  Widget build(BuildContext context) {
    final compact = layoutSize == LayoutSize.compact;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrowMedium =
            layoutSize == LayoutSize.medium && constraints.maxWidth < 620;
        final proportionalDesktop =
            layoutSize == LayoutSize.expanded && constraints.maxWidth >= 1180;
        final searchSurface = LibrarySearchSurface(
          controller: controller,
          searchFocusNode: searchFocusNode,
          compact: compact,
          keywordActive: keywordActive,
          onSearchChanged: onSearchChanged,
          onClearKeyword: onClearKeyword,
        );
        final filterStatus = LibraryFilterStatusArea(
          compact: compact || narrowMedium,
          defaultLabel: defaultChipLabel,
          filters: activeFilters,
          resultCount: videoCount,
          resultCountLabel: resultCountLabel,
          refreshing: refreshing,
          progressLabel: progressLabel,
          progressValue: progressValue,
          progressPaused: progressPaused,
          onToggleProgressPaused: onToggleProgressPaused,
          onCancelProgress: onCancelProgress,
          onClearAll: onClearAll,
          showResultStatus: !proportionalDesktop,
        );
        final resultStatus = SizedBox(
          key: LibrarySmokeKeys.toolbarResultStatus,
          width: progressLabel == null
              ? (resultCountLabel == null ? 92 : 200) + resultTextScaleAllowance
              : 224,
          child: LibraryFilterResultLine(
            resultCount: videoCount,
            resultCountLabel: resultCountLabel,
            refreshing: refreshing,
            progressLabel: progressLabel,
            progressValue: progressValue,
            progressPaused: progressPaused,
            onToggleProgressPaused: onToggleProgressPaused,
            onCancelProgress: onCancelProgress,
          ),
        );
        final selectionStatus = LibrarySelectionToolbar(
          selectedCount: selectedCount,
          allSelected: allSelected,
          onToggleSelectAll: onToggleSelectAll,
          onDeleteSelected: onDeleteSelected,
          onCancel: onCancelSelectionMode,
        );
        final sortControl = LibraryCompactTopSortControl(
          sortMode: sortMode,
          sortDirection: sortDirection,
          showCurrentField: layoutSize == LayoutSize.expanded,
          onChanged: onSortChanged,
          onDirectionToggle: onSortDirectionToggle,
        );
        final normalActions = SizedBox(
          key: LibrarySmokeKeys.toolbarActions,
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onEnterSelectionMode != null)
                if (compact || narrowMedium)
                  LibraryReferenceIconButton(
                    key: LibrarySmokeKeys.libraryEnterSelection,
                    tooltip: '\u591a\u9009',
                    icon: Icons.checklist_rounded,
                    onPressed: onEnterSelectionMode!,
                  )
                else
                  LibraryTopToolbarTextButton(
                    key: LibrarySmokeKeys.libraryEnterSelection,
                    onPressed: onEnterSelectionMode!,
                    label: '\u591a\u9009',
                  ),
              if (onEnterSelectionMode != null && !compact && !narrowMedium)
                const SizedBox(width: 8),
              if (!compact && !narrowMedium)
                ResultViewToggle(
                  dense: denseResultGrid,
                  onChanged: onResultViewChanged,
                ),
            ],
          ),
        );
        if (layoutSize == LayoutSize.expanded) {
          final pageTitle =
              defaultChipLabel == '全部视频' ? '媒体库' : defaultChipLabel;
          final resultStatusWidth = progressLabel == null
              ? (resultCountLabel == null ? 104.0 : 200.0) +
                  resultTextScaleAllowance
              : 224.0;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pageTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: libraryText,
                              fontSize: 24,
                              height: 1.12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            defaultChipLabel == '全部视频'
                                ? '全部视频 · 浏览、搜索并整理你的本地视频'
                                : '当前资料库视图',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: libraryTextMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      key: LibrarySmokeKeys.toolbarResultStatus,
                      width: resultStatusWidth,
                      child: LibraryFilterResultLine(
                        resultCount: videoCount,
                        resultCountLabel: resultCountLabel,
                        refreshing: refreshing,
                        progressLabel: progressLabel,
                        progressValue: progressValue,
                        progressPaused: progressPaused,
                        onToggleProgressPaused: onToggleProgressPaused,
                        onCancelProgress: onCancelProgress,
                      ),
                    ),
                    if (onToggleTagPanel != null) ...[
                      const SizedBox(width: 12),
                      LibraryTagDiscoveryHeaderButton(
                        expanded: tagPanelOpen,
                        activeFilterCount: activeFilters.length,
                        onPressed: onToggleTagPanel!,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 搜索和动作直接落在画布上，各自用自身 surface 表达可交互性；
              // 不再用大圆角容器包裹一组已经带边框的控件，避免“容器套容器”。
              SizedBox(
                key: LibrarySmokeKeys.headerActionLane,
                height: 50,
                child: Row(
                  children: [
                    Expanded(child: searchSurface),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 380,
                      child: selectionMode
                          ? selectionStatus
                          : Row(
                              children: [
                                // 桌面动作带保留固定宽度以避免进入多选时搜索框跳动；
                                // 排序字段使用紧凑稳定宽度，余量只作为方向与低频动作的分组间距。
                                SizedBox(
                                  width: libraryExpandedSortControlWidth,
                                  child: sortControl,
                                ),
                                const SizedBox(width: 12),
                                // 把少量响应式余量留在动作分组之间，保持视图切换与右边界对齐。
                                const Spacer(),
                                normalActions,
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              if (!selectionMode && activeFilters.isNotEmpty) ...[
                const SizedBox(height: 8),
                KeyedSubtree(
                  key: LibrarySmokeKeys.filterStatusArea,
                  child: LibraryFilterStatusArea(
                    compact: false,
                    defaultLabel: defaultChipLabel,
                    filters: activeFilters,
                    resultCount: videoCount,
                    resultCountLabel: resultCountLabel,
                    refreshing: refreshing,
                    progressLabel: progressLabel,
                    progressValue: progressValue,
                    progressPaused: progressPaused,
                    onToggleProgressPaused: onToggleProgressPaused,
                    onCancelProgress: onCancelProgress,
                    onClearAll: onClearAll,
                    showResultStatus: false,
                  ),
                ),
              ],
            ],
          );
        }
        if (proportionalDesktop) {
          return SizedBox(
            height: 50,
            child: Row(
              children: [
                // 搜索从 60% 收敛到 50%，把标签浏览和媒体库状态提升为同级主场景。
                Expanded(flex: 5, child: searchSurface),
                const SizedBox(width: 12),
                if (selectionMode) ...[
                  Expanded(flex: 5, child: selectionStatus),
                  // 与常态区域保留相同总间距，进入多选时搜索框宽度不会跳动。
                  const SizedBox(width: 8),
                ] else ...[
                  Expanded(
                    flex: 4,
                    child: KeyedSubtree(
                      key: LibrarySmokeKeys.filterStatusArea,
                      child: Row(
                        children: [
                          Expanded(child: filterStatus),
                          const SizedBox(width: 8),
                          sortControl,
                          const SizedBox(width: 10),
                          resultStatus,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(flex: 1, child: normalActions),
                ],
              ],
            ),
          );
        }
        return Row(
          children: [
            if (layoutSize != LayoutSize.expanded) ...[
              LibraryReferenceIconButton(
                tooltip: '\u6253\u5f00\u667a\u80fd\u7b5b\u9009',
                icon: hasActiveFilters
                    ? Icons.filter_alt_rounded
                    : Icons.filter_alt_outlined,
                onPressed: onOpenFilters,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(child: searchSurface),
            const SizedBox(width: 8),
            if (selectionMode)
              SizedBox(width: 280, child: selectionStatus)
            else ...[
              SizedBox(
                key: LibrarySmokeKeys.filterStatusArea,
                width: progressLabel != null
                    ? math.min(
                        360,
                        math.max(224, constraints.maxWidth * 0.42),
                      )
                    : activeFilters.isNotEmpty
                        ? narrowMedium
                            ? 82
                            : math.min(
                                220,
                                math.max(
                                  142,
                                  constraints.maxWidth * 0.24,
                                ),
                              )
                        : narrowMedium
                            ? 82
                            : resultCountLabel != null
                                ? 200 + resultTextScaleAllowance
                                : 118 + resultTextScaleAllowance,
                child: filterStatus,
              ),
              if (!compact &&
                  !(progressLabel != null && constraints.maxWidth < 700)) ...[
                const SizedBox(width: 8),
                sortControl,
              ],
              if (compact) ...[
                const SizedBox(width: 8),
                LibraryReferenceIconButton(
                  tooltip: '标签中心',
                  icon: Icons.sell_outlined,
                  onPressed: onOpenTagManager,
                ),
              ],
              if (!(progressLabel != null && constraints.maxWidth < 700)) ...[
                const SizedBox(width: 8),
                normalActions,
              ],
            ],
          ],
        );
      },
    );
  }
}
