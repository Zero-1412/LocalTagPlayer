import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/playback_settings.dart';
import '../../features/player/application/player_open_request_controller.dart';
import '../../features/player/domain/player_playback_progress.dart';
import '../../models/video_item.dart';
import '../../models/player_feature_apply_result.dart';
import '../../services/player/player_hardware_compatibility.dart';
import '../../services/player/player_adaptive_quality.dart';
import '../../services/player/player_memory_diagnostics.dart';
import 'player_hardware_decode_warning_dialog.dart';
import 'player_resume_dialog.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 协调媒体打开请求、可播放性确认与失败恢复。
 *
 * 这里只承载 [PlayerPageState] 的实现细节；播放会话、过滤队列与资源生命周期所有权
 * 仍保留在页面状态对象中。
 */
extension PlayerStateOpening on PlayerPageState {
  void requestOpenCurrent() {
    if (queue.isEmpty) {
      return;
    }
    // 新媒体不能继承上一条视频遗漏 KeyUp 的累计目标或迟到精确 seek。
    cancelKeyboardSeek();
    setOptimisticProgressPosition(null);
    if (openedPath == null && openingPosterPath == null) {
      // 缩略图只承担 Route 首次冷启动占位；队列切换继续复用唯一视频纹理，
      // 避免图片解码与不同分辨率的原生纹理重建在同一帧交叉。
      prepareOpeningPoster(currentItem);
    }
    if (currentItem.isMissing) {
      openedPath = null;
      openRequests.markImmediateFailure(currentOpenTarget,
          code: 'missing_media');
      if (mounted) {
        rebuild(() {});
      }
      return;
    }
    final compatibility = PlayerHardwareCompatibility.assess(
      details: currentItem.mediaDetails,
      settings: pageWidget.playbackSettings,
    );
    if (openedPath != null &&
        openedPath != currentItem.path &&
        compatibility.status == HardwareDecodeCompatibilityStatus.unsupported) {
      // 队列切换先保留当前播放会话；超规格媒体不交给 open worker。
      unawaited(confirmQueueHardwareDecodeRisk(
        currentItem,
        compatibility,
      ));
      return;
    }
    if (openRequests.request(currentOpenTarget)) {
      unawaited(drainOpenRequests());
    }
  }

