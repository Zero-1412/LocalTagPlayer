import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/playback_settings.dart';
import '../../services/player/player_adaptive_quality.dart';
import '../../services/player/player_nvidia_video_auto_policy.dart';
import '../../services/player/player_nvidia_video_enhancement_experiment.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 协调 NVIDIA 视频增强实验及其安全回退。
 *
 * 这里只承载 [PlayerPageState] 的实现细节；播放会话、过滤队列与资源生命周期所有权
 * 仍保留在页面状态对象中。
 */
extension PlayerStateNvidia on PlayerPageState {
  Future<void> probeNvidiaVideoEnhancementCapability() async {
    final capability = await PlayerNvidiaVideoEnhancementExperiment.probe(
      playerService,
      conflictingCpuFilters: !nvidiaCpuEnhancementsSuspended &&
          (compressionEnhancementMode != PlayerCompressionEnhancementMode.off ||
              darkSceneEnhancementActive),
    );
    if (!mounted) return;
    rebuild(() {
      nvidiaVideoEnhancementCapability = capability;
      if (!capability.canEnable) {
        nvidiaVideoEnhancementExperimentEnabled = false;
      }
      if (!capability.canEnableHdr) {
        nvidiaVideoHdrExperimentEnabled = false;
      }
    });
  }

  /** 真实画质集成测试使用的 VSR 会话控制入口。 */
  Future<void> setNvidiaVideoEnhancementExperimentEnabled(
    bool enabled,
  ) =>
      setNvidiaVideoFilterModes(
        videoSuperResolutionEnabled: enabled,
        videoHdrEnabled: nvidiaVideoHdrExperimentEnabled,
      );

  /** 真实画质集成测试使用的 HDR 会话控制入口。 */
  Future<void> setNvidiaVideoHdrExperimentEnabled(bool enabled) =>
      setNvidiaVideoFilterModes(
        videoSuperResolutionEnabled: nvidiaVideoEnhancementExperimentEnabled,
        videoHdrEnabled: enabled,
      );

  /** NVIDIA 请求前暂时释放 CPU `lavfi`，但保留用户的全局增强偏好。 */
  void suspendCpuEnhancementsForNvidia() {
    if (nvidiaCpuEnhancementsSuspended) return;
    nvidiaSuspendedDarkSceneEnhancement = darkSceneEnhancementActive;
    nvidiaCpuEnhancementsSuspended = true;
    darkSceneEnhancementActive = false;
    adaptiveQualityCoordinator.reset();
    adaptiveQualityLevel = PlayerAdaptiveQualityLevel.off;
    qualityMarginSampleTick = 1;
    if (mounted) rebuild(() {});
  }

  /**
   * NVIDIA 关闭、拒绝或回滚后恢复当前媒体可安全运行的 CPU 增强。
   *
   * 压缩增强从关闭档重新采样，不沿用 NVIDIA 运行期间的性能判断；暗场增强只有
   * 在开启前实际活动、持久偏好仍开启且当前媒体仍满足门槛时才恢复。
   */
  Future<void> restoreCpuEnhancementsAfterNvidia() async {
    if (!nvidiaCpuEnhancementsSuspended) return;
    final restoreDarkScene = nvidiaSuspendedDarkSceneEnhancement &&
        effectivePlaybackSettings.darkSceneEnhancementEnabled &&
        (gpuCapabilitySnapshot?.darkSceneEnhancementEligible ?? false);
    nvidiaCpuEnhancementsSuspended = false;
    nvidiaSuspendedDarkSceneEnhancement = false;
    darkSceneEnhancementActive = restoreDarkScene;
    adaptiveQualityCoordinator.reset();
    adaptiveQualityLevel = PlayerAdaptiveQualityLevel.off;
    qualityMarginSampleTick = 1;
    await PlayerAdaptiveQualityEnhancer.apply(
      backend: playerService,
      level: PlayerAdaptiveQualityLevel.off,
      darkSceneEnhancementEnabled: restoreDarkScene,
    );
    if (!mounted) return;
    rebuild(() {});
    await probeNvidiaVideoEnhancementCapability();
  }

