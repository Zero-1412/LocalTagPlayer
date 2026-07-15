import 'package:flutter/material.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放器画面比例模式。
 *
 * 这些模式只改变当前播放会话的 mpv 画面呈现，不修改源文件、媒体详情、
 * filtered queue 或缩略图缓存。
 */
enum PlayerVideoAspectMode {
  automatic,
  ratio4x3,
  ratio16x9,
  cover,
}

/** 播放器比例模式的文案、图标与 mpv 参数映射。 */
extension PlayerVideoAspectModePresentation on PlayerVideoAspectMode {
  /** 设置面板使用的短名称。 */
  String get label => switch (this) {
        PlayerVideoAspectMode.automatic => '自动',
        PlayerVideoAspectMode.ratio4x3 => '4:3',
        PlayerVideoAspectMode.ratio16x9 => '16:9',
        PlayerVideoAspectMode.cover => '铺满',
      };

  /** 设置面板用于快速辨认模式用途的图标。 */
  IconData get icon => switch (this) {
        PlayerVideoAspectMode.automatic => Icons.fit_screen_rounded,
        PlayerVideoAspectMode.ratio4x3 => Icons.crop_landscape_rounded,
        PlayerVideoAspectMode.ratio16x9 => Icons.aspect_ratio_rounded,
        PlayerVideoAspectMode.cover => Icons.fullscreen_rounded,
      };

  /** Flutter 视频表面的缩放方式；铺满会等比裁掉超出窗口的区域。 */
  BoxFit get surfaceFit =>
      this == PlayerVideoAspectMode.cover ? BoxFit.cover : BoxFit.contain;

  /** 用户显式选择的显示宽高比；自动与铺满继续采用媒体自身比例。 */
  double? get surfaceAspectRatio => switch (this) {
        PlayerVideoAspectMode.ratio4x3 => 4 / 3,
        PlayerVideoAspectMode.ratio16x9 => 16 / 9,
        PlayerVideoAspectMode.automatic || PlayerVideoAspectMode.cover => null,
      };

  /** mpv 的显示宽高比覆盖值；`-1` 表示恢复媒体自身比例。 */
  String get mpvAspectOverride => switch (this) {
        PlayerVideoAspectMode.ratio4x3 => '4:3',
        PlayerVideoAspectMode.ratio16x9 => '16:9',
        PlayerVideoAspectMode.automatic || PlayerVideoAspectMode.cover => '-1',
      };

  /**
   * mpv 的最大 panscan 值。
   *
   * “铺满”允许等比裁掉超出窗口的上下或左右区域，适合带编码黑边的 16:10
   * 视频；其它模式保持完整画面。
   */
  String get mpvPanscan => this == PlayerVideoAspectMode.cover ? '1.0' : '0.0';
}
