part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

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
class _PlayerQueueSidebar extends StatelessWidget {
  const _PlayerQueueSidebar({
    required this.playlist,
    required this.sourcePlaylist,
    required this.playingIndex,
    required this.selectedIndex,
    required this.scrollController,
    required this.thumbnailService,
    required this.detailsService,
    required this.activeTags,
    required this.selectedChildTag,
    required this.queueTitle,
    required this.onChildTagSelected,
    required this.onSelect,
    required this.onPlay,
    required this.onLocatePlaying,
    required this.onLocateSelected,
    required this.onDeleteSelected,
    required this.onSearchQueue,
  });

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
   * 播放器页持有的队列滚动控制器，用于定位当前播放或选中项。
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
   * 队列顶部显示的筛选摘要。
   */
  final String queueTitle;

  /**
   * 切换播放器页内部子标签筛选。
   */
  final ValueChanged<String> onChildTagSelected;

  /**
   * 单击队列项时更新当前选择。
   */
  final ValueChanged<int> onSelect;

  /**
   * 单击或双击队列项时跳转播放。
   */
  final ValueChanged<int> onPlay;

  /**
   * 将右侧队列滚动回正在播放项，不改变选择或播放状态。
   */
  final VoidCallback onLocatePlaying;

  /**
   * 将右侧队列滚动回当前选中项，不改变选择或播放状态。
   */
  final VoidCallback onLocateSelected;

  /**
   * 删除当前视频的入口；为 null 时禁用。
   */
  final VoidCallback? onDeleteSelected;

  /** 在当前队列内搜索并定位，不改变队列内容。 */
  final ValueChanged<String> onSearchQueue;

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

  String get _filterSummary {
    if (queueTitle.trim().isEmpty) {
      return '\u5168\u90e8\u89c6\u9891';
    }
    return queueTitle;
  }

