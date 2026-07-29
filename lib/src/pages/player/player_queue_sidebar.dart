import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/tag_rules.dart';
import '../../models/video_item.dart';
import '../../services/media/media_details_service.dart';
import '../../services/media/thumbnail_service.dart';
import '../../widgets/app_theme_tokens.dart';

import 'player_queue_header.dart';
import 'player_queue_list_item.dart';
import 'player_queue_metadata_widgets.dart';
import 'player_queue_viewport.dart';

export 'player_queue_header.dart'
    show
        PlayerQueueHeader,
        playerQueueIndexIsVisible,
        playerQueueScrollOffsetForIndex;
export 'player_queue_viewport.dart' show playerQueueSidebarWidthForWindow;

// ignore_for_file: slash_for_doc_comments

const double playerQueueItemExtent = 104;

/** 队列底部返回操作栏高度，保证鼠标命中范围不小于桌面端推荐尺寸。 */
const double playerQueueLocatorHeight = 48;

/**
 * 判断队列项是否应继续显示快速滚动占位。
 *
 * Flutter 对大跨度 `jumpTo` 也可能短暂建议延后加载；滚动已经结束时必须优先恢复
 * 完整卡片，否则程序化定位后的可视条目可能永久停留在轻量占位外观。
 */
bool playerQueueShouldDeferItem({
  required bool scrollSettled,
  required bool recommendsDeferredLoading,
}) {
  return !scrollSettled && recommendsDeferredLoading;
}

/** 根据拖动进度与水平速度决定队列项操作区是否吸附到展开状态。 */
bool playerQueueActionShouldOpen({
  required double progress,
  required double horizontalVelocity,
}) {
  return horizontalVelocity < -250 ||
      (horizontalVelocity <= 250 && progress >= 0.45);
}

/** 队列搜索提交后返回给输入框的明确状态，不改变队列搜索语义。 */
enum PlayerQueueSearchOutcome {
  /** 已找到下一条匹配视频，并同步选中与实际播放位置。 */
  played,

  /** 当前 filtered queue 中没有匹配项。 */
  noMatch,

  /** 查询为空，未执行定位或播放。 */
  emptyQuery,
}

/** 在当前 filtered queue 内查找并直接播放下一条匹配视频。 */
typedef PlayerQueueSearchCallback = PlayerQueueSearchOutcome Function(
  String query,
);

class _PlayerDesktopDragScrollBehavior extends MaterialScrollBehavior {
  const _PlayerDesktopDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.mouse,
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
      };
}

class _HorizontalWheelScroller extends StatelessWidget {
  const _HorizontalWheelScroller({
    required this.children,
    this.padding = EdgeInsets.zero,
    this.spacing = 0,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double spacing;

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
        behavior: const _PlayerDesktopDragScrollBehavior(),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: padding,
          itemCount: children.length,
          itemBuilder: (context, index) => children[index],
          separatorBuilder: (context, index) => SizedBox(width: spacing),
        ),
      );
}

/** 只在当前播放器队列内执行轻量关键字定位，不访问媒体库或重新扫描。 */
int? playerQueueSearchIndex(
  List<VideoItem> items,
  String query, {
  int startIndex = 0,
}) {
  final keywords = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((value) => value.isNotEmpty)
      .toList();
  if (items.isEmpty || keywords.isEmpty) {
    return null;
  }
  for (var offset = 1; offset <= items.length; offset++) {
    final index = (startIndex + offset) % items.length;
    final item = items[index];
    final searchable = <String>[
      item.title,
      item.path,
      ...item.tags,
      for (final children in item.childTags.values) ...children,
    ].join('\n').toLowerCase();
    if (keywords.every(searchable.contains)) {
      return index;
    }
  }
  return null;
}

/**
 * 播放器右侧的筛选结果队列，承接库页传入的 filteredVideos。
 */
class PlayerQueueSidebar extends StatelessWidget {
  const PlayerQueueSidebar({
    super.key,
    this.embedded = false,
    required this.playlist,
    required this.sourcePlaylist,
    required this.playingIndex,
    required this.selectedIndex,
    required this.scrollController,
    required this.thumbnailService,
    required this.detailsService,
    required this.activeTags,
    required this.selectedChildTag,
    required this.onChildTagSelected,
    required this.onSelect,
    required this.onPlay,
    required this.onReturnToPlaying,
    required this.onLocateSelected,
    required this.onDeleteSelected,
    required this.onToggleFavorite,
    required this.onDeleteItem,
    required this.onSearchQueue,
    this.onSearchVisibilityChanged,
  });

  /**
   * 是否嵌入统一播放器侧栏。
   *
   * 嵌入时只构建队列内容，由上层统一提供边框、宽度和“列表/详情”切换；独立使用时
   * 保留原有完整容器，兼容窄窗口和测试入口。
   */
  final bool embedded;

  /**
   * 当前播放器实际消费的队列。
   */
  final List<VideoItem> playlist;

  /**
   * 原始筛选结果队列，用于子标签切换后恢复上下文。
   */
  final List<VideoItem> sourcePlaylist;

  /**
   * 正在播放的视频索引。
   */
  final int playingIndex;

  /**
   * 当前键盘或鼠标选中的队列项索引。
   */
  final int selectedIndex;

  /**
   * 播放器页持有的队列滚动控制器，用于回到播放项或定位选中项。
   */
  final ScrollController scrollController;

