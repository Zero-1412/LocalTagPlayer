import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/playback_settings.dart';
import '../../models/video_item.dart';
import '../../services/library/library_card_ui_diagnostics.dart';
import '../../services/media/thumbnail_service.dart';
import '../app_theme_tokens.dart';
import 'library_video_grid_layout.dart';
import 'library_video_grid_resize_coordinator.dart';
import 'library_video_results.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

class VideoGrid extends StatefulWidget {
  const VideoGrid({
    required this.videos,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.dense,
    this.columnReferenceWidth,
    this.onVisible,
    required this.onOpen,
    this.onRevealLocation,
    required this.onToggleFavorite,
    required this.onDelete,
    this.preserveScrollOnResultDelta = false,
    this.selectionMode = false,
    this.selectedVideoIds = const <String>{},
    this.onToggleSelected,
    this.scrollChromeEnabled = false,
    this.onHeaderVisibilityChanged,
  });

  final List<VideoItem> videos;

  final ThumbnailService thumbnailService;

  final PlaybackSettings playbackSettings;

  final bool dense;

  /**
   * 只用于确定响应式列数的稳定宽度。
   *
   * 页面传入扣除默认侧栏占位后的窗口基准宽度，使窗口尺寸不变时左右侧栏开合只改变
   * 卡片尺寸，不增加或减少列数；为空时独立测试和复用场景继续使用结果区实际宽度。
   */
  final double? columnReferenceWidth;

  /** 实际构建到视口附近时通知页面提升媒体详情任务，不在 build 中做磁盘访问。 */
  final ValueChanged<VideoItem>? onVisible;

  final void Function(VideoItem item, List<VideoItem> playlist) onOpen;

  /** 请求页面通过 FileSystemAdapter 定位当前卡片的视频；为空时隐藏该菜单项。 */
  final ValueChanged<VideoItem>? onRevealLocation;

  final ValueChanged<VideoItem> onToggleFavorite;

  /** 请求删除视频记录；是否同步删除本地文件由 Application 层确认。 */
  final ValueChanged<VideoItem> onDelete;

  /** 删除或列表差量发布时保留当前滚动锚点，不把结果区跳回首屏。 */
  final bool preserveScrollOnResultDelta;

  /** true 时卡片和列表点击只切换选择，不打开播放器。 */
  final bool selectionMode;

  /** 当前完整结果中已选择的稳定 videoId。 */
  final Set<String> selectedVideoIds;

  /** 切换单个视频选择状态；普通模式不调用。 */
  final ValueChanged<VideoItem>? onToggleSelected;

  /** 是否启用宽桌面结果区的滚动顶部收起和回到顶部入口。 */
  final bool scrollChromeEnabled;

  /** 结果离开或回到绝对顶部时，请求页面收起或恢复顶部信息区。 */
  final ValueChanged<bool>? onHeaderVisibilityChanged;

  @override
  State<VideoGrid> createState() => _VideoGridState();
}

class _VideoGridState extends State<VideoGrid> {
  /** 网格和列表共享一个滚动位置；追加批次时不替换控制器，避免画面跳动。 */
  late final ScrollController _scrollController;

  /** 已明确追加的条目数；首次批次会在 build 中按当前列数计算。 */
  var _loadedItemCount = 0;

  /** 当前网格列数；列表模式固定为 1，用于把 10 行换算成条目数。 */
  var _currentColumnCount = 1;

  /** 当前单行高度，用于在距离末尾 4 行时提前追加下一批。 */
  var _currentRowExtent = 120.0;

  /** 合并同一帧内的多个滚动通知，防止一次触底重复追加并引发抖动。 */
  var _loadMoreScheduled = false;

  /** 当前 Sliver 已挂载范围的稳定身份索引；只在结果引用或挂载数量变化时重建。 */
  List<VideoItem>? _indexedVideos;
  var _indexedItemCount = -1;
  Map<String, int> _visibleIndexByVideoId = const <String, int>{};

  /** 合并窗口拖动期间的响应式列数变化，不接触结果或筛选 owner。 */
  final _resizeCoordinator = LibraryVideoGridResizeCoordinator();

  /** 回到结果绝对顶部后的短暂稳定计时，避免惯性边界轻微抖动造成闪回。 */
  Timer? _headerRestoreTimer;

