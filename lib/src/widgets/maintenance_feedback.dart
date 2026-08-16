import 'package:flutter/material.dart';

import 'app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 维护反馈浮层使用的局部主题。
 *
 * 该主题与页面的维护主题叠加而不是修改全局 ThemeData；因此菜单、sheet、tooltip 和
 * SnackBar 可以在 Route context 位于全局主题上方时仍保持同一套实色材质。
 */
ThemeData maintenanceFeedbackTheme(ThemeData base) {
  final workspace = maintenanceWorkspaceTheme(base);
  return workspace.copyWith(
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: librarySurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.floating),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: librarySurfaceAlt,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.floating),
        side: const BorderSide(color: libraryBorder),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: libraryBorder),
      ),
      textStyle: const TextStyle(
        color: libraryText,
        fontSize: 12,
        fontWeight: AppTypography.medium,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      waitDuration: const Duration(milliseconds: 420),
      showDuration: const Duration(seconds: 3),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: librarySurfaceAlt,
      contentTextStyle: const TextStyle(
        color: libraryText,
        fontSize: AppTypography.body,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: const BorderSide(color: libraryBorder),
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/** 将任意维护反馈内容包回局部浮层主题。 */
Widget maintenanceFeedbackSurface({
  required BuildContext context,
  required Widget child,
}) {
  return Theme(
    data: maintenanceFeedbackTheme(Theme.of(context)),
    child: child,
  );
}

/**
 * 维护工作区共享对话框入口。
 *
 * 由调用页面继续拥有 builder、返回值和业务动作；这里仅把弹层包回维护主题，
 * 让 dialog 不会因为 Route context 跨出局部 Theme 而退回全局浅色表面。
 */
Future<T?> showMaintenanceDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useSafeArea = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    useSafeArea: useSafeArea,
    builder: (dialogContext) => maintenanceFeedbackSurface(
      context: context,
      child: builder(dialogContext),
    ),
  );
}

/**
 * 维护工作区共享 modal sheet 入口。
 *
 * Sheet 只承载当前页面已经决定的内容，不复制筛选、设置或队列状态；实色表面和
 * 顶部圆角在高对比度与无 blur 环境下仍保持可读。
 */
Future<T?> showMaintenanceModalBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    backgroundColor: librarySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.floating),
      ),
    ),
    builder: (sheetContext) => maintenanceFeedbackSurface(
      context: context,
      child: builder(sheetContext),
    ),
  );
}

/**
 * 维护工作区共享菜单入口。
 *
 * [position] 仍由触发控件根据自己的几何计算，避免共享组件猜测 anchor；菜单项的
 * value、选择回调和键盘语义继续由页面 owner 决定。
 */
Future<T?> showMaintenanceMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
}) {
  return showMenu<T>(
    context: context,
    position: position,
    items: items,
    initialValue: initialValue,
    color: librarySurfaceAlt,
    elevation: 12,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.floating),
      side: const BorderSide(color: libraryBorder),
    ),
  );
}

/**
 * 展示维护页非阻塞反馈。
 *
 * 默认遵循 SnackBarTheme 的 floating 行为；只有调用方明确要求替换时才隐藏当前
 * 消息，避免连续错误或恢复提示在用户尚未读完时被无意截断。
 */
void showMaintenanceSnackBar(
  BuildContext context, {
  required String message,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
  bool replaceCurrent = false,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }
  if (replaceCurrent) {
    messenger.hideCurrentSnackBar();
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: action,
      duration: duration,
      backgroundColor: librarySurfaceAlt,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: const BorderSide(color: libraryBorder),
      ),
    ),
  );
}

/** 维护页面图标入口共享 tooltip 外壳，保留 Tooltip 的语义和键盘可达性。 */
class MaintenanceTooltip extends StatelessWidget {
  const MaintenanceTooltip({
    super.key,
    required this.message,
    required this.child,
    this.preferBelow = true,
  });

  /** 图标动作的完整说明，不使用只有颜色的状态表达。 */
  final String message;

  /** tooltip 包裹的可聚焦或可点击内容。 */
  final Widget child;

  /** 窄窗口下是否优先把浮层放在触发器下方。 */
  final bool preferBelow;

  @override
  Widget build(BuildContext context) {
    return maintenanceFeedbackSurface(
      context: context,
      child: Tooltip(
        message: message,
        preferBelow: preferBelow,
        child: child,
      ),
    );
  }
}
