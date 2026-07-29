import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';
import 'player_control_slider_metrics.dart';
import 'player_control_slider_shapes.dart';

// ignore_for_file: slash_for_doc_comments

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
    return PlayerSliderVisual(
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
class PlayerSliderVisual extends StatelessWidget {
  const PlayerSliderVisual({
    super.key,
    required this.sliderKey,
    required this.value,
    required this.max,
    required this.onChanged,
    required this.trackHeight,
    required this.thumbRadius,
    required this.overlayRadius,
    required this.thumbVisibility,
    this.onChangeStart,
    this.onChangeEnd,
    this.useCatSlimeThumb = false,
    this.catSlimeThumbScale = 1,
  });

  final Key? sliderKey;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  /** 可选的拖动开始回调；主进度条用它隔离后端 seek。 */
  final ValueChanged<double>? onChangeStart;
  /** 可选的拖动结束回调；主进度条只在这里提交最终 seek。 */
  final ValueChanged<double>? onChangeEnd;
  final double trackHeight;
  final double thumbRadius;
  final double overlayRadius;
  final double thumbVisibility;

  /** 仅主进度条启用猫耳史莱姆焦点，音量条继续使用紧凑圆点。 */
  final bool useCatSlimeThumb;

  /** 高分辨率全屏下猫耳焦点的有限视觉倍率。 */
  final double catSlimeThumbScale;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: trackHeight,
        trackShape: const PlayerGradientSliderTrackShape(),
        activeTrackColor: appAccentViolet,
        inactiveTrackColor: playerTextMuted.withValues(alpha: 0.38),
        thumbColor: playerText,
        thumbShape: useCatSlimeThumb
            ? PlayerCatSlimeThumbShape(
                visibility: thumbVisibility,
                visualScale: catSlimeThumbScale,
              )
            : PlayerRingSliderThumbShape(
                radius: thumbRadius,
                visibility: thumbVisibility,
              ),
        overlayColor: appAccentViolet.withValues(alpha: 0.22),
        overlayShape: RoundSliderOverlayShape(overlayRadius: overlayRadius),
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: Slider(
        key: sliderKey,
        value: value,
        max: max,
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
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
                    color: appAccentViolet,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x526d5dfc),
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
