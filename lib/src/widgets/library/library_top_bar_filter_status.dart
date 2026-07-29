import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';
import 'library_smoke_keys.dart';
import 'library_top_bar_search_surface.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

/** 单行筛选工具栏中一个可移除筛选项的轻量描述。 */
class LibraryFilterToolbarEntry {
  const LibraryFilterToolbarEntry({
    required this.label,
    required this.onRemove,
    this.icon,
  });

  final String label;
  final VoidCallback onRemove;
  final IconData? icon;
}

/**
 * 搜索框右侧的筛选结果状态区域。
 *
 * 该区域使用低对比度实色表面，与更高权重的搜索输入形成明确层级；筛选标签只表达当前状态，
 * 空间不足时折叠为数量，不反向压缩搜索框或复制过滤计算。
 */
class LibraryFilterStatusArea extends StatelessWidget {
  const LibraryFilterStatusArea({
    required this.compact,
    required this.defaultLabel,
    required this.filters,
    required this.resultCount,
    this.resultCountLabel,
    required this.refreshing,
    required this.progressLabel,
    required this.progressValue,
    required this.progressPaused,
    required this.onToggleProgressPaused,
    required this.onCancelProgress,
    required this.onClearAll,
    this.showResultStatus = true,
  });

  /** 紧凑布局只展示最必要的状态。 */
  final bool compact;

  /** 非全库来源在没有筛选标签时展示的上下文名称。 */
  final String defaultLabel;

  /** 当前标签、收藏与排除条件。 */
  final List<LibraryFilterToolbarEntry> filters;

  /** 当前筛选结果数量。 */
  final int resultCount;

  /** 非纯视频来源的精确统计文案，例如“40 个文件夹 · 0 个视频”。 */
  final String? resultCountLabel;

  /** 结果或旁路计数正在后台刷新。 */
  final bool refreshing;

  /** 扫描或媒体解析期间替代普通数量的状态。 */
  final String? progressLabel;

  /** 后台任务的确定型进度；null 表示未知总量。 */
  final double? progressValue;

  /** 后台任务是否暂停。 */
  final bool progressPaused;

  /** 暂停或继续后台任务。 */
  final VoidCallback? onToggleProgressPaused;

  /** 取消当前可取消的扫描任务；媒体解析等不可取消任务传 null。 */
  final VoidCallback? onCancelProgress;

  /** 一次清除全部筛选；为空时不绘制入口。 */
  final VoidCallback? onClearAll;

  /** 是否在本区域末端绘制结果数量；宽屏由排序控件之后的独立状态承担。 */
  final bool showResultStatus;

