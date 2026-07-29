import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../features/player/application/player_session_controller.dart';
import '../../services/media/thumbnail_service.dart';
import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

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
  State<PlayerOpeningOverlay> createState() => PlayerOpeningOverlayState();
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
  State<PlayerOpeningPoster> createState() => PlayerOpeningPosterState();
}

/** 保证占位图不会因系统“减少动态效果”而在纹理首帧前过早消失。 */
class PlayerOpeningPosterState extends State<PlayerOpeningPoster> {
  Timer? hideTimer;
  late bool visible;

  @override
  void initState() {
    super.initState();
    visible = widget.opening && widget.file != null;
  }

  @override
  void didUpdateWidget(covariant PlayerOpeningPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.opening) {
      hideTimer?.cancel();
      visible = widget.file != null;
      return;
    }
    if (oldWidget.opening && !widget.opening && visible) {
      hideTimer?.cancel();
      hideTimer = Timer(widget.hold, () {
        if (mounted && !widget.opening) {
          setState(() => visible = false);
        }
      });
    }
  }

  @override
  void dispose() {
    hideTimer?.cancel();
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
        opacity: visible ? 1 : 0,
        duration: accessibility.fadeDuration(
          const Duration(milliseconds: 600),
        ),
        curve: appMotionCurve,
        child: ColoredBox(
          color: Colors.black,
          child: Image.file(
            poster,
            key: ValueKey<String>(poster.path),
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
class PlayerOpeningOverlayState extends State<PlayerOpeningOverlay> {
  Timer? timer;
  var showOverlay = false;

  @override
  void initState() {
    super.initState();
    syncTimer();
  }

  @override
  void didUpdateWidget(covariant PlayerOpeningOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opening != widget.opening ||
        oldWidget.delay != widget.delay) {
      syncTimer();
    }
  }

  /** 每轮打开只保留一个计时器；完成时同步移除遮罩。 */
  void syncTimer() {
    timer?.cancel();
    timer = null;
    if (!widget.opening) {
      showOverlay = false;
      return;
    }
    showOverlay = false;
    timer = Timer(widget.delay, () {
      if (!mounted || !widget.opening) {
        return;
      }
      setState(() => showOverlay = true);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!showOverlay) {
      return const SizedBox.shrink();
    }
    return const ColoredBox(
      key: ValueKey('player.opening.overlay'),
      color: Color(0x66000000),
      child: Center(child: CircularProgressIndicator()),
    );
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
 * [PlayerSessionController.currentItem]，避免定位尚未开始播放的视频。
 */
String playerCurrentRevealPath(PlayerSessionController playback) =>
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
