import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/playback_settings.dart';
import '../../models/media_details.dart';
import '../../services/player/player_adaptive_quality.dart';
import '../../services/player/player_hdr_mapping_experiment.dart';
import '../../services/player/player_memory_diagnostics.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 处理安全退出、播放健康采样、交互反馈与截图。
 *
 * 这里只承载 [PlayerPageState] 的实现细节；播放会话、过滤队列与资源生命周期所有权
 * 仍保留在页面状态对象中。
 */
extension PlayerStateHealth on PlayerPageState {
  Future<void> exitPlayer() async {
    if (isExiting) {
      return;
    }
    isExiting = true;
    exitRequestedAt = DateTime.now();
    unawaited(PlayerMemoryDiagnostics.logStage(
      'exit_requested',
      backend: playerService,
    ));
    seekCoordinator.cancelPending();
    openRequests.cancel();
    detailsService.dispose();
    persistOpenedProgress();
    var pauseAcknowledged = false;
    try {
      // pause 的确认路径比 stop 短，先确保音频静音，不能让原生 stop 阻塞路由退出。
      await playerService.pause().timeout(const Duration(milliseconds: 800));
      pauseAcknowledged = true;
      pauseAcknowledgedAt = DateTime.now();
      unawaited(PlayerMemoryDiagnostics.logStage(
        'pause_acknowledged',
        backend: playerService,
      ));
    } catch (_) {
      // pause 失败时提前 stop 是音频安全兜底；正常返回不会在反向转场前清空纹理。
    }
    if (playerExitStopShouldStartBeforePop(
      pauseAcknowledged: pauseAcknowledged,
    )) {
      unawaited(playerResources.stopForExit());
    }
    // 返回媒体库前等待最后一次全局设置写入，避免用户改完立即退出时丢失配置。
    await playbackSettingsSaveTail;
    await windowFullscreen.prepareForExit(
      queryFullscreen: windowManager.isFullScreen,
      setWindowed: () => windowManager.setFullScreen(false),
      maximize: windowManager.maximize,
      reportError: reportFullscreenLifecycleError,
    );
    fullscreenQueueVisible = false;
    pointerInWindowTopBarRegion = false;
    if (mounted) {
      routePopRequestedAt = DateTime.now();
      Navigator.of(context).maybePop();
    }
  }

