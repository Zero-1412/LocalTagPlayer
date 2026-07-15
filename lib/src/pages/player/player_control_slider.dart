import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 计算播放器进度比例，并把尚未取得时长或越界的位置安全限制在 0 到 1。
 */
double playerProgressFraction(Duration position, Duration duration) {
  final total = duration.inMicroseconds;
  if (total <= 0) {
    return 0;
  }
  return (position.inMicroseconds / total).clamp(0.0, 1.0);
}

/** 悬停停止后按目标播放位置异步加载预览帧。 */
typedef PlayerProgressPreviewLoader = Future<File?> Function(Duration position);

/**
 * 优酷式播放器主进度条：静止时保持细轨无焦点，悬停时动画加粗并延迟显示帧预览。
 */
class PlayerProgressSlider extends StatefulWidget {
  const PlayerProgressSlider({
    super.key,
    this.sliderKey,
    required this.value,
    required this.max,
    required this.onChanged,
    required this.previewIdentity,
    required this.loadPreview,
  });

  /** 直接挂在内部 Slider 上的定位键。 */
  final Key? sliderKey;

  /** 当前播放位置，单位与 [max] 一致。 */
  final double value;

  /** 视频总时长，当前页面使用毫秒。 */
  final double max;

  /** 拖动后提交真实 seek 的回调。 */
  final ValueChanged<double> onChanged;

  /** 当前视频稳定标识；切换视频时使迟到预览立即失效。 */
  final Object previewIdentity;

  /** 经缩略图服务和 FFmpegBackend 限流的预览加载器。 */
  final PlayerProgressPreviewLoader loadPreview;

  @override
  State<PlayerProgressSlider> createState() => _PlayerProgressSliderState();
}

class _PlayerProgressSliderState extends State<PlayerProgressSlider> {
  static const _previewDelay = Duration(milliseconds: 350);
  static const _previewWidth = 220.0;
  static const _previewHeight = 124.0;
  static const _sliderHorizontalInset = 14.0;

  Timer? _previewTimer;
  var _hovered = false;
  var _hoverX = 0.0;
  var _hoverValue = 0.0;
  var _requestGeneration = 0;
  var _previewLoading = false;
  File? _previewFile;

  @override
  void didUpdateWidget(covariant PlayerProgressSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previewIdentity != widget.previewIdentity) {
      _cancelPreview(clearHover: false);
    }
  }

  /** 根据轨道可用宽度把指针位置映射为目标播放时间。 */
  double _valueForPointer(double x, double width) {
    final usableWidth = math.max(1.0, width - _sliderHorizontalInset * 2);
    final fraction = ((x - _sliderHorizontalInset) / usableWidth).clamp(0, 1);
    return fraction * widget.max;
  }

  /** 指针移动只更新轻量位置；停稳后才允许进入 FFmpeg 取帧链路。 */
  void _handlePointer(PointerEvent event, double width,
      {bool entering = false}) {
    final nextValue = _valueForPointer(event.localPosition.dx, width);
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
    _requestGeneration++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final popupLeft = (_hoverX - _previewWidth / 2)
          .clamp(0.0, math.max(0.0, width - _previewWidth))
          .toDouble();
      return MouseRegion(
        key: const ValueKey('player.progress.hoverRegion'),
        onEnter: (event) => _handlePointer(event, width, entering: true),
        onHover: (event) => _handlePointer(event, width),
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
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  builder: (context, hoverProgress, child) {
                    return _PlayerSliderVisual(
                      sliderKey: widget.sliderKey,
                      value: widget.value,
                      max: widget.max,
                      onChanged: widget.onChanged,
                      trackHeight: 2 + hoverProgress * 3,
                      thumbRadius: 5.5,
                      overlayRadius: 14,
                      thumbVisibility: hoverProgress,
                      useCatSlimeThumb: true,
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
        color: const Color(0xf21a2030),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0x997f68d9)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x99000000), blurRadius: 16, offset: Offset(0, 6)),
        ],
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
                            color: Color(0xff9b7cff),
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

/**
 * 播放器进度与音量共用的紧凑滑条，统一轨道、滑块和交互反馈样式。
 */
class PlayerControlSlider extends StatelessWidget {
  const PlayerControlSlider({
    super.key,
    this.sliderKey,
    required this.value,
    required this.max,
    required this.onChanged,
    this.trackHeight = 4,
    this.thumbRadius = 5.5,
    this.overlayRadius = 13,
  });

