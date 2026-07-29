import 'package:flutter/material.dart';

import '../../../widgets/app_theme_tokens.dart';
import 'settings_workspace_theme.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 删除文件二级设置页。
 *
 * 两个开关只修改确认与回收站偏好，不执行删除、扫描或数据库写入；真实删除仍由
 * 页面动作、稳定身份清理事务和 FileSystemAdapter 共同完成。
 */
class DeleteFileSettingsPanel extends StatelessWidget {
  const DeleteFileSettingsPanel({
    super.key,
    required this.confirmBeforeDeletingVideo,
    required this.moveDeletedFileToTrash,
    required this.autoRemoveMissingOrUnreadableVideos,
    required this.onConfirmChanged,
    required this.onMoveToTrashChanged,
    required this.onAutoRemoveMissingOrUnreadableChanged,
  });

  /** 是否在删除前展示影响范围确认。 */
  final bool confirmBeforeDeletingVideo;

  /** 是否在删除记录前把本地文件移入回收站。 */
  final bool moveDeletedFileToTrash;
  /** 是否自动清理缺失/不可读视频的数据库记录。 */
  final bool autoRemoveMissingOrUnreadableVideos;

  /** 确认层显示偏好回调。 */
  final ValueChanged<bool> onConfirmChanged;

  /** 回收站默认行为回调。 */
  final ValueChanged<bool> onMoveToTrashChanged;
  /** 清理运行期间为 null，阻止重复触发同一批删除。 */
  final ValueChanged<bool>? onAutoRemoveMissingOrUnreadableChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('settings.fileDeletion.card'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '删除文件',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              '统一控制媒体卡片、批量选择和播放器队列中的删除动作。',
              style: TextStyle(color: libraryTextMuted, height: 1.45),
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              key: const ValueKey(
                'settings.fileDeletion.autoRemoveMissingOrUnreadable',
              ),
              contentPadding: EdgeInsets.zero,
              value: autoRemoveMissingOrUnreadableVideos,
              title: const Text('自动移除路径失效或不可读视频'),
              subtitle: const Text(
                '默认开启；路径不存在时直接清理数据库记录，不删除磁盘文件或文件夹',
              ),
              onChanged: onAutoRemoveMissingOrUnreadableChanged,
            ),
            const Divider(height: 20),
            SwitchListTile.adaptive(
              key: const ValueKey('settings.fileDeletion.confirm'),
              contentPadding: EdgeInsets.zero,
              value: confirmBeforeDeletingVideo,
              title: const Text('删除前显示提示框'),
              subtitle: const Text('显示删除影响范围，并允许本次临时修改回收站选择'),
              onChanged: onConfirmChanged,
            ),
            const Divider(height: 20),
            SwitchListTile.adaptive(
              key: const ValueKey('settings.fileDeletion.moveToTrash'),
              contentPadding: EdgeInsets.zero,
              value: moveDeletedFileToTrash,
              title: const Text('同步将本地文件移入回收站'),
              subtitle: const Text('关闭时只移除媒体库记录，本地文件可能在下次扫描时重新加入'),
              onChanged: onMoveToTrashChanged,
            ),
            if (!confirmBeforeDeletingVideo) ...[
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: playerDanger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(
                    color: playerDanger.withValues(alpha: 0.34),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: playerDanger,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          moveDeletedFileToTrash
                              ? '后续删除将不再提示，直接把本地文件移入回收站并移除媒体库记录。'
                              : '后续删除将不再提示，直接移除媒体库记录；本地文件会保留。',
                          style: const TextStyle(height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/** 构建删除文件设置的 focused test 容器，不触发真实删除或文件系统调用。 */
@visibleForTesting
Widget deleteFileSettingsSmokeHarness({
  bool confirmBeforeDeletingVideo = true,
  bool moveDeletedFileToTrash = false,
  bool autoRemoveMissingOrUnreadableVideos = true,
  TextScaler textScaler = TextScaler.noScaling,
  ValueChanged<bool>? onConfirmChanged,
  ValueChanged<bool>? onMoveToTrashChanged,
  ValueChanged<bool>? onAutoRemoveMissingOrUnreadableChanged,
}) {
  return MaterialApp(
    theme: settingsWorkspaceTheme(ThemeData(useMaterial3: true)),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(900, 720),
        textScaler: textScaler,
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: DeleteFileSettingsPanel(
            confirmBeforeDeletingVideo: confirmBeforeDeletingVideo,
            moveDeletedFileToTrash: moveDeletedFileToTrash,
            autoRemoveMissingOrUnreadableVideos:
                autoRemoveMissingOrUnreadableVideos,
            onConfirmChanged: onConfirmChanged ?? (_) {},
            onMoveToTrashChanged: onMoveToTrashChanged ?? (_) {},
            onAutoRemoveMissingOrUnreadableChanged:
                onAutoRemoveMissingOrUnreadableChanged ?? (_) {},
          ),
        ),
      ),
    ),
  );
}
