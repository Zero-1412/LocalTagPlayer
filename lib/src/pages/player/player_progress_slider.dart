import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';
import 'player_control_slider_metrics.dart';
import 'player_control_slider_surface.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 优酷式播放器主进度条：静止时保持细轨无焦点，悬停时动画加粗并延迟显示帧预览。
 */
class PlayerProgressSlider extends StatefulWidget {
  const PlayerProgressSlider({
    super.key,
    this.sliderKey,
    required this.value,
    required this.max,
    required this.onCommitted,
    this.onSeekTargetChanged,
    required this.previewIdentity,
    required this.loadPreview,
    this.isFullscreen = false,
  });

  /** 直接挂在内部 Slider 上的定位键。 */
  final Key? sliderKey;

  /** 当前播放位置，单位与 [max] 一致。 */
  final double value;

  /** 视频总时长，当前页面使用毫秒。 */
  final double max;

  /**
   * 仅在手势结束时提交最终 seek 目标，并在播放器协调器完成该目标后返回。
   *
   * 内部 Slider 的 `onChanged` 只维护拖动中的本地视觉位置；不能把每个移动事件
   * 透传到播放器，否则长 GOP 媒体会在同一次拖动中堆积多次解码跳转。
   */
  final Future<void> Function(double value) onCommitted;

  /** 通知外层同步时间文本与隐藏态进度条的乐观目标；不改变后端提交语义。 */
  final ValueChanged<double?>? onSeekTargetChanged;

  /** 当前视频稳定标识；切换视频时使迟到预览立即失效。 */
  final Object previewIdentity;

  /** 经缩略图服务和 FFmpegBackend 限流的预览加载器。 */
  final PlayerProgressPreviewLoader loadPreview;

  /** 是否处于窗口全屏，用于在高分辨率视口中有限放大猫耳焦点。 */
  final bool isFullscreen;

  @override
  State<PlayerProgressSlider> createState() => _PlayerProgressSliderState();
}

class _PlayerProgressSliderState extends State<PlayerProgressSlider> {
  static const _previewDelay = Duration(milliseconds: 350);
  static const _previewWidth = 220.0;
  static const _previewHeight = 124.0;
  static const _baseThumbHalfExtent = 14.0;

  Timer? _previewTimer;
  var _hovered = false;
  var _hoverX = 0.0;
  var _hoverValue = 0.0;
  var _requestGeneration = 0;
  var _previewLoading = false;
  File? _previewFile;
  /** 拖动期间只更新本地视觉位置，松手后才向播放后端提交一次 seek。 */
  double? _dragValue;
  var _dragging = false;
  /** 鼠标点击后暂时保持目标位置，等待后端位置流追上，避免滑块回弹。 */
  double? _pendingCommitValue;
  Timer? _pendingCommitTimer;
  var _pendingCommitCompleted = false;
  var _commitGeneration = 0;
  double? _lastCommitValue;
  double? _previousCommitValue;

  static const _pendingCommitTimeout = Duration(seconds: 3);
  static const _pendingCommitToleranceMs = 500.0;

