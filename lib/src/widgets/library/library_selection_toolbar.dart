import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';
import 'library_reference_icon_button.dart';
import 'library_selection_summary.dart';
import 'library_smoke_keys.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库多选状态工具栏。
 *
 * 组件只显示选择快照并转发全选、删除与取消意图，不持有选择集合或删除命令。
 */
class LibrarySelectionToolbar extends StatelessWidget {
  const LibrarySelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.allSelected,
    required this.onToggleSelectAll,
    required this.onDeleteSelected,
    required this.onCancel,
  });

  /** 当前完整结果范围内已选择的视频数量。 */
  final int selectedCount;

  /** 当前完整结果是否已全部选择。 */
  final bool allSelected;

  /** 圆形复选框承担全选/取消全选入口。 */
  final VoidCallback? onToggleSelectAll;

  /** 删除已选视频；未选择时由页面传入 null。 */
  final VoidCallback? onDeleteSelected;

  /** 退出多选并清空临时选择。 */
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: LibrarySmokeKeys.selectionStatusArea,
      width: double.infinity,
      height: libraryTopBarControlHeight,
      child: Row(
        children: [
          LibrarySelectionSummary(
            selectedCount: selectedCount,
            allSelected: allSelected,
            onToggleSelectAll: onToggleSelectAll,
          ),
          const Spacer(),
          TextButton.icon(
            key: LibrarySmokeKeys.libraryDeleteSelected,
            onPressed: onDeleteSelected,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('\u5220\u9664'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xffe26573),
              disabledForegroundColor: libraryTextMuted.withValues(alpha: 0.45),
              backgroundColor: onDeleteSelected == null
                  ? Colors.transparent
                  : const Color(0x24e26573),
              minimumSize: const Size(68, 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: LibrarySmokeKeys.libraryCancelSelection,
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: libraryTextMuted,
              minimumSize: const Size(56, 34),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('\u53d6\u6d88'),
          ),
        ],
      ),
    );
  }
}
