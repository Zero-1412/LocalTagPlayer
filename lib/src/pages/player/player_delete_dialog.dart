import 'package:flutter/material.dart';

import '../../core/playback_settings.dart';
import '../../models/video_item.dart';
import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 删除确认层返回的完整偏好，不把“不再提示”混入文件操作布尔值。 */
class VideoDeleteDecision {
  const VideoDeleteDecision({
    required this.moveLocalFileToTrash,
    required this.dontAskAgain,
  });

  /** 是否先把本地媒体文件移入系统回收站。 */
  final bool moveLocalFileToTrash;

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
    moveLocalFileToTrash: settings.moveDeletedFileToTrash,
    dontAskAgain: true,
  );
}

/**
 * 展示单视频删除确认弹窗。
 *
 * 返回 null 表示取消；确认后同时返回回收站选择与“不再提示”选择。文件操作不能
 * 静默降级为绕过回收站的永久删除，调用方仍必须经过 FileSystemAdapter。
 */
Future<VideoDeleteDecision?> showPlayerDeleteConfirmationDialog(
  BuildContext context,
  VideoItem item, {
  bool initialMoveLocalFileToTrash = false,
}) {
  return _showVideoDeleteConfirmationDialog(
    context,
    title: '删除视频',
    subjectTitle: item.title,
    subjectPath: item.path,
    impactText: '将移除媒体库记录、标签关系、收藏、播放进度、媒体详情和缩略图缓存。'
        '如果保留本地文件，它在下次扫描时可能重新加入媒体库。',
    recycleTitle: '同时将本地视频移入回收站',
    initialMoveLocalFileToTrash: initialMoveLocalFileToTrash,
  );
}

/** 批量删除使用与单条删除相同的偏好和危险动作语义。 */
Future<VideoDeleteDecision?> showBatchVideoDeleteConfirmationDialog(
  BuildContext context, {
  required int count,
  bool initialMoveLocalFilesToTrash = false,
}) {
  return _showVideoDeleteConfirmationDialog(
    context,
    title: '删除 $count 个视频',
    impactText: '将删除所选视频的数据库记录、标签关系、收藏、播放进度、媒体详情和缩略图缓存。'
        '如果保留本地文件，它们在下次扫描时可能重新加入媒体库。',
    recycleTitle: '同时将所选本地视频移入回收站',
    initialMoveLocalFileToTrash: initialMoveLocalFilesToTrash,
  );
}

/** 构建单条与批量删除共享的确认层，保证两个入口记忆同一组设置。 */
Future<VideoDeleteDecision?> _showVideoDeleteConfirmationDialog(
  BuildContext context, {
  required String title,
  required String impactText,
  required String recycleTitle,
  required bool initialMoveLocalFileToTrash,
  String? subjectTitle,
  String? subjectPath,
}) async {
  var moveLocalFileToTrash = initialMoveLocalFileToTrash;
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
                Material(
                  color: playerSurfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  clipBehavior: Clip.antiAlias,
                  child: CheckboxListTile(
                    key: const ValueKey('deleteDialog.moveToTrash'),
                    value: moveLocalFileToTrash,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(recycleTitle),
                    subtitle: const Text('可在 Windows 回收站中恢复'),
                    onChanged: (value) => setDialogState(
                      () => moveLocalFileToTrash = value ?? false,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
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
                  moveLocalFileToTrash: moveLocalFileToTrash,
                  dontAskAgain: dontAskAgain,
                ),
              ),
              child: Text(
                moveLocalFileToTrash ? '移入回收站并移除记录' : '仅移出媒体库',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
