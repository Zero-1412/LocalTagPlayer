import 'package:flutter/material.dart';

import '../core/layout_size.dart';
import 'app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 维护页面共享的两级上下文标题栏。
 *
 * 标题栏只负责返回、当前维护领域和一个页面级主要动作；数据状态、确认弹窗和
 * 业务回调仍由具体 Route 持有，避免共享组件越过页面 owner 边界。
 */
class MaintenanceWorkspaceAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const MaintenanceWorkspaceAppBar({
    super.key,
    required this.title,
    required this.onBack,
    required this.actionIcon,
    required this.actionLabel,
    required this.actionTooltip,
    required this.actionKey,
    this.onAction,
  });

  /** 当前维护页面标题。 */
  final String title;

  /** 返回来源页面的导航意图。 */
  final VoidCallback onBack;

  /** 页面主要动作的图标和文字。 */
  final IconData actionIcon;
  final String actionLabel;
  final String actionTooltip;
  final Key actionKey;

  /** 页面主要动作；为空时保持禁用状态。 */
  final VoidCallback? onAction;

  @override
  Size get preferredSize => const Size.fromHeight(77);

  @override
  Widget build(BuildContext context) {
    final compact = LayoutBreakpoints.fromWidth(
          MediaQuery.sizeOf(context).width,
        ) ==
        LayoutSize.compact;
    return AppBar(
      toolbarHeight: compact ? 64 : 76,
      titleSpacing: 0,
      leading: IconButton(
        key: const ValueKey('maintenance.workspace.back'),
        tooltip: '返回媒体库',
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '维护工作区',
            style: TextStyle(
              color: libraryTextMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: const TextStyle(
              color: libraryText,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      actions: [
        if (compact)
          IconButton(
            key: actionKey,
            tooltip: actionTooltip,
            onPressed: onAction,
            icon: Icon(actionIcon),
          )
        else
          OutlinedButton.icon(
            key: actionKey,
            onPressed: onAction,
            icon: Icon(actionIcon, size: 18),
            label: Text(actionLabel),
          ),
        SizedBox(width: compact ? 8 : 20),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: libraryBorder),
      ),
    );
  }
}
