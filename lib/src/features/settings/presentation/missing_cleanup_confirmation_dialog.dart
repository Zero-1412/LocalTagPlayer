import 'package:flutter/material.dart';

import '../../../widgets/maintenance_feedback.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 展示缺失记录清理的不可逆影响确认。
 *
 * 对话框独立于设置 Route 的 Repository 命令，便于真实窗口视觉门禁复用同一生产内容；
 * 返回 false 或关闭都不得触发数据清理。
 */
Future<bool> showMissingCleanupConfirmationDialog(
  BuildContext context,
) async {
  final confirmed = await showMaintenanceDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('清理缺失或不可读记录？'),
      content: const Text(
        '将重新检查全部媒体。确认缺失或不可读的项目会从数据库永久移除，'
        '同时移除其标签关联、收藏、播放记录、进度和备份快照；磁盘文件不会删除。\n\n'
        '如果移动硬盘暂时断开或目录权限异常，请先取消并恢复连接。',
      ),
      actions: [
        TextButton(
          key: const ValueKey('settings.fileDeletion.cancelCleanup'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('settings.fileDeletion.confirmCleanup'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('确认清理'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
