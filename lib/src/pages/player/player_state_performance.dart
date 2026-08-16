import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';
import '../../services/player/player_service.dart';
import 'player_queue_sidebar.dart';
import 'player_settings_panel.dart';
import 'player_video_aspect_mode.dart';
import 'player_page.dart';

/**
 * 本地文件的缓存暂停 A/B 变体；默认跑 `no`，对照组可用
 * `--dart-define=LTP_LOCAL_CACHE_PAUSE=true` 启动同素材测试。
 */
const bool localPlaybackCachePauseEnabled = bool.fromEnvironment(
  'LTP_LOCAL_CACHE_PAUSE',
  defaultValue: false,
);

// ignore_for_file: slash_for_doc_comments

/**
 * 处理设置弹窗、队列预取与播放性能配置。
 *
 * 这里只承载 [PlayerPageState] 的实现细节；播放会话、过滤队列与资源生命周期所有权
 * 仍保留在页面状态对象中。
 */
extension PlayerStatePerformance on PlayerPageState {
  Future<void> showControlSettingsDialog() async {
    if (settingsDialogOpen) return;
    final anchorRect = settingsButtonRect();
    interaction.openSettings();
    try {
      await withPlayerOverlaySurfaceOccluded(
        () => showPlayerSettingsDialog(
          context,
          anchorRect: anchorRect,
          mirrorVideo: mirrorVideo,
          playbackMode: playbackMode,
          videoAspectMode: videoAspectMode,
          playbackRate: playbackRate,
          seekStepSeconds: seekStepSeconds,
          mpvEnhancementsAvailable: mpvEnhancementsAvailable,
          videoSuperResolutionEnabled: videoSuperResolutionEnabled,
          compressionEnhancementMode: compressionEnhancementMode,
          playbackRates: PlayerPageState.playbackRates,
          seekStepOptions: PlayerPageState.seekStepOptions,
          onMirrorVideoChanged: setMirrorVideo,
          onPlaybackModeChanged: setPlaybackMode,
          onVideoAspectModeChanged: (mode) {
            unawaited(setVideoAspectMode(mode));
          },
          onPlaybackRateChanged: setPlaybackRate,
          onSeekStepChanged: setSeekStepSeconds,
          onVideoSuperResolutionChanged: setVideoSuperResolutionEnabled,
          onCompressionEnhancementModeChanged: setCompressionEnhancementMode,
          onBoundsChanged: (bounds) =>
              updateCurrentPlayerOverlaySurfaceRect(bounds.inflate(2)),
        ),
        overlayRect: estimatedSettingsOverlayRect(anchorRect),
      );
    } finally {
      if (mounted) {
        interaction.closeSettings();
        restorePlayerShortcutFocus();
      }
    }
  }

