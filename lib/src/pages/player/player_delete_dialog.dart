import 'package:flutter/material.dart';

import '../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 展示播放器删除确认弹窗。
 *
 * 返回 `null` 表示取消、`false` 表示仅移出媒体库、`true` 表示同步删除本地文件。
 * 删除真实磁盘文件属于高风险动作，因此默认不勾选并明确提示不可撤销。
 */
Future<bool?> showPlayerDeleteConfirmationDialog(
  BuildContext context,
  VideoItem item,
) async {
  var deleteLocalFile = false;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('删除视频'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                item.path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xff8f99a8)),
              ),
              const SizedBox(height: 12),
              const Text(
                '将移除媒体库记录、标签关系、收藏、播放进度、媒体详情和缩略图缓存。'
                '如果保留本地文件，它在下次扫描时可能重新加入媒体库。',
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: deleteLocalFile,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('同时删除本地视频文件'),
                subtitle: const Text('此操作无法撤销'),
                onChanged: (value) => setDialogState(
                  () => deleteLocalFile = value ?? false,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffc53b4d),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(deleteLocalFile),
            child: Text(deleteLocalFile ? '删除文件和记录' : '仅移出媒体库'),
          ),
        ],
      ),
    ),
  );
}
