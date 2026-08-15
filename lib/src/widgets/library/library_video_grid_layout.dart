import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/layout_size.dart';
import '../../core/playback_settings.dart';
import '../../models/video_item.dart';
import '../../services/media/thumbnail_service.dart';
import 'library_video_grid_results_view.dart';
import 'library_video_grid_return_to_top.dart';
import 'library_video_results.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

/**
 * 结果网格的纯布局叶子。
 *
 * VideoGrid State 继续拥有滚动、增量批次和顶部状态；这里仅根据快照计算布局并挂载结果，
 * 避免入口文件同时承载状态机和大段响应式展示树。
 */
class LibraryVideoGridLayout extends StatelessWidget {
  const LibraryVideoGridLayout({
    super.key,
    required this.videos,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.dense,
    required this.columnReferenceWidth,
    required this.onVisible,
    required this.onOpen,
    required this.onRevealLocation,
    required this.onToggleFavorite,
    required this.onDelete,
    required this.selectionMode,
    required this.selectedVideoIds,
    required this.onToggleSelected,
    required this.scrollChromeEnabled,
    required this.scrollController,
    required this.loadedItemCount,
    required this.showReturnToTop,
    required this.stableViewportWidth,
    required this.visibleIndexMap,
    required this.onLayoutMetrics,
    required this.onScrollNotification,
    required this.onScrollToTop,
  });

  final List<VideoItem> videos;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  final bool dense;
  final double? columnReferenceWidth;
  final ValueChanged<VideoItem>? onVisible;
  final void Function(VideoItem item, List<VideoItem> playlist) onOpen;
  final ValueChanged<VideoItem>? onRevealLocation;
  final ValueChanged<VideoItem> onToggleFavorite;
  final ValueChanged<VideoItem> onDelete;
  final bool selectionMode;
  final Set<String> selectedVideoIds;
  final ValueChanged<VideoItem>? onToggleSelected;
  final bool scrollChromeEnabled;
  final ScrollController scrollController;
  final int loadedItemCount;
  final bool showReturnToTop;
  final double Function(double measuredWidth) stableViewportWidth;
  final Map<String, int> Function(int visibleItemCount) visibleIndexMap;
  final void Function(int columnCount, double rowExtent, int visibleItemCount)
      onLayoutMetrics;
  final bool Function(ScrollNotification notification) onScrollNotification;
  final Future<void> Function() onScrollToTop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final measuredWidth = constraints.maxWidth;
        final referenceWidth = columnReferenceWidth ?? measuredWidth;
        final stableWidth = stableViewportWidth(referenceWidth);
        final resizing = (referenceWidth - stableWidth).abs() > 0.5;
        final compact = stableWidth < LayoutBreakpoints.compactMaxWidth;
        final narrow = stableWidth < 560;
        final crossAxisSpacing = libraryVideoGridCrossAxisSpacing(
          gridWidth: stableWidth,
          compact: compact,
        );
        final mainAxisSpacing = libraryVideoGridMainAxisSpacing(
          gridWidth: stableWidth,
          compact: compact,
        );
        final textScaleFactor = MediaQuery.textScalerOf(context).scale(1);
        final columnCount = dense
            ? 1
            : libraryVideoGridColumnCount(
                gridWidth: stableWidth,
                narrow: narrow,
                compact: compact,
              );
        final rowExtent = dense
            ? (narrow ? 132.0 : 120.0)
            : libraryVideoCardMainAxisExtentForColumnCount(
                  gridWidth: measuredWidth,
                  compact: compact,
                  columnCount: columnCount,
                  crossAxisSpacing: crossAxisSpacing,
                  textScaleFactor: textScaleFactor,
                ) +
                mainAxisSpacing;
        final initialCount = libraryIncrementalItemCount(
          totalCount: videos.length,
          currentCount: 0,
          columnCount: columnCount,
        );
        // 窗口改变列数时只允许扩大首批范围，不能让已显示卡片倒退消失。
        final visibleItemCount = math
            .min(videos.length, math.max(loadedItemCount, initialCount))
            .toInt();
        onLayoutMetrics(columnCount, rowExtent, visibleItemCount);
        final results = LibraryVideoGridResultsView(
          dense: dense,
          narrow: narrow,
          compact: compact,
          scrollController: scrollController,
          visibleItemCount: visibleItemCount,
          visibleIndexByVideoId: visibleIndexMap(visibleItemCount),
          videos: videos,
          thumbnailService: thumbnailService,
          playbackSettings: playbackSettings,
          onVisible: onVisible,
          onOpen: onOpen,
          onRevealLocation: onRevealLocation,
          onToggleFavorite: onToggleFavorite,
          onDelete: onDelete,
          selectionMode: selectionMode,
          selectedVideoIds: selectedVideoIds,
          onToggleSelected: onToggleSelected,
          columnCount: columnCount,
          measuredWidth: measuredWidth,
          crossAxisSpacing: crossAxisSpacing,
          mainAxisSpacing: mainAxisSpacing,
          textScaleFactor: textScaleFactor,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: NotificationListener<ScrollNotification>(
                onNotification: onScrollNotification,
                child: AnimatedOpacity(
                  opacity: resizing ? 0.97 : 1,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  child: results,
                ),
              ),
            ),
            if (scrollChromeEnabled)
              LibraryVideoGridReturnToTop(
                visible: showReturnToTop,
                onTap: onScrollToTop,
              ),
          ],
        );
      },
    );
  }
}
