import 'package:flutter/material.dart';

import '../../../core/playback_settings.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放与解码页中的原始码流缓存设置。
 *
 * 该开关只影响播放器会话的 demux 内存窗口，不复制媒体文件，也不触发缩略图或
 * 媒体详情缓存任务；因此与解码策略放在同一入口，而不是混入画质增强页面。
 */
class PlaybackStreamCacheCard extends StatelessWidget {
  const PlaybackStreamCacheCard({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  /** 当前播放设置快照。 */
  final PlaybackSettings settings;

  /** 保存更新后的完整设置快照。 */
  final ValueChanged<PlaybackSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('settings.playback.streamCache.card'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SwitchListTile.adaptive(
          key: const ValueKey('settings.playbackQuality.streamCache'),
          contentPadding: EdgeInsets.zero,
          value: settings.highQualityStreamCacheEnabled,
          title: const Text('缓存原始高清码流'),
          subtitle: const Text(
            '为当前会话保留 96 MiB 前向、32 MiB 回看内存窗口；不复制源文件',
          ),
          onChanged: (value) => onChanged(
            settings.copyWith(highQualityStreamCacheEnabled: value),
          ),
        ),
      ),
    );
  }
}
