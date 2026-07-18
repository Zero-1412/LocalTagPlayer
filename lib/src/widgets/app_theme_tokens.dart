import 'package:flutter/material.dart';

// ignore_for_file: slash_for_doc_comments

/** Apple 式视觉系统使用的圆角层级，避免页面各自发明相近数值。 */
abstract final class AppRadius {
  /** 紧凑输入、按钮与标签。 */
  static const double control = 10;

  /** 内容卡片与分组容器。 */
  static const double card = 14;

  /** 侧栏、详情面板与大块结构表面。 */
  static const double panel = 18;

  /** 菜单、弹窗与其它浮动表面。 */
  static const double floating = 20;

  /** 胶囊形状态或单一短动作。 */
  static const double capsule = 999;
}

/** 以 4 像素为基础节奏的共享间距。 */
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/** 桌面高信息密度界面的共享排版尺度。 */
abstract final class AppTypography {
  static const double caption = 12;
  static const double body = 14;
  static const double bodyLarge = 16;
  static const double title = 20;
  static const double pageTitle = 28;
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w600;
  static const FontWeight strong = FontWeight.w700;
}

/** 可选浮层材质参数；结构表面始终保持实色。 */
abstract final class AppMaterialOpacity {
  static const double floating = 0.94;
}

/** 按交互含义组织的动效时长；业务结果提交不得等待这些时长。 */
abstract final class AppMotion {
  static const Duration press = Duration(milliseconds: 110);
  static const Duration hover = Duration(milliseconds: 160);
  static const Duration popover = Duration(milliseconds: 200);
  static const Duration route = Duration(milliseconds: 220);
  static const Duration panel = Duration(milliseconds: 300);
  static const Duration reducedFade = Duration(milliseconds: 80);
  static const Curve standardCurve = Curves.easeOutCubic;
}

/**
 * 从系统媒体设置派生的无障碍策略。
 *
 * 位移动效在 [reduceMotion] 下立即完成，短淡入仍可通过 [fadeDuration]
 * 保留状态连续性；高对比度下所有可选透明材质必须回退为实色。
 */
@immutable
class AppAccessibilityData {
  const AppAccessibilityData({
    required this.disableAnimations,
    required this.accessibleNavigation,
    required this.highContrast,
    required this.textScaler,
  });

  /** 从 Flutter 提供的系统媒体偏好创建策略快照。 */
  factory AppAccessibilityData.fromMediaQuery(MediaQueryData mediaQuery) {
    return AppAccessibilityData(
      disableAnimations: mediaQuery.disableAnimations,
      accessibleNavigation: mediaQuery.accessibleNavigation,
      highContrast: mediaQuery.highContrast,
      textScaler: mediaQuery.textScaler,
    );
  }

  /** 系统是否要求停用装饰动画。 */
  final bool disableAnimations;

  /** 系统是否偏好更稳定、无自动位移的导航。 */
  final bool accessibleNavigation;

  /** 系统是否要求强化文字、边框和焦点对比度。 */
  final bool highContrast;

  /** 保留系统文字缩放，不在组件内反向抵消。 */
  final TextScaler textScaler;

  /** 任一系统减弱动效偏好生效时，都停用位移和缩放动画。 */
  bool get reduceMotion => disableAnimations || accessibleNavigation;

  /** 为位移、缩放和结构变化返回可访问时长。 */
  Duration motionDuration(Duration regular) {
    return reduceMotion ? Duration.zero : regular;
  }

  /** reduced motion 下仍允许很短的颜色或透明度过渡。 */
  Duration fadeDuration(Duration regular) {
    return reduceMotion ? AppMotion.reducedFade : regular;
  }
}

/**
 * 向共享基础组件提供当前无障碍策略。
 *
 * 页面业务状态不依赖该作用域；缺少作用域的独立测试会安全使用系统默认值。
 */
class AppAccessibilityScope extends InheritedWidget {
  const AppAccessibilityScope({
    super.key,
    required this.data,
    required super.child,
  });

  /** 当前系统媒体偏好的不可变快照。 */
  final AppAccessibilityData data;

