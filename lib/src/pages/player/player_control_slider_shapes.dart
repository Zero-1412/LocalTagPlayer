import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 为播放器滑条绘制柔和的底轨与紫色渐变有效轨道。
 */
class PlayerGradientSliderTrackShape extends SliderTrackShape
    with BaseSliderTrackShape {
  const PlayerGradientSliderTrackShape();

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
      ..color = sliderTheme.inactiveTrackColor ??
          playerTextMuted.withValues(alpha: 0.38);
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
      ..color = sliderTheme.activeTrackColor ?? appAccentViolet;
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(activeRect, radius),
      activePaint,
    );
  }
}

/**
 * 绘制带紫色外环和轻微按压放大的白色滑块，保证深色画面上的辨识度。
 */
class PlayerRingSliderThumbShape extends SliderComponentShape {
  const PlayerRingSliderThumbShape({
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
      Paint()..color = appAccentViolet,
    );
    canvas.drawCircle(
      center,
      (radius + pressedGrowth * 0.5) * visibility,
      Paint()..color = sliderTheme.thumbColor ?? Colors.white,
    );
  }
}

/**
 * 判断 Slider 主题是否使用播放器主进度条专属的猫咪焦点。
 *
 * 该只读入口用于防止后续视觉统一时再次把猫咪方案静默替换成通用圆点。
 */
@visibleForTesting
bool playerProgressThumbIsCat(SliderThemeData sliderTheme) =>
    sliderTheme.thumbShape is PlayerCatSlimeThumbShape;

/**
 * 绘制主进度条专用的猫耳史莱姆焦点。
 *
 * 使用矢量轮廓而不是位图资源，保证普通窗口与高分辨率全屏下都保持锐利；
 * 紫色渐变沿用播放器强调色系，脸部只保留小尺寸仍能辨认的眼睛、笑线和高光。
 */
class PlayerCatSlimeThumbShape extends SliderComponentShape {
  const PlayerCatSlimeThumbShape({
    required this.visibility,
    required this.visualScale,
  });

  /** 0 时完全隐藏，1 时显示完整焦点，并跟随进度条悬停动画取中间值。 */
  final double visibility;

  /** 仅由全屏视口计算的视觉倍率，调用层已限制在 1 到 1.25。 */
  final double visualScale;

  /** 28px 目标尺寸相对原始 26px 矢量稿的绘制倍率。 */
  static const _artworkScale = 28 / 26;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.square(28 * visualScale);
  }

  /** 构建带双耳的圆润猫咪轮廓，坐标围绕滑块中心定义。 */
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
    final appearScale = visibility.clamp(0.0, 1.0);
    final pressedScale = 1 + activationAnimation.value * 0.06;
    final body = _buildBodyPath();
    final bodyBounds = const Rect.fromLTRB(-10.5, -10.5, 10.5, 9.5);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(
      appearScale * pressedScale * visualScale * _artworkScale,
    );

    // 小范围柔光只负责把焦点从明暗视频画面中分离，不扩大到整条进度轨道。
    canvas.drawPath(
      body,
      Paint()
        ..color = appAccentViolet.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );
    canvas.drawPath(
      body,
      Paint()..color = playerText.withValues(alpha: 0.92),
    );

    canvas.save();
    canvas.scale(0.91, 0.91);
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xffc8b7ff),
            Color(0xff8d69f7),
            Color(0xff5548e7),
          ],
        ).createShader(bodyBounds),
    );

    // 小尺寸不堆叠复杂纹理，保留能快速识别卡通形象的最少面部细节。
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
