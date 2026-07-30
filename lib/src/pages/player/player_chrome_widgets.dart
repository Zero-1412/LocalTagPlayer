import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';
import '../../widgets/design_system/app_interaction_surface.dart';

// ignore_for_file: slash_for_doc_comments

class PlayerRevealFileButton extends StatelessWidget {
  const PlayerRevealFileButton({
    super.key,
    required this.onPressed,
  });

  /** 请求在系统文件管理器中定位当前播放视频文件。 */
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PlayerChromeButton(
      key: const ValueKey('player.revealFile'),
      tooltip: '在文件管理器中显示当前视频',
      onPressed: onPressed,
      icon: Icons.eject_rounded,
    );
  }
}

/** 播放控制条中的音量按钮，点击时在静音与最近音量之间切换。 */
class PlayerVolumeButton extends StatelessWidget {
  const PlayerVolumeButton({
    super.key,
    required this.volume,
    required this.onPressed,
  });

  /** 当前页面即时音量，用于同步图标与 tooltip。 */
  final double volume;

  /** 请求切换静音状态。 */
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final muted = volume <= 0;
    return PlayerChromeButton(
      key: const ValueKey('player.volume.toggleMute'),
      tooltip: muted ? '恢复音量' : '静音',
      onPressed: onPressed,
      icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
    );
  }
}

/**
 * 播放器 chrome 的统一图标动作。
 *
 * 普通状态不绘制沉重边框，依靠 hover、press 与 focus 给出直接反馈；主播放动作可
 * 使用强调色圆形表面。组件只负责视觉与输入，不持有任何播放或队列状态。
 */
class PlayerChromeButton extends StatelessWidget {
  const PlayerChromeButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.size = 38,
    this.iconSize = 20,
    this.iconChild,
  });

  /** 鼠标提示与辅助技术动作名称。 */
  final String tooltip;

  /** 默认静态图标；[iconChild] 非空时只作为语义回退。 */
  final IconData icon;

  /** 激活动作；为 null 时保留位置并进入禁用状态。 */
  final VoidCallback? onPressed;

  /** 是否使用强调色圆形主操作表面。 */
  final bool primary;

  /** 正方形点击区域边长。 */
  final double size;

  /** 默认图标尺寸。 */
  final double iconSize;

  /** 需要动效切换时传入的自定义图标内容。 */
  final Widget? iconChild;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: AppInteractionSurface(
        onTap: onPressed,
        semanticLabel: tooltip,
        padding: EdgeInsets.zero,
        borderRadius: primary ? AppRadius.capsule : AppRadius.control,
        backgroundColor: primary ? appAccentViolet : Colors.transparent,
        // 透明按钮保持真正的无底色静止态；交互表面仍会在 hover、press
        // 与 focus 时叠加强调色反馈，主播放按钮则继续保留紫色实心表面。
        material: AppSurfaceMaterial.solid,
        showBorder: false,
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: IconTheme(
              data: IconThemeData(
                color: enabled
                    ? playerText
                    : playerTextMuted.withValues(alpha: 0.42),
                size: iconSize,
              ),
              child: iconChild ?? Icon(icon),
            ),
          ),
        ),
      ),
    );
  }
}

/** 判断画面局部坐标是否落在底部进度与按钮控制区。 */
bool playerPointerInControlBar({
  required double localY,
  required double surfaceHeight,
  double controlHeight = 112,
}) {
  return localY >= math.max(0, surfaceHeight - controlHeight);
}

/**
 * 判断全屏指针是否仍位于队列激活区域。
 *
 * 队列隐藏时仅保留用户设置的右缘热区；队列展开后以完整侧栏宽度为边界，
 * 指针真正离开后才启动短延迟隐藏，避免依赖子组件偶发的 enter/exit 事件。
 */
bool playerPointerInFullscreenQueueActivationZone({
  required double localX,
  required double surfaceWidth,
  required bool queueVisible,
  required double edgeWidth,
  double queueWidth = 440,
  double retentionPadding = 12,
}) {
  final distanceFromRight = surfaceWidth - localX;
  if (distanceFromRight < 0) {
    return false;
  }
  return distanceFromRight <=
      (queueVisible ? queueWidth + retentionPadding : edgeWidth);
}

/** 判断指针是否进入折叠宽屏队列对应的非全屏标题栏热区。 */
bool playerPointerInWindowTopBarActivationZone({
  required double localY,
  required bool hasWideQueueSidebar,
  required bool queueCollapsed,
  double topBarHeight = 64,
}) {
  return hasWideQueueSidebar &&
      queueCollapsed &&
      localY >= 0 &&
      localY <= topBarHeight;
}

/**
 * 判断非全屏播放器顶栏是否应显示。
 *
 * 宽屏队列展开时顶栏常驻；队列折叠后只在顶部热区悬停时临时显示。
 * 全屏继续使用原无顶栏画布，辅助导航开启时则保留返回入口可达。
 */