  /** 首次开始滚动时的结果视口高度，用于判定首屏视频是否已经全部划过。 */
  double? _initialViewportExtent;

  /** 是否已经越过首个结果视口并显示回到顶部入口。 */
  var _showReturnToTop = false;

  /** 最近一次上报给页面的顶部可见性，避免滚动像素更新重复触发父级状态。 */
  var _reportedHeaderVisible = true;

  /**
   * 用结果数量和首尾稳定身份识别筛选/排序结果变化。
   *
   * 该检查为 O(1)，避免每次收藏或媒体详情更新时扫描 11,000 条结果计算签名。
   */
  (int, String?, String?) _resultBoundarySignature(List<VideoItem> videos) => (
        videos.length,
        videos.isEmpty ? null : videos.first.videoId,
        videos.isEmpty ? null : videos.last.videoId,
      );

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.scrollChromeEnabled) {
        // 新进入 expanded 布局时主动恢复顶部，避免窗口尺寸切换继承旧隐藏态。
        widget.onHeaderVisibilityChanged?.call(true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant VideoGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final resultChanged = _resultBoundarySignature(oldWidget.videos) !=
        _resultBoundarySignature(widget.videos);
    if (resultChanged || oldWidget.dense != widget.dense) {
      if (widget.preserveScrollOnResultDelta &&
          oldWidget.dense == widget.dense) {
        _preserveResultDelta(oldWidget.videos, widget.videos);
      } else {
        // 新筛选、排序或视图模式从首批 10 行开始，并在下一帧安全回到顶部。
        _resetIncrementalResults();
      }
    }
    if (oldWidget.scrollChromeEnabled && !widget.scrollChromeEnabled) {
      _reportHeaderVisibility(true);
      if (_showReturnToTop) {
        _showReturnToTop = false;
      }
    } else if (!oldWidget.scrollChromeEnabled && widget.scrollChromeEnabled) {
      _reportedHeaderVisible = true;
      widget.onHeaderVisibilityChanged?.call(true);
    }
  }

  /** 重置为首批结果；滚动复位延后到布局完成，避免控制器尚未挂载。 */
  void _resetIncrementalResults() {
    _loadedItemCount = 0;
    _loadMoreScheduled = false;
    _initialViewportExtent = null;
    _headerRestoreTimer?.cancel();
    _reportHeaderVisibility(true);
    if (_showReturnToTop) {
      _showReturnToTop = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(0);
    });
  }

  /**
   * 结果仅发生 stable ID 差量时保留当前可见锚点。
   *
   * 删除项可能位于当前视口上方；以旧列表中的锚点视频重新定位到新索引，避免
   * Sliver 因索引收缩造成内容跳动，同时继续让 keyed child 复用未变化卡片。
   */
  void _preserveResultDelta(
    List<VideoItem> oldVideos,
    List<VideoItem> nextVideos,
  ) {
    _loadedItemCount = math.min(_loadedItemCount, nextVideos.length);
    if (oldVideos.isEmpty ||
        nextVideos.isEmpty ||
        !_scrollController.hasClients) {
      return;
    }
    final rowExtent = math.max(_currentRowExtent, 1);
    final columns = math.max(_currentColumnCount, 1);
    final offset = _scrollController.position.pixels;
    final oldRow = math.max((offset / rowExtent).floor(), 0);
    final oldAnchorIndex = math.min(
      oldVideos.length - 1,
      oldRow * columns,
    );
    var nextAnchorIndex = nextVideos.indexWhere(
      (item) => item.videoId == oldVideos[oldAnchorIndex].videoId,
    );
    if (nextAnchorIndex < 0) {
      for (var index = oldAnchorIndex + 1;
          index < oldVideos.length && nextAnchorIndex < 0;
          index += 1) {
        nextAnchorIndex = nextVideos.indexWhere(
          (item) => item.videoId == oldVideos[index].videoId,
        );
      }
    }
    if (nextAnchorIndex < 0) {
      return;
    }
    final intraRowOffset = offset - oldRow * rowExtent;
    final nextOffset =
        (nextAnchorIndex ~/ columns) * rowExtent + intraRowOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      _scrollController.jumpTo(
        nextOffset
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    });
  }

  /**
   * 返回当前已挂载范围的 videoId -> index 映射。
   *
   * Sliver 通过该映射在筛选后搬移仍存在的 Element；缓存避免媒体详情等外围 setState
   * 在连续加载数百行后反复扫描已挂载范围。
   */
  Map<String, int> _visibleIndexMap(int visibleItemCount) {
    if (identical(_indexedVideos, widget.videos) &&
        _indexedItemCount == visibleItemCount) {
      return _visibleIndexByVideoId;
    }
    _indexedVideos = widget.videos;
    _indexedItemCount = visibleItemCount;
    _visibleIndexByVideoId = <String, int>{
      for (var index = 0; index < visibleItemCount; index++)
        widget.videos[index].videoId: index,
    };
    return _visibleIndexByVideoId;
  }

  /**
   * 下滑到当前批次最后 4 行前追加 10 行，同一帧只允许调度一次。
   *
   * 追加发生在用户触底前；Sliver 仍只构建视口与 cacheExtent 附近项目，因此连续加载
   * 数百行只增长轻量 itemCount，不会同时保活数百行 Widget。
   */
  void _handleScroll() {
    _syncScrollChrome();
    _hideHeaderAwayFromTop();
    if (!_scrollController.hasClients ||
        _loadMoreScheduled ||
        widget.videos.isEmpty) {
      return;
    }
    if (LibraryCardUiDiagnostics.scrollStatsEnabled) {
      LibraryCardUiDiagnostics.recordScrollActivity(
        loadedItemCount: _loadedItemCount,
      );
    }
    final position = _scrollController.position;
    if (position.extentAfter > _currentRowExtent * libraryPreloadRowsAhead) {
      return;
    }
    final initialCount = libraryIncrementalItemCount(
      totalCount: widget.videos.length,
      currentCount: 0,
      columnCount: _currentColumnCount,
    );
    final currentCount = math.max(_loadedItemCount, initialCount).toInt();
    if (currentCount >= widget.videos.length) {
      return;
    }
    _loadMoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final nextCount = libraryIncrementalItemCount(
        totalCount: widget.videos.length,
        currentCount: currentCount,
        columnCount: _currentColumnCount,
      );
      setState(() {
        // 只扩大尾部范围，已有条目、滚动偏移和缩略图 Future 均保持稳定。
        _loadedItemCount = math.max(_loadedItemCount, nextCount).toInt();
        _loadMoreScheduled = false;
      });
      if (LibraryCardUiDiagnostics.scrollStatsEnabled) {
        LibraryCardUiDiagnostics.recordScrollActivity(
          loadedItemCount: nextCount,
        );
      }
    });
  }

  /**
   * 只在跨越首屏阈值时更新回到顶部入口。
   *
   * 该方法虽然挂在滚动监听器上，但不会逐像素调用 setState；首次视口高度固定后，
   * 只有布尔结果变化才重建当前结果组件，避免把 11,000 条列表拖入高频页面刷新。
   */
  void _syncScrollChrome() {
    if (!widget.scrollChromeEnabled || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final measuredViewport = position.viewportDimension;
    if (_initialViewportExtent == null && measuredViewport > 0) {
      _initialViewportExtent = measuredViewport;
    }
    final threshold = _initialViewportExtent;
    if (threshold == null) {
      return;
    }
    final shouldShow = position.pixels >= threshold;
    if (shouldShow != _showReturnToTop && mounted) {
      setState(() => _showReturnToTop = shouldShow);
    }
  }

  /** 向页面上报顶部信息区目标状态，同一状态不会重复触发。 */
  void _reportHeaderVisibility(bool visible) {
    if (_reportedHeaderVisible == visible) {
      return;
    }
    _reportedHeaderVisible = visible;
    widget.onHeaderVisibilityChanged?.call(visible);
  }

  /** 当前结果是否位于允许显示顶部信息区的绝对起点。 */
  bool get _isAtScrollTop =>
      _scrollController.hasClients &&
      _scrollController.position.pixels <=
          _scrollController.position.minScrollExtent + 0.5;

  /** 一旦离开绝对顶部就保持收起；同一状态由上报去重保护。 */
  void _hideHeaderAwayFromTop() {
    if (!widget.scrollChromeEnabled || _isAtScrollTop) {
      return;
    }
    _headerRestoreTimer?.cancel();
    _reportHeaderVisibility(false);
  }

  /**
   * 处理真实用户滚动：离开顶部后始终收起，仅在回到绝对顶部并稳定后恢复。
   *
   * 140ms 只合并触控板惯性在顶部边界的短暂 idle，不再让中途停留恢复 chrome。
   */
  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.scrollChromeEnabled || notification.depth != 0) {
      return false;
    }
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.idle) {
        _scheduleHeaderRestore();
      } else {
        _headerRestoreTimer?.cancel();
        // 从顶部开始向下或在中途反向时都保持收起，直到真实回到起点。
        if (notification.direction == ScrollDirection.reverse ||
            !_isAtScrollTop) {
          _reportHeaderVisibility(false);
        }
      }
    } else if (notification is ScrollEndNotification) {
      _scheduleHeaderRestore();
    }
    return false;
  }

  /** 只在结果绝对顶部稳定 140ms 后恢复，惯性滚动停在中途不会显示。 */
  void _scheduleHeaderRestore() {
    _headerRestoreTimer?.cancel();
    if (!_isAtScrollTop) {
      _reportHeaderVisibility(false);
      return;
    }
    _headerRestoreTimer = Timer(const Duration(milliseconds: 140), () {
      if (mounted && _isAtScrollTop) {
        _reportHeaderVisibility(true);
      }
    });
  }

  /** 点击浮动入口后以有上限的短动画回到结果顶部。 */
  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) {
      return;
    }
    _headerRestoreTimer?.cancel();
    final accessibility = AppAccessibilityScope.of(context);
    if (accessibility.reduceMotion) {
      _scrollController.jumpTo(0);
      _scheduleHeaderRestore();
      return;
    }
    final distance = _scrollController.position.pixels.abs();
    final milliseconds = (220 + distance / 6).clamp(220, 520).round();
    await _scrollController.animateTo(
      0,
      duration: Duration(milliseconds: milliseconds),
      curve: Curves.easeOutCubic,
    );
    _scheduleHeaderRestore();
  }

  @override
  void dispose() {
    _resizeCoordinator.dispose();
    _headerRestoreTimer?.cancel();
    if (LibraryCardUiDiagnostics.scrollStatsEnabled) {
      LibraryCardUiDiagnostics.finishScrollSample();
    }
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  /**
   * 记录最新窗口基准宽度，并在约束稳定后只提交一次重排。
   *
   * 拖动窗口会反复覆盖目标并重启计时，最终提交才更新响应式断点。侧栏动画不会改变
   * 该基准，因此只缩放卡片而不换列；视频顺序、滚动控制器和缩略图 Future 均保持不变。
   */
  double _stableViewportWidth(double measuredWidth) {
    return _resizeCoordinator.resolve(
      measuredWidth,
      onSettled: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LibraryVideoGridLayout(
      videos: widget.videos,
      thumbnailService: widget.thumbnailService,
      playbackSettings: widget.playbackSettings,
      dense: widget.dense,
      columnReferenceWidth: widget.columnReferenceWidth,
      onVisible: widget.onVisible,
      onOpen: widget.onOpen,
      onRevealLocation: widget.onRevealLocation,
      onToggleFavorite: widget.onToggleFavorite,
      onDelete: widget.onDelete,
      selectionMode: widget.selectionMode,
      selectedVideoIds: widget.selectedVideoIds,
      onToggleSelected: widget.onToggleSelected,
      scrollChromeEnabled: widget.scrollChromeEnabled,
      scrollController: _scrollController,
      loadedItemCount: _loadedItemCount,
      showReturnToTop: _showReturnToTop,
      stableViewportWidth: _stableViewportWidth,
      visibleIndexMap: _visibleIndexMap,
      onLayoutMetrics: (columnCount, rowExtent, visibleItemCount) {
        _currentColumnCount = columnCount;
        _currentRowExtent = rowExtent;
        _loadedItemCount = visibleItemCount;
      },
      onScrollNotification: _handleScrollNotification,
      onScrollToTop: _scrollToTop,
    );
  }
}
