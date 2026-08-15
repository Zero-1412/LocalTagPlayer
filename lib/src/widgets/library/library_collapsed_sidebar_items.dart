import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 图标折叠态的单个入口；选中态仅用背景和强调色表达。 */
class CollapsedSidebarItem extends StatelessWidget {
  const CollapsedSidebarItem({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: onTap != null,
          selected: selected,
          label: tooltip,
          child: Material(
            color: selected ? const Color(0xff2b3650) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: SizedBox.square(
                dimension: 46,
                child: Icon(
                  icon,
                  size: 21,
                  color: selected
                      ? appAccentViolet
                      : onTap == null
                          ? const Color(0xff526077)
                          : const Color(0xffa7b4c6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/** 折叠导航的轻量分组线。 */
class CollapsedSidebarDivider extends StatelessWidget {
  const CollapsedSidebarDivider({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Divider(height: 1, color: Color(0xff2a3548)),
      );
}