  /** 直接挂在内部 Slider 上的定位键，保留既有自动化点击入口。 */
  final Key? sliderKey;

  /** 当前滑条数值。 */
  final double value;

  /** 滑条最大数值。 */
  final double max;

  /** 用户拖动滑条时的更新回调。 */
  final ValueChanged<double> onChanged;

  /** 轨道高度；主进度条略高于音量条。 */
  final double trackHeight;

  /** 滑块圆点半径。 */
  final double thumbRadius;

  /** 拖动反馈光晕半径。 */
  final double overlayRadius;

  @override
  Widget build(BuildContext context) {
    return _PlayerSliderVisual(
      sliderKey: sliderKey,
      value: value,
      max: max,
      onChanged: onChanged,
      trackHeight: trackHeight,
      thumbRadius: thumbRadius,
      overlayRadius: overlayRadius,
      thumbVisibility: 1,
    );
  }
}

/** 进度与音量共用的无状态滑条绘制层。 */
class _PlayerSliderVisual extends StatelessWidget {
  const _PlayerSliderVisual({
    required this.sliderKey,
    required this.value,
    required this.max,
    required this.onChanged,
    required this.trackHeight,
    required this.thumbRadius,
    required this.overlayRadius,
    required this.thumbVisibility,
    this.useCatSlimeThumb = false,
  });

  final Key? sliderKey;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  final double trackHeight;
  final double thumbRadius;
  final double overlayRadius;
  final double thumbVisibility;

  /** 仅主进度条启用猫耳史莱姆焦点，音量条继续使用紧凑圆点。 */
  final bool useCatSlimeThumb;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: trackHeight,
        trackShape: const _PlayerGradientSliderTrackShape(),
        activeTrackColor: const Color(0xff8060ff),
        inactiveTrackColor: const Color(0x8a66718b),
        thumbColor: Colors.white,
        thumbShape: useCatSlimeThumb
            ? _PlayerCatSlimeThumbShape(visibility: thumbVisibility)
            : _PlayerRingSliderThumbShape(
                radius: thumbRadius,
                visibility: thumbVisibility,
              ),
        overlayColor: const Color(0x387c5cff),
        overlayShape: RoundSliderOverlayShape(overlayRadius: overlayRadius),
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: Slider(
        key: sliderKey,
        value: value,
        max: max,
        onChanged: onChanged,
      ),
    );
  }
}

/**
 * 控制栏隐藏后贴住视频底边的只读细进度线，避免遮挡画面或扩大点击区域。
 */
class PlayerHiddenProgressBar extends StatelessWidget {
  const PlayerHiddenProgressBar({
    super.key,
    required this.position,
    required this.duration,
  });

  /** 当前播放位置。 */
  final Duration position;

  /** 当前视频总时长。 */
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final fraction = playerProgressFraction(position, duration);
    return IgnorePointer(
      child: SizedBox(
        key: const ValueKey('player.hiddenProgressBar'),
        height: 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0x520b1020)),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                key: const ValueKey('player.hiddenProgressBar.active'),
                widthFactor: fraction,
                heightFactor: 1,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xff7251ff), Color(0xffa875ff)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x667451ff),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/**
 * 为播放器滑条绘制柔和的底轨与紫色渐变有效轨道。
 */
class _PlayerGradientSliderTrackShape extends SliderTrackShape
    with BaseSliderTrackShape {
  const _PlayerGradientSliderTrackShape();

  @override
  bool get isRounded => true;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final height = sliderTheme.trackHeight ?? 0;
    if (height <= 0) {
      return;
    }
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final radius = Radius.circular(trackRect.height / 2);
    final inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? const Color(0x8a66718b);
    context.canvas
        .drawRRect(RRect.fromRectAndRadius(trackRect, radius), inactivePaint);

    // 文本方向只影响有效轨道起点，不改变播放器进度数值本身。
    final activeRect = textDirection == TextDirection.ltr
        ? Rect.fromLTRB(
            trackRect.left,
            trackRect.top,
            thumbCenter.dx.clamp(trackRect.left, trackRect.right),
            trackRect.bottom,
          )
        : Rect.fromLTRB(
            thumbCenter.dx.clamp(trackRect.left, trackRect.right),
            trackRect.top,
            trackRect.right,
            trackRect.bottom,
          );
    if (activeRect.width <= 0) {
      return;
    }
    final activePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xff7251ff), Color(0xffa875ff)],
      ).createShader(trackRect);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(activeRect, radius),
      activePaint,
    );
  }
}

