import 'package:flutter/material.dart';

import '../../core/data_backup_settings.dart';
import '../../core/playback_settings.dart';
import '../../core/tag_rules.dart';
import '../../features/library/application/library_continue_watching_command_executor.dart';
import '../../features/library/application/library_facet_count_controller.dart';
import '../../features/library/application/library_file_command_executor.dart';
import '../../features/library/application/library_manual_tag_command_executor.dart';
import '../../features/library/application/library_playback_queue_controller.dart';
import '../../features/library/application/library_query_controller.dart';
import '../../features/library/application/library_revision_tracker.dart';
import '../../features/library/application/library_scan_lifecycle_controller.dart';
import '../../features/library/application/library_selection_controller.dart';
import '../../features/library/application/library_sort_controller.dart';
import '../../features/library/application/library_source_navigation_controller.dart';
import '../../features/library/application/library_view_preferences_controller.dart';
import '../../models/library_scan_models.dart';
import '../../models/library_sort.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../services/library/library_application_facade.dart';
import '../../services/library/library_scan_ui_diagnostics.dart';
import '../../services/library/video_similarity_scan_controller.dart';
import '../../services/media/media_details_service.dart';
import '../../services/media/thumbnail_service.dart';
import '../../services/resources/resource_scheduler.dart';
import '../../services/player/playback_snapshot_write_queue.dart';
import '../../widgets/library/library_local_view.dart';
import '../../features/player/application/player_fullscreen_lifecycle_controller.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 保存媒体库 Route 的可变运行时状态与既有细粒度 controller。
 *
 * 该对象只把历史页面字段集中到一个生命周期容器，不复制筛选、计数、扫描、排序或
 * filtered queue owner；对应状态仍由既有 controller 唯一持有。
 */
class LibraryPageRuntime {
  /** 当前 Route 使用的媒体库 facade；加载完成前为 null。 */
  LibraryApplicationFacade? store;
  /** 播放进度的串行持久化队列；随媒体库加载和页面释放。 */
  PlaybackSnapshotWriteQueue? playbackSnapshotQueue;
  /** 当前媒体库共享的缩略图服务。 */
  ThumbnailService? thumbnailService;
  /** 与扫描、探测、备份和播放让渡门共享的资源预算。 */
  ResourceScheduler? resourceScheduler;
  /** 后台媒体详情补全服务；页面释放时统一取消。 */
  MediaDetailsService? libraryMediaDetailsService;
  /** 媒体库 Route 级相似视频扫描；相似视频页进出只改变前台优先级。 */
  VideoSimilarityScanController? similarityScanController;
  /** 页面与播放器 Route 共享的最新播放设置快照。 */
  PlaybackSettings playbackSettings = PlaybackSettings.defaults;
  /** 自动清理失效记录的复用 Future，防止重复执行。 */
  Future<int>? unavailableCleanupFuture;
  /** 数据备份开关的最新页面快照。 */
  DataBackupSettings dataBackupSettings = DataBackupSettings.defaults;
  /** 筛选、搜索、结果缓存与 latest-only 发布的唯一 owner。 */
  final LibraryQueryController queryController = LibraryQueryController();
  /** 当前候选计数与全库稳定计数的唯一 owner。 */
  final LibraryFacetCountController facetCountController =
      LibraryFacetCountController();
  /** 已接受结果到 filtered playback queue 的唯一转换 owner。 */
  final LibraryPlaybackQueueController playbackQueueController =
      LibraryPlaybackQueueController();
  /** 定位、改名与删除的平台/Repository 编排命令执行器。 */
  final LibraryFileCommandExecutor fileCommandExecutor =
      const LibraryFileCommandExecutor();
  /** 单视频 manual 标签替换与失败回滚命令执行器。 */
  final LibraryManualTagCommandExecutor manualTagCommandExecutor =
      const LibraryManualTagCommandExecutor();
  /** 扫描、路径检查与扫描后解析状态的 latest-only 生命周期 owner。 */
  final LibraryScanLifecycleController<MediaDetailsProgress>
      scanLifecycleController =
      LibraryScanLifecycleController<MediaDetailsProgress>();
  /** 搜索输入的稳定 controller；真实键盘和程序修改共用同一链路。 */
  final TextEditingController searchController = TextEditingController();
  /** Ctrl+K 与点击搜索入口共用的焦点节点。 */
  final FocusNode searchFocusNode =
      FocusNode(debugLabel: 'library-search-field');
  /** 兼容一级 folder 标签的当前选择。 */
  final Set<String> selectedTags = <String>{};
  /** 当前一级标签下选择的二级 folder 标签。 */
  final Set<String> selectedChildTags = <String>{};
  /** 按 TagGroup 保存的包含筛选 tagId。 */
  final Map<String, Set<String>> selectedGroupTagIds = <String, Set<String>>{};
  /** 当前排除筛选的 tagId。 */
  final Set<String> excludedTagIds = <String>{};