  /**
   * 每秒分别读取 mpv 的当前视频帧号与音频播放头。
   *
   * `estimated-frame-number` 代表视频链路是否继续交付帧，`audio-pts` 包含音频驱动延迟；
   * 两者不共用 `time-pos`，因此可以识别“画面停住但声音继续”及其反向故障。
   */
  Future<void> sampleIndependentPlaybackProgress() async {
    if (playbackHealthSampling || isExiting) {
      return;
    }
    playbackHealthSampling = true;
    try {
      final previousFrame = lastVideoFrameNumber;
      final frame = parseMpvInt(await getMpvProperty('estimated-frame-number'));
      final audioPts = parseMpvNumber(await getMpvProperty('audio-pts'));
      final hwdecCurrent = await getMpvProperty('hwdec-current');
      final now = DateTime.now();
      lastHealthSampleAt = now;
      if (frame != null) {
        if (lastVideoFrameNumber == null || frame != lastVideoFrameNumber) {
          lastVideoAdvanceAt = now;
          videoProgressState = '视频帧持续推进';
        }
        lastVideoFrameNumber = frame;
      }
      if (audioPts != null) {
        if (lastAudioPts == null || (audioPts - lastAudioPts!).abs() >= 0.01) {
          lastAudioAdvanceAt = now;
          audioProgressState = '音频播放头持续推进';
        }
        lastAudioPts = audioPts;
      }

      final canJudge = playerService.state.playing &&
          !playerService.state.buffering &&
          (lastSeekAt == null || now.difference(lastSeekAt!).inSeconds >= 2);
      // mpv 在已开始软件解码时可能把 hwdec-current 返回为空；平台接口不可用才保持未知。
      final effectiveHwdec =
          hwdecCurrent == 'empty' && canJudge ? 'no' : hwdecCurrent;
      if (effectiveHwdec != 'empty' && effectiveHwdec != 'unavailable') {
        lastHwdecCurrent = effectiveHwdec;
        if (canJudge &&
            pageWidget.playbackSettings.hardwareDecodingEnabled &&
            effectiveHwdec == 'no') {
          consecutiveSoftwareDecodeSamples++;
        } else {
          consecutiveSoftwareDecodeSamples = 0;
        }
      }
      if (consecutiveSoftwareDecodeSamples >= 3 && !softwareDecodeConfirmed) {
        softwareDecodeConfirmed = true;
        // 运行时热切换 hwdec 会让部分超规格视频直接打开失败；只记录确认结果并保留软件回退可播放性。
        debugPrint(
          'PLAYER_HEALTH software_decode_confirmed requested=$requestedHwdec actual=$hwdecCurrent',
        );
      }
      if (canJudge &&
          frame != null &&
          lastVideoAdvanceAt != null &&
          now.difference(lastVideoAdvanceAt!) >= const Duration(seconds: 3)) {
        if (videoProgressState != '视频帧停滞') {
          videoStallEvents++;
          debugPrint(
              'PLAYER_HEALTH video_stall frame=$frame audio_pts=$audioPts');
        }
        videoProgressState = '视频帧停滞';
      }
      if (canJudge &&
          audioPts != null &&
          lastAudioAdvanceAt != null &&
          now.difference(lastAudioAdvanceAt!) >= const Duration(seconds: 3)) {
        if (audioProgressState != '音频播放头停滞') {
          audioStallEvents++;
          debugPrint(
              'PLAYER_HEALTH audio_stall frame=$frame audio_pts=$audioPts');
        }
        audioProgressState = '音频播放头停滞';
      }
      if (compressionEnhancementMode != PlayerCompressionEnhancementMode.off ||
          hdrMappingExperimentActive ||
          darkSceneEnhancementActive ||
          smoothMotionActive ||
          nvidiaVideoEnhancementExperimentEnabled ||
          nvidiaVideoHdrExperimentEnabled) {
        qualityMarginSampleTick++;
        if (qualityMarginSampleTick.isEven) {
          await sampleQualityMargin(
            sampledAt: now,
            frame: frame,
            previousFrame: previousFrame,
            hwdecCurrent: effectiveHwdec,
          );
        }
      }
    } finally {
      playbackHealthSampling = false;
    }
  }

