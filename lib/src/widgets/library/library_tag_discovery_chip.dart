import 'package:flutter/material.dart';

import '../../models/platform_models.dart';
import '../app_theme_tokens.dart';
import 'library_smoke_keys.dart';
import 'library_tag_display_helpers.dart';

// ignore_for_file: slash_for_doc_comments

class TagFilterChip extends StatelessWidget {
  const TagFilterChip({
    super.key,
    required this.tag,
    required this.groupColor,
    required this.count,
    required this.selected,
    required this.excluded,
    required this.onToggle,
    required this.onExcludeToggle,
    this.semanticLabel,
  });

  final TagItem tag;

  final Color groupColor;

  final int count;

  final bool selected;

  final bool excluded;

  final VoidCallback onToggle;

  final VoidCallback onExcludeToggle;

  /**
   * 真实窗口 QA 使用的稳定语义标签。
   *
   * 二级标签需要携带所属一级上下文，避免辅助树定位时把不同层级的同名标签混在一起。
   */
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final textColor = excluded ? const Color(0xffb42318) : groupColor;
    final borderColor = excluded
        ? const Color(0xffffb4ad)
        : selected
            ? const Color(0xffd8d4ff)
            : const Color(0xffe6ecf5);
    final backgroundColor = excluded
        ? const Color(0xfffff1f0)
        : selected
            ? const Color(0xfff3f0ff)
            : librarySurfaceAlt;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? LibrarySmokeSemantics.genericTag(tag),
      value: formatCount(count),
      child: GestureDetector(
        onLongPress: onExcludeToggle,
        child: Material(
          key: LibrarySmokeKeys.tagChip(tag.id),
          color: backgroundColor,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onToggle,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected || excluded) ...[
                    Icon(
                      excluded
                          ? Icons.remove_circle_outline
                          : Icons.check_circle_rounded,
                      size: 16,
                      color: textColor,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    excluded
                        ? 'NOT ${tag.displayName ?? tag.name}'
                        : (tag.displayName ?? tag.name),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatCount(count),
                    style: const TextStyle(
                      color: libraryTextMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
