import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/playback_settings.dart';
import '../../models/video_item.dart';
import '../../services/media/thumbnail_service.dart';
import 'library_smoke_keys.dart';
import 'library_video_results.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库增量结果的网格或列表展示。
 *
 * 组件只消费当前可见批次、布局指标和卡片回调；滚动批次、筛选结果、缩略图优先级
 * 以及播放队列仍由外部 owner 持有。
 */
class LibraryVideoGridResultsView extends StatelessWidget {
  const LibraryVideoGridResultsView({
    super.key,
    required this.dense,
    required this.narrow,
    required this.compact,
    required this.scrollController,
    required this.visibleItemCount,
    required this.visibleIndexByVideoId,
    required this.videos,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.onVisible,
    required this.onOpen,
    required this.onRevealLocation,
    required this.onToggleFavorite,
    required this.onDelete,
    required this.selectionMode,
    required this.selectedVideoIds,
    required this.onToggleSelected,
    required this.columnCount,
    required this.measuredWidth,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.textScaleFactor,
  });

  /** 是否使用单列紧凑结果行。 */
  final bool dense;
  /** 当前宽度是否需要更高的紧凑行。 */
  final bool narrow;
  /** 当前是否处于 compact 响应式断点。 */
  final bool compact;
  /** 由外部增量加载 owner 持有的滚动控制器。 */
  final ScrollController scrollController;
  /** 当前允许挂载的增量结果数量。 */
  final int visibleItemCount;
  /** Sliver 复用稳定 videoId 时使用的索引。 */
  final Map<String, int> visibleIndexByVideoId;
  /** 当前过滤结果的只读稳定快照。 */
  final List<VideoItem> videos;
  /** 卡片继续使用的缩略图服务边界。 */
  final ThumbnailService thumbnailService;
  /** 卡片预览需要的只读播放设置。 */
  final PlaybackSettings playbackSettings;
  /** 卡片进入挂载范围时的优先级通知。 */
  final ValueChanged<VideoItem>? onVisible;
  /** 请求播放器消费当前过滤队列。 */
  final void Function(VideoItem item, List<VideoItem> playlist) onOpen;
  /** 请求页面定位文件的回调。 */
  final ValueChanged<VideoItem>? onRevealLocation;
  /** 请求页面切换收藏的回调。 */
  final ValueChanged<VideoItem> onToggleFavorite;
  /** 请求页面执行删除确认的回调。 */
  final ValueChanged<VideoItem> onDelete;
  /** 是否处于批量选择模式。 */
  final bool selectionMode;
  /** 当前已选择的稳定 videoId。 */
  final Set<String> selectedVideoIds;
  /** 请求页面切换单条选择状态。 */
  final ValueChanged<VideoItem>? onToggleSelected;
  /** 稳定窗口宽度计算出的列数。 */
  final int columnCount;
  /** 当前结果区实际宽度。 */
  final double measuredWidth;
  /** 网格横向间距。 */
  final double crossAxisSpacing;
  /** 网格纵向间距。 */
  final double mainAxisSpacing;
  /** 系统文字缩放倍率。 */
  final double textScaleFactor;

  @override
  Widget build(BuildContext context) {
    final Widget results;
    if (dense) {
      results = ListView.builder(
        key: LibrarySmokeKeys.incrementalResults,
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(
          compact ? 14 : 22,
          2,
          compact ? 14 : 22,
          12,
        ),
        itemExtent: narrow ? 132 : 120,
        scrollCacheExtent: const ScrollCacheExtent.pixels(720),
        itemCount: visibleItemCount,
        findChildIndexCallback: (key) {
          if (key case ValueKey<String>(value: final value)) {
            return visibleIndexByVideoId[value];
          }
          return null;
        },
        itemBuilder: (context, index) {
          final item = videos[index];
          return Padding(
            key: ValueKey<String>(item.videoId),
            padding: const EdgeInsets.only(bottom: 8),
            child: InteractiveVideoListRow(
              item: item,
              thumbnailService: thumbnailService,
              playbackSettings: playbackSettings,
              onVisible: onVisible,
              onOpen: () => onOpen(item, videos),
              onRevealLocation: onRevealLocation == null
                  ? null
                  : () => onRevealLocation!(item),
              onToggleFavorite: () => onToggleFavorite(item),
              onDelete: () => onDelete(item),
              selectionMode: selectionMode,
              selected: selectedVideoIds.contains(item.videoId),
              onToggleSelected: onToggleSelected == null
                  ? null
                  : () => onToggleSelected!(item),
            ),
          );
        },
      );
    } else {
      results = GridView.builder(
        key: LibrarySmokeKeys.incrementalResults,
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(
          compact ? 14 : 22,
          2,
          compact ? 14 : 22,
          12,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columnCount,
          mainAxisExtent: libraryVideoCardMainAxisExtentForColumnCount(
            gridWidth: measuredWidth,
            compact: compact,
            columnCount: columnCount,
            crossAxisSpacing: crossAxisSpacing,
            textScaleFactor: textScaleFactor,
          ),
          mainAxisSpacing: mainAxisSpacing,
          crossAxisSpacing: crossAxisSpacing,
        ),
        itemCount: visibleItemCount,
        scrollCacheExtent: const ScrollCacheExtent.pixels(720),
        findChildIndexCallback: (key) {
          if (key case ValueKey<String>(value: final value)) {
            return visibleIndexByVideoId[value];
          }
          return null;
        },
        itemBuilder: (context, index) {
          final item = videos[index];
          return KeyedSubtree(
            key: ValueKey<String>(item.videoId),
            child: InteractiveVideoCard(
              item: item,
              thumbnailService: thumbnailService,
              playbackSettings: playbackSettings,
              onVisible: onVisible,
              onOpen: () => onOpen(item, videos),
              onRevealLocation: onRevealLocation == null
                  ? null
                  : () => onRevealLocation!(item),
              onToggleFavorite: () => onToggleFavorite(item),
              onDelete: () => onDelete(item),
              selectionMode: selectionMode,
              selected: selectedVideoIds.contains(item.videoId),
              onToggleSelected: onToggleSelected == null
                  ? null
                  : () => onToggleSelected!(item),
            ),
          );
        },
      );
    }

    return results;
  }
}
