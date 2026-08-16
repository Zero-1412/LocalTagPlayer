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
    this.secondaryActionIcon,
    this.secondaryActionLabel,
    this.secondaryActionTooltip,
    this.secondaryActionKey,
    this.onSecondaryAction,
    this.actionEmphasized = false,
    this.secondaryActionEmphasized = false,
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

  /** 可选的次要动作，通常用于添加、打开或辅助维护入口。 */
  final IconData? secondaryActionIcon;
  final String? secondaryActionLabel;
  final String? secondaryActionTooltip;
  final Key? secondaryActionKey;
  final VoidCallback? onSecondaryAction;

  /** 主要动作是否使用更高对比度的实色层级。 */
  final bool actionEmphasized;

  /** 次要动作是否使用更高对比度的实色层级。 */
  final bool secondaryActionEmphasized;

  @override
  Size get preferredSize => const Size.fromHeight(77);

  @override
  Widget build(BuildContext context) {
    final compact = LayoutBreakpoints.fromWidth(
          MediaQuery.sizeOf(context).width,
        ) ==
        LayoutSize.compact;
    final secondaryAction = _buildAction(
      compact: compact,
      icon: secondaryActionIcon,
      label: secondaryActionLabel,
      tooltip: secondaryActionTooltip,
      key: secondaryActionKey,
      onPressed: onSecondaryAction,
      emphasized: secondaryActionEmphasized,
    );
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
        if (secondaryAction != null) secondaryAction,
        _buildAction(
          compact: compact,
          icon: actionIcon,
          label: actionLabel,
          tooltip: actionTooltip,
          key: actionKey,
          onPressed: onAction,
          emphasized: actionEmphasized,
        )!,
        SizedBox(width: compact ? 8 : 20),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: libraryBorder),
      ),
    );
  }

  /** 按窗口密度构建同一动作的文字或图标形态，保留稳定 key 与 tooltip。 */
  Widget? _buildAction({
    required bool compact,
    required IconData? icon,
    required String? label,
    required String? tooltip,
    required Key? key,
    required VoidCallback? onPressed,
    required bool emphasized,
  }) {
    if (icon == null || label == null || tooltip == null || key == null) {
      return null;
    }
    if (compact) {
      return emphasized
          ? IconButton.filled(
              key: key,
              tooltip: tooltip,
              onPressed: onPressed,
              icon: Icon(icon),
            )
          : IconButton(
              key: key,
              tooltip: tooltip,
              onPressed: onPressed,
              icon: Icon(icon),
            );
    }
    return emphasized
        ? FilledButton.icon(
            key: key,
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
          )
        : OutlinedButton.icon(
            key: key,
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
  }
}
