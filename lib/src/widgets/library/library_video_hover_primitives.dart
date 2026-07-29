import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';
import 'library_video_results.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

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

/** 将已知媒体总时长格式化为卡片角标；未知时长不伪装成 `0:00`。 */

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
