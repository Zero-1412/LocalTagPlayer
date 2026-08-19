import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/playback_settings.dart';
import 'player_input_qa_evidence.dart';
import 'player_video_aspect_mode.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 处理音量、画面比例、进度跳转与传输控制。
 *
 * 这里只承载 [PlayerPageState] 的实现细节；播放会话、过滤队列与资源生命周期所有权
 * 仍保留在页面状态对象中。
 */
extension PlayerStateTransport on PlayerPageState {
  void setPlayerVolume(double value) {
    final nextVolume = value.clamp(0, 100).toDouble();
    if (nextVolume == volume) {
      return;
    }
    if (nextVolume > 0) {
      lastAudibleVolume = nextVolume;
    }
    rebuild(() => volume = nextVolume);
    unawaited(playerService.setVolume(nextVolume));
  }

  /** 按 5 点步长调整音量，供方向键和鼠标滚轮共用。 */
  void stepPlayerVolume(double delta) {
    setPlayerVolume(playerVolumeAfterStep(volume, delta));
  }

  /** 在静音与最近一次非零音量之间切换，不改变全局播放配置。 */
  void togglePlayerMute() {
    if (volume > 0) {
      lastAudibleVolume = volume;
    }
    setPlayerVolume(
      playerVolumeAfterMuteToggle(
        currentVolume: volume,
        lastAudibleVolume: lastAudibleVolume,
      ),
    );
  }

