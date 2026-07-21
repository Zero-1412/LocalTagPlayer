import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/tag_rules.dart';
import '../../models/media_details.dart';
import '../../models/video_item.dart';
import '../../services/media/media_details_service.dart';
import '../../services/media/thumbnail_service.dart';
import '../../widgets/app_theme_tokens.dart';

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
@visibleForTesting
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
          onLocateSelected: onLocateSelected,
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
                  _PlayerChildTagChip(
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
              _QueueListViewport(
                controller: scrollController,
                playlist: playlist,
                itemBuilder: (context, index, item) {
                  return _QueueListItem(
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
                    return _QueueFloatingLocator(
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

/** 为队列可视区域维护“滚动中/已停稳”状态，确保程序化定位后恢复完整卡片。 */
class _QueueListViewport extends StatefulWidget {
  const _QueueListViewport({
    required this.controller,
    required this.playlist,
    required this.itemBuilder,
  });

  /** 当前布局实例独占的滚动控制器。 */
  final ScrollController controller;

  /** 当前播放器实际消费的 filtered queue。 */
  final List<VideoItem> playlist;

  /** 滚动负载允许时构建完整队列项的回调。 */
  final Widget Function(BuildContext context, int index, VideoItem item)
      itemBuilder;

  @override
  State<_QueueListViewport> createState() => _QueueListViewportState();
}

/** 只协调占位生命周期，不持有或修改队列、选择和播放状态。 */
class _QueueListViewportState extends State<_QueueListViewport> {
  var _scrollSettled = true;

  /** 某些 Windows 滚轮/程序化跳转不会稳定发送结束通知，使用短防抖兜底。 */
  Timer? _settleFallbackTimer;

  /**
   * 记录滚动生命周期；结束通知必须触发重建，修复 `jumpTo` 后占位残留。
   */
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    final settled = notification is ScrollEndNotification ||
        notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle;
    final active = notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification ||
        notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle;
    if (settled) {
      _settleFallbackTimer?.cancel();
      if (!_scrollSettled) {
        setState(() => _scrollSettled = true);
      }
    } else if (active) {
      if (_scrollSettled) {
        setState(() => _scrollSettled = false);
      }
      _scheduleSettledFallback();
    }
    // 通知继续冒泡，保留外层滚动监听和桌面滚轮行为。
    return false;
  }

  /**
   * 最后一个滚动事件后恢复完整卡片，兼容只发送更新通知的 Windows 滚轮链路。
   */
  void _scheduleSettledFallback() {
    _settleFallbackTimer?.cancel();
    _settleFallbackTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _scrollSettled) {
        return;
      }
      setState(() => _scrollSettled = true);
    });
  }

  @override
  void dispose() {
    _settleFallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: ListView.builder(
        controller: widget.controller,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        itemExtent: playerQueueItemExtent,
        // 只预建邻近两项，避免大队列滚动时提前触发大量文件校验与 FFprobe。
        scrollCacheExtent: const ScrollCacheExtent.pixels(208),
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemCount: widget.playlist.length,
        itemBuilder: (context, index) {
          final item = widget.playlist[index];
          return _DeferredQueueListItem(
            item: item,
            scrollSettled: _scrollSettled,
            child: widget.itemBuilder(context, index, item),
          );
        },
      ),
    );
  }
}

/**
 * 快速滚动期间用轻量占位保护视频解码线程，滚动减速后再创建会访问磁盘的队列项。
 */
class _DeferredQueueListItem extends StatelessWidget {
  const _DeferredQueueListItem({
    required this.item,
    required this.scrollSettled,
    required this.child,
  });

  /** 当前队列项，仅用于在占位状态展示稳定标题。 */
  final VideoItem item;

  /** 当前滚动是否已经结束；停稳后必须恢复完整队列项。 */
  final bool scrollSettled;

