import 'package:flutter/material.dart';

import '../../../core/playback_settings.dart';
import '../../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 播放会话缓存工作区；只影响 demux 内存窗口，不复制媒体或启动缩略图任务。 */
class PlaybackStreamCacheCard extends StatelessWidget {
  const PlaybackStreamCacheCard(
      {super.key, required this.settings, required this.onChanged});

  final PlaybackSettings settings;
  final ValueChanged<PlaybackSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('settings.playback.streamCache.card'),
      container: true,
      label: '播放会话缓存工作区',
      child: Material(
        key: const ValueKey('settings.playback.streamCache.workspaceSurface'),
        color: librarySurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.panel)),
          side: BorderSide(color: libraryBorder),
        ),
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
      ),
    );
  }
}
