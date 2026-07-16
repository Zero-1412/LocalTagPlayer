import 'package:flutter/material.dart';

import '../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 展示播放器删除确认弹窗。
 *
 * 返回 `null` 表示取消、`false` 表示仅移出媒体库、`true` 表示把本地文件移入回收站。
 * 文件操作默认不勾选，且不能静默降级为绕过回收站的永久删除。
 */
Future<bool?> showPlayerDeleteConfirmationDialog(
  BuildContext context,
  VideoItem item,
) async {
  var moveLocalFileToTrash = false;
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
                value: moveLocalFileToTrash,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('同时将本地视频移入回收站'),
                subtitle: const Text('可在 Windows 回收站中恢复'),
                onChanged: (value) => setDialogState(
                  () => moveLocalFileToTrash = value ?? false,
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
            onPressed: () =>
                Navigator.of(dialogContext).pop(moveLocalFileToTrash),
            child: Text(
              moveLocalFileToTrash ? '移入回收站并移除记录' : '仅移出媒体库',
            ),
          ),
        ],
      ),
    ),
  );
}
