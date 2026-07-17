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
 * 侧栏会改变中央结果区宽度，使用比按钮反馈更完整的过渡时间，让宽度、内容位移和
 * 边缘阴影形成可感知的结构变化；该常量不影响筛选、播放或缩略图后台任务。
 */
const libraryPanelMotionDuration = Duration(milliseconds: 320);

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

/**
 * 为标签、设置、缓存和重关联等维护页面创建统一深色工作区主题。
 *
 * 这些页面与媒体库属于同一条标签发现和数据维护闭环，复用同一组 surface、边框和
 * 文字 token，避免路由切换时退回全局浅色卡片。该主题只由目标路由显式包裹，
 * 不改变应用其它浅色弹窗或尚未迁移的页面。
 */
ThemeData maintenanceWorkspaceTheme(ThemeData base) {
  final workspace = libraryWorkspaceTheme(base);
  const inputBorder = OutlineInputBorder(
    borderSide: BorderSide(color: libraryBorder),
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );
  return workspace.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: libraryBackground,
      foregroundColor: libraryText,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: librarySurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: libraryBorder),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: librarySurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: libraryBorder),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: librarySurfaceAlt,
      labelStyle: TextStyle(color: libraryTextMuted),
      hintStyle: TextStyle(color: libraryTextMuted),
      enabledBorder: inputBorder,
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: appAccentViolet, width: 1.5),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      border: inputBorder,
    ),
    searchBarTheme: const SearchBarThemeData(
      backgroundColor: WidgetStatePropertyAll(librarySurfaceAlt),
      textStyle: WidgetStatePropertyAll(TextStyle(color: libraryText)),
      hintStyle: WidgetStatePropertyAll(
        TextStyle(color: libraryTextMuted),
      ),
      elevation: WidgetStatePropertyAll(0),
      side: WidgetStatePropertyAll(BorderSide(color: libraryBorder)),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: librarySurfaceAlt,
      selectedColor: Color(0x506d5dfc),
      disabledColor: librarySurface,
      labelStyle: TextStyle(color: libraryText),
      secondaryLabelStyle: TextStyle(
        color: libraryText,
        fontWeight: FontWeight.w800,
      ),
      side: BorderSide(color: libraryBorder),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: libraryText,
      iconColor: libraryTextMuted,
      selectedColor: libraryText,
      selectedTileColor: Color(0x386d5dfc),
    ),
  );
}
