import 'package:flutter/material.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 标签管理工作区的标题栏。
 *
 * 组件只转发刷新与新建意图；标签创建命令及页面状态仍由 [TagManagerPage] 的 State
 * owner 执行。
 */
class TagManagerWorkspaceAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const TagManagerWorkspaceAppBar({
    super.key,
    required this.compact,
    required this.onRefresh,
    required this.onCreate,
  });

  /** 是否使用只显示图标的紧凑动作。 */
  final bool compact;

  /** 请求页面重新读取标签用量。 */
  final VoidCallback onRefresh;

  /** 请求页面打开手动标签创建流程。 */
  final VoidCallback onCreate;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('标签管理'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
        if (compact)
          IconButton(
            tooltip: '新建标签',
            onPressed: onCreate,
            icon: const Icon(Icons.add),
          )
        else
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('新建标签'),
          ),
        const SizedBox(width: 12),
      ],
    );
  }
}
