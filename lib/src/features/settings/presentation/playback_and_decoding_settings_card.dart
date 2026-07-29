import 'package:flutter/material.dart';

import '../../../core/playback_settings.dart';
import '../../../widgets/app_theme_tokens.dart';
import 'playback_backend_dropdowns.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放与解码二级页的主设置卡。
 *
 * 组件只展示不可变 [PlaybackSettings] 快照并把完整的新快照交还页面；确认、持久化、
 * 失败补偿和设置 section 生命周期继续由 `CacheSettingsPage` 的 controller 统一拥有。
 */
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

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '继续观看',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              '打开有未完成进度的视频时，默认执行以下操作。',
              style: TextStyle(color: libraryTextMuted),
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
                if (behavior == null) {
                  return;
                }
                await onChanged(settings.copyWith(resumeBehavior: behavior));
              },
            ),
            const SizedBox(height: 22),
            const Divider(height: 1),
            const SizedBox(height: 20),
            const Text(
              '播放渲染器',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              '两种配置共用 MediaKit Texture；增强配置开放同实例 libmpv 画质能力。',
              style: TextStyle(color: libraryTextMuted),
            ),
            const SizedBox(height: 14),
            PlaybackRendererDropdown(
              settings: settings,
              onChanged: onChanged,
            ),
            const SizedBox(height: 22),
            const Divider(height: 1),
            const SizedBox(height: 20),
            const Text(
              '播放解码',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            PlaybackDecoderDropdown(
              settings: settings,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