/**
 * 绘制带紫色外环和轻微按压放大的白色滑块，保证深色画面上的辨识度。
 */
class _PlayerRingSliderThumbShape extends SliderComponentShape {
  const _PlayerRingSliderThumbShape({
    required this.radius,
    this.visibility = 1,
  });

  /** 静止状态下白色滑块的半径。 */
  final double radius;

  /** 0 时完全隐藏，1 时显示完整焦点；主进度条悬停动画使用中间值。 */
  final double visibility;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(radius + 2);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    if (visibility <= 0.01) {
      return;
    }
    final pressedGrowth = activationAnimation.value;
    final outerRadius = (radius + 1.5 + pressedGrowth) * visibility;
    final canvas = context.canvas;
    canvas.drawCircle(
      center,
      outerRadius,
      Paint()..color = const Color(0xff7251ff),
    );
    canvas.drawCircle(
      center,
      (radius + pressedGrowth * 0.5) * visibility,
      Paint()..color = sliderTheme.thumbColor ?? Colors.white,
    );
  }
}

/**
 * 绘制主进度条专用的猫耳史莱姆焦点。
 *
 * 使用矢量轮廓而不是缩放参考位图，避免十几像素尺寸下出现棋盘底色、锯齿或模糊；
 * 紫蓝渐变与进度轨道保持同一色系，浅色描边只负责从视频画面中分离焦点。
 */
class _PlayerCatSlimeThumbShape extends SliderComponentShape {
  const _PlayerCatSlimeThumbShape({required this.visibility});

  /** 0 时完全隐藏，1 时显示完整焦点，并跟随进度条悬停动画取中间值。 */
  final double visibility;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size.square(26);
  }

  /** 构建带双耳的圆润史莱姆轮廓，坐标围绕滑块中心定义。 */
  Path _buildBodyPath() {
    return Path()
      ..moveTo(-9.3, -3)
      ..lineTo(-7.7, -9.1)
      ..quadraticBezierTo(-7.3, -10.4, -6.1, -9.3)
      ..lineTo(-3.1, -6.2)
      ..quadraticBezierTo(0, -7.3, 3.1, -6.2)
      ..lineTo(6.1, -9.3)
      ..quadraticBezierTo(7.3, -10.4, 7.7, -9.1)
      ..lineTo(9.3, -3)
      ..cubicTo(10.2, -0.7, 10.1, 4.4, 7.2, 6.8)
      ..cubicTo(4, 9.2, -4, 9.2, -7.2, 6.8)
      ..cubicTo(-10.1, 4.4, -10.2, -0.7, -9.3, -3)
      ..close();
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    if (visibility <= 0.01) {
      return;
    }

    final canvas = context.canvas;
    final appearScale =
        Curves.easeOutBack.transform(visibility.clamp(0, 1).toDouble());
    final pressedScale = 1 + activationAnimation.value * 0.08;
    final body = _buildBodyPath();
    final bodyBounds = const Rect.fromLTRB(-10.5, -10.5, 10.5, 9.5);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(appearScale * pressedScale);

    // 轻量外光与浅色轮廓让焦点在明暗视频画面上都清晰，但不抢占进度轨道主体。
    canvas.drawPath(
      body,
      Paint()
        ..color = const Color(0x52755cff)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
    );
    canvas.drawPath(body, Paint()..color = const Color(0xffdcd5ff));

    canvas.save();
    canvas.scale(0.91, 0.91);
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xffc8b7ff),
            Color(0xff8d69f7),
            Color(0xff5548e7),
          ],
        ).createShader(bodyBounds),
    );

    // 小尺寸仅保留高光、眼睛和短笑线，避免完整参考图细节缩小后形成视觉噪点。
    canvas.drawOval(
      const Rect.fromLTWH(-5.8, -4.1, 3.8, 2.3),
      Paint()..color = const Color(0xd9ffffff),
    );
    final facePaint = Paint()..color = const Color(0xff17164f);
    canvas.drawCircle(const Offset(-3, 1.1), 1.15, facePaint);
    canvas.drawCircle(const Offset(3, 1.1), 1.15, facePaint);
    canvas.drawArc(
      const Rect.fromLTWH(-1.6, 1.3, 3.2, 2.8),
      0.15,
      math.pi - 0.3,
      false,
      Paint()
        ..color = const Color(0xff17164f)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
    canvas.restore();
  }
}
