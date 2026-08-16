import 'package:flutter/material.dart';

import '../maintenance_feedback.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 二次确认清空全部继续观看进度。
 *
 * 文案明确只清进度、不删除视频，并提示撤销窗口；对话框不执行数据命令。
 */
Future<bool?> showClearAllRecentPlaybackConfirmation(
  BuildContext context, {
  required int count,
}) {
  return showMaintenanceDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('清空全部观看进度？'),
      content: Text(
        '将清除 $count 条继续观看进度，不会删除视频文件、标签或收藏。'
        '清除后可在 10 秒内撤销。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('只清除进度'),
        ),
      ],
    ),
  );
}

/**
 * 确认解除本地媒体库根目录管理。
 *
 * [root] 只用于展示影响范围；实际移除与数据保留策略仍由页面命令 owner 执行。
 */
Future<bool?> showRemoveLibraryRootConfirmation(
  BuildContext context, {
  required String root,
}) {
  return showMaintenanceDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('解除目录管理'),
      content: Text(
        '目录中的视频会从当前媒体库与播放队列隐藏，但不会删除本地文件。\n\n'
        '标签关系、收藏、播放进度、媒体详情和稳定视频身份都会保留；'
        '以后重新添加同一目录或匹配到相同文件时会自动恢复。\n\n$root',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xffb84d5f),
          ),
          child: const Text('解除管理'),
        ),
      ],
    ),
  );
}