  /** 提示当前筛选队列已经播放完毕，避免用户误以为播放器卡住。 */
  void showQueueEndMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已播放到当前筛选队列末尾，共 ${queue.length} 项'),
        ),
      );
  }

  void ensureQueueIndexVisible(
    int index, {
    required bool center,
    bool animated = true,
    ScrollController? controller,
    int layoutAttempt = 0,
  }) {
    if (index < 0 || index >= queue.length) {
      return;
    }
    final targetController = controller ??
        (isWindowFullscreen && fullscreenQueueVisible
            ? fullscreenQueueScrollController
            : queueScrollController);
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
              ensureQueueIndexVisible(
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

  void prefetchQueueWindow({int radius = 5}) {
    if (queue.isEmpty) {
      return;
    }
    final start = math.max(0, index - radius);
    final end = math.min(queue.length - 1, index + radius);
    for (var queueIndex = start; queueIndex <= end; queueIndex++) {
      final item = queue[queueIndex];
      if (item.isMissing) {
        // missing 条目只展示稳定状态和 Relink，不派发失效路径的媒体/缩略图 I/O。
        continue;
      }
      if (queueIndex == index) {
        // 播放期间只补齐当前视频详情，避免滚动列表时 FFprobe 与 4K 解码争抢磁盘。
        unawaited(detailsService.detailsFor(item, priority: true));
      }
    }
    // 播放期间不再补建队列缩略图，避免快速滚动与视频解码争抢磁盘和解码器。
  }

  /**
   * 媒体确认可播放后再预取队列窗口，避免大文件首次 open 与 FFprobe/缩略图任务争抢磁盘。
   */
  void scheduleQueuePrefetch() {
    queuePrefetchTimer?.cancel();
    queuePrefetchTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted && !openRequests.isOpening) {
        prefetchQueueWindow();
      }
    });
  }

  /**
   * 在打开媒体前提交解码与缓存配置。
   *
   * 这些属性不依赖媒体元数据；同一次 open 只提交一次，避免打开后再次重复平台往返。
   */
  Future<void> applyPlaybackEngineProfile() async {
    debugPrint(
      'PLAYER_CACHE_PAUSE_AB scope=local-file '
      'variant=${localPlaybackCachePauseEnabled ? 'yes' : 'no'}',
    );
    final options = <String, String>{
      // 固定解码并发，避免 FFmpeg 在高核心数机器上为单个视频扩张大量工作线程。
      'vd-lavc-threads': '4',
      'cache': 'yes',
      'hwdec': requestedHwdec,
      // 自动硬解连续失败三帧后允许回退软件解码，优先保证视频继续播放。
      'hwdec-software-fallback': '3',
      // 允许 mpv 对高分辨率 HEVC/VP9/AV1 等编码尝试用户选择的硬解后端。
      'hwdec-codecs': 'all',
      // 本地文件不采用网络式 cache pause；保留常量开关便于同素材 A/B 对照。
      'cache-pause': localPlaybackCachePauseEnabled ? 'yes' : 'no',
      'demuxer-readahead-secs':
          effectivePlaybackSettings.highQualityStreamCacheEnabled ? '15' : '5',
      'demuxer-max-bytes':
          effectivePlaybackSettings.highQualityStreamCacheEnabled
              ? '96MiB'
              : '32MiB',
      'demuxer-max-back-bytes':
          effectivePlaybackSettings.highQualityStreamCacheEnabled
              ? '32MiB'
              : '8MiB',
    };
    try {
      // Windows 原生后端在一个平台事务内提交；MediaKit 仍由服务按既有顺序逐项写入。
      await playerService.setProperties(options);
    } catch (_) {
      // 某些后端缺少可选缓存属性时继续恢复其它播放偏好。
    }
  }

  /**
   * 媒体打开后恢复比例、缩放、输出范围、倍速和显示同步。
   *
   * 返回值中的增强状态均来自属性读回；持久开关本身不能冒充当前会话已经生效。
   */
  Future<void> applyMediaPresentationProfile() async {
    final result = await playerService.applyOpenPreferences(
      videoAspectOverride: videoAspectMode.mpvAspectOverride,
      panscan: videoAspectMode.mpvPanscan,
      videoScaler: videoScaler,
      smoothMotionMode: smoothMotionMode,
      videoOutputRange: videoOutputRange,
      playbackRate: playbackRate,
      videoSuperResolutionEnabled: videoSuperResolutionEnabled,
      // 第三阶段实验不能仅凭持久化开关提前启动；媒体可播放后的真实 LUID、
      // Compute 与 HDR 源信号检测会在 `detectCurrentGpuCapabilities` 中解锁。
      hdrDynamicToneMappingExperimentEnabled: false,
    );
    videoSuperResolutionApplyResult = result.scaling;
    videoSuperResolutionActive =
        videoSuperResolutionEnabled && result.scaling.applied;
    hdrMappingApplyResult = result.hdrToneMapping;
    smoothMotionActive = result.smoothMotion.active;
    smoothMotionApplyReason = result.smoothMotion.reason;
  }

  Future<void> setMpvProperty(String property, String value) async {
    try {
      final platform = playerService;
      await platform.setProperty(property, value);
    } catch (_) {
      // 部分 mpv 构建会拒绝少数属性；诊断信息会展示实际生效值。
    }
  }

  Future<String> getMpvProperty(String property) async {
    try {
      final platform = playerService;
      // 页面诊断再保留一层总上限；即使测试或兼容后端绕过服务默认值，
      // 健康采样、GPU 轮询和打开可播放性确认也不能永久占住页面任务。
      final value = await platform
          .getProperty(property)
          .timeout(PlayerService.defaultPropertyReadTimeout);
      final text = value.toString().trim();
      return text.isEmpty ? 'empty' : text;
    } catch (error) {
      return 'unavailable';
    }
  }
}
