import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../../core/layout_size.dart';
import '../../core/playback_settings.dart';
import '../../models/video_item.dart';
import '../../services/library/library_card_ui_diagnostics.dart';
import '../../services/media/thumbnail_service.dart';
import '../../services/player/media_kit_initializer.dart';
import '../app_theme_tokens.dart';
import '../design_system/app_interaction_surface.dart';
import 'library_smoke_keys.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

/**
 * 计算网格视频卡片高度。
 *
 * 卡片只保留 16:9 缩略图与两行标题；收藏和时长位于缩略图叠层，不再为标签、路径或
 * 底部操作区预留垂直空间。单列仍按更宽缩略图单独留足高度，避免窗口缩小时溢出。
 */
double libraryVideoCardMainAxisExtent({
  required double gridWidth,
  required bool narrow,
  required bool compact,
  double textScaleFactor = 1,
}) {
  final columnCount = libraryVideoGridColumnCount(
    gridWidth: gridWidth,
    narrow: narrow,
    compact: compact,
  );
  return libraryVideoCardMainAxisExtentForColumnCount(
    gridWidth: gridWidth,
    compact: compact,
    columnCount: columnCount,
    textScaleFactor: textScaleFactor,
  );
}

/**
 * 按已锁定的列数计算卡片高度。
 *
 * 侧栏动画期间列数保持不变，但结果区宽度连续变化；卡片因此能够平滑改变尺寸，
 * 不会逐帧跨越列数断点，也不会把旧宽度网格裁切到新的结果区中。[crossAxisSpacing]
 * 可由调用方传入当前锁定间距，保证高度计算与真实网格代理使用同一组几何参数。
 */
double libraryVideoCardMainAxisExtentForColumnCount({
  required double gridWidth,
  required bool compact,
  required int columnCount,
  double? crossAxisSpacing,
  double textScaleFactor = 1,
}) {
  final safeColumnCount = math.max(1, columnCount);
  final horizontalPadding = libraryVideoGridHorizontalPadding(compact);
  final spacing = crossAxisSpacing ??
      libraryVideoGridCrossAxisSpacing(
        gridWidth: gridWidth,
        compact: compact,
      );
  final usableWidth = math.max(1.0, gridWidth - horizontalPadding);
  final cardWidth =
      (usableWidth - spacing * (safeColumnCount - 1)) / safeColumnCount;
  // 标题槽位跟随系统文字缩放增长；只改变可见卡片几何，不参与网格列数或数据加载计算。
  final metadataHeight =
      libraryVideoCardMetadataHeightForTextScale(textScaleFactor);
  // 额外 2px 吸收高 DPI 下 AspectRatio 与网格像素舍入误差，避免 150% 出现亚像素溢出。
  return cardWidth * 9 / 16 + metadataHeight + 16;
}

/**
 * 卡片标题内容区固定高度。
 *
 * 一行和两行标题都占用同一垂直槽位，保证同一网格行的卡片底部、点击区域和下一行
 * 起点一致；外层 8px 顶部与 6px 底部间距仍由卡片布局单独承担。
 */
const double libraryVideoCardMetadataHeight = 42;

/**
 * 按系统文字缩放计算两行标题槽位高度。
 *
 * 100% 继续使用原始密度；125% 和 150% 只增加标题容器，不压缩缩略图，也不截断
 * 系统放大后的第二行文字。上限用于防止异常缩放把虚拟网格行高无限放大。
 */
double libraryVideoCardMetadataHeightForTextScale(double textScaleFactor) {
  final safeScale = textScaleFactor.isFinite
      ? textScaleFactor.clamp(1.0, 2.0).toDouble()
      : 1.0;
  return libraryVideoCardMetadataHeight + (safeScale - 1) * 32;
}

/** 桌面结果区略收紧左右留白，把宽度优先分配给缩略图。 */
double libraryVideoGridHorizontalPadding(bool compact) => compact ? 28 : 44;

/**
 * 计算视频网格的横向列间距。
 *
 * 窄窗口优先保证卡片宽度，超宽窗口逐步增加留白，避免高分辨率下形成密集小卡片墙。
 */
double libraryVideoGridCrossAxisSpacing({
  required double gridWidth,
  required bool compact,
}) {
  if (compact || gridWidth < 720) {
    return 10;
  }
  if (gridWidth < 1000) {
    return 12;
  }
  if (gridWidth < 1400) {
    return 16;
  }
  return 20;
}

/** 行间距与卡片标题高度配合，宽窗口增加呼吸感但不降低首屏浏览数量。 */
double libraryVideoGridMainAxisSpacing({
  required double gridWidth,
  required bool compact,
}) {
  if (compact || gridWidth < 720) {
    return 14;
  }
  if (gridWidth < 1000) {
    return 16;
  }
  if (gridWidth < 1400) {
    return 18;
  }
  return 22;
}

/** 超宽结果区适度放大卡片上限，使桌面信息密度接近内容平台而不是文件缩略图墙。 */
double libraryVideoGridMaxCrossAxisExtent({
  required double gridWidth,
  required bool narrow,
  required bool compact,
}) {
  if (narrow) {
    return 500;
  }
  if (compact) {
    return 260;
  }
  if (gridWidth < 1000) {
    return 310;
  }
  if (gridWidth < 1400) {
    return 340;
  }
  if (gridWidth < 1800) {
    return 430;
  }
  return 500;
}

/** 卡片标题按实际卡片宽度分档，保持窄卡不拥挤、宽卡不显得过小。 */
double libraryVideoCardTitleFontSize(double cardWidth) {
  if (cardWidth < 220) {
    return 13.5;
  }
  if (cardWidth < 300) {
    return 14.5;
  }
  if (cardWidth < 380) {
    return 15.5;
  }
  return 16;
}

/** 缩略图与悬停外框共用的小圆角，接近内容平台的紧凑视觉。 */
const double libraryVideoCardRadius = AppRadius.card;

/** 标题右侧更多按钮的淡入淡出时长；短过渡避免快速扫过卡片时产生闪烁。 */
const Duration libraryCardMoreFadeDuration = Duration(milliseconds: 120);

/** 媒体卡片双项菜单宽度；只容纳“打开文件 / 删除文件”，避免遮挡相邻内容。 */
const BoxConstraints libraryVideoMoreMenuConstraints = BoxConstraints(
  minWidth: 136,
  maxWidth: 156,
);

/** 媒体卡片菜单单项最小高度；保持紧凑，同时保留可用的桌面点击目标。 */
const double libraryVideoMoreMenuItemHeight = 40;

/** 媒体卡片菜单外层留白；文字缩放时条目仍可按内容向下扩展。 */
const EdgeInsets libraryVideoMoreMenuPadding =
    EdgeInsets.symmetric(vertical: 4);

/** 收藏与时长叠层的响应式视觉参数。 */
class LibraryVideoOverlayMetrics {
  const LibraryVideoOverlayMetrics({
    required this.edgeInset,
    required this.favoriteButtonSize,
    required this.favoriteIconSize,
    required this.durationFontSize,
    required this.durationHorizontalPadding,
    required this.durationVerticalPadding,
  });

  /** 叠层距离缩略图边缘的距离。 */
  final double edgeInset;

  /** 收藏按钮的视觉和桌面点击区域尺寸。 */
  final double favoriteButtonSize;

