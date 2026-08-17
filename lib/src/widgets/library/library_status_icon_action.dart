import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';
import '../design_system/app_interaction_surface.dart';

// ignore_for_file: slash_for_doc_comments

/** 搜索与筛选状态共用的 40 像素图标动作，保留 tooltip、焦点和按压反馈。 */
class LibraryStatusIconAction extends StatelessWidget {
  const LibraryStatusIconAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  /** 鼠标悬停和辅助技术读取的动作名称。 */
  final String tooltip;

  /** 与动作语义对应的 Material 图标。 */
  final IconData icon;

  /** 点击或键盘激活回调。 */
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 40,
      child: Tooltip(
        message: tooltip,
        child: AppInteractionSurface(
          semanticLabel: tooltip,
          onTap: onPressed,
          padding: EdgeInsets.zero,
          borderRadius: AppRadius.control,
          backgroundColor: Colors.transparent,
          child: Center(
            child: Icon(icon, size: 17, color: libraryTextMuted),
          ),
        ),
      ),
    );
  }
}
