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
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: trackHeight,
        trackShape: const _PlayerGradientSliderTrackShape(),
        activeTrackColor: const Color(0xff8060ff),
        inactiveTrackColor: const Color(0x8a66718b),
        thumbColor: Colors.white,
        thumbShape: _PlayerRingSliderThumbShape(radius: thumbRadius),
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
  const _PlayerRingSliderThumbShape({required this.radius});

  /** 静止状态下白色滑块的半径。 */
  final double radius;

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
    final pressedGrowth = activationAnimation.value;
    final outerRadius = radius + 1.5 + pressedGrowth;
    final canvas = context.canvas;
    canvas.drawCircle(
      center,
      outerRadius,
      Paint()..color = const Color(0xff7251ff),
    );
    canvas.drawCircle(
      center,
      radius + pressedGrowth * 0.5,
      Paint()..color = sliderTheme.thumbColor ?? Colors.white,
    );
  }
}
