import 'package:flutter/material.dart';

// ignore_for_file: slash_for_doc_comments

/** 应用强调色。 */
const appAccent = Color(0xff0f766e);
const appAccentStrong = Color(0xff0b5d57);
const appAccentViolet = Color(0xff6d5dfc);
const appShell = Color(0xff111827);
const appBackground = Color(0xfff4f7fb);
const appSurface = Color(0xfffbfdfc);
const appSurfaceAlt = Color(0xfff4f8f7);
const appPanel = Color(0xffffffff);
const appBorder = Color(0xffdce4ee);
const appTextMuted = Color(0xff62706d);
const appText = Color(0xff17202e);

/** 媒体库工作区深色画布；与左侧 [appShell] 同色系但保留轻微层级差。 */
const libraryBackground = Color(0xff151d2a);

/** 媒体库主要控件和卡片表面。 */
const librarySurface = Color(0xff1b2636);

/** 媒体库悬停、分段选择和嵌套区域表面。 */
const librarySurfaceAlt = Color(0xff243145);

/** 深色工作区的低强调边框。 */
const libraryBorder = Color(0xff314057);

/** 深色工作区的主要文字。 */
const libraryText = Color(0xfff1f5f9);

/** 深色工作区的次要文字。 */
const libraryTextMuted = Color(0xff9baabd);
const appSoftShadow = <BoxShadow>[
  BoxShadow(
    color: Color(0x140f172a),
    blurRadius: 24,
    offset: Offset(0, 12),
  ),
];

/** 深色媒体库只使用低透明阴影，避免恢复成突兀的白色浮卡视觉。 */
const librarySoftShadow = <BoxShadow>[
  BoxShadow(
    color: Color(0x38000000),
    blurRadius: 20,
    offset: Offset(0, 10),
  ),
];
const appMotionDuration = Duration(milliseconds: 180);
const appMotionCurve = Curves.easeOutCubic;

/**
 * 媒体库左右侧栏的结构动画时长。
 *
 * 侧栏会改变中央结果区宽度，使用比按钮反馈更完整的过渡时间，让面板移动和结果区
 * 稳定缓冲能够衔接；该常量不影响筛选、播放或缩略图后台任务。
 */
const libraryPanelMotionDuration = Duration(milliseconds: 260);

/** 侧栏结构动画使用双向平滑曲线，展开和收起都避免末段突然停住。 */
const libraryPanelMotionCurve = Curves.easeInOutCubic;

/**
 * 结果区等待窗口宽度稳定后再提交卡片重排的时间。
 *
 * 连续窗口缩放帧会反复重启该短等待；侧栏使用独立的列数基准，不会触发换列。
 */
const libraryResultsResizeSettleDuration = Duration(milliseconds: 100);
const libraryThumbnailWidth = 384;

/**
 * 为媒体库路由创建局部深色主题。
 *
 * 该主题只包裹媒体库页面，不改变设置、标签管理器或系统弹窗的全局浅色基线。
 */
ThemeData libraryWorkspaceTheme(ThemeData base) {
  final scheme = const ColorScheme.dark(
    primary: appAccentViolet,
    secondary: appAccent,
    surface: librarySurface,
    onSurface: libraryText,
    outline: libraryBorder,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: libraryBackground,
    textTheme: base.textTheme.apply(
      bodyColor: libraryText,
      displayColor: libraryText,
    ),
    iconTheme: const IconThemeData(color: libraryTextMuted),
    dividerColor: libraryBorder,
    popupMenuTheme: PopupMenuThemeData(
      color: librarySurface,
      surfaceTintColor: Colors.transparent,
      textStyle: const TextStyle(color: libraryText, fontSize: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: libraryBorder),
      ),
    ),
  );
}