  /** 仅处理视频画面内的垂直滚轮，右侧队列继续拥有自己的滚动行为。 */
  void handleVideoPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = playerVolumeDeltaForScroll(event.scrollDelta.dy);
    if (delta != 0) {
      stepPlayerVolume(delta);
    }
  }

  /**
   * 原生后端在 render 回调完成后递增 `native-rendered-frames`；Texture 与 child HWND
   * 都可能拥有这个计数，故必须沿用后端声明的输出类型标注证据。未声明类型时保持
   * unknown，不能把兼容后端的计数猜成正式 Texture。
   */
  Future<int?> readPresentedVideoFrame() async {
    final nativeRendered =
        parseMpvInt(await getMpvProperty('native-rendered-frames'));
    if (nativeRendered != null) {
      lastPresentedVideoFrameEvidence = switch (
        playerService.framePresentationEvidenceKind
      ) {
        'texture' => 'native-rendered-texture',
        'child-hwnd' => 'native-rendered-child-hwnd',
        _ => 'native-rendered-output-unknown',
      };
      return nativeRendered;
    }
    lastPresentedVideoFrameEvidence = 'estimated-frame-number-fallback';
    return parseMpvInt(await getMpvProperty('estimated-frame-number'));
  }

  /**
   * 精确 seek 已落点后轮询 Texture 渲染号。向前、向后 seek 都只要求帧号发生变化；不使用
   * 大小比较，以免反向跳转把正确的新帧误判为旧帧。超时会留下诊断而非伪造成功证据。
   */
  Future<bool> waitForPresentedVideoFrame(
    int? previousFrame,
    Duration timeout,
  ) async {
    final stopwatch = Stopwatch()..start();
    while (!isExiting && stopwatch.elapsed < timeout) {
      final currentFrame = await readPresentedVideoFrame();
      if (currentFrame != null &&
          (previousFrame == null || currentFrame != previousFrame)) {
        lastVideoFrameNumber = currentFrame;
        lastVideoAdvanceAt = DateTime.now();
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    debugPrint(
      'PLAYER_SEEK frame_presentation_timeout '
      'previous=$previousFrame timeout_ms=${timeout.inMilliseconds}',
    );
    return false;
  }

  /**
   * 更新当前会话的画面比例并立即应用到 mpv。
   *
   * 自动、4:3 与 16:9 保持完整画面；铺满使用 panscan 等比裁边，主要用于
   * 1728×1080 等非 16:9 视频在全屏时消除左右留边和源内黑边的组合效果。
   */
  Future<void> setVideoAspectMode(PlayerVideoAspectMode mode) async {
    final changed = videoAspectMode != mode;
    if (changed && mounted) {
      rebuild(() => videoAspectMode = mode);
      saveGlobalPlaybackSettings(
        effectivePlaybackSettings.copyWith(videoAspectMode: mode),
      );
    }
    await applyVideoAspectMode();
  }

  /**
   * 串行保存当前播放器配置。
   *
   * 页面先更新真实播放状态，再把同一个值写回应用级配置；保存失败只提示用户，
   * 不回滚已经生效的当前会话，以免 UI 与播放内核出现二次跳变。
   */
  void saveGlobalPlaybackSettings(PlaybackSettings settings) {
    effectivePlaybackSettings = settings;
    playbackSettingsSaveTail = playbackSettingsSaveTail.then((_) async {
      try {
        await pageWidget.onPlaybackSettingsChanged(settings);
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
  Future<void> applyVideoAspectMode() async {
    await setMpvProperty(
      'video-aspect-override',
      videoAspectMode.mpvAspectOverride,
    );
    await setMpvProperty('panscan', videoAspectMode.mpvPanscan);
    // 切换模式时归零历史缩放，避免诊断或外部属性残留叠加到新的比例选择。
    await setMpvProperty('video-zoom', '0');
    await setMpvProperty('video-pan-x', '0');
    await setMpvProperty('video-pan-y', '0');
  }

  /** 鼠标进入或移动时显示控制条；播放中空闲三秒后自动淡出。 */
  /**
   * 执行 seek 并记录从请求到播放器返回的耗时，供持续诊断识别随机拖动压力。
   */
  Future<void> seekWithDiagnostics(Duration target) async {
    if (isExiting) {
      return;
    }
    // 进度条只在手势结束后提交一次精确落点，不能先 keyframe 预览再精确 seek；
    // 否则同一次拖动会在后端形成双跳转，并放大长 GOP 的可感知卡顿。
    cancelKeyboardSeek();
    // 精确 seek 从前一关键帧解码时不允许旧声音先恢复；位置确认且新帧交付后才解除静音。
    await seekAudioGate.run(() => seekExactlyWithDiagnostics(target));
  }

  /**
   * 处理鼠标进度条的最终精确跳转。
   *
   * 拖动过程由 Slider 本地视觉值和缩略图预览承担，解码器只在松手后收到一次普通 seek。
   * 精确协调器是 latest-only，连续点击只替换尚未下发目标；音频门禁等待目标新帧后再
   * 恢复，避免准确落点前先听到旧位置声音。进度条组件自身保留鼠标目标，避免位置流
   * 尚未追上时滑块回弹。
   */
  Future<void> seekFromProgressBarWithDiagnostics(Duration target) async {
    if (isExiting) {
      return;
    }
    cancelKeyboardSeek();
    final generation = ++progressSeekGeneration;
    try {
      if (pageWidget.progressDragSeekMode ==
          PlayerProgressDragSeekMode.fastPreviewThenExact) {
        await _seekProgressWithFastPreviewThenExact(target);
      } else {
        await seekWithDiagnostics(target);
      }
    } finally {
      // 长 GOP 关键帧可能永远不会落在目标容差内；超时或后端回到其它有效位置时，
      // 页面必须退回真实 position，不能让乐观目标永久遮住播放器状态。
      if (mounted && generation == progressSeekGeneration) {
        setOptimisticProgressPosition(null);
      }
    }
  }

  /**
   * 两阶段拖动合同：先请求目标附近关键帧以缩短可见反馈，再提交既有精确 seek 收敛
   * 真实目标。预览不解除静音；任何一个阶段异常都会沿用原有失败处理与
   * 乐观位置回退，不能把关键帧位置伪装成准确落点。
   */
  Future<void> _seekProgressWithFastPreviewThenExact(Duration target) async {
    await seekAudioGate.run(() async {
      final frameBeforePreview = await seekAudioGate.captureFinalFrame();
      final traceId = seekAudioGate.activeTraceId;
      seekTrace.mark(traceId, 'progress_preview_submit', target: target);
      PlayerInputQaEvidence.progressPreviewSeekSubmitted();
      await playerService.seekInteractive(target);
      final previewPresented = await waitForPresentedVideoFrame(
        frameBeforePreview,
        const Duration(milliseconds: 600),
      );
      seekTrace.mark(
        traceId,
        previewPresented
            ? 'progress_preview_frame'
            : 'progress_preview_frame_timeout',
        target: target,
        framePresented: previewPresented,
        frameEvidence: lastPresentedVideoFrameEvidence,
      );
      // 即使预览超时也继续既有精确定位，不能让 Debug 实验改变用户的准确落点合同。
      await seekExactlyWithDiagnostics(target);
    });
    PlayerInputQaEvidence.progressExactSeekConfirmed();
  }

  /**
   * 执行继续观看所需的精确 seek，并保留既有位置确认与延迟诊断语义。
   *
   * 该协调器只服务进度条和继续观看等明确的精确落点，不与键盘关键帧预览工作器
   * 共享待提交目标，避免不同入口互相改写。
   */
  Future<void> seekExactlyWithDiagnostics(Duration target) async {
    await exactSeekCoordinator.request(target);
    // PlayerSeekCoordinator 的确认窗口耗尽时会安全结束 worker，以免把 native 状态
    // 卡死；进度条精确合同不能把这种“命令已返回但实际位置未收敛”当成功。这里在
    // AudioGate 允许恢复声音前做最后一次同步后置条件检查。
    final actual = playerService.state.position;
    if ((actual - target).abs() > const Duration(milliseconds: 100)) {
      if (mounted) {
        setOptimisticProgressPosition(null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未能准确定位到拖动位置，请重试')),
        );
      }
      debugPrint(
        'PLAYER_EXACT_SEEK_UNCONFIRMED target_ms=${target.inMilliseconds} '
        'actual_ms=${actual.inMilliseconds}',
      );
      throw TimeoutException(
        '精确定位未在确认窗口内收敛',
        const Duration(seconds: 2),
      );
    }
  }

  /**
   * 短按在 KeyUp 提交唯一关键帧跳转；长按前进转为连续高速播放，快退保持关键帧预览。
   */
  Duration seekRelative(
    Duration delta, {
    required bool mutePreview,
    required bool isRepeat,
  }) {
    return keyboardSeek.requestRelative(
      delta,
      // 只有长按快退仍以 latest-only 关键帧预览推进；前进的首个 KeyRepeat 会由
      // controller 切到临时倍速，不能继续把更多随机 seek 压进解码链。
      submitPreview: true,
      mutePreview: mutePreview,
      isRepeat: isRepeat,
    );
  }

  /** KeyUp 收敛短按关键帧预览，或恢复长按快进前的原速度与音量。 */
  void settleKeyboardSeek() {
    unawaited(keyboardSeek.settlePreview());
  }

  /** 切换媒体、进度条提交或退出时取消旧键盘目标和尚未提交的预览。 */
  void cancelKeyboardSeek() {
    keyboardSeekAction = null;
    keyboardSeekLogicalKey = null;
    progressSeekGeneration++;
    seekCoordinator.cancelPending();
    exactSeekCoordinator.cancelPending();
    keyboardSeek.cancel();
  }

  /**
   * 返回前先暂停音频，但保留最后一帧直到反向路由已经开始。
   *
   * 正常路径的 stop 由 dispose 串行执行，避免播放器纹理在媒体库完全接管画面前变黑
   * 或重置到 0:00；只有 pause 失败时才提前 stop，优先保证不会残留声音。
   */
}