bool playerWindowTopBarShouldShow({
  required bool isFullscreen,
  required bool queueCollapsed,
  required bool pointerInTopBarRegion,
  required bool accessibleNavigation,
}) {
  if (isFullscreen) {
    return false;
  }
  return !queueCollapsed || pointerInTopBarRegion || accessibleNavigation;
}

/**
 * 判断非全屏顶栏是否仍应挂载。
 *
 * Windows 进入全屏时，原生窗口会先于异步 Future 完成视觉切换；若继续挂载旧顶栏，
 * 队列动画可能短暂泄露序号与筛选摘要。过渡期间先卸载顶栏，成功后再由最终全屏状态
 * 决定是否恢复，避免在视频画面顶部留下闪烁语境。
 */
bool playerWindowTopBarShouldMount({
  required bool isFullscreen,
  required bool fullscreenTransitionInProgress,
}) {
  return !isFullscreen && !fullscreenTransitionInProgress;
}

/**
 * 判断当前焦点是否属于可编辑文本。
 *
 * 播放器快捷键位于页面祖先 Focus；EditableText 未消费的字母仍可能继续冒泡，
 * 因此必须在页面入口统一门禁，而不能依赖每个搜索框单独拦截某几个按键。
 */
bool playerFocusIsEditable(FocusNode? focus) {
  final focusContext = focus?.context;
  if (focusContext == null) {
    return false;
  }
  return focusContext.widget is EditableText ||
      focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
}

/** 弹窗、菜单或 BottomSheet 位于不同 ModalRoute 时暂停底层播放器快捷键。 */
bool playerFocusIsOnDifferentRoute({
  required BuildContext playerContext,
  required FocusNode? focus,
}) {
  final focusContext = focus?.context;
  if (focusContext == null) {
    return false;
  }
  final playerRoute = ModalRoute.of(playerContext);
  final focusedRoute = ModalRoute.of(focusContext);
  return playerRoute != null &&
      focusedRoute != null &&
      !identical(playerRoute, focusedRoute);
}

/**
 * 判断播放器路由上方是否存在弹窗、菜单或 BottomSheet。
 *
 * 某些 PopupRoute 不会把焦点从播放器 FocusScope 移走，因此不能只检查 primaryFocus；
 * 只要播放器路由不再位于最上层，就暂停其全局快捷键。
 */
bool playerRouteHasBlockingOverlay(BuildContext playerContext) {
  final route = ModalRoute.of(playerContext);
  return route != null && !route.isCurrent;
}

/**
 * pause 未确认时才允许在路由 pop 前启动 stop。
 *
 * 正常退出必须保留最后一帧；异常路径则优先确保音频和原生播放不会残留。
 */
bool playerExitStopShouldStartBeforePop({required bool pauseAcknowledged}) {
  return !pauseAcknowledged;
}

/**
 * 把播放器声明为独立语义路由，并阻断其下方媒体库的无障碍节点。
 *
 * Windows Route 过渡期间可能同时挂载前后两个页面；视觉叠放不应让读屏器继续命中
 * 媒体库控件，因此播放器根节点必须显式承担 route scope。
 */
class PlayerRouteSemantics extends StatelessWidget {
  const PlayerRouteSemantics({super.key, required this.child});

  /** 播放器页面的完整视觉与交互树。 */
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlockSemantics(
      key: const ValueKey('player.route.blockSemantics'),
      child: Semantics(
        key: const ValueKey('player.route.semantics'),
        container: true,
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: '播放器',
        child: child,
      ),
    );
  }
}

/**
 * 画面左上角的统一短时操作反馈。
 *
 * 默认使用轻量半透明深色底与高亮前景，减少对视频内容的遮挡；高对比度模式会提高
 * 表面和描边的不透明度。组件始终忽略指针，不拦截视频或控制条的鼠标命中。
 */
class PlayerShortcutFeedback extends StatelessWidget {
  const PlayerShortcutFeedback({
    super.key,
    required this.visible,
    required this.label,
    required this.icon,
  });

  /** 当前反馈是否处于可见时段。 */
  final bool visible;

  /** 对本次快捷键结果的简短说明。 */
  final String label;

  /** 与本次快捷键动作一致的图标。 */
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    // 普通模式尽量露出视频内容；高对比度模式保留更实的底色，避免亮画面吞没文字。
    final surfaceColor = Colors.black.withValues(
      alpha: highContrast ? 0.78 : 0.38,
    );
    final borderColor = Colors.white.withValues(
      alpha: highContrast ? 0.52 : 0.18,
    );
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          // 所有动作共用同一视频安全区，首次触发也不能回退到中央挂载。
          padding: const EdgeInsets.all(16),
          child: Semantics(
            liveRegion: true,
            label: visible ? '快捷键反馈：$label' : null,
            excludeSemantics: !visible,
            child: AnimatedOpacity(
              key: const ValueKey('player.shortcutFeedback'),
              opacity: visible ? 1 : 0,
              duration: accessibility.fadeDuration(AppMotion.hover),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: borderColor),
                  boxShadow: playerSoftShadow,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 22, color: Colors.white),
                      const SizedBox(width: 9),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: AppTypography.strong,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
