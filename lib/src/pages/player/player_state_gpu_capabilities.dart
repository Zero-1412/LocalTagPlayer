import 'package:flutter/foundation.dart';

import '../../features/player/application/player_open_request_controller.dart';
import '../../models/player_feature_apply_result.dart';
import '../../services/player/player_adaptive_quality.dart';
import '../../services/player/player_hdr_mapping_experiment.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 协调当前媒体的 GPU 能力探测与可选增强应用。
 *
 * 结果始终绑定 [PlayerOpenRequest]；共享 libmpv 实例的跨媒体串行等待由打开协调器
 * 负责，旧媒体任务不得在新媒体打开后成为最后写入者。
 */
extension PlayerStateGpuCapabilities on PlayerPageState {
  /**
   * 媒体确认可播放后检测当前 GPU 渲染会话；过期 open 的结果不得覆盖新媒体。
   */
  Future<void> detectCurrentGpuCapabilities(
    PlayerOpenRequest request,
    PlayerMediaTaskContext task,
  ) async {
    try {
      await applyDetectedGpuCapabilities(request, task);
    } catch (_) {
      if (!mounted ||
          openRequests.hasSuperseded(request) ||
          !isCurrentMediaTask(task)) {
        return;
      }
      // 可选能力探测失败只关闭当前媒体增强，不能形成未处理异步异常或打断播放。
      gpuCapabilitySnapshot = null;
      darkSceneEnhancementActive = false;
      hdrMappingExperimentActive = false;
      darkSceneEnhancementApplyResult =
          const PlayerFeatureApplyResult.failed('dark-scene-enhancement');
      hdrMappingApplyResult =
          const PlayerFeatureApplyResult.failed('hdr-to-sdr-tone-mapping');
    }
  }

  /** 检测并应用仍属于当前 open 请求的 GPU 能力快照。 */
  Future<void> applyDetectedGpuCapabilities(
    PlayerOpenRequest request,
    PlayerMediaTaskContext task,
  ) async {
    if (!isCurrentMediaTask(task) || openRequests.hasSuperseded(request)) {
      return;
    }
    final snapshot = await gpuCapabilityDetector.detect(
      playerService,
      shouldCancel: () => !isCurrentMediaTask(task),
    );
    if (!mounted ||
        openRequests.hasSuperseded(request) ||
        !isCurrentMediaTask(task)) {
      return;
    }
    final experimentAllowed =
        effectivePlaybackSettings.hdrDynamicToneMappingExperimentEnabled &&
            snapshot.selectedAdapter != null &&
            snapshot.computeShaderVerified &&
            snapshot.hdrSourceDetected;
    final darkSceneAllowed =
        effectivePlaybackSettings.darkSceneEnhancementEnabled &&
            snapshot.darkSceneEnhancementEligible;
    final filterResult = await PlayerAdaptiveQualityEnhancer.apply(
      backend: playerService,
      level: adaptiveQualityLevel,
      darkSceneEnhancementEnabled: darkSceneAllowed,
      nvidiaVideoEnhancementEnabled: nvidiaVideoEnhancementExperimentEnabled,
      nvidiaVideoHdrEnabled: nvidiaVideoHdrExperimentEnabled,
    );
    if (!mounted ||
        openRequests.hasSuperseded(request) ||
        !isCurrentMediaTask(task)) {
      return;
    }
    final hdrResult = await PlayerHdrMappingExperiment.apply(
      backend: playerService,
      enabled: experimentAllowed,
    );
    if (!mounted ||
        openRequests.hasSuperseded(request) ||
        !isCurrentMediaTask(task)) {
      // 过期任务不得再向共享后端写回关闭状态；最新 open 会恢复自己的完整快照。
      return;
    }
    gpuCapabilitySnapshot = snapshot;
    adaptiveQualityApplyResult = filterResult;
    darkSceneEnhancementApplyResult =
        effectivePlaybackSettings.darkSceneEnhancementEnabled
            ? darkSceneAllowed
                ? filterResult
                : const PlayerFeatureApplyResult.blocked(
                    'dark-scene-enhancement',
                  )
            : const PlayerFeatureApplyResult.notRequested(
                'dark-scene-enhancement',
              );
    hdrMappingApplyResult =
        effectivePlaybackSettings.hdrDynamicToneMappingExperimentEnabled
            ? experimentAllowed
                ? hdrResult
                : const PlayerFeatureApplyResult.blocked(
                    'hdr-to-sdr-tone-mapping',
                  )
            : const PlayerFeatureApplyResult.notRequested(
                'hdr-to-sdr-tone-mapping',
              );
    hdrMappingExperimentActive = experimentAllowed && hdrResult.applied;
    darkSceneEnhancementActive = darkSceneAllowed && filterResult.applied;
    if (playerService.supportsNativeNvidiaVideoEnhancement) {
      await applyAutomaticNvidiaVideoEnhancement(task);
    }
    if (!mounted ||
        openRequests.hasSuperseded(request) ||
        !isCurrentMediaTask(task)) {
      return;
    }
    if (darkSceneEnhancementActive) {
      // 从真实滤镜应用后再建立压力基线，媒体打开阶段不能算入暗部增强成本。
      darkSceneSafetyCoordinator.reset();
    }
    if (hdrMappingExperimentActive) {
      // 从实验真正启用后再建立累计掉帧基线，避免把媒体打开阶段算作 HDR 成本。
      hdrMappingSafetyCoordinator.reset();
    }
    debugPrint(
      'PLAYER_GPU_CAPABILITY renderer=${snapshot.rendererDetected} '
      'api=${snapshot.gpuApi} context=${snapshot.gpuContext} '
      'vulkan=${snapshot.vulkanDetected} '
      'compute=${snapshot.computeShaderVerified}',
    );
  }
}