  /** 红心图标尺寸。 */
  final double favoriteIconSize;

  /** 时长文字字号。 */
  final double durationFontSize;

  /** 时长角标左右内边距。 */
  final double durationHorizontalPadding;

  /** 时长角标上下内边距。 */
  final double durationVerticalPadding;
}

/**
 * 按卡片宽度选择叠层尺寸。
 *
 * 点击区域与视觉尺寸一起分档，避免窄卡遮挡画面，同时确保桌面鼠标仍容易命中。
 */
LibraryVideoOverlayMetrics libraryVideoOverlayMetrics(double cardWidth) {
  if (cardWidth < 220) {
    return const LibraryVideoOverlayMetrics(
      edgeInset: 6,
      favoriteButtonSize: 30,
      favoriteIconSize: 17.5,
      durationFontSize: 10,
      durationHorizontalPadding: 5,
      durationVerticalPadding: 2,
    );
  }
  if (cardWidth < 380) {
    return const LibraryVideoOverlayMetrics(
      edgeInset: 7,
      favoriteButtonSize: 32,
      favoriteIconSize: 19,
      durationFontSize: 10.5,
      durationHorizontalPadding: 5.5,
      durationVerticalPadding: 2.5,
    );
  }
  return const LibraryVideoOverlayMetrics(
    edgeInset: 9,
    favoriteButtonSize: 34,
    favoriteIconSize: 20,
    durationFontSize: 11,
    durationHorizontalPadding: 6,
    durationVerticalPadding: 3,
  );
}

/** 收藏按钮底色保持完全透明，仅由红心轮廓和阴影保证亮色视频上的可见性。 */
const double libraryFavoriteOverlayOpacity = 0;

/** 时长角标使用比旧版更透明的底色，并由文字阴影补足亮色视频上的可读性。 */
const double libraryDurationOverlayOpacity = 0.56;

/** 动态预览真正显示时隐藏静态视频时长，退出预览后恢复。 */
double libraryDurationOpacityForPreview(bool previewVisible) =>
    previewVisible ? 0 : 1;

/** 缩略图占位状态；只描述展示结果，不改变生成服务的失败或重试语义。 */
enum LibraryThumbnailPlaceholderState { loading, failed, empty }

/** 深色缩略图占位背景的起止色，加载切换时与媒体库表面保持连续。 */
const Color libraryThumbnailPlaceholderTop = Color(0xff243145);
const Color libraryThumbnailPlaceholderBottom = Color(0xff182332);

/**
 * 加载中、生成异常和无可用缩略图共用的深色占位组件。
 *
 * 三种状态仅替换中心图标与文案，尺寸和背景保持一致，避免异步完成前后出现浅色闪烁。
 */
class LibraryThumbnailPlaceholder extends StatelessWidget {
  const LibraryThumbnailPlaceholder({super.key, required this.state});

  /** 当前占位原因。 */
  final LibraryThumbnailPlaceholderState state;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (state) {
      LibraryThumbnailPlaceholderState.loading => (null, '正在生成缩略图'),
      LibraryThumbnailPlaceholderState.failed => (
          Icons.broken_image_outlined,
          '缩略图生成失败'
        ),
      LibraryThumbnailPlaceholderState.empty => (Icons.movie_outlined, '暂无缩略图'),
    };
    return Container(
      key: ValueKey<String>('library-thumbnail-placeholder-${state.name}'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            libraryThumbnailPlaceholderTop,
            libraryThumbnailPlaceholderBottom,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon == null)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: appAccentViolet,
                  backgroundColor: Color(0x334b5d75),
                ),
              )
            else
              Icon(icon, size: 29, color: libraryTextMuted),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: libraryTextMuted,
                fontSize: 10.5,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/** 缩略图内部放大比例；外框尺寸不变，接近内容平台的动态聚焦效果。 */
const double libraryVideoHoverScale = 1.06;

/** hover 放大使用稍长的进入动画，快速扫过时不会出现突兀跳帧。 */
const Duration libraryVideoHoverScaleDuration = Duration(milliseconds: 220);

/** 退出略快于进入，连续跨卡片时前后动画可自然衔接。 */
const Duration libraryVideoHoverScaleReverseDuration =
    Duration(milliseconds: 170);

/**
 * 在固定裁剪框内连续缩放缩略图内容。
 *
 * AnimationController 从当前进度正向或反向运行，鼠标快速进出时不会把比例重置到动画端点；
 * 因此标题、卡片间距和 Sliver 布局完全不参与 hover 动画。
 */
class LibraryThumbnailHoverScale extends StatefulWidget {
  const LibraryThumbnailHoverScale({
    super.key,
    required this.hovered,
    required this.child,
  });

  /** 当前卡片是否处于鼠标悬停状态。 */
  final bool hovered;

  /** 只缩放静态缩略图和动态预览画面，不缩放收藏与时长角标。 */
  final Widget child;

  @override
  State<LibraryThumbnailHoverScale> createState() =>
      _LibraryThumbnailHoverScaleState();
}

class _LibraryThumbnailHoverScaleState extends State<LibraryThumbnailHoverScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: libraryVideoHoverScaleDuration,
      reverseDuration: libraryVideoHoverScaleReverseDuration,
      value: widget.hovered ? 1 : 0,
    );
    _scale = Tween<double>(
      begin: 1,
      end: libraryVideoHoverScale,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant LibraryThumbnailHoverScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hovered == widget.hovered) {
      return;
    }
    if (widget.hovered) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: _scale,
        child: widget.child,
      );
}

/** 用户稳定停留后才启动动态预览，快速掠过不会创建原生播放器。 */
const Duration libraryHoverPreviewStartDelay = Duration(milliseconds: 650);

/** 鼠标离开后先交叉淡回静态缩略图，再释放动态预览资源。 */
const Duration libraryHoverPreviewFadeDuration = Duration(milliseconds: 180);

/**
 * 将鼠标进入意图分为即时反馈和延迟预览两条路径。
 *
 * 缩略图浮动可由 [onEnter] 立即响应，原生动态预览只在连续停留达到 [startDelay] 后
 * 通过 [onIntent] 启动；离开时会取消尚未触发的任务，避免快速扫过卡片创建播放器。
 */
class LibraryHoverIntentRegion extends StatefulWidget {
  const LibraryHoverIntentRegion({
    super.key,
    required this.child,
    required this.onEnter,
    required this.onIntent,
    required this.onExit,
    this.startDelay = libraryHoverPreviewStartDelay,
  });

  /** 接收鼠标事件的缩略图内容。 */
  final Widget child;

  /** 鼠标进入时的即时回调，用于恢复正在淡出的已有预览。 */
  final VoidCallback onEnter;

  /** 连续停留达到延迟后的回调，用于创建动态预览。 */
  final VoidCallback onIntent;

  /** 鼠标离开时的即时回调，用于启动淡出或取消加载。 */
  final VoidCallback onExit;

  /** 动态预览启动前必须连续停留的时间。 */
  final Duration startDelay;

  @override
  State<LibraryHoverIntentRegion> createState() =>
      _LibraryHoverIntentRegionState();
}

class _LibraryHoverIntentRegionState extends State<LibraryHoverIntentRegion> {
  Timer? _intentTimer;