  /** 读取最近的策略；独立组件测试没有作用域时返回稳定默认值。 */
  static AppAccessibilityData of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<AppAccessibilityScope>()
            ?.data ??
        const AppAccessibilityData(
          disableAnimations: false,
          accessibleNavigation: false,
          highContrast: false,
          textScaler: TextScaler.noScaling,
        );
  }

  @override
  bool updateShouldNotify(AppAccessibilityScope oldWidget) {
    return data.disableAnimations != oldWidget.data.disableAnimations ||
        data.accessibleNavigation != oldWidget.data.accessibleNavigation ||
        data.highContrast != oldWidget.data.highContrast ||
        data.textScaler != oldWidget.data.textScaler;
  }
}

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

/** 高对比度模式使用的强化描边。 */
const appBorderHighContrast = Color(0xff53625e);

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
const appMotionDuration = AppMotion.hover;
const appMotionCurve = AppMotion.standardCurve;

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
 * 创建全应用共享浅色主题。
 *
 * [highContrast] 只强化轮廓、焦点和文字对比，不改变业务状态颜色或页面结构。
 * 媒体库和维护页仍可在此主题之上应用各自的深色工作区覆盖层。
 */
ThemeData buildLocalTagPlayerTheme({bool highContrast = false}) {
  final outline = highContrast ? appBorderHighContrast : appBorder;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: appAccent,
    brightness: Brightness.light,
  ).copyWith(
    outline: outline,
    outlineVariant: outline,
  );
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.control),
  );
  final outlinedControlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.control),
    side: BorderSide(color: outline),
  );
  final base = ThemeData(
    colorScheme: colorScheme,
    fontFamilyFallback: const <String>[
      'Microsoft YaHei',
      'Microsoft YaHei UI',
      'SimHei',
      'Segoe UI',
    ],
    useMaterial3: true,
  );

  return base.copyWith(
    scaffoldBackgroundColor: appBackground,
    textTheme: base.textTheme.copyWith(
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        color: appText,
        fontSize: AppTypography.body,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        color: appText,
        fontSize: AppTypography.bodyLarge,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        color: appText,
        fontSize: AppTypography.title,
        fontWeight: AppTypography.strong,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: appSurface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: outline),
      ),
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: appSurface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: appText,
      centerTitle: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: appSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.floating),
        side: BorderSide(color: outline),
      ),
      titleTextStyle: const TextStyle(
        color: appText,
        fontSize: AppTypography.title,
        fontWeight: AppTypography.strong,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: appSurface,
      surfaceTintColor: Colors.transparent,
      textStyle: const TextStyle(
        color: appText,
        fontSize: AppTypography.body,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: outline),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(appSurface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(outlinedControlShape),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: appSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.floating),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: appShell,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: appAccent,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: AppTypography.strong),
        shape: controlShape,
        minimumSize: const Size(0, 40),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: appAccentStrong,
        side: BorderSide(color: outline),
        shape: controlShape,
        minimumSize: const Size(0, 40),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: appAccentStrong,
        shape: controlShape,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: appSurfaceAlt,
      selectedColor: const Color(0xffd7eeea),
      disabledColor: const Color(0xffe7ecea),
      side: BorderSide(color: outline),
      shape: controlShape,
      labelStyle: const TextStyle(
        color: Color(0xff20302d),
        fontWeight: AppTypography.medium,
      ),
      secondaryLabelStyle: const TextStyle(
        color: appAccentStrong,
        fontWeight: AppTypography.strong,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      showCheckmark: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: appSurface,
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(
          Radius.circular(AppRadius.control),
        ),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(
          Radius.circular(AppRadius.control),
        ),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(AppRadius.control),
        ),
        borderSide: BorderSide(color: appAccent, width: 1.6),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: WidgetStatePropertyAll(BorderSide(color: outline)),
        shape: WidgetStatePropertyAll(controlShape),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? const Color(0xffd7eeea)
              : appSurface;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? appAccentStrong
              : appTextMuted;
        }),
      ),
    ),
    focusColor: highContrast
        ? appAccent.withValues(alpha: 0.24)
        : appAccent.withValues(alpha: 0.14),
    hoverColor: appAccent.withValues(alpha: 0.08),
  );
}

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
