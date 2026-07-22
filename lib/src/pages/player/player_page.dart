import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../../core/playback_settings.dart';
import '../../core/tag_rules.dart';
import '../../models/media_details.dart';
import '../../models/video_item.dart';
import '../../platform/file_system_adapter.dart';
import '../../platform/platform_interfaces.dart';
import '../../services/media/media_details_service.dart';
import '../../services/media/thumbnail_service.dart';
import '../../services/player/player_hardware_acceleration.dart';
import '../../services/player/player_hardware_compatibility.dart';
import '../../services/player/player_adaptive_quality.dart';
import '../../services/player/player_hdr_mapping_experiment.dart';
import '../../services/player/player_gpu_capability_detector.dart';
import '../../services/player/player_memory_diagnostics.dart';
import '../../services/player/player_video_super_resolution.dart';
import '../../widgets/app_theme_tokens.dart';
import '../../widgets/design_system/app_interaction_surface.dart';
import '../../widgets/player_shortcut_input.dart';
import 'player_context_panel.dart';
import 'player_control_slider.dart';
import 'player_delete_dialog.dart';
import 'player_diagnostics_dialog.dart';
import 'player_dialog_content.dart';
import 'player_hardware_decode_warning_dialog.dart';
import 'player_open_failure_panel.dart';
import 'player_open_request_controller.dart';
import 'player_playback_controller.dart';
import 'player_playback_mode.dart';
import 'player_queue_sidebar.dart';
import 'player_rename_file_dialog.dart';
import 'player_resume_dialog.dart';
import 'player_settings_panel.dart';
import 'player_video_aspect_mode.dart';

// ignore_for_file: slash_for_doc_comments

/** 设置浮层或控制条鼠标驻留期间必须阻止播放控制条自动隐藏。 */
bool playerControlsShouldAutoHide({
  required bool settingsOpen,
  required bool pointerInControlBar,
}) =>
    !settingsOpen && !pointerInControlBar;

/**
 * 本地视频打开超过该时长后才展示加载遮罩。
 *
 * media_kit 往往已经渲染首帧，但可播放性与损坏文件校验仍在后台完成；立即展示
 * loading 会盖住可用画面并制造二次冷启动错觉。短打开直接出画，真正慢盘或异常
 * 媒体仍会得到明确反馈。
 */
const playerOpeningOverlayDelay = Duration(milliseconds: 800);

/** open 成功后继续保留首帧占位的最短时间，覆盖原生纹理异步接管窗口。 */
const playerOpeningPosterHold = Duration(milliseconds: 500);

/** 延迟展示播放器打开遮罩，避免正常本地首播闪烁 loading。 */
class PlayerOpeningOverlay extends StatefulWidget {
  const PlayerOpeningOverlay({
    super.key,
    required this.opening,
    this.delay = playerOpeningOverlayDelay,
  });

  /** open worker 是否仍在处理当前媒体。 */
  final bool opening;

  /** 达到该等待时长后才把慢打开反馈给用户。 */
  final Duration delay;

  @override
  State<PlayerOpeningOverlay> createState() => _PlayerOpeningOverlayState();
}

/**
 * 用媒体库已验证缩略图覆盖原生纹理接管前的短暂黑帧。
 *
 * 播放器 Route 创建前已经预热当前队列缩略图，因此这里只读取内存命中的文件，
 * 不新增磁盘扫描或 FFmpeg 任务。open 完成后保留短淡出，让首个真实视频帧自然接管。
 */
class PlayerOpeningPoster extends StatefulWidget {
  const PlayerOpeningPoster({
    super.key,
    required this.opening,
    required this.file,
    this.hold = playerOpeningPosterHold,
  });

  /** 当前媒体是否仍处于打开校验阶段。 */
  final bool opening;

  /** 跳转前已由 [ThumbnailService] 验证并缓存的缩略图。 */
  final File? file;

  /** open 成功后继续覆盖原生纹理接管窗口的时间。 */
  final Duration hold;

  @override
  State<PlayerOpeningPoster> createState() => _PlayerOpeningPosterState();
}

/** 保证占位图不会因系统“减少动态效果”而在纹理首帧前过早消失。 */
class _PlayerOpeningPosterState extends State<PlayerOpeningPoster> {
  Timer? _hideTimer;
  late bool _visible;

  @override
  void initState() {
    super.initState();
    _visible = widget.opening && widget.file != null;
  }