  /** 播放时间变化使用的轻量修订号，不冒充标签定义变化。 */
  int playbackDataRevision = 0;
  /** 程序化清空输入时抑制一次 controller 重复回调。 */
  bool suppressSearchControllerChange = false;
  /** 搜索 controller 变化已排入微任务，防止同帧重复调度。 */
  bool searchControllerChangeQueued = false;
  /** 上次已处理的搜索文本，用于丢弃无变化通知。 */
  String lastObservedSearchText = '';
  /** 播放器 Route 内是否发生需要返回后刷新的媒体库变化。 */
  bool playerScopedLibraryDataChanged = false;
  /** 播放器 Route 返回后是否需要刷新标签计数。 */
  bool playerScopedNeedsCountRefresh = false;
  /** 播放器 Route 内是否发生标签定义变化。 */
  bool playerScopedTagDefinitionsChanged = false;
  /** 播放器 Route 内已删除的 stable videoId，返回媒体库时只移除对应列表项。 */
  final Set<String> playerScopedRemovedVideoIds = <String>{};
  /** 下一次列表结果发布需要保留滚动位置的 stable videoId 差量。 */
  final Set<String> pendingResultDeltaVideoIds = <String>{};
  /** 尚未完成列表发布的删除 stable ID，合并连续删除避免旧项重新出现在缓存结果。 */
  final Set<String> pendingRemovedVideoIds = <String>{};
  /** 防止同一差量在多次 build 中重复安排清理回调。 */
  bool resultDeltaClearScheduled = false;
  /** 最近一次播放器原生资源完全释放的完成信号。 */
  Future<void> latestPlayerRelease = Future<void>.value();
  /** 播放器 Route 活跃时排除底层媒体库语义树。 */
  bool playerRouteActive = false;
  /** 播放器 Route 之间复用的全屏窗口会话 owner。 */
  final PlayerFullscreenSessionController playerFullscreenSession =
      PlayerFullscreenSessionController();
  /** 当前结果查询是否仍在刷新。 */
  bool isRefreshingVideos = false;
  /** 当前延后标签计数是否仍在刷新。 */
  bool isRefreshingCounts = false;

  /** 结果数据与标签定义的独立修订 owner。 */
  final LibraryRevisionTracker libraryRevisionTracker =
      LibraryRevisionTracker();
  /** 是否叠加本地收藏筛选。 */
  bool showFavoritesOnly = false;
  /** 当前扫描的 UI 诊断记录器；新扫描会替换旧实例。 */
  LibraryScanUiDiagnostics? activeScanUiDiagnostics;
  /** 排序字段、方向和稳定指纹的唯一 owner。 */
  final LibrarySortController sortController = LibrarySortController();
  /** 网格密度与左右面板显隐的唯一 owner。 */
  final LibraryViewPreferencesController viewPreferences =
      LibraryViewPreferencesController(
    denseResultGrid: false,
    mainSidebarCollapsed: true,
    tagDiscoveryPanelOpen: false,
  );
  /** 滚动结果区域是否展示顶部工具栏。 */
  final ValueNotifier<bool> libraryHeaderVisible = ValueNotifier<bool>(true);
  /** 结果来源、本地路径和返回栈的唯一 owner。 */
  final LibrarySourceNavigationController sourceNavigation =
      LibrarySourceNavigationController(
    normalizePath: TagRules.normalizeRootPath,
    pathKey: TagRules.pathKey,
  );

