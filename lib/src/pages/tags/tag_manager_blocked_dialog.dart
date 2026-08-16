import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';
import '../../widgets/maintenance_feedback.dart';

// ignore_for_file: slash_for_doc_comments

/** 标签高风险入口的只读反馈层，不提供任何提交或删除动作。 */
class BlockedTagOperationDialog extends StatelessWidget {
  const BlockedTagOperationDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  /** 当前检查的高风险动作图标。 */
  final IconData icon;

  /** 明确说明动作未启用的标题。 */
  final String title;

  /** 引用数量、来源边界和未执行结果说明。 */
  final String message;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('tagManager.blockedOperation.dialog'),
      scrollable: true,
      title: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(title)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Text(message, style: const TextStyle(height: 1.5)),
      ),
      actions: [
        TextButton(
          key: const ValueKey('tagManager.blockedOperation.close'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('返回标签详情'),
        ),
      ],
    );
  }
}

/** 构建标签高风险反馈的 focused test 容器，不连接 Store 或执行数据操作。 */
@visibleForTesting
Widget tagManagerBlockedOperationSmokeHarness({
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    theme: maintenanceWorkspaceTheme(ThemeData(useMaterial3: true)),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(720, 600),
        textScaler: textScaler,
      ),
      child: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showMaintenanceDialog<void>(
                context: context,
                builder: (_) => const BlockedTagOperationDialog(
                  icon: Icons.delete_outline_rounded,
                  title: '暂不能删除此标签',
                  message: '“示例标签”当前有 12 条引用。本次未删除标签或任何视频关联。',
                ),
              ),
              child: const Text('检查删除影响'),
            ),
          ),
        ),
      ),
    ),
  );
}
