import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 顶栏低频文字动作。
 *
 * 保留 48px 命中高度与相邻控件对齐，但使用透明背景和无边框文字视觉。
 */
class LibraryTopToolbarTextButton extends StatelessWidget {
  const LibraryTopToolbarTextButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  /** 按钮短文案。 */
  final String label;

  /** 点击动作。 */
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? libraryText
              : libraryTextMuted;
        }),
        overlayColor: WidgetStatePropertyAll(
          appAccentViolet.withValues(alpha: 0.10),
        ),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}