  /**
   * 原子更新唯一的 NVIDIA `d3d11vpp` 滤镜图。
   *
   * VSR 与 TrueHDR 必须在一次完整 `vf` 写入中合成；失败时恢复此前已确认模式，
   * 避免开启第二项时意外关闭第一项。TrueHDR 联合模式不强制 NV12。
   */
  Future<void> setNvidiaVideoFilterModes({
    required bool videoSuperResolutionEnabled,
    required bool videoHdrEnabled,
    bool showFailureFeedback = true,
  }) async {
    if (nvidiaVideoEnhancementExperimentEnabled ==
            videoSuperResolutionEnabled &&
        nvidiaVideoHdrExperimentEnabled == videoHdrEnabled) {
      return;
    }
    final targetEnabled = videoSuperResolutionEnabled || videoHdrEnabled;
    final startedCpuSuspension = targetEnabled &&
        !nvidiaCpuEnhancementsSuspended &&
        (compressionEnhancementMode != PlayerCompressionEnhancementMode.off ||
            darkSceneEnhancementActive);
    if (startedCpuSuspension) {
      suspendCpuEnhancementsForNvidia();
    }
    await probeNvidiaVideoEnhancementCapability();
    if (!mounted) return;
    debugPrint(
      'NVIDIA_ENABLE_GATE vsr=$videoSuperResolutionEnabled '
      'hdr=$videoHdrEnabled '
      'status=${nvidiaVideoEnhancementCapability.status.name} '
      'chain=${nvidiaVideoEnhancementCapability.filterChainIntegrated} '
      'hwdec=${nvidiaVideoEnhancementCapability.hwdecCurrent} '
      'vo=${nvidiaVideoEnhancementCapability.currentVo} '
      'sourceHdr=${nvidiaVideoEnhancementCapability.sourceIsHdr} '
      'conflict=${nvidiaVideoEnhancementCapability.conflictingCpuFilters} '
      'canVsr=${nvidiaVideoEnhancementCapability.canEnable} '
      'canHdr=${nvidiaVideoEnhancementCapability.canEnableHdr} '
      'requestVsr=${nvidiaVideoEnhancementCapability.canRequest} '
      'requestHdr=${nvidiaVideoEnhancementCapability.canRequestHdr}',
    );
    final rejectedVsr = videoSuperResolutionEnabled &&
        !nvidiaVideoEnhancementCapability.canEnable;
    final rejectedHdr =
        videoHdrEnabled && !nvidiaVideoEnhancementCapability.canEnableHdr;
    if (rejectedVsr || rejectedHdr) {
      if (startedCpuSuspension) {
        await restoreCpuEnhancementsAfterNvidia();
      }
      if (!mounted) return;
      if (showFailureFeedback) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                rejectedHdr
                    ? nvidiaVideoEnhancementCapability.hdrHelperText
                    : nvidiaVideoEnhancementCapability.helperText,
              ),
            ),
          );
      }
      return;
    }
    final previousVsr = nvidiaVideoEnhancementExperimentEnabled;
    final previousHdr = nvidiaVideoHdrExperimentEnabled;
    var appliedFilter = '';
    final attempts = targetEnabled ? 5 : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      await PlayerAdaptiveQualityEnhancer.apply(
        backend: playerService,
        level: PlayerAdaptiveQualityLevel.off,
        nvidiaVideoEnhancementEnabled: videoSuperResolutionEnabled,
        nvidiaVideoHdrEnabled: videoHdrEnabled,
      );
      if (targetEnabled) {
        // d3d11vpp 会触发硬件滤镜图重建；短暂等待后读回，避免把异步重建中的
        // 临时空值误判为永久拒绝。失败仍保持有界重试和原有安全回滚。
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      appliedFilter = await getMpvProperty('vf');
      final vsrAccepted = !videoSuperResolutionEnabled ||
          appliedFilter.contains('scaling-mode=nvidia');
      final hdrAccepted =
          !videoHdrEnabled || appliedFilter.contains('nvidia-true-hdr');
      if (!targetEnabled ||
          appliedFilter.contains('d3d11vpp') && vsrAccepted && hdrAccepted) {
        break;
      }
    }
    final accepted = !targetEnabled ||
        appliedFilter.contains('d3d11vpp') &&
            (!videoSuperResolutionEnabled ||
                appliedFilter.contains('scaling-mode=nvidia')) &&
            (!videoHdrEnabled || appliedFilter.contains('nvidia-true-hdr'));
    if (!accepted) {
      // 新组合失败时恢复此前已确认组合，不因一次失败破坏仍可工作的 NVIDIA 模式。
      await PlayerAdaptiveQualityEnhancer.apply(
        backend: playerService,
        level: PlayerAdaptiveQualityLevel.off,
        nvidiaVideoEnhancementEnabled: previousVsr,
        nvidiaVideoHdrEnabled: previousHdr,
      );
      if (startedCpuSuspension && !previousVsr && !previousHdr) {
        await restoreCpuEnhancementsAfterNvidia();
      }
      if (!mounted) return;
      if (showFailureFeedback) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('mpv 未接受 NVIDIA 联合滤镜，已恢复先前状态')),
          );
      }
      return;
    }
    if (!mounted) return;
    rebuild(() {
      nvidiaVideoEnhancementExperimentEnabled = videoSuperResolutionEnabled;
      nvidiaVideoHdrExperimentEnabled = videoHdrEnabled;
      nvidiaVideoEnhancementRollbackReason = null;
      nvidiaVideoEnhancementRollbackAt = null;
    });
    if (targetEnabled) {
      nvidiaVideoSafetyCoordinator.reset();
      await refreshNvidiaVideoEnhancementRuntimeState();
    } else {
      await restoreCpuEnhancementsAfterNvidia();
    }
  }

  /**
   * 在当前媒体与活动 GPU 都完成探测后自动协商 NVIDIA VSR/HDR。
   *
   * 自动策略只运行一次且不显示失败 Snackbar；未知能力、非 NVIDIA、无放大空间
   * 或 Windows HDR 未活动时静默保持原画质链。实际启用仍由驱动日志二次确认。
   */
  Future<void> applyAutomaticNvidiaVideoEnhancement(
    String openedPathCandidate,
  ) async {
    final snapshot = gpuCapabilitySnapshot;
    if (snapshot == null || openedPathCandidate != openedPath) return;
    if (!mpvEnhancementsAvailable) {
      rebuild(() {
        nvidiaVideoAutomaticReason = '当前选择 MediaKit，不请求 MPV 专属 NVIDIA 增强';
      });
      return;
    }
    await probeNvidiaVideoEnhancementCapability();
    if (!mounted || openedPathCandidate != openedPath) return;
    final decision = PlayerNvidiaVideoAutoPolicy.evaluate(
      snapshot: snapshot,
      capability: nvidiaVideoEnhancementCapability,
    );
    debugPrint(
      'PLAYER_NVIDIA_AUTO_DECISION '
      'vsr=${decision.videoSuperResolutionEnabled} '
      'hdr=${decision.videoHdrEnabled} '
      'vendor=${snapshot.selectedAdapter?.vendorId} '
      'source=${snapshot.sourceWidth}x${snapshot.sourceHeight} '
      'outputs=${snapshot.selectedAdapter?.outputs.length ?? 0} '
      'canVsr=${nvidiaVideoEnhancementCapability.canRequest} '
      'canHdr=${nvidiaVideoEnhancementCapability.canRequestHdr} '
      'reason=${decision.reason}',
    );
    rebuild(() => nvidiaVideoAutomaticReason = decision.reason);
    if (!decision.enabled) return;
    await setNvidiaVideoFilterModes(
      videoSuperResolutionEnabled: decision.videoSuperResolutionEnabled,
      videoHdrEnabled: decision.videoHdrEnabled,
      showFailureFeedback: false,
    );
    if (!mounted || openedPathCandidate != openedPath) return;
    final requestAccepted = (!decision.videoSuperResolutionEnabled ||
            nvidiaVideoEnhancementExperimentEnabled) &&
        (!decision.videoHdrEnabled || nvidiaVideoHdrExperimentEnabled);
    if (!requestAccepted) {
      rebuild(() {
        nvidiaVideoAutomaticReason = 'NVIDIA 自动请求被后端拒绝，已安全回退';
      });
    }
  }

  /**
   * 等待原生 libmpv 从固定 NVIDIA 日志确认驱动扩展状态。
   *
   * 最多等待三秒，不读取或展示原始日志；驱动没有确认时保留 `requested`，不能把
   * 已接受的滤镜字符串冒充为 RTX Super Resolution 已经工作。
   */
  Future<void> refreshNvidiaVideoEnhancementRuntimeState() async {
    for (var attempt = 0; attempt < 15; attempt++) {
      final vsrState = await getMpvProperty('native-nvidia-vsr-state');
      final hdrState = await getMpvProperty('native-nvidia-hdr-state');
      final vsrDone = !nvidiaVideoEnhancementExperimentEnabled ||
          vsrState == 'active' ||
          vsrState == 'rejected';
      final hdrDone = !nvidiaVideoHdrExperimentEnabled ||
          hdrState == 'active' ||
          hdrState == 'rejected' ||
          hdrState == 'ignored-source-hdr';
      if (vsrDone && hdrDone) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted ||
          !nvidiaVideoEnhancementExperimentEnabled &&
              !nvidiaVideoHdrExperimentEnabled) {
        return;
      }
    }
    await probeNvidiaVideoEnhancementCapability();
  }

  /**
   * 即时切换压缩画质增强档位并复用原有性能回滚。
   *
   * 切档先清除上一档滤镜和去色带状态，再由下一次低频健康样本决定新档位；
   * 清晰增强只在首个稳定样本快速请求基线最高档，不会在压力后反复强制拉高。
   */
  Future<void> setCompressionEnhancementMode(
    PlayerCompressionEnhancementMode mode,
  ) async {
    if (compressionEnhancementMode == mode) return;
    if (mode != PlayerCompressionEnhancementMode.off &&
        (nvidiaVideoEnhancementExperimentEnabled ||
            nvidiaVideoHdrExperimentEnabled)) {
      await setNvidiaVideoFilterModes(
        videoSuperResolutionEnabled: false,
        videoHdrEnabled: false,
      );
      if (!mounted) return;
      nvidiaVideoAutomaticReason = '用户切换压缩画质增强，本媒体已回退 CPU 滤镜';
    }
    rebuild(() => compressionEnhancementMode = mode);
    saveGlobalPlaybackSettings(
      effectivePlaybackSettings.copyWith(
        compressionEnhancementMode: mode,
      ),
    );
    adaptiveQualityCoordinator.reset();
    adaptiveQualityLevel = PlayerAdaptiveQualityLevel.off;
    // 下一次一秒健康采样即进入画质判定，避免用户切档后等待完整两秒周期。
    qualityMarginSampleTick = 1;
    await PlayerAdaptiveQualityEnhancer.apply(
      backend: playerService,
      level: PlayerAdaptiveQualityLevel.off,
      darkSceneEnhancementEnabled: darkSceneEnhancementActive,
      nvidiaVideoEnhancementEnabled: nvidiaVideoEnhancementExperimentEnabled,
      nvidiaVideoHdrEnabled: nvidiaVideoHdrExperimentEnabled,
    );
    await probeNvidiaVideoEnhancementCapability();
  }

  /**
   * 更新页面即时音量并异步送入播放后端。
   *
   * 所有按钮、键盘、滚轮和滑条入口都经过这里，保证图标与滑条即时同步，同时避免
   * 多处各自维护静音恢复值。
   */
}
