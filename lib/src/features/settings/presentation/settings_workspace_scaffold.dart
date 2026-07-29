import 'package:flutter/material.dart';

import '../../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 设置首页与二级页共享的 Route 展示外壳。
 *
 * 组件只消费当前层级快照和导航回调；具体 section 状态、设置 controller、持久化及
 * 业务命令继续由 `CacheSettingsPage` 唯一拥有。
 */
class SettingsWorkspaceScaffold extends StatelessWidget {
  const SettingsWorkspaceScaffold({
    super.key,
    required this.isHome,
    required this.title,
    required this.showRefreshAction,
    required this.onBack,
    required this.onRefresh,
    required this.child,
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

  /** 页面 owner 已按当前 section 构建的内容。 */
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: isHome,
      onPopInvokedWithResult: (didPop, result) {
        // 二级页拦截系统返回并只发出返回首页意图，不直接退出整个设置 Route。
        if (!didPop && !isHome) {
          onBack();
        }
      },
      child: Scaffold(
        backgroundColor: libraryBackground,
        appBar: AppBar(
          leading: isHome
              ? null
              : BackButton(
                  key: const ValueKey('settings.section.back'),
                  onPressed: onBack,
                ),
          title: Text(title),
          actions: [
            if (showRefreshAction)
              TextButton.icon(
                key: const ValueKey('settings.refreshCacheStats'),
                style: TextButton.styleFrom(foregroundColor: libraryText),
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('刷新统计'),
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isHome ? 760 : 920),
            child: child,
          ),
        ),
      ),
    );
  }
}
