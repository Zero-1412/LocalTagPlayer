import 'dart:async';

import '../../core/tag_rules.dart';
import '../../features/player/domain/player_playback_progress.dart';
import '../../models/player_feature_apply_result.dart';
import '../../models/video_item.dart';
import '../../services/player/player_video_super_resolution.dart';
import 'player_playback_mode.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 处理后端事件与基础播放设置。
 *
 * 这里只承载 [PlayerPageState] 的实现细节；播放会话、过滤队列与资源生命周期所有权
 * 仍保留在页面状态对象中。
 */
extension PlayerStateEvents on PlayerPageState {
  /** 让进度条的本地目标同时驱动时间文本和隐藏态进度反馈。 */
  void setOptimisticProgressPosition(Duration? position) {
    if (optimisticProgressPosition == position) {
      return;
    }
    rebuild(() => optimisticProgressPosition = position);
  }

  /**
   * 处理播放内核在 open 完成后才报告的运行期错误。
   *
   * 打开 worker 运行期间由可播放性确认统一收口，避免旧媒体迟到错误覆盖快速切换后的新视频。
   */
  void handlePlayerError(String code) {
    if (!mounted || openRequests.isOpening) {
      return;
    }
    final path = openedPath;
    if (path == null || path != currentItem.path) {
      return;
    }
    openedPath = null;
    openRequests.markImmediateFailure(currentOpenTarget, code: code);
    unawaited(playerService.stop());
    rebuild(() {});
  }

  /** 以低频写入当前已打开视频的进度，避免播放流每帧触发 SQLite。 */
  void handlePosition(Duration position) {
    final optimistic = optimisticProgressPosition;
    if (mounted &&
        optimistic != null &&
        (position - optimistic).abs() <= const Duration(milliseconds: 500)) {
      rebuild(() => optimisticProgressPosition = null);
    }
    final openedPathSnapshot = openedPath;
    if (openRequests.isOpening ||
        choosingPlaybackStart ||
        openedPathSnapshot == null ||
        position <= Duration.zero) {
      return;
    }
    final now = DateTime.now();
    final elapsed = lastProgressWriteAt == null
        ? const Duration(days: 1)
        : now.difference(lastProgressWriteAt!);
    final advanced = (position - lastPersistedPosition).abs();
    if (elapsed < const Duration(seconds: 5) &&
        advanced < const Duration(seconds: 5)) {
      return;
    }
    final item = itemForPath(openedPathSnapshot);
    if (item == null) {
      return;
    }
    lastProgressWriteAt = now;
    lastPersistedPosition = position;
    final duration = playerService.state.duration;
    unawaited(pageWidget.onPlaybackProgressUpdated(
      item,
      position,
      duration,
      playerPlaybackIsNearCompletion(position: position, duration: duration),
    ));
  }

  /** 从来源队列解析当前路径，确保进度写入对应视频而不是刚切换的新条目。 */
  VideoItem? itemForPath(String path) {
    for (final item in sourcePlaylist) {
      if (TagRules.pathKey(item.path) == TagRules.pathKey(path)) {
        return item;
      }
    }
    return null;
  }

  /**
   * 处理播放完成事件，在当前 filtered queue 内顺序进入下一条。
   *
   * media_kit 在打开新媒体时会发送 false，因此路径去重只防御同一 EOF 的重复 true；
   * 到达队尾时明确停止并提示，不默认循环到队首。
   */
  void handlePlaybackCompleted(bool completed) {
    if (!completed) {
      handledCompletedPath = null;
      // 用户在队尾重新播放或拖动进度后，完成提示应立即退出。
      if (mounted && queueEndReached) {
        rebuild(() => queueEndReached = false);
      }
      return;
    }
    if (!mounted || queue.isEmpty) {
      return;
    }
    final completedPath = currentItem.path;
    // 旧媒体在快速切换期间迟到的 EOF 不能推进新队列项。
    if (openedPath != completedPath) {
      return;
    }
    if (handledCompletedPath == completedPath) {
      return;
    }
    handledCompletedPath = completedPath;
    final duration = playerService.state.duration;
    unawaited(
      pageWidget.onPlaybackProgressUpdated(
        currentItem,
        duration,
        duration,
        true,
      ),
    );
    final targetIndex = playerCompletionTargetIndex(
      mode: playbackMode,
      currentIndex: index,
      queueLength: queue.length,
      randomValue: random.nextDouble(),
    );
    if (targetIndex == null) {
      rebuild(() => queueEndReached = true);
      showQueueEndMessage();
      return;
    }
    jumpTo(targetIndex, ignoreFollowUpSelection: true);
  }

