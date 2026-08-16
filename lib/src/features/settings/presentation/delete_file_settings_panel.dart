import 'package:flutter/material.dart';

import '../../../widgets/app_theme_tokens.dart';
import 'settings_workspace_theme.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 删除文件二级设置页。
 *
 * 确认开关只修改提示行为，不执行删除、扫描或数据库写入；真实删除始终先通过
 * FileSystemAdapter 移入系统回收站，再由页面动作完成稳定身份清理事务。
 */
class DeleteFileSettingsPanel extends StatelessWidget {
  const DeleteFileSettingsPanel({
    super.key,
    required this.confirmBeforeDeletingVideo,
    required this.autoRemoveMissingOrUnreadableVideos,
    required this.onConfirmChanged,
    required this.onAutoRemoveMissingOrUnreadableChanged,
  });

  /** 是否在删除前展示影响范围确认。 */
  final bool confirmBeforeDeletingVideo;

  /** 是否自动清理缺失/不可读视频的数据库记录。 */
  final bool autoRemoveMissingOrUnreadableVideos;

  /** 确认层显示偏好回调。 */
  final ValueChanged<bool> onConfirmChanged;

  /** 清理运行期间为 null，阻止重复触发同一批删除。 */
  final ValueChanged<bool>? onAutoRemoveMissingOrUnreadableChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('settings.fileDeletion.card'),
      container: true,
      label: '文件删除安全工作区',
      child: DecoratedBox(
        key: const ValueKey('settings.fileDeletion.workspaceSurface'),
        decoration: BoxDecoration(
          color: librarySurface,
          borderRadius: BorderRadius.circular(AppRadius.panel),
          border: const Border.fromBorderSide(BorderSide(color: libraryBorder)),
        ),
        // 让开关和规则 ListTile 继续拥有可见的 ink/focus 状态，不改变交互反馈。
        child: Material(
          type: MaterialType.transparency,
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
                  subtitle: const Text('显示删除影响范围；视频文件始终移入系统回收站'),
                  onChanged: onConfirmChanged,
                ),
                const Divider(height: 20),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_sweep_outlined),
                  title: Text('视频文件删除规则：始终移入系统回收站'),
                  subtitle: Text('可从回收站恢复；缺失或不可读记录的自动清理只移除数据库记录，不操作磁盘文件。'),
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
                            child: const Text(
                              '后续删除将不再提示，但仍会先把本地视频移入系统回收站，再移除媒体库记录。',
                              style: TextStyle(height: 1.45),
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
        ),
      ),
    );
  }
}

/** 构建删除文件设置的 focused test 容器，不触发真实删除或文件系统调用。 */
@visibleForTesting
Widget deleteFileSettingsSmokeHarness({
  bool confirmBeforeDeletingVideo = true,
  bool autoRemoveMissingOrUnreadableVideos = true,
  TextScaler textScaler = TextScaler.noScaling,
  ValueChanged<bool>? onConfirmChanged,
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
            autoRemoveMissingOrUnreadableVideos:
                autoRemoveMissingOrUnreadableVideos,
            onConfirmChanged: onConfirmChanged ?? (_) {},
            onAutoRemoveMissingOrUnreadableChanged:
                onAutoRemoveMissingOrUnreadableChanged ?? (_) {},
          ),
        ),
      ),
    ),
  );
}