  /**
   * 复用播放健康 Timer 的低频样本评估自动画质与可选增强实时余量。
   *
   * 属性读取只执行一次；第二阶段协调器仅在档位变化时重建滤镜，HDR 映射只在
   * 压力触发时执行一次完整回滚，不增加新的 UI Timer 或逐帧读取。
   */
  Future<void> sampleQualityMargin({
    required DateTime sampledAt,
    required int? frame,
    required int? previousFrame,
    required String? hwdecCurrent,
  }) async {
    final details =
        detailsService.cachedDetailsFor(currentItem) ?? const MediaDetails();
    final sourceFps = parseMpvNumber(await getMpvProperty('container-fps'));
    final estimatedFps =
        parseMpvNumber(await getMpvProperty('estimated-vf-fps'));
    final cacheDuration =
        parseMpvNumber(await getMpvProperty('demuxer-cache-duration'));
    final decoderDrops =
        parseMpvInt(await getMpvProperty('decoder-frame-drop-count'));
    final outputDrops =
        parseMpvInt(await getMpvProperty('vo-drop-frame-count'));
    final totalDrops = parseMpvInt(await getMpvProperty('frame-drop-count'));
    final sample = PlayerAdaptiveQualitySample(
      sampledAt: sampledAt,
      playing: playerService.state.playing,
      buffering: playerService.state.buffering,
      recentSeek: lastSeekAt != null &&
          sampledAt.difference(lastSeekAt!) < const Duration(seconds: 3),
      videoAdvanced:
          frame != null && previousFrame != null && frame > previousFrame,
      videoStalled: videoProgressState == '视频帧停滞',
      audioStalled: audioProgressState == '音频播放头停滞',
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
    if (compressionEnhancementMode != PlayerCompressionEnhancementMode.off &&
        !nvidiaCpuEnhancementsSuspended &&
        !adaptiveQualitySessionBlocked) {
      final decision = adaptiveQualityCoordinator.evaluate(
        sample,
        preferClarity: compressionEnhancementMode ==
            PlayerCompressionEnhancementMode.clarity,
      );
      if (decision.changed && !isExiting) {
        final result = await PlayerAdaptiveQualityEnhancer.apply(
          backend: playerService,
          level: decision.level,
          darkSceneEnhancementEnabled: darkSceneEnhancementActive,
          nvidiaVideoEnhancementEnabled:
              nvidiaVideoEnhancementExperimentEnabled,
          nvidiaVideoHdrEnabled: nvidiaVideoHdrExperimentEnabled,
        );
        adaptiveQualityApplyResult = result;
        if (result.applied) {
          adaptiveQualityLevel = decision.level;
        } else {
          adaptiveQualityLevel = PlayerAdaptiveQualityLevel.off;
          adaptiveQualitySessionBlocked = true;
        }
        debugPrint(
          'PLAYER_ADAPTIVE_QUALITY level=${decision.level.name} '
          'profile=${decision.profile.label} reason=${decision.reason}',
        );
      }
    }
    if (darkSceneEnhancementActive && !isExiting) {
      final darkDecision = darkSceneSafetyCoordinator.evaluate(sample);
      if (darkDecision.shouldRollback) {
        final guardedPath = openedPath;
        final result = await PlayerAdaptiveQualityEnhancer.apply(
          backend: playerService,
          level: adaptiveQualityLevel,
          darkSceneEnhancementEnabled: false,
          nvidiaVideoEnhancementEnabled:
              nvidiaVideoEnhancementExperimentEnabled,
          nvidiaVideoHdrEnabled: nvidiaVideoHdrExperimentEnabled,
        );
        if (!mounted || openedPath != guardedPath) return;
        adaptiveQualityApplyResult = result;
        darkSceneEnhancementApplyResult = result;
        darkSceneEnhancementActive = !result.applied;
        darkSceneEnhancementRollbackReason = result.applied
            ? darkDecision.reason
            : '${darkDecision.reason}；回滚属性未确认';
        darkSceneEnhancementRollbackAt = sampledAt;
        debugPrint(
          'PLAYER_DARK_SCENE_ENHANCEMENT rollback=true '
          'reason=${darkDecision.reason}',
        );
      }
    }
    if ((nvidiaVideoEnhancementExperimentEnabled ||
            nvidiaVideoHdrExperimentEnabled) &&
        !isExiting) {
      final nvidiaDecision = nvidiaVideoSafetyCoordinator.evaluate(sample);
      if (nvidiaDecision.shouldRollback) {
        final guardedPath = openedPath;
        await PlayerAdaptiveQualityEnhancer.apply(
          backend: playerService,
          level: PlayerAdaptiveQualityLevel.off,
        );
        if (!mounted || openedPath != guardedPath) return;
        rebuild(() {
          nvidiaVideoEnhancementExperimentEnabled = false;
          nvidiaVideoHdrExperimentEnabled = false;
          nvidiaVideoEnhancementRollbackReason = nvidiaDecision.reason;
          nvidiaVideoEnhancementRollbackAt = sampledAt;
          nvidiaVideoAutomaticReason = '播放压力触发 NVIDIA 自动回滚';
        });
        await restoreCpuEnhancementsAfterNvidia();
        if (!mounted || openedPath != guardedPath) return;
        await probeNvidiaVideoEnhancementCapability();
        debugPrint(
          'PLAYER_NVIDIA_VIDEO_ENHANCEMENT rollback=true '
          'reason=${nvidiaDecision.reason}',
        );
      }
    }
    if (smoothMotionActive && !isExiting) {
      final smoothMotionDecision =
          smoothMotionSafetyCoordinator.evaluate(sample);
      if (smoothMotionDecision.shouldRollback) {
        final guardedPath = openedPath;
        final result = await playerService.applySmoothMotion(
          PlayerSmoothMotionMode.off,
        );
        if (!mounted || openedPath != guardedPath) return;
        smoothMotionActive = false;
        smoothMotionApplyReason = result.reason;
        smoothMotionRollbackReason = smoothMotionDecision.reason;
        smoothMotionRollbackAt = sampledAt;
        debugPrint(
          'PLAYER_SMOOTH_MOTION rollback=true '
          'reason=${smoothMotionDecision.reason}',
        );
      }
    }
    if (!hdrMappingExperimentActive || isExiting) return;
    final hdrDecision = hdrMappingSafetyCoordinator.evaluate(sample);
    if (!hdrDecision.shouldRollback) return;
    final guardedPath = openedPath;
    final result = await PlayerHdrMappingExperiment.apply(
      backend: playerService,
      enabled: false,
    );
    if (!mounted || openedPath != guardedPath) return;
    hdrMappingApplyResult = result;
    hdrMappingExperimentActive = !result.applied;
    hdrMappingRollbackReason =
        result.applied ? hdrDecision.reason : '${hdrDecision.reason}；回滚属性未确认';
    hdrMappingRollbackAt = sampledAt;
    debugPrint(
      'PLAYER_HDR_MAPPING rollback=true reason=${hdrDecision.reason}',
    );
  }

  void showVideoControls() => interaction.showControls();

  /** 显示短时快捷键结果；控制条仍只由底部热区或设置入口唤出。 */
  void showShortcutFeedback(
    String label,
    IconData icon, {
    bool isSeekWatermark = false,
  }) {
    interaction.showFeedback(
      label: label,
      icon: icon,
      isSeekWatermark: isSeekWatermark,
    );
  }

  /** 控制条进出状态只协调计时，不触发播放、筛选队列或媒体后台任务。 */
  void setPointerInControlBar(bool inside) =>
      interaction.setPointerInControlBar(inside);

  /** 根据画面局部坐标识别底部 112px 控制区；画面其它区域不得唤出控制条。 */
  void handleVideoControlsPointer(PointerEvent event) {
    final renderBox =
        videoControlsRegionKey.currentContext?.findRenderObject() as RenderBox?;
    final inside = renderBox != null &&
        playerPointerInControlBar(
          localY: event.localPosition.dy,
          surfaceHeight: renderBox.size.height,
        );
    setPointerInControlBar(inside);
  }

  /**
   * 抓取当前视频帧并让用户选择保存位置。
   *
   * 截图由 media_kit 获取编码后的 JPEG；文件写入只发生在用户确认保存路径后，
   * 不修改媒体库记录、缩略图缓存或当前 filtered queue。
   */
  Future<void> saveCurrentFrameScreenshot() async {
    try {
      final bytes = await playerService.screenshot(format: 'image/jpeg');
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前画面暂时无法截图')),
        );
        return;
      }
      final safeTitle =
          currentItem.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = await withPlayerShortcutsSuspended(
        () => pageWidget.fileSystem.pickSavePath(
          dialogTitle: '保存当前画面',
          suggestedName:
              '${safeTitle.isEmpty ? 'video' : safeTitle}_$timestamp.jpg',
          allowedExtensions: const <String>['jpg'],
        ),
      );
      if (outputPath == null || !mounted) return;
      await pageWidget.fileSystem.writeBytes(outputPath, bytes, flush: true);
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

  /** 构建画面底部统一浮层控制条；全屏不再额外挂载顶部队列语境。 */
}