  /** 修改倍速并立即应用到当前播放内核；切换视频时 media_kit 会保留该状态。 */
  void setPlaybackRate(double rate) {
    if (!PlayerPageState.playbackRates.contains(rate) || playbackRate == rate) {
      return;
    }
    rebuild(() => playbackRate = rate);
    unawaited(playerService.setRate(rate));
    saveGlobalPlaybackSettings(
      effectivePlaybackSettings.copyWith(playbackRate: rate),
    );
  }

  /** 按固定档位调整倍速，供菜单与键盘快捷键共用同一条状态链路。 */
  void stepPlaybackRate(int delta) {
    final current = PlayerPageState.playbackRates.indexOf(playbackRate);
    final next =
        (current + delta).clamp(0, PlayerPageState.playbackRates.length - 1);
    setPlaybackRate(PlayerPageState.playbackRates[next]);
  }

  /** 更新快进与快退共用档位；仅保存固定秒数，不立即触发 seek。 */
  void setSeekStepSeconds(int seconds) {
    if (!PlayerPageState.seekStepOptions.contains(seconds) ||
        seekStepSeconds == seconds) {
      return;
    }
    rebuild(() => seekStepSeconds = seconds);
    saveGlobalPlaybackSettings(
      effectivePlaybackSettings.copyWith(seekStepSeconds: seconds),
    );
  }

  /** 更新队列播放方式，不改变 filtered queue 的内容或顺序。 */
  void setPlaybackMode(PlayerPlaybackMode mode) {
    if (playbackMode == mode) return;
    rebuild(() {
      playbackMode = mode;
      queueEndReached = false;
    });
    saveGlobalPlaybackSettings(
      effectivePlaybackSettings.copyWith(playbackMode: mode),
    );
  }

  /** 更新全局镜像状态，不改变媒体文件、控制条方向或播放队列。 */
  void setMirrorVideo(bool enabled) {
    if (mirrorVideo == enabled) return;
    rebuild(() => mirrorVideo = enabled);
    saveGlobalPlaybackSettings(
      effectivePlaybackSettings.copyWith(mirrorVideo: enabled),
    );
  }

  /**
   * 即时切换 libmpv GPU 高质量缩放并异步持久化。
   *
   * Flutter 只重绘设置开关；高质量缩放留在 mpv GPU renderer，不能在 UI isolate
   * 解码或处理视频帧，也不能触发 filtered queue 与媒体详情重算。
   */
  void setVideoSuperResolutionEnabled(bool enabled) {
    if (videoSuperResolutionEnabled == enabled) return;
    rebuild(() {
      videoSuperResolutionEnabled = enabled;
      videoSuperResolutionActive = false;
      videoSuperResolutionApplyResult =
          const PlayerFeatureApplyResult.notRequested(
        'gpu-high-quality-scaling',
      );
    });
    saveGlobalPlaybackSettings(
      effectivePlaybackSettings.copyWith(
        videoSuperResolutionEnabled: enabled,
      ),
    );
    unawaited(applyVideoSuperResolutionSetting(enabled));
  }

  /**
   * 提交 GPU 缩放并只在当前媒体仍匹配时发布读回结果。
   *
   * 用户开关表达请求，诊断中的“已生效”必须来自属性回读，不能在点击瞬间乐观冒充。
   */
  Future<void> applyVideoSuperResolutionSetting(bool enabled) async {
    final guardedPath = openedPath;
    final result = await PlayerVideoSuperResolution.apply(
      backend: playerService,
      enabled: enabled,
      baseScaler: videoScaler,
    );
    if (!mounted ||
        guardedPath != openedPath ||
        videoSuperResolutionEnabled != enabled) {
      return;
    }
    rebuild(() {
      videoSuperResolutionApplyResult = result;
      videoSuperResolutionActive = enabled && result.applied;
    });
  }

  /**
   * 只读检测隔离原生 QA 后端的 NVIDIA scaling mode。
   *
   * 检测不加载 NVIDIA 文件、不写 `vf`，也不经过本机视频增强插件 ABI；媒体
   * 打开后会再次读取实际 `hwdec-current`，避免把配置值误当成零拷贝证据。
   */
}
