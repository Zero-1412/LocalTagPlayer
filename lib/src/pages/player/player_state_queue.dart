import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/playback_settings.dart';
import '../../features/player/domain/player_playback_progress.dart';
import '../../models/video_item.dart';
import 'player_delete_dialog.dart';
import 'player_queue_sidebar.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 处理 filtered queue 选择、定位、收藏与删除动作。
 *
 * 这里只承载 [PlayerPageState] 的实现细节；播放会话、过滤队列与资源生命周期所有权
 * 仍保留在页面状态对象中。
 */
extension PlayerStateQueue on PlayerPageState {
  void select(int selectedIndexCandidate) {
    if (selectedIndexCandidate < 0 || selectedIndexCandidate >= queue.length) {
      return;
    }
    final ignoreBefore = ignoreQueueSelectionBefore;
    if (ignoreBefore != null) {
      if (DateTime.now().isBefore(ignoreBefore) &&
          selectedIndexCandidate != index) {
        return;
      }
      ignoreQueueSelectionBefore = null;
    }
    rebuild(() => playback.select(selectedIndexCandidate));
    // 鼠标单击发生在已经可见的队列项上，只更新选中态；若此处立刻滚动，
    // 双击的第二击会落到移动后的另一行。离屏选中项由“定位已选中”显式定位。
  }

  void selectQueueIndex(int index, {bool center = false}) {
    if (queue.isEmpty) {
      return;
    }
    late int nextIndex;
    rebuild(() => nextIndex = playback.selectQueueIndex(index));
    ensureQueueIndexVisible(nextIndex, center: center);
  }

  /**
   * 从离屏位置回到播放项，但保留用户当前浏览选择。
   *
   * “正在播放”是播放器事实，“已选中”是用户在队列中的浏览焦点；定位动作不得把
   * 后者静默覆盖，否则用户再点“回到选中”时会丢失原先浏览位置。
   */
  void returnToPlayingQueueItem(ScrollController controller) {
    if (queue.isEmpty) {
      return;
    }
    final playingIndex = playback.locatePlayingIndex();
    ensureQueueIndexVisible(
      playingIndex,
      center: true,
      // 显式定位需要立即落点；大队列跨段动画会连续重建 Windows 无障碍树，
      // 不仅浪费可视区域 I/O，还可能让桌面端语义桥接失稳。
      animated: false,
      controller: controller,
    );
  }

  /** 搜索当前 filtered queue 并直接定位播放，不访问全媒体库。 */
  PlayerQueueSearchOutcome searchQueue(String query) {
    if (query.trim().isEmpty) {
      return PlayerQueueSearchOutcome.emptyQuery;
    }
    final matchedIndex = playerQueueSearchIndex(
      queue,
      query,
      startIndex: index,
    );
    if (matchedIndex == null) {
      return PlayerQueueSearchOutcome.noMatch;
    }
    jumpTo(matchedIndex, ignoreFollowUpSelection: true);
    return PlayerQueueSearchOutcome.played;
  }

  void jumpTo(int index, {bool ignoreFollowUpSelection = false}) {
    if (index < 0 || index >= queue.length) {
      return;
    }
    persistOpenedProgress();
    if (ignoreFollowUpSelection) {
      ignoreQueueSelectionBefore =
          DateTime.now().add(const Duration(milliseconds: 700));
    }
    rebuild(() {
      queueEndReached = false;
      playback.jumpTo(index);
    });
    ensureQueueIndexVisible(index, center: true);
    requestOpenCurrent();
  }

  /** 切换或退出前补写当前位置、总时长和动态完成态。 */
  void persistOpenedProgress() {
    final openedVideoIdSnapshot = openedVideoId;
    final position = playerService.state.position;
    final duration = playerService.state.duration;
    if (openedVideoIdSnapshot == null || position <= Duration.zero) {
      return;
    }
    final item = itemForVideoId(openedVideoIdSnapshot);
    if (item == null) {
      return;
    }
    unawaited(pageWidget.onPlaybackProgressUpdated(
      item,
      position,
      duration,
      playerPlaybackIsNearCompletion(position: position, duration: duration),
    ));
  }

  /** 切换队列项收藏并刷新当前页面，不重算 filtered queue。 */
  Future<void> toggleQueueFavorite(VideoItem item) async {
    try {
      await pageWidget.onToggleFavorite(item);
      if (mounted) {
        rebuild(() {});
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('收藏状态更新失败，请重试')),
      );
    }
  }

  /**
   * 删除任意队列项；非播放项只调整索引，删除当前播放项时才重启播放后端。
   */
  Future<void> deleteQueueItem(int queueIndex) async {
    if (queueIndex < 0 || queueIndex >= queue.length) {
      return;
    }
    final item = queue[queueIndex];
    final settings = effectivePlaybackSettings;
    final decision = videoDeleteDecisionWithoutPrompt(settings) ??
        await withPlayerOverlaySurfaceOccluded(
          () => showPlayerDeleteConfirmationDialog(
            context,
            item,
          ),
        );
    if (decision == null || !mounted) {
      return;
    }

    if (settings.confirmBeforeDeletingVideo) {
      // 只有确认提交才记忆弹窗选择；取消不会改写后续删除行为。
      final saved = await saveDeletePreferencesBeforeAction(
        settings.copyWith(
          confirmBeforeDeletingVideo: !decision.dontAskAgain,
        ),
      );
      if (!saved || !mounted) {
        return;
      }
    }

    try {
      final deletingPlayingItem = queueIndex == index;
      if (deletingPlayingItem) {
        persistOpenedProgress();
        await playerService.stop();
      }
      await pageWidget.onDeleteVideo(item);
      if (!mounted) {
        return;
      }
      if (queue.length == 1) {
        // 不先把会话队列改成空列表；exitPlayer 的异步暂停/全屏收尾期间页面仍会
        // build 当前项，提前 remove 会让 currentItem 越界并留下半帧空播放器。
        await exitPlayer();
        return;
      }
      rebuild(() {
        queueEndReached = false;
        playback.removeItemAt(queueIndex);
      });
      ensureQueueIndexVisible(index, center: true);
      if (deletingPlayingItem) {
        requestOpenCurrent();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已移入回收站并移除媒体库记录',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('移除失败，本地文件或媒体库记录未完成，请重试')),
      );
    }
  }

  /**
   * 删除动作使用比普通播放偏好更严格的持久化门禁。
   *
   * 先等待既有设置写入，再保存本次最终删除状态；失败时中止删除，避免后续无提示
   * 删除行为与磁盘上的设置文件分叉。
   */
  Future<bool> saveDeletePreferencesBeforeAction(
    PlaybackSettings settings,
  ) async {
    await playbackSettingsSaveTail;
    try {
      await pageWidget.onPlaybackSettingsChanged(settings);
      effectivePlaybackSettings = settings;
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('保存删除偏好失败：$error；本次未执行删除')),
          );
      }
      return false;
    }
  }
}
