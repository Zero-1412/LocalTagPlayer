import 'package:flutter/material.dart';

import '../../core/playback_settings.dart';
import '../../models/video_item.dart';
import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 删除确认层返回的唯一可选偏好；视频文件动作本身固定进入回收站。 */
class VideoDeleteDecision {
  const VideoDeleteDecision({required this.dontAskAgain});

  /** 是否保存当前选择并在后续删除中跳过确认层。 */
  final bool dontAskAgain;
}

/**
 * 提示关闭时生成可直接执行的最终决定；提示开启时返回 null 交给调用方展示弹窗。
 */
VideoDeleteDecision? videoDeleteDecisionWithoutPrompt(
  PlaybackSettings settings,
) {
  if (settings.confirmBeforeDeletingVideo) {
    return null;
  }
  return VideoDeleteDecision(
    dontAskAgain: true,
  );
}

/**
 * 展示单视频删除确认弹窗。
 *
 * 返回 null 表示取消；确认后返回“不再提示”选择。用户视频文件始终先移入系统回收站，
 * 不能静默降级为保留原文件或永久删除。
 */
Future<VideoDeleteDecision?> showPlayerDeleteConfirmationDialog(
  BuildContext context,
  VideoItem item, {
  VideoItem? mergeInto,
}) {
  return _showVideoDeleteConfirmationDialog(
    context,
    title: '删除视频',
    subjectTitle: item.title,
    subjectPath: item.path,
    impactText: mergeInto == null
        ? '将本地视频移入系统回收站，并移除媒体库记录、标签关系、收藏、播放进度、'
            '媒体详情和缩略图缓存。文件可从回收站恢复。'
        : '会先把收藏和自定义标签合并到“${mergeInto.title}”，再将本地视频移入系统回收站，'
            '并移除源视频的媒体库记录、标签关系、播放进度、媒体详情和缩略图缓存。',
  );
}

/** 批量删除使用与单条删除相同的偏好和危险动作语义。 */
Future<VideoDeleteDecision?> showBatchVideoDeleteConfirmationDialog(
  BuildContext context, {
  required int count,
}) {
  return _showVideoDeleteConfirmationDialog(
    context,
    title: '删除 $count 个视频',
    impactText: '将所选本地视频移入系统回收站，并删除数据库记录、标签关系、收藏、播放进度、'
        '媒体详情和缩略图缓存。文件可从回收站恢复。',
  );
}

/** 构建单条与批量删除共享的确认层，保证所有视频删除都进入回收站。 */
Future<VideoDeleteDecision?> _showVideoDeleteConfirmationDialog(
  BuildContext context, {
  required String title,
  required String impactText,
  String? subjectTitle,
  String? subjectPath,
}) async {
  var dontAskAgain = false;
  return showDialog<VideoDeleteDecision>(
    context: context,
    builder: (dialogContext) => Theme(
      // DialogRoute 位于页面局部 Theme 之外，必须显式继承维护页深色浮层语义。
      data: maintenanceWorkspaceTheme(Theme.of(dialogContext)),
      child: StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (subjectTitle != null) ...[
                  Text(
                    subjectTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                ],
                if (subjectPath != null) ...[
                  Text(
                    subjectPath,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: playerTextMuted),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(impactText),
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const ValueKey('deleteDialog.dontAskAgain'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: dontAskAgain,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('不再提示'),
                  subtitle: const Text('以后按本次选择直接执行，可在设置中重新开启提示'),
                  onChanged: (value) => setDialogState(
                    () => dontAskAgain = value ?? false,
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
              style: FilledButton.styleFrom(backgroundColor: playerDanger),
              onPressed: () => Navigator.of(dialogContext).pop(
                VideoDeleteDecision(
                  dontAskAgain: dontAskAgain,
                ),
              ),
              child: const Text('移入回收站并移除记录'),
            ),
          ],
        ),
      ),
    ),
  );
}
