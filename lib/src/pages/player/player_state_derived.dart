import 'package:flutter/material.dart';

import '../../features/player/application/player_open_request_controller.dart';
import '../../models/video_item.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放器页面的低风险派生状态和队列入口。
 *
 * 这些方法不拥有会话、稳定身份或 filtered queue；它们只把已有 owner 的状态转换成
 * 页面/侧栏需要的视图，避免把派生代码重新堆回 PlayerPage 主聚合文件。
 */
extension PlayerStateDerived on PlayerPageState {
  List<VideoItem> get sourcePlaylist => playback.sourcePlaylist;

  List<VideoItem> get queue => playback.queue;

  String? get selectedChildTag => playback.selectedChildTag;

  int get index => playback.playingIndex;

  int get selectedIndex => playback.selectedIndex;

  VideoItem get currentItem => playback.currentItem;

  PlayerOpenTarget get currentOpenTarget =>
      (videoId: currentItem.videoId, path: currentItem.path);

  bool get controlsVisible => interaction.controlsVisible;

  bool get shortcutFeedbackVisible => interaction.feedbackVisible;

  String? get shortcutFeedbackLabel => interaction.feedbackLabel;

  IconData get shortcutFeedbackIcon => interaction.feedbackIcon;

  bool get settingsDialogOpen => interaction.settingsOpen;

  bool get isWindowFullscreen => windowFullscreen.isFullscreen;

  bool get fullscreenTransitionInProgress =>
      windowFullscreen.transitionInProgress;

  String get filterSummary {
    final value = widget.queueTitle.trim();
    return value.isEmpty ? '\u5168\u90e8\u89c6\u9891' : value;
  }

  String? get activeParentTag =>
      widget.activeTags.length == 1 ? widget.activeTags.first : null;

  void selectChildTag(String tag) {
    if (queue.isEmpty) {
      return;
    }
    persistOpenedProgress();
    rebuild(() {
      queueEndReached = false;
      playback.toggleChildTag(tag, preferredVideoId: currentItem.videoId);
    });
    ensureQueueIndexVisible(index, center: true);
    requestOpenCurrent();
  }
}
