import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/playback_settings.dart';
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
    // 拖动进度条时只保留最新目标，避免大量并发 seek 让视频解码停止而音频继续推进。
    final duration = playerService.state.duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && target > duration
            ? duration
            : target;
    latestRequestedSeekTarget = clamped;
    pendingSeekTarget = clamped;
    seekRequestGeneration++;
    if (seekInFlight) {
      return;
    }
    seekInFlight = true;
    try {
      while (!isExiting && pendingSeekTarget != null) {
        final observedGeneration = seekRequestGeneration;
        // 拖动松手、鼠标连点或键盘连按都先进入短尾随防抖；只让停止变化的最终
        // 目标进入解码器，界面反馈仍由本地滑块和快捷键水印即时完成。
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (observedGeneration != seekRequestGeneration) {
          continue;
        }
        final requested = pendingSeekTarget!;
        pendingSeekTarget = null;
        final stopwatch = Stopwatch()..start();
        await playerService.seek(requested);
        // media_kit 的 seek Future 只代表命令已提交；等待位置接近目标后再记录真实延迟。
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (!isExiting && DateTime.now().isBefore(deadline)) {
          // 已有更新目标时无需等待旧位置落稳，立即把解码器推进到用户最终选择。
          if (pendingSeekTarget != null) {
            break;
          }
          final delta = (playerService.state.position - requested).abs();
          if (delta <= const Duration(milliseconds: 750)) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        stopwatch.stop();
        lastSeekLatencyMs = stopwatch.elapsedMilliseconds;
        lastSeekAt = DateTime.now();
      }
    } finally {
      seekInFlight = false;
      latestRequestedSeekTarget = null;
    }
  }

  /**
   * 相对跳转在 seek 未完成时基于用户最新目标累加，而不是反复读取滞后的后端位置。
   */
  void seekRelative(Duration delta) {
    final base = seekInFlight
        ? (latestRequestedSeekTarget ?? playerService.state.position)
        : playerService.state.position;
    unawaited(seekWithDiagnostics(base + delta));
  }

  /**
   * 返回前先暂停音频，但保留最后一帧直到反向路由已经开始。
   *
   * 正常路径的 stop 由 dispose 串行执行，避免播放器纹理在媒体库完全接管画面前变黑
   * 或重置到 0:00；只有 pause 失败时才提前 stop，优先保证不会残留声音。
   */
}
