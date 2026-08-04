import 'package:flutter/material.dart';

import '../../models/player_media_controls.dart';

// ignore_for_file: slash_for_doc_comments

/** 媒体控制面板的可复用展示叶子；不持有播放器、路由或队列状态。 */
class PlayerMediaControlSection extends StatelessWidget {
  const PlayerMediaControlSection({
    super.key,
    required this.title,
    required this.icon,
    required this.emptyLabel,
    required this.children,
  });

  final String title;
  final IconData icon;
  final String emptyLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(dense: true, leading: Icon(icon), title: Text(title)),
              if (children.isEmpty && emptyLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(emptyLabel),
                )
              else
                ...children,
            ],
          ),
        ),
      );
}

/** 固定步长的音频或字幕延迟控制行。 */
class PlayerMediaDelayControlRow extends StatelessWidget {
  const PlayerMediaDelayControlRow({
    super.key,
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final String value;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) => ListTile(
        key: key,
        dense: true,
        title: Text(label),
        subtitle: Text(value),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '减少 0.1 秒',
              icon: const Icon(Icons.remove_rounded),
              onPressed: onDecrease,
            ),
            IconButton(
              tooltip: '增加 0.1 秒',
              icon: const Icon(Icons.add_rounded),
              onPressed: onIncrease,
            ),
          ],
        ),
      );
}

/** 章节位置使用本地播放器一致的时分秒格式。 */
String formatPlayerMediaChapterPosition(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/** 轨道副标题只展示可安全公开的语言、编码和默认标记。 */
Widget? playerMediaTrackSubtitle(PlayerMediaTrack track) {
  final details = <String>[
    if (track.language != null && track.language!.isNotEmpty) track.language!,
    if (track.codec != null && track.codec!.isNotEmpty) track.codec!,
    if (track.isDefault) '默认',
  ];
  return details.isEmpty ? null : Text(details.join(' · '));
}

/** 轨道选择项使用普通 ListTile，避免已弃用的 RadioListTile 状态 API。 */
Widget buildPlayerMediaTrackTile({
  required PlayerMediaTrack track,
  required String fallback,
  required VoidCallback onTap,
}) =>
    ListTile(
      dense: true,
      selected: track.selected,
      leading: Icon(
        track.selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
      ),
      title: Text(track.label(fallback)),
      subtitle: playerMediaTrackSubtitle(track),
      onTap: onTap,
    );