  /** 滚动负载允许时才创建的完整队列项。 */
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shouldDefer = playerQueueShouldDeferItem(
      scrollSettled: scrollSettled,
      recommendsDeferredLoading:
          Scrollable.recommendDeferredLoadingForContext(context),
    );
    if (!shouldDefer) {
      return child;
    }
    // 快速滚动期间不启动缩略图校验或媒体详情读取，只保留可辨认的标题反馈。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: playerSurfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: playerBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: playerTextMuted, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

/**
 * 按桌面窗口宽度计算播放队列栏宽度。
 *
 * 队列栏在宽屏下保持接近蓝图的三成占比，同时通过上下限避免窄窗挤压
 * 播放画面，或在超宽屏上让单行队列信息变得过度松散。
 */
double playerQueueSidebarWidthForWindow(double windowWidth) {
  return (windowWidth * 0.28).clamp(360.0, 460.0).toDouble();
}

/**
 * 播放器队列头部，在紧凑操作区内按需展开搜索输入。
 *
 * 搜索默认收起，避免持续占用列表高度；播放序号后的操作按钮使用固定尺寸和
 * 明确间距，保证搜索、定位和删除入口在不同队列数量下仍保持稳定布局。
 */
class PlayerQueueHeader extends StatefulWidget {
  const PlayerQueueHeader({
    super.key,
    required this.playlistLength,
    required this.playingIndex,
    required this.onLocateSelected,
    required this.onDeleteSelected,
    required this.onSearch,
    this.onSearchVisibilityChanged,
  });

  /** 当前播放器实际消费的队列数量。 */
  final int playlistLength;

  /** 正在播放的视频在当前队列中的零基序号。 */
  final int playingIndex;

  /** 将列表定位到当前选中项，不改变播放状态。 */
  final VoidCallback onLocateSelected;

  /** 删除当前视频的入口；为 null 时禁用按钮。 */
  final VoidCallback? onDeleteSelected;

  /** 在当前队列内查找并播放下一条匹配视频，不重新查询媒体库。 */
  final PlayerQueueSearchCallback onSearch;

  /** 搜索输入展开/收起通知，供播放器恢复快捷键焦点。 */
  final ValueChanged<bool>? onSearchVisibilityChanged;

  @override
  State<PlayerQueueHeader> createState() => _PlayerQueueHeaderState();
}

/** 维护队列搜索框的临时展开状态，不污染播放器会话状态。 */
class _PlayerQueueHeaderState extends State<PlayerQueueHeader> {
  bool _searchVisible = false;

  /** 切换搜索框；重新展开时由输入框自动获得焦点。 */
  void _toggleSearch() {
    final visible = !_searchVisible;
    setState(() => _searchVisible = visible);
    widget.onSearchVisibilityChanged?.call(visible);
  }

  @override
  void dispose() {
    if (_searchVisible) {
      // 全屏队列自动隐藏会直接卸载头部；仍需通知播放器恢复稳定焦点。
      widget.onSearchVisibilityChanged?.call(false);
    }
    super.dispose();
  }

  /** 构建统一尺寸的紧凑操作按钮，避免图标随默认约束产生不规则间距。 */
  Widget _actionButton({
    required Key key,
    required String tooltip,
    required VoidCallback? onPressed,
    required IconData icon,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        child: IconButton(
          key: key,
          onPressed: onPressed,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
          icon: Icon(icon, size: 18),
          color: playerTextMuted,
          disabledColor: playerTextMuted.withValues(alpha: 0.32),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: const BoxDecoration(
        color: playerSurface,
        border: Border(
          bottom: BorderSide(color: playerBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.filter_alt_outlined,
                color: appAccentViolet,
                size: 21,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '筛选结果队列',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: playerText,
                    fontSize: 14,
                    fontWeight: AppTypography.strong,
                  ),
                ),
              ),
              Text(
                '${widget.playingIndex + 1} / ${widget.playlistLength}',
                key: const ValueKey('player.queue.position'),
                style: const TextStyle(
                  color: playerTextMuted,
                  fontSize: 12,
                  fontWeight: AppTypography.strong,
                ),
              ),
              const SizedBox(width: 8),
              _actionButton(
                key: const ValueKey('player.queue.search.toggle'),
                tooltip: _searchVisible ? '收起搜索' : '搜索队列',
                onPressed: _toggleSearch,
                icon:
                    _searchVisible ? Icons.close_rounded : Icons.search_rounded,
              ),
              const SizedBox(width: 4),
              _actionButton(
                key: const ValueKey('player.queue.locate.selected'),
                tooltip: '定位已选中',
                onPressed: widget.onLocateSelected,
                icon: Icons.center_focus_strong_rounded,
              ),
              const SizedBox(width: 4),
              _actionButton(
                key: const ValueKey('player.queue.delete.selected'),
                tooltip: '删除当前视频',
                onPressed: widget.onDeleteSelected,
                icon: Icons.delete_outline,
              ),
            ],
          ),
          if (_searchVisible) ...[
            const SizedBox(height: 8),
            _QueueSearchField(
              autofocus: true,
              onSearch: widget.onSearch,
              onClose: _toggleSearch,
            ),
          ],
        ],
      ),
    );
  }
}