  @override
  void didUpdateWidget(covariant PlayerOpeningPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.opening) {
      _hideTimer?.cancel();
      _visible = widget.file != null;
      return;
    }
    if (oldWidget.opening && !widget.opening && _visible) {
      _hideTimer?.cancel();
      _hideTimer = Timer(widget.hold, () {
        if (mounted && !widget.opening) {
          setState(() => _visible = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final poster = widget.file;
    if (poster == null) {
      return const SizedBox.shrink();
    }
    final accessibility = AppAccessibilityScope.of(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        key: const ValueKey('player.opening.poster'),
        opacity: _visible ? 1 : 0,
        duration: accessibility.fadeDuration(
          const Duration(milliseconds: 600),
        ),
        curve: appMotionCurve,
        child: ColoredBox(
          color: Colors.black,
          child: Image.file(
            poster,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/** 管理延迟计时器，并在打开完成或销毁时立即取消过期回调。 */
class _PlayerOpeningOverlayState extends State<PlayerOpeningOverlay> {
  Timer? _timer;
  var _showOverlay = false;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant PlayerOpeningOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opening != widget.opening ||
        oldWidget.delay != widget.delay) {
      _syncTimer();
    }
  }

  /** 每轮打开只保留一个计时器；完成时同步移除遮罩。 */
  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (!widget.opening) {
      _showOverlay = false;
      return;
    }
    _showOverlay = false;
    _timer = Timer(widget.delay, () {
      if (!mounted || !widget.opening) {
        return;
      }
      setState(() => _showOverlay = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showOverlay) {
      return const SizedBox.shrink();
    }
    return const ColoredBox(
      key: ValueKey('player.opening.overlay'),
      color: Color(0x66000000),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

/**
 * 媒体库与播放器 Route 共享的全屏会话状态。
 *
 * 该状态只在当前应用会话内记住“下次进入播放器是否恢复全屏”，不写入播放设置或
 * 桌面窗口布局。用户主动退出播放器全屏时立即清除，避免普通最大化窗口误走恢复路径。
 */
class PlayerFullscreenSessionController {
  bool _shouldOpenFullscreen = false;

  /** 新播放器 Route 是否需要恢复上一次播放器全屏状态。 */
  bool get shouldOpenFullscreen => _shouldOpenFullscreen;

  /** 记录用户在播放器内完成的全屏切换。 */
  void recordPlayerFullscreen(bool fullscreen) {
    _shouldOpenFullscreen = fullscreen;
  }

  /**
   * 判断返回前是否需要把系统窗口恢复为最大化。
   *
   * 从全屏返回时保留播放器偏好，非全屏返回则不改变窗口，也不凭空创建全屏偏好。
   */
  bool prepareForPlayerExit({required bool currentlyFullscreen}) {
    if (currentlyFullscreen) {
      _shouldOpenFullscreen = true;
    }
    return currentlyFullscreen;
  }
}

/** 持续按住快进键仍可重复 seek，但居中反馈只在首次按下时展示。 */
bool playerSeekFeedbackShouldShow({required bool isRepeat}) => !isRepeat;

/** 全屏覆盖队列宽度随窗口有限伸缩，避免窄屏遮挡过多或超宽屏过度扩张。 */
double playerFullscreenQueueWidth(double windowWidth) =>
    math.min(476.0, math.max(320.0, windowWidth * 0.32));

/** 未展开时使用固定 32px 容错热区，避免高分屏最右边缘难以命中。 */
const playerFullscreenQueueEdgeActivationWidth = 32.0;

/** 离开完整列表后保留 450ms 退场宽限，避免手部微小抖动造成闪退。 */
const playerFullscreenQueueHideGrace = Duration(milliseconds: 450);

/** 按固定步长调整播放器音量，并把结果限制在后端接受的 0..100。 */
double playerVolumeAfterStep(double currentVolume, double delta) =>
    (currentVolume + delta).clamp(0, 100).toDouble();

/** 把滚轮的垂直方向映射为音量步长；纯水平滚动不得误改音量。 */
double playerVolumeDeltaForScroll(double scrollDy) {
  if (scrollDy == 0) return 0;
  return scrollDy < 0 ? 5 : -5;
}

/**
 * 判断底部控制条是否有足够空间显示完整时间文本。
 *
 * 三段式控制条必须优先保持中央传输控制不位移；文字放大后，时间文本占用会同时挤压
 * 左侧和中央区域，因此按倍率提高显示门槛，空间不足时只隐藏这项辅助信息。
 */
bool playerControlsShowTime({
  required double availableWidth,
  required double textScaleFactor,
}) {
  final safeScale = math.max(1, textScaleFactor);
  final scaledThreshold = 780 + (safeScale - 1) * 240;
  return availableWidth >= scaledThreshold;
}

/** 从当前视频路径提取播放器顶栏文件名，避免标题继续显示固定应用名称。 */
String playerTopBarFileName(String path) => p.basename(path);

/**
 * 返回“打开当前视频位置”动作应交给文件系统边界的路径。
 *
 * 即使键盘或鼠标把队列选择移到其它条目，也始终读取 [playingIndex] 对应的
 * [PlayerPlaybackController.currentItem]，避免定位尚未开始播放的视频。
 */
@visibleForTesting
String playerCurrentRevealPath(PlayerPlaybackController playback) =>
    playback.currentItem.path;

/** 静音时归零，恢复时回到最近一次有效的非零音量。 */
double playerVolumeAfterMuteToggle({
  required double currentVolume,
  required double lastAudibleVolume,
}) {
  if (currentVolume > 0) return 0;
  final restored = lastAudibleVolume.clamp(1, 100).toDouble();
  return restored > 0 ? restored : 100;
}

/**
 * 播放控制条中的“打开当前视频位置”按钮。
 *
 * 图标沿用用户指定的弹出式样式；实际文件管理器调用由页面传入的平台边界回调负责。
 */
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
@visibleForTesting
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
@visibleForTesting
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
@visibleForTesting
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
@visibleForTesting
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
 * 判断全屏顶部队列语境是否应显示。
 *
 * 底部控制条出现时已经包含当前进度与队列操作，顶部胶囊必须让出画面；控制条收起后
 * 才恢复最小队列语境。该判断只消费现有轻量状态，不新增计时器或队列计算。
 */
@visibleForTesting
bool playerFullscreenContextShouldShow({
  required bool isFullscreen,
  required bool controlsVisible,
}) {
  return isFullscreen && !controlsVisible;
}

/**
 * 判断当前焦点是否属于可编辑文本。
 *
 * 播放器快捷键位于页面祖先 Focus；EditableText 未消费的字母仍可能继续冒泡，
 * 因此必须在页面入口统一门禁，而不能依赖每个搜索框单独拦截某几个按键。
 */
@visibleForTesting
bool playerFocusIsEditable(FocusNode? focus) {
  final focusContext = focus?.context;
  if (focusContext == null) {
    return false;
  }
  return focusContext.widget is EditableText ||
      focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
}

/** 弹窗、菜单或 BottomSheet 位于不同 ModalRoute 时暂停底层播放器快捷键。 */
@visibleForTesting
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
@visibleForTesting
bool playerRouteHasBlockingOverlay(BuildContext playerContext) {
  final route = ModalRoute.of(playerContext);
  return route != null && !route.isCurrent;
}

/**
 * pause 未确认时才允许在路由 pop 前启动 stop。
 *
 * 正常退出必须保留最后一帧；异常路径则优先确保音频和原生播放不会残留。
 */
@visibleForTesting
bool playerExitStopShouldStartBeforePop({required bool pauseAcknowledged}) {
  return !pauseAcknowledged;
}

/**
 * 把持久化的画面比例、倍速与 GPU 超分重新应用到刚打开的播放后端。
 *
 * 播放器在 open 前后都会调用该函数，避免后端重建媒体状态后只保留设置数据或
 * UI 选中态，却没有把真实参数送入当前播放会话。
 */
Future<void> applyPlayerOpenPreferences({
  required PlayerBackend backend,
  required PlayerVideoAspectMode videoAspectMode,
  required PlayerVideoScaler videoScaler,
  required PlayerVideoOutputRange videoOutputRange,
  required double playbackRate,
  required bool videoSuperResolutionEnabled,
  bool hdrDynamicToneMappingExperimentEnabled = false,
}) async {
  /** 单个可选 mpv 属性失败时继续应用其余偏好，兼容能力较少的后端。 */
  Future<void> setPropertySafely(String property, String value) async {
    try {
      await backend.setProperty(property, value);
    } catch (_) {
      // 比例属性属于可选能力，不能因为后端不支持而阻止媒体打开。
    }
  }

  await setPropertySafely(
    'video-aspect-override',
    videoAspectMode.mpvAspectOverride,
  );
  await setPropertySafely('panscan', videoAspectMode.mpvPanscan);
  // 清除历史缩放和平移，防止它们叠加到新的全局比例模式。
  await setPropertySafely('video-zoom', '0');
  await setPropertySafely('video-pan-x', '0');
  await setPropertySafely('video-pan-y', '0');
  await setPropertySafely(
    'video-output-levels',
    switch (videoOutputRange) {
      PlayerVideoOutputRange.automatic => 'auto',
      PlayerVideoOutputRange.limited => 'limited',
      PlayerVideoOutputRange.full => 'full',
    },
  );
  await PlayerVideoSuperResolution.apply(
    backend: backend,
    enabled: videoSuperResolutionEnabled,
    baseScaler: videoScaler,
  );
  await PlayerHdrMappingExperiment.apply(
    backend: backend,
    enabled: hdrDynamicToneMappingExperimentEnabled,
  );
  await backend.setRate(playbackRate);
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

/** 画面中央的短时快捷键反馈，不拦截视频或控制条的鼠标命中。 */
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
    return IgnorePointer(
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
              color: playerSurfaceRaised.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: playerBorder),
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
                  Icon(icon, size: 22, color: playerText),
                  const SizedBox(width: 9),
                  Text(
                    label,
                    style: const TextStyle(
                      color: playerText,
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
    );
  }
}

/** 画面左上角的快进/快退文字水印，避免中心反馈反复遮挡主体内容。 */
class PlayerSeekFeedbackWatermark extends StatelessWidget {
  const PlayerSeekFeedbackWatermark({
    super.key,
    required this.visible,
    required this.label,
  });

  /** 当前水印是否处于短时可见阶段。 */
  final bool visible;

  /** 本次快进或快退动作及其秒数。 */
  final String label;

  @override
  Widget build(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        label: visible ? '播放跳转：$label' : null,
        excludeSemantics: !visible,
        child: AnimatedOpacity(
          key: const ValueKey('player.seekFeedback.watermark'),
          opacity: visible ? 1 : 0,
          duration: accessibility.fadeDuration(AppMotion.hover),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(AppRadius.capsule),
              border: Border.all(color: playerBorder.withValues(alpha: 0.7)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                label,
                style: const TextStyle(
                  color: playerText,
                  fontSize: 12,
                  fontWeight: AppTypography.strong,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.initialItem,
    required this.playlist,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.onPlaybackSettingsChanged,
    required this.activeTags,
    required this.activeChildTag,
    required this.queueTitle,
    required this.onDeleteVideo,
    required this.onToggleFavorite,
    required this.onRenameFile,
    required this.onEditManualTags,
    required this.onRelinkMissing,
    required this.onPlaybackProgressUpdated,
    required this.onMediaDetailsUpdated,
    required this.disposalCompleter,
    required this.fileSystem,
    required this.playerBackendFactory,
    required this.mediaProbeBackendFactory,
    required this.fullscreenSessionController,
  });

  final VideoItem initialItem;
  final List<VideoItem> playlist;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  /** 保存全局播放器设置；调用方必须同步更新应用内存状态与持久化文件。 */
  final Future<void> Function(PlaybackSettings settings)
      onPlaybackSettingsChanged;
  final List<String> activeTags;
  final String? activeChildTag;
  final String queueTitle;
  /** 删除媒体库记录，并按用户确认结果选择是否把本地文件移入回收站。 */
  final Future<void> Function(VideoItem item, bool moveLocalFileToTrash)
      onDeleteVideo;
  final Future<void> Function(VideoItem item) onToggleFavorite;
  /** 通过媒体库协调物理文件与稳定 mutable path 的同目录重命名事务。 */
  final Future<void> Function(VideoItem item, String newBaseName) onRenameFile;
  final Future<void> Function(VideoItem item) onEditManualTags;
  final Future<bool> Function(VideoItem item) onRelinkMissing;
  final Future<void> Function(
    VideoItem item,
    Duration position,
    Duration duration,
    bool completed,
  ) onPlaybackProgressUpdated;
  final Future<void> Function(
          VideoItem item, MediaDetails details, String? fingerprint)
      onMediaDetailsUpdated;
  /** 页面退出后由播放器原生资源释放流程完成的路由协调信号。 */
  final Completer<void> disposalCompleter;

  /** 文件选择、写入、元数据与文件管理器定位的平台边界。 */
  final FileSystemAdapter fileSystem;

  /** 可选播放器后端工厂，用于测试或原生后端 A/B 切换。 */
  final PlayerBackendFactory playerBackendFactory;

  /** 由组合根选择的媒体探测后端工厂。 */
  final MediaProbeBackendFactory mediaProbeBackendFactory;

  /** 媒体库 Route 持有的播放器全屏会话状态，不参与持久化。 */
  final PlayerFullscreenSessionController fullscreenSessionController;

  @override
  State<PlayerPage> createState() => PlayerPageState();
}

class PlayerPageState extends State<PlayerPage> {
  late final PlayerBackend _playerBackend;
  /** 诊断弹窗使用的只读播放器边界。 */
  PlayerBackend get playerBackend => _playerBackend;
  late final FocusNode _focusNode;
  late final ScrollController _queueScrollController;
  late final ScrollController _fullscreenQueueScrollController;
  late final MediaDetailsService _detailsService;
  late final String _requestedHwdec;
  late final PlayerPlaybackController _playback;
  final _openRequests = PlayerOpenRequestController();
  /** 用于把设置浮层右边缘锚定到齿轮按钮，而不是按整个窗口居中。 */
  final _settingsButtonAnchorKey = GlobalKey();
  /** 用于把画面内鼠标位置换算到底部控制区，不额外叠加拦截按钮的命中层。 */
  final _videoControlsRegionKey = GlobalKey();
  /** 正在等待兼容性确认的路径；避免快速点击叠加多个警告弹窗。 */
  String? _compatibilityPromptPath;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<String>? _playerErrorSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;
  Timer? _controlsHideTimer;
  Timer? _shortcutFeedbackTimer;
  Timer? _queuePrefetchTimer;
  Timer? _fullscreenQueueHideTimer;
  Timer? _playbackHealthTimer;
  var _playbackHealthSampling = false;
  /** 第二阶段自动画质协调器；只消费低频诊断样本，不创建额外定时器。 */
  final PlayerAdaptiveQualityCoordinator _adaptiveQualityCoordinator =
      PlayerAdaptiveQualityCoordinator();
  /** 第三阶段能力检测器；只查询当前 PlayerBackend 的真实运行属性。 */
  final PlayerGpuCapabilityDetector _gpuCapabilityDetector =
      const PlayerGpuCapabilityDetector();
  /** HDR 映射复用播放健康样本，并在压力出现后锁存关闭到下一媒体。 */
  final PlayerHdrMappingSafetyCoordinator _hdrMappingSafetyCoordinator =
      PlayerHdrMappingSafetyCoordinator();
  /** 暗部增强复用同一低频压力判定，但拥有独立计数与会话回滚锁存。 */
  final PlayerHdrMappingSafetyCoordinator _darkSceneSafetyCoordinator =
      PlayerHdrMappingSafetyCoordinator(featureLabel: '暗部增强');
  /** 当前会话已经实际送入后端的自动增强档位。 */
  PlayerAdaptiveQualityLevel _adaptiveQualityLevel =
      PlayerAdaptiveQualityLevel.off;
  /** 最近一次播放器会话能力检测结果；新媒体打开时作废并重新检测。 */
  PlayerGpuCapabilitySnapshot? _gpuCapabilitySnapshot;
  /** HDR 映射只有在当前媒体与实际活动 LUID 均通过门槛后才对本会话生效。 */
  var _hdrMappingExperimentActive = false;
  /** 当前 SDR 会话已经通过分辨率、硬解和传递函数门槛并启用暗部增强。 */
  var _darkSceneEnhancementActive = false;
  /** 暗部增强只回滚当前媒体，不改写用户的持久开关。 */
  String? _darkSceneEnhancementRollbackReason;
  /** 暗部增强自动回滚时间，用于与诊断掉帧样本对齐。 */
  DateTime? _darkSceneEnhancementRollbackAt;
  /** 当前媒体最近一次 HDR 自动回滚原因；全局开关不会被改写。 */
  String? _hdrMappingRollbackReason;
  /** 当前媒体 HDR 自动回滚发生时间，用于与掉帧和功耗基线对齐。 */
  DateTime? _hdrMappingRollbackAt;
  /** 画质余量扩展采样每两秒执行一次，供自动增强与 HDR 压力保护共享。 */
  var _qualityMarginSampleTick = 0;
  var _controlsVisible = true;
  var _shortcutFeedbackVisible = false;
  String? _shortcutFeedbackLabel;
  IconData _shortcutFeedbackIcon = Icons.keyboard_rounded;
  /** 当前快捷键反馈是否应显示为左上角快进/快退文字水印。 */
  var _shortcutFeedbackIsSeekWatermark = false;
  /** 鼠标停留在底部进度与控制区时暂停自动隐藏计时。 */
  var _pointerInControlBar = false;
  /** 设置浮层展开期间锁定底部进度与控制区为可见。 */
  var _settingsDialogOpen = false;
  DateTime? _lastProgressWriteAt;
  Duration _lastPersistedPosition = Duration.zero;
  DateTime? _ignoreQueueSelectionBefore;
  String? _handledCompletedPath;
  String? _openedPath;
  /** 当前打开请求使用的已验证缩略图；只承担原生纹理首帧占位。 */
  File? _openingPosterFile;
  /** [_openingPosterFile] 对应路径，防止快速切换时旧 Future 覆盖新视频。 */
  String? _openingPosterPath;
  int? _lastSeekLatencyMs;
  DateTime? _lastSeekAt;
  int? _lastVideoFrameNumber;
  double? _lastAudioPts;
  DateTime? _lastVideoAdvanceAt;
  DateTime? _lastAudioAdvanceAt;
  DateTime? _lastHealthSampleAt;
  /** 最近一次 mpv 明确报告的实际硬解状态，不把属性不可用误判为软件解码。 */
  String? _lastHwdecCurrent;
  var _consecutiveSoftwareDecodeSamples = 0;
  var _softwareDecodeConfirmed = false;
  var _videoProgressState = '等待首个视频样本';
  var _audioProgressState = '等待首个音频样本';
  var _videoStallEvents = 0;
  var _audioStallEvents = 0;
  var _textureReadyLogged = false;
  DateTime? _exitRequestedAt;
  /** 路由退出后继续执行的原生 stop；dispose 必须等待它结束，禁止两条命令并发释放。 */
  Future<void>? _exitStopFuture;
  DateTime? _pauseAcknowledgedAt;
  DateTime? _routePopRequestedAt;
  Duration? _pendingSeekTarget;
  var _seekInFlight = false;
  var _isExiting = false;
  /** 恢复选择弹窗期间暂停进度写入，避免刚打开的 0 秒覆盖稳定进度。 */
  var _choosingPlaybackStart = false;
  var _queueEndReached = false;
  /** 标签弹窗打开期间阻止底层播放器重复消费 Escape，避免意外返回媒体库。 */
  var _editingManualTags = false;
  /** 文件重命名事务期间阻止重复点击和播放器快捷键并发操作。 */
  var _renamingFile = false;
  /** 原生文件对话框无法可靠暴露 Flutter Focus，使用显式深度暂停全部播放器快捷键。 */
  var _shortcutSuspensionDepth = 0;
  late PlayerPlaybackMode _playbackMode;
  late double _playbackRate;
  /** 是否仅水平翻转当前视频画面，控制条与命中区域保持原方向。 */
  late bool _mirrorVideo;
  /** 当前全局画面比例；打开新媒体后会重新应用到后端。 */
  late PlayerVideoAspectMode _videoAspectMode;
  /** 当前缩放器基线；超分关闭后恢复该值。 */
  late PlayerVideoScaler _videoScaler;
  /** 当前显示输出电平策略。 */
  late PlayerVideoOutputRange _videoOutputRange;
  /** 当前全局 GPU 画质超分开关；只影响视频渲染缩放器。 */
  late bool _videoSuperResolutionEnabled;
  /** 快进与快退快捷键共用的离散跳转秒数。 */
  late int _seekStepSeconds;
  /** 当前播放器会话使用的全局配置快照。 */
  late PlaybackSettings _effectivePlaybackSettings;
  /** 页面即时音量；避免异步后端快照让滑条、图标和键盘反馈不同步。 */
  late double _volume;
  /** 一键静音前最近一次非零音量，用于准确恢复用户原值。 */
  double _lastAudibleVolume = 100;
  /** 串行保存设置，避免连续点击时旧写入覆盖最后一次选择。 */
  Future<void> _playbackSettingsSaveTail = Future<void>.value();
  /** 用户主动折叠宽屏右侧队列时保持当前页面内的显示状态。 */
  var _queueSidebarCollapsed = false;
  /** 是否由播放器页面进入桌面窗口全屏。 */
  var _isWindowFullscreen = false;
  /** 会话全屏恢复只执行一次；返回流程等待它结束，避免首帧后立即返回造成窗口命令交错。 */
  Future<void> _sessionFullscreenRestore = Future<void>.value();
  /** 全屏时是否在画面右侧显示不改变视频尺寸的当前筛选队列覆盖层。 */
  var _fullscreenQueueVisible = false;
  /** 宽屏队列折叠时，指针是否进入非全屏顶部标题栏热区。 */
  var _pointerInWindowTopBarRegion = false;
  final _random = math.Random();

  static const _playbackRates = PlaybackSettings.playbackRates;
  static const _seekStepOptions = PlaybackSettings.seekStepOptions;

  List<VideoItem> get _sourcePlaylist => _playback.sourcePlaylist;

  List<VideoItem> get _queue => _playback.queue;

  String? get _selectedChildTag => _playback.selectedChildTag;

  int get _index => _playback.playingIndex;

  int get _selectedIndex => _playback.selectedIndex;

  VideoItem get _currentItem => _playback.currentItem;

  String get _filterSummary {
    final value = widget.queueTitle.trim();
    return value.isEmpty ? '\u5168\u90e8\u89c6\u9891' : value;
  }

  String? get _activeParentTag {
    if (widget.activeTags.length != 1) {
      return null;
    }
    return widget.activeTags.first;
  }

  void _selectChildTag(String tag) {
    if (_queue.isEmpty) {
      return;
    }
    _persistOpenedProgress();
    final preferredPath = _currentItem.path;
    setState(() {
      _queueEndReached = false;
      _playback.toggleChildTag(tag, preferredPath: preferredPath);
    });
    _ensureQueueIndexVisible(_index, center: true);
    _requestOpenCurrent();
  }

  @override
  void initState() {
    super.initState();
    _isWindowFullscreen =
        widget.fullscreenSessionController.shouldOpenFullscreen;
    _effectivePlaybackSettings = widget.playbackSettings;
    _mirrorVideo = _effectivePlaybackSettings.mirrorVideo;
    _playbackMode = _effectivePlaybackSettings.playbackMode;
    _videoAspectMode = _effectivePlaybackSettings.videoAspectMode;
    _videoScaler = _effectivePlaybackSettings.videoScaler;
    _videoOutputRange = _effectivePlaybackSettings.videoOutputRange;
    _playbackRate = _effectivePlaybackSettings.playbackRate;
    _videoSuperResolutionEnabled =
        _effectivePlaybackSettings.videoSuperResolutionEnabled;
    _seekStepSeconds = _effectivePlaybackSettings.seekStepSeconds;
    _focusNode = FocusNode(debugLabel: 'player-shortcuts');
    _queueScrollController = ScrollController();
    _fullscreenQueueScrollController = ScrollController();
    _detailsService = MediaDetailsService(
      onUpdated: widget.onMediaDetailsUpdated,
      probeBackend: widget.mediaProbeBackendFactory(),
    );
    _requestedHwdec =
        PlayerHardwareAcceleration.resolve(widget.playbackSettings.hwdec);
    _playback = PlayerPlaybackController(
      sourcePlaylist: widget.playlist.isEmpty
          ? <VideoItem>[widget.initialItem]
          : widget.playlist,
      activeParentTag: _activeParentTag,
      initialChildTag: widget.activeChildTag,
      initialPath: widget.initialItem.path,
    );
    _playerBackend = widget.playerBackendFactory(
      hwdec: _requestedHwdec,
      enableHardwareAcceleration:
          widget.playbackSettings.hardwareDecodingEnabled,
    );
    _volume = _playerBackend.state.volume.clamp(0, 100).toDouble();
    if (_volume > 0) {
      _lastAudibleVolume = _volume;
    }
    _playerBackend.textureId.addListener(_handleTextureReadyForDiagnostics);
    unawaited(PlayerMemoryDiagnostics.logStage(
      'player_constructed',
      backend: _playerBackend,
    ));
    _completedSubscription =
        _playerBackend.completedChanges.listen(_handlePlaybackCompleted);
    _playerErrorSubscription =
        _playerBackend.errorChanges.listen(_handlePlayerError);
    _positionSubscription =
        _playerBackend.positionChanges.listen(_handlePosition);
    _playingSubscription = _playerBackend.playingChanges.listen((_) {
      if (!mounted) return;
      // 播放状态只同步图标；隐藏后的控制条只能由底部热区重新唤出。
      setState(() {});
    });
    _requestOpenCurrent();
    // 诊断弹窗关闭时仍持续独立观察视频帧与音频播放头，避免瞬时 AV offset 掩盖单路停滞。
    _playbackHealthTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_sampleIndependentPlaybackProgress()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (_isWindowFullscreen) {
          _sessionFullscreenRestore = _restoreSessionWindowFullscreen();
        }
        _focusNode.requestFocus();
        _ensureQueueIndexVisible(_index, center: true, animated: false);
        // 首次进入默认展示控制条，再按统一三秒规则自动收起。
        _showVideoControls();
      }
    });
  }

  /**
   * 处理播放内核在 open 完成后才报告的运行期错误。
   *
   * 打开 worker 运行期间由可播放性确认统一收口，避免旧媒体迟到错误覆盖快速切换后的新视频。
   */
  void _handlePlayerError(String _) {
    if (!mounted || _openRequests.isOpening) {
      return;
    }
    final path = _openedPath;
    if (path == null || path != _currentItem.path) {
      return;
    }
    _openedPath = null;
    _openRequests.markFailure(path, code: 'media_kit_error');
    unawaited(_playerBackend.stop());
    setState(() {});
  }

  /** 以低频写入当前已打开视频的进度，避免播放流每帧触发 SQLite。 */
  void _handlePosition(Duration position) {
    final openedPath = _openedPath;
    if (_openRequests.isOpening ||
        _choosingPlaybackStart ||
        openedPath == null ||
        position <= Duration.zero) {
      return;
    }
    final now = DateTime.now();
    final elapsed = _lastProgressWriteAt == null
        ? const Duration(days: 1)
        : now.difference(_lastProgressWriteAt!);
    final advanced = (position - _lastPersistedPosition).abs();
    if (elapsed < const Duration(seconds: 5) &&
        advanced < const Duration(seconds: 5)) {
      return;
    }
    final item = _itemForPath(openedPath);
    if (item == null) {
      return;
    }
    _lastProgressWriteAt = now;
    _lastPersistedPosition = position;
    final duration = _playerBackend.state.duration;
    unawaited(widget.onPlaybackProgressUpdated(
      item,
      position,
      duration,
      playerPlaybackIsNearCompletion(position: position, duration: duration),
    ));
  }

  /** 从来源队列解析当前路径，确保进度写入对应视频而不是刚切换的新条目。 */
  VideoItem? _itemForPath(String path) {
    for (final item in _sourcePlaylist) {
      if (TagRules.pathKey(item.path) == TagRules.pathKey(path)) {
        return item;
      }
    }
    return null;
  }

  /**
   * 处理播放完成事件，在当前 filtered queue 内顺序进入下一条。
   *
   * media_kit 在打开新媒体时会发送 false，因此路径去重只防御同一 EOF 的重复 true；
   * 到达队尾时明确停止并提示，不默认循环到队首。
   */
  void _handlePlaybackCompleted(bool completed) {
    if (!completed) {
      _handledCompletedPath = null;
      // 用户在队尾重新播放或拖动进度后，完成提示应立即退出。
      if (mounted && _queueEndReached) {
        setState(() => _queueEndReached = false);
      }
      return;
    }
    if (!mounted || _queue.isEmpty) {
      return;
    }
    final completedPath = _currentItem.path;
    // 旧媒体在快速切换期间迟到的 EOF 不能推进新队列项。
    if (_openedPath != completedPath) {
      return;
    }
    if (_handledCompletedPath == completedPath) {
      return;
    }
    _handledCompletedPath = completedPath;
    final duration = _playerBackend.state.duration;
    unawaited(
      widget.onPlaybackProgressUpdated(
        _currentItem,
        duration,
        duration,
        true,
      ),
    );
    final targetIndex = playerCompletionTargetIndex(
      mode: _playbackMode,
      currentIndex: _index,
      queueLength: _queue.length,
      randomValue: _random.nextDouble(),
    );
    if (targetIndex == null) {
      setState(() => _queueEndReached = true);
      _showQueueEndMessage();
      return;
    }
    _jumpTo(targetIndex, ignoreFollowUpSelection: true);
  }

  /** 修改倍速并立即应用到当前播放内核；切换视频时 media_kit 会保留该状态。 */
  void _setPlaybackRate(double rate) {
    if (!_playbackRates.contains(rate) || _playbackRate == rate) {
      return;
    }
    setState(() => _playbackRate = rate);
    unawaited(_playerBackend.setRate(rate));
    _saveGlobalPlaybackSettings(
      _effectivePlaybackSettings.copyWith(playbackRate: rate),
    );
  }

  /** 按固定档位调整倍速，供菜单与键盘快捷键共用同一条状态链路。 */
  void _stepPlaybackRate(int delta) {
    final current = _playbackRates.indexOf(_playbackRate);
    final next = (current + delta).clamp(0, _playbackRates.length - 1);
    _setPlaybackRate(_playbackRates[next]);
  }

  /** 更新快进与快退共用档位；仅保存固定秒数，不立即触发 seek。 */
  void _setSeekStepSeconds(int seconds) {
    if (!_seekStepOptions.contains(seconds) || _seekStepSeconds == seconds) {
      return;
    }
    setState(() => _seekStepSeconds = seconds);
    _saveGlobalPlaybackSettings(
      _effectivePlaybackSettings.copyWith(seekStepSeconds: seconds),
    );
  }

  /** 更新队列播放方式，不改变 filtered queue 的内容或顺序。 */
  void _setPlaybackMode(PlayerPlaybackMode mode) {
    if (_playbackMode == mode) return;
    setState(() {
      _playbackMode = mode;
      _queueEndReached = false;
    });
    _saveGlobalPlaybackSettings(
      _effectivePlaybackSettings.copyWith(playbackMode: mode),
    );
  }

  /** 更新全局镜像状态，不改变媒体文件、控制条方向或播放队列。 */
  void _setMirrorVideo(bool enabled) {
    if (_mirrorVideo == enabled) return;
    setState(() => _mirrorVideo = enabled);
    _saveGlobalPlaybackSettings(
      _effectivePlaybackSettings.copyWith(mirrorVideo: enabled),
    );
  }

  /**
   * 即时切换本地 GPU 画质超分并异步持久化。
   *
   * Flutter 只重绘设置开关；高质量缩放留在 mpv GPU renderer，不能在 UI isolate
   * 解码或处理视频帧，也不能触发 filtered queue 与媒体详情重算。
   */
  void _setVideoSuperResolutionEnabled(bool enabled) {
    if (_videoSuperResolutionEnabled == enabled) return;
    setState(() => _videoSuperResolutionEnabled = enabled);
    _saveGlobalPlaybackSettings(
      _effectivePlaybackSettings.copyWith(
        videoSuperResolutionEnabled: enabled,
      ),
    );
    unawaited(
      PlayerVideoSuperResolution.apply(
        backend: _playerBackend,
        enabled: enabled,
        baseScaler: _videoScaler,
      ),
    );
  }

  /**
   * 更新页面即时音量并异步送入播放后端。
   *
   * 所有按钮、键盘、滚轮和滑条入口都经过这里，保证图标与滑条即时同步，同时避免
   * 多处各自维护静音恢复值。
   */
  void _setPlayerVolume(double value) {
    final volume = value.clamp(0, 100).toDouble();
    if (_volume == volume) {
      return;
    }
    if (volume > 0) {
      _lastAudibleVolume = volume;
    }
    setState(() => _volume = volume);
    unawaited(_playerBackend.setVolume(volume));
  }

  /** 按 5 点步长调整音量，供方向键和鼠标滚轮共用。 */
  void _stepPlayerVolume(double delta) {
    _setPlayerVolume(playerVolumeAfterStep(_volume, delta));
  }

  /** 在静音与最近一次非零音量之间切换，不改变全局播放配置。 */
  void _togglePlayerMute() {
    if (_volume > 0) {
      _lastAudibleVolume = _volume;
    }
    _setPlayerVolume(
      playerVolumeAfterMuteToggle(
        currentVolume: _volume,
        lastAudibleVolume: _lastAudibleVolume,
      ),
    );
  }

  /** 仅处理视频画面内的垂直滚轮，右侧队列继续拥有自己的滚动行为。 */
  void _handleVideoPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = playerVolumeDeltaForScroll(event.scrollDelta.dy);
    if (delta != 0) {
      _stepPlayerVolume(delta);
    }
  }

  /**
   * 更新当前会话的画面比例并立即应用到 mpv。
   *
   * 自动、4:3 与 16:9 保持完整画面；铺满使用 panscan 等比裁边，主要用于
   * 1728×1080 等非 16:9 视频在全屏时消除左右留边和源内黑边的组合效果。
   */
  Future<void> _setVideoAspectMode(PlayerVideoAspectMode mode) async {
    final changed = _videoAspectMode != mode;
    if (changed && mounted) {
      setState(() => _videoAspectMode = mode);
      _saveGlobalPlaybackSettings(
        _effectivePlaybackSettings.copyWith(videoAspectMode: mode),
      );
    }
    await _applyVideoAspectMode();
  }

  /**
   * 串行保存当前播放器配置。
   *
   * 页面先更新真实播放状态，再把同一个值写回应用级配置；保存失败只提示用户，
   * 不回滚已经生效的当前会话，以免 UI 与播放内核出现二次跳变。
   */
  void _saveGlobalPlaybackSettings(PlaybackSettings settings) {
    _effectivePlaybackSettings = settings;
    _playbackSettingsSaveTail = _playbackSettingsSaveTail.then((_) async {
      try {
        await widget.onPlaybackSettingsChanged(settings);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text('播放器设置保存失败，请重试')),
            );
        }
      }
    });
  }

  /** 把页面比例状态映射为后端通用 mpv 属性；后端不支持时允许安全忽略。 */
  Future<void> _applyVideoAspectMode() async {
    await _setMpvProperty(
      'video-aspect-override',
      _videoAspectMode.mpvAspectOverride,
    );
    await _setMpvProperty('panscan', _videoAspectMode.mpvPanscan);
    // 切换模式时归零历史缩放，避免诊断或外部属性残留叠加到新的比例选择。
    await _setMpvProperty('video-zoom', '0');
    await _setMpvProperty('video-pan-x', '0');
    await _setMpvProperty('video-pan-y', '0');
  }

  /** 鼠标进入或移动时显示控制条；播放中空闲三秒后自动淡出。 */
  /**
   * 执行 seek 并记录从请求到播放器返回的耗时，供持续诊断识别随机拖动压力。
   */
  Future<void> _seekWithDiagnostics(Duration target) async {
    if (_isExiting) {
      return;
    }
    // 拖动进度条时只保留最新目标，避免大量并发 seek 让视频解码停止而音频继续推进。
    _pendingSeekTarget = target < Duration.zero ? Duration.zero : target;
    if (_seekInFlight) {
      return;
    }
    _seekInFlight = true;
    try {
      while (!_isExiting && _pendingSeekTarget != null) {
        final requested = _pendingSeekTarget!;
        _pendingSeekTarget = null;
        final stopwatch = Stopwatch()..start();
        await _playerBackend.seek(requested);
        // media_kit 的 seek Future 只代表命令已提交；等待位置接近目标后再记录真实延迟。
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (!_isExiting && DateTime.now().isBefore(deadline)) {
          final delta = (_playerBackend.state.position - requested).abs();
          if (delta <= const Duration(milliseconds: 750)) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        stopwatch.stop();
        _lastSeekLatencyMs = stopwatch.elapsedMilliseconds;
        _lastSeekAt = DateTime.now();
      }
    } finally {
      _seekInFlight = false;
    }
  }

  /**
   * 返回前先暂停音频，但保留最后一帧直到反向路由已经开始。
   *
   * 正常路径的 stop 由 dispose 串行执行，避免播放器纹理在媒体库完全接管画面前变黑
   * 或重置到 0:00；只有 pause 失败时才提前 stop，优先保证不会残留声音。
   */
  Future<void> _exitPlayer() async {
    if (_isExiting) {
      return;
    }
    _isExiting = true;
    _exitRequestedAt = DateTime.now();
    unawaited(PlayerMemoryDiagnostics.logStage(
      'exit_requested',
      backend: _playerBackend,
    ));
    _pendingSeekTarget = null;
    _openRequests.cancel();
    _detailsService.dispose();
    _persistOpenedProgress();
    var pauseAcknowledged = false;
    try {
      // pause 的确认路径比 stop 短，先确保音频静音，不能让原生 stop 阻塞路由退出。
      await _playerBackend.pause().timeout(const Duration(milliseconds: 800));
      pauseAcknowledged = true;
      _pauseAcknowledgedAt = DateTime.now();
      unawaited(PlayerMemoryDiagnostics.logStage(
        'pause_acknowledged',
        backend: _playerBackend,
      ));
    } catch (_) {
      // pause 失败时提前 stop 是音频安全兜底；正常返回不会在反向转场前清空纹理。
    }
    if (playerExitStopShouldStartBeforePop(
      pauseAcknowledged: pauseAcknowledged,
    )) {
      _exitStopFuture ??= _stopForExitDiagnostics();
    }
    // 返回媒体库前等待最后一次全局设置写入，避免用户改完立即退出时丢失配置。
    await _playbackSettingsSaveTail;
    await _sessionFullscreenRestore;
    final actuallyFullscreen = await _isActuallyWindowFullscreen();
    if (widget.fullscreenSessionController.prepareForPlayerExit(
      currentlyFullscreen: actuallyFullscreen,
    )) {
      await _restoreMaximizedWindowForRouteExit();
    }
    if (mounted) {
      _routePopRequestedAt = DateTime.now();
      Navigator.of(context).maybePop();
    }
  }

  /** 原生 stop 不阻塞路由退出，但完成时必须留下可与 GPU 计数器对齐的阶段标记。 */
  Future<void> _stopForExitDiagnostics() async {
    try {
      await _playerBackend.stop().timeout(const Duration(seconds: 3));
      await PlayerMemoryDiagnostics.logStage(
        'stop_acknowledged',
        backend: _playerBackend,
      );
    } catch (_) {
      debugPrint('PLAYER_MEMORY_STAGE stage=stop_timeout');
    }
  }

  /** 首个有效纹理ID只记录一次，避免每次尺寸变化污染阶段日志。 */
  void _handleTextureReadyForDiagnostics() {
    if (_textureReadyLogged || _playerBackend.textureId.value == null) {
      return;
    }
    _textureReadyLogged = true;
    unawaited(PlayerMemoryDiagnostics.logStage(
      'texture_ready',
      backend: _playerBackend,
    ));
  }

  /**
   * 每秒分别读取 mpv 的当前视频帧号与音频播放头。
   *
   * `estimated-frame-number` 代表视频链路是否继续交付帧，`audio-pts` 包含音频驱动延迟；
   * 两者不共用 `time-pos`，因此可以识别“画面停住但声音继续”及其反向故障。
   */
  Future<void> _sampleIndependentPlaybackProgress() async {
    if (_playbackHealthSampling || _isExiting) {
      return;
    }
    _playbackHealthSampling = true;
    try {
      final previousFrame = _lastVideoFrameNumber;
      final frame =
          _parseMpvInt(await _getMpvProperty('estimated-frame-number'));
      final audioPts = _parseMpvNumber(await _getMpvProperty('audio-pts'));
      final hwdecCurrent = await _getMpvProperty('hwdec-current');
      final now = DateTime.now();
      _lastHealthSampleAt = now;
      if (frame != null) {
        if (_lastVideoFrameNumber == null || frame != _lastVideoFrameNumber) {
          _lastVideoAdvanceAt = now;
          _videoProgressState = '视频帧持续推进';
        }
        _lastVideoFrameNumber = frame;
      }
      if (audioPts != null) {
        if (_lastAudioPts == null ||
            (audioPts - _lastAudioPts!).abs() >= 0.01) {
          _lastAudioAdvanceAt = now;
          _audioProgressState = '音频播放头持续推进';
        }
        _lastAudioPts = audioPts;
      }

      final canJudge = _playerBackend.state.playing &&
          !_playerBackend.state.buffering &&
          (_lastSeekAt == null || now.difference(_lastSeekAt!).inSeconds >= 2);
      // mpv 在已开始软件解码时可能把 hwdec-current 返回为空；平台接口不可用才保持未知。
      final effectiveHwdec =
          hwdecCurrent == 'empty' && canJudge ? 'no' : hwdecCurrent;
      if (effectiveHwdec != 'empty' && effectiveHwdec != 'unavailable') {
        _lastHwdecCurrent = effectiveHwdec;
        if (canJudge &&
            widget.playbackSettings.hardwareDecodingEnabled &&
            effectiveHwdec == 'no') {
          _consecutiveSoftwareDecodeSamples++;
        } else {
          _consecutiveSoftwareDecodeSamples = 0;
        }
      }
      if (_consecutiveSoftwareDecodeSamples >= 3 && !_softwareDecodeConfirmed) {
        _softwareDecodeConfirmed = true;
        // 运行时热切换 hwdec 会让部分超规格视频直接打开失败；只记录确认结果并保留软件回退可播放性。
        debugPrint(
          'PLAYER_HEALTH software_decode_confirmed requested=$_requestedHwdec actual=$hwdecCurrent',
        );
      }
      if (canJudge &&
          frame != null &&
          _lastVideoAdvanceAt != null &&
          now.difference(_lastVideoAdvanceAt!) >= const Duration(seconds: 3)) {
        if (_videoProgressState != '视频帧停滞') {
          _videoStallEvents++;
          debugPrint(
              'PLAYER_HEALTH video_stall frame=$frame audio_pts=$audioPts');
        }
        _videoProgressState = '视频帧停滞';
      }
      if (canJudge &&
          audioPts != null &&
          _lastAudioAdvanceAt != null &&
          now.difference(_lastAudioAdvanceAt!) >= const Duration(seconds: 3)) {
        if (_audioProgressState != '音频播放头停滞') {
          _audioStallEvents++;
          debugPrint(
              'PLAYER_HEALTH audio_stall frame=$frame audio_pts=$audioPts');
        }
        _audioProgressState = '音频播放头停滞';
      }
      if (_effectivePlaybackSettings.automaticQualityEnhancementEnabled ||
          _hdrMappingExperimentActive ||
          _darkSceneEnhancementActive) {
        _qualityMarginSampleTick++;
        if (_qualityMarginSampleTick.isEven) {
          await _sampleQualityMargin(
            sampledAt: now,
            frame: frame,
            previousFrame: previousFrame,
            hwdecCurrent: effectiveHwdec,
          );
        }
      }
    } finally {
      _playbackHealthSampling = false;
    }
  }

  /**
   * 复用播放健康 Timer 的低频样本评估自动画质与可选增强实时余量。
   *
   * 属性读取只执行一次；第二阶段协调器仅在档位变化时重建滤镜，HDR 映射只在
   * 压力触发时执行一次完整回滚，不增加新的 UI Timer 或逐帧读取。
   */
  Future<void> _sampleQualityMargin({
    required DateTime sampledAt,
    required int? frame,
    required int? previousFrame,
    required String? hwdecCurrent,
  }) async {
    final details =
        _detailsService.cachedDetailsFor(_currentItem) ?? const MediaDetails();
    final sourceFps = _parseMpvNumber(await _getMpvProperty('container-fps'));
    final estimatedFps =
        _parseMpvNumber(await _getMpvProperty('estimated-vf-fps'));
    final cacheDuration =
        _parseMpvNumber(await _getMpvProperty('demuxer-cache-duration'));
    final decoderDrops =
        _parseMpvInt(await _getMpvProperty('decoder-frame-drop-count'));
    final outputDrops =
        _parseMpvInt(await _getMpvProperty('vo-drop-frame-count'));
    final totalDrops = _parseMpvInt(await _getMpvProperty('frame-drop-count'));
    final sample = PlayerAdaptiveQualitySample(
      sampledAt: sampledAt,
      playing: _playerBackend.state.playing,
      buffering: _playerBackend.state.buffering,
      recentSeek: _lastSeekAt != null &&
          sampledAt.difference(_lastSeekAt!) < const Duration(seconds: 3),
      videoAdvanced:
          frame != null && previousFrame != null && frame > previousFrame,
      videoStalled: _videoProgressState == '视频帧停滞',
      audioStalled: _audioProgressState == '音频播放头停滞',
      width: details.width,
      height: details.height,
      hwdecCurrent: hwdecCurrent,
      sourceFps: sourceFps,
      estimatedFps: estimatedFps,
      cacheDuration: cacheDuration,
      decoderDroppedFrames: decoderDrops,
      outputDroppedFrames: outputDrops,
      totalDroppedFrames: totalDrops,
    );
    if (_effectivePlaybackSettings.automaticQualityEnhancementEnabled) {
      final decision = _adaptiveQualityCoordinator.evaluate(sample);
      if (decision.changed && !_isExiting) {
        await PlayerAdaptiveQualityEnhancer.apply(
          backend: _playerBackend,
          level: decision.level,
          darkSceneEnhancementEnabled: _darkSceneEnhancementActive,
        );
        _adaptiveQualityLevel = decision.level;
        debugPrint(
          'PLAYER_ADAPTIVE_QUALITY level=${decision.level.name} '
          'profile=${decision.profile.label} reason=${decision.reason}',
        );
      }
    }
    if (_darkSceneEnhancementActive && !_isExiting) {
      final darkDecision = _darkSceneSafetyCoordinator.evaluate(sample);
      if (darkDecision.shouldRollback) {
        final guardedPath = _openedPath;
        await PlayerAdaptiveQualityEnhancer.apply(
          backend: _playerBackend,
          level: _adaptiveQualityLevel,
          darkSceneEnhancementEnabled: false,
        );
        if (!mounted || _openedPath != guardedPath) return;
        _darkSceneEnhancementActive = false;
        _darkSceneEnhancementRollbackReason = darkDecision.reason;
        _darkSceneEnhancementRollbackAt = sampledAt;
        debugPrint(
          'PLAYER_DARK_SCENE_ENHANCEMENT rollback=true '
          'reason=${darkDecision.reason}',
        );
      }
    }
    if (!_hdrMappingExperimentActive || _isExiting) return;
    final hdrDecision = _hdrMappingSafetyCoordinator.evaluate(sample);
    if (!hdrDecision.shouldRollback) return;
    final guardedPath = _openedPath;
    await PlayerHdrMappingExperiment.apply(
      backend: _playerBackend,
      enabled: false,
    );
    if (!mounted || _openedPath != guardedPath) return;
    _hdrMappingExperimentActive = false;
    _hdrMappingRollbackReason = hdrDecision.reason;
    _hdrMappingRollbackAt = sampledAt;
    debugPrint(
      'PLAYER_HDR_MAPPING rollback=true reason=${hdrDecision.reason}',
    );
  }

  void _showVideoControls() {
    _controlsHideTimer?.cancel();
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    if (playerControlsShouldAutoHide(
      settingsOpen: _settingsDialogOpen,
      pointerInControlBar: _pointerInControlBar,
    )) {
      _controlsHideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted &&
            playerControlsShouldAutoHide(
              settingsOpen: _settingsDialogOpen,
              pointerInControlBar: _pointerInControlBar,
            )) {
          setState(() => _controlsVisible = false);
        }
      });
    }
  }

  /** 显示短时快捷键结果；控制条仍只由底部热区或设置入口唤出。 */
  void _showShortcutFeedback(
    String label,
    IconData icon, {
    bool isSeekWatermark = false,
  }) {
    _shortcutFeedbackTimer?.cancel();
    if (mounted) {
      setState(() {
        _shortcutFeedbackLabel = label;
        _shortcutFeedbackIcon = icon;
        _shortcutFeedbackIsSeekWatermark = isSeekWatermark;
        _shortcutFeedbackVisible = true;
      });
    }
    _shortcutFeedbackTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) {
        setState(() => _shortcutFeedbackVisible = false);
      }
    });
  }

  /** 控制条进出状态只协调计时，不触发播放、筛选队列或媒体后台任务。 */
  void _setPointerInControlBar(bool inside) {
    if (_pointerInControlBar == inside) {
      return;
    }
    _pointerInControlBar = inside;
    if (inside) {
      _controlsHideTimer?.cancel();
      if (!_controlsVisible && mounted) {
        setState(() => _controlsVisible = true);
      }
      return;
    }
    _showVideoControls();
  }

  /** 根据画面局部坐标识别底部 112px 控制区；画面其它区域不得唤出控制条。 */
  void _handleVideoControlsPointer(PointerEvent event) {
    final renderBox = _videoControlsRegionKey.currentContext?.findRenderObject()
        as RenderBox?;
    final inside = renderBox != null &&
        playerPointerInControlBar(
          localY: event.localPosition.dy,
          surfaceHeight: renderBox.size.height,
        );
    _setPointerInControlBar(inside);
  }

  /**
   * 抓取当前视频帧并让用户选择保存位置。
   *
   * 截图由 media_kit 获取编码后的 JPEG；文件写入只发生在用户确认保存路径后，
   * 不修改媒体库记录、缩略图缓存或当前 filtered queue。
   */
  Future<void> _saveCurrentFrameScreenshot() async {
    try {
      final bytes = await _playerBackend.screenshot(format: 'image/jpeg');
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前画面暂时无法截图')),
        );
        return;
      }
      final safeTitle =
          _currentItem.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = await _withPlayerShortcutsSuspended(
        () => widget.fileSystem.pickSavePath(
          dialogTitle: '保存当前画面',
          suggestedName:
              '${safeTitle.isEmpty ? 'video' : safeTitle}_$timestamp.jpg',
          allowedExtensions: const <String>['jpg'],
        ),
      );
      if (outputPath == null || !mounted) return;
      await widget.fileSystem.writeBytes(outputPath, bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('截图已保存')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('截图保存失败，请重试')),
      );
    }
  }

  /** 构建画面底部统一控制条，并在全屏顶部保留最小队列语境。 */
  Widget _buildVideoControls() {
    final accessibility = AppAccessibilityScope.of(context);
    final fullscreenContextVisible = playerFullscreenContextShouldShow(
      isFullscreen: _isWindowFullscreen,
      controlsVisible: _controlsVisible,
    );
    // 进入稍慢以建立层级，退出更短以快速让出画面；无障碍模式由 token 自动降级。
    final fadeDuration = accessibility.fadeDuration(
      _controlsVisible ? AppMotion.popover : AppMotion.hover,
    );
    final fullscreenContextFadeDuration = accessibility.fadeDuration(
      fullscreenContextVisible ? AppMotion.popover : AppMotion.hover,
    );
    final motionDuration = accessibility.motionDuration(
      _controlsVisible ? AppMotion.popover : AppMotion.hover,
    );
    final controlsOffset = accessibility.reduceMotion || _controlsVisible
        ? Offset.zero
        : const Offset(0, 0.025);
    return MouseRegion(
      key: _videoControlsRegionKey,
      onEnter: _handleVideoControlsPointer,
      onHover: _handleVideoControlsPointer,
      onExit: (_) {
        _setPointerInControlBar(false);
      },
      child: Stack(children: [
        if (_isWindowFullscreen)
          Positioned(
            left: 20,
            right: 20,
            top: 18,
            child: SafeArea(
              child: AnimatedOpacity(
                // 顶部语境进入略慢、退出更快；它与底部控制条方向相反，不能共用时长。
                duration: fullscreenContextFadeDuration,
                opacity: fullscreenContextVisible ? 1 : 0,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: DecoratedBox(
                    key: const ValueKey('player.fullscreen.context'),
                    decoration: BoxDecoration(
                      color: playerSurface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(AppRadius.capsule),
                      border: Border.all(color: playerBorder),
                      boxShadow: playerSoftShadow,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Text(
                          '${_index + 1} / ${_queue.length} · $_filterSummary',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: playerText,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedSlide(
            duration: motionDuration,
            curve: AppMotion.standardCurve,
            offset: controlsOffset,
            child: AnimatedOpacity(
              key: const ValueKey('player.controls.opacity'),
              duration: fadeDuration,
              opacity: _controlsVisible ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: StreamBuilder<Duration>(
                  stream: _playerBackend.positionChanges,
                  initialData: _playerBackend.state.position,
                  builder: (context, positionSnapshot) {
                    final position = positionSnapshot.data ?? Duration.zero;
                    final duration = _playerBackend.state.duration;
                    final maxMs =
                        math.max(1, duration.inMilliseconds).toDouble();
                    return Container(
                      padding: EdgeInsets.fromLTRB(
                        _isWindowFullscreen ? 24 : 14,
                        32,
                        _isWindowFullscreen ? 24 : 14,
                        _isWindowFullscreen ? 18 : 12,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xb8000000)],
                        ),
                      ),
                      child: DecoratedBox(
                        key: const ValueKey('player.controls.chrome'),
                        decoration: BoxDecoration(
                          color: playerSurface.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(color: playerBorder),
                          boxShadow: playerSoftShadow,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                          child: IconTheme(
                            data: const IconThemeData(color: playerText),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PlayerProgressSlider(
                                    sliderKey:
                                        const ValueKey('player.progress'),
                                    isFullscreen: _isWindowFullscreen,
                                    value: position.inMilliseconds
                                        .clamp(0, maxMs.toInt())
                                        .toDouble(),
                                    max: maxMs,
                                    previewIdentity: _currentItem.path,
                                    loadPreview: (target) => widget
                                        .thumbnailService
                                        .previewFrameFor(_currentItem, target),
                                    onChanged: (value) => unawaited(
                                      _seekWithDiagnostics(
                                        Duration(milliseconds: value.round()),
                                      ),
                                    ),
                                  ),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final textScaler =
                                          MediaQuery.textScalerOf(context);
                                      final textScaleFactor =
                                          textScaler.scale(12) / 12;
                                      final showTime = playerControlsShowTime(
                                        availableWidth: constraints.maxWidth,
                                        textScaleFactor: textScaleFactor,
                                      );
                                      final volumeWidth =
                                          constraints.maxWidth >= 780
                                              ? 112.0
                                              : 76.0;
                                      return Row(
                                        children: [
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  PlayerRevealFileButton(
                                                    onPressed: () => unawaited(
                                                        _revealCurrentFile()),
                                                  ),
                                                  const SizedBox(width: 2),
                                                  PlayerVolumeButton(
                                                    volume: _volume,
                                                    onPressed:
                                                        _togglePlayerMute,
                                                  ),
                                                  SizedBox(
                                                    width: volumeWidth,
                                                    child: PlayerControlSlider(
                                                      sliderKey: const ValueKey(
                                                          'player.volume'),
                                                      value: _volume,
                                                      max: 100,
                                                      trackHeight: 3,
                                                      thumbRadius: 4.5,
                                                      overlayRadius: 11,
                                                      onChanged:
                                                          _setPlayerVolume,
                                                    ),
                                                  ),
                                                  if (showTime) ...[
                                                    const SizedBox(width: 14),
                                                    Text(
                                                      '${_formatControlDuration(position)} / '
                                                      '${_formatControlDuration(duration)}',
                                                      style: const TextStyle(
                                                        color: playerTextMuted,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontFeatures: [
                                                          FontFeature
                                                              .tabularFigures(),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                          _buildTransportControls(
                                            accessibility,
                                          ),
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  PlayerChromeButton(
                                                    key: const ValueKey(
                                                        'player.screenshot'),
                                                    tooltip: '当前帧截图',
                                                    icon: Icons
                                                        .photo_camera_outlined,
                                                    onPressed: () => unawaited(
                                                        _saveCurrentFrameScreenshot()),
                                                  ),
                                                  KeyedSubtree(
                                                    key:
                                                        _settingsButtonAnchorKey,
                                                    child: PlayerChromeButton(
                                                      key: const ValueKey(
                                                          'player.settings'),
                                                      tooltip: '播放设置',
                                                      icon: Icons
                                                          .settings_outlined,
                                                      onPressed: () => unawaited(
                                                          _showControlSettingsDialog()),
                                                    ),
                                                  ),
                                                  PlayerChromeButton(
                                                    key: const ValueKey(
                                                        'player.fullscreen.toggle'),
                                                    tooltip: _isWindowFullscreen
                                                        ? '退出全屏'
                                                        : '全屏',
                                                    icon: _isWindowFullscreen
                                                        ? Icons
                                                            .fullscreen_exit_rounded
                                                        : Icons
                                                            .fullscreen_rounded,
                                                    onPressed: () => unawaited(
                                                        _toggleWindowFullscreen()),
                                                  ),
                                                  PlayerChromeButton(
                                                    key: const ValueKey(
                                                        'player.queue.toggle'),
                                                    tooltip: _isWindowFullscreen
                                                        ? '播放列表'
                                                        : _queueSidebarCollapsed
                                                            ? '展开筛选结果队列'
                                                            : '折叠筛选结果队列',
                                                    icon: Icons
                                                        .playlist_play_rounded,
                                                    onPressed:
                                                        _toggleQueueVisibility,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ]),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /** 构建视觉上始终居中的上一条、播放/暂停与下一条传输控制。 */
  Widget _buildTransportControls(AppAccessibilityData accessibility) {
    final playing = _playerBackend.state.playing;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerChromeButton(
          tooltip: '上一条',
          icon: Icons.skip_previous_rounded,
          onPressed: _playback.previousIndex == null
              ? null
              : () => _jumpTo(
                    _playback.previousIndex!,
                    ignoreFollowUpSelection: true,
                  ),
        ),
        const SizedBox(width: 6),
        PlayerChromeButton(
          tooltip: playing ? '暂停' : '播放',
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          primary: true,
          size: 46,
          iconSize: 27,
          onPressed: () {
            unawaited(_playerBackend.playOrPause());
            _showVideoControls();
          },
          iconChild: AnimatedSwitcher(
            duration: accessibility.fadeDuration(AppMotion.press),
            transitionBuilder: (child, animation) {
              final scale = accessibility.reduceMotion
                  ? animation
                  : Tween<double>(begin: 0.92, end: 1).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: scale, child: child),
              );
            },
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(playing),
            ),
          ),
        ),
        const SizedBox(width: 6),
        PlayerChromeButton(
          tooltip: '下一条',
          icon: Icons.skip_next_rounded,
          onPressed: _playback.nextIndex == null
              ? null
              : () => _jumpTo(
                    _playback.nextIndex!,
                    ignoreFollowUpSelection: true,
                  ),
        ),
      ],
    );
  }

  /** 切换常规侧栏或全屏同层队列，不改变 filtered queue 与当前播放索引。 */
  void _toggleQueueVisibility() {
    if (_isWindowFullscreen) {
      if (_fullscreenQueueVisible) {
        _fullscreenQueueHideTimer?.cancel();
        _fullscreenQueueHideTimer = null;
        setState(() => _fullscreenQueueVisible = false);
      } else {
        _showFullscreenQueueSidebar();
      }
      return;
    }
    setState(() {
      _queueSidebarCollapsed = !_queueSidebarCollapsed;
      // 队列重新展开后顶栏改为常驻，不再保留临时 hover 状态。
      if (!_queueSidebarCollapsed) {
        _pointerInWindowTopBarRegion = false;
      }
    });
  }

  /** 切换桌面窗口全屏，并让页面布局与窗口状态同步更新。 */
  Future<void> _toggleWindowFullscreen() async {
    final target = !_isWindowFullscreen;
    _fullscreenQueueHideTimer?.cancel();
    _fullscreenQueueHideTimer = null;
    await windowManager.setFullScreen(target);
    if (!mounted) {
      return;
    }
    setState(() {
      _isWindowFullscreen = target;
      _fullscreenQueueVisible = false;
      _pointerInWindowTopBarRegion = false;
    });
    widget.fullscreenSessionController.recordPlayerFullscreen(target);
    _showVideoControls();
  }

  /** 首帧提交后恢复当前会话记住的播放器全屏，普通最大化进入时不会调用。 */
  Future<void> _restoreSessionWindowFullscreen() async {
    try {
      await windowManager.setFullScreen(true);
    } catch (error) {
      // 平台边界拒绝全屏时回退为普通窗口，并清除会话标记，避免后续每次进入重复失败。
      widget.fullscreenSessionController.recordPlayerFullscreen(false);
      if (mounted) {
        setState(() => _isWindowFullscreen = false);
      }
      debugPrint('PLAYER_FULLSCREEN_RESTORE_FAILED error=$error');
    }
  }

  /** 退出 Route 前以插件实际状态兜底，防止异步窗口回调与页面布尔值短暂不同步。 */
  Future<bool> _isActuallyWindowFullscreen() async {
    if (_isWindowFullscreen) {
      return true;
    }
    try {
      return await windowManager.isFullScreen();
    } catch (_) {
      return false;
    }
  }

  /**
   * 全屏播放器返回时先退出系统全屏，再最大化底层应用窗口。
   *
   * 此处故意不清除会话全屏标记：媒体库保持最大化，下一次进入播放器才恢复全屏。
   */
  Future<void> _restoreMaximizedWindowForRouteExit() async {
    try {
      await windowManager.setFullScreen(false);
    } catch (error) {
      debugPrint('PLAYER_FULLSCREEN_EXIT_FAILED error=$error');
    }
    try {
      await windowManager.maximize();
    } catch (error) {
      // 窗口恢复失败不能阻塞播放器释放与 Route 返回，保留日志供真实桌面诊断。
      debugPrint('PLAYER_FULLSCREEN_EXIT_MAXIMIZE_FAILED error=$error');
    }
    if (mounted) {
      setState(() {
        _isWindowFullscreen = false;
        _fullscreenQueueVisible = false;
        _pointerInWindowTopBarRegion = false;
      });
    }
  }

  /** 鼠标进入右侧热区或队列时展示全屏侧栏，并取消待执行的自动隐藏。 */
  void _showFullscreenQueueSidebar() {
    _fullscreenQueueHideTimer?.cancel();
    _fullscreenQueueHideTimer = null;
    if (mounted && !_fullscreenQueueVisible) {
      setState(() => _fullscreenQueueVisible = true);
    }
  }

  /** 鼠标离开队列宽度后短延迟收回侧栏，避免边缘抖动导致反复闪烁。 */
  void _scheduleFullscreenQueueHide() {
    if (_fullscreenQueueHideTimer?.isActive ?? false) {
      return;
    }
    _fullscreenQueueHideTimer = Timer(playerFullscreenQueueHideGrace, () {
      _fullscreenQueueHideTimer = null;
      if (mounted && _fullscreenQueueVisible) {
        setState(() => _fullscreenQueueVisible = false);
      }
    });
  }

  /**
   * 在播放器根表面持续判断全屏队列右缘或非全屏顶栏热区。
   *
   * 根级坐标避免标题栏处于展开中间帧时丢失 MouseRegion exit；只有跨越热区边界才更新状态。
   */
  void _handlePlayerPointerHover(PointerHoverEvent event) {
    if (!_isWindowFullscreen) {
      final inTopBarZone = playerPointerInWindowTopBarActivationZone(
        localY: event.localPosition.dy,
        hasWideQueueSidebar: MediaQuery.sizeOf(context).width >= 1100,
        queueCollapsed: _queueSidebarCollapsed,
      );
      if (inTopBarZone) {
        _showWindowTopBarFromPointer();
      } else {
        _hideWindowTopBarFromPointer();
      }
      return;
    }
    final inActivationZone = playerPointerInFullscreenQueueActivationZone(
      localX: event.localPosition.dx,
      surfaceWidth: MediaQuery.sizeOf(context).width,
      queueVisible: _fullscreenQueueVisible,
      edgeWidth: playerFullscreenQueueEdgeActivationWidth,
      queueWidth: playerFullscreenQueueWidth(MediaQuery.sizeOf(context).width),
    );
    if (inActivationZone) {
      if (_fullscreenQueueVisible ||
          widget.playbackSettings.fullscreenQueueEdgeHoverEnabled) {
        _showFullscreenQueueSidebar();
      }
    } else if (_fullscreenQueueVisible) {
      _scheduleFullscreenQueueHide();
    }
  }

  /** 指针进入非全屏顶部热区时临时展示已随队列收起的标题栏。 */
  void _showWindowTopBarFromPointer() {
    if (_isWindowFullscreen ||
        !_queueSidebarCollapsed ||
        _pointerInWindowTopBarRegion) {
      return;
    }
    setState(() => _pointerInWindowTopBarRegion = true);
  }

  /** 指针离开标题栏后收回临时层；队列展开时标题栏仍保持常驻。 */
  void _hideWindowTopBarFromPointer() {
    if (!_queueSidebarCollapsed || !_pointerInWindowTopBarRegion) {
      return;
    }
    setState(() => _pointerInWindowTopBarRegion = false);
  }

  /** 读取齿轮在当前普通/全屏布局中的全局矩形，供浮层实时对齐。 */
  Rect _settingsButtonRect() {
    final renderBox = _settingsButtonAnchorKey.currentContext
        ?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      return renderBox.localToGlobal(Offset.zero) & renderBox.size;
    }
    final size = MediaQuery.sizeOf(context);
    // 首帧极端竞态下回退到控制条右下区域，避免浮层退回窗口中心。
    return Rect.fromLTWH(size.width - 72, size.height - 64, 40, 40);
  }

  /** 打开齿轮锚定的分级设置，并在整个显示期间保持进度控制区可见。 */
  Future<void> _showControlSettingsDialog() async {
    if (_settingsDialogOpen) return;
    final anchorRect = _settingsButtonRect();
    _controlsHideTimer?.cancel();
    if (mounted) {
      setState(() {
        _settingsDialogOpen = true;
        _controlsVisible = true;
      });
    }
    try {
      await showPlayerSettingsDialog(
        context,
        anchorRect: anchorRect,
        mirrorVideo: _mirrorVideo,
        playbackMode: _playbackMode,
        videoAspectMode: _videoAspectMode,
        playbackRate: _playbackRate,
        seekStepSeconds: _seekStepSeconds,
        videoSuperResolutionEnabled: _videoSuperResolutionEnabled,
        playbackRates: _playbackRates,
        seekStepOptions: _seekStepOptions,
        onMirrorVideoChanged: _setMirrorVideo,
        onPlaybackModeChanged: _setPlaybackMode,
        onVideoAspectModeChanged: (mode) {
          unawaited(_setVideoAspectMode(mode));
        },
        onPlaybackRateChanged: _setPlaybackRate,
        onSeekStepChanged: _setSeekStepSeconds,
        onVideoSuperResolutionChanged: _setVideoSuperResolutionEnabled,
      );
    } finally {
      if (mounted) {
        setState(() => _settingsDialogOpen = false);
        _showVideoControls();
        _restorePlayerShortcutFocus();
      }
    }
  }

  /** 提示当前筛选队列已经播放完毕，避免用户误以为播放器卡住。 */
  void _showQueueEndMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已播放到当前筛选队列末尾，共 ${_queue.length} 项'),
        ),
      );
  }

  void _ensureQueueIndexVisible(
    int index, {
    required bool center,
    bool animated = true,
    ScrollController? controller,
    int layoutAttempt = 0,
  }) {
    if (index < 0 || index >= _queue.length) {
      return;
    }
    final targetController = controller ??
        (_isWindowFullscreen && _fullscreenQueueVisible
            ? _fullscreenQueueScrollController
            : _queueScrollController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!targetController.hasClients ||
          !targetController.position.hasContentDimensions) {
        if (layoutAttempt < 4) {
          // 首次路由/全屏队列刚挂载时列表尺寸可能晚一帧建立；有限重试确保定位请求不丢失。
          Future<void>.delayed(const Duration(milliseconds: 16), () {
            if (mounted) {
              _ensureQueueIndexVisible(
                index,
                center: center,
                animated: animated,
                controller: targetController,
                layoutAttempt: layoutAttempt + 1,
              );
            }
          });
        }
        return;
      }
      final position = targetController.position;
      final viewport = position.viewportDimension;
      final clampedOffset = playerQueueScrollOffsetForIndex(
        index: index,
        viewportExtent: viewport,
        itemExtent: playerQueueItemExtent,
        minScrollExtent: position.minScrollExtent,
        maxScrollExtent: position.maxScrollExtent,
        center: center,
      );
      if (animated) {
        unawaited(targetController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 220),
          curve: appMotionCurve,
        ));
      } else {
        targetController.jumpTo(clampedOffset);
      }
    });
  }

  void _prefetchQueueWindow({int radius = 5}) {
    if (_queue.isEmpty) {
      return;
    }
    final start = math.max(0, _index - radius);
    final end = math.min(_queue.length - 1, _index + radius);
    for (var index = start; index <= end; index++) {
      final item = _queue[index];
      if (item.isMissing) {
        // missing 条目只展示稳定状态和 Relink，不派发失效路径的媒体/缩略图 I/O。
        continue;
      }
      if (index == _index) {
        // 播放期间只补齐当前视频详情，避免滚动列表时 FFprobe 与 4K 解码争抢磁盘。
        unawaited(_detailsService.detailsFor(item, priority: true));
      }
    }
    // 播放期间不再补建队列缩略图，避免快速滚动与视频解码争抢磁盘和解码器。
  }

  /**
   * 媒体确认可播放后再预取队列窗口，避免大文件首次 open 与 FFprobe/缩略图任务争抢磁盘。
   */
  void _scheduleQueuePrefetch() {
    _queuePrefetchTimer?.cancel();
    _queuePrefetchTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted && !_openRequests.isOpening) {
        _prefetchQueueWindow();
      }
    });
  }

  Future<void> _applyPlaybackPerformanceProfile() async {
    final options = <String, String>{
      'video-sync': 'display-resample',
      'interpolation': 'no',
      // 固定解码并发，避免 FFmpeg 在高核心数机器上为单个视频扩张大量工作线程。
      'vd-lavc-threads': '4',
      'cache': 'yes',
      'hwdec': _requestedHwdec,
      // 自动硬解连续失败三帧后允许回退软件解码，优先保证视频继续播放。
      'hwdec-software-fallback': '3',
      // 允许 mpv 对高分辨率 HEVC/VP9/AV1 等编码尝试用户选择的硬解后端。
      'hwdec-codecs': 'all',
      // 缓存暂时耗尽时让 mpv 等待输入恢复，不以连续丢帧追赶播放时钟。
      'cache-pause': 'yes',
      'demuxer-readahead-secs':
          _effectivePlaybackSettings.highQualityStreamCacheEnabled ? '15' : '5',
      'demuxer-max-bytes':
          _effectivePlaybackSettings.highQualityStreamCacheEnabled
              ? '96MiB'
              : '32MiB',
      'demuxer-max-back-bytes':
          _effectivePlaybackSettings.highQualityStreamCacheEnabled
              ? '32MiB'
              : '8MiB',
    };
    for (final entry in options.entries) {
      await _setMpvProperty(entry.key, entry.value);
    }
    // 部分后端会在打开新媒体时重建参数；每次 open 前后恢复比例、倍速与超分。
    await applyPlayerOpenPreferences(
      backend: _playerBackend,
      videoAspectMode: _videoAspectMode,
      videoScaler: _videoScaler,
      videoOutputRange: _videoOutputRange,
      playbackRate: _playbackRate,
      videoSuperResolutionEnabled: _videoSuperResolutionEnabled,
      // 第三阶段实验不能仅凭持久化开关提前启动；媒体可播放后的真实 LUID、
      // Compute 与 HDR 源信号检测会在 `_detectCurrentGpuCapabilities` 中解锁。
      hdrDynamicToneMappingExperimentEnabled: false,
    );
  }

  Future<void> _setMpvProperty(String property, String value) async {
    try {
      final platform = _playerBackend;
      await platform.setProperty(property, value);
    } catch (_) {
      // 部分 mpv 构建会拒绝少数属性；诊断信息会展示实际生效值。
    }
  }

  Future<String> _getMpvProperty(String property) async {
    try {
      final platform = _playerBackend;
      final value = await platform.getProperty(property);
      final text = value.toString().trim();
      return text.isEmpty ? 'empty' : text;
    } catch (error) {
      return 'unavailable';
    }
  }

  void _requestOpenCurrent() {
    if (_queue.isEmpty) {
      return;
    }
    _prepareOpeningPoster(_currentItem);
    if (_currentItem.isMissing) {
      _openedPath = null;
      _openRequests.markFailure(
        _currentItem.path,
        code: 'missing_media',
      );
      if (mounted) {
        setState(() {});
      }
      return;
    }
    final compatibility = PlayerHardwareCompatibility.assess(
      details: _currentItem.mediaDetails,
      settings: widget.playbackSettings,
    );
    if (_openedPath != null &&
        _openedPath != _currentItem.path &&
        compatibility.status == HardwareDecodeCompatibilityStatus.unsupported) {
      // 队列切换先保留当前播放会话；超规格媒体不交给 open worker。
      unawaited(_confirmQueueHardwareDecodeRisk(
        _currentItem,
        compatibility,
      ));
      return;
    }
    if (_openRequests.request(_currentItem.path)) {
      unawaited(_drainOpenRequests());
    }
  }

  /**
   * 读取当前进程已验证缩略图；缓存尚未落入同步索引时只补一次轻量异步查询。
   *
   * 媒体库在压入播放器 Route 前已经预热当前队列，因此这里不会启动 FFmpeg；
   * 路径校验避免快速点选队列时过期缩略图闪到新媒体上。
   */
  void _prepareOpeningPoster(VideoItem item) {
    final path = item.path;
    if (_openingPosterPath == path) {
      return;
    }
    _openingPosterPath = path;
    _openingPosterFile = widget.thumbnailService.cachedThumbnailFor(item);
    if (_openingPosterFile != null) {
      debugPrint(
        'PLAYER_OPEN_POSTER status=ready file=${p.basename(path)} source=memory',
      );
      return;
    }
    unawaited(widget.thumbnailService.thumbnailFor(item).then((file) {
      if (!mounted || _openingPosterPath != path || file == null) {
        if (mounted && _openingPosterPath == path) {
          debugPrint(
            'PLAYER_OPEN_POSTER status=missing file=${p.basename(path)}',
          );
        }
        return;
      }
      setState(() => _openingPosterFile = file);
      debugPrint(
        'PLAYER_OPEN_POSTER status=ready file=${p.basename(path)} source=async',
      );
    }));
  }

  /**
   * 串行阻止播放器队列内的超规格视频。
   *
   * 取消时恢复已经打开的视频索引；用户快速选择其它项时丢弃旧结果并重新评估
   * 最新选择，避免过期弹窗打开错误媒体。
   */
  Future<void> _confirmQueueHardwareDecodeRisk(
    VideoItem item,
    HardwareDecodeCompatibilityAssessment compatibility,
  ) async {
    if (_compatibilityPromptPath != null) {
      return;
    }
    final requestedPath = item.path;
    _compatibilityPromptPath = requestedPath;
    await showPlayerHardwareDecodeWarningDialog(
      context,
      compatibility,
    );
    _compatibilityPromptPath = null;
    if (!mounted) {
      return;
    }
    if (_currentItem.path != requestedPath) {
      _requestOpenCurrent();
      return;
    }
    final openedPath = _openedPath;
    final openedIndex = openedPath == null
        ? -1
        : _queue.indexWhere((video) => video.path == openedPath);
    if (openedIndex >= 0) {
      setState(() => _playback.jumpTo(openedIndex));
      _ensureQueueIndexVisible(openedIndex, center: true);
    }
  }

  Future<void> _drainOpenRequests() async {
    if (mounted) {
      setState(_openRequests.beginDrain);
    }
    var shouldContinue = false;
    try {
      while (mounted) {
        final path = _openRequests.takePendingPath();
        if (path == null) {
          break;
        }
        try {
          // 每个新媒体独立判断实际解码器，不能沿用上一条视频的 no/恢复状态。
          _lastHwdecCurrent = null;
          _consecutiveSoftwareDecodeSamples = 0;
          _softwareDecodeConfirmed = false;
          _adaptiveQualityCoordinator.reset();
          _adaptiveQualityLevel = PlayerAdaptiveQualityLevel.off;
          _qualityMarginSampleTick = 0;
          _gpuCapabilitySnapshot = null;
          _hdrMappingExperimentActive = false;
          _darkSceneEnhancementActive = false;
          _darkSceneSafetyCoordinator.reset();
          _darkSceneEnhancementRollbackReason = null;
          _darkSceneEnhancementRollbackAt = null;
          _hdrMappingSafetyCoordinator.reset();
          _hdrMappingRollbackReason = null;
          _hdrMappingRollbackAt = null;
          // 新媒体必须先清除上一条的滤镜，再从本条稳定样本逐级恢复。
          await PlayerAdaptiveQualityEnhancer.apply(
            backend: _playerBackend,
            level: PlayerAdaptiveQualityLevel.off,
            darkSceneEnhancementEnabled: false,
          );
          await _applyPlaybackPerformanceProfile();
          if (!mounted) {
            return;
          }
          await _playerBackend.openPath(path);
          if (!mounted) {
            return;
          }
          await _applyPlaybackPerformanceProfile();
          final playable = await _waitForPlayableMedia();
          if (!playable) {
            // 快速切换已有更新请求时只放弃旧验证，不展示过时错误。
            if (!_openRequests.hasPending) {
              _openedPath = null;
              _openRequests.markFailure(
                path,
                code: 'unplayable_media',
              );
              await _playerBackend.stop();
            }
            continue;
          }
          _openedPath = path;
          unawaited(_detectCurrentGpuCapabilities(path));
          unawaited(PlayerMemoryDiagnostics.logStage(
            'media_opened',
            backend: _playerBackend,
          ));
          _openRequests.markSuccess();
          _scheduleQueuePrefetch();
          final openedItem = _itemForPath(path);
          if (openedItem != null) {
            _lastPersistedPosition = Duration.zero;
            _lastProgressWriteAt = null;
            _choosingPlaybackStart = true;
            try {
              await _choosePlaybackStart(openedItem);
            } finally {
              _choosingPlaybackStart = false;
            }
          }
        } catch (error) {
          if (!mounted) {
            return;
          }
          // 只记录错误类型，避免异常正文中的本地路径进入 UI 或可复制诊断摘要。
          _openRequests.markFailure(
            path,
            code: error.runtimeType.toString(),
          );
        }
      }
    } finally {
      shouldContinue = mounted && _openRequests.hasPending;
      _openRequests.finishDrain(keepOpening: shouldContinue);
      if (mounted && !shouldContinue) {
        setState(() {});
      }
    }
    if (shouldContinue) {
      unawaited(_drainOpenRequests());
    }
  }

  /**
   * 媒体确认可播放后检测当前 GPU 渲染会话；过期 open 的结果不得覆盖新媒体。
   */
  Future<void> _detectCurrentGpuCapabilities(String openedPath) async {
    final snapshot = await _gpuCapabilityDetector.detect(_playerBackend);
    if (!mounted || _openedPath != openedPath) return;
    final experimentAllowed =
        _effectivePlaybackSettings.hdrDynamicToneMappingExperimentEnabled &&
            snapshot.selectedAdapter != null &&
            snapshot.computeShaderVerified &&
            snapshot.hdrSourceDetected;
    final darkSceneAllowed =
        _effectivePlaybackSettings.darkSceneEnhancementEnabled &&
            snapshot.darkSceneEnhancementEligible;
    await PlayerAdaptiveQualityEnhancer.apply(
      backend: _playerBackend,
      level: _adaptiveQualityLevel,
      darkSceneEnhancementEnabled: darkSceneAllowed,
    );
    await PlayerHdrMappingExperiment.apply(
      backend: _playerBackend,
      enabled: experimentAllowed,
    );
    if (!mounted || _openedPath != openedPath) {
      // 能力查询期间若已切换媒体，不允许旧 HDR 结论泄漏到新会话。
      await PlayerHdrMappingExperiment.apply(
        backend: _playerBackend,
        enabled: false,
      );
      await PlayerAdaptiveQualityEnhancer.apply(
        backend: _playerBackend,
        level: _adaptiveQualityLevel,
        darkSceneEnhancementEnabled: false,
      );
      return;
    }
    _gpuCapabilitySnapshot = snapshot;
    _hdrMappingExperimentActive = experimentAllowed;
    _darkSceneEnhancementActive = darkSceneAllowed;
    if (darkSceneAllowed) {
      // 从真实滤镜应用后再建立压力基线，媒体打开阶段不能算入暗部增强成本。
      _darkSceneSafetyCoordinator.reset();
    }
    if (experimentAllowed) {
      // 从实验真正启用后再建立累计掉帧基线，避免把媒体打开阶段算作 HDR 成本。
      _hdrMappingSafetyCoordinator.reset();
    }
    debugPrint(
      'PLAYER_GPU_CAPABILITY renderer=${snapshot.rendererDetected} '
      'api=${snapshot.gpuApi} context=${snapshot.gpuContext} '
      'vulkan=${snapshot.vulkanDetected} compute=${snapshot.computeShaderVerified}',
    );
  }

  /**
   * 等待本地媒体产生有效时长或 codec 证据。
   *
   * 0 字节/损坏 MP4 的 `Player.open` 可能成功返回却永久停在 00:00；限定等待窗口后将其
   * 归入稳定错误面板。检测期间如出现更新 open 请求则立即放弃旧验证，保护快速切换流畅度。
   */
  Future<bool> _waitForPlayableMedia() async {
    const attempts = 6;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (_openRequests.hasPending) {
        return false;
      }
      final videoCodec = await _getMpvProperty('video-codec');
      final audioCodec = await _getMpvProperty('audio-codec');
      if (playerMediaStateIsPlayable(
        duration: _playerBackend.state.duration,
        videoCodec: videoCodec,
        audioCodec: audioCodec,
      )) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  /** 按设置页默认行为处理有效进度；仅“每次询问”继续弹出选择框。 */
  Future<void> _choosePlaybackStart(VideoItem item) async {
    final duration = _playerBackend.state.duration;
    final saved = playerResumePosition(
      saved: item.playbackPosition,
      duration: duration,
      completed: item.playbackCompleted,
    );
    if (saved == null) {
      return;
    }
    final behavior = widget.playbackSettings.resumeBehavior;
    PlayerResumeChoice choice;
    if (behavior == PlaybackResumeBehavior.ask) {
      await _playerBackend.pause();
      if (!mounted || _openedPath != item.path) {
        return;
      }
      choice = await showPlayerResumeDialog(
        context,
        item: item,
        position: saved,
        duration: duration,
      );
    } else {
      choice = behavior == PlaybackResumeBehavior.continueWatching
          ? PlayerResumeChoice.continueWatching
          : PlayerResumeChoice.restart;
    }
    if (!mounted || _openedPath != item.path) {
      return;
    }
    final start =
        choice == PlayerResumeChoice.continueWatching ? saved : Duration.zero;
    await _seekWithDiagnostics(start);
    await _playerBackend.play();
    _lastPersistedPosition = start;
    _lastProgressWriteAt = DateTime.now();
    if (choice == PlayerResumeChoice.restart) {
      unawaited(widget.onPlaybackProgressUpdated(
        item,
        Duration.zero,
        duration,
        false,
      ));
    }
  }

  /** 从失败面板重新关联 missing 文件，成功后原地打开同一稳定 videoId。 */
  Future<void> _relinkCurrentMissing() async {
    final item = _currentItem;
    final relinked = await _withPlayerShortcutsSuspended(
      () => widget.onRelinkMissing(item),
    );
    if (!mounted || !relinked) {
      return;
    }
    setState(() => _openRequests.clearFailure());
    _requestOpenCurrent();
  }

  /** 重新打开最近失败的视频，并继续复用 latest-request worker。 */
  void _retryFailedOpen() {
    if (_openRequests.retryFailure()) {
      setState(() => _queueEndReached = false);
      unawaited(_drainOpenRequests());
    }
  }

  /** 跳过失败项；队尾不循环，只显示当前筛选队列结束提示。 */
  void _skipFailedOpen() {
    final nextIndex = _playback.nextIndex;
    setState(() {
      _queueEndReached = nextIndex == null;
      _openRequests.clearFailure();
    });
    if (nextIndex == null) {
      _showQueueEndMessage();
      return;
    }
    _jumpTo(nextIndex, ignoreFollowUpSelection: true);
  }

  void _select(int index) {
    if (index < 0 || index >= _queue.length) {
      return;
    }
    final ignoreBefore = _ignoreQueueSelectionBefore;
    if (ignoreBefore != null) {
      if (DateTime.now().isBefore(ignoreBefore) && index != _index) {
        return;
      }
      _ignoreQueueSelectionBefore = null;
    }
    setState(() => _playback.select(index));
    // 鼠标单击发生在已经可见的队列项上，只更新选中态；若此处立刻滚动，
    // 双击的第二击会落到移动后的另一行。离屏选中项由“定位已选中”显式定位。
  }

  void _selectQueueIndex(int index, {bool center = false}) {
    if (_queue.isEmpty) {
      return;
    }
    late int nextIndex;
    setState(() => nextIndex = _playback.selectQueueIndex(index));
    _ensureQueueIndexVisible(nextIndex, center: center);
  }

  /**
   * 从离屏位置回到播放项，但保留用户当前浏览选择。
   *
   * “正在播放”是播放器事实，“已选中”是用户在队列中的浏览焦点；定位动作不得把
   * 后者静默覆盖，否则用户再点“回到选中”时会丢失原先浏览位置。
   */
  void _returnToPlayingQueueItem(ScrollController controller) {
    if (_queue.isEmpty) {
      return;
    }
    final playingIndex = _playback.locatePlayingIndex();
    _ensureQueueIndexVisible(
      playingIndex,
      center: true,
      // 显式定位需要立即落点；大队列跨段动画会连续重建 Windows 无障碍树，
      // 不仅浪费可视区域 I/O，还可能让桌面端语义桥接失稳。
      animated: false,
      controller: controller,
    );
  }

  /** 搜索当前 filtered queue 并直接定位播放，不访问全媒体库。 */
  PlayerQueueSearchOutcome _searchQueue(String query) {
    if (query.trim().isEmpty) {
      return PlayerQueueSearchOutcome.emptyQuery;
    }
    final index = playerQueueSearchIndex(
      _queue,
      query,
      startIndex: _index,
    );
    if (index == null) {
      return PlayerQueueSearchOutcome.noMatch;
    }
    _jumpTo(index, ignoreFollowUpSelection: true);
    return PlayerQueueSearchOutcome.played;
  }

  void _jumpTo(int index, {bool ignoreFollowUpSelection = false}) {
    if (index < 0 || index >= _queue.length) {
      return;
    }
    _persistOpenedProgress();
    if (ignoreFollowUpSelection) {
      _ignoreQueueSelectionBefore =
          DateTime.now().add(const Duration(milliseconds: 700));
    }
    setState(() {
      _queueEndReached = false;
      _playback.jumpTo(index);
    });
    _ensureQueueIndexVisible(index, center: true);
    _requestOpenCurrent();
  }

  /** 切换或退出前补写当前位置、总时长和动态完成态。 */
  void _persistOpenedProgress() {
    final openedPath = _openedPath;
    final position = _playerBackend.state.position;
    final duration = _playerBackend.state.duration;
    if (openedPath == null || position <= Duration.zero) {
      return;
    }
    final item = _itemForPath(openedPath);
    if (item == null) {
      return;
    }
    unawaited(widget.onPlaybackProgressUpdated(
      item,
      position,
      duration,
      playerPlaybackIsNearCompletion(position: position, duration: duration),
    ));
  }

  /** 切换队列项收藏并刷新当前页面，不重算 filtered queue。 */
  Future<void> _toggleQueueFavorite(VideoItem item) async {
    try {
      await widget.onToggleFavorite(item);
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('收藏状态更新失败，请重试')),
      );
    }
  }

  /**
   * 删除任意队列项；非播放项只调整索引，删除当前播放项时才重启播放后端。
   */
  Future<void> _deleteQueueItem(int queueIndex) async {
    if (queueIndex < 0 || queueIndex >= _queue.length) {
      return;
    }
    final item = _queue[queueIndex];
    final settings = _effectivePlaybackSettings;
    final decision = videoDeleteDecisionWithoutPrompt(settings) ??
        await showPlayerDeleteConfirmationDialog(
          context,
          item,
          initialMoveLocalFileToTrash: settings.moveDeletedFileToTrash,
        );
    if (decision == null || !mounted) {
      return;
    }

    if (settings.confirmBeforeDeletingVideo) {
      // 只有确认提交才记忆弹窗选择；取消不会改写后续删除行为。
      final saved = await _saveDeletePreferencesBeforeAction(
        settings.copyWith(
          moveDeletedFileToTrash: decision.moveLocalFileToTrash,
          confirmBeforeDeletingVideo: !decision.dontAskAgain,
        ),
      );
      if (!saved || !mounted) {
        return;
      }
    }

    try {
      final deletingPlayingItem = queueIndex == _index;
      if (deletingPlayingItem) {
        _persistOpenedProgress();
        await _playerBackend.stop();
      }
      await widget.onDeleteVideo(item, decision.moveLocalFileToTrash);
      if (!mounted) {
        return;
      }
      setState(() {
        _queueEndReached = false;
        _playback.removeItemAt(queueIndex);
      });
      if (_queue.isEmpty) {
        await _exitPlayer();
        return;
      }
      _ensureQueueIndexVisible(_index, center: true);
      if (deletingPlayingItem) {
        _requestOpenCurrent();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision.moveLocalFileToTrash ? '已移入回收站并移除媒体库记录' : '已从媒体库移除视频',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('移除失败，本地文件或媒体库记录未完成，请重试')),
      );
    }
  }

  /**
   * 删除动作使用比普通播放偏好更严格的持久化门禁。
   *
   * 先等待既有设置写入，再保存本次最终删除状态；失败时中止删除，避免后续无提示
   * 删除行为与磁盘上的设置文件分叉。
   */
  Future<bool> _saveDeletePreferencesBeforeAction(
    PlaybackSettings settings,
  ) async {
    await _playbackSettingsSaveTail;
    try {
      await widget.onPlaybackSettingsChanged(settings);
      _effectivePlaybackSettings = settings;
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('保存删除偏好失败：$error；本次未执行删除')),
          );
      }
      return false;
    }
  }

  Future<void> _showPlayerContextMenu(TapDownDetails details) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(
          value: 'info',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.info_outline),
            title: Text('\u89c6\u9891\u4fe1\u606f'),
          ),
        ),
        PopupMenuItem(
          value: 'diagnostics',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.monitor_heart_outlined),
            title: Text('\u8bca\u65ad\u68c0\u67e5'),
          ),
        ),
      ],
    );
    if (!mounted) {
      return;
    }
    switch (action) {
      case 'info':
        await _showVideoInfoDialog();
      case 'diagnostics':
        await _showDiagnosticsDialog();
    }
  }

  Future<void> _showVideoInfoDialog() async {
    final item = _currentItem;
    final stat = await widget.fileSystem.statFile(item.path);
    final details = await _detailsService.detailsFor(item);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded),
            SizedBox(width: 10),
            Text('视频信息'),
          ],
        ),
        content: SizedBox(
          width: 700,
          height: math.min(590, MediaQuery.sizeOf(context).height * 0.72),
          child: SingleChildScrollView(
            child: Column(
              children: [
                PlayerDialogSectionCard(
                  title: '文件',
                  icon: Icons.insert_drive_file_outlined,
                  child: Column(
                    children: [
                      PlayerDialogInfoRow(
                          label: '文件名', value: item.title, emphasize: true),
                      PlayerDialogInfoRow(label: '路径', value: item.path),
                      PlayerDialogInfoRow(label: '目录', value: item.folder),
                      PlayerDialogInfoRow(
                        label: '大小',
                        value: _formatBytes(stat?.size ?? item.fileSize ?? 0),
                      ),
                      PlayerDialogInfoRow(
                        label: '修改时间',
                        value: stat?.modifiedAt?.toString() ?? '未知',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                PlayerDialogSectionCard(
                  title: '媒体',
                  icon: Icons.movie_outlined,
                  child: Column(
                    children: [
                      PlayerDialogInfoRow(
                          label: '视频', value: details.videoLabel),
                      PlayerDialogInfoRow(
                          label: '音频', value: details.audioLabel),
                      PlayerDialogInfoRow(
                          label: '媒体指纹', value: item.mediaFingerprint ?? '未读取'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                PlayerDialogSectionCard(
                  title: '整理状态',
                  icon: Icons.sell_outlined,
                  child: Column(
                    children: [
                      PlayerDialogInfoRow(
                          label: '标签',
                          value: item.tags.isEmpty
                              ? '未添加'
                              : (item.tags.toList()..sort()).join('、')),
                      PlayerDialogInfoRow(
                          label: '二级标签', value: _childTagSummary(item)),
                      PlayerDialogInfoRow(
                          label: '收藏', value: item.isFavorite ? '是' : '否'),
                    ],
                  ),
                ),
                if (item.mediaDetailsError != null ||
                    item.thumbnailError != null) ...[
                  const SizedBox(height: 12),
                  PlayerDialogSectionCard(
                    title: '异常',
                    icon: Icons.warning_amber_rounded,
                    child: Column(
                      children: [
                        if (item.mediaDetailsError != null)
                          PlayerDialogInfoRow(
                              label: '媒体信息', value: item.mediaDetailsError!),
                        if (item.thumbnailError != null)
                          PlayerDialogInfoRow(
                              label: '缩略图', value: item.thumbnailError!),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDiagnosticsDialog() async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => PlaybackDiagnosticsDialog(
        playerPage: this,
        title: '\u64ad\u653e\u8bca\u65ad',
      ),
    );
  }

  /** 打开当前视频的 manual 标签编辑器，并在保存后刷新播放器上下文。 */
  Future<void> _editManualTags() async {
    _editingManualTags = true;
    try {
      await widget.onEditManualTags(_currentItem);
      if (mounted) {
        setState(() {});
      }
    } finally {
      _editingManualTags = false;
      _restorePlayerShortcutFocus();
    }
  }

  /**
   * 把文件名编辑、平台文件操作和稳定路径提交串成一个播放器内事务。
   *
   * 首次尝试不打断播放；仅当桌面文件句柄拒绝改名时才停止后端、重试并恢复原位置。
   */
  Future<void> _renameCurrentFile() async {
    if (_renamingFile) {
      return;
    }
    _renamingFile = true;
    try {
      await _withPlayerShortcutsSuspended(() async {
        final item = _currentItem;
        if (item.isMissing) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('文件缺失，请重新关联后再重命名')),
            );
          }
          return;
        }
        final newBaseName = await showPlayerRenameFileDialog(
          context,
          item: item,
        );
        if (!mounted || newBaseName == null) {
          return;
        }

        final oldPath = item.path;
        final position = _playerBackend.state.position;
        final wasPlaying = _playerBackend.state.playing;
        try {
          await widget.onRenameFile(item, newBaseName);
          if (!mounted) {
            return;
          }
          // 后端仍持有同一文件句柄时无需重新打开，只同步 path 身份供进度和诊断继续解析。
          _openedPath = item.path;
          setState(() {});
          _showRenameResult('文件已重命名');
        } on FileSystemException {
          // Windows 后端可能独占当前媒体句柄；仅在真实文件系统失败后进入一次受控重试。
          _openedPath = null;
          await _playerBackend.pause();
          await _playerBackend.stop();
          try {
            await widget.onRenameFile(item, newBaseName);
            await _reopenAfterFileRename(
              path: item.path,
              position: position,
              wasPlaying: wasPlaying,
            );
            if (mounted) {
              _showRenameResult('文件已重命名，播放状态已恢复');
            }
          } catch (error) {
            // 重试失败时原路径仍应存在；恢复旧媒体，避免一次命名错误终止当前会话。
            try {
              await _reopenAfterFileRename(
                path: oldPath,
                position: position,
                wasPlaying: wasPlaying,
              );
            } catch (_) {
              // 下方错误反馈仍保留准确重试入口；这里不以第二个异常覆盖原始失败原因。
            }
            if (mounted) {
              _showRenameResult(_playerRenameErrorMessage(error));
            }
          }
        } catch (error) {
          if (mounted) {
            _showRenameResult(_playerRenameErrorMessage(error));
          }
        }
      });
    } finally {
      _renamingFile = false;
    }
  }

  /**
   * 隔离冒烟测试入口；仍执行真实弹窗、文件占用回退和播放恢复链路。
   *
   * 生产 UI 不调用该方法，避免测试通过复制私有实现绕过播放器页面状态。
   */
  @visibleForTesting
  Future<void> renameCurrentFileForTesting() => _renameCurrentFile();

  /** 在后端因文件占用被停止后重新打开目标路径并恢复用户可见播放状态。 */
  Future<void> _reopenAfterFileRename({
    required String path,
    required Duration position,
    required bool wasPlaying,
  }) async {
    _openRequests.clearFailure();
    await _playerBackend.openPath(path);
    await _applyPlaybackPerformanceProfile();
    if (position > Duration.zero) {
      await _playerBackend.seek(position);
    }
    if (wasPlaying) {
      await _playerBackend.play();
    } else {
      await _playerBackend.pause();
    }
    _openedPath = path;
    _openRequests.markSuccess();
    _lastPersistedPosition = position;
    _lastProgressWriteAt = DateTime.now();
    if (mounted) {
      setState(() {});
    }
  }

  /** 展示不包含本地路径的重命名结果，避免异常正文泄露用户目录。 */
  void _showRenameResult(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /** 把领域校验保留为可理解文案，其它异常统一收敛为安全提示。 */
  String _playerRenameErrorMessage(Object error) {
    if (error is StateError) {
      return error.message.toString();
    }
    if (error is FileSystemException) {
      return '无法重命名文件，请检查文件是否被其它程序占用或目标名称已存在';
    }
    return '重命名失败，文件名和媒体库记录均未更改';
  }

  /**
   * 在原生文件对话框或其它不参与 Flutter Focus 树的操作期间暂停全部播放器快捷键。
   */
  Future<T> _withPlayerShortcutsSuspended<T>(
      Future<T> Function() action) async {
    _shortcutSuspensionDepth += 1;
    try {
      return await action();
    } finally {
      _shortcutSuspensionDepth = math.max(0, _shortcutSuspensionDepth - 1);
      _restorePlayerShortcutFocus();
    }
  }

  /** 搜索/弹窗收起后在下一帧把 PageDown、Escape 等键盘导航交还播放器。 */
  void _restorePlayerShortcutFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _shortcutSuspensionDepth > 0 ||
          _editingManualTags ||
          _settingsDialogOpen) {
        return;
      }
      final primaryFocus = FocusManager.instance.primaryFocus;
      if (playerFocusIsOnDifferentRoute(
        playerContext: context,
        focus: primaryFocus,
      )) {
        return;
      }
      _focusNode.requestFocus();
    });
  }

  /** 队列搜索只在收起时恢复页面焦点，展开时由 EditableText 的 autofocus 接管。 */
  void _handleQueueSearchVisibilityChanged(bool visible) {
    if (!visible) {
      _restorePlayerShortcutFocus();
    }
  }

  /** 通过平台边界定位当前媒体文件，并稳定展示失败原因。 */
  Future<void> _revealCurrentFile() async {
    try {
      await widget.fileSystem.revealInFileManager(
        playerCurrentRevealPath(_playback),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开文件位置，请确认文件仍然存在')),
        );
      }
    }
  }

  Future<PlaybackDiagnosticsSnapshot> buildDiagnosticsSnapshot() async {
    final before = _playerBackend.state.position;
    final wasPlaying = _playerBackend.state.playing;
    final wasBuffering = _playerBackend.state.buffering;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final after = _playerBackend.state.position;
    final progressMs = after.inMilliseconds - before.inMilliseconds;
    final expectedMs = wasPlaying && !wasBuffering ? 900 : 0;
    final smooth = expectedMs == 0 || progressMs >= expectedMs;
    // 播放诊断只读已有详情，打开弹窗不能为兜底探测再创建一个 media_kit Player。
    final details =
        _detailsService.cachedDetailsFor(_currentItem) ?? const MediaDetails();
    final mpv = <String, String>{};
    for (final property in const <String>[
      'hwdec-current',
      'current-vo',
      'video-codec',
      'audio-codec',
      'container-fps',
      'estimated-vf-fps',
      'display-fps',
      'video-sync',
      'interpolation',
      'vf',
      'scale',
      'cscale',
      'scaler-resizes-only',
      'video-output-levels',
      'video-params/colorlevels',
      'video-params/colormatrix',
      'video-params/primaries',
      'video-params/gamma',
      'video-target-params/colorlevels',
      'tone-mapping',
      'hdr-compute-peak',
      'allow-delayed-peak-detect',
      'gpu-api',
      'gpu-context',
      'd3d11-feature-level',
      'avsync',
      'total-avsync-change',
      'mistimed-frame-count',
      'vo-delayed-frame-count',
      'vo-drop-frame-count',
      'decoder-frame-drop-count',
      'frame-drop-count',
      'demuxer-cache-duration',
      'cache-buffering-state',
      'estimated-frame-number',
      'audio-pts',
      'native-render-requests',
      'native-rendered-frames',
      'native-skipped-renders',
      'native-texture-copies',
      'native-surface-resizes',
      'native-surface-width',
      'native-surface-height',
    ]) {
      mpv[property] = await _getMpvProperty(property);
    }
    final sampledHwdec = mpv['hwdec-current'];
    if (sampledHwdec != null &&
        sampledHwdec != 'empty' &&
        sampledHwdec != 'unavailable') {
      _lastHwdecCurrent = sampledHwdec;
    }
    final estimatedFps = _parseMpvNumber(mpv['estimated-vf-fps']);
    final frameDurationMs =
        estimatedFps == null || estimatedFps <= 0 ? null : 1000 / estimatedFps;
    final lines = <String>[
      '\u5f53\u524d\u89c6\u9891: ${_currentItem.title}',
      '\u64ad\u653e\u4f4d\u7f6e: ${_formatDuration(after)} / ${_formatDuration(_playerBackend.state.duration)}',
      '\u64ad\u653e\u72b6\u6001: ${_playerBackend.state.playing ? '\u64ad\u653e\u4e2d' : '\u6682\u505c'}',
      '\u7f13\u51b2\u72b6\u6001: ${_playerBackend.state.buffering ? '\u7f13\u51b2\u4e2d' : '\u6b63\u5e38'}',
      '\u91c7\u6837\u63a8\u8fdb: $progressMs ms / 1200 ms',
      '\u6d41\u7545\u63a8\u65ad: ${smooth ? '\u6b63\u5e38' : '\u53ef\u80fd\u5361\u987f\u6216\u89e3\u7801\u8ddf\u4e0d\u4e0a'}',
      '\u8bbe\u7f6e\u786c\u89e3: ${widget.playbackSettings.hwdec}',
      'mpv 请求硬解: $_requestedHwdec',
      'mpv \u5b9e\u9645\u786c\u89e3: ${mpv['hwdec-current']}',
      'mpv \u8f93\u51fa\u9a71\u52a8: ${mpv['current-vo']}',
      'mpv \u89c6\u9891\u7f16\u7801: ${mpv['video-codec']}',
      'mpv \u97f3\u9891\u7f16\u7801: ${mpv['audio-codec']}',
      'mpv \u5bb9\u5668 FPS: ${mpv['container-fps']}',
      'mpv \u4f30\u7b97\u89c6\u9891 FPS: ${mpv['estimated-vf-fps']}',
      '估算单帧耗时: ${frameDurationMs?.toStringAsFixed(2) ?? 'unavailable'} ms',
      'mpv \u663e\u793a FPS: ${mpv['display-fps']}',
      'mpv \u89c6\u9891\u540c\u6b65: ${mpv['video-sync']}',
      'mpv \u63d2\u5e27: ${mpv['interpolation']}',
      '自动画质协调器: ${_effectivePlaybackSettings.automaticQualityEnhancementEnabled ? '开启' : '关闭'}',
      '自动画质基线: ${_adaptiveQualityCoordinator.profile.label}',
      '自动画质档位: ${playerAdaptiveQualityLevelLabel(_adaptiveQualityLevel)}',
      '自动画质判断: ${_adaptiveQualityCoordinator.reason}',
      'mpv 视频滤镜: ${mpv['vf']}',
      '画质超分设置: ${_videoSuperResolutionEnabled ? '开启' : '关闭'}',
      'mpv GPU 缩放器: ${mpv['scale']}',
      'mpv GPU 色度缩放器: ${mpv['cscale']}',
      'mpv 仅缩放时增强: ${mpv['scaler-resizes-only']}',
      'mpv 输出电平设置: ${mpv['video-output-levels']}',
      '源色彩范围: ${mpv['video-params/colorlevels']}',
      '源色彩矩阵: ${mpv['video-params/colormatrix']}',
      '源色彩原色: ${mpv['video-params/primaries']}',
      '源传递函数: ${mpv['video-params/gamma']}',
      '实际输出色彩范围: ${mpv['video-target-params/colorlevels']}',
      'GPU 输出驱动: ${_gpuCapabilitySnapshot?.outputDriver ?? mpv['current-vo']}',
      'GPU 渲染 API: ${_gpuCapabilitySnapshot?.gpuApi ?? mpv['gpu-api']}',
      'GPU 渲染上下文: ${_gpuCapabilitySnapshot?.gpuContext ?? mpv['gpu-context']}',
      'D3D11 Feature Level: ${_gpuCapabilitySnapshot?.d3d11FeatureLevel ?? mpv['d3d11-feature-level']}',
      '原生 GPU 探测: ${_gpuCapabilitySnapshot?.capabilityMatrix.probeStatus ?? '等待检测'}',
      'GPU 设备数量: ${_gpuCapabilitySnapshot?.capabilityMatrix.adapters.length ?? 0}',
      '活动 GPU: ${_gpuCapabilitySnapshot?.selectedAdapter?.name ?? '未唯一确认'}',
      '活动 GPU 判定: ${_gpuCapabilitySnapshot?.adapterSelectionSource ?? '等待检测'}',
      '活动 GPU 专用显存: ${_gpuCapabilitySnapshot?.selectedAdapter == null ? '未确认' : _formatBytes(_gpuCapabilitySnapshot!.selectedAdapter!.dedicatedVideoMemoryBytes)}',
      '活动 GPU 本地显存预算/占用: ${_formatGpuMemoryPair(_gpuCapabilitySnapshot?.selectedAdapter?.localMemoryBudgetBytes, _gpuCapabilitySnapshot?.selectedAdapter?.localMemoryUsageBytes)}',
      'Vulkan loader / 实例: ${_gpuCapabilitySnapshot?.capabilityMatrix.vulkanLoaderAvailable == true ? '是' : '否'} / ${_gpuCapabilitySnapshot?.capabilityMatrix.vulkanInstanceAvailable == true ? '是' : '否'}',
      'Vulkan 已检测: ${_gpuCapabilitySnapshot?.vulkanDetected == true ? '是' : '否 / 未验证'}',
      'Compute Shader 已验证: ${_gpuCapabilitySnapshot?.computeShaderVerified == true ? '是' : '否'}',
      'HDR 源信号: ${_gpuCapabilitySnapshot?.hdrSourceDetected == true ? '已检测' : '未检测'}',
      'SDR 源信号: ${_gpuCapabilitySnapshot?.sdrSourceDetected == true ? '已检测' : '未检测 / 未确认'}',
      '暗部细节增强设置: ${_effectivePlaybackSettings.darkSceneEnhancementEnabled ? '开启' : '关闭'}',
      '暗部细节增强会话: ${_darkSceneEnhancementActive ? '已通过 SDR/1080p/硬解门槛并启用' : '未启用 / 门槛未通过 / 已回滚'}',
      '暗部增强压力保护: ${_darkSceneSafetyCoordinator.reason}',
      '暗部增强自动回滚原因: ${_darkSceneEnhancementRollbackReason ?? '无'}',
      '暗部增强自动回滚时间: ${_darkSceneEnhancementRollbackAt?.toIso8601String() ?? 'none'}',
      'HDR 动态映射设置: ${_effectivePlaybackSettings.hdrDynamicToneMappingExperimentEnabled ? '开启' : '关闭'}',
      'HDR 动态映射会话: ${_hdrMappingExperimentActive ? '已通过门槛并启用' : '未启用 / 门槛未通过'}',
      'HDR 会话压力保护: ${_hdrMappingSafetyCoordinator.reason}',
      'HDR 自动回滚原因: ${_hdrMappingRollbackReason ?? '无'}',
      'HDR 自动回滚时间: ${_hdrMappingRollbackAt?.toIso8601String() ?? 'none'}',
      'mpv HDR 映射曲线: ${mpv['tone-mapping']}',
      'mpv HDR 动态峰值: ${mpv['hdr-compute-peak']}',
      '第三阶段能力状态: ${_gpuCapabilitySnapshot?.readinessLabel ?? '等待当前媒体能力检测'}',
      ...?_gpuCapabilitySnapshot?.capabilityMatrix.adapters.expand(
        (adapter) => <String>[
          'GPU[${adapter.enumerationIndex}]: ${adapter.name} · '
              'VID ${adapter.vendorId.toRadixString(16).padLeft(4, '0')} '
              'DID ${adapter.deviceId.toRadixString(16).padLeft(4, '0')} · '
              'VRAM ${_formatBytes(adapter.dedicatedVideoMemoryBytes)} · '
              'D3D ${adapter.d3dFeatureLevel} · '
              'Compute ${adapter.computeShaderSupported ? '是' : '否'} · '
              'Vulkan ${adapter.vulkanSupported ? adapter.vulkanApiVersion ?? '是' : '否'}',
          for (final output in adapter.outputs)
            '显示输出 ${output.deviceName}: '
                '${output.desktopWidth}x${output.desktopHeight} · '
                '${output.bitsPerColor ?? 0} bit · '
                '${output.colorSpace ?? 'unavailable'} · '
                'HDR 信号 ${output.hdrSignalActive ? '活动' : '未活动'} · '
                '峰值 ${output.maxLuminanceNits?.toStringAsFixed(1) ?? 'unknown'} nits',
        ],
      ),
      'mpv AV \u504f\u79fb: ${mpv['avsync']}',
      'mpv AV \u7d2f\u8ba1\u4fee\u6b63: ${mpv['total-avsync-change']}',
      'mpv \u65f6\u5e8f\u5f02\u5e38\u5e27: ${mpv['mistimed-frame-count']}',
      'mpv VO \u5ef6\u8fdf\u5e27: ${mpv['vo-delayed-frame-count']}',
      'mpv VO \u6389\u5e27: ${mpv['vo-drop-frame-count']}',
      'mpv \u89e3\u7801\u6389\u5e27: ${mpv['decoder-frame-drop-count']}',
      'mpv \u603b\u6389\u5e27: ${mpv['frame-drop-count']}',
      'mpv \u7f13\u5b58\u65f6\u957f: ${mpv['demuxer-cache-duration']}',
      'mpv \u7f13\u5b58\u72b6\u6001: ${mpv['cache-buffering-state']}',
      '原生渲染请求: ${mpv['native-render-requests']}',
      '原生实际渲染帧: ${mpv['native-rendered-frames']}',
      '原生跳过渲染: ${mpv['native-skipped-renders']}',
      '原生纹理复制: ${mpv['native-texture-copies']}',
      '原生表面重建: ${mpv['native-surface-resizes']}',
      '原生表面尺寸: ${mpv['native-surface-width']}x${mpv['native-surface-height']}',
      '视频帧推进: $_videoProgressState',
      '视频当前帧号: ${_lastVideoFrameNumber ?? -1}',
      '视频停滞事件: $_videoStallEvents',
      '音频播放头推进: $_audioProgressState',
      '音频当前 PTS: ${_lastAudioPts?.toStringAsFixed(3) ?? 'unavailable'}',
      '音频停滞事件: $_audioStallEvents',
      '独立推进采样时间: ${_lastHealthSampleAt?.toIso8601String() ?? 'none'}',
      '退出请求时间: ${_exitRequestedAt?.toIso8601String() ?? 'none'}',
      '暂停确认时间: ${_pauseAcknowledgedAt?.toIso8601String() ?? 'none'}',
      '路由退出请求时间: ${_routePopRequestedAt?.toIso8601String() ?? 'none'}',
      '最近 seek 耗时: ${_lastSeekLatencyMs ?? -1} ms',
      '最近 seek 时间: ${_lastSeekAt?.toIso8601String() ?? 'none'}',
      '媒体详情活动读取: ${_detailsService.activeReads}',
      '媒体详情排队读取: ${_detailsService.queuedReads}',
      '\u89c6\u9891\u4fe1\u606f: ${details.videoLabel}',
      '\u97f3\u9891\u4fe1\u606f: ${details.audioLabel}',
      '\u5df2\u8bc6\u522b\u89c6\u9891\u8f68: ${_playerBackend.state.videoTrackCount}',
      '\u5df2\u8bc6\u522b\u97f3\u9891\u8f68: ${_playerBackend.state.audioTrackCount}',
      '\u97f3\u91cf: ${_playerBackend.state.volume.toStringAsFixed(0)}',
      '\u7f29\u7565\u56fe\u961f\u5217: ${widget.thumbnailService.isPaused ? '\u5df2\u6682\u505c' : '\u8fd0\u884c\u4e2d'}',
      '\u7f29\u7565\u56fe\u6d3b\u8dc3\u4efb\u52a1: ${widget.thumbnailService.activeJobs} / ${widget.thumbnailService.maxConcurrentJobs}',
      '\u7f29\u7565\u56fe\u540e\u53f0\u4efb\u52a1: ${widget.thumbnailService.activeBackgroundJobs} / ${widget.thumbnailService.maxBackgroundJobs}',
      '\u7f29\u7565\u56fe\u6392\u961f: ${widget.thumbnailService.queuedJobs}',
      '\u8fdb\u7a0b\u5185\u5b58: ${_formatBytes(ProcessInfo.currentRss)}',
      '\u5904\u7406\u5668\u6838\u5fc3: ${Platform.numberOfProcessors}',
      if (_openRequests.hasFailure)
        '最近打开错误类型: ${_openRequests.failureCode ?? 'unknown'}',
    ];
    return PlaybackDiagnosticsSnapshot(
      lines: lines,
      sampledAt: DateTime.now(),
      wasPlaying: wasPlaying,
      wasBuffering: wasBuffering,
      progressMs: progressMs,
      expectedMs: expectedMs,
      smooth: smooth,
      avSync: _parseMpvNumber(mpv['avsync']),
      mistimedFrames: _parseMpvInt(mpv['mistimed-frame-count']),
      voDelayedFrames: _parseMpvInt(mpv['vo-delayed-frame-count']),
      voDroppedFrames: _parseMpvInt(mpv['vo-drop-frame-count']),
      decoderDroppedFrames: _parseMpvInt(mpv['decoder-frame-drop-count']),
      totalDroppedFrames: _parseMpvInt(mpv['frame-drop-count']),
      cacheDuration: _parseMpvNumber(mpv['demuxer-cache-duration']),
      cacheBufferingState: _parseMpvNumber(mpv['cache-buffering-state']),
      hwdecCurrent: _lastHwdecCurrent,
      videoCodec:
          mpv['video-codec'] == 'empty' || mpv['video-codec'] == 'unavailable'
              ? details.videoCodec
              : mpv['video-codec'],
      videoWidth: details.width,
      videoHeight: details.height,
      seekLatencyMs: _lastSeekLatencyMs,
      detailsQueued: _detailsService.queuedReads,
      frameDurationMs: frameDurationMs,
      videoStalled: _videoProgressState == '视频帧停滞',
      audioStalled: _audioProgressState == '音频播放头停滞',
    );
  }

  static double? _parseMpvNumber(String? value) {
    final text = value?.trim();
    if (text == null ||
        text.isEmpty ||
        text == 'empty' ||
        text == 'unavailable') {
      return null;
    }
    return double.tryParse(text);
  }

  static int? _parseMpvInt(String? value) {
    final number = _parseMpvNumber(value);
    return number?.round();
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  /** 蓝图控制栏固定显示两位小时，避免时长跨小时后横向跳动。 */
  String _formatControlDuration(Duration value) {
    final hours = value.inHours.toString().padLeft(2, '0');
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 2)} ${units[unit]}';
  }

  /** 显存预算和当前进程占用必须成对展示，缺失时不以 0 冒充真实读数。 */
  String _formatGpuMemoryPair(int? budgetBytes, int? usageBytes) {
    if (budgetBytes == null || usageBytes == null) return '不可用';
    return '${_formatBytes(budgetBytes)} / ${_formatBytes(usageBytes)}';
  }

  String _childTagSummary(VideoItem item) {
    final parts = <String>[];
    for (final entry in item.childTags.entries) {
      final values = entry.value.toList()..sort();
      parts.add('${entry.key}: ${values.join(', ')}');
    }
    return parts.isEmpty ? '\u65e0' : parts.join(' / ');
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (_shortcutSuspensionDepth > 0 ||
        _editingManualTags ||
        _settingsDialogOpen ||
        playerFocusIsEditable(primaryFocus) ||
        playerFocusIsOnDifferentRoute(
          playerContext: context,
          focus: primaryFocus,
        ) ||
        playerRouteHasBlockingOverlay(context)) {
      // 输入框、弹窗、菜单和原生文件对话框统一暂停所有单键及组合播放器动作。
      return KeyEventResult.ignored;
    }
    if (_isWindowFullscreen && event.logicalKey == LogicalKeyboardKey.escape) {
      // Escape 是桌面全屏的固定安全出口，必须先于页面返回逻辑消费。
      unawaited(_toggleWindowFullscreen());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.insert &&
        HardwareKeyboard.instance.isAltPressed) {
      unawaited(_toggleQueueFavorite(_currentItem));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_currentItem.isFavorite
                ? '\u5df2\u6dfb\u52a0\u5230\u6211\u7684\u6536\u85cf'
                : '\u5df2\u53d6\u6d88\u6536\u85cf')),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete &&
        HardwareKeyboard.instance.isControlPressed &&
        HardwareKeyboard.instance.isShiftPressed) {
      unawaited(_deleteQueueItem(_selectedIndex));
      return KeyEventResult.handled;
    }
    final pressedKey = playerShortcutIdFromEvent(event);
    final shortcuts = _effectivePlaybackSettings.shortcuts;
    bool matches(PlayerShortcutAction action) =>
        pressedKey != null && shortcuts[action] == pressedKey;
    if (matches(PlayerShortcutAction.navigateBack)) {
      if (_isWindowFullscreen) {
        unawaited(_toggleWindowFullscreen());
      } else {
        unawaited(_exitPlayer());
      }
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.playPause)) {
      final playing = _playerBackend.state.playing;
      unawaited(_playerBackend.playOrPause());
      _showShortcutFeedback(
        playing ? '暂停' : '播放',
        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
      );
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.seekBackward)) {
      unawaited(_seekWithDiagnostics(
          _playerBackend.state.position - Duration(seconds: _seekStepSeconds)));
      // KeyRepeat 继续执行 seek，但同一次按住只在首次 KeyDown 展示一次反馈。
      if (playerSeekFeedbackShouldShow(isRepeat: event is KeyRepeatEvent)) {
        _showShortcutFeedback(
          '后退 $_seekStepSeconds 秒',
          Icons.fast_rewind_rounded,
          isSeekWatermark: true,
        );
      }
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.seekForward)) {
      unawaited(_seekWithDiagnostics(
          _playerBackend.state.position + Duration(seconds: _seekStepSeconds)));
      // 与快退一致，重复键事件不重新启动居中反馈动画。
      if (playerSeekFeedbackShouldShow(isRepeat: event is KeyRepeatEvent)) {
        _showShortcutFeedback(
          '前进 $_seekStepSeconds 秒',
          Icons.fast_forward_rounded,
          isSeekWatermark: true,
        );
      }
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.previous)) {
      if (_index > 0) {
        _jumpTo(_index - 1, ignoreFollowUpSelection: true);
        _showShortcutFeedback('上一条', Icons.skip_previous_rounded);
      } else {
        _showShortcutFeedback('已到队列开头', Icons.first_page_rounded);
      }
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.next)) {
      if (_index + 1 < _queue.length) {
        _jumpTo(_index + 1, ignoreFollowUpSelection: true);
        _showShortcutFeedback('下一条', Icons.skip_next_rounded);
      } else {
        _showShortcutFeedback('已到队列末尾', Icons.last_page_rounded);
      }
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.editTags)) {
      unawaited(_editManualTags());
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.screenshot)) {
      unawaited(_saveCurrentFrameScreenshot());
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.fullscreen)) {
      unawaited(_toggleWindowFullscreen());
      _showShortcutFeedback(
        _isWindowFullscreen ? '退出全屏' : '进入全屏',
        _isWindowFullscreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
      );
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.speedDown)) {
      _stepPlaybackRate(-1);
      _showShortcutFeedback('倍速 $_playbackRate×', Icons.speed_rounded);
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.speedUp)) {
      _stepPlaybackRate(1);
      _showShortcutFeedback('倍速 $_playbackRate×', Icons.speed_rounded);
      return KeyEventResult.handled;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _stepPlayerVolume(5);
        _showShortcutFeedback(
          '音量 ${_volume.round()}%',
          Icons.volume_up_rounded,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _stepPlayerVolume(-5);
        _showShortcutFeedback(
          '音量 ${_volume.round()}%',
          _volume == 0 ? Icons.volume_off_rounded : Icons.volume_down_rounded,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _selectQueueIndex(0, center: true);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _selectQueueIndex(_queue.length - 1, center: true);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _jumpTo(_selectedIndex, ignoreFollowUpSelection: true);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons == kBackMouseButton) {
      unawaited(_exitPlayer());
    }
  }

  @override
  void dispose() {
    // 路由或测试直接卸载播放器时同样进入退出态，禁止尚未结束的健康采样把释放期停顿误判为 HDR 压力。
    _isExiting = true;
    _openRequests.cancel();
    _controlsHideTimer?.cancel();
    _shortcutFeedbackTimer?.cancel();
    _queuePrefetchTimer?.cancel();
    _fullscreenQueueHideTimer?.cancel();
    _playbackHealthTimer?.cancel();
    _playerBackend.textureId.removeListener(_handleTextureReadyForDiagnostics);
    _detailsService.dispose();
    _persistOpenedProgress();
    _queueScrollController.dispose();
    _fullscreenQueueScrollController.dispose();
    _focusNode.dispose();
    unawaited(_releaseAsyncResources());
    super.dispose();
  }

  /**
   * 等待流订阅和 media_kit 原生播放器真正释放，再通知媒体库允许下一次进入。
   */
  Future<void> _releaseAsyncResources() async {
    final releaseStartedAt = DateTime.now();
    await PlayerMemoryDiagnostics.logStage(
      'dispose_started',
      backend: _playerBackend,
    );
    try {
      await Future.wait<void>([
        if (_completedSubscription != null) _completedSubscription!.cancel(),
        if (_playerErrorSubscription != null)
          _playerErrorSubscription!.cancel(),
        if (_positionSubscription != null) _positionSubscription!.cancel(),
        if (_playingSubscription != null) _playingSubscription!.cancel(),
      ]);
      // stop 与 dispose 必须串行；此前路由 pop 后两者可能并发进入 media_kit/libmpv，
      // 导致纹理解绑完成但解码池和驱动缓存更晚才释放。
      await (_exitStopFuture ??= _stopForExitDiagnostics());
      await _playerBackend.dispose();
      await _playerBackend.released;
    } finally {
      await PlayerMemoryDiagnostics.logStage('player_disposed');
      debugPrint(
        'PLAYER_EXIT requested=${_exitRequestedAt?.toIso8601String()} '
        'pause_ack=${_pauseAcknowledgedAt?.toIso8601String()} '
        'pop=${_routePopRequestedAt?.toIso8601String()} '
        'dispose_start=${releaseStartedAt.toIso8601String()} '
        'dispose_end=${DateTime.now().toIso8601String()}',
      );
      if (!widget.disposalCompleter.isCompleted) {
        widget.disposalCompleter.complete();
      }
    }
  }

  /** 构建当前 filtered queue 侧栏；不同布局实例使用独立滚动控制器。 */
  Widget _buildQueueSidebar({
    ScrollController? scrollController,
    Key? key,
    bool edgeToEdge = false,
    double? width,
  }) {
    final controller = scrollController ?? _queueScrollController;
    final queuePanel = PlayerQueueSidebar(
      key: const ValueKey('player.queue.sidebar.content'),
      embedded: true,
      playlist: _queue,
      sourcePlaylist: _sourcePlaylist,
      playingIndex: _index,
      selectedIndex: _selectedIndex,
      scrollController: controller,
      thumbnailService: widget.thumbnailService,
      detailsService: _detailsService,
      activeTags: widget.activeTags,
      selectedChildTag: _selectedChildTag,
      onChildTagSelected: _selectChildTag,
      onSelect: _select,
      onPlay: _jumpTo,
      onReturnToPlaying: () => _returnToPlayingQueueItem(controller),
      onLocateSelected: () => _ensureQueueIndexVisible(
        _selectedIndex,
        center: true,
        // 与“回到播放”一致，一次跳转避免大队列动画期间的语义节点风暴。
        animated: false,
        controller: controller,
      ),
      onSearchQueue: _searchQueue,
      onSearchVisibilityChanged: _handleQueueSearchVisibilityChanged,
      onDeleteSelected: _queue.isEmpty
          ? null
          : () => unawaited(_deleteQueueItem(_selectedIndex)),
      onToggleFavorite: (item) => unawaited(_toggleQueueFavorite(item)),
      onDeleteItem: (index) => unawaited(_deleteQueueItem(index)),
    );
    return PlayerSidePanel(
      key: key ?? const ValueKey('player.queue.sidebar'),
      queuePanel: queuePanel,
      item: _currentItem,
      queueEndReached: _queueEndReached,
      onRenameFile: () => unawaited(_renameCurrentFile()),
      onEditManualTags: () => unawaited(_editManualTags()),
      edgeToEdge: edgeToEdge,
      width: width,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 中窄窗口改用底部队列，避免侧栏挤压蓝图式横向控制层。
    final hasWideQueueSidebar = MediaQuery.sizeOf(context).width >= 1100;
    final accessibility = AppAccessibilityScope.of(context);
    final queueSidebar = _buildQueueSidebar();
    final fullscreenQueueWidth =
        playerFullscreenQueueWidth(MediaQuery.sizeOf(context).width);
    final windowQueueCollapsed = hasWideQueueSidebar && _queueSidebarCollapsed;
    final windowTopBarVisible = playerWindowTopBarShouldShow(
      isFullscreen: _isWindowFullscreen,
      queueCollapsed: windowQueueCollapsed,
      pointerInTopBarRegion: _pointerInWindowTopBarRegion,
      accessibleNavigation: accessibility.accessibleNavigation,
    );
    final page = Theme(
      data: playerWorkspaceTheme(
        Theme.of(context),
        highContrast: accessibility.highContrast,
      ),
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Listener(
          onPointerDown: _handlePointerDown,
          child: Scaffold(
            backgroundColor: playerCanvas,
            body: MouseRegion(
              onHover: _handlePlayerPointerHover,
              onExit: (_) {
                if (_isWindowFullscreen && _fullscreenQueueVisible) {
                  _scheduleFullscreenQueueHide();
                } else if (!_isWindowFullscreen) {
                  _hideWindowTopBarFromPointer();
                }
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      children: [
                        if (!_isWindowFullscreen)
                          AnimatedSize(
                            key: const ValueKey(
                              'player.windowTopBar.visibility',
                            ),
                            alignment: Alignment.topCenter,
                            duration: accessibility.motionDuration(
                              AppMotion.popover,
                            ),
                            curve: appMotionCurve,
                            child: ClipRect(
                              child: Align(
                                alignment: Alignment.topCenter,
                                heightFactor: windowTopBarVisible ? 1 : 0,
                                child: MouseRegion(
                                  onEnter: (_) =>
                                      _showWindowTopBarFromPointer(),
                                  onExit: (_) => _hideWindowTopBarFromPointer(),
                                  child: PlayerTopBar(
                                    currentFileName: playerTopBarFileName(
                                      _currentItem.path,
                                    ),
                                    contextLabel:
                                        '${_index + 1} / ${_queue.length} · $_filterSummary',
                                    onBack: () => unawaited(_exitPlayer()),
                                    onOpenQueue: hasWideQueueSidebar
                                        ? null
                                        : () {
                                            showModalBottomSheet<void>(
                                              context: context,
                                              isScrollControlled: true,
                                              backgroundColor: playerSurface,
                                              showDragHandle: true,
                                              builder: (_) =>
                                                  FractionallySizedBox(
                                                heightFactor: 0.82,
                                                child: queueSidebar,
                                              ),
                                            );
                                          },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        key: const ValueKey(
                                            'player.video.surface'),
                                        margin: _isWindowFullscreen
                                            ? EdgeInsets.zero
                                            : const EdgeInsets.fromLTRB(
                                                16, 12, 16, 16),
                                        decoration: BoxDecoration(
                                          color: Colors.black,
                                          borderRadius: BorderRadius.circular(
                                            AppRadius.panel,
                                          ),
                                          border: Border.all(
                                            color: playerBorder,
                                          ),
                                          boxShadow: playerSoftShadow,
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Stack(
                                          children: [
                                            Positioned.fill(
                                              child: Listener(
                                                onPointerSignal:
                                                    _handleVideoPointerSignal,
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTapDown: (_) =>
                                                      _focusNode.requestFocus(),
                                                  onSecondaryTapDown:
                                                      _showPlayerContextMenu,
                                                  child: Center(
                                                    child: _playerBackend
                                                        .buildVideoSurface(
                                                      controls:
                                                          _buildVideoControls(),
                                                      fit: _videoAspectMode
                                                          .surfaceFit,
                                                      aspectRatio:
                                                          _videoAspectMode
                                                              .surfaceAspectRatio,
                                                      mirror: _mirrorVideo,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Positioned.fill(
                                              child: PlayerOpeningPoster(
                                                // 首次 build 时 open worker 尚未把 isOpening
                                                // 提交到树中；路径未确认也必须立即显示占位。
                                                opening:
                                                    _openRequests.isOpening ||
                                                        _openedPath !=
                                                            _currentItem.path,
                                                file: _openingPosterPath ==
                                                        _currentItem.path
                                                    ? _openingPosterFile
                                                    : null,
                                              ),
                                            ),
                                            Positioned.fill(
                                              child: PlayerOpeningOverlay(
                                                opening:
                                                    _openRequests.isOpening,
                                              ),
                                            ),
                                            if (!_openRequests.isOpening &&
                                                _openRequests.hasFailure)
                                              Positioned.fill(
                                                child: PlayerOpenFailurePanel(
                                                  failureCode: _openRequests
                                                          .failureCode ??
                                                      'unknown',
                                                  canSkip: _playback.hasNext,
                                                  onRetry: _retryFailedOpen,
                                                  onSkip: _skipFailedOpen,
                                                  onDiagnostics: () {
                                                    unawaited(
                                                        _showDiagnosticsDialog());
                                                  },
                                                  onRelink:
                                                      _currentItem.isMissing
                                                          ? () {
                                                              unawaited(
                                                                  _relinkCurrentMissing());
                                                            }
                                                          : null,
                                                ),
                                              ),
                                            if (_shortcutFeedbackLabel != null)
                                              if (_shortcutFeedbackIsSeekWatermark)
                                                Positioned(
                                                  left: 16,
                                                  top: 16,
                                                  child:
                                                      PlayerSeekFeedbackWatermark(
                                                    visible:
                                                        _shortcutFeedbackVisible,
                                                    label:
                                                        _shortcutFeedbackLabel!,
                                                  ),
                                                )
                                              else
                                                Positioned.fill(
                                                  child: Center(
                                                    child:
                                                        PlayerShortcutFeedback(
                                                      visible:
                                                          _shortcutFeedbackVisible,
                                                      label:
                                                          _shortcutFeedbackLabel!,
                                                      icon:
                                                          _shortcutFeedbackIcon,
                                                    ),
                                                  ),
                                                ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!_isWindowFullscreen && hasWideQueueSidebar)
                                AnimatedSize(
                                  duration: accessibility.motionDuration(
                                    AppMotion.panel,
                                  ),
                                  curve: appMotionCurve,
                                  child: ClipRect(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      widthFactor:
                                          _queueSidebarCollapsed ? 0 : 1,
                                      child: IgnorePointer(
                                        ignoring: _queueSidebarCollapsed,
                                        child: queueSidebar,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isWindowFullscreen)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !_fullscreenQueueVisible,
                        child: AnimatedSwitcher(
                          key: const ValueKey(
                            'player.fullscreenQueue.overlayMotion',
                          ),
                          duration: accessibility.motionDuration(
                            AppMotion.panel,
                          ),
                          reverseDuration: accessibility.motionDuration(
                            AppMotion.popover,
                          ),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (currentChild, previousChildren) {
                            return Stack(
                              alignment: Alignment.centerRight,
                              children: [
                                ...previousChildren,
                                if (currentChild != null) currentChild,
                              ],
                            );
                          },
                          transitionBuilder: (child, animation) {
                            // 覆盖层只做合成位移与短淡入，不改变视频纹理或大队列宽度。
                            final begin = accessibility.reduceMotion
                                ? Offset.zero
                                : const Offset(0.06, 0);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: begin,
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: _fullscreenQueueVisible
                              ? Align(
                                  key: const ValueKey(
                                    'player.fullscreenQueue.overlay',
                                  ),
                                  alignment: Alignment.centerRight,
                                  child: RepaintBoundary(
                                    child: MouseRegion(
                                      onEnter: (_) =>
                                          _showFullscreenQueueSidebar(),
                                      child: _buildQueueSidebar(
                                        key: const ValueKey(
                                          'player.fullscreenQueue.sidebar',
                                        ),
                                        scrollController:
                                            _fullscreenQueueScrollController,
                                        edgeToEdge: true,
                                        width: fullscreenQueueWidth,
                                      ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey(
                                    'player.fullscreenQueue.hidden',
                                  ),
                                ),
                        ),
                      ),
                    ),
                  if (_isWindowFullscreen &&
                      widget.playbackSettings.fullscreenQueueEdgeHoverEnabled &&
                      !_fullscreenQueueVisible)
                    Positioned(
                      key: const ValueKey('player.fullscreenQueue.edge'),
                      top: 0,
                      right: 0,
                      bottom: 0,
                      width: playerFullscreenQueueEdgeActivationWidth,
                      child: MouseRegion(
                        opaque: true,
                        onEnter: (_) => _showFullscreenQueueSidebar(),
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return PlayerRouteSemantics(child: page);
  }
}

/**
 * Apple 式播放器顶栏。
 *
 * 顶栏只展示当前播放文件名和导航动作；队列搜索保留在右侧列表内部，避免同一功能
 * 重复占用视频上方空间，也不提供绕过媒体库与 filtered queue 的“打开文件”。
 */
class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({
    super.key,
    required this.currentFileName,
    this.contextLabel,
    required this.onBack,
    required this.onOpenQueue,
  });

  /** 当前实际播放视频的完整文件名，包含扩展名。 */
  final String currentFileName;

  /** 当前 filtered queue 的序号与筛选摘要，只读展示且不参与队列计算。 */
  final String? contextLabel;

  /** 返回媒体库并释放当前播放器会话。 */
  final VoidCallback onBack;

  /** 紧凑窗口打开队列的入口；宽屏常驻队列时为空。 */
  final VoidCallback? onOpenQueue;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: const BoxDecoration(
        color: playerSurface,
        border: Border(bottom: BorderSide(color: playerBorder)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _PlayerTopBarAction(
              key: const ValueKey('player.back'),
              tooltip: '返回媒体库',
              semanticLabel: '返回媒体库',
              onPressed: onBack,
              icon: Icons.arrow_back_ios_new_rounded,
            ),
          ),
          Padding(
            // 两侧保留对称安全区，使标题不受队列按钮显隐影响而偏移。
            padding: const EdgeInsets.symmetric(horizontal: 64),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Tooltip(
                message: currentFileName,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      currentFileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: playerText,
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: AppTypography.strong,
                        height: 1.15,
                      ),
                    ),
                    if (contextLabel != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        contextLabel!,
                        key: const ValueKey('player.topbar.context'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: playerTextMuted,
                          fontSize: AppTypography.caption,
                          fontWeight: AppTypography.medium,
                          height: 1,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (onOpenQueue != null)
            Align(
              alignment: Alignment.centerRight,
              child: _PlayerTopBarAction(
                tooltip: '播放队列',
                semanticLabel: '打开播放队列',
                onPressed: onOpenQueue!,
                icon: Icons.playlist_play_rounded,
              ),
            ),
        ],
      ),
    );
  }
}

/** 顶栏紧凑动作，复用共享 press、hover、focus 与 reduced-motion 反馈。 */
class _PlayerTopBarAction extends StatelessWidget {
  const _PlayerTopBarAction({
    super.key,
    required this.tooltip,
    required this.semanticLabel,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final String semanticLabel;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: AppInteractionSurface(
        onTap: onPressed,
        semanticLabel: semanticLabel,
        padding: EdgeInsets.zero,
        backgroundColor: playerSurfaceAlt,
        child: SizedBox.square(
          dimension: 40,
          child: Icon(icon, size: 19, color: playerText),
        ),
      ),
    );
  }
}
