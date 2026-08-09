import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/layout_size.dart';
import '../../core/tag_rules.dart';
import '../../features/update/domain/app_update_service.dart';
import '../../features/library/application/library_source_navigation_controller.dart';
import '../../features/library/presentation/library_queue_title.dart';
import '../../features/library/presentation/library_scan_progress_labels.dart';
import '../../models/video_item.dart';
import '../../platform/file_system_adapter.dart';
import '../../platform/platform_interfaces.dart';
import '../../services/library/library_page_application_service.dart';
import '../../services/player/player_service.dart';
import '../../widgets/app_theme_tokens.dart';
import '../../widgets/library/library_local_view.dart';
import '../../widgets/library/library_panel_content_transition.dart';
import '../../widgets/library/library_sidebar.dart';
import '../../widgets/library/library_smoke_keys.dart';
import '../../widgets/library/library_tag_discovery_panel.dart';
import '../../widgets/library/library_tag_display_helpers.dart';
import '../../widgets/library/library_video_results.dart';
import '../../widgets/library/library_widgets.dart';
import '../../widgets/library/library_recent_playback_view.dart';
import 'library_page_state_host.dart';
import 'library_page_lifecycle_mixin.dart';
import 'library_page_scan_mixin.dart';
import 'library_page_navigation_mixin.dart';
import 'library_page_recent_mixin.dart';
import 'library_page_query_mixin.dart';
import 'library_page_filter_mixin.dart';
import 'library_page_routes_mixin.dart';
import 'library_page_playback_mixin.dart';
import 'library_page_commands_mixin.dart';

export 'cache_settings_page.dart'
    show CacheSettingsPage, playerShortcutConflictMessage;

/** 标签筛选默认保持折叠，把媒体结果宽度优先留给高频浏览。 */
const bool libraryTagDiscoveryPanelInitiallyOpen = false;
/** 计算筛选动作后的面板状态；只有真实标签选择要求自动收起。 */
bool libraryTagDiscoveryPanelOpenAfterMutation({
  required bool currentOpen,
  required bool collapseAfterMutation,
}) =>
    collapseAfterMutation ? false : currentOpen;

/** 播放器 Route 挂载期间排除媒体库语义，防止 Windows UIA 保留旧页面节点。 */
@visibleForTesting
bool libraryRouteShouldExcludeSemantics({required bool playerRouteActive}) {
  return playerRouteActive;
}

// ignore_for_file: slash_for_doc_comments

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.applicationService,
    required this.fileSystem,
    required this.playerServiceFactory,
    required this.mediaProbeBackendFactory,
    required this.updateService,
  });

  /** facade 加载、偏好持久化、缩略图与媒体详情创建的页面应用服务。 */
  final LibraryPageApplicationService applicationService;
  /** 目录选择、异步枚举、文件检查和删除的平台边界。 */
  final FileSystemAdapter fileSystem;
  /** 仅转交播放器页面的应用层播放服务工厂。 */
  final PlayerServiceFactory playerServiceFactory;
  /** 仅转交播放器页面的媒体探测工厂。 */
  final MediaProbeBackendFactory mediaProbeBackendFactory;
  /** 应用组合根注入的更新服务；页面不创建网络或平台具体实现。 */
  final AppUpdateService updateService;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

/**
 * 选择添加目录或文件时使用的媒体上下文起点。
 *
 * 当前正在浏览的本地目录优先，其次使用首个已管理 root；两者都不存在时返回 null，
 * 由平台选择器决定默认位置，避免回到与视频无关的系统“图片”目录。
 */
@visibleForTesting
String? preferredLibraryPickerDirectory({
  required String? currentPath,
  required List<String> roots,
}) {
  final current = currentPath?.trim();
  if (current != null && current.isNotEmpty) {
    return current;
  }
  return roots.isEmpty ? null : roots.first;
}

