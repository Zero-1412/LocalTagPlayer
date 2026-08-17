import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../core/tag_rules.dart';
import '../../features/library/application/library_revision_tracker.dart';
import '../../features/library/application/library_source_navigation_controller.dart';
import '../../models/library_sort.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../services/library/library_application_facade.dart';
import '../../services/tags/tag_query_service.dart';
import '../../widgets/library/library_confirmation_dialogs.dart';
import '../../widgets/library/library_local_view.dart';

import 'library_page_state_host.dart';

// ignore_for_file: slash_for_doc_comments

/** LibraryPageNavigationMixin 按既有一致性边界承载页面协调逻辑，不复制业务状态 owner。 */
mixin LibraryPageNavigationMixin<T extends StatefulWidget>
    on LibraryPageStateHost<T> {
  @override
  void refreshStableTagCountsNow(LibraryApplicationFacade store) {
    runtime.facetCountController.refreshStableNow(
      query: const FilterQuery(),
      compute: store.resultCounts,
    );
  }

  /**
   * 构建本地媒体库当前路径的直接子项。
   *
   * 文件夹从磁盘目录读取；视频只取已入库项目，确保播放、缩略图、收藏和更多操作继续复用现有 VideoItem 管线。
   */
  @override
  Future<List<LocalLibraryEntry>> localLibraryEntries(
    LibraryApplicationFacade store,
  ) async {
    final currentPath = runtime.localLibraryPath;
    if (currentPath == null || currentPath.isEmpty) {
      return const <LocalLibraryEntry>[];
    }
    if (!await fileSystem.directoryExists(currentPath)) {
      return const <LocalLibraryEntry>[];
    }
    final folders = <LocalLibraryEntry>[];
    final videos = <VideoItem>[];
    final children = await fileSystem.listFiles(
      currentPath,
      recursive: false,
    );
    children.sort((a, b) {
      final aIsDirectory = a.isDirectory;
      final bIsDirectory = b.isDirectory;
      if (aIsDirectory != bIsDirectory) {
        return aIsDirectory ? -1 : 1;
      }
      return p.basename(a.path).compareTo(p.basename(b.path));
    });
    for (final child in children) {
      if (child.isDirectory) {
        folders.add(LocalLibraryEntry.folder(child.path));
        continue;
      }
      if (TagRules.isVideoPath(child.path)) {
        final video = store.videos[TagRules.pathKey(child.path)];
        if (video != null) {
          videos.add(video);
        }
      }
    }
    return [
      ...folders,
      for (final video in runtime.sortController.sort(videos))
        LocalLibraryEntry.video(video),
    ];
  }

  /** 在现有 setState 中退出主媒体多选并清空临时选择。 */
  void clearLibrarySelectionState() {
    runtime.librarySelection.clear();
  }

  /**
   * 修改筛选条件并刷新当前可见结果。
   *
   * 高频交互（标签点击、搜索输入）默认只刷新视频列表，标签计数这类重任务
   * 只在库结构变化、扫描、标签管理返回等低频路径显式开启，避免大媒体库下点击卡顿。
   */
  @override
  void mutateFilters(
    VoidCallback mutation, {
    bool refreshCounts = false,
    bool collapseTagPanel = false,
  }) {
    setState(() {
      clearLibrarySelectionState();
      runtime.sourceNavigation.showLibraryResults();
      mutation();
      runtime.viewPreferences.setTagDiscoveryPanelOpen(
        libraryTagDiscoveryPanelOpenAfterMutation(
          currentOpen: runtime.isTagDiscoveryPanelOpen,
          collapseAfterMutation: collapseTagPanel,
        ),
      );
    });
    scheduleFilterRefresh(refreshCounts: refreshCounts);
  }

  /**
   * 应用排序字段或方向变更。
   *
   * 排序只改变当前结果的展示顺序，不改变筛选条件、标签数量或收藏状态；
   * 这里直接重排内存中的 `FilterState`，避免切换排序时触发完整过滤和 resultCounts 统计。
   */
  @override
  void applySortChange({
    SortMode? sortMode,
    SortDirection? sortDirection,
  }) {
    LibrarySortPreferences? preferences;
    setState(() {
      if (!runtime.sortController.apply(
        mode: sortMode,
        direction: sortDirection,
      )) {
        return;
      }
      preferences = runtime.libraryDisplayPreferences;
      if (runtime.resultMode != LibraryResultMode.library ||
          runtime.queryController.state == null) {
        return;
      }
      final currentState = runtime.queryController.state!;
      final sortedState = FilterState(
        epoch: resultEpoch(currentState.query),
        query: currentState.query,
        filteredVideos:
            runtime.sortController.sort(currentState.filteredVideos),
        resultCount: currentState.resultCount,
        totalCount: currentState.totalCount,
      );
      runtime.queryController.publish(
        sortedState,
        expectedEpoch: sortedState.epoch,
      );
    });
    final changedPreferences = preferences;
    if (changedPreferences != null) {
      unawaited(
        applicationService.saveSortPreferences(changedPreferences),
      );
    }
  }

  /**
   * 切换网格/列表并复用展示偏好文件持久化，不触发过滤、计数或缩略图全量刷新。
   */
  void setResultView(bool dense) {
    if (runtime.denseResultGrid == dense) {
      return;
    }
    setState(() => runtime.viewPreferences.setDenseResultGrid(dense));
    unawaited(applicationService.saveSortPreferences(
      runtime.libraryDisplayPreferences,
    ));
  }

  /** 切换主功能栏并复用展示偏好文件保存，进入媒体库时恢复上次状态。 */
  void toggleMainSidebar() {
    setState(runtime.viewPreferences.toggleMainSidebar);
    unawaited(
      applicationService.saveSortPreferences(runtime.libraryDisplayPreferences),
    );
  }

  /**
   * 回到媒体库全量视图。
   *
   * 侧栏“媒体库”应像重置入口：清空搜索、一级/二级/分组/排除/收藏筛选，并展示全量视频，
   * 避免用户从最近播放或某个标签视图返回时仍被旧条件限制。
   */
  void showAllLibraryVideos() {
    final store = runtime.store;
    setState(() {
      clearLibrarySelectionState();
      runtime.sourceNavigation.resetToLibrary();
      runtime.recentPlaybackSelection.clear();
      clearSearchSilently();
      runtime.selectedTags.clear();
      runtime.selectedChildTags.clear();
      runtime.selectedGroupTagIds.clear();
      runtime.excludedTagIds.clear();
      runtime.showFavoritesOnly = false;
      if (store != null) {
        runtime.queryController.seed(buildImmediateFilterState(store));
      }
    });
    scheduleFilterRefresh();
  }

  /**
   * 切换到最近播放结果视图。
   *
   * 最近播放是主结果区的一种数据源，不再用弹窗承载；切换时清空筛选条件，让用户看到的列表只由播放记录决定。
   */
  void showRecentPlaybackVideos() {
    setState(() {
      clearLibrarySelectionState();
      runtime.sourceNavigation.showRecent();
      runtime.recentPlaybackSelection.clear();
      clearSearchSilently();
      runtime.selectedTags.clear();
      runtime.selectedChildTags.clear();
      runtime.selectedGroupTagIds.clear();
      runtime.excludedTagIds.clear();
      runtime.showFavoritesOnly = false;
    });
  }

  /**
   * 切换到收藏结果视图。
   *
   * 该入口直接从当前内存视频集合筛选收藏项，同时保留 favoriteOnly 状态；
   * 后续再点击右侧标签时会切回普通媒体库筛选，但收藏条件仍会作为 AND 条件叠加。
   */
  void showFavoriteVideos() {
    setState(() {
      clearLibrarySelectionState();
      runtime.sourceNavigation.showFavorites();
      runtime.recentPlaybackSelection.clear();
      clearSearchSilently();
      runtime.selectedTags.clear();
      runtime.selectedChildTags.clear();
      runtime.selectedGroupTagIds.clear();
      runtime.excludedTagIds.clear();
      runtime.showFavoritesOnly = true;
    });
  }

  /**
   * 打开本地媒体库路径。
   *
   * 只切换当前浏览路径和结果模式；实际文件扫描仍由添加目录/重新扫描负责。
   */
  void showLocalLibraryPath(String rootPath) {
    setState(() {
      clearLibrarySelectionState();
      runtime.sourceNavigation.showLocalRoot(rootPath);
      runtime.recentPlaybackSelection.clear();
      clearSearchSilently();
      runtime.selectedTags.clear();
      runtime.selectedChildTags.clear();
      runtime.selectedGroupTagIds.clear();
      runtime.excludedTagIds.clear();
      runtime.showFavoritesOnly = false;
    });
  }

  /**
   * 从当前本地媒体库路径进入子文件夹。
   *
   * 该操作只改变 UI 浏览路径，不触发扫描，也不改变 root 配置或视频索引。
   */
  void openLocalLibraryFolder(String folderPath) {
    setState(() {
      runtime.sourceNavigation.openLocalFolder(folderPath);
    });
  }

  /**
   * 回到本地媒体库上一个浏览路径。
   *
   * 返回按钮和鼠标侧键共用该方法，保证两种入口的历史栈行为一致。
   */
  void goBackLocalLibraryPath() {
    if (!runtime.sourceNavigation.canGoBack) {
      return;
    }
    setState(() => runtime.sourceNavigation.goBack());
  }

  /**
   * 从侧栏解除一个 root 的媒体库管理状态。
   *
   * 本地文件、稳定视频身份、用户数据和可复用缓存保持不动；仍被其它重叠 root 覆盖的
   * 视频继续 active，仅不再受任何 root 覆盖的条目进入 detached 归档。
   */
  Future<void> removeLocalLibraryRoot(String root) async {
    final store = runtime.store;
    if (store == null) {
      return;
    }
    final confirmed = await showRemoveLibraryRootConfirmation(
      context,
      root: root,
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await removeLibraryRootData(root);
  }

  /**
   * 提交 root 解除管理并把 active 结果差量应用到当前媒体库。
   *
   * 系统确认弹窗和隔离压测共用此方法；Store 只切换 detached 状态，绝不删除 root
   * 下的本地媒体文件、稳定身份或用户维护数据。
   */
  @override
  Future<int> removeLibraryRootData(String root) async {
    final store = runtime.store;
    if (store == null) {
      return 0;
    }
    // root 移除会使大批 probe candidate 失效。先推进 generation 并丢弃排队回调，
    // 避免删除事务期间旧 FFmpeg 结果重新 upsert 已移除的视频。
    runtime.libraryMediaDetailsService?.dispose();
    runtime.libraryMediaDetailsService = null;
    final removedVideos = await store.removeRoot(root);
    if (!mounted) {
      return removedVideos.length;
    }
    final removedVideoIds = removedVideos.map((item) => item.videoId).toSet();
    runtime.pendingResultDeltaVideoIds.addAll(removedVideoIds);
    runtime.pendingRemovedVideoIds.addAll(removedVideoIds);
    setState(() {
      // 解除管理改变了 active 数据源；必须提升 revision，禁止 FilterStateSource 复用
      // 操作前的 11k 列表缓存，否则 SQLite 已完成但 UI 总量会长期停留在旧值。
      runtime.libraryRevisionTracker.record(
        LibraryDataChangeKind.tagDefinitions,
      );
      invalidateDerivedCaches();
      runtime.sourceNavigation.leaveRemovedRoot(root);
      refreshStableTagCountsNow(store);
    });
    scheduleFilterRefresh(
      refreshCounts: true,
      removedVideoIds: removedVideoIds.isEmpty ? null : removedVideoIds,
    );
    // 缩略图与媒体详情均可在 root 重新加入时复用，解除管理不能把缓存当作垃圾清除。
    return removedVideos.length;
  }

  /**
   * 清理最近播放记录。
   *
   * 该动作清空继续观看状态，但不删除视频、收藏或标签。
   */
}
