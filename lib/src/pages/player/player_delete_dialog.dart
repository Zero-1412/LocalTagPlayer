import 'package:flutter/material.dart';

import '../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 展示播放器删除文件确认弹窗。
 *
 * 删除真实磁盘文件属于高风险动作，确认 UI 单独放在这里，便于后续扩展路径、大小、
 * 删除后队列影响等提示，而不继续膨胀 `PlayerPage`。
 */
Future<bool> showPlayerDeleteConfirmationDialog(
  BuildContext context,
  VideoItem item,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除视频文件'),
      content: Text('${item.title}\n\n${item.path}'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