  /** 立即反馈进入状态，同时重置唯一的延迟启动任务。 */
  void _handleEnter(PointerEnterEvent _) {
    widget.onEnter();
    _intentTimer?.cancel();
    _intentTimer = Timer(widget.startDelay, widget.onIntent);
  }

  /** 离开即取消尚未触发的启动任务，防止快速掠过产生加载闪动。 */
  void _handleExit(PointerExitEvent _) {
    _intentTimer?.cancel();
    _intentTimer = null;
    widget.onExit();
  }

  @override
  void dispose() {
    _intentTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: _handleEnter,
        onExit: _handleExit,
        child: widget.child,
      );
}

/** 让原生动态预览与静态缩略图之间使用统一的短淡入淡出。 */
class LibraryHoverPreviewFade extends StatelessWidget {
  const LibraryHoverPreviewFade({
    super.key,
    required this.visible,
    required this.child,
  });

  /** 是否显示动态预览；为 false 时底层静态缩略图逐渐恢复。 */
  final bool visible;

  /** 原生动态预览纹理。 */
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: libraryHoverPreviewFadeDuration,
        curve: Curves.easeOutCubic,
        child: child,
      );
}

/** 计算当前响应式网格列数，增量加载和卡片尺寸必须复用同一结果。 */
int libraryVideoGridColumnCount({
  required double gridWidth,
  required bool narrow,
  required bool compact,
}) {
  final horizontalPadding = libraryVideoGridHorizontalPadding(compact);
  final spacing = libraryVideoGridCrossAxisSpacing(
    gridWidth: gridWidth,
    compact: compact,
  );
  final maxExtent = libraryVideoGridMaxCrossAxisExtent(
    gridWidth: gridWidth,
    narrow: narrow,
    compact: compact,
  );
  final usableWidth = math.max(1.0, gridWidth - horizontalPadding);
  return math.max(1, (usableWidth / (maxExtent + spacing)).ceil()).toInt();
}

/** 将已知媒体总时长格式化为卡片角标；未知时长不伪装成 `0:00`。 */
String libraryVideoDurationLabel(Duration duration) {
  if (duration <= Duration.zero) {
    return '--:--';
  }
  final totalSeconds = duration.inSeconds;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  final totalMinutes = totalSeconds ~/ 60;
  if (totalMinutes < 60) {
    return '$totalMinutes:$seconds';
  }
  final minutes = (totalMinutes % 60).toString().padLeft(2, '0');
  return '${totalMinutes ~/ 60}:$minutes:$seconds';
}

/** 媒体库每次增量挂载的行数；网格条目数由当前响应式列数换算。 */
const int libraryRowsPerLoad = 10;

/**
 * 距离当前批次末尾多少行时预加载下一批。
 *
 * 该值小于单批 10 行，保证只提前一批，不会在快速滚动时连续扩张到完整结果集。
 */
const int libraryPreloadRowsAhead = 4;

/** 计算首次或下一批应挂载的条目数，不得超过完整筛选结果。 */
int libraryIncrementalItemCount({
  required int totalCount,
  required int currentCount,
  required int columnCount,
}) {
  if (totalCount <= 0) {
    return 0;
  }
  final batchSize = math.max(1, columnCount).toInt() * libraryRowsPerLoad;
  return math
      .min(totalCount, math.max(currentCount, 0).toInt() + batchSize)
      .toInt();
}

