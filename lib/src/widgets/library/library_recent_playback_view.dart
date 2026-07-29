import 'package:flutter/material.dart';

import '../../core/layout_size.dart';
import '../../core/playback_settings.dart';
import '../../models/video_item.dart';
import '../../features/player/domain/player_playback_progress.dart';
import '../../services/media/thumbnail_service.dart';
import '../app_theme_tokens.dart';
import 'library_video_results.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

/**
 * 继续观看结果视图。
 *
 * 这里的删除只清理播放记录，不删除视频文件；stable videoId 选择状态由 LibraryPage 保存，
 * 避免滚动重建时丢失用户正在批量清理的选择。
 */
class RecentPlaybackView extends StatelessWidget {
  const RecentPlaybackView({
    required this.videos,
    required this.selectedVideoIds,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.dense,
    required this.onOpen,
    this.onRevealLocation,
    required this.onToggleFavorite,
    required this.onDeleteVideo,
    required this.onToggleSelected,
    required this.onSelectAll,
    required this.onClearSelection,
    required this.onDeleteOne,
    required this.onDeleteSelected,
    required this.onDeleteAll,
  });

  final List<VideoItem> videos;
  /** 临时选择只绑定 stable videoId，不随 mutable path 变化。 */
  final Set<String> selectedVideoIds;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  final bool dense;
  final void Function(VideoItem item, List<VideoItem> playlist) onOpen;
  /** 在文件管理器中定位当前继续观看条目的视频文件。 */
  final ValueChanged<VideoItem>? onRevealLocation;
  final ValueChanged<VideoItem> onToggleFavorite;
  /** 卡片更多菜单的完整视频删除动作，与“清除播放记录”保持语义隔离。 */
  final ValueChanged<VideoItem> onDeleteVideo;
  final ValueChanged<VideoItem> onToggleSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final ValueChanged<VideoItem> onDeleteOne;
  final VoidCallback onDeleteSelected;
  final VoidCallback onDeleteAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
          child: Row(
            children: [
              Text(
                '\u5df2\u9009 ${selectedVideoIds.length} / ${videos.length}',
                style: const TextStyle(
                  color: libraryTextMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: selectedVideoIds.length == videos.length
                    ? onClearSelection
                    : onSelectAll,
                child: Text(selectedVideoIds.length == videos.length
                    ? '\u53d6\u6d88\u5168\u9009'
                    : '\u5168\u9009'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: selectedVideoIds.isEmpty ? null : onDeleteSelected,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('\u5220\u9664\u5df2\u9009'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: videos.isEmpty ? null : onDeleteAll,
                icon: const Icon(Icons.clear_all_rounded, size: 18),
                label: const Text('\u6e05\u7a7a\u5168\u90e8'),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < LayoutBreakpoints.compactMaxWidth;
              final narrow = constraints.maxWidth < 560;
              if (dense) {
                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 14 : 22,
                    2,
                    compact ? 14 : 22,
                    22,
                  ),
                  itemExtent: narrow ? 138 : 126,
                  itemCount: videos.length,
                  itemBuilder: (context, index) {
                    final item = videos[index];
                    return _RecentPlaybackRow(
                      item: item,
                      selected: selectedVideoIds.contains(item.videoId),
                      thumbnailService: thumbnailService,
                      playbackSettings: playbackSettings,
                      onOpen: () => onOpen(item, videos),
                      onRevealLocation: onRevealLocation == null
                          ? null
                          : () => onRevealLocation!(item),
                      onToggleFavorite: () => onToggleFavorite(item),
                      onDeleteVideo: () => onDeleteVideo(item),
                      onToggleSelected: () => onToggleSelected(item),
                      onDelete: () => onDeleteOne(item),
                    );
                  },
                );
              }
              return GridView.builder(
                padding: EdgeInsets.fromLTRB(
                    compact ? 14 : 22, 2, compact ? 14 : 22, 22),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: narrow ? 500 : (compact ? 248 : 286),
                  mainAxisExtent: libraryVideoCardMainAxisExtent(
                    gridWidth: constraints.maxWidth,
                    narrow: narrow,
                    compact: compact,
                  ),
                  mainAxisSpacing: compact ? 14 : 16,
                  crossAxisSpacing: compact ? 10 : 14,
                ),
                itemCount: videos.length,
                itemBuilder: (context, index) {
                  final item = videos[index];
                  return _RecentPlaybackCard(
                    item: item,
                    selected: selectedVideoIds.contains(item.videoId),
                    thumbnailService: thumbnailService,
                    playbackSettings: playbackSettings,
                    onOpen: () => onOpen(item, videos),
                    onToggleFavorite: () => onToggleFavorite(item),
                    onToggleSelected: () => onToggleSelected(item),
                    onDelete: () => onDeleteOne(item),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RecentPlaybackRow extends StatelessWidget {
  const _RecentPlaybackRow({
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

class _RecentPlaybackCard extends StatelessWidget {
  const _RecentPlaybackCard({
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

/**
 * 本地媒体库路径浏览视图。
 *
 * 文件夹使用文件夹卡片/行，视频复用现有视频卡片/行；这样本地浏览不会绕开
 * 播放队列、收藏和更多编辑等媒体库已有行为。
 */