class _LibraryPageState extends LibraryPageStateHost<LibraryPage>
    with
        LibraryPageLifecycleMixin<LibraryPage>,
        LibraryPageScanMixin<LibraryPage>,
        LibraryPageNavigationMixin<LibraryPage>,
        LibraryPageRecentMixin<LibraryPage>,
        LibraryPageQueryMixin<LibraryPage>,
        LibraryPageFilterMixin<LibraryPage>,
        LibraryPageRoutesMixin<LibraryPage>,
        LibraryPagePlaybackMixin<LibraryPage>,
        LibraryPageCommandsMixin<LibraryPage> {
  @override
  LibraryPageApplicationService get applicationService =>
      (widget).applicationService;

  @override
  FileSystemAdapter get fileSystem => (widget).fileSystem;

  @override
  PlayerServiceFactory get playerServiceFactory =>
      (widget).playerServiceFactory;

  @override
  MediaProbeBackendFactory get mediaProbeBackendFactory =>
      (widget).mediaProbeBackendFactory;

  @override
  AppUpdateService get updateService => (widget).updateService;

  @override
  Widget build(BuildContext context) {
    final store = runtime.store;
    final thumbnailService = runtime.thumbnailService;
    if (store == null || thumbnailService == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final filterState =
        runtime.queryController.state ?? buildImmediateFilterState(store);
    final filteredVideos = filterState.filteredVideos;
    final recentVideos = sortedRecentVideos(store);
    final favoriteVideos = sortedFavoriteVideos(store);
    final videos = switch (runtime.resultMode) {
      LibraryResultMode.recent => recentVideos,
      LibraryResultMode.favorites => favoriteVideos,
      LibraryResultMode.local => const <VideoItem>[],
      LibraryResultMode.library => filteredVideos,
    };
    final localEntries = runtime.resultMode == LibraryResultMode.local
        ? cachedLocalLibraryEntries(store)
        : const <LocalLibraryEntry>[];
    final localVideos = <VideoItem>[
      for (final entry in localEntries)
        if (entry.video != null) entry.video!,
    ];
    final localVideoCount = localVideos.length;
    final displayedQueueVideos =
        runtime.resultMode == LibraryResultMode.local ? localVideos : videos;
    final playbackBinding = bindDisplayedPlaybackResult(
      controller: runtime.playbackQueueController,
      sourceName: runtime.resultMode.name,
      acceptedLibraryEpoch: filterState.epoch,
      displayedVideos: displayedQueueVideos,
      totalCount: store.videos.length,
      dataRevision: runtime.libraryDataRevision,
      playbackDataRevision: runtime.playbackDataRevision,
      sortFingerprint: runtime.sortController.fingerprint,
      localPath: runtime.localLibraryPath,
      libraryTitle: filterSummary(
        store: store,
        resultCount: displayedQueueVideos.length,
        totalCount: store.videos.length,
      ),
    );
    void openAcceptedVideo(VideoItem item, List<VideoItem> playlist) =>
        unawaited(
          openVideo(
            item,
            playlist,
            playbackBinding.result,
            playbackBinding.queueTitle,
          ),
        );
    final displayResultCount = switch (runtime.resultMode) {
      LibraryResultMode.recent => videos.length,
      LibraryResultMode.favorites => videos.length,
      LibraryResultMode.local => localVideoCount,
      LibraryResultMode.library => filterState.resultCount,
    };
    final resultCountLabel = runtime.resultMode == LibraryResultMode.local
        ? localLibraryEntrySummary(localEntries)
        : null;
    final defaultResultLabel = switch (runtime.resultMode) {
      LibraryResultMode.recent => '继续观看',
      LibraryResultMode.favorites => '\u672c\u5730\u6536\u85cf',
      LibraryResultMode.local => '\u672c\u5730\u5a92\u4f53\u5e93',
      LibraryResultMode.library => '\u5168\u90e8\u89c6\u9891',
    };
    final tags = store.allTags.toList()..sort();
    final tagGroups = tagGroupsForSidebar(store);
    final resultCounts = runtime.facetCountController.visibleCounts.isEmpty
        ? runtime.facetCountController.fallbackCounts(store.allTagItems)
        : runtime.facetCountController.visibleCounts;
    final pathDerivedTagCounts = {
      for (final group in tagGroups)
        if (group.id == 'folder.primary' || group.id == 'folder.child')
          for (final tag in group.items) tag.id: tag.usageCount,
    };
    final stableTagCounts = {
      ...(runtime.facetCountController.stableCounts.isEmpty
          ? runtime.facetCountController.fallbackCounts(store.allTagItems)
          : runtime.facetCountController.stableCounts),
      ...pathDerivedTagCounts,
    };
    final selectedGroupTags = selectedGroupTagItems(store);
    final excludedTags = excludedTagItems(store);
    final supportsLibrarySelection =
        (runtime.resultMode == LibraryResultMode.library ||
                runtime.resultMode == LibraryResultMode.favorites) &&
            videos.isNotEmpty;
    final allLibraryVideosSelected = videos.isNotEmpty &&
        runtime.selectedLibraryVideoIds.length == videos.length;
    final childParentTag = activeChildParentTag;
    final childTags = childParentTag == null
        ? <String>[]
        : TagRules.sortedChildTags(store.childTagsFor(childParentTag))
            .where((tag) =>
                !TagRules.sameTag(tag, TagRules.defaultAlbumTag) &&
                !TagRules.sameTag(tag, childParentTag))
            .toList();
    final childTagItemsByParent = childTagItemsByParentId(
      tagGroups.expand((group) => group.items),
      store.tagQueryContext,
    );
    final favoriteCount =
        store.videos.values.where((item) => item.isFavorite).length;
    final missingCount =
        store.videos.values.where((item) => item.isMissing).length;
    Widget buildSidebar({required bool dense, double? width}) {
      return LibrarySidebar(
        roots: store.roots,
        tags: tags,
        tagGroups: tagGroups,
        resultCounts: resultCounts,
        selectedLocalLibraryPath: runtime.localLibraryPath,
        childParentTag: childParentTag,
        childTags: childTags,
        selectedChildTags: runtime.selectedChildTags,
        selectedGroupTagIds: runtime.selectedGroupTagIds,
        excludedTagIds: runtime.excludedTagIds,
        favoriteCount: favoriteCount,
        missingCount: missingCount,
        favoriteVideosSelected:
            runtime.resultMode == LibraryResultMode.favorites ||
                runtime.showFavoritesOnly,
        recentPlaybackSelected: runtime.resultMode == LibraryResultMode.recent,
        localLibrarySelected: runtime.resultMode == LibraryResultMode.local,
        selectedTags: runtime.selectedTags,
        isScanning: runtime.isScanning,
        dense: dense,
        collapsed: runtime.isMainSidebarCollapsed,
        width: width,
        onToggleCollapsed: () =>
            setState(runtime.viewPreferences.toggleMainSidebar),
        onPickFolder: pickFolder,
        onShowAllLibrary: showAllLibraryVideos,
        onRescan: rescan,
        onRemoveLocalLibraryRoot: removeLocalLibraryRoot,
        onFavoritesToggle: showFavoriteVideos,
        onOpenRecentPlayback: showRecentPlaybackVideos,
        onOpenLocalLibraryRoot: showLocalLibraryPath,
        onOpenDirectoryManager: openDirectoryManager,
        onOpenMissingRelink: openMissingRelink,
        onOpenTagManager: () => openTagManager(videos),
        onOpenSettings: openSettings,
        onChildTagToggle: (tag) {
          mutateFilters(() {
            removeEquivalentGroupSelection(
              tagName: tag,
              parentTag: activeChildParentTag,
            );
            toggleSingleSelection(runtime.selectedChildTags, tag);
          }, collapseTagPanel: true);
        },
        onClearChildTags: () => mutateFilters(runtime.selectedChildTags.clear),
        onGroupTagToggle: toggleGroupTag,
        onGroupTagExcludeToggle: toggleExcludedTag,
      );
    }

    Widget buildFilterPanel({required bool dense, double? panelWidth}) {
      return TagDiscoveryZone(
        tagGroups: tagGroups,
        resultCounts: stableTagCounts,
        favoriteTags: store.favoriteTags,
        selectedTags: runtime.selectedTags,
        selectedChildTags: runtime.selectedChildTags,
        selectedGroupTagIds: runtime.selectedGroupTagIds,
        excludedTagIds: runtime.excludedTagIds,
        childParentTag: childParentTag,
        childTags: childTags,
        childTagItemsByParent: childTagItemsByParent,
        favoriteCount: favoriteCount,
        showFavoritesOnly: runtime.showFavoritesOnly,
        dense: dense,
        panelWidth: panelWidth,
        onFavoritesToggle: () => mutateFilters(
          () => runtime.showFavoritesOnly = !runtime.showFavoritesOnly,
          collapseTagPanel: true,
        ),
        onTagToggle: (tag) {
          mutateFilters(() {
            removeEquivalentGroupSelection(tagName: tag);
            toggleSingleSelection(runtime.selectedTags, tag);
            runtime.selectedChildTags.clear();
          }, collapseTagPanel: true);
        },
        onChildTagToggle: (tag) {
          mutateFilters(() {
            removeEquivalentGroupSelection(
              tagName: tag,
              parentTag: activeChildParentTag,
            );
            toggleSingleSelection(runtime.selectedChildTags, tag);
          }, collapseTagPanel: true);
        },
        onGroupTagToggle: toggleGroupTag,
        onFolderPrimaryChildSelected: selectFolderPrimaryChild,
        onGroupTagExcludeToggle: toggleExcludedTag,
        onCollapse: dense
            ? null
            : () => setState(
                  () => runtime.viewPreferences.setTagDiscoveryPanelOpen(false),
                ),
      );
    }

    Widget buildMain(
      LayoutSize layoutSize, {
      Widget? topBar,
      required double gridColumnReferenceWidth,
    }) {
      return Column(
        children: [
          if (topBar != null) topBar,
          Expanded(
            child: LibraryImportDropRegion(
              enabled: runtime.resultMode == LibraryResultMode.library &&
                  !runtime.isScanning,
              onDropPaths: (paths) => unawaited(importLibraryPaths(paths)),
              child: RepaintBoundary(
                child: switch (runtime.resultMode) {
                  LibraryResultMode.local => LocalLibraryView(
                      currentPath: runtime.localLibraryPath,
                      entries: localEntries,
                      thumbnailService: thumbnailService,
                      playbackSettings: runtime.playbackSettings,
                      dense: runtime.denseResultGrid,
                      canGoBack: runtime.sourceNavigation.canGoBack,
                      onBack: goBackLocalLibraryPath,
                      onOpenFolder: openLocalLibraryFolder,
                      onOpenVideo: openAcceptedVideo,
                      onRevealLocation: revealVideoLocation,
                      onToggleFavorite: toggleFavorite,
                      onDelete: requestDeleteVideo,
                    ),
                  LibraryResultMode.recent => videos.isEmpty
                      ? EmptyState(
                          hasLibrary: store.videos.isNotEmpty,
                          message: '当前没有未完成的观看记录',
                        )
                      : RecentPlaybackView(
                          videos: videos,
                          selectedVideoIds:
                              runtime.recentPlaybackSelection.selectedVideoIds,
                          thumbnailService: thumbnailService,
                          playbackSettings: runtime.playbackSettings,
                          dense: runtime.denseResultGrid,
                          onOpen: openAcceptedVideo,
                          onRevealLocation: revealVideoLocation,
                          onToggleFavorite: toggleFavorite,
                          onDeleteVideo: requestDeleteVideo,
                          onToggleSelected: toggleRecentSelection,
                          onSelectAll: () => setState(() {
                            runtime.recentPlaybackSelection.toggleAll(
                              videos.map((item) => item.videoId),
                            );
                          }),
                          onClearSelection: () =>
                              setState(runtime.recentPlaybackSelection.clear),
                          onDeleteOne: clearOneRecentPlayback,
                          onDeleteSelected: () =>
                              clearRecentPlayback(selectedOnly: true),
                          onDeleteAll: () =>
                              clearRecentPlayback(selectedOnly: false),
                        ),
                  _ => videos.isEmpty
                      ? EmptyState(
                          hasLibrary: store.videos.isNotEmpty,
                          message:
                              runtime.resultMode == LibraryResultMode.favorites
                                  ? '\u8fd8\u6ca1\u6709\u6536\u85cf\u89c6\u9891'
                                  : null,
                          onAddFiles:
                              runtime.resultMode == LibraryResultMode.library &&
                                      store.videos.isEmpty
                                  ? pickVideoFiles
                                  : null,
                        )
                      : VideoGrid(
                          videos: videos,
                          thumbnailService: thumbnailService,
                          playbackSettings: runtime.playbackSettings,
                          dense: runtime.denseResultGrid,
                          columnReferenceWidth: gridColumnReferenceWidth,
                          onVisible: prioritizeVisibleLibraryItem,
                          onOpen: openAcceptedVideo,
                          onRevealLocation: revealVideoLocation,
                          onToggleFavorite: toggleFavorite,
                          onDelete: requestDeleteVideo,
                          selectionMode: runtime.librarySelectionMode,
                          selectedVideoIds: runtime.selectedLibraryVideoIds,
                          onToggleSelected: (item) => setState(
                            () => runtime.librarySelection.toggle(item.videoId),
                          ),
                          scrollChromeEnabled:
                              layoutSize == LayoutSize.expanded,
                          onHeaderVisibilityChanged: (visible) {
                            if (runtime.libraryHeaderVisible.value != visible) {
                              runtime.libraryHeaderVisible.value = visible;
                            }
                          },
                        ),
                },
              ),
            ),
          ),
        ],
      );
    }

    Widget buildTopBar(LayoutSize layoutSize) {
      return ReferenceTopBar(
        controller: runtime.searchController,
        videoCount: displayResultCount,
        resultCountLabel: resultCountLabel,
        keyword: runtime.searchController.text,
        searchFocusNode: runtime.searchFocusNode,
        selectedTags: runtime.selectedTags.toList()..sort(),
        selectedChildTags: runtime.selectedChildTags.toList()..sort(),
        selectedGroupTags: selectedGroupTags,
        excludedTags: excludedTags,
        defaultChipLabel: defaultResultLabel,
        showFavoritesOnly: runtime.showFavoritesOnly,
        refreshing: runtime.isRefreshingVideos || runtime.isRefreshingCounts,
        progressLabel: runtime.resultMode != LibraryResultMode.library
            ? null
            : runtime.isScanning
                ? runtime.isCancellingScan
                    ? '正在取消扫描…'
                    : libraryScanProgressLabel(runtime.scanProgress)
                : runtime.mediaImportProgress == null
                    ? null
                    : libraryMediaImportProgressLabel(
                        runtime.mediaImportProgress!,
                      ),
        progressValue: runtime.resultMode != LibraryResultMode.library
            ? null
            : runtime.isScanning
                ? runtime.scanProgress?.fraction
                : runtime.mediaImportProgress?.fraction,
        progressPaused: runtime.isScanning
            ? (runtime.scanProgress?.isPaused ?? false)
            : (runtime.mediaImportProgress?.isPaused ?? false),
        onToggleProgressPaused: runtime.resultMode != LibraryResultMode.library
            ? null
            : runtime.isScanning
                ? (runtime.scanProgress == null ? null : toggleScanPaused)
                : runtime.mediaImportProgress == null
                    ? null
                    : toggleMediaImportPaused,
        onCancelProgress: runtime.resultMode == LibraryResultMode.library &&
                runtime.isScanning &&
                !runtime.isCancellingScan
            ? cancelScan
            : null,
        sortMode: runtime.sortMode,
        sortDirection: runtime.sortDirection,
        layoutSize: layoutSize,
        hasActiveFilters: hasActiveFilters,
        onSearchChanged: (_) => handleSearchControllerChanged(),
        onSortChanged: (mode) => applySortChange(sortMode: mode),
        onSortDirectionToggle: toggleSortDirection,
        denseResultGrid: runtime.denseResultGrid,
        onResultViewChanged: setResultView,
        onOpenTagManager: () => openTagManager(videos),
        tagPanelOpen: runtime.isTagDiscoveryPanelOpen,
        onToggleTagPanel: layoutSize == LayoutSize.expanded
            ? () => setState(runtime.viewPreferences.toggleTagDiscoveryPanel)
            : null,
        onRemovePrimaryTag: (tag) => mutateFilters(() {
          runtime.selectedTags.remove(tag);
          runtime.selectedChildTags.clear();
        }),
        onRemoveChildTag: (tag) =>
            mutateFilters(() => runtime.selectedChildTags.remove(tag)),
        onRemoveGroupTag: removeGroupTag,
        onRemoveExcludedTag: removeExcludedTag,
        onClearKeyword: () => mutateFilters(clearSearchSilently),
        onClearFavoritesOnly: () =>
            mutateFilters(() => runtime.showFavoritesOnly = false),
        onClearAll: hasActiveFilters ? clearAllFilters : null,
        selectionMode: runtime.librarySelectionMode,
        selectedCount: runtime.selectedLibraryVideoIds.length,
        allSelected: allLibraryVideosSelected,
        onEnterSelectionMode: supportsLibrarySelection
            ? () => setState(runtime.librarySelection.enter)
            : null,
        onToggleSelectAll: runtime.librarySelectionMode
            ? () => setState(
                  () => runtime.librarySelection.toggleAll(
                    videos.map((item) => item.videoId),
                  ),
                )
            : null,
        onDeleteSelected: runtime.librarySelectionMode &&
                runtime.selectedLibraryVideoIds.isNotEmpty
            ? () => requestDeleteSelectedVideos(videos)
            : null,
        onCancelSelectionMode: runtime.librarySelectionMode
            ? () => setState(runtime.librarySelection.clear)
            : null,
        onOpenFilters: () {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: librarySurface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            builder: (_) => FractionallySizedBox(
              heightFactor: 0.92,
              child: buildFilterPanel(dense: true),
            ),
          );
        },
      );
    }

    Widget buildExpandedContent(
      MainLibraryLayoutSlots layoutSlots, {
      required double gridColumnReferenceWidth,
    }) {
      // 收起后完全释放右侧空间；恢复入口已经提升到页面标题区，避免保留突兀的竖排窄条。
      const collapsedFilterWidth = 0.0;
      final accessibility = AppAccessibilityScope.of(context);
      final panelDuration =
          accessibility.motionDuration(libraryPanelMotionDuration);
      return Column(
        children: [
          LibraryScrollResponsiveHeader(
            key: LibrarySmokeKeys.scrollResponsiveHeader,
            visibleListenable: runtime.libraryHeaderVisible,
            child: buildTopBar(LayoutSize.expanded),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: buildMain(
                    LayoutSize.expanded,
                    gridColumnReferenceWidth: gridColumnReferenceWidth,
                  ),
                ),
                AnimatedContainer(
                  duration: panelDuration,
                  curve: libraryPanelMotionCurve,
                  width: runtime.isTagDiscoveryPanelOpen
                      ? layoutSlots.filterPanelWidth
                      : collapsedFilterWidth,
                  // 外框只承担稳定分隔；面板和折叠入口各自表达层级，避免出现双重阴影。
                  decoration: runtime.isTagDiscoveryPanelOpen
                      ? BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: libraryBorder.withValues(alpha: 0.72),
                            ),
                          ),
                        )
                      : null,
                  child: ClipRect(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final childWidth = runtime.isTagDiscoveryPanelOpen
                            ? layoutSlots.filterPanelWidth
                            : collapsedFilterWidth;
                        return AnimatedSwitcher(
                          duration: panelDuration,
                          switchInCurve: libraryPanelMotionCurve,
                          switchOutCurve: libraryPanelMotionCurve,
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                            alignment: Alignment.centerRight,
                            clipBehavior: Clip.hardEdge,
                            children: [
                              ...previousChildren,
                              if (currentChild != null) currentChild,
                            ],
                          ),
                          transitionBuilder: (child, animation) {
                            final enteringPanel =
                                child.key == const ValueKey<bool>(true);
                            return LibraryPanelContentTransition(
                              animation: animation,
                              horizontalOffset: enteringPanel ? 0.14 : 0.55,
                              alignment: Alignment.centerRight,
                              child: child,
                            );
                          },
                          child: OverflowBox(
                            key:
                                ValueKey<bool>(runtime.isTagDiscoveryPanelOpen),
                            alignment: Alignment.centerRight,
                            minWidth: childWidth,
                            maxWidth: childWidth,
                            minHeight: constraints.maxHeight,
                            maxHeight: constraints.maxHeight,
                            child: SizedBox(
                              width: childWidth,
                              height: constraints.maxHeight,
                              child: runtime.isTagDiscoveryPanelOpen
                                  ? buildFilterPanel(
                                      dense: false,
                                      panelWidth: layoutSlots.filterPanelWidth,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final page = Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            const FocusLibrarySearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          FocusLibrarySearchIntent: CallbackAction<FocusLibrarySearchIntent>(
            onInvoke: (_) {
              focusSearchField();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Theme(
            data: libraryWorkspaceTheme(Theme.of(context)),
            child: Scaffold(
              backgroundColor: libraryBackground,
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final layoutSize =
                      LayoutBreakpoints.fromWidth(constraints.maxWidth);
                  final showMainSidebar = layoutSize != LayoutSize.compact;
                  final expandedSlots =
                      mainLibraryLayoutSlotsForWidth(constraints.maxWidth);
                  // 列数使用默认侧栏占位后的窗口基准宽度。左右侧栏开合不会改变该值，
                  // 因此只会让结果区里的卡片缩放；只有窗口尺寸改变才可能跨越列数断点。
                  final gridColumnReferenceWidth = (switch (layoutSize) {
                    LayoutSize.compact => constraints.maxWidth,
                    LayoutSize.medium => constraints.maxWidth - 248,
                    LayoutSize.expanded =>
                      constraints.maxWidth - expandedSlots.sidebarWidth,
                  })
                      .clamp(1.0, double.infinity)
                      .toDouble();
                  return Row(
                    children: [
                      if (showMainSidebar)
                        buildSidebar(
                          dense: layoutSize != LayoutSize.expanded,
                          width: runtime.isMainSidebarCollapsed
                              ? 76
                              : layoutSize == LayoutSize.expanded
                                  ? expandedSlots.sidebarWidth
                                  : null,
                        ),
                      Expanded(
                        child: layoutSize == LayoutSize.expanded
                            ? buildExpandedContent(
                                expandedSlots,
                                gridColumnReferenceWidth:
                                    gridColumnReferenceWidth,
                              )
                            : buildMain(
                                layoutSize,
                                topBar: buildTopBar(layoutSize),
                                gridColumnReferenceWidth:
                                    gridColumnReferenceWidth,
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    return ExcludeSemantics(
      excluding: libraryRouteShouldExcludeSemantics(
        playerRouteActive: runtime.playerRouteActive,
      ),
      child: page,
    );
  }
}