  /**
   * 队列缩略图来源。
   */
  final ThumbnailService thumbnailService;

  /**
   * 队列媒体信息来源。
   */
  final MediaDetailsService detailsService;

  /**
   * 库页传入的当前筛选标签上下文。
   */
  final List<String> activeTags;

  /**
   * 播放器页内部选中的子标签。
   */
  final String? selectedChildTag;

  /**
   * 切换播放器页内部子标签筛选。
   */
  final ValueChanged<String> onChildTagSelected;

  /**
   * 单击队列项时更新当前选择。
   */
  final ValueChanged<int> onSelect;

  /**
   * 双击队列项时跳转播放。
   */
  final ValueChanged<int> onPlay;

  /**
   * 底部“回到播放”将队列滚动回正在播放项，并让选中态同步到该视频。
   */
  final VoidCallback onReturnToPlaying;

  /**
   * 将右侧队列滚动回当前选中项，不改变选择或播放状态。
   */
  final VoidCallback onLocateSelected;

  /**
   * 删除当前视频的入口；为 null 时禁用。
   */
  final VoidCallback? onDeleteSelected;

  /** 切换单个队列项的收藏状态，不改变当前播放或筛选顺序。 */
  final ValueChanged<VideoItem> onToggleFavorite;

  /** 请求删除指定队列索引，实际文件动作由播放器页确认后执行。 */
  final ValueChanged<int> onDeleteItem;

  /** 在当前队列内查找并播放下一条匹配视频，不改变队列内容。 */
  final PlayerQueueSearchCallback onSearchQueue;

  /**
   * 队列搜索展开/收起通知。
   *
   * 播放器页只在收起后恢复全局快捷键焦点；输入期间仍由真实 EditableText 独占键盘。
   */
  final ValueChanged<bool>? onSearchVisibilityChanged;

  String? get _activeParentTag {
    if (activeTags.length != 1) {
      return null;
    }
    return activeTags.first;
  }

  List<String> get _childTags {
    final parent = _activeParentTag;
    if (parent == null) {
      return const <String>[];
    }
    final tags = <String>{};
    for (final item in sourcePlaylist) {
      tags.addAll(
          item.childTags[parent] ?? const <String>{TagRules.defaultAlbumTag});
    }
    return TagRules.sortedChildTags(tags);
  }

  @override
  Widget build(BuildContext context) {
    final sidebarWidth = playerQueueSidebarWidthForWindow(
      MediaQuery.sizeOf(context).width,
    );
    final content = Column(
      children: [
        PlayerQueueHeader(
          playlistLength: playlist.length,
          playingIndex: playingIndex,
          onDeleteSelected: onDeleteSelected,
          onSearch: onSearchQueue,
          onSearchVisibilityChanged: onSearchVisibilityChanged,
        ),
        if (_activeParentTag != null)
          SizedBox(
            height: 44,
            child: _HorizontalWheelScroller(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              spacing: 8,
              children: [
                for (final tag in _childTags)
                  PlayerChildTagChip(
                    label: tag,
                    selected: selectedChildTag == tag,
                    onPressed: () => onChildTagSelected(tag),
                  ),
              ],
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              QueueListViewport(
                controller: scrollController,
                playlist: playlist,
                itemBuilder: (context, index, item) {
                  return QueueListItem(
                    key: ValueKey('player.queue.item.${item.videoId}'),
                    item: item,
                    index: index,
                    playing: index == playingIndex,
                    selected: index == selectedIndex,
                    thumbnailService: thumbnailService,
                    detailsService: detailsService,
                    onTap: () => onSelect(index),
                    onDoubleTap: () => onPlay(index),
                    onToggleFavorite: () => onToggleFavorite(item),
                    onDelete: () => onDeleteItem(index),
                  );
                },
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedBuilder(
                  animation: scrollController,
                  builder: (context, _) {
                    final showPlaying = !_isQueueIndexVisible(playingIndex);
                    final showSelected = selectedIndex != playingIndex &&
                        !_isQueueIndexVisible(selectedIndex);
                    if (!showPlaying && !showSelected) {
                      return const SizedBox.shrink();
                    }
                    return QueueFloatingLocator(
                      showPlaying: showPlaying,
                      showSelected: showSelected,
                      onReturnToPlaying: onReturnToPlaying,
                      onLocateSelected: onLocateSelected,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (embedded) {
      return content;
    }
    return Container(
      width: sidebarWidth,
      // 与视频画面共享 Apple 式结构表面的外边距和底部基线。
      margin: const EdgeInsets.fromLTRB(0, 12, 16, 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: playerSurface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: playerBorder),
        boxShadow: playerSoftShadow,
      ),
      child: content,
    );
  }

  bool _isQueueIndexVisible(int index) {
    if (index < 0 || index >= playlist.length) {
      return true;
    }
    if (!scrollController.hasClients) {
      return true;
    }
    final position = scrollController.position;
    // 列表首次挂载或从压缩动画恢复时，ScrollPosition 可能已经绑定但尚未取得
    // viewport 尺寸；此时按可见处理，下一帧会由 ScrollController 自动重算。
    if (!position.hasContentDimensions) {
      return true;
    }
    final top = position.pixels;
    return playerQueueIndexIsVisible(
      index: index,
      scrollOffset: top,
      viewportExtent: position.viewportDimension,
      itemExtent: playerQueueItemExtent,
    );
  }
}