/**
 * 当前播放队列的轻量搜索框，同时支持键盘提交和可见按钮提交。
 */
class _QueueSearchField extends StatefulWidget {
  const _QueueSearchField({
    this.autofocus = false,
    required this.onSearch,
    required this.onClose,
  });

  /** 展开后是否立即接管键盘输入焦点。 */
  final bool autofocus;

  /** 仅在播放器已持有的队列中查找并播放，不访问媒体库或触发重新扫描。 */
  final PlayerQueueSearchCallback onSearch;

  /** Escape 或关闭动作只收起搜索，不让同一按键继续冒泡成播放器退出。 */
  final VoidCallback onClose;

  @override
  State<_QueueSearchField> createState() => _QueueSearchFieldState();
}

/** 维护搜索输入，避免把临时查询状态提升到播放器或媒体库控制器。 */
class _QueueSearchFieldState extends State<_QueueSearchField> {
  final TextEditingController _controller = TextEditingController();
  String _status = 'Enter 查找并播放下一条匹配视频';

  /** 提交当前查询，并把实际播放结果反馈在输入框下方的固定状态区。 */
  void _submit() {
    final outcome = widget.onSearch(_controller.text);
    setState(() {
      _status = switch (outcome) {
        PlayerQueueSearchOutcome.played => '已切换到下一条匹配视频',
        PlayerQueueSearchOutcome.noMatch => '当前筛选队列没有匹配项',
        PlayerQueueSearchOutcome.emptyQuery => '请先输入关键词',
      };
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('player.queueSearch'),
            controller: _controller,
            autofocus: widget.autofocus,
            style: const TextStyle(color: playerText, fontSize: 12),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: '查找并播放下一条',
              hintStyle: const TextStyle(color: playerTextMuted),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 18,
                color: playerTextMuted,
              ),
              filled: true,
              fillColor: playerSurfaceAlt,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide: const BorderSide(color: playerBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide:
                    const BorderSide(color: appAccentViolet, width: 1.5),
              ),
              suffixIcon: IconButton(
                key: const ValueKey('player.queueSearchSubmit'),
                tooltip: '播放下一条匹配视频',
                onPressed: _submit,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
              ),
            ),
            onChanged: (_) {
              if (_status != 'Enter 查找并播放下一条匹配视频') {
                setState(() => _status = 'Enter 查找并播放下一条匹配视频');
              }
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 5),
          Semantics(
            liveRegion: true,
            child: Text(
              _status,
              key: const ValueKey('player.queueSearch.status'),
              style: const TextStyle(
                color: playerTextSecondary,
                fontSize: 11,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

@visibleForTesting
bool playerQueueIndexIsVisible({
  required int index,
  required double scrollOffset,
  required double viewportExtent,
  required double itemExtent,
  double tolerance = 12,
}) {
  if (index < 0 || viewportExtent <= 0 || itemExtent <= 0) {
    return true;
  }
  final top = scrollOffset;
  final bottom = top + viewportExtent;
  final itemTop = index * itemExtent;
  final itemBottom = itemTop + itemExtent;
  return itemBottom > top + tolerance && itemTop < bottom - tolerance;
}

/**
 * 计算队列索引的稳定滚动位置。
 *
 * [topPadding] 必须与 ListView 顶部 padding 一致；集中计算可避免大队列定位因忽略
 * padding 或视口居中偏移而落到相邻视频。
 */
double playerQueueScrollOffsetForIndex({
  required int index,
  required double viewportExtent,
  required double itemExtent,
  required double minScrollExtent,
  required double maxScrollExtent,
  required bool center,
  double topPadding = 6,
}) {
  final itemTop = topPadding + index * itemExtent;
  final target = center
      ? itemTop - (viewportExtent - itemExtent) / 2
      : itemTop - itemExtent;
  return target.clamp(minScrollExtent, maxScrollExtent).toDouble();
}

class _PlayerChildTagChip extends StatelessWidget {
  const _PlayerChildTagChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        selected ? appAccentViolet.withValues(alpha: 0.20) : playerSurfaceAlt;
    final borderColor = selected ? appAccentViolet : playerBorder;
    final textColor = selected ? playerText : playerTextMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onPressed,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight:
                  selected ? AppTypography.strong : AppTypography.medium,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueStateBadge extends StatelessWidget {
  const _QueueStateBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.capsule),
        border: Border.all(color: color.withValues(alpha: 0.72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueFloatingLocator extends StatelessWidget {
  const _QueueFloatingLocator({
    required this.showPlaying,
    required this.showSelected,
    required this.onReturnToPlaying,
    required this.onLocateSelected,
  });

  final bool showPlaying;
  final bool showSelected;
  final VoidCallback onReturnToPlaying;
  final VoidCallback onLocateSelected;

  @override
  Widget build(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    return AnimatedOpacity(
      duration: accessibility.fadeDuration(AppMotion.hover),
      opacity: showPlaying || showSelected ? 1 : 0,
      child: SizedBox(
        height: playerQueueLocatorHeight,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: playerSurfaceRaised,
            border: Border(top: BorderSide(color: playerBorder)),
            boxShadow: [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: Row(
            // 操作按钮填满停靠栏，整块可见区域均可点击。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showPlaying)
                Expanded(
                  child: _QueueLocatorButton(
                    icon: Icons.play_arrow_rounded,
                    label: '回到播放',
                    onPressed: onReturnToPlaying,
                  ),
                ),
              if (showPlaying && showSelected)
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: playerBorder,
                ),
              if (showSelected)
                Expanded(
                  child: _QueueLocatorButton(
                    icon: Icons.center_focus_strong_rounded,
                    label: '回到选中',
                    onPressed: onLocateSelected,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueLocatorButton extends StatelessWidget {
  const _QueueLocatorButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: playerText,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(),
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _QueueListItem extends StatefulWidget {
  const _QueueListItem({
    super.key,
    required this.item,
    required this.index,
    required this.playing,
    required this.selected,
    required this.thumbnailService,
    required this.detailsService,
    required this.onTap,
    required this.onDoubleTap,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  /**
   * 队列项对应的视频，不改变播放队列顺序。
   */
  final VideoItem item;

  /**
   * 当前项在筛选结果队列中的零基序号。
   */
  final int index;

  /**
   * 该项是否为播放器正在消费的视频。
   */
  final bool playing;

  /**
   * 该项是否为键盘或鼠标当前选中的队列项。
   */
  final bool selected;

  /**
   * 缩略图服务，仅用于队列项预览。
   */
  final ThumbnailService thumbnailService;

  /**
   * 媒体详情服务，仅用于显示编码和分辨率摘要。
   */
  final MediaDetailsService detailsService;

  /**
   * 单击队列项时只更新选中位置。
   */
  final VoidCallback onTap;

  /**
   * 双击队列项时切换实际播放位置。
   */
  final VoidCallback onDoubleTap;

  /** 左滑操作区中的收藏切换动作。 */
  final VoidCallback onToggleFavorite;

  /** 左滑操作区中的删除动作。 */
  final VoidCallback onDelete;

  @override
  State<_QueueListItem> createState() => _QueueListItemState();
}

class _QueueListItemState extends State<_QueueListItem>
    with SingleTickerProviderStateMixin {
  static const _actionRevealWidth = 106.0;
  late Future<File?> _thumbnailFuture;
  late Future<MediaDetails> _detailsFuture;
  late final AnimationController _actionController;
  var _hovered = false;

  @override
  void initState() {
    super.initState();
    _actionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _loadItemFutures();
  }

  @override
  void didUpdateWidget(covariant _QueueListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.path != widget.item.path) {
      _actionController.value = 0;
      _loadItemFutures();
      return;
    }
    if (!oldWidget.playing && widget.playing) {
      // 条目成为当前播放项时必须清除之前保留的左滑进度；否则隐藏操作层会与播放徽标重叠。
      // 这里只复位视觉状态，用户随后仍可主动左滑当前项执行收藏或删除。
      _actionController.value = 0;
    }
  }

  @override
  void dispose() {
    _actionController.dispose();
    super.dispose();
  }

  /** 把水平拖动距离映射为稳定的 0..1 展开进度。 */
  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    _actionController.value =
        (_actionController.value - details.delta.dx / _actionRevealWidth)
            .clamp(0.0, 1.0);
  }

  /** 根据拖动速度和过半阈值平滑吸附到展开或折叠状态。 */
  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final shouldOpen = playerQueueActionShouldOpen(
      progress: _actionController.value,
      horizontalVelocity: velocity,
    );
    _settleActionPanel(shouldOpen);
  }

  /** 按剩余距离计算吸附时长；下一次拖动可直接改写 controller 进度。 */
  void _settleActionPanel(bool open) {
    final accessibility = AppAccessibilityScope.of(context);
    final target = open ? 1.0 : 0.0;
    final remaining = (target - _actionController.value).abs();
    if (accessibility.reduceMotion) {
      _actionController.value = target;
      return;
    }
    final milliseconds = (60 + 160 * remaining).round();
    _actionController.animateTo(
      target,
      duration: Duration(milliseconds: milliseconds),
      curve: AppMotion.standardCurve,
    );
  }

  /** 执行动作前先收回操作区，避免弹窗返回后队列项仍停在半展开状态。 */
  void _runAction(VoidCallback action) {
    _settleActionPanel(false);
    action();
  }

  void _loadItemFutures() {
    if (widget.item.isMissing) {
      // missing 条目不再派发文件 I/O，避免大队列对失效路径反复探测。
      _thumbnailFuture = Future<File?>.value(null);
      _detailsFuture = Future<MediaDetails>.value(const MediaDetails());
      return;
    }
    // 完整队列项只会在滚动负载允许时挂载，因此这里代表真实可视/近可视区域。
    // 缩略图复用共享缓存；缺失时进入播放期单并发优先队列，不唤醒后台补全。
    _thumbnailFuture = widget.thumbnailService.ensureThumbnailFor(widget.item);
    // 已持久化详情立即返回；未命中时把当前可视项提升到扫描后台任务之前。
    _detailsFuture =
        widget.detailsService.detailsFor(widget.item, priority: true);
  }

  @override
  Widget build(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    final emphasis = widget.playing
        ? 3
        : widget.selected
            ? 2
            : _hovered
                ? 1
                : 0;
    final infoColor = emphasis >= 2
        ? playerTextMuted
        : _hovered
            ? playerTextMuted
            : playerTextMuted.withValues(alpha: 0.72);
    final titleColor = widget.playing
        ? playerText
        : widget.selected
            ? playerText
            : _hovered
                ? playerText
                : playerText.withValues(alpha: 0.76);
    final backgroundColor = widget.playing
        ? appAccentViolet.withValues(alpha: 0.18)
        : widget.selected
            ? playerSurfaceRaised
            : _hovered
                ? playerSurfaceRaised.withValues(alpha: 0.82)
                : playerSurfaceAlt;
    final borderColor = widget.playing
        ? appAccentViolet
        : widget.selected
            ? playerTextMuted.withValues(alpha: 0.55)
            : _hovered
                ? playerTextMuted.withValues(alpha: 0.38)
                : playerBorder;
    final accentColor = widget.playing
        ? appAccentViolet
        : widget.selected
            ? playerText
            : _hovered
                ? playerTextMuted
                : playerTextMuted.withValues(alpha: 0.44);
    final showHoverAction = _hovered && !widget.playing;
    final stateBadgeLabel = widget.item.isMissing
        ? '缺失'
        : widget.playing
            ? '播放中'
            : widget.selected
                ? '已选中'
                : null;
    final stateBadgeIcon = widget.item.isMissing
        ? Icons.link_off_rounded
        : widget.playing
            ? Icons.play_arrow_rounded
            : widget.selected
                ? Icons.center_focus_strong_rounded
                : null;
    final stateBadgeColor = widget.item.isMissing
        ? playerDanger
        : widget.playing
            ? appAccentViolet
            : playerTextMuted;
    final shadow = widget.selected || _hovered
        ? const [
            BoxShadow(
              color: Color(0x2e000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ]
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) {
          setState(() => _hovered = false);
          _actionController.reverse();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: AnimatedBuilder(
            animation: _actionController,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: widget.onTap,
              onDoubleTap: widget.onDoubleTap,
              child: AnimatedContainer(
                key: ValueKey(
                  'player.queue.card.${widget.item.videoId}',
                ),
                duration: accessibility.fadeDuration(AppMotion.hover),
                curve: AppMotion.standardCurve,
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: borderColor),
                  boxShadow: shadow,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: accessibility.fadeDuration(AppMotion.hover),
                      width: 3,
                      height: 60,
                      decoration: BoxDecoration(
                        color: widget.playing || widget.selected || _hovered
                            ? accentColor
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.capsule),
                      ),
                    ),
                    const SizedBox(width: 5),
                    SizedBox(
                      width: 100,
                      height: 58,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FutureBuilder<File?>(
                              future: _thumbnailFuture,
                              initialData:
                                  widget.thumbnailService.cachedThumbnailFor(
                                widget.item,
                              ),
                              builder: (context, snapshot) {
                                final file = snapshot.data;
                                // 缓存有效性由 ThumbnailService 负责，Widget 不再同步访问磁盘。
                                if (file != null) {
                                  return Image.file(
                                    file,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.low,
                                    cacheWidth: 160,
                                    gaplessPlayback: true,
                                  );
                                }
                                return const ColoredBox(
                                  color: playerSurfaceRaised,
                                  child: Center(
                                    child: Icon(Icons.movie_outlined,
                                        color: playerTextMuted, size: 22),
                                  ),
                                );
                              },
                            ),
                            AnimatedOpacity(
                              duration:
                                  accessibility.fadeDuration(AppMotion.hover),
                              opacity: showHoverAction ? 1 : 0,
                              child: const ColoredBox(
                                color: Color(0x66000000),
                                child: Center(
                                  child: Icon(Icons.play_arrow_rounded,
                                      color: Colors.white, size: 24),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FutureBuilder<MediaDetails>(
                        future: _detailsFuture,
                        initialData:
                            widget.detailsService.cachedDetailsFor(widget.item),
                        builder: (context, snapshot) {
                          final details = snapshot.data;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    width: 30,
                                    child: Text(
                                      (widget.index + 1)
                                          .toString()
                                          .padLeft(2, '0'),
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      style: TextStyle(
                                        color: accentColor,
                                        fontSize: 12,
                                        fontWeight: emphasis >= 2
                                            ? FontWeight.w900
                                            : FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      widget.item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: titleColor,
                                        fontSize: 13,
                                        height: 1.15,
                                        fontWeight: emphasis >= 2
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Semantics(
                                    label:
                                        widget.item.isFavorite ? '已收藏' : '未收藏',
                                    child: SizedBox(
                                      width: 15,
                                      height: 15,
                                      child: widget.item.isFavorite
                                          ? Icon(
                                              Icons.favorite_rounded,
                                              key: ValueKey(
                                                'player.queue.'
                                                'favoriteIndicator.'
                                                '${widget.item.videoId}',
                                              ),
                                              size: 15,
                                              color: playerDanger,
                                            )
                                          : null,
                                    ),
                                  ),
                                  if (stateBadgeLabel != null &&
                                      stateBadgeIcon != null) ...[
                                    const SizedBox(width: 6),
                                    _QueueStateBadge(
                                      label: stateBadgeLabel,
                                      icon: stateBadgeIcon,
                                      color: stateBadgeColor,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _detailsLine(details),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: infoColor,
                                    fontSize: 11,
                                    height: 1.1),
                              ),
                              AnimatedOpacity(
                                duration:
                                    accessibility.fadeDuration(AppMotion.hover),
                                opacity: showHoverAction ? 1 : 0,
                                child: const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Text(
                                    '单击选中 · 双击播放',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: playerTextMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            builder: (context, front) {
              final revealProgress = _actionController.value;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (revealProgress > 0.001)
                    // 完全收起时卸载隐藏操作层，避免真实窗口的像素舍入让图标从卡片右缘泄出。
                    _buildActionBackground(),
                  Transform.translate(
                    offset: Offset(
                      -_actionRevealWidth * revealProgress,
                      0,
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (_) => widget.onTap(),
                      onHorizontalDragUpdate: _handleHorizontalDragUpdate,
                      onHorizontalDragEnd: _handleHorizontalDragEnd,
                      onHorizontalDragCancel: () => _settleActionPanel(false),
                      child: front,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /** 构建折叠在卡片后的收藏与删除操作区，颜色沿用播放器深色主题。 */
  Widget _buildActionBackground() {
    return DecoratedBox(
      decoration: const BoxDecoration(color: playerSurface),
      child: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: _actionRevealWidth,
          height: double.infinity,
          child: Padding(
            // 操作面板与前景卡片共享 Stack 的完整高度，只保留横向呼吸空间。
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: DecoratedBox(
              key: ValueKey(
                'player.queue.actionPanel.${widget.item.videoId}',
              ),
              decoration: BoxDecoration(
                color: playerSurfaceRaised,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: playerBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: widget.item.isFavorite ? '取消收藏' : '收藏',
                        child: Material(
                          key: ValueKey(
                            'player.queue.favoriteActionSurface.'
                            '${widget.item.videoId}',
                          ),
                          // 红心本身已明确表达收藏状态，不再叠加发光式色块。
                          color: Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(AppRadius.control),
                          child: InkWell(
                            key: ValueKey(
                              'player.queue.favoriteAction.'
                              '${widget.item.videoId}',
                            ),
                            borderRadius:
                                BorderRadius.circular(AppRadius.control),
                            onTap: () => _runAction(widget.onToggleFavorite),
                            child: Icon(
                              widget.item.isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: playerDanger,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 7),
                      child: VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: playerBorder,
                      ),
                    ),
                    Expanded(
                      child: Tooltip(
                        message: '删除',
                        child: Material(
                          color: Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(AppRadius.control),
                          child: InkWell(
                            key: ValueKey(
                              'player.queue.deleteAction.'
                              '${widget.item.videoId}',
                            ),
                            borderRadius:
                                BorderRadius.circular(AppRadius.control),
                            onTap: () => _runAction(widget.onDelete),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              color: playerDanger,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _detailsLine(MediaDetails? details) {
    if (widget.item.isMissing) {
      return '路径失效 · 可重新关联';
    }
    if (details == null) {
      return '\u5a92\u4f53\u4fe1\u606f\u8bfb\u53d6\u4e2d';
    }
    return '${details.videoLabel}  |  ${details.audioLabel}';
  }
}
