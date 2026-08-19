import 'dart:async';

import '../../core/playback_settings.dart';
import '../../features/player/application/player_open_request_controller.dart';
import '../../features/player/domain/player_playback_progress.dart';
import '../../models/video_item.dart';
import '../../services/player/player_adaptive_quality.dart';
import 'player_page.dart';
import 'player_resume_dialog.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 承载打开失败、可播放性检测和继续观看收敛。
 *
 * 这些恢复动作与打开 worker 同属页面状态，但拆成独立叶文件，避免打开协调器继续
 * 膨胀；它们仍复用同一个 latest-request、资源释放和来源队列所有权。
 */
extension PlayerStateOpeningRecovery on PlayerPageState {
  /**
   * 保留损坏媒体的有界检测，并把失败收口成稳定的播放器错误状态。
   *
   * 普通新视频会先播放再进入这里；如果底层没有时长、音频或视频 codec 证据，
   * 仍会在原有窗口结束后停止，不能让“快速启动”变成永久黑屏或旧媒体叠播。
   */
  Future<bool> ensurePlayableMedia(PlayerOpenRequest request) async {
    final playable = await waitForPlayableMedia(request);
    if (playable) {
      return true;
    }
    // 快速切换已有更新请求时只放弃旧验证，不展示过时错误。
    invalidateOpenedMediaEvents();
    openedPath = null;
    if (!openRequests.hasSuperseded(request)) {
      openRequests.markFailure(
        request,
        code: 'unplayable_media',
      );
    }
    // 即使已经有更新请求，损坏/无首帧的 open 也必须先停止，保证下一条媒体
    // 不会在旧失败会话上叠加播放状态。
    await safeStopPlayer(reason: 'unplayable-media');
    return false;
  }

  /**
   * 清除上一条媒体的滤镜并收敛当前画质属性。
   *
   * 继续观看在精确 seek 前等待此步骤；普通新视频在显式 play 后再执行，避免把
   * 首帧交付与可选画质属性的多次平台往返绑定成一个启动门禁。
   */
  Future<void> settleMediaOpeningProperties(PlayerOpenRequest request) async {
    if (openRequests.hasSuperseded(request)) {
      return;
    }
    adaptiveQualityApplyResult = await PlayerAdaptiveQualityEnhancer.apply(
      backend: playerService,
      level: PlayerAdaptiveQualityLevel.off,
      darkSceneEnhancementEnabled: false,
    );
    if (openRequests.hasSuperseded(request)) {
      return;
    }
    await applyMediaPresentationProfile();
  }

  /**
   * 等待本地媒体产生有效时长或 codec 证据。
   *
   * 0 字节/损坏 MP4 的 `Player.open` 可能成功返回却永久停在 00:00；限定等待窗口后将其
   * 归入稳定错误面板。检测期间如出现更新 open 请求则立即放弃旧验证，保护快速切换流畅度。
   */
  Future<bool> waitForPlayableMedia(PlayerOpenRequest request) async {
    // 保持约 1.5 秒损坏媒体判定窗口，但把新请求响应粒度从 250ms 缩短到 80ms。
    const attempts = 19;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (openRequests.hasSuperseded(request)) {
        return false;
      }
      final videoCodec = await getMpvProperty('video-codec');
      if (openRequests.hasSuperseded(request)) {
        return false;
      }
      final audioCodec = await getMpvProperty('audio-codec');
      if (playerMediaStateIsPlayable(
        duration: playerService.state.duration,
        videoCodec: videoCodec,
        audioCodec: audioCodec,
      )) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    return false;
  }

  /** 按设置页默认行为处理有效进度；仅“每次询问”继续弹出选择框。 */
  Future<void> choosePlaybackStart(VideoItem item) async {
    final duration = playerService.state.duration;
    final saved = playerResumePosition(
      saved: item.playbackPosition,
      duration: duration,
      completed: item.playbackCompleted,
    );
    if (saved == null) {
      // MediaKit open 使用 play:false；没有历史进度时也必须在打开门禁完成后显式启动。
      if (mounted && openedVideoId == item.videoId) {
        await playerService.play();
      }
      return;
    }
    final behavior = pageWidget.playbackSettings.resumeBehavior;
    PlayerResumeChoice choice;
    if (behavior == PlaybackResumeBehavior.ask) {
      await playerService.pause();
      if (!mounted || openedVideoId != item.videoId) {
        return;
      }
      choice = await withPlayerOverlaySurfaceOccluded(
        () => showPlayerResumeDialog(
          context,
          item: item,
          position: saved,
          duration: duration,
        ),
      );
    } else {
      choice = behavior == PlaybackResumeBehavior.continueWatching
          ? PlayerResumeChoice.continueWatching
          : PlayerResumeChoice.restart;
    }
    if (!mounted || openedVideoId != item.videoId) {
      return;
    }
    final start =
        choice == PlayerResumeChoice.continueWatching ? saved : Duration.zero;
    // 继续观看需要恢复到已保存的精确时间，不能复用进度条的关键帧优先随机跳转。
    await seekExactlyWithDiagnostics(start);
    await playerService.play();
    lastPersistedPosition = start;
    lastProgressWriteAt = DateTime.now();
    if (choice == PlayerResumeChoice.restart) {
      unawaited(pageWidget.onPlaybackProgressUpdated(
        item,
        Duration.zero,
        duration,
        false,
      ));
    }
  }

  /** 从失败面板重新关联 missing 文件，成功后原地打开同一稳定 videoId。 */
  Future<void> relinkCurrentMissing() async {
    final item = currentItem;
    final relinked = await withPlayerShortcutsSuspended(
      () => pageWidget.onRelinkMissing(item),
    );
    if (!mounted || !relinked) {
      return;
    }
    rebuild(() => openRequests.clearFailure());
    requestOpenCurrent();
  }

  /** 重新打开最近失败的视频，并继续复用 latest-request worker。 */
  void retryFailedOpen() {
    if (openRequests.retryFailure()) {
      rebuild(() => queueEndReached = false);
      unawaited(drainOpenRequests());
    }
  }

  /** 跳过失败项；队尾不循环，只显示当前筛选队列结束提示。 */
  void skipFailedOpen() {
    final nextIndex = playback.nextIndex;
    rebuild(() {
      queueEndReached = nextIndex == null;
      openRequests.clearFailure();
    });
    if (nextIndex == null) {
      showQueueEndMessage();
      return;
    }
    jumpTo(nextIndex, ignoreFollowUpSelection: true);
  }
}
