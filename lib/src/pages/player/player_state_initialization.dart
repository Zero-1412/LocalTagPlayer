import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/tag_rules.dart';
import '../../features/player/application/player_backend_event_bridge.dart';
import '../../features/player/application/player_fullscreen_lifecycle_controller.dart';
import '../../features/player/application/player_interaction_state_controller.dart';
import '../../features/player/application/player_session_controller.dart';
import '../../models/video_item.dart';
import '../../services/media/media_details_service.dart';
import '../../services/player/player_hardware_acceleration.dart';
import '../../services/player/player_memory_diagnostics.dart';
import '../../services/player/player_resource_lifecycle_coordinator.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 初始化播放器页面依赖、会话控制器和资源协调器。
 *
 * State 生命周期入口仍由主文件持有，这里不改变 controller 或业务命令所有权。
 */
extension PlayerStateInitialization on PlayerPageState {
  void initializePlayerPage() {
    interaction = PlayerInteractionStateController<IconData>(
      initialFeedbackIcon: Icons.keyboard_rounded,
      onChanged: () {
        if (mounted) rebuild(() {});
      },
    );
    windowFullscreen = PlayerFullscreenLifecycleController(
      session: pageWidget.fullscreenSessionController,
      onChanged: () {
        if (mounted) rebuild(() {});
      },
    );
    effectivePlaybackSettings = pageWidget.playbackSettings;
    mirrorVideo = effectivePlaybackSettings.mirrorVideo;
    playbackMode = effectivePlaybackSettings.playbackMode;
    videoAspectMode = effectivePlaybackSettings.videoAspectMode;
    videoScaler = effectivePlaybackSettings.videoScaler;
    smoothMotionMode = effectivePlaybackSettings.smoothMotionMode;
    videoOutputRange = effectivePlaybackSettings.videoOutputRange;
    playbackRate = effectivePlaybackSettings.playbackRate;
    // MediaKit 的同一 NativePlayer 直接消费 libmpv 缩放属性，不再受历史渲染器值限制。
    videoSuperResolutionEnabled =
        effectivePlaybackSettings.videoSuperResolutionEnabled;
    compressionEnhancementMode =
        effectivePlaybackSettings.compressionEnhancementMode;
    seekStepSeconds = effectivePlaybackSettings.seekStepSeconds;
    focusNode = FocusNode(debugLabel: 'player-shortcuts');
    queueScrollController = ScrollController();
    fullscreenQueueScrollController = ScrollController();
    detailsService = MediaDetailsService(
      onUpdated: pageWidget.onMediaDetailsUpdated,
      probeBackend: pageWidget.mediaProbeBackendFactory(),
    );
    requestedHwdec =
        PlayerHardwareAcceleration.resolve(pageWidget.playbackSettings.hwdec);
    playback = PlayerSessionController(
      sourcePlaylist: pageWidget.playlist.isEmpty
          ? <VideoItem>[pageWidget.initialItem]
          : pageWidget.playlist,
      acceptedSourceVideoIds: pageWidget.queueSnapshot?.orderedVideoIds,
      activeParentTag: activeParentTag,
      initialChildTag: pageWidget.activeChildTag,
      initialVideoId: pageWidget.initialItem.videoId,
      matchesChildTag: TagRules.matchesChildTag,
    );
    playerServiceOwner = pageWidget.playerServiceFactory(
      hwdec: requestedHwdec,
      enableHardwareAcceleration:
          pageWidget.playbackSettings.hardwareDecodingEnabled,
      rendererPreference: pageWidget.playbackSettings.rendererPreference,
    );
    if (playerService.supportsNativeNvidiaVideoEnhancement) {
      // NVIDIA 实验只允许显式 child HWND QA 后端探测，正式 Texture 路径不付出该开销。
      unawaited(probeNvidiaVideoEnhancementCapability());
    } else {
      nvidiaVideoAutomaticReason = '正式 MediaKit Texture 不运行 NVIDIA 原生增强探测';
    }
    volume = playerService.state.volume.clamp(0, 100).toDouble();
    if (volume > 0) {
      lastAudibleVolume = volume;
    }
    unawaited(PlayerMemoryDiagnostics.logStage(
      'player_constructed',
      backend: playerService,
    ));
    backendEvents = PlayerBackendEventBridge(
      completedChanges: playerService.completedChanges,
      errorChanges: playerService.errorChanges,
      positionChanges: playerService.positionChanges,
      playingChanges: playerService.playingChanges,
      onCompleted: handlePlaybackCompleted,
      onError: handlePlayerError,
      onPosition: handlePosition,
      onPlayingChanged: (_) {
        if (mounted) rebuild(() {});
      },
    );
    playerResources = PlayerResourceLifecycleCoordinator(
      textureId: playerService.textureId,
      cancelBackendEvents: backendEvents.dispose,
      stop: playerService.stop,
      disposeResource: playerService.dispose,
      awaitReleased: () => playerService.released,
      logStage: (
        stage, {
        required readEngineProperties,
      }) =>
          PlayerMemoryDiagnostics.logStage(
        stage,
        backend: playerService,
        readEngineProperties: readEngineProperties,
      ),
      onTextureReady: () => unawaited(PlayerMemoryDiagnostics.logStage(
        'texture_ready',
        backend: playerService,
      )),
      onStopFailed: (_) {
        debugPrint('PLAYER_MEMORY_STAGE stage=stop_timeout');
      },
      onReleased: handlePlayerResourcesReleased,
    );
    requestOpenCurrent();
    // 诊断弹窗关闭时仍持续独立观察视频帧与音频播放头，避免瞬时 AV offset 掩盖单路停滞。
    playbackHealthTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(sampleIndependentPlaybackProgress()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (isWindowFullscreen) {
          unawaited(windowFullscreen.restoreSession(
            enterFullscreen: () => windowManager.setFullScreen(true),
            reportError: reportFullscreenLifecycleError,
          ));
        }
        focusNode.requestFocus();
        ensureQueueIndexVisible(index, center: true, animated: false);
        // 首次进入默认展示控制条，再按统一三秒规则自动收起。
        showVideoControls();
      }
    });
  }
}
