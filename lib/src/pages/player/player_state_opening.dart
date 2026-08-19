import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/playback_settings.dart';
import '../../models/video_item.dart';
import '../../models/player_feature_apply_result.dart';
import '../../services/player/player_hardware_compatibility.dart';
import '../../services/player/player_adaptive_quality.dart';
import '../../services/player/player_gpu_capability_detector.dart';
import '../../services/player/player_memory_diagnostics.dart';
import 'player_hardware_decode_warning_dialog.dart';
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
      invalidateOpenedMediaEvents();
      openedPath = null;
      openRequests.markImmediateFailure(currentOpenTarget,
          code: 'missing_media');
      // missing 不会进入 backend.openPath；必须显式停掉旧媒体，避免旧声音和画面继续
      // 被误认为当前队列项的打开结果。
      unawaited(safeStopPlayer(reason: 'missing-media'));
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
    invalidateOpenedMediaEvents();
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
          // 旧任务只能在有界窗口内阻挡新 open；任务自身携带稳定身份，超时后即使
          // 某个 native 读调用迟到返回，也不能再向新媒体发布结果。
          try {
            await previousGpuTask.timeout(playerGpuCapabilityDetectionTimeout);
          } catch (error) {
            debugPrint(
              'PLAYER_GPU_PROBE_WAIT_RELEASED type=${error.runtimeType}',
            );
          }
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
          final eventGeneration = beginMediaOpenGeneration(request.revision);
          await playerService.openPath(path);
          if (!mounted) {
            return;
          }
          if (openRequests.hasSuperseded(request)) {
            // open 本身无法中断，但返回后立即消费最新路径，不等待旧媒体首帧。
            continue;
          }
          final openedItem = playback.sourceItemForVideoId(request.videoId);
          final needsPreciseResume = openedItem != null &&
              _needsPreciseResumeGate(
                openedItem,
                pageWidget.playbackSettings.resumeBehavior,
              );

          /**
           * 继续观看/询问场景必须先完成完整可播放性和属性收敛门禁；普通新视频
           * 则先绑定事件并播放，避免首帧被非关键画质往返挡住。
           */
          if (needsPreciseResume) {
            if (!await ensurePlayableMedia(request)) {
              continue;
            }
            await settleMediaOpeningProperties(request);
            if (openRequests.hasSuperseded(request)) {
              continue;
            }
          }
          if (openRequests.hasSuperseded(request)) {
            continue;
          }
          // 旧媒体的四类事件订阅必须先取消；新回调携带本次不可变 generation，
          // 成功发布 stable videoId 后才允许页面消费 position/EOF/error。
          await backendEvents.rebind(generation: eventGeneration);
          if (openRequests.hasSuperseded(request)) {
            continue;
          }
          if (!openRequests.markSuccess(request)) {
            continue;
          }
          openedPath = path;
          openedVideoId = request.videoId;
          openedMediaGeneration = eventGeneration;
          handledCompletedVideoId = null;
          handledCompletedGeneration = null;
          final requiresGpuCapabilityDetection =
              effectivePlaybackSettings.darkSceneEnhancementEnabled ||
                  effectivePlaybackSettings
                      .hdrDynamicToneMappingExperimentEnabled ||
                  playerService.supportsNativeNvidiaVideoEnhancement;
          if (requiresGpuCapabilityDetection) {
            final taskContext = currentMediaTaskContext;
            if (taskContext == null) {
              continue;
            }
            final task = detectCurrentGpuCapabilities(request, taskContext);
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
          if (openedItem != null) {
            lastPersistedPosition = Duration.zero;
            lastProgressWriteAt = null;
            if (needsPreciseResume) {
              choosingPlaybackStart = true;
              try {
                await choosePlaybackStart(openedItem);
              } finally {
                choosingPlaybackStart = false;
              }
            } else {
              // MediaKit open 保持 play:false；无有效恢复点时在首帧路径上立即启动。
              await playerService.play();
              if (openRequests.hasSuperseded(request)) {
                continue;
              }
              // 播放命令已完成后即可撤掉打开占位；损坏媒体检测和属性收敛继续在
              // 当前 worker 尾部执行，避免与下一次 open 并发写入同一个后端。
              openRequests.markPlaybackReady();
              if (!await ensurePlayableMedia(request)) {
                continue;
              }
              try {
                await settleMediaOpeningProperties(request);
              } catch (error) {
                // 普通新视频已经开始播放；可选画质属性失败只能降级诊断，不能
                // 反向停止已交付的首帧。
                debugPrint(
                  'PLAYER_OPEN_PRESENTATION_SETTLE_FAILED '
                  'type=${error.runtimeType}',
                );
              }
            }
          }
        } catch (error) {
          if (!mounted) {
            return;
          }
          invalidateOpenedMediaEvents();
          openedPath = null;
          // open、属性应用或可播放性准备任一步骤失败都必须结束旧媒体；否则旧视频
          // 会在失败面板后继续播放，且下一次 position 事件仍可能污染进度记录。
          await safeStopPlayer(reason: 'open-failed');
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
   * 判断本次打开是否必须先走继续观看的精确恢复门禁。
   *
   * 未完成且已有至少三秒记录的位置才属于恢复候选；“重播”明确表示从头开始，
   * 不应因为旧进度记录把普通首播重新挡在画质属性收敛之后。
   */
  bool _needsPreciseResumeGate(
    VideoItem item,
    PlaybackResumeBehavior behavior,
  ) =>
      behavior != PlaybackResumeBehavior.restart &&
      !item.playbackCompleted &&
      item.playbackPosition >= const Duration(seconds: 3);
}