  /** 最近播放派生缓存的输入身份。 */
  Object? recentVideoCacheKey;
  /** 收藏结果派生缓存的输入身份。 */
  Object? favoriteVideoCacheKey;
  /** 当前本地目录条目缓存的输入身份。 */
  Object? localEntryCacheKey;
  /** 侧栏标签分组缓存的输入身份。 */
  Object? tagGroupsCacheKey;
  /** 已按当前排序生成的最近播放快照。 */
  List<VideoItem> recentVideoCache = const <VideoItem>[];
  /** 已按当前排序生成的收藏快照。 */
  List<VideoItem> favoriteVideoCache = const <VideoItem>[];
  /** 当前本地目录的只读条目快照。 */
  List<LocalLibraryEntry> localEntryCache = const <LocalLibraryEntry>[];
  /** 不同路径身份对应的本地目录快照，避免返回时重复枚举。 */
  final Map<Object, List<LocalLibraryEntry>> localEntryCacheByKey =
      <Object, List<LocalLibraryEntry>>{};
  /** 正在读取的本地目录身份，防止同一路径重复启动任务。 */
  final Set<Object> localEntryLoads = <Object>{};
  /** 当前 Store 修订下的侧栏标签分组快照。 */
  List<TagGroup> tagGroupsCache = const <TagGroup>[];

  /** 继续观看区域按 stable videoId 保存的临时选择。 */
  final LibrarySelectionController recentPlaybackSelection =
      LibrarySelectionController();
  /** 继续观看清理与撤销的显式补偿命令执行器。 */
  final LibraryContinueWatchingCommandExecutor continueWatchingCommands =
      const LibraryContinueWatchingCommandExecutor();
  /** 媒体结果区域按 stable videoId 保存的批量选择。 */
  final LibrarySelectionController librarySelection =
      LibrarySelectionController();

  /** 当前媒体数据修订号。 */
  int get libraryDataRevision => libraryRevisionTracker.dataRevision;
  /** 当前标签定义修订号。 */
  int get tagDefinitionRevision => libraryRevisionTracker.tagDefinitionRevision;
  /** 扫描生命周期是否处于活动状态。 */
  bool get isScanning => scanLifecycleController.state.isScanning;
  /** 当前扫描是否正在执行取消。 */
  bool get isCancellingScan => scanLifecycleController.state.isCancelling;
  /** 当前扫描进度快照。 */
  LibraryScanProgress? get scanProgress =>
      scanLifecycleController.state.scanProgress;
  /** 当前媒体详情导入进度快照。 */
  MediaDetailsProgress? get mediaImportProgress =>
      scanLifecycleController.state.mediaImportProgress;
  /** 当前排序字段。 */
  SortMode get sortMode => sortController.mode;
  /** 当前排序方向。 */
  SortDirection get sortDirection => sortController.direction;
  /** 是否使用紧凑结果网格。 */
  bool get denseResultGrid => viewPreferences.denseResultGrid;
  /** 主侧栏是否折叠。 */
  bool get isMainSidebarCollapsed => viewPreferences.mainSidebarCollapsed;
  /** 当前媒体库展示偏好快照；排序和布局持久化共用这一值对象。 */
  LibrarySortPreferences get libraryDisplayPreferences =>
      LibrarySortPreferences(
        mode: sortMode,
        direction: sortDirection,
        denseResultGrid: denseResultGrid,
        mainSidebarCollapsed: isMainSidebarCollapsed,
      );
  /** 标签发现面板是否展开。 */
  bool get isTagDiscoveryPanelOpen => viewPreferences.tagDiscoveryPanelOpen;
  /** 当前结果来源模式。 */
  LibraryResultMode get resultMode => sourceNavigation.mode;
  /** 当前浏览的本地目录路径。 */
  String? get localLibraryPath => sourceNavigation.localPath;
  /** 媒体结果是否处于批量选择模式。 */
  bool get librarySelectionMode => librarySelection.selectionMode;
  /** 当前已选 stable videoId 的只读视图。 */
  Set<String> get selectedLibraryVideoIds => librarySelection.selectedVideoIds;
}
