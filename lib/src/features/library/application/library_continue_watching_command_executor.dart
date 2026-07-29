import 'dart:collection';

import '../../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/** 按 stable videoId 选择需要清理继续观看状态的目标。 */
List<VideoItem> recentPlaybackClearTargets(
  Iterable<VideoItem> videos, {
  required Set<String> selectedVideoIds,
  required bool selectedOnly,
}) {
  return videos.where((item) {
    if (item.lastPlayedAt == null) {
      return false;
    }
    return !selectedOnly || selectedVideoIds.contains(item.videoId);
  }).toList(growable: false);
}

/**
 * 清理继续观看前保存的完整播放状态。
 *
 * Undo 恢复最近播放时间、精确位置、完成态和位置更新时间；稳定身份校验禁止旧快照覆盖
 * 另一个视频或用户在撤销窗口内产生的新进度。
 */
class ContinueWatchingClearSnapshot {
  const ContinueWatchingClearSnapshot._({
    required this.item,
    required this.videoId,
    required this.lastPlayedAt,
    required this.playbackPosition,
    required this.playbackCompleted,
    required this.playbackPositionUpdatedAt,
  });

  /** 捕获一次清理动作之前的用户播放状态。 */
  factory ContinueWatchingClearSnapshot.capture(VideoItem item) =>
      ContinueWatchingClearSnapshot._(
        item: item,
        videoId: item.videoId,
        lastPlayedAt: item.lastPlayedAt,
        playbackPosition: item.playbackPosition,
        playbackCompleted: item.playbackCompleted,
        playbackPositionUpdatedAt: item.playbackPositionUpdatedAt,
      );

  /** 当前内存中的稳定视频对象；恢复时不替换，避免列表和播放器持有旧引用。 */
  final VideoItem item;

  /** 清理时的视频稳定身份。 */
  final String videoId;

  /** 清理前用于继续观看排序的最近播放时间。 */
  final DateTime? lastPlayedAt;

  /** 清理前的精确播放位置。 */
  final Duration playbackPosition;

  /** 清理前的播放完成态。 */
  final bool playbackCompleted;

  /** 清理前用于解决异步写入先后顺序的位置更新时间。 */
  final DateTime? playbackPositionUpdatedAt;

  /** 仅当记录仍保持本次清理后的空状态时允许 Undo。 */
  bool get canRestoreWithoutOverwritingNewPlayback =>
      item.videoId == videoId &&
      item.lastPlayedAt == null &&
      item.playbackPosition == Duration.zero &&
      !item.playbackCompleted &&
      item.playbackPositionUpdatedAt == null;

  /** 把捕获的精确播放状态恢复到原稳定视频对象。 */
  void restore() {
    item
      ..lastPlayedAt = lastPlayedAt
      ..playbackPosition = playbackPosition
      ..playbackCompleted = playbackCompleted
      ..playbackPositionUpdatedAt = playbackPositionUpdatedAt;
  }

  /** 清空可撤销字段；保留时长、收藏、标签和其它用户数据。 */
  void clear() {
    item
      ..lastPlayedAt = null
      ..playbackPosition = Duration.zero
      ..playbackCompleted = false
      ..playbackPositionUpdatedAt = null;
  }
}

/** 继续观看清理/撤销的应用层结果。 */
class ContinueWatchingCommandResult {
  ContinueWatchingCommandResult._({
    required this.succeeded,
    required Iterable<ContinueWatchingClearSnapshot> snapshots,
    this.nothingToRestore = false,
    this.error,
  }) : snapshots = UnmodifiableListView<ContinueWatchingClearSnapshot>(
          snapshots.toList(growable: false),
        );

  /** 命令成功；[snapshots] 是清理后的撤销输入或撤销后的已恢复项。 */
  factory ContinueWatchingCommandResult.success(
    Iterable<ContinueWatchingClearSnapshot> snapshots,
  ) =>
      ContinueWatchingCommandResult._(
        succeeded: true,
        snapshots: snapshots,
      );

  /** 撤销窗口内已产生新进度，没有安全可恢复项。 */
  factory ContinueWatchingCommandResult.noRestorableItems() =>
      ContinueWatchingCommandResult._(
        succeeded: false,
        snapshots: const <ContinueWatchingClearSnapshot>[],
        nothingToRestore: true,
      );

  /** Repository 失败；executor 已恢复与持久化状态一致的内存模型。 */
  factory ContinueWatchingCommandResult.failed(
    Iterable<ContinueWatchingClearSnapshot> snapshots,
    Object error,
  ) =>
      ContinueWatchingCommandResult._(
        succeeded: false,
        snapshots: snapshots,
        error: error,
      );

  final bool succeeded;
  final List<ContinueWatchingClearSnapshot> snapshots;
  final bool nothingToRestore;
  final Object? error;
}

/**
 * 继续观看清理与撤销的无 UI 命令执行器。
 *
 * executor 只维护同一 `VideoItem` 的可补偿播放字段并注入批量 Repository 提交；不持有
 * Store、BuildContext、Route、SnackBar、筛选结果或播放器资源。
 */
class LibraryContinueWatchingCommandExecutor {
  const LibraryContinueWatchingCommandExecutor();

  /** 清理目标并在 Repository 失败时恢复完整播放快照。 */
  Future<ContinueWatchingCommandResult> clear(
    Iterable<VideoItem> targets, {
    required Future<void> Function(List<VideoItem> items) commit,
  }) async {
    final snapshots = targets
        .map(ContinueWatchingClearSnapshot.capture)
        .toList(growable: false);
    for (final snapshot in snapshots) {
      snapshot.clear();
    }
    try {
      await commit(
        snapshots.map((snapshot) => snapshot.item).toList(growable: false),
      );
      return ContinueWatchingCommandResult.success(snapshots);
    } catch (error) {
      for (final snapshot in snapshots) {
        snapshot.restore();
      }
      return ContinueWatchingCommandResult.failed(snapshots, error);
    }
  }

  /** 只恢复仍为空的记录；提交失败时重新清空，保持内存与 SQLite 一致。 */
  Future<ContinueWatchingCommandResult> undo(
    Iterable<ContinueWatchingClearSnapshot> snapshots, {
    required Future<void> Function(List<VideoItem> items) commit,
  }) async {
    final restorable = snapshots
        .where((snapshot) => snapshot.canRestoreWithoutOverwritingNewPlayback)
        .toList(growable: false);
    if (restorable.isEmpty) {
      return ContinueWatchingCommandResult.noRestorableItems();
    }
    for (final snapshot in restorable) {
      snapshot.restore();
    }
    try {
      await commit(
        restorable.map((snapshot) => snapshot.item).toList(growable: false),
      );
      return ContinueWatchingCommandResult.success(restorable);
    } catch (error) {
      for (final snapshot in restorable) {
        snapshot.clear();
      }
      return ContinueWatchingCommandResult.failed(restorable, error);
    }
  }
}
