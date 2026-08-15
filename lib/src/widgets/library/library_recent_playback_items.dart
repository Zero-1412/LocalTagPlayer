import 'package:flutter/material.dart';

import '../../core/playback_settings.dart';
import '../../features/player/domain/player_playback_progress.dart';
import '../../models/video_item.dart';
import '../../services/media/thumbnail_service.dart';
import '../app_theme_tokens.dart';
import 'library_video_results.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

/** 继续观看列表的行展示，保留媒体库统一播放、定位、收藏和删除入口。 */
class RecentPlaybackRow extends StatelessWidget {
  const RecentPlaybackRow({
    required this.item,
    required this.selected,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.onOpen,
    required this.onRevealLocation,
    required this.onToggleFavorite,
    required this.onDeleteVideo,
    required this.onToggleSelected,
    required this.onDelete,
  });

  final VideoItem item;
  final bool selected;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  final VoidCallback onOpen;
  final VoidCallback? onRevealLocation;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDeleteVideo;
  final VoidCallback onToggleSelected;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(value: selected, onChanged: (_) => onToggleSelected()),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: InteractiveVideoListRow(
                  item: item,
                  thumbnailService: thumbnailService,
                  playbackSettings: playbackSettings,
                  onOpen: onOpen,
                  onRevealLocation: onRevealLocation,
                  onToggleFavorite: onToggleFavorite,
                  onDelete: onDeleteVideo,
                ),
              ),
              LinearProgressIndicator(
                value: videoPlaybackProgressFraction(item),
                minHeight: 3,
                color: appAccentViolet,
                backgroundColor: libraryBorder,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '\u5220\u9664\u8be5\u64ad\u653e\u8bb0\u5f55',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}

/** 继续观看网格的卡片展示，进度条和清除记录按钮与行视图保持同一语义。 */
class RecentPlaybackCard extends StatelessWidget {
  const RecentPlaybackCard({
    required this.item,
    required this.selected,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onToggleSelected,
    required this.onDelete,
  });

  final VideoItem item;
  final bool selected;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  final VoidCallback onOpen;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleSelected;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InteractiveVideoCard(
          item: item,
          thumbnailService: thumbnailService,
          playbackSettings: playbackSettings,
          onOpen: onOpen,
          onToggleFavorite: onToggleFavorite,
        ),
        Positioned(
          top: 8,
          left: 48,
          child:
              Checkbox(value: selected, onChanged: (_) => onToggleSelected()),
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 6,
          child: LinearProgressIndicator(
            value: videoPlaybackProgressFraction(item),
            minHeight: 4,
            borderRadius: BorderRadius.circular(99),
            color: appAccentViolet,
            backgroundColor: const Color(0x55000000),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton.filledTonal(
            tooltip: '\u5220\u9664\u8be5\u64ad\u653e\u8bb0\u5f55',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ),
      ],
    );
  }
}
