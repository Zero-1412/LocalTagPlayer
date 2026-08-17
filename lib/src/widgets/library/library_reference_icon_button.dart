import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 媒体库结果工具栏的一线控件统一高度，覆盖搜索、排序和视图动作。 */
const double libraryTopBarControlHeight = 48;

/** 顶栏紧凑描边图标按钮。 */
class LibraryReferenceIconButton extends StatelessWidget {
  const LibraryReferenceIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  /** 桌面悬停与辅助技术提示。 */
  final String tooltip;

  /** 按钮图标。 */
  final IconData icon;

  /** 点击意图。 */
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: librarySurface,
        foregroundColor: libraryTextMuted,
        fixedSize: const Size(
          libraryTopBarControlHeight,
          libraryTopBarControlHeight,
        ),
        side: const BorderSide(color: libraryBorder),
      ),
    );
  }
}