/**
 * 媒体库增量滚动结果视图。
 *
 * [videos] 始终保留完整排序/筛选结果，首次和每次触底只追加 10 行可见 Widget。打开
 * 视频时仍把完整列表传给播放器，保证 filtered queue 不被增量挂载边界截断。
 */
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

  /** 最近一次用于确定响应式断点和列数的稳定窗口基准宽度。 */
  double? _settledViewportWidth;

  /** 拖动窗口时当前正在趋近的最新列数基准宽度。 */
  double? _pendingViewportWidth;

  /** 窗口宽度停止变化后提交唯一一次网格重排。 */
  Timer? _viewportResizeTimer;

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
      // 新筛选、排序或视图模式从首批 10 行开始，并在下一帧安全回到顶部。
      _resetIncrementalResults();
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

  /** 构建不遮挡滚动条的右下角回到顶部浮动入口。 */
  Widget _buildReturnToTopButton(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    final motionDuration =
        accessibility.motionDuration(const Duration(milliseconds: 180));
    final fadeDuration =
        accessibility.fadeDuration(const Duration(milliseconds: 160));
    return Positioned(
      right: 20,
      bottom: 20,
      child: ExcludeFocus(
        excluding: !_showReturnToTop,
        child: ExcludeSemantics(
          excluding: !_showReturnToTop,
          child: IgnorePointer(
            ignoring: !_showReturnToTop,
            child: AnimatedSlide(
              offset: _showReturnToTop ? Offset.zero : const Offset(0, 0.28),
              duration: motionDuration,
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _showReturnToTop ? 1 : 0,
                duration: fadeDuration,
                curve: Curves.easeOutCubic,
                child: Tooltip(
                  message: '回到顶部',
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: librarySoftShadow,
                    ),
                    child: AppInteractionSurface(
                      key: LibrarySmokeKeys.returnToTopButton,
                      onTap: _scrollToTop,
                      semanticLabel: '回到媒体库顶部',
                      padding: EdgeInsets.zero,
                      borderRadius: 22,
                      backgroundColor: librarySurface,
                      showBorder: false,
                      child: const SizedBox.square(
                        dimension: 44,
                        child: Icon(
                          Icons.keyboard_arrow_up_rounded,
                          size: 28,
                          color: libraryAccent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _viewportResizeTimer?.cancel();
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
    final normalizedWidth =
        measuredWidth.isFinite && measuredWidth > 0 ? measuredWidth : 1.0;
    final settledWidth = _settledViewportWidth;
    if (settledWidth == null) {
      _settledViewportWidth = normalizedWidth;
      return normalizedWidth;
    }
    if ((normalizedWidth - settledWidth).abs() <= 0.5) {
      _pendingViewportWidth = null;
      _viewportResizeTimer?.cancel();
      return settledWidth;
    }
    if (_pendingViewportWidth == null ||
        (normalizedWidth - _pendingViewportWidth!).abs() > 0.5) {
      _pendingViewportWidth = normalizedWidth;
      _viewportResizeTimer?.cancel();
      _viewportResizeTimer = Timer(libraryResultsResizeSettleDuration, () {
        final targetWidth = _pendingViewportWidth;
        if (!mounted || targetWidth == null) {
          return;
        }
        setState(() {
          _settledViewportWidth = targetWidth;
          _pendingViewportWidth = null;
        });
      });
    }
    return settledWidth;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final measuredWidth = constraints.maxWidth;
        final referenceWidth = widget.columnReferenceWidth ?? measuredWidth;
        final stableWidth = _stableViewportWidth(referenceWidth);
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
        final columnCount = widget.dense
            ? 1
            : libraryVideoGridColumnCount(
                gridWidth: stableWidth,
                narrow: narrow,
                compact: compact,
              );
        final rowExtent = widget.dense
            ? (narrow ? 132.0 : 120.0)
            : libraryVideoCardMainAxisExtentForColumnCount(
                  gridWidth: measuredWidth,
                  compact: compact,
                  columnCount: columnCount,
                  crossAxisSpacing: crossAxisSpacing,
                  textScaleFactor: textScaleFactor,
                ) +
                mainAxisSpacing;
        _currentColumnCount = columnCount;
        _currentRowExtent = rowExtent;
        final initialCount = libraryIncrementalItemCount(
          totalCount: widget.videos.length,
          currentCount: 0,
          columnCount: columnCount,
        );
        // 窗口改变列数时只允许扩大首批范围，不能让已显示卡片倒退消失。
        final visibleItemCount = math
            .min(
              widget.videos.length,
              math.max(_loadedItemCount, initialCount),
            )
            .toInt();
        // 同步真实首批数量，供预加载阈值和显式压测统计使用；不触发额外 build。
        _loadedItemCount = visibleItemCount;
        final visibleIndexByVideoId = _visibleIndexMap(visibleItemCount);
        final Widget results;
        if (widget.dense) {
          results = ListView.builder(
            key: LibrarySmokeKeys.incrementalResults,
            controller: _scrollController,
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
              final item = widget.videos[index];
              return Padding(
                key: ValueKey<String>(item.videoId),
                padding: const EdgeInsets.only(bottom: 8),
                child: InteractiveVideoListRow(
                  item: item,
                  thumbnailService: widget.thumbnailService,
                  playbackSettings: widget.playbackSettings,
                  onVisible: widget.onVisible,
                  onOpen: () => widget.onOpen(item, widget.videos),
                  onRevealLocation: widget.onRevealLocation == null
                      ? null
                      : () => widget.onRevealLocation!(item),
                  onToggleFavorite: () => widget.onToggleFavorite(item),
                  onDelete: () => widget.onDelete(item),
                  selectionMode: widget.selectionMode,
                  selected: widget.selectedVideoIds.contains(item.videoId),
                  onToggleSelected: widget.onToggleSelected == null
                      ? null
                      : () => widget.onToggleSelected!(item),
                ),
              );
            },
          );
        } else {
          results = GridView.builder(
            key: LibrarySmokeKeys.incrementalResults,
            controller: _scrollController,
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
              final item = widget.videos[index];
              return KeyedSubtree(
                key: ValueKey<String>(item.videoId),
                child: InteractiveVideoCard(
                  item: item,
                  thumbnailService: widget.thumbnailService,
                  playbackSettings: widget.playbackSettings,
                  onVisible: widget.onVisible,
                  onOpen: () => widget.onOpen(item, widget.videos),
                  onRevealLocation: widget.onRevealLocation == null
                      ? null
                      : () => widget.onRevealLocation!(item),
                  onToggleFavorite: () => widget.onToggleFavorite(item),
                  onDelete: () => widget.onDelete(item),
                  selectionMode: widget.selectionMode,
                  selected: widget.selectedVideoIds.contains(item.videoId),
                  onToggleSelected: widget.onToggleSelected == null
                      ? null
                      : () => widget.onToggleSelected!(item),
                ),
              );
            },
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: AnimatedOpacity(
                  opacity: resizing ? 0.97 : 1,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  child: results,
                ),
              ),
            ),
            if (widget.scrollChromeEnabled) _buildReturnToTopButton(context),
          ],
        );
      },
    );
  }
}

/**
 * 列表模式下的单条视频结果。
 *
 * 行内容限制在可读宽度内，避免超宽桌面窗口把“播放 / 收藏 / 更多”
 * 操作区推到视线外，导致入口存在但真实点击和视觉发现都不稳定。
 */
class InteractiveVideoListRow extends StatelessWidget {
  const InteractiveVideoListRow({
    required this.item,
    required this.thumbnailService,
    required this.playbackSettings,
    this.onVisible,
    required this.onOpen,
    this.onRevealLocation,
    required this.onToggleFavorite,
    required this.onDelete,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelected,
  });

  final VideoItem item;

  final ThumbnailService thumbnailService;

  final PlaybackSettings playbackSettings;

  /** 当前行进入真实构建范围时的轻量优先级通知。 */
  final ValueChanged<VideoItem>? onVisible;

  final VoidCallback onOpen;

  /** 通过页面注入的平台边界在文件管理器中定位当前行的视频文件。 */
  final VoidCallback? onRevealLocation;

  final VoidCallback onToggleFavorite;

  final VoidCallback onDelete;

  /** 多选模式下整行点击只切换选择。 */
  final bool selectionMode;

  /** 当前行是否已选择。 */
  final bool selected;

  /** 多选状态切换回调。 */
  final VoidCallback? onToggleSelected;

  @override
  Widget build(BuildContext context) {
    final tags = item.tags.toList()..sort();
    return Material(
      key: LibrarySmokeKeys.videoListRow(item.path),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: selectionMode ? onToggleSelected : null,
        onDoubleTap: selectionMode ? null : onOpen,
        child: Ink(
          decoration: BoxDecoration(
            color: librarySurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: libraryBorder),
          ),
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;
              final thumbnailWidth = narrow ? 116.0 : 146.0;
              final showMediaSummary = constraints.maxWidth >= 1050;
              final showWideTagColumn = constraints.maxWidth >= 1500;
              final visibleTagCount = constraints.maxWidth >= 1300
                  ? 8
                  : narrow
                      ? 2
                      : 4;
              // 中等宽度窗口下右侧标签面板会压缩列表列宽；行按钮应先降级为图标，
              // 而不是继续保留 276px 操作区导致整行底部出现 overflow 条纹。
              final compactActions = constraints.maxWidth < 700;
              return Row(
                children: [
                  if (selectionMode) ...[
                    Checkbox(
                      key: LibrarySmokeKeys.cardSelection(item.path),
                      value: selected,
                      onChanged: onToggleSelected == null
                          ? null
                          : (_) => onToggleSelected!(),
                      shape: const CircleBorder(),
                      activeColor: appAccentViolet,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 8),
                  ],
                  SizedBox(
                    width: thumbnailWidth,
                    child: _VideoPreview(
                      item: item,
                      thumbnailService: thumbnailService,
                      playbackSettings: playbackSettings,
                      onVisible: onVisible,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.title,
                          maxLines: narrow ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: libraryText,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.folder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: libraryTextMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!showWideTagColumn) ...[
                          const SizedBox(height: 8),
                          _ListTagSummary(
                            tags: tags,
                            visibleTagCount: visibleTagCount,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (showWideTagColumn) ...[
                    // 最大化超宽窗口把标签提升为独立列，避免标题和媒体信息之间形成空带。
                    SizedBox(
                      width: math.min(480, constraints.maxWidth * 0.22),
                      child: _ListTagSummary(
                        tags: tags,
                        visibleTagCount: visibleTagCount,
                        showLabel: true,
                      ),
                    ),
                    const SizedBox(width: 20),
                  ],
                  if (showMediaSummary) ...[
                    // 超宽列表把既有媒体详情转成固定信息列，填补横向空白但不触发新探测。
                    SizedBox(
                      width: 230,
                      child: _ListMediaSummary(item: item),
                    ),
                    const SizedBox(width: 16),
                  ],
                  if (!selectionMode)
                    _ListRowActions(
                      item: item,
                      onOpen: onOpen,
                      onToggleFavorite: onToggleFavorite,
                      onRevealLocation: onRevealLocation,
                      onDelete: onDelete,
                      compact: compactActions,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/** 列表行标签摘要；超宽模式可显示列标题，普通模式继续使用原紧凑横向 pills。 */
class _ListTagSummary extends StatelessWidget {
  const _ListTagSummary({
    required this.tags,
    required this.visibleTagCount,
    this.showLabel = false,
  });

  /** 已排序标签名称。 */
  final List<String> tags;

  /** 当前响应式宽度允许直接展示的标签数。 */
  final int visibleTagCount;

  /** 是否在超宽独立列中显示“标签”提示。 */
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          const Text(
            '标签',
            style: TextStyle(
              color: libraryTextMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
        ],
        SizedBox(
          height: 24,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (tags.isEmpty)
                const _ListTagPill(label: '\u672a\u6dfb\u52a0\u6807\u7b7e')
              else ...[
                for (final tag in tags.take(visibleTagCount))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _ListTagPill(label: tag),
                  ),
                if (tags.length > visibleTagCount)
                  _ListTagPill(
                    label: '+${tags.length - visibleTagCount}',
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/** 超宽列表复用已缓存媒体详情和文件大小，不在 build 阶段访问磁盘。 */
class _ListMediaSummary extends StatelessWidget {
  const _ListMediaSummary({required this.item});

  /** 当前列表行的视频；只读取内存字段。 */
  final VideoItem item;

  @override
  Widget build(BuildContext context) {
    final details = item.mediaDetails;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          details?.videoLabel ?? '媒体信息读取中',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: libraryText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${details?.audioLabel ?? '音频信息读取中'} · '
          '${libraryVideoFileSizeLabel(item.fileSize)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: libraryTextMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/** 把内存中的文件大小转换为列表紧凑标签；未知值不伪造为 0 B。 */
String libraryVideoFileSizeLabel(int? bytes) {
  if (bytes == null || bytes < 0) {
    return '大小读取中';
  }
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

class _ListTagPill extends StatelessWidget {
  const _ListTagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: libraryBorder),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: libraryTextMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ListRowActions extends StatelessWidget {
  const _ListRowActions({
    required this.item,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onRevealLocation,
    required this.onDelete,
    required this.compact,
  });

  final VideoItem item;

  final VoidCallback onOpen;

  final VoidCallback onToggleFavorite;

  final VoidCallback? onRevealLocation;

  final VoidCallback onDelete;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: compact ? 112 : 276,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!compact) ...[
            Semantics(
              button: true,
              label: LibrarySmokeSemantics.videoPlay(item),
              child: SizedBox(
                width: 78,
                height: 34,
                child: GestureDetector(
                  key: LibrarySmokeKeys.listPlay(item.path),
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpen,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: appAccentViolet,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow_rounded,
                            size: 18, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          '\u64ad\u653e',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Semantics(
            button: true,
            label: LibrarySmokeSemantics.videoFavorite(item),
            selected: item.isFavorite,
            child: IconButton.outlined(
              key: LibrarySmokeKeys.listFavorite(item.path),
              tooltip: item.isFavorite
                  ? '\u53d6\u6d88\u6536\u85cf'
                  : '\u6dfb\u52a0\u6536\u85cf',
              onPressed: onToggleFavorite,
              icon: Icon(
                  item.isFavorite ? Icons.favorite : Icons.favorite_border),
              style: IconButton.styleFrom(
                fixedSize: const Size(34, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: LibrarySmokeSemantics.videoMore(item),
            child: _VideoMoreButton(
              key: LibrarySmokeKeys.listMore(item.path),
              onRevealLocation: onRevealLocation,
              onDelete: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

class InteractiveVideoCard extends StatefulWidget {
  const InteractiveVideoCard({
    required this.item,
    required this.thumbnailService,
    required this.playbackSettings,
    this.onVisible,
    required this.onOpen,
    this.onRevealLocation,
    required this.onToggleFavorite,
    this.onDelete,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelected,
    this.mediaKitInitializer,
  });

  final VideoItem item;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  /** 当前卡片进入真实构建范围时的轻量优先级通知。 */
  final ValueChanged<VideoItem>? onVisible;
  final VoidCallback onOpen;
  /** 标题更多菜单的打开文件入口；平台调用仍由页面层负责。 */
  final VoidCallback? onRevealLocation;
  final VoidCallback onToggleFavorite;
  /** 标题更多菜单的删除入口；为空时不显示卡片更多按钮。 */
  final VoidCallback? onDelete;

  /** 多选模式下卡片点击只切换选择，并关闭动态预览和更多菜单。 */
  final bool selectionMode;

  /** 当前卡片是否已选择。 */
  final bool selected;

  /** 切换当前卡片选择状态。 */
  final VoidCallback? onToggleSelected;

  /** 只供回归测试注入初始化失败；生产路径始终使用进程级默认门禁。 */
  @visibleForTesting
  final MediaKitInitializer? mediaKitInitializer;

  @override
  State<InteractiveVideoCard> createState() => InteractiveVideoCardState();
}

class InteractiveVideoCardState extends State<InteractiveVideoCard> {
  var _hovered = false;
  var _focused = false;
  var _pressed = false;
  var _moreMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final accessibility = AppAccessibilityScope.of(context);
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1);
    final supportsMoreActions =
        !widget.selectionMode && widget.onDelete != null;
    // 标题宽度始终为按钮保留固定槽位；显示状态变化不会触发标题重新换行和卡片抖动。
    final showMore =
        supportsMoreActions && (_hovered || _focused || _moreMenuOpen);
    return LibraryCardUiDiagnostics.buildSubtree(
      'card_shell',
      () => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          child: AnimatedScale(
            duration: accessibility.motionDuration(appMotionDuration),
            curve: appMotionCurve,
            scale: _pressed ? 0.992 : 1,
            child: AnimatedContainer(
              duration: accessibility.fadeDuration(appMotionDuration),
              curve: appMotionCurve,
              decoration: BoxDecoration(
                color: librarySurface,
                borderRadius: BorderRadius.circular(libraryVideoCardRadius),
                border: Border.all(
                  color: widget.selected
                      ? appAccentViolet
                      : _focused
                          ? appAccentViolet.withValues(alpha: 0.78)
                          : _hovered
                              ? libraryTextMuted.withValues(alpha: 0.42)
                              : libraryBorder.withValues(alpha: 0.72),
                  width: widget.selected || _focused ? 1.5 : 1,
                ),
                boxShadow: _hovered && !accessibility.highContrast
                    ? const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x30000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(libraryVideoCardRadius),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: LibrarySmokeKeys.cardOpen(item.path),
                  borderRadius: BorderRadius.circular(libraryVideoCardRadius),
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  onFocusChange: (focused) =>
                      setState(() => _focused = focused),
                  // 多选期间点击只更新选择；普通状态才打开完整 filtered queue。
                  onTap: widget.selectionMode
                      ? widget.onToggleSelected
                      : widget.onOpen,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KeyedSubtree(
                        key: LibrarySmokeKeys.cardThumbnailSurface(item.path),
                        child: _VideoPreview(
                          item: item,
                          thumbnailService: widget.thumbnailService,
                          playbackSettings: widget.playbackSettings,
                          hovered: _hovered && !widget.selectionMode,
                          hoverPreviewEnabled: !widget.selectionMode,
                          onVisible: widget.onVisible,
                          onToggleFavorite: widget.selectionMode
                              ? null
                              : widget.onToggleFavorite,
                          selected:
                              widget.selectionMode ? widget.selected : null,
                          onToggleSelected: widget.selectionMode
                              ? widget.onToggleSelected
                              : null,
                          mediaKitInitializer: widget.mediaKitInitializer,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
                        child: SizedBox(
                          height: libraryVideoCardMetadataHeightForTextScale(
                            textScaleFactor,
                          ),
                          child: _VideoCardMetadata(
                            item: item,
                            showMore: showMore,
                            onMoreOpened: () =>
                                setState(() => _moreMenuOpen = true),
                            onMoreClosed: () =>
                                setState(() => _moreMenuOpen = false),
                            onRevealLocation: widget.selectionMode
                                ? null
                                : widget.onRevealLocation,
                            onDelete:
                                widget.selectionMode ? null : widget.onDelete,
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
      ),
    );
  }
}

/**
 * 卡片标题子树。
 *
 * 路径和标签已移除以提高浏览密度；标题右侧固定预留更多按钮槽位，按钮仅在卡片
 * hover、键盘焦点或菜单展开期间可见，避免出现时推动标题换行。
 */
class _VideoCardMetadata extends StatelessWidget {
  const _VideoCardMetadata({
    required this.item,
    required this.showMore,
    required this.onMoreOpened,
    required this.onMoreClosed,
    required this.onRevealLocation,
    required this.onDelete,
  });

  final VideoItem item;
  final bool showMore;
  final VoidCallback onMoreOpened;
  final VoidCallback onMoreClosed;
  final VoidCallback? onRevealLocation;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => LibraryCardUiDiagnostics.buildSubtree(
        'metadata',
        () => LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: libraryText,
                        fontSize:
                            libraryVideoCardTitleFontSize(constraints.maxWidth),
                        fontWeight: FontWeight.w600,
                        height: 1.28,
                        letterSpacing: 0.05,
                      ),
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 2),
                SizedBox(
                  width: 28,
                  height: 32,
                  child: ExcludeFocus(
                    excluding: !showMore,
                    child: ExcludeSemantics(
                      excluding: !showMore,
                      child: IgnorePointer(
                        ignoring: !showMore,
                        child: AnimatedOpacity(
                          opacity: showMore ? 1 : 0,
                          duration: libraryCardMoreFadeDuration,
                          curve: Curves.easeOutCubic,
                          child: _VideoCardMoreButton(
                            key: LibrarySmokeKeys.cardMore(item.path),
                            onOpened: onMoreOpened,
                            onClosed: onMoreClosed,
                            onRevealLocation: onRevealLocation,
                            onDelete: onDelete!,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

/**
 * 网格卡片标题右侧的悬停更多菜单。
 *
 * 菜单展开时通过 [onOpened] 保持按钮可见；选择或取消后先通知卡片关闭状态，再把
 * 业务动作交还页面层。菜单只保留定位当前文件与删除，删除仍经过页面确认弹窗。
 */
class _VideoCardMoreButton extends StatelessWidget {
  const _VideoCardMoreButton({
    super.key,
    required this.onOpened,
    required this.onClosed,
    required this.onRevealLocation,
    required this.onDelete,
  });

  final VoidCallback onOpened;
  final VoidCallback onClosed;
  final VoidCallback? onRevealLocation;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_VideoMoreAction>(
      tooltip: '更多操作',
      icon: const Icon(Icons.more_vert_rounded, size: 21),
      position: PopupMenuPosition.under,
      offset: const Offset(0, -2),
      color: librarySurfaceAlt,
      elevation: 8,
      constraints: libraryVideoMoreMenuConstraints,
      menuPadding: libraryVideoMoreMenuPadding,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: libraryBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      onOpened: onOpened,
      onCanceled: onClosed,
      itemBuilder: (context) => [
        if (onRevealLocation != null)
          const PopupMenuItem(
            key: LibrarySmokeKeys.videoMoreRevealLocation,
            value: _VideoMoreAction.revealLocation,
            height: libraryVideoMoreMenuItemHeight,
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.folder_open_rounded, size: 19),
                SizedBox(width: 8),
                Text('打开文件'),
              ],
            ),
          ),
        const PopupMenuItem(
          key: LibrarySmokeKeys.videoMoreDelete,
          value: _VideoMoreAction.delete,
          height: libraryVideoMoreMenuItemHeight,
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 19,
                color: Color(0xffe26573),
              ),
              SizedBox(width: 8),
              Text('删除文件', style: TextStyle(color: Color(0xffe26573))),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        onClosed();
        switch (value) {
          case _VideoMoreAction.revealLocation:
            onRevealLocation?.call();
            break;
          case _VideoMoreAction.delete:
            onDelete();
            break;
        }
      },
      style: IconButton.styleFrom(
        foregroundColor: libraryTextMuted,
        fixedSize: const Size(28, 28),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _VideoMoreButton extends StatelessWidget {
  const _VideoMoreButton({
    super.key,
    required this.onRevealLocation,
    required this.onDelete,
  });

  final VoidCallback? onRevealLocation;

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_VideoMoreAction>(
      tooltip: '更多操作',
      icon: const Icon(Icons.more_horiz_rounded),
      position: PopupMenuPosition.under,
      color: librarySurfaceAlt,
      elevation: 8,
      constraints: libraryVideoMoreMenuConstraints,
      menuPadding: libraryVideoMoreMenuPadding,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: libraryBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      itemBuilder: (context) => [
        if (onRevealLocation != null)
          const PopupMenuItem(
            key: LibrarySmokeKeys.videoMoreRevealLocation,
            value: _VideoMoreAction.revealLocation,
            height: libraryVideoMoreMenuItemHeight,
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.folder_open_rounded, size: 19),
                SizedBox(width: 8),
                Text('打开文件'),
              ],
            ),
          ),
        const PopupMenuItem(
          key: LibrarySmokeKeys.videoMoreDelete,
          value: _VideoMoreAction.delete,
          height: libraryVideoMoreMenuItemHeight,
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 19,
                color: Color(0xffe26573),
              ),
              SizedBox(width: 8),
              Text('删除文件', style: TextStyle(color: Color(0xffe26573))),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case _VideoMoreAction.revealLocation:
            onRevealLocation?.call();
            break;
          case _VideoMoreAction.delete:
            onDelete();
            break;
        }
      },
      style: IconButton.styleFrom(
        fixedSize: const Size(34, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/** 媒体卡片更多菜单只保留文件级动作，避免与详情页的标签和改名入口重复。 */
enum _VideoMoreAction { revealLocation, delete }

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({
    required this.item,
    required this.thumbnailService,
    required this.playbackSettings,
    this.hovered = false,
    this.hoverPreviewEnabled = true,
    this.onVisible,
    this.onToggleFavorite,
    this.selected,
    this.onToggleSelected,
    this.mediaKitInitializer,
  });

  final VideoItem item;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  /** 网格卡片 hover 状态；列表预览保持 false，不引入额外动画。 */
  final bool hovered;
  /** 多选模式关闭动态预览，避免选择过程中创建原生播放器和画面干扰。 */
  final bool hoverPreviewEnabled;
  /** 只通知页面提升媒体详情任务；缩略图仍由共享服务自身的优先队列处理。 */
  final ValueChanged<VideoItem>? onVisible;

  /** 网格卡片传入时在缩略图左上角显示收藏入口；列表预览保持原有紧凑动作区。 */
  final VoidCallback? onToggleFavorite;

  /** 非 null 表示多选模式，并作为圆形复选框当前值。 */
  final bool? selected;

  /** 多选模式切换回调；与 [selected] 同时存在时替换收藏红心。 */
  final VoidCallback? onToggleSelected;

  /** 悬停预览创建 Player 前使用的初始化门禁。 */
  final MediaKitInitializer? mediaKitInitializer;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late Future<File?> _future;
  Timer? _hoverExitTimer;
  Player? _hoverPlayer;
  VideoController? _hoverController;
  var _isHoverPreviewLoading = false;
  var _isHoverPreviewReady = false;
  var _isHoverPreviewVisible = false;

  @override
  void initState() {
    super.initState();
    _future = widget.thumbnailService.ensureThumbnailFor(widget.item);
    widget.onVisible?.call(widget.item);
  }

  @override
  void didUpdateWidget(covariant _VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hoverPreviewEnabled && !widget.hoverPreviewEnabled) {
      _stopHoverPreview();
    }
    if (oldWidget.item.path != widget.item.path ||
        oldWidget.thumbnailService != widget.thumbnailService) {
      _stopHoverPreview();
      _future = widget.thumbnailService.ensureThumbnailFor(widget.item);
      widget.onVisible?.call(widget.item);
    }
  }

  @override
  void dispose() {
    _hoverExitTimer?.cancel();
    unawaited(_disposeHoverPlayer());
    super.dispose();
  }

  /** 重新进入正在淡出的预览时复用现有播放器，避免边缘移动反复初始化。 */
  void _onEnter() {
    if (!widget.hoverPreviewEnabled) {
      return;
    }
    _hoverExitTimer?.cancel();
    _hoverExitTimer = null;
    if (_isHoverPreviewReady && !_isHoverPreviewVisible && mounted) {
      setState(() => _isHoverPreviewVisible = true);
    }
  }

  /** 已显示的预览先淡出；尚在加载的预览直接取消，避免离开后才闪出首帧。 */
  void _onExit() {
    if (_isHoverPreviewReady && _hoverPlayer != null) {
      setState(() => _isHoverPreviewVisible = false);
      _hoverExitTimer?.cancel();
      _hoverExitTimer = Timer(
        libraryHoverPreviewFadeDuration,
        _stopHoverPreview,
      );
      return;
    }
    _stopHoverPreview();
  }

  /** 创建静音原生播放器，并仅在当前卡片仍持有该播放器时展示首帧。 */
  Future<void> _startHoverPreview() async {
    if (!mounted ||
        !widget.hoverPreviewEnabled ||
        _hoverPlayer != null ||
        _isHoverPreviewLoading) {
      return;
    }
    setState(() => _isHoverPreviewLoading = true);
    Player? player;
    try {
      // 上次为避免首帧前阻塞将 media_kit 改为延迟初始化；悬停
      // 预览也是真实 Player 消费者，必须与正式播放共用同一门禁。
      (widget.mediaKitInitializer ?? defaultMediaKitInitializer)
          .ensureInitialized();
      if (!mounted || !widget.hoverPreviewEnabled) {
        if (mounted) {
          setState(() => _isHoverPreviewLoading = false);
        }
        return;
      }
      player = Player(
        configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
      );
      final controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          width: 640,
          height: 360,
          hwdec: widget.playbackSettings.hwdec,
          enableHardwareAcceleration:
              widget.playbackSettings.hardwareDecodingEnabled,
        ),
      );

      _hoverPlayer = player;
      _hoverController = controller;
      await player.setVolume(0);
      await player.open(Media(widget.item.path), play: true).timeout(
            const Duration(seconds: 10),
          );
      await controller.platform.future
          .then((platform) => platform.waitUntilFirstFrameRendered)
          .timeout(const Duration(seconds: 8), onTimeout: () {});
      if (!mounted || _hoverPlayer != player) {
        await player.dispose();
        return;
      }
      setState(() {
        _isHoverPreviewLoading = false;
        _isHoverPreviewReady = true;
        _isHoverPreviewVisible = true;
      });
    } catch (error) {
      if (_hoverPlayer == player) {
        _hoverPlayer = null;
        _hoverController = null;
      }
      if (player != null) {
        await player.dispose();
      }
      if (mounted) {
        setState(() {
          _isHoverPreviewLoading = false;
          _isHoverPreviewReady = false;
          _isHoverPreviewVisible = false;
        });
      }
      // 只记录文件名与错误，不输出用户完整媒体路径。
      debugPrint(
        'LIBRARY_HOVER_PREVIEW status=failed '
        'file=${p.basename(widget.item.path)} error=$error',
      );
    }
  }

  /** 取消淡出计时并释放当前卡片独占的动态预览资源。 */
  void _stopHoverPreview() {
    _hoverExitTimer?.cancel();
    _hoverExitTimer = null;
    final player = _hoverPlayer;
    _hoverPlayer = null;
    _hoverController = null;
    if (mounted) {
      setState(() {
        _isHoverPreviewLoading = false;
        _isHoverPreviewReady = false;
        _isHoverPreviewVisible = false;
      });
    }
    if (player != null) {
      unawaited(player.dispose());
    }
  }

  Future<void> _disposeHoverPlayer() async {
    final player = _hoverPlayer;
    _hoverPlayer = null;
    _hoverController = null;
    if (player != null) {
      await player.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoverController = _hoverController;
    return LibraryCardUiDiagnostics.buildSubtree(
      'preview',
      () => LibraryHoverIntentRegion(
        key: ValueKey<String>('hover-intent:${widget.item.path}'),
        onEnter: _onEnter,
        onIntent: () => unawaited(_startHoverPreview()),
        onExit: _onExit,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final overlay = libraryVideoOverlayMetrics(constraints.maxWidth);
            return ClipRRect(
              borderRadius: BorderRadius.circular(libraryVideoCardRadius),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    LibraryThumbnailHoverScale(
                      key: LibrarySmokeKeys.cardThumbnailZoom(widget.item.path),
                      hovered: widget.hovered,
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          FutureBuilder<File?>(
                            key: ValueKey(widget.item.path),
                            future: _future,
                            // 已在本进程验证过的 JPEG 直接用于首帧；Future 继续负责缓存失效后的
                            // 异步校验/生成，筛选重排时不再先闪回加载占位。
                            initialData: widget.thumbnailService
                                .cachedThumbnailFor(widget.item),
                            builder: (context, snapshot) {
                              final file = snapshot.data;
                              // Future 完成前已验证 JPEG 存在性与完整性，build 阶段不再同步 stat。
                              if (file != null) {
                                return Image.file(
                                  file,
                                  key: ValueKey(file.path),
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.medium,
                                  gaplessPlayback: true,
                                  // 历史 fallback 缓存中仍有 4K JPEG，按卡片尺寸解码避免占用数十 MiB。
                                  cacheWidth: libraryThumbnailWidth,
                                );
                              }
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const LibraryThumbnailPlaceholder(
                                  state:
                                      LibraryThumbnailPlaceholderState.loading,
                                );
                              }
                              if (snapshot.hasError) {
                                return const LibraryThumbnailPlaceholder(
                                  state:
                                      LibraryThumbnailPlaceholderState.failed,
                                );
                              }
                              return const LibraryThumbnailPlaceholder(
                                state: LibraryThumbnailPlaceholderState.empty,
                              );
                            },
                          ),
                          if (_isHoverPreviewReady && hoverController != null)
                            LibraryHoverPreviewFade(
                              key: LibrarySmokeKeys.cardHoverPreview(
                                widget.item.path,
                              ),
                              visible: _isHoverPreviewVisible,
                              child: Video(
                                controller: hoverController,
                                controls: NoVideoControls,
                                fit: BoxFit.cover,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.02),
                              Colors.black.withValues(alpha: 0.34),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_isHoverPreviewLoading)
                      Center(
                        key: LibrarySmokeKeys.cardHoverPreviewLoading(
                          widget.item.path,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.64),
                            shape: BoxShape.circle,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(18),
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: appAccentViolet,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (widget.selected != null &&
                        widget.onToggleSelected != null)
                      Positioned(
                        top: overlay.edgeInset,
                        left: overlay.edgeInset,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.28),
                            shape: BoxShape.circle,
                          ),
                          child: Checkbox(
                            key: LibrarySmokeKeys.cardSelection(
                              widget.item.path,
                            ),
                            value: widget.selected,
                            onChanged: (_) => widget.onToggleSelected!(),
                            shape: const CircleBorder(),
                            activeColor: appAccentViolet,
                            checkColor: Colors.white,
                            side: const BorderSide(
                              color: Colors.white,
                              width: 1.6,
                            ),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      )
                    else if (widget.onToggleFavorite != null)
                      Positioned(
                        top: overlay.edgeInset,
                        left: overlay.edgeInset,
                        child: Semantics(
                          button: true,
                          selected: widget.item.isFavorite,
                          label:
                              LibrarySmokeSemantics.videoFavorite(widget.item),
                          child: IconButton(
                            key:
                                LibrarySmokeKeys.cardFavorite(widget.item.path),
                            tooltip: widget.item.isFavorite ? '取消收藏' : '添加收藏',
                            onPressed: widget.onToggleFavorite,
                            icon: Icon(
                              widget.item.isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: overlay.favoriteIconSize,
                              shadows: const <Shadow>[
                                Shadow(
                                  color: Color(0x99000000),
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              hoverColor: Colors.transparent,
                              focusColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                              foregroundColor: widget.item.isFavorite
                                  ? const Color(0xffff5a6f)
                                  : Colors.white.withValues(alpha: 0.94),
                              fixedSize:
                                  Size.square(overlay.favoriteButtonSize),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: overlay.edgeInset,
                      bottom: overlay.edgeInset,
                      child: AnimatedOpacity(
                        key: LibrarySmokeKeys.cardDuration(widget.item.path),
                        opacity: libraryDurationOpacityForPreview(
                          _isHoverPreviewVisible,
                        ),
                        duration: libraryHoverPreviewFadeDuration,
                        curve: Curves.easeOutCubic,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(
                              alpha: libraryDurationOverlayOpacity,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: overlay.durationHorizontalPadding,
                              vertical: overlay.durationVerticalPadding,
                            ),
                            child: Text(
                              libraryVideoDurationLabel(
                                widget.item.playbackDuration,
                              ),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: overlay.durationFontSize,
                                fontWeight: FontWeight.w600,
                                height: 1,
                                shadows: const <Shadow>[
                                  Shadow(
                                    color: Color(0xcc000000),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/**
 * 媒体库结果区的桌面文件拖放边界。
 *
 * 组件只负责接收路径和提供轻量覆盖反馈；目录识别、视频扩展名校验和扫描由页面应用链路负责，
 * 避免拖动经过 UI 时触发文件系统访问或全列表 rebuild。
 */
class LibraryImportDropRegion extends StatefulWidget {
  const LibraryImportDropRegion({
    super.key,
    required this.enabled,
    required this.onDropPaths,
    required this.child,
  });

  /** 当前是否允许接收桌面拖放；扫描期间关闭以避免并发扫描。 */
  final bool enabled;

  /** 用户释放文件后收到的原始本地路径。 */
  final ValueChanged<List<String>> onDropPaths;

  /** 原媒体库结果内容。 */
  final Widget child;

  @override
  State<LibraryImportDropRegion> createState() =>
      _LibraryImportDropRegionState();
}

class _LibraryImportDropRegionState extends State<LibraryImportDropRegion> {
  /** 文件是否正在结果区上方悬停，仅用于绘制反馈，不参与业务筛选。 */
  var _dragging = false;

  /** 更新拖放悬停态；禁用后不保留过期覆盖层。 */
  void _setDragging(bool value) {
    final next = widget.enabled && value;
    if (_dragging == next) {
      return;
    }
    setState(() => _dragging = next);
  }

  @override
  void didUpdateWidget(covariant LibraryImportDropRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _dragging) {
      _dragging = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      key: LibrarySmokeKeys.importDropRegion,
      enable: widget.enabled,
      onDragEntered: (_) => _setDragging(true),
      onDragExited: (_) => _setDragging(false),
      onDragDone: (details) {
        _setDragging(false);
        final paths = <String>[
          for (final item in details.files)
            if (item.path.trim().isNotEmpty) item.path,
        ];
        if (paths.isNotEmpty) {
          widget.onDropPaths(paths);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          IgnorePointer(
            child: AnimatedOpacity(
              key: LibrarySmokeKeys.importDropOverlay,
              opacity: _dragging ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: appAccentViolet.withValues(alpha: 0.12),
                  border: Border.all(color: appAccentViolet, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: librarySurface,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      boxShadow: appSoftShadow,
                    ),
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.file_download_outlined,
                              size: 42, color: appAccentViolet),
                          SizedBox(height: 10),
                          Text(
                            '释放以添加视频或目录',
                            style: TextStyle(
                              color: libraryText,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/** 媒体库、筛选结果和维护页面共用的空状态。 */
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.hasLibrary,
    this.message,
    this.onAddFiles,
  });

  final bool hasLibrary;

  final String? message;

  /** 仅在全库没有视频时提供的多文件选择入口。 */
  final VoidCallback? onAddFiles;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onAddFiles != null) ...[
            Semantics(
              button: true,
              label: '添加视频文件',
              child: Material(
                key: LibrarySmokeKeys.emptyAddFiles,
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: onAddFiles,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      // 使用媒体库的次级深色表面，避免空状态入口重新形成突兀的浅色孤岛。
                      color: librarySurfaceAlt,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0x596d5dfc),
                        width: 1.25,
                      ),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x126d5dfc),
                          blurRadius: 18,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 48,
                      color: Color(0xff756ae8),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '添加视频文件',
              style: TextStyle(
                color: libraryText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              '选择视频文件，或将文件 / 文件夹拖到媒体库区域',
              textAlign: TextAlign.center,
              style: TextStyle(color: libraryTextMuted, height: 1.4),
            ),
          ] else ...[
            Icon(
              hasLibrary
                  ? Icons.filter_alt_off_outlined
                  : Icons.video_library_outlined,
              size: 54,
              color: Colors.black38,
            ),
            const SizedBox(height: 12),
            Text(message ??
                (hasLibrary
                    ? '\u6ca1\u6709\u5339\u914d\u7684\u89c6\u9891'
                    : '\u6dfb\u52a0\u89c6\u9891\u76ee\u5f55\u540e\u5f00\u59cb\u626b\u63cf')),
          ],
        ],
      ),
    );
  }
}
