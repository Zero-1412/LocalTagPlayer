import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 侧栏导航的轻量选中态。
 *
 * 选中态只使用低对比度底色和左侧定位线，避免导航栏与媒体缩略图争夺注意力。
 */
BoxDecoration librarySidebarSelectionDecoration({required bool selected}) {
  return BoxDecoration(
    color:
        selected ? appAccentViolet.withValues(alpha: 0.10) : Colors.transparent,
    border: Border(
      left: BorderSide(
        color: selected ? appAccentViolet : Colors.transparent,
        width: 2,
      ),
    ),
    borderRadius: BorderRadius.circular(AppRadius.control),
  );
}
