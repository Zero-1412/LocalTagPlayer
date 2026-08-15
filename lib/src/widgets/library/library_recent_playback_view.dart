import 'package:flutter/material.dart';

import '../../core/layout_size.dart';
import '../../core/playback_settings.dart';
import '../../models/video_item.dart';
import '../../services/media/thumbnail_service.dart';
import '../app_theme_tokens.dart';
import 'library_recent_playback_items.dart';
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
    this.preserveScrollOnResultDelta = false,
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

  /** 删除或播放记录差量发布时保留当前列表位置。 */
  final bool preserveScrollOnResultDelta;

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
                  findChildIndexCallback: preserveScrollOnResultDelta
                      ? (key) => _recentPlaybackIndexForKey(key, videos)
                      : null,
                  itemBuilder: (context, index) {
                    final item = videos[index];
                    return KeyedSubtree(
                      key: ValueKey<String>(item.videoId),
                      child: RecentPlaybackRow(
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
                      ),
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
                findChildIndexCallback: preserveScrollOnResultDelta
                    ? (key) => _recentPlaybackIndexForKey(key, videos)
                    : null,
                itemBuilder: (context, index) {
                  final item = videos[index];
                  return KeyedSubtree(
                    key: ValueKey<String>(item.videoId),
                    child: RecentPlaybackCard(
                      item: item,
                      selected: selectedVideoIds.contains(item.videoId),
                      thumbnailService: thumbnailService,
                      playbackSettings: playbackSettings,
                      onOpen: () => onOpen(item, videos),
                      onToggleFavorite: () => onToggleFavorite(item),
                      onToggleSelected: () => onToggleSelected(item),
                      onDelete: () => onDeleteOne(item),
                    ),
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

int? _recentPlaybackIndexForKey(
  Key? key,
  List<VideoItem> videos,
) {
  if (key is! ValueKey<String>) {
    return null;
  }
  final index = videos.indexWhere((item) => item.videoId == key.value);
  return index < 0 ? null : index;
}