  @override
  Widget build(BuildContext context) {
    final sidebarWidth = playerQueueSidebarWidthForWindow(
      MediaQuery.sizeOf(context).width,
    );
    return Container(
      width: sidebarWidth,
      // 与左侧视频画面的顶边对齐，保持蓝图中的双栏视觉基线。
      margin: const EdgeInsets.fromLTRB(0, 18, 14, 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xff0d1528),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xff202c46)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: const BoxDecoration(
              color: Color(0xff0d1528),
              border: Border(
                bottom: BorderSide(color: Color(0xff243044)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.filter_alt_outlined,
                      color: Color(0xffa9b8ff),
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Flexible(
                              child: Text(
                                '筛选结果队列',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xff1b2544),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text('${playlist.length}',
                                  style: const TextStyle(
                                      color: Color(0xffb7c2d8),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ]),
                          const SizedBox(height: 2),
                          const Text(
                            '当前筛选（AND）',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xff8f9bad),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '定位当前播放',
                      onPressed: onLocatePlaying,
                      icon: const Icon(Icons.my_location_rounded, size: 17),
                      color: Colors.white70,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      tooltip: '定位已选中',
                      onPressed: onLocateSelected,
                      icon: const Icon(Icons.center_focus_strong_rounded,
                          size: 17),
                      color: Colors.white70,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      tooltip: '删除当前视频',
                      onPressed: onDeleteSelected,
                      icon: const Icon(Icons.delete_outline, size: 17),
                      color: Colors.white70,
                      disabledColor: Colors.white24,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Tooltip(
                  message: _filterSummary,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xff121c2b),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xff344369)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 16,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(children: [
                      const _QueueFilterChip(
                        label: '全部视频',
                        emphasized: true,
                      ),
                      const SizedBox(width: 6),
                      const _QueueFilterChip(label: '时长：全部'),
                      const SizedBox(width: 6),
                      const _QueueFilterChip(label: '大小：全部'),
                      const Spacer(),
                      Text(
                        '${playingIndex + 1} / ${playlist.length}',
                        style: const TextStyle(
                          color: Color(0xffa5b4fc),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                _QueueSearchField(onSearch: onSearchQueue),
              ],
            ),
          ),
          if (_activeParentTag != null)
            SizedBox(
              height: 44,
              child: _HorizontalWheelScroller(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                  itemExtent: _PlayerPageState._queueItemExtent,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(720),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  itemCount: playlist.length,
                  itemBuilder: (context, index) {
                    final item = playlist[index];
                    return _QueueListItem(
                      item: item,
                      index: index,
                      playing: index == playingIndex,
                      selected: index == selectedIndex,
                      thumbnailService: thumbnailService,
                      detailsService: detailsService,
                      onTap: () => onPlay(index),
                      onDoubleTap: () => onPlay(index),
                    );
                  },
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
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
                        onLocatePlaying: onLocatePlaying,
                        onLocateSelected: onLocateSelected,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    final top = position.pixels;
    return playerQueueIndexIsVisible(
      index: index,
      scrollOffset: top,
      viewportExtent: position.viewportDimension,
      itemExtent: _PlayerPageState._queueItemExtent,
    );
  }
}

/** 蓝图队列头部的只读筛选状态，不伪装为尚未实现的交互按钮。 */
class _QueueFilterChip extends StatelessWidget {
  const _QueueFilterChip({required this.label, this.emphasized = false});

  /** 当前筛选维度的摘要文本。 */
  final String label;

  /** 是否为当前主要筛选入口。 */
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: emphasized ? const Color(0xff18254a) : const Color(0xff11192c),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: emphasized ? const Color(0xff4f68a8) : const Color(0xff283550),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: emphasized ? const Color(0xffdbe4ff) : const Color(0xff9ba8c2),
          fontSize: 10,
          fontWeight: FontWeight.w700,
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
@visibleForTesting
double playerQueueSidebarWidthForWindow(double windowWidth) {
  return (windowWidth * 0.30).clamp(360.0, 500.0).toDouble();
}

/**
 * 当前播放队列的轻量搜索框，同时支持键盘提交和可见按钮提交。
 */
class _QueueSearchField extends StatefulWidget {
  const _QueueSearchField({required this.onSearch});

  /** 仅在播放器已持有的队列中定位，不访问媒体库或触发重新扫描。 */
  final ValueChanged<String> onSearch;

  @override
  State<_QueueSearchField> createState() => _QueueSearchFieldState();
}

/** 维护搜索输入，避免把临时查询状态提升到播放器或媒体库控制器。 */
class _QueueSearchFieldState extends State<_QueueSearchField> {
  final TextEditingController _controller = TextEditingController();

  /** 提交当前查询；空查询由队列搜索规则稳定忽略。 */
  void _submit() => widget.onSearch(_controller.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('player.queueSearch'),
      controller: _controller,
      style: const TextStyle(color: Colors.white, fontSize: 12),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: '搜索当前队列并定位',
        hintStyle: const TextStyle(color: Color(0xff6f7d99)),
        prefixIcon: const Icon(Icons.search_rounded,
            size: 18, color: Color(0xff8fa0c5)),
        filled: true,
        fillColor: const Color(0xff0a1122),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xff253251)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xff7457ff)),
        ),
        suffixIcon: IconButton(
          key: const ValueKey('player.queueSearchSubmit'),
          tooltip: '定位下一条匹配视频',
          onPressed: _submit,
          icon: const Icon(Icons.my_location_rounded, size: 17),
        ),
      ),
      onSubmitted: (_) => _submit(),
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
        selected ? const Color(0xff254d7d) : const Color(0xff242832);
    final borderColor =
        selected ? const Color(0xff5d9cec) : const Color(0xff38404d);
    final textColor =
        selected ? const Color(0xffffffff) : const Color(0xffb7c0cc);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(6),
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
              fontWeight: FontWeight.w600,
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
      height: 19,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: color,
              fontSize: 10,
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
    required this.onLocatePlaying,
    required this.onLocateSelected,
  });

  final bool showPlaying;
  final bool showSelected;
  final VoidCallback onLocatePlaying;
  final VoidCallback onLocateSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: showPlaying || showSelected ? 1 : 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xee101722),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xff344369)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              if (showPlaying)
                _QueueLocatorButton(
                  icon: Icons.play_arrow_rounded,
                  label: '回到播放',
                  onPressed: onLocatePlaying,
                ),
              if (showSelected)
                _QueueLocatorButton(
                  icon: Icons.center_focus_strong_rounded,
                  label: '回到选中',
                  onPressed: onLocateSelected,
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
        foregroundColor: const Color(0xffdbe4ff),
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _QueueListItem extends StatefulWidget {
  const _QueueListItem({
    required this.item,
    required this.index,
    required this.playing,
    required this.selected,
    required this.thumbnailService,
    required this.detailsService,
    required this.onTap,
    required this.onDoubleTap,
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
   * 单击队列项时直接切换实际播放位置。
   */
  final VoidCallback onTap;

  /**
   * 双击队列项时切换实际播放位置。
   */
  final VoidCallback onDoubleTap;

  @override
  State<_QueueListItem> createState() => _QueueListItemState();
}

class _QueueListItemState extends State<_QueueListItem> {
  late Future<File?> _thumbnailFuture;
  late Future<MediaDetails> _detailsFuture;
  var _hovered = false;

  @override
  void initState() {
    super.initState();
    _loadItemFutures();
  }

  @override
  void didUpdateWidget(covariant _QueueListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.path != widget.item.path) {
      _loadItemFutures();
    }
  }

  void _loadItemFutures() {
    if (widget.item.isMissing) {
      // missing 条目不再派发文件 I/O，避免大队列对失效路径反复探测。
      _thumbnailFuture = Future<File?>.value(null);
      _detailsFuture = Future<MediaDetails>.value(const MediaDetails());
      return;
    }
    _thumbnailFuture = widget.thumbnailService.thumbnailFor(widget.item);
    _detailsFuture = widget.detailsService.detailsFor(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    final emphasis = widget.playing
        ? 3
        : widget.selected
            ? 2
            : _hovered
                ? 1
                : 0;
    final infoColor = emphasis >= 2
        ? const Color(0xffb7d3ff)
        : _hovered
            ? const Color(0xffa0aabb)
            : const Color(0xff7a8493);
    final titleColor = widget.playing
        ? const Color(0xffffffff)
        : widget.selected
            ? const Color(0xffeef2f6)
            : _hovered
                ? const Color(0xffdde4ed)
                : const Color(0xffb9c1cc);
    final backgroundColor = widget.playing
        ? const Color(0xff20204d)
        : widget.selected
            ? const Color(0xff242d3a)
            : _hovered
                ? const Color(0xff1d2530)
                : const Color(0xff151a21);
    final borderColor = widget.playing
        ? const Color(0xff7457ff)
        : widget.selected
            ? const Color(0xff52647d)
            : _hovered
                ? const Color(0xff3a4658)
                : const Color(0xff222936);
    final accentColor = widget.playing
        ? const Color(0xff8b73ff)
        : widget.selected
            ? const Color(0xffa7b4ff)
            : _hovered
                ? const Color(0xff7f8da3)
                : const Color(0xff566171);
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
        ? const Color(0xffffb4a9)
        : widget.playing
            ? const Color(0xff8b73ff)
            : const Color(0xffa7b4ff);
    final shadow = widget.playing
        ? const [
            BoxShadow(
              color: Color(0x557457ff),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ]
        : widget.selected || _hovered
            ? const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ]
            : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: _motionCurve,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
              boxShadow: shadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 3,
                  height: 60,
                  decoration: BoxDecoration(
                    color: widget.playing || widget.selected || _hovered
                        ? accentColor
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 5),
                SizedBox(
                  width: 100,
                  height: 58,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FutureBuilder<File?>(
                          future: _thumbnailFuture,
                          builder: (context, snapshot) {
                            final file = snapshot.data;
                            if (file != null && file.existsSync()) {
                              return Image.file(
                                file,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.low,
                                cacheWidth: 160,
                                gaplessPlayback: true,
                              );
                            }
                            return const ColoredBox(
                              color: Color(0xff242932),
                              child: Center(
                                child: Icon(Icons.movie_outlined,
                                    color: Color(0xff687282), size: 22),
                              ),
                            );
                          },
                        ),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 120),
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
                                  (widget.index + 1).toString().padLeft(2, '0'),
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
                                color: infoColor, fontSize: 11, height: 1.1),
                          ),
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 120),
                            opacity: showHoverAction ? 1 : 0,
                            child: const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Text(
                                '单击播放',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(0xffa7b4ff),
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
