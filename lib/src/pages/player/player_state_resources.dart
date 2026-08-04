import 'dart:async';

import 'package:flutter/material.dart';

import 'player_context_panel.dart';
import 'player_queue_sidebar.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 释放播放器页面持有的可取消资源。
 *
 * 主文件仍负责调用 `super.dispose()`，确保 State 生命周期边界清晰。
 */
extension PlayerStateResources on PlayerPageState {
  void disposePlayerPage() {
    // 路由或测试直接卸载播放器时同样进入退出态，禁止尚未结束的健康采样把释放期停顿误判为 HDR 压力。
    isExiting = true;
    cancelKeyboardSeek();
    openRequests.cancel();
    interaction.dispose();
    queuePrefetchTimer?.cancel();
    fullscreenQueueHideTimer?.cancel();
    playbackHealthTimer?.cancel();
    mediaControlShortcutPrefixTimer?.cancel();
    detailsService.dispose();
    persistOpenedProgress();
    queueScrollController.dispose();
    fullscreenQueueScrollController.dispose();
    focusNode.dispose();
    unawaited(playerResources.release());
  }

  /**
   * 资源协调器完成唯一释放链后，记录退出时序并通知媒体库允许下一次进入。
   */
  void handlePlayerResourcesReleased(DateTime releaseStartedAt) {
    debugPrint(
      'PLAYER_EXIT requested=${exitRequestedAt?.toIso8601String()} '
      'pause_ack=${pauseAcknowledgedAt?.toIso8601String()} '
      'pop=${routePopRequestedAt?.toIso8601String()} '
      'dispose_start=${releaseStartedAt.toIso8601String()} '
      'dispose_end=${DateTime.now().toIso8601String()}',
    );
    if (!pageWidget.disposalCompleter.isCompleted) {
      pageWidget.disposalCompleter.complete();
    }
  }

  /** 构建当前 filtered queue 侧栏；不同布局实例使用独立滚动控制器。 */
  Widget buildQueueSidebar({
    ScrollController? scrollController,
    Key? key,
    bool edgeToEdge = false,
    double? width,
  }) {
    final controller = scrollController ?? queueScrollController;
    final queuePanel = PlayerQueueSidebar(
      key: const ValueKey('player.queue.sidebar.content'),
      embedded: true,
      playlist: queue,
      sourcePlaylist: sourcePlaylist,
      playingIndex: index,
      selectedIndex: selectedIndex,
      scrollController: controller,
      thumbnailService: pageWidget.thumbnailService,
      detailsService: detailsService,
      activeTags: pageWidget.activeTags,
      selectedChildTag: selectedChildTag,
      onChildTagSelected: selectChildTag,
      onSelect: select,
      onPlay: jumpTo,
      onReturnToPlaying: () => returnToPlayingQueueItem(controller),
      onLocateSelected: () => ensureQueueIndexVisible(
        selectedIndex,
        center: true,
        // 与“回到播放”一致，一次跳转避免大队列动画期间的语义节点风暴。
        animated: false,
        controller: controller,
      ),
      onSearchQueue: searchQueue,
      onSearchVisibilityChanged: handleQueueSearchVisibilityChanged,
      onDeleteSelected: queue.isEmpty
          ? null
          : () => unawaited(deleteQueueItem(selectedIndex)),
      onToggleFavorite: (item) => unawaited(toggleQueueFavorite(item)),
      onDeleteItem: (index) => unawaited(deleteQueueItem(index)),
    );
    return PlayerSidePanel(
      key: key ?? const ValueKey('player.queue.sidebar'),
      queuePanel: queuePanel,
      item: currentItem,
      queueEndReached: queueEndReached,
      onRenameFile: () => unawaited(renameCurrentFile()),
      onEditManualTags: () => unawaited(editManualTags()),
      edgeToEdge: edgeToEdge,
      width: width,
    );
  }
}
