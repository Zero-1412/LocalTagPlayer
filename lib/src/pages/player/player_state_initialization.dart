import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/tag_rules.dart';
import '../../features/player/application/player_backend_event_bridge.dart';
import '../../features/player/application/player_fullscreen_lifecycle_controller.dart';
import '../../features/player/application/player_interaction_state_controller.dart';
import '../../features/player/application/player_seek_coordinator.dart';
import '../../features/player/application/player_session_controller.dart';
import '../../models/video_item.dart';
import '../../services/media/media_details_service.dart';
import '../../services/player/player_hardware_acceleration.dart';
import '../../services/player/player_memory_diagnostics.dart';
import '../../services/player/player_resource_lifecycle_coordinator.dart';
import 'player_input_qa_evidence.dart';
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
    seekPreviewThrottle = PlayerSeekGopAdaptiveThrottle();
    seekTrace = PlayerSeekTraceLogger(output: debugPrint);
    exactSeekCoordinator = PlayerSeekCoordinator(
      // 进度条只在手势结束后提交一次；此处必须走普通 seek，才能从前一关键帧解码至
      // 用户选择的准确落点。latest-only 仍保护连续点击不累积 native 命令。
      submit: playerService.seek,
      readPosition: () => playerService.state.position,
      readDuration: () => playerService.state.duration,
      isExiting: () => isExiting,
      onLatency: (milliseconds) {
        lastSeekLatencyMs = milliseconds;
        lastSeekAt = DateTime.now();
      },
      onFailure: (error) {
        if (mounted) setOptimisticProgressPosition(null);
        debugPrint('PLAYER_EXACT_SEEK_FAILED type=${error.runtimeType}');
      },
      // 精确拖动不能沿用 keyframe 预览的 750ms 容差；位置确认只允许小于一帧级别的
      // 100ms 偏差，音频仍要等到新视频帧后恢复。
      confirmationTolerance: const Duration(milliseconds: 100),
      trace: seekTrace,
      readTraceId: () => seekAudioGate.activeTraceId,
      readTraceRuntimeSnapshot: PlayerInputQaEvidence.seekSegmentTraceEnabled
          ? readSeekTraceRuntimeSnapshot
          : null,
      readPresentedFrame: readPresentedVideoFrame,
      readFrameEvidence: () => lastPresentedVideoFrameEvidence,
    );
    seekCoordinator = PlayerSeekCoordinator(
      // 进度条和连续按键只提交关键帧预览；继续观看等精确入口单独提交普通 seek。
      submit: playerService.seekInteractive,
      readPosition: () => playerService.state.position,
      readDuration: () => playerService.state.duration,
      isExiting: () => isExiting,
      onLatency: (milliseconds) {
        lastSeekLatencyMs = milliseconds;
        lastSeekAt = DateTime.now();
      },
      onFailure: (error) {
        if (mounted) {
          setOptimisticProgressPosition(null);
        }
        debugPrint(
          'PLAYER_SEEK_FAILED type=${error.runtimeType}',
        );
      },
      // 关键帧可能与逻辑目标相距超过容差；此处只等命令返回，不等待精确位置确认。
      confirmationTimeout: Duration.zero,
      adaptiveThrottle: seekPreviewThrottle,
      trace: seekTrace,
      // 键盘临时静音会话已有 trace id；进度条没有音频门禁时由 coordinator 新建 id。
      readTraceId: () => seekAudioGate.activeTraceId,
      readTraceRuntimeSnapshot: PlayerInputQaEvidence.seekSegmentTraceEnabled
          ? readSeekTraceRuntimeSnapshot
          : null,
      readPresentedFrame: readPresentedVideoFrame,
      readFrameEvidence: () => lastPresentedVideoFrameEvidence,
    );
    seekAudioGate = PlayerSeekAudioGate(
      // 临时静音只写后端，不触碰用户音量、播放状态或视频时钟。
      readDesiredVolume: () => volume,
      setVolume: playerService.setVolume,
      readPresentedFrame: readPresentedVideoFrame,
      waitForNewFrame: waitForPresentedVideoFrame,
      framePresentationTimeout: () =>
          seekPreviewThrottle.finalPresentationTimeout,
      isExiting: () => isExiting,
      readFrameEvidence: () => lastPresentedVideoFrameEvidence,
      trace: seekTrace,
    );
    keyboardSeek = PlayerKeyboardSeekController(
      coordinator: seekCoordinator,
      readPosition: () => playerService.state.position,
      readDuration: () => playerService.state.duration,
      isExiting: () => isExiting,
      onLatency: (milliseconds) {
        lastSeekLatencyMs = milliseconds;
        lastSeekAt = DateTime.now();
      },
      previewAudioGate: seekAudioGate,
      trace: seekTrace,
      // 首个 KeyDown 不再抢先随机 seek：短按在松键时只提交一次，长按在首个
      // KeyRepeat 转入连续高速播放，避免解码器刚被随机跳转又被下一目标打断。
      deferInitialPreviewUntilRelease: true,
      readPlaybackRate: () => playbackRate,
      // 长按快进是瞬时交互，不更新偏好或设置面板中的用户常规播放速度。
      setTemporaryPlaybackRate: playerService.setRate,
      // MediaKit/libmpv 在同一原生锁内切换高速扫描呈现档位；普通后端仍由 controller
      // 安全回退到上面的临时倍速，页面不接触 mpv 属性或 NativePlayer。
      beginFastForwardScan: playerService.beginFastForwardScan,
      endFastForwardScan: () => playerService.endFastForwardScan(
        fallbackRate: playbackRate,
      ),
      readScanTraceSnapshot: PlayerInputQaEvidence.seekSegmentTraceEnabled
          ? readSeekTraceRuntimeSnapshot
          : null,
    );
    if (!playerService.supportsNativeNvidiaVideoEnhancement) {
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
      onCompletedWithGeneration: (completed, generation) =>
          handlePlaybackCompleted(
        completed,
        eventGeneration: generation,
      ),
      onErrorWithGeneration: (code, generation) => handlePlayerError(
        code,
        eventGeneration: generation,
      ),
      onPositionWithGeneration: (position, generation) => handlePosition(
        position,
        eventGeneration: generation,
      ),
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
      onReleaseFailed: (stage, error) {
        handlePlayerResourceReleaseFailure(stage, error);
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

  /**
   * Debug-only 连续扫描分段快照；只读取固定运行态字段，不触碰播放命令或用户数据。
   *
   * 每项属性都有更短的本地超时，避免诊断采样拖住 KeyRepeat；不可用值保留为文本，
   * 由 trace logger 做无空格清洗后写入匿名日志。
   */
  Future<Map<String, String>> readSeekTraceRuntimeSnapshot() async {
    const properties = <String>[
      'demuxer-cache-duration',
      'cache-buffering-state',
      'decoder-frame-drop-count',
      'vo-drop-frame-count',
      'frame-drop-count',
      'mistimed-frame-count',
      'vo-delayed-frame-count',
      'hwdec-current',
      'current-vo',
      'video-sync',
      'interpolation',
      'framedrop',
    ];
    final values = await Future.wait<String>(
      properties.map((property) async {
        try {
          return await playerService
              .getProperty(property)
              .timeout(const Duration(milliseconds: 220));
        } catch (_) {
          return 'unavailable';
        }
      }),
    );
    final mpv = <String, String>{
      for (var index = 0; index < properties.length; index++)
        properties[index]: values[index],
    };
    final surface = playerService.videoSurfaceDiagnostics;
    String read(String property) => mpv[property] ?? 'unavailable';
    String readNumber(double? value) =>
        value == null ? 'unavailable' : value.toStringAsFixed(0);
    return <String, String>{
      'cache_duration_s': read('demuxer-cache-duration'),
      'cache_buffering_state': read('cache-buffering-state'),
      'decoder_drop_frames': read('decoder-frame-drop-count'),
      'vo_drop_frames': read('vo-drop-frame-count'),
      'total_drop_frames': read('frame-drop-count'),
      'mistimed_frames': read('mistimed-frame-count'),
      'vo_delayed_frames': read('vo-delayed-frame-count'),
      'hwdec_current': read('hwdec-current'),
      'current_vo': read('current-vo'),
      'video_sync': read('video-sync'),
      'interpolation': read('interpolation'),
      'framedrop': read('framedrop'),
      'texture_supported': surface.supported.toString(),
      'texture_generation': surface.supported
          ? surface.textureGenerationCount.toString()
          : 'unavailable',
      'texture_width_px':
          readNumber(surface.supported ? surface.textureWidthPx : null),
      'texture_height_px':
          readNumber(surface.supported ? surface.textureHeightPx : null),
      'texture_resize_state':
          surface.supported ? surface.textureResizeState : 'unavailable',
      'frame_presentation_evidence':
          playerService.framePresentationEvidenceKind,
    };
  }
}
