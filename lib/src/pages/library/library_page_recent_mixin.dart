import 'dart:async';
import 'package:flutter/material.dart';
import '../../features/library/application/library_continue_watching_command_executor.dart';
import '../../features/library/application/library_revision_tracker.dart';
import '../../features/library/application/library_source_navigation_controller.dart';
import '../../models/library_scan_models.dart';
import '../../models/video_item.dart';
import '../../services/library/library_application_facade.dart';
import '../../widgets/library/library_confirmation_dialogs.dart';
import '../../widgets/library/library_local_view.dart';
import '../../features/player/domain/player_playback_progress.dart';

import 'library_page_state_host.dart';

// ignore_for_file: slash_for_doc_comments

/** LibraryPageRecentMixin 按既有一致性边界承载页面协调逻辑，不复制业务状态 owner。 */
mixin LibraryPageRecentMixin<T extends StatefulWidget>
    on LibraryPageStateHost<T> {
  Future<void> clearRecentPlayback({required bool selectedOnly}) async {
    final store = runtime.store;
    if (store == null) {
      return;
    }
    final targets = recentPlaybackClearTargets(
      store.videos.values,
      selectedVideoIds: runtime.recentPlaybackSelection.selectedVideoIds,
      selectedOnly: selectedOnly,
    );
    if (targets.isEmpty) {
      return;
    }

    if (!selectedOnly) {
      final confirmed = await showClearAllRecentPlaybackConfirmation(
        context,
        count: targets.length,
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    await clearRecentPlaybackTargets(targets);
  }

  /**
   * 批量清理播放状态并提供 10 秒精确 Undo。
   *
   * SQLite 使用既有批量视频行写入，避免逐条 await 放大交互等待；失败时先恢复内存
   * 快照，保证界面不会宣称已清理但数据库仍保留旧状态。
   */
  Future<void> clearRecentPlaybackTargets(List<VideoItem> targets) async {
    final store = runtime.store;
    if (store == null || targets.isEmpty) {
      return;
    }
    final result = await runtime.continueWatchingCommands.clear(
      targets,
      commit: store.upsertPlaybackStates,
    );
    if (!mounted) {
      return;
    }
    if (!result.succeeded) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('清除观看进度失败，原记录已保留')),
      );
      return;
    }
    setState(runtime.recentPlaybackSelection.clear);
    markLibraryDataChanged();
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text('已清除 ${targets.length} 条观看进度，视频文件未删除'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () =>
                unawaited(undoRecentPlaybackClear(result.snapshots)),
          ),
        ),
      );
  }

  /**
   * 清理单个最近播放记录。
   *
   * 单条删除不能依赖“先选中再批量删除”的状态刷新顺序，否则真实鼠标快速点击时会出现命中但未删除。
   */
  Future<void> clearOneRecentPlayback(VideoItem item) async {
    await clearRecentPlaybackTargets(<VideoItem>[item]);
  }

  /**
   * 恢复仍处于本次清理空状态的记录；已产生新播放进度的条目保持新值。
   */
  Future<void> undoRecentPlaybackClear(
    List<ContinueWatchingClearSnapshot> snapshots,
  ) async {
    final store = runtime.store;
    if (store == null) {
      return;
    }
    final result = await runtime.continueWatchingCommands.undo(
      snapshots,
      commit: store.upsertPlaybackStates,
    );
    if (!mounted) {
      return;
    }
    if (result.nothingToRestore) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('记录已产生新的播放进度，未覆盖新状态')),
      );
      return;
    }
    if (!result.succeeded) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('撤销失败，请重试播放以重新生成进度')),
      );
      return;
    }
    markLibraryDataChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已恢复 ${result.snapshots.length} 条观看进度')),
    );
  }

  /**
   * 切换最近播放清理选择状态。
   */
  void toggleRecentSelection(VideoItem item) {
    setState(() => runtime.recentPlaybackSelection.toggle(item.videoId));
  }

  @override
  void markLibraryDataChanged({
    bool tagDefinitionsChanged = false,
  }) {
    runtime.libraryRevisionTracker.record(
      tagDefinitionsChanged
          ? LibraryDataChangeKind.tagDefinitions
          : LibraryDataChangeKind.content,
    );
    invalidateDerivedCaches();
    final store = runtime.store;
    if (store != null) {
      // 数据变化后先回退到持久化 usageCount，精确计数由延后刷新任务更新。
      runtime.facetCountController.clearStable();
    }
    scheduleFilterRefresh(refreshCounts: true);
  }

  /**
   * 把扫描层输出的不可变差量应用到当前界面。
   *
   * 主结果列表只重新评估变化的 stable `videoId`；路径或 folder 标签
   * 可能影响本地目录与侧边栏，因此只定向失效这两类派生缓存。
   */
  @override
  void applyLibraryScanDelta(LibraryScanCommitResult result) {
    if (result.changedVideos.isEmpty) {
      // 零差量不得提升 revision 或失效 folder 侧边栏，否则每次点击重新扫描
      // 都会无意义地重算整个媒体库。
      return;
    }
    runtime.libraryRevisionTracker.record(
      LibraryDataChangeKind.tagDefinitions,
    );
    runtime.tagGroupsCacheKey = null;
    runtime.localEntryCacheKey = null;
    runtime.localEntryCacheByKey.clear();
    if (result.changedVideos.any((item) => item.lastPlayedAt != null)) {
      runtime.recentVideoCacheKey = null;
    }
    if (result.changedVideos.any((item) => item.isFavorite)) {
      runtime.favoriteVideoCacheKey = null;
    }
    runtime.facetCountController.clearStable();
    scheduleFilterRefresh(
      refreshCounts: true,
      changedVideos: result.changedVideos,
    );
  }

  @override
  void invalidateDerivedCaches() {
    runtime.tagGroupsCacheKey = null;
    runtime.localEntryCacheKey = null;
    runtime.localEntryCacheByKey.clear();
    runtime.recentVideoCacheKey = null;
    runtime.favoriteVideoCacheKey = null;
  }

  /**
   * 播放器返回后只更新播放时间相关的可见状态。
   *
   * `lastPlayedAt` 不会改变标签、收藏、路径或筛选命中集合；因此不能复用
   * `markLibraryDataChanged` 的全库标签计数与完整筛选刷新路径，否则从播放器
   * 返回主界面会在大媒体库上产生明显卡顿。
   */
  @override
  void markPlaybackTimestampChanged(VideoItem item) {
    runtime.playbackDataRevision += 1;
    if (runtime.resultMode == LibraryResultMode.library) {
      // 主媒体库默认排序使用添加时间，播放时间更新不再改变当前结果顺序。
      return;
    }

    // 最近播放、本地收藏和本地路径浏览只依赖当前内存对象重建轻量列表。
    if (runtime.resultMode == LibraryResultMode.recent ||
        (runtime.resultMode == LibraryResultMode.favorites &&
            item.isFavorite) ||
        runtime.resultMode == LibraryResultMode.local) {
      setState(() {});
    }
  }

  List<VideoItem> sortedRecentVideos(LibraryApplicationFacade store) {
    final key = (
      'recent',
      runtime.libraryDataRevision,
      runtime.playbackDataRevision,
      runtime.sortMode,
      runtime.sortDirection,
    );
    if (runtime.recentVideoCacheKey == key) {
      return runtime.recentVideoCache;
    }
    runtime.recentVideoCacheKey = key;
    runtime.recentVideoCache = runtime.sortController.sort(
      store.videos.values.where(videoIsContinueWatching),
    );
    return runtime.recentVideoCache;
  }

  List<VideoItem> sortedFavoriteVideos(LibraryApplicationFacade store) {
    final key = (
      'favorites',
      runtime.libraryDataRevision,
      runtime.sortMode,
      runtime.sortDirection,
    );
    if (runtime.favoriteVideoCacheKey == key) {
      return runtime.favoriteVideoCache;
    }
    runtime.favoriteVideoCacheKey = key;
    runtime.favoriteVideoCache = runtime.sortController.sort(
      store.videos.values.where((item) => item.isFavorite),
    );
    return runtime.favoriteVideoCache;
  }

  List<LocalLibraryEntry> cachedLocalLibraryEntries(
    LibraryApplicationFacade store,
  ) {
    final key = (
      'local',
      runtime.libraryDataRevision,
      runtime.localLibraryPath,
      runtime.sortMode,
      runtime.sortDirection,
    );
    if (runtime.localEntryCacheKey == key) {
      return runtime.localEntryCache;
    }
    final cached = runtime.localEntryCacheByKey[key];
    if (cached != null) {
      runtime.localEntryCacheKey = key;
      runtime.localEntryCache = cached;
      return cached;
    }
    if (runtime.localEntryLoads.add(key)) {
      // 目录枚举放到异步平台边界，build 只消费缓存，避免大目录阻塞 UI 线程。
      unawaited(() async {
        try {
          final entries = await localLibraryEntries(store);
          runtime.localEntryCacheByKey[key] = entries;
          while (runtime.localEntryCacheByKey.length > 24) {
            runtime.localEntryCacheByKey
                .remove(runtime.localEntryCacheByKey.keys.first);
          }
          if (mounted &&
              runtime.store == store &&
              runtime.resultMode == LibraryResultMode.local) {
            final currentKey = (
              'local',
              runtime.libraryDataRevision,
              runtime.localLibraryPath,
              runtime.sortMode,
              runtime.sortDirection,
            );
            if (currentKey == key) {
              setState(() {
                runtime.localEntryCacheKey = key;
                runtime.localEntryCache = entries;
              });
            }
          }
        } finally {
          runtime.localEntryLoads.remove(key);
        }
      }());
    }
    return const <LocalLibraryEntry>[];
  }
}
