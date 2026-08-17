import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';
import 'library_smoke_keys.dart';

// ignore_for_file: slash_for_doc_comments

/** 多选工具栏的全选入口与当前选择数量摘要。 */
class LibrarySelectionSummary extends StatelessWidget {
  const LibrarySelectionSummary({
    super.key,
    required this.selectedCount,
    required this.allSelected,
    required this.onToggleSelectAll,
  });

  /** 当前完整结果范围内已选择的视频数量。 */
  final int selectedCount;

  /** 当前完整结果是否已全部选择。 */
  final bool allSelected;

  /** 圆形复选框承担全选/取消全选入口。 */
  final VoidCallback? onToggleSelectAll;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: LibrarySmokeKeys.librarySelectAll,
      borderRadius: BorderRadius.circular(8),
      onTap: onToggleSelectAll,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Row(
          children: [
            Checkbox(
              value: allSelected,
              onChanged: onToggleSelectAll == null
                  ? null
                  : (_) => onToggleSelectAll!(),
              shape: const CircleBorder(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 6),
            Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: libraryText,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
                children: [
                  const TextSpan(text: '\u5df2\u9009\u62e9 '),
                  TextSpan(
                    text: '$selectedCount',
                    style: const TextStyle(
                      color: appAccentViolet,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const TextSpan(text: ' \u9879'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
