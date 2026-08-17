import 'package:flutter/material.dart';

import '../../models/library_sort.dart';
import '../app_theme_tokens.dart';
import 'library_reference_icon_button.dart';
import 'library_smoke_keys.dart';
import 'library_sort_control.dart';

// ignore_for_file: slash_for_doc_comments

/** 宽桌面排序字段的视觉宽度，同时约束触发入口、弹层和结构轻表面。 */
const double _expandedSortFieldWidth = 168;

/** 排序字段、6px 间距和 48px 方向命中区组成的稳定动作宽度。 */
const double libraryExpandedSortControlWidth = _expandedSortFieldWidth + 6 + 48;

/**
 * 媒体库顶部的响应式排序控件。
 *
 * 宽桌面显示当前字段，中等窗口压缩成图标；两种形态只回调页面已有排序状态。
 */
class LibraryCompactTopSortControl extends StatelessWidget {
  const LibraryCompactTopSortControl({
    super.key,
    required this.sortMode,
    required this.sortDirection,
    required this.showCurrentField,
    required this.onChanged,
    required this.onDirectionToggle,
  });

  /** 当前排序字段。 */
  final SortMode sortMode;

  /** 当前排序方向。 */
  final SortDirection sortDirection;

  /** 是否在宽桌面布局中展示当前排序字段。 */
  final bool showCurrentField;

  /** 选择排序字段后交给页面已有轻量重排入口。 */
  final ValueChanged<SortMode> onChanged;

  /** 切换排序方向。 */
  final VoidCallback onDirectionToggle;

  @override
  Widget build(BuildContext context) {
    final ascending = sortDirection == SortDirection.ascending;
    final fieldButton = PopupMenuButton<SortMode>(
      key: LibrarySmokeKeys.topSortFieldButton,
      tooltip: '\u6392\u5e8f\u5b57\u6bb5\uff1a${sortModeLabel(sortMode)}',
      onSelected: onChanged,
      color: librarySurface,
      initialValue: sortMode,
      // 菜单固定从按钮下方展开，避免遮挡触发入口。
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      constraints: showCurrentField
          ? const BoxConstraints.tightFor(width: _expandedSortFieldWidth)
          : null,
      itemBuilder: (context) => [
        for (final mode in SortMode.values)
          PopupMenuItem<SortMode>(
            key: LibrarySmokeKeys.topSortMenuItem(mode),
            value: mode,
            child: Semantics(
              label: LibrarySmokeSemantics.sortMenuItem(mode),
              selected: mode == sortMode,
              excludeSemantics: true,
              child: Row(
                children: [
                  Icon(
                    mode == sortMode
                        ? Icons.check_rounded
                        : Icons.circle_outlined,
                    size: 17,
                    color:
                        mode == sortMode ? appAccentViolet : libraryTextMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(sortModeLabel(mode)),
                ],
              ),
            ),
          ),
      ],
      borderRadius: BorderRadius.circular(AppRadius.control),
      style: showCurrentField
          ? IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              fixedSize: const Size(
                _expandedSortFieldWidth,
                libraryTopBarControlHeight,
              ),
            )
          : IconButton.styleFrom(
              backgroundColor: librarySurface,
              foregroundColor: libraryTextMuted,
              fixedSize: const Size(
                libraryTopBarControlHeight,
                libraryTopBarControlHeight,
              ),
              side: const BorderSide(color: libraryBorder),
            ),
      icon: showCurrentField ? null : const Icon(Icons.sort_rounded, size: 20),
      child: showCurrentField
          ? SizedBox(
              width: _expandedSortFieldWidth,
              child: Container(
                height: libraryTopBarControlHeight,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: librarySurfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: libraryBorder),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sort_rounded,
                      size: 19,
                      color: appAccentViolet,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        sortModeLabel(sortMode),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: libraryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: libraryTextMuted,
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: LibrarySmokeSemantics.sortFieldButton,
          value: sortModeLabel(sortMode),
          child: fieldButton,
        ),
        const SizedBox(width: 6),
        Semantics(
          key: LibrarySmokeKeys.topSortDirectionButton,
          button: true,
          label: LibrarySmokeSemantics.sortDirectionButton,
          value: ascending ? '\u6b63\u5e8f' : '\u5012\u5e8f',
          child: LibraryReferenceIconButton(
            tooltip: ascending
                ? '\u5207\u6362\u4e3a\u5012\u5e8f'
                : '\u5207\u6362\u4e3a\u6b63\u5e8f',
            icon: ascending
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            onPressed: onDirectionToggle,
          ),
        ),
      ],
    );
  }
}
