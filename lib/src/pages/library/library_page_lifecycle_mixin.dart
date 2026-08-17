import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/library_scan_models.dart';
import '../../models/platform_models.dart';
import '../../services/library/library_application_facade.dart';
import '../../services/library/library_load_diagnostics.dart';
import '../../services/library/library_stress_control.dart';
import '../../services/media/thumbnail_service.dart';
import '../../services/player/playback_snapshot_write_queue.dart';
import '../../services/library/video_similarity_scan_controller.dart';

import 'library_page_state_host.dart';

// ignore_for_file: slash_for_doc_comments

/** LibraryPageLifecycleMixin 按既有一致性边界承载页面协调逻辑，不复制业务状态 owner。 */
mixin LibraryPageLifecycleMixin<T extends StatefulWidget>
    on LibraryPageStateHost<T> {
  /** 延后到首帧后的空闲窗口，避免自动补全与 SQLite 首屏恢复争抢 UI 线程。 */
  static const _startupThumbnailBackfillDelay = Duration(milliseconds: 800);
  /** 媒体详情读取再错开一段时间，优先让缩略图先形成可见反馈。 */
  static const _startupMediaDetailsBackfillDelay = Duration(milliseconds: 1600);
  Timer? _startupThumbnailBackfillTimer;
  Timer? _startupMediaDetailsBackfillTimer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(handleGlobalSearchShortcut);
    runtime.searchController.addListener(handleSearchControllerChanged);
    load();
  }

  @override
  void dispose() {
    _startupThumbnailBackfillTimer?.cancel();
    _startupMediaDetailsBackfillTimer?.cancel();
    LibraryStressControl.unregister(this);
    unawaited(runtime.playbackSnapshotQueue?.dispose());
    runtime.libraryMediaDetailsService?.dispose();
    runtime.similarityScanController?.dispose();
    runtime.activeScanUiDiagnostics?.abort();
    HardwareKeyboard.instance.removeHandler(handleGlobalSearchShortcut);
    runtime.searchController.removeListener(handleSearchControllerChanged);
    runtime.searchController.dispose();
    runtime.searchFocusNode.dispose();
    runtime.libraryHeaderVisible.dispose();
    runtime.queryController.dispose();
    runtime.facetCountController.dispose();
    runtime.playbackQueueController.clear();
    runtime.scanLifecycleController.dispose();
    super.dispose();
  }

  /**
   * 在媒体库页面处于最上层时稳定处理 Ctrl+K。
   *
   * Windows 真实窗口中焦点可能停在页面容器而不进入局部 Shortcuts 焦点链，
   * 因此页面生命周期内补充全局键盘处理；弹窗或播放器路由位于上层时不抢焦点。
   */
  bool handleGlobalSearchShortcut(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyK ||
        !HardwareKeyboard.instance.isControlPressed ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    focusSearchField();
    return true;
  }

  void handleSearchControllerChanged() {
    if (runtime.suppressSearchControllerChange) {
      return;
    }
    final keyword = runtime.searchController.text;
    if (keyword == runtime.lastObservedSearchText ||
        runtime.searchControllerChangeQueued) {
      return;
    }
    runtime.lastObservedSearchText = keyword;
    runtime.searchControllerChangeQueued = true;
    scheduleMicrotask(() {
      runtime.searchControllerChangeQueued = false;
      if (!mounted ||
          runtime.searchController.text != runtime.lastObservedSearchText) {
        return;
      }
      mutateFilters(() {}, refreshCounts: false);
    });
  }

  void setSearchTextSilently(String value) {
    if (runtime.searchController.text == value) {
      runtime.lastObservedSearchText = value;
      return;
    }
    runtime.suppressSearchControllerChange = true;
    runtime.searchController.text = value;
    runtime.lastObservedSearchText = value;
    runtime.suppressSearchControllerChange = false;
  }

  @override
  void clearSearchSilently() => setSearchTextSilently('');

  /**
   * 聚焦主搜索框并选中已有关键字。
   *
   * 该方法只处理焦点，不直接触发筛选；真实键盘或自动化输入随后写入
   * `TextEditingController`，再由统一的监听链路刷新结果。
   */
  void focusSearchField() {
    runtime.searchFocusNode.requestFocus();
    runtime.searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: runtime.searchController.text.length,
    );
    // Windows 全局快捷键可能与本帧的页面 Focus 重建竞争；下一帧再次确认焦点，
    // 让真实键盘和自动化输入稳定落到同一个 EditableText。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      runtime.searchFocusNode.requestFocus();
      runtime.searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: runtime.searchController.text.length,
      );
    });
  }

  Future<void> load() async {
    final diagnostics =
        (kDebugMode || kProfileMode) ? LibraryLoadDiagnostics() : null;
    final startupWatch = Stopwatch()..start();
    final startupData = await applicationService.load(
      diagnostics: diagnostics,
    );
    final store = startupData.store;
    final thumbnailService = startupData.thumbnailService;
    final playbackSettings = startupData.playbackSettings;
    final dataBackupSettings = startupData.dataBackupSettings;
    final sortPreferences = startupData.sortPreferences;
    if (!mounted) {
      await store.close();
      return;
    }
    runtime.playbackSnapshotQueue = PlaybackSnapshotWriteQueue(
      writer: (snapshot) async {
        snapshot.item
          ..playbackPosition = snapshot.position
          ..playbackDuration = snapshot.duration
          ..playbackCompleted = snapshot.completed
          ..playbackPositionUpdatedAt = snapshot.updatedAt
          ..lastPlayedAt = snapshot.updatedAt;
        await store.savePlaybackPosition(
          videoId: snapshot.item.videoId,
          position: snapshot.position,
          duration: snapshot.duration,
          completed: snapshot.completed,
          updatedAt: snapshot.updatedAt,
        );
      },
    );
    final firstFrameWatch = Stopwatch()..start();
    void applyHydratedState() => setState(() {
          runtime.sortController.restore(sortPreferences);
          runtime.viewPreferences.setDenseResultGrid(
            sortPreferences.denseResultGrid,
          );
          runtime.viewPreferences.setMainSidebarCollapsed(
            sortPreferences.mainSidebarCollapsed,
          );
          runtime.store = store;
          runtime.thumbnailService = thumbnailService;
          runtime.resourceScheduler = startupData.resourceScheduler;
          runtime.similarityScanController ??= VideoSimilarityScanController(
            store: store,
            thumbnailService: thumbnailService,
          );
          runtime.playbackSettings = playbackSettings;
          runtime.dataBackupSettings = dataBackupSettings;
          runtime.lastObservedSearchText = runtime.searchController.text;
          runtime.queryController.seed(buildImmediateFilterState(store));
          runtime.facetCountController.seedVisible(
            runtime.facetCountController.fallbackCounts(store.allTagItems),
          );
          runtime.facetCountController.clearStable();
        });
    if (diagnostics == null) {
      applyHydratedState();
    } else {
      diagnostics.measureSync(
        'ui.hydrated_state_prepare',
        applyHydratedState,
      );
      unawaited(applicationService.writeStartupDiagnostics(
        diagnostics: diagnostics,
        totalElapsed: startupWatch.elapsed,
        marker: 'hydrated_state_ready',
      ));
    }
    registerLibraryStressControl(store, thumbnailService);
    // 首帧只消费 SQLite 已恢复的对象和持久化 usageCount；目录扫描与全库计数不得阻塞首屏。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || runtime.store != store) {
        return;
      }
      firstFrameWatch.stop();
      if (diagnostics != null) {
        diagnostics.record(
            'ui.first_frame_build_and_layout', firstFrameWatch.elapsed);
        unawaited(applicationService.writeStartupDiagnostics(
          diagnostics: diagnostics,
          totalElapsed: startupWatch.elapsed,
          marker: 'first_frame_ready',
        ));
      }
      scheduleFilterRefresh();
      scheduleInitialStableTagCounts(store);
      scheduleStartupThumbnailBackfill(store, thumbnailService);
      scheduleStartupMediaDetailsBackfill(store);
      unawaited(() async {
        // 新增发现是用户启动后最直接的反馈，必须先于可能遍历整个媒体库的无效记录
        // 清理执行；否则大库在默认开启自动清理时，会让新增提示长期不可见。
        await promptForNewVideos(store);
        if (playbackSettings.autoRemoveMissingOrUnreadableVideos &&
            mounted &&
            identical(runtime.store, store)) {
          await cleanupMissingOrUnreadableVideos(store);
        }
      }());
    });
  }

  /**
   * 应用启动后自动补齐安全的媒体详情/时长缓存。
   *
   * 任务在缩略图启动窗口之后再登记；媒体详情服务内部仍按 500 项窗口惰性生产，
   * 使用同一个暂停入口、播放器让渡门和 ResourceScheduler，不与首屏争抢资源。
   */
  void scheduleStartupMediaDetailsBackfill(LibraryApplicationFacade store) {
    _startupMediaDetailsBackfillTimer?.cancel();
    _startupMediaDetailsBackfillTimer = Timer(
      _startupMediaDetailsBackfillDelay,
      () {
        _startupMediaDetailsBackfillTimer = null;
        if (!mounted || !identical(runtime.store, store)) {
          return;
        }
        startStartupLibraryMediaDetailsBackfill(store);
      },
    );
  }

  /**
   * 应用启动后自动登记缺失缩略图，但只保留一个页面生命周期内的请求。
   *
   * `ThumbnailService.generateMissing` 使用惰性生产源；这里传入视频视图不会把整库
   * 复制进队列。若扫描预取已经占用后台窗口，请求会在服务内部排队等待而不会丢失。
   */
  void scheduleStartupThumbnailBackfill(
    LibraryApplicationFacade store,
    ThumbnailService thumbnailService,
  ) {
    _startupThumbnailBackfillTimer?.cancel();
    _startupThumbnailBackfillTimer = Timer(
      _startupThumbnailBackfillDelay,
      () {
        _startupThumbnailBackfillTimer = null;
        if (!mounted || !identical(runtime.store, store)) {
          return;
        }
        thumbnailService.generateMissing(store.videos.values);
      },
    );
  }

  /** 串行清理无效数据库记录，完成后统一刷新筛选结果与标签计数。 */
  @override
  Future<int> cleanupMissingOrUnreadableVideos(
    LibraryApplicationFacade store,
  ) {
    final active = runtime.unavailableCleanupFuture;
    if (active != null) {
      return active;
    }
    final videoIdsBeforeCleanup =
        store.videos.values.map((item) => item.videoId).toSet();
    final task = store.removeMissingOrUnreadableVideos();
    runtime.unavailableCleanupFuture = task;
    return task.whenComplete(() {
      if (identical(runtime.unavailableCleanupFuture, task)) {
        runtime.unavailableCleanupFuture = null;
      }
      if (mounted && identical(runtime.store, store)) {
        final removedVideoIds = videoIdsBeforeCleanup.difference(
          store.videos.values.map((item) => item.videoId).toSet(),
        );
        markLibraryDataChanged(
          tagDefinitionsChanged: true,
          removedVideoIds: removedVideoIds.isEmpty ? null : removedVideoIds,
        );
      }
    });
  }

  /**
   * 为显式隔离 profile 注册真实窗口专项压测入口。
   *
   * 环境变量缺失时不注册；回调固定使用同一个 root，防止测试代码把任意路径
   * 传入生产页面。添加仍经过 `scan`，移除仍经过 SQLite 单事务和 UI 差量刷新。
   */
  void registerLibraryStressControl(
    LibraryApplicationFacade store,
    ThumbnailService thumbnailService,
  ) {
    final root = applicationService.stressRoot;
    if (!(kDebugMode || kProfileMode) || root == null || root.isEmpty) {
      return;
    }
    LibraryStressControl.register(
      owner: this,
      addRoot: () async {
        LibraryScanCommitResult? captured;
        await scan((onProgress) async {
          final result = await store.addRootAndScanWithChanges(
            root,
            onProgress: onProgress,
          );
          captured = result;
          return result;
        });
        final result = captured;
        if (result == null || result.cancelled) {
          throw StateError('专项压测添加目录未完成');
        }
        return result;
      },
      removeRoot: () => removeLibraryRootData(root),
      waitForPlayerRelease: () => runtime.latestPlayerRelease,
      snapshot: () {
        final probes = runtime.libraryMediaDetailsService;
        return LibraryStressSnapshot(
          videoCount: store.videos.length,
          visibleCount:
              runtime.queryController.state?.filteredVideos.length ?? 0,
          roots: List<String>.unmodifiable(store.roots),
          thumbnailQueued: thumbnailService.queuedJobs,
          thumbnailActive: thumbnailService.activeJobs,
          probeQueued: probes?.queuedReads ?? 0,
          probeActive: probes?.activeReads ?? 0,
          probeCompleted: probes?.completedThisRun ?? 0,
          probeFailed: probes?.failedThisRun ?? 0,
        );
      },
    );
  }

  /** 在首帧之后的空闲窗口刷新稳定标签计数，过期页面结果会被丢弃。 */
  void scheduleInitialStableTagCounts(LibraryApplicationFacade store) {
    const query = FilterQuery();
    final epoch = countEpoch(query);
    runtime.facetCountController.scheduleStable(
      epoch: epoch,
      query: query,
      compute: store.resultCounts,
      isStillCurrent: (candidate) =>
          mounted && runtime.store == store && candidate == countEpoch(query),
      onAccepted: (candidate, counts) {
        if (!mounted || runtime.store != store || candidate != epoch) {
          return;
        }
        setState(() {});
      },
    );
  }

  Future<void> promptForNewVideos(LibraryApplicationFacade store) async {
    if (store.roots.isEmpty) {
      return;
    }
    final count = await store.countUntrackedVideos();
    if (!mounted || count == 0 || runtime.store != store) {
      return;
    }
    final shouldScan = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('\u53d1\u73b0\u65b0\u589e\u89c6\u9891'),
        content: Text(
            '\u5f53\u524d\u76ee\u5f55\u53d1\u73b0 $count \u4e2a\u672a\u5165\u5e93\u89c6\u9891\uff0c\u662f\u5426\u73b0\u5728\u91cd\u65b0\u626b\u63cf\uff1f'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('\u7a0d\u540e'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('\u91cd\u65b0\u626b\u63cf'),
          ),
        ],
      ),
    );
    if (shouldScan == true && mounted && runtime.store == store) {
      await rescan();
    }
  }
}
