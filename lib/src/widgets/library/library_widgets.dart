import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/layout_size.dart';
import '../../models/library_sort.dart';
import '../../models/platform_models.dart';
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

class SmartListDraftDialog extends StatefulWidget {
  const SmartListDraftDialog({
    required this.suggestedName,
    required this.querySummary,
    required this.queryExpression,
    required this.resultCount,
    required this.totalCount,
    required this.onConfirmDraft,
  });

  final String suggestedName;
  final String querySummary;
  final String queryExpression;
  final int resultCount;
  final int totalCount;
  final VoidCallback onConfirmDraft;

  @override
  State<SmartListDraftDialog> createState() => SmartListDraftDialogState();
}

class SmartListDraftDialogState extends State<SmartListDraftDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.suggestedName);
  var _autoRefreshPreview = true;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _confirmDraft() {
    Navigator.of(context).pop();
    widget.onConfirmDraft();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
      actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xfff5f3ff),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xffd8d4ff)),
            ),
            child: const Icon(Icons.bookmark_add_outlined,
                color: appAccentViolet, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '\u4fdd\u5b58\u7b5b\u9009\u8349\u6848',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '\u7b5b\u9009\u540d\u79f0',
                prefixIcon: Icon(Icons.edit_outlined),
              ),
            ),
            const SizedBox(height: 14),
            _SmartListPreviewPanel(
              querySummary: widget.querySummary,
              queryExpression: widget.queryExpression,
              resultCount: widget.resultCount,
              totalCount: widget.totalCount,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _autoRefreshPreview,
              onChanged: (value) {
                setState(() => _autoRefreshPreview = value);
              },
              contentPadding: EdgeInsets.zero,
              title: const Text('\u81ea\u52a8\u5237\u65b0\u9884\u89c8'),
              subtitle: const Text(
                  '\u4ec5\u9a8c\u8bc1 UI \u6d41\u7a0b\uff0c\u4e0d\u5199\u5165 SQLite'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('\u53d6\u6d88'),
        ),
        FilledButton.icon(
          onPressed: _confirmDraft,
          icon: const Icon(Icons.check_rounded),
          label: const Text('\u786e\u8ba4\u8349\u6848'),
        ),
      ],
    );
  }
}

class _SmartListPreviewPanel extends StatelessWidget {
  const _SmartListPreviewPanel({
    required this.querySummary,
    required this.queryExpression,
    required this.resultCount,
    required this.totalCount,
  });

  final String querySummary;
  final String queryExpression;
  final int resultCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: libraryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.manage_search_rounded,
                  size: 18, color: appAccentViolet),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  querySummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: libraryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$resultCount / $totalCount',
                style: const TextStyle(
                  color: appAccentViolet,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            queryExpression,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: libraryTextMuted,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/**
 * 根据结果区是否处于绝对顶部收起或恢复媒体库顶部信息区。
 *
 * 动画只包裹顶部 chrome，不读取筛选结果，也不驱动视频逐项动画；[visibleListenable]
 * 由结果滚动组件仅在跨越顶部边界时更新，避免逐像素重建页面。
 */
class LibraryScrollResponsiveHeader extends StatefulWidget {
  const LibraryScrollResponsiveHeader({
    super.key,
    required this.visibleListenable,
    required this.child,
  });

  /** 顶部信息区的目标可见状态。 */
  final ValueListenable<bool> visibleListenable;

  /** 保留原有搜索、筛选、排序和动作语义的顶部内容。 */
  final Widget child;

  @override
  State<LibraryScrollResponsiveHeader> createState() =>
      _LibraryScrollResponsiveHeaderState();
}

/** 管理可打断的顶部尺寸、透明度和短距离位移动画。 */
class _LibraryScrollResponsiveHeaderState
    extends State<LibraryScrollResponsiveHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _visibilityAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
      value: widget.visibleListenable.value ? 1 : 0,
    );
    _visibilityAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.045),
      end: Offset.zero,
    ).animate(_visibilityAnimation);
    widget.visibleListenable.addListener(_handleVisibilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animateToTarget();
  }

  @override
  void didUpdateWidget(covariant LibraryScrollResponsiveHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibleListenable != widget.visibleListenable) {
      oldWidget.visibleListenable.removeListener(_handleVisibilityChanged);
      widget.visibleListenable.addListener(_handleVisibilityChanged);
    }
    _animateToTarget();
  }

  /** 响应轻量可见性通知，并从当前动画进度直接反向。 */
  void _handleVisibilityChanged() {
    if (mounted) {
      _animateToTarget();
    }
  }

  /** 根据无障碍策略平滑抵达目标；reduced motion 下立即完成结构变化。 */
  void _animateToTarget() {
    final visible = widget.visibleListenable.value;
    final accessibility = AppAccessibilityScope.of(context);
    if (accessibility.reduceMotion) {
      _controller.value = visible ? 1 : 0;
      return;
    }
    if (visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    widget.visibleListenable.removeListener(_handleVisibilityChanged);
    _visibilityAnimation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final targetVisible = widget.visibleListenable.value;
        return ExcludeFocus(
          excluding: !targetVisible,
          child: ExcludeSemantics(
            excluding: !targetVisible,
            child: IgnorePointer(
              ignoring: !targetVisible,
              child: SizeTransition(
                sizeFactor: _visibilityAnimation,
                alignment: Alignment.topCenter,
                child: FadeTransition(
                  opacity: _visibilityAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrowMedium = layoutSize == LayoutSize.medium &&
                          constraints.maxWidth < 620;
                      final proportionalDesktop =
                          layoutSize == LayoutSize.expanded &&
                              constraints.maxWidth >= 1180;
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
                            ? (resultCountLabel == null ? 92 : 200) +
                                resultTextScaleAllowance
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
                            if (onEnterSelectionMode != null &&
                                !compact &&
                                !narrowMedium)
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
                        final pageTitle = defaultChipLabel == '全部视频'
                            ? '媒体库'
                            : defaultChipLabel;
                        final resultStatusWidth = progressLabel == null
                            ? (resultCountLabel == null ? 104.0 : 200.0) +
                                resultTextScaleAllowance
                            : 224.0;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                      onToggleProgressPaused:
                                          onToggleProgressPaused,
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
                                                width:
                                                    libraryExpandedSortControlWidth,
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
                                  onToggleProgressPaused:
                                      onToggleProgressPaused,
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
                                      math.max(
                                          224, constraints.maxWidth * 0.42),
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
                                !(progressLabel != null &&
                                    constraints.maxWidth < 700)) ...[
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
                            if (!(progressLabel != null &&
                                constraints.maxWidth < 700)) ...[
                              const SizedBox(width: 8),
                              normalActions,
                            ],
                          ],
                        ],
                      );
                    },
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
