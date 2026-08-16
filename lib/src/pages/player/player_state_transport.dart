import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/playback_settings.dart';
import '../../features/player/application/player_seek_coordinator.dart';
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
   * Windows 原生桥在 mpv render 回调完成共享纹理复制并通知 Flutter Texture 后递增
   * `native-rendered-frames`，这是最终精确落点已进入 Texture 的直接证据。非原生桥
   * 才退回 mpv 的估算帧号，并把来源写入 trace，不能把回退值与屏幕呈现混为一谈。
   */
  Future<int?> readPresentedVideoFrame() async {
    final nativeRendered =
        parseMpvInt(await getMpvProperty('native-rendered-frames'));
    if (nativeRendered != null) {
      lastPresentedVideoFrameEvidence = 'native-rendered-texture';
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
    // 进度条只在手势结束后提交一次精确落点，不能先预览再精确 seek；
    // 否则同一次拖动会在后端形成双跳转，并放大长 GOP 的可感知卡顿。
    cancelKeyboardSeek();
    // 精确 seek 从前一关键帧解码时不允许旧声音先恢复；位置确认且新帧交付后才解除静音。
    await seekAudioGate.run(() => seekExactlyWithDiagnostics(target));
  }

  /**
   * 处理鼠标进度条的交互式跳转。
   *
   * 进度条点击必须复用页面级 latest-only 协调器：第一次点击立即下发，后续快速点击
   * 只替换尚未下发的目标，不能让每个点击都排队等待新帧和音量恢复。进度条组件自身
   * 保留鼠标目标，避免位置流尚未追上时滑块回弹；继续观看恢复仍走精确 seek 与音频门禁。
   */
  Future<void> seekFromProgressBarWithDiagnostics(Duration target) async {
    if (isExiting) {
      return;
    }
    cancelKeyboardSeek();
    final generation = ++progressSeekGeneration;
    try {
      await seekCoordinator.request(target);
    } finally {
      // 长 GOP 关键帧可能永远不会落在目标容差内；超时或后端回到其它有效位置时，
      // 页面必须退回真实 position，不能让乐观目标永久遮住播放器状态。
      if (mounted && generation == progressSeekGeneration) {
        setOptimisticProgressPosition(null);
      }
    }
  }

  /**
   * 执行继续观看所需的精确 seek，并保留既有位置确认与延迟诊断语义。
   *
   * 该协调器只服务单次精确落点，不与长按的关键帧预览工作器共享待提交目标，
   * 避免短按或进度条提交被随后到达的交互式请求改写。
   */
  Future<void> seekExactlyWithDiagnostics(Duration target) async {
    final exactCoordinator = PlayerSeekCoordinator(
      submit: playerService.seek,
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
    );
    await exactCoordinator.request(target);
  }

  /** 键盘先提交关键帧预览；短按 KeyUp 精确收敛，长按保持 latest-only 预览。 */
  Duration seekRelative(
    Duration delta, {
    required bool mutePreview,
    bool isRepeat = false,
  }) {
    return keyboardSeek.requestRelative(
      delta,
      isRepeat: isRepeat,
      // 首次短按先走关键帧路径，KeyUp 再用独立精确命令确认完整步长；长按不重复精确 seek。
      submitPreview: true,
      mutePreview: mutePreview,
    );
  }

  /** KeyUp 收敛键盘会话；短按精确到完整步长，长按不重复绝对 seek。 */
  void settleKeyboardSeek() {
    unawaited(keyboardSeek.settlePreview());
  }

  /** 切换媒体、进度条提交或退出时取消旧键盘目标和尚未提交的预览。 */
  void cancelKeyboardSeek() {
    keyboardSeekAction = null;
    keyboardSeekLogicalKey = null;
    progressSeekGeneration++;
    seekCoordinator.cancelPending();
    keyboardSeek.cancel();
  }

  /**
   * 返回前先暂停音频，但保留最后一帧直到反向路由已经开始。
   *
   * 正常路径的 stop 由 dispose 串行执行，避免播放器纹理在媒体库完全接管画面前变黑
   * 或重置到 0:00；只有 pause 失败时才提前 stop，优先保证不会残留声音。
   */
}
