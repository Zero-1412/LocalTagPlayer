import 'package:flutter/material.dart';

import '../design_system/app_navigation_item.dart';

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
    return AppNavigationItem(
      icon: icon,
      label: tooltip,
      tooltip: tooltip,
      selected: selected,
      onTap: onTap,
      collapsed: true,
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