  @override
  Widget build(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    // 结果数量是高频导航反馈。桌面文字放大时预留最多 80px，避免五位数媒体库数量
    // 在仍有充足搜索空间的窗口里被省略；紧凑布局继续优先保护搜索与清除操作。
    final resultTextScaleAllowance = compact
        ? 0.0
        : (accessibility.textScaler.scale(1).clamp(1.0, 1.5) - 1) * 160;
    final resultLabel =
        progressLabel ?? resultCountLabel ?? '$resultCount \u4e2a\u89c6\u9891';
    return Semantics(
      container: true,
      liveRegion: refreshing || progressLabel != null,
      label: '\u5f53\u524d\u7b5b\u9009\u72b6\u6001\uff0c$resultLabel',
      child: Container(
        height: compact ? 44 : 50,
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
        decoration: BoxDecoration(
          color: accessibility.highContrast
              ? librarySurface
              : librarySurface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: accessibility.highContrast
                ? libraryTextMuted
                : libraryBorder.withValues(alpha: 0.82),
            width: accessibility.highContrast ? 1.5 : 1,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasFilters = filters.isNotEmpty;
            // 活动筛选及其清除入口是结果语义的一部分；窄空间下先让位普通数量，
            // 避免用户只能从结果变化猜测筛选是否仍然生效。扫描进度仍保持可见。
            final showInlineResultStatus = showResultStatus &&
                (progressLabel != null ||
                    !hasFilters ||
                    constraints.maxWidth >= 230);
            final trailingWidth = !showInlineResultStatus
                ? 0.0
                : progressLabel == null
                    ? resultCountLabel != null
                        ? 200.0 + resultTextScaleAllowance
                        : (compact ? 74.0 : 92.0 + resultTextScaleAllowance)
                    : 224.0;
            final showClearAll = onClearAll != null && hasFilters;
            final clearWidth = showClearAll ? 40.0 : 0.0;
            final filterBudget = math.max(
              0.0,
              constraints.maxWidth -
                  trailingWidth -
                  clearWidth -
                  (compact ? 8.0 : 14.0),
            );
            // 标签过多时只在状态区内折叠，不污染搜索输入。
            final maxVisibleFilters = filterBudget >= 145
                ? 2
                : filterBudget >= 92
                    ? 1
                    : 0;
            final visibleFilters = filters.take(maxVisibleFilters).toList();
            final hiddenCount = filters.length - visibleFilters.length;
            final showCollapsedCount = hiddenCount > 0 &&
                filterBudget >= (visibleFilters.isEmpty ? 56 : 42);
            final visibleFilterBudget = math.max(
              0.0,
              filterBudget -
                  (showCollapsedCount ? (visibleFilters.isEmpty ? 56 : 42) : 0),
            );
            final showSourceLabel = filters.isEmpty && filterBudget >= 96;
            return Row(
              children: [
                if (showSourceLabel) ...[
                  _SourceContextChip(label: defaultLabel),
                  const SizedBox(width: 6),
                ],
                if (visibleFilters.isNotEmpty)
                  ConstrainedBox(
                    key: LibrarySmokeKeys.searchFilterLane,
                    constraints: BoxConstraints(maxWidth: visibleFilterBudget),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: Row(
                        children: [
                          for (var index = 0;
                              index < visibleFilters.length;
                              index++) ...[
                            _CurrentFilterChip(
                              avatar: visibleFilters[index].icon == null
                                  ? null
                                  : Icon(
                                      visibleFilters[index].icon,
                                      size: 14,
                                      color: libraryTextMuted,
                                    ),
                              label: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: compact ? 68 : 84,
                                ),
                                child: Text(
                                  visibleFilters[index].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              onDeleted: visibleFilters[index].onRemove,
                            ),
                            if (index != visibleFilters.length - 1)
                              const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (visibleFilters.isNotEmpty) const SizedBox(width: 6),
                if (showCollapsedCount) ...[
                  _CollapsedFilterCount(
                    count: hiddenCount,
                    showFilterPrefix: visibleFilters.isEmpty,
                  ),
                  // 折叠数量已是窄宽最后一项时不保留无意义尾间距，避免 452px 桌面窗口溢出。
                  if (showClearAll || showInlineResultStatus)
                    const SizedBox(width: 6),
                ],
                if (showClearAll)
                  LibraryStatusIconAction(
                    tooltip: '\u6e05\u7a7a\u5168\u90e8\u7b5b\u9009',
                    icon: Icons.filter_alt_off_outlined,
                    onPressed: onClearAll!,
                  ),
                if (showInlineResultStatus) ...[
                  const Spacer(),
                  SizedBox(
                    width: math.min(trailingWidth, constraints.maxWidth),
                    child: LibraryFilterResultLine(
                      resultCount: resultCount,
                      resultCountLabel: resultCountLabel,
                      refreshing: refreshing,
                      progressLabel: progressLabel,
                      progressValue: progressValue,
                      progressPaused: progressPaused,
                      onToggleProgressPaused: onToggleProgressPaused,
                      onCancelProgress: onCancelProgress,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/** 非全库来源的只读上下文 chip，不伪装成可删除筛选条件。 */
class _SourceContextChip extends StatelessWidget {
  const _SourceContextChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: libraryBorder),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: libraryTextMuted,
          fontSize: AppTypography.caption,
          fontWeight: AppTypography.strong,
        ),
      ),
    );
  }
}

/** 被折叠的筛选数量，不承担交互，避免与真实筛选 chip 混淆。 */
class _CollapsedFilterCount extends StatelessWidget {
  const _CollapsedFilterCount({
    required this.count,
    required this.showFilterPrefix,
  });

  /** 当前未单独展示的活动筛选数量。 */
  final int count;

  /** 没有可见 chip 时用“筛选 N”明确表达当前状态，而不是只显示含糊的“+N”。 */
  final bool showFilterPrefix;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: libraryBorder),
      ),
      child: Text(
        showFilterPrefix ? '筛选 $count' : '+$count',
        style: const TextStyle(
          color: libraryTextMuted,
          fontSize: AppTypography.caption,
          fontWeight: AppTypography.strong,
        ),
      ),
    );
  }
}

class _CurrentFilterChip extends StatelessWidget {
  const _CurrentFilterChip({
    required this.label,
    this.avatar,
    this.onDeleted,
  });

  final Widget? avatar;

  final Widget label;

  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: avatar,
      label: label,
      onDeleted: onDeleted,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      color: WidgetStateProperty.resolveWith((states) {
        // 紫色只表示交互状态变化，常态保持中性灰，避免与数量和选中态争夺注意力。
        if (states.contains(WidgetState.focused) ||
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed)) {
          return appAccentViolet.withValues(alpha: 0.18);
        }
        return librarySurfaceAlt;
      }),
      deleteIconColor: libraryTextMuted,
      deleteIcon: const Icon(Icons.close_rounded, size: 15),
      deleteButtonTooltipMessage: '\u79fb\u9664\u8be5\u7b5b\u9009',
      labelStyle: const TextStyle(
        color: libraryText,
        fontSize: AppTypography.caption,
        fontWeight: AppTypography.strong,
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
    );
  }
}

class LibraryFilterResultLine extends StatelessWidget {
  const LibraryFilterResultLine({
    required this.resultCount,
    this.resultCountLabel,
    required this.refreshing,
    required this.progressLabel,
    required this.progressValue,
    required this.progressPaused,
    required this.onToggleProgressPaused,
    required this.onCancelProgress,
  });

  final int resultCount;

  /** 自定义结果统计；为空时沿用“视频”语义。 */
  final String? resultCountLabel;

  final bool refreshing;

  final String? progressLabel;

  final double? progressValue;

  final bool progressPaused;

  final VoidCallback? onToggleProgressPaused;

  /** 当前扫描的取消入口；为空时不占用进度行空间。 */
  final VoidCallback? onCancelProgress;

  @override
  Widget build(BuildContext context) {
    final operationInProgress = progressLabel != null;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (!operationInProgress) ...[
        const Icon(Icons.circle, size: 7, color: appAccentViolet),
        const SizedBox(width: AppSpacing.xs),
      ],
      Flexible(
        child: Text(
          progressLabel ?? resultCountLabel ?? '$resultCount 个视频',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: libraryText,
            fontSize: 13,
            fontWeight: AppTypography.strong,
          ),
        ),
      ),
      if (operationInProgress) ...[
        const SizedBox(width: 8),
        if (progressValue == null)
          const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          SizedBox(
            width: 64,
            child: LinearProgressIndicator(
              value: progressValue!.clamp(0, 1),
              minHeight: 4,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: const Color(0xffe7e4ff),
            ),
          ),
        if (onToggleProgressPaused != null) ...[
          const SizedBox(width: 4),
          SizedBox.square(
            dimension: 28,
            child: IconButton(
              key: ValueKey(progressPaused
                  ? 'qa.media_import.resume'
                  : 'qa.media_import.pause'),
              tooltip: progressPaused ? '继续后台任务' : '暂停后台任务',
              padding: EdgeInsets.zero,
              iconSize: 18,
              color: appAccentViolet,
              onPressed: onToggleProgressPaused,
              icon: Icon(
                progressPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              ),
            ),
          ),
        ],
        if (onCancelProgress != null) ...[
          const SizedBox(width: 2),
          SizedBox.square(
            dimension: 28,
            child: IconButton(
              key: const ValueKey('qa.library_scan.cancel'),
              tooltip: '取消扫描',
              padding: EdgeInsets.zero,
              iconSize: 17,
              color: libraryTextMuted,
              onPressed: onCancelProgress,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ] else if (refreshing) ...[
        const SizedBox(width: 8),
        const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ],
    ]);
  }
}