  /**
   * 读取当前进程已验证缩略图；缓存尚未落入同步索引时只补一次轻量异步查询。
   *
   * 媒体库在压入播放器 Route 前已经预热当前队列，因此这里不会启动 FFmpeg；
   * 路径校验避免快速点选队列时过期缩略图闪到新媒体上。
   */
  void prepareOpeningPoster(VideoItem item) {
    final path = item.path;
    if (openingPosterPath == path) {
      return;
    }
    openingPosterPath = path;
    openingPosterFile = pageWidget.thumbnailService.cachedThumbnailFor(item);
    if (openingPosterFile != null) {
      debugPrint(
        'PLAYER_OPEN_POSTER status=ready file=${p.basename(path)} source=memory',
      );
      return;
    }
    unawaited(pageWidget.thumbnailService.thumbnailFor(item).then((file) {
      if (!mounted || openingPosterPath != path || file == null) {
        if (mounted && openingPosterPath == path) {
          debugPrint(
            'PLAYER_OPEN_POSTER status=missing file=${p.basename(path)}',
          );
        }
        return;
      }
      rebuild(() => openingPosterFile = file);
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
  Future<void> confirmQueueHardwareDecodeRisk(
    VideoItem item,
    HardwareDecodeCompatibilityAssessment compatibility,
  ) async {
    if (compatibilityPromptPath != null) {
      return;
    }
    final requestedPath = item.path;
    compatibilityPromptPath = requestedPath;
    await withPlayerOverlaySurfaceOccluded(
      () => showPlayerHardwareDecodeWarningDialog(
        context,
        compatibility,
      ),
    );
    compatibilityPromptPath = null;
    if (!mounted) {
      return;
    }
    if (currentItem.path != requestedPath) {
      requestOpenCurrent();
      return;
    }
    final openedPathSnapshot = openedPath;
    final openedIndex = openedPathSnapshot == null
        ? -1
        : queue.indexWhere((video) => video.path == openedPathSnapshot);
    if (openedIndex >= 0) {
      rebuild(() => playback.jumpTo(openedIndex));
      ensureQueueIndexVisible(openedIndex, center: true);
    }
  }

  Future<void> drainOpenRequests() async {
    if (mounted) {
      rebuild(openRequests.beginDrain);
    }
    var shouldContinue = false;
    try {
      while (mounted) {
        final request = openRequests.takePending();
        if (request == null) {
          break;
        }
        final previousGpuTask = gpuCapabilityDetectionTask;
        if (previousGpuTask != null) {
          // libmpv 属性属于共享实例；旧媒体任务结束后再开始新 open，保证最后写入者是新媒体。
          await previousGpuTask;
          if (!mounted) return;
          if (openRequests.hasSuperseded(request)) continue;
        }
        final path = request.path;
        try {
          // 每个新媒体独立判断实际解码器，不能沿用上一条视频的 no/恢复状态。
          lastHwdecCurrent = null;
          consecutiveSoftwareDecodeSamples = 0;
          softwareDecodeConfirmed = false;
          adaptiveQualityCoordinator.reset();
          adaptiveQualityLevel = PlayerAdaptiveQualityLevel.off;
          adaptiveQualitySessionBlocked = false;
          adaptiveQualityApplyResult =
              const PlayerFeatureApplyResult.notRequested(
            'compression-filter-snapshot',
          );
          qualityMarginSampleTick = 0;
          gpuCapabilitySnapshot = null;
          hdrMappingExperimentActive = false;
          hdrMappingApplyResult = const PlayerFeatureApplyResult.notRequested(
            'hdr-to-sdr-tone-mapping',
          );
          darkSceneEnhancementApplyResult =
              const PlayerFeatureApplyResult.notRequested(
            'dark-scene-enhancement',
          );
          darkSceneEnhancementActive = false;
          videoSuperResolutionActive = false;
          videoSuperResolutionApplyResult =
              const PlayerFeatureApplyResult.notRequested(
            'gpu-high-quality-scaling',
          );
          darkSceneSafetyCoordinator.reset();
          darkSceneEnhancementRollbackReason = null;
          darkSceneEnhancementRollbackAt = null;
          nvidiaVideoEnhancementExperimentEnabled = false;
          nvidiaVideoHdrExperimentEnabled = false;
          nvidiaCpuEnhancementsSuspended = false;
          nvidiaSuspendedDarkSceneEnhancement = false;
          nvidiaVideoSafetyCoordinator.reset();
          nvidiaVideoEnhancementRollbackReason = null;
          nvidiaVideoEnhancementRollbackAt = null;
          nvidiaVideoAutomaticReason = '等待当前媒体能力';
          smoothMotionActive = false;
          smoothMotionApplyReason = '等待当前媒体配置';
          smoothMotionSafetyCoordinator.reset();
          smoothMotionRollbackReason = null;
          smoothMotionRollbackAt = null;
          hdrMappingSafetyCoordinator.reset();
          hdrMappingRollbackReason = null;
          hdrMappingRollbackAt = null;
          await applyPlaybackEngineProfile();
          if (!mounted) {
            return;
          }
          if (openRequests.hasSuperseded(request)) {
            continue;
          }
          await playerService.openPath(path);
          if (!mounted) {
            return;
          }
          if (openRequests.hasSuperseded(request)) {
            // open 本身无法中断，但返回后立即消费最新路径，不等待旧媒体首帧。
            continue;
          }
          // 新媒体打开后清除上一条滤镜；不再在 open 前额外执行一次完整滤镜事务。
          adaptiveQualityApplyResult =
              await PlayerAdaptiveQualityEnhancer.apply(
            backend: playerService,
            level: PlayerAdaptiveQualityLevel.off,
            darkSceneEnhancementEnabled: false,
          );
          if (openRequests.hasSuperseded(request)) {
            continue;
          }
          await applyMediaPresentationProfile();
          if (openRequests.hasSuperseded(request)) {
            continue;
          }
          final playable = await waitForPlayableMedia(request);
          if (!playable) {
            // 快速切换已有更新请求时只放弃旧验证，不展示过时错误。
            if (!openRequests.hasSuperseded(request)) {
              openedPath = null;
              openRequests.markFailure(
                request,
                code: 'unplayable_media',
              );
              await playerService.stop();
            }
            continue;
          }
          if (openRequests.hasSuperseded(request)) {
            continue;
          }
          if (!openRequests.markSuccess(request)) {
            continue;
          }
          openedPath = path;
          final requiresGpuCapabilityDetection =
              effectivePlaybackSettings.darkSceneEnhancementEnabled ||
                  effectivePlaybackSettings
                      .hdrDynamicToneMappingExperimentEnabled ||
                  playerService.supportsNativeNvidiaVideoEnhancement;
          if (requiresGpuCapabilityDetection) {
            final task = detectCurrentGpuCapabilities(request);
            gpuCapabilityDetectionTask = task;
            unawaited(task.whenComplete(() {
              if (identical(gpuCapabilityDetectionTask, task)) {
                gpuCapabilityDetectionTask = null;
              }
            }));
          } else {
            nvidiaVideoAutomaticReason =
                '正式 MediaKit Texture 不运行 NVIDIA 原生增强探测';
          }
          unawaited(PlayerMemoryDiagnostics.logStage(
            'media_opened',
            backend: playerService,
          ));
          scheduleQueuePrefetch();
          final openedItem = playback.sourceItemForVideoId(request.videoId);
          if (openedItem != null) {
            lastPersistedPosition = Duration.zero;
            lastProgressWriteAt = null;
            choosingPlaybackStart = true;
            try {
              await choosePlaybackStart(openedItem);
            } finally {
              choosingPlaybackStart = false;
            }
          }
        } catch (error) {
          if (!mounted) {
            return;
          }
          // 只记录错误类型，避免异常正文中的本地路径进入 UI 或可复制诊断摘要。
          openRequests.markFailure(
            request,
            code: error.runtimeType.toString(),
          );
        }
      }
    } finally {
      shouldContinue = mounted && openRequests.hasPending;
      openRequests.finishDrain(keepOpening: shouldContinue);
      if (mounted && !shouldContinue) {
        rebuild(() {});
      }
    }
    if (shouldContinue) {
      unawaited(drainOpenRequests());
    }
  }

  /**
   * 等待本地媒体产生有效时长或 codec 证据。
   *
   * 0 字节/损坏 MP4 的 `Player.open` 可能成功返回却永久停在 00:00；限定等待窗口后将其
   * 归入稳定错误面板。检测期间如出现更新 open 请求则立即放弃旧验证，保护快速切换流畅度。
   */
  Future<bool> waitForPlayableMedia(PlayerOpenRequest request) async {
    // 保持约 1.5 秒损坏媒体判定窗口，但把新请求响应粒度从 250ms 缩短到 80ms。
    const attempts = 19;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (openRequests.hasSuperseded(request)) {
        return false;
      }
      final videoCodec = await getMpvProperty('video-codec');
      if (openRequests.hasSuperseded(request)) {
        return false;
      }
      final audioCodec = await getMpvProperty('audio-codec');
      if (playerMediaStateIsPlayable(
        duration: playerService.state.duration,
        videoCodec: videoCodec,
        audioCodec: audioCodec,
      )) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    return false;
  }

  /** 按设置页默认行为处理有效进度；仅“每次询问”继续弹出选择框。 */
  Future<void> choosePlaybackStart(VideoItem item) async {
    final duration = playerService.state.duration;
    final saved = playerResumePosition(
      saved: item.playbackPosition,
      duration: duration,
      completed: item.playbackCompleted,
    );
    if (saved == null) {
      return;
    }
    final behavior = pageWidget.playbackSettings.resumeBehavior;
    PlayerResumeChoice choice;
    if (behavior == PlaybackResumeBehavior.ask) {
      await playerService.pause();
      if (!mounted || openedPath != item.path) {
        return;
      }
      choice = await withPlayerOverlaySurfaceOccluded(
        () => showPlayerResumeDialog(
          context,
          item: item,
          position: saved,
          duration: duration,
        ),
      );
    } else {
      choice = behavior == PlaybackResumeBehavior.continueWatching
          ? PlayerResumeChoice.continueWatching
          : PlayerResumeChoice.restart;
    }
    if (!mounted || openedPath != item.path) {
      return;
    }
    final start =
        choice == PlayerResumeChoice.continueWatching ? saved : Duration.zero;
    // 继续观看需要恢复到已保存的精确时间，不能复用进度条的关键帧优先随机跳转。
    await seekExactlyWithDiagnostics(start);
    await playerService.play();
    lastPersistedPosition = start;
    lastProgressWriteAt = DateTime.now();
    if (choice == PlayerResumeChoice.restart) {
      unawaited(pageWidget.onPlaybackProgressUpdated(
        item,
        Duration.zero,
        duration,
        false,
      ));
    }
  }

  /** 从失败面板重新关联 missing 文件，成功后原地打开同一稳定 videoId。 */
  Future<void> relinkCurrentMissing() async {
    final item = currentItem;
    final relinked = await withPlayerShortcutsSuspended(
      () => pageWidget.onRelinkMissing(item),
    );
    if (!mounted || !relinked) {
      return;
    }
    rebuild(() => openRequests.clearFailure());
    requestOpenCurrent();
  }

  /** 重新打开最近失败的视频，并继续复用 latest-request worker。 */
  void retryFailedOpen() {
    if (openRequests.retryFailure()) {
      rebuild(() => queueEndReached = false);
      unawaited(drainOpenRequests());
    }
  }

  /** 跳过失败项；队尾不循环，只显示当前筛选队列结束提示。 */
  void skipFailedOpen() {
    final nextIndex = playback.nextIndex;
    rebuild(() {
      queueEndReached = nextIndex == null;
      openRequests.clearFailure();
    });
    if (nextIndex == null) {
      showQueueEndMessage();
      return;
    }
    jumpTo(nextIndex, ignoreFollowUpSelection: true);
  }
}