  @override
  void didUpdateWidget(covariant PlayerProgressSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previewIdentity != widget.previewIdentity) {
      _cancelPreview(clearHover: false);
      _commitGeneration++;
      _clearPendingCommit();
      _lastCommitValue = null;
      _previousCommitValue = null;
      return;
    }
    final pending = _pendingCommitValue;
    if (pending != null && _pendingCommitCompleted) {
      _maybeClearPendingCommit(widget.value);
    }
  }

  /** 清理已经被后端确认或超时的本地乐观位置。 */
  void _clearPendingCommit() {
    _pendingCommitTimer?.cancel();
    _pendingCommitTimer = null;
    _pendingCommitValue = null;
    _pendingCommitCompleted = false;
  }

  /** 根据轨道可用宽度把指针位置映射为目标播放时间。 */
  double _valueForPointer(double x, double width, double thumbScale) {
    // 与 Slider thumb preferred size 使用同一倍率，避免高分辨率全屏两端的预览时间偏移。
    final horizontalInset = _baseThumbHalfExtent * thumbScale + 1;
    final usableWidth = math.max(1.0, width - horizontalInset * 2);
    final fraction = ((x - horizontalInset) / usableWidth).clamp(0, 1);
    return fraction * widget.max;
  }

  /** 指针移动只更新轻量位置；停稳后才允许进入 FFmpeg 取帧链路。 */
  void _handlePointer(PointerEvent event, double width, double thumbScale,
      {bool entering = false}) {
    final nextValue =
        _valueForPointer(event.localPosition.dx, width, thumbScale);
    _previewTimer?.cancel();
    _requestGeneration++;
    setState(() {
      if (entering) {
        _hovered = true;
      }
      _hoverX = event.localPosition.dx.clamp(0, width);
      _hoverValue = nextValue;
      _previewLoading = false;
      _previewFile = null;
    });
    final generation = _requestGeneration;
    _previewTimer = Timer(_previewDelay, () {
      unawaited(_loadPreview(generation, nextValue));
    });
  }

  /** 仅接受仍对应当前视频和当前悬停位置的异步结果。 */
  Future<void> _loadPreview(int generation, double value) async {
    if (!mounted || generation != _requestGeneration || !_hovered) {
      return;
    }
    setState(() => _previewLoading = true);
    final file = await widget.loadPreview(
      Duration(milliseconds: value.round()),
    );
    if (!mounted || generation != _requestGeneration || !_hovered) {
      return;
    }
    setState(() {
      _previewLoading = false;
      _previewFile = file;
    });
  }

  /** 使定时器和迟到异步结果失效；离开轨道时同时收起焦点与预览。 */
  void _cancelPreview({required bool clearHover}) {
    _previewTimer?.cancel();
    _requestGeneration++;
    if (!mounted) {
      return;
    }
    setState(() {
      if (clearHover) {
        _hovered = false;
      }
      _previewLoading = false;
      _previewFile = null;
    });
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _pendingCommitTimer?.cancel();
    _requestGeneration++;
    super.dispose();
  }

  /** 开始拖动时锁定本地显示值，避免后端尚未确认的位置把滑块拉回。 */
  void _handleChangeStart(double value) {
    _clearPendingCommit();
    widget.onSeekTargetChanged?.call(null);
    setState(() {
      _dragging = true;
      _dragValue = value;
    });
  }

  /** 拖动过程只刷新轻量滑块，不连续刷新解码器和原生纹理链。 */
  void _handleChanged(double value) {
    setState(() => _dragValue = value);
  }

  /** 松手后只提交最终目标，后续位置显示继续以播放器确认状态为准。 */
  void _handleChangeEnd(double value) {
    final committedValue = value.clamp(0.0, widget.max).toDouble();
    final generation = ++_commitGeneration;
    _previousCommitValue = _lastCommitValue;
    _lastCommitValue = committedValue;
    _pendingCommitTimer?.cancel();
    setState(() {
      _dragging = false;
      _dragValue = null;
      _pendingCommitValue = committedValue;
      _pendingCommitCompleted = false;
    });
    widget.onSeekTargetChanged?.call(committedValue);
    _pendingCommitTimer = Timer(_pendingCommitTimeout, () {
      if (!mounted ||
          _commitGeneration != generation ||
          _pendingCommitValue != committedValue) {
        return;
      }
      setState(() => _pendingCommitValue = null);
      _pendingCommitTimer = null;
      _pendingCommitCompleted = false;
    });
    unawaited(_awaitCommit(committedValue, generation));
  }

  /**
   * 只有最新提交已经离开协调器，且位置流也追上后才解除本地乐观位置。
   *
   * 快速点击时第一次位置回写可能与第二个目标相差不到容差；没有完成标记就
   * 会把旧落点误判为新落点，导致滑块回弹。
   */
  Future<void> _awaitCommit(double value, int generation) async {
    try {
      await widget.onCommitted(value);
    } catch (_) {
      // 提交失败时保留目标直到超时，避免失败瞬间回弹覆盖用户最后一次点击。
      return;
    }
    if (!mounted ||
        generation != _commitGeneration ||
        _pendingCommitValue != value) {
      return;
    }
    _pendingCommitCompleted = true;
    _maybeClearPendingCommit(widget.value);
  }

  /**
   * 位置流可能先回写上一次点击的目标；相近目标仅靠绝对容差无法区分新旧。
   * 选择更接近最新提交的值，宁可短暂保持乐观位置，也不能让旧回写覆盖新点击。
   */
  void _maybeClearPendingCommit(double observedValue) {
    final pending = _pendingCommitValue;
    if (pending == null || !_pendingCommitCompleted) return;
    if ((observedValue - pending).abs() > _pendingCommitToleranceMs) {
      return;
    }
    final previous = _previousCommitValue;
    if (previous != null &&
        (observedValue - previous).abs() < (observedValue - pending).abs()) {
      return;
    }
    _clearPendingCommit();
  }

  @override
  Widget build(BuildContext context) {
    final thumbScale = playerProgressThumbScale(
      isFullscreen: widget.isFullscreen,
      viewportSize: MediaQuery.sizeOf(context),
    );
    final accessibility = AppAccessibilityScope.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final popupLeft = (_hoverX - _previewWidth / 2)
          .clamp(0.0, math.max(0.0, width - _previewWidth))
          .toDouble();
      return MouseRegion(
        key: const ValueKey('player.progress.hoverRegion'),
        onEnter: (event) =>
            _handlePointer(event, width, thumbScale, entering: true),
        onHover: (event) => _handlePointer(event, width, thumbScale),
        onExit: (_) => _cancelPreview(clearHover: true),
        child: SizedBox(
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  key: const ValueKey('player.progress.hoverAnimation'),
                  tween: Tween<double>(end: _hovered ? 1 : 0),
                  duration: accessibility.fadeDuration(AppMotion.hover),
                  curve: AppMotion.standardCurve,
                  builder: (context, hoverProgress, child) {
                    final displayValue =
                        (_dragging ? _dragValue : _pendingCommitValue) ??
                            widget.value;
                    return PlayerSliderVisual(
                      sliderKey: widget.sliderKey,
                      value: displayValue.clamp(0.0, widget.max).toDouble(),
                      max: widget.max,
                      onChanged: _handleChanged,
                      onChangeStart: _handleChangeStart,
                      onChangeEnd: _handleChangeEnd,
                      trackHeight: 2 + hoverProgress * 3,
                      thumbRadius: 5.5 * thumbScale,
                      overlayRadius: 14,
                      thumbVisibility: hoverProgress,
                      useCatSlimeThumb: true,
                      catSlimeThumbScale: thumbScale,
                    );
                  },
                ),
              ),
              if (_hovered && (_previewLoading || _previewFile != null))
                Positioned(
                  key: const ValueKey('player.progress.preview'),
                  left: popupLeft,
                  bottom: 42,
                  child: IgnorePointer(
                    child: _PlayerFramePreview(
                      file: _previewFile,
                      loading: _previewLoading,
                      position: Duration(milliseconds: _hoverValue.round()),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

/** 悬停帧卡片，加载期间保持稳定尺寸，完成后淡入当前时间点画面。 */
class _PlayerFramePreview extends StatelessWidget {
  const _PlayerFramePreview({
    required this.file,
    required this.loading,
    required this.position,
  });

  final File? file;
  final bool loading;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _PlayerProgressSliderState._previewWidth,
      height: _PlayerProgressSliderState._previewHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: playerSurfaceRaised.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: playerBorder),
        boxShadow: playerSoftShadow,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 140),
            child: file != null
                ? Image.file(
                    file!,
                    key: ValueKey(file!.path),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  )
                : loading
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: appAccentViolet,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
          ),
          Positioned(
            left: 8,
            bottom: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xb8000000),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  _formatPreviewDuration(position),
                  key: const ValueKey('player.progress.previewTime'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

/** 把悬停位置格式化为播放器预览时间。 */
String _formatPreviewDuration(Duration value) {
  final totalSeconds = value.inSeconds.clamp(0, 24 * 60 * 60 - 1);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
