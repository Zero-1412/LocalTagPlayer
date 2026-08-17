import 'package:flutter/material.dart';

import '../../models/library_sort.dart';
import '../app_theme_tokens.dart';
import 'library_reference_top_bar_tokens.dart';
import 'library_sort_control.dart';

// ignore_for_file: slash_for_doc_comments

/** 宽桌面排序按钮中的字段摘要，保持字段与方向按钮使用同一高度基线。 */
class SortFieldPreview extends StatelessWidget {
  const SortFieldPreview({
    super.key,
    required this.width,
    required this.sortMode,
  });

  /** 排序字段触发入口的稳定宽度。 */
  final double width;

  /** 当前排序字段。 */
  final SortMode sortMode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
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
            const Icon(Icons.sort_rounded, size: 19, color: appAccentViolet),
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
    );
  }
}
