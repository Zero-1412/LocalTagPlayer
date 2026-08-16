import 'package:flutter/material.dart';

import '../../../core/layout_size.dart';
import '../../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 设置工作区的两级标题栏。
 *
 * 标题栏只负责层级、返回和只读统计刷新入口；设置 section 的状态与命令仍由页面
 * owner 管理，避免视觉外壳重新建立一份设置状态。
 */
class SettingsWorkspaceAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const SettingsWorkspaceAppBar({
    super.key,
    required this.isHome,
    required this.title,
    required this.showRefreshAction,
    required this.onBack,
    required this.onRefresh,
  });

  /** 当前是否停留在设置功能列表。 */
  final bool isHome;

  /** 当前设置层级标题。 */
  final String title;

  /** 是否展示缓存统计刷新入口。 */
  final bool showRefreshAction;

  /** 二级页返回设置首页的意图回调。 */
  final VoidCallback onBack;

  /** 刷新当前只读统计快照的意图回调。 */
  final VoidCallback onRefresh;

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
      leading: isHome
          ? null
          : BackButton(
              key: const ValueKey('settings.section.back'),
              onPressed: onBack,
            ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isHome ? '维护工作区' : '设置',
            style: const TextStyle(
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
        if (showRefreshAction)
          if (compact)
            IconButton(
              key: const ValueKey('settings.refreshCacheStats'),
              tooltip: '刷新统计',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            )
          else
            TextButton.icon(
              key: const ValueKey('settings.refreshCacheStats'),
              style: TextButton.styleFrom(foregroundColor: libraryText),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新统计'),
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
