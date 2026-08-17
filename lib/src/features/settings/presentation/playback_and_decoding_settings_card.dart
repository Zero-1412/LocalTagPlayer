import 'package:flutter/material.dart';

import '../../../core/playback_settings.dart';
import '../../../widgets/app_theme_tokens.dart';
import 'playback_backend_dropdowns.dart';

// ignore_for_file: slash_for_doc_comments

/** 播放与解码工作区；确认、持久化和 section 生命周期仍由 `CacheSettingsPage` 拥有。 */
class PlaybackAndDecodingSettingsCard extends StatelessWidget {
  const PlaybackAndDecodingSettingsCard({
    super.key,
    required this.settings,
    required this.onChanged,
  });
  /** 当前设置快照。 */
  final PlaybackSettings settings;
  /** 提交用户确认后的完整设置快照。 */
  final Future<void> Function(PlaybackSettings settings) onChanged;
  static const _headingStyle =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w800);
  static const _mutedStyle = TextStyle(color: libraryTextMuted);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('settings.playback.card'),
      container: true,
      label: '播放与解码工作区',
      child: Material(
        key: const ValueKey('settings.playback.workspaceSurface'),
        color: librarySurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.panel)),
          side: BorderSide(color: libraryBorder),
        ),
        // 保留 Material 状态层，让下拉、展开项和播放后端说明继续提供 focus/ink 反馈。
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('继续观看', style: _headingStyle),
              const SizedBox(height: 6),
              const Text(
                '打开有未完成进度的视频时，默认执行以下操作。',
                style: _mutedStyle,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<PlaybackResumeBehavior>(
                key: const ValueKey('settings.resumeBehavior'),
                initialValue: settings.resumeBehavior,
                decoration: const InputDecoration(labelText: '默认打开行为'),
                items: [
                  for (final behavior in PlaybackResumeBehavior.values)
                    DropdownMenuItem(
                      value: behavior,
                      child: Text(PlaybackSettings.resumeLabelFor(behavior)),
                    ),
                ],
                onChanged: (behavior) async {
                  if (behavior != null) {
                    await onChanged(
                        settings.copyWith(resumeBehavior: behavior));
                  }
                },
              ),
              const SizedBox(height: 22),
              const Divider(height: 1),
              const SizedBox(height: 20),
              const Text('播放后端', style: _headingStyle),
              const SizedBox(height: 6),
              const Text(
                '正式播放统一使用 MediaKit Texture；高级画质由同一个 libmpv 实例按能力应用。',
                style: _mutedStyle,
              ),
              const SizedBox(height: 14),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.video_settings_outlined),
                title: Text('MediaKit Texture'),
                subtitle: Text(
                  '生命周期、事件和 Flutter Texture 由 MediaKit 管理；不会自动激活 NVIDIA VSR/HDR',
                ),
              ),
              const SizedBox(height: 22),
              const Divider(height: 1),
              const SizedBox(height: 20),
              const Text('播放解码', style: _headingStyle),
              const SizedBox(height: 14),
              PlaybackDecoderDropdown(settings: settings, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
