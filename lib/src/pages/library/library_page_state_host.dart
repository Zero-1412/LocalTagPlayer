import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/library/domain/library_query_snapshot.dart';
import '../../features/library/domain/tag_editor_candidates.dart';
import '../../features/update/domain/app_update_service.dart';
import '../../models/library_scan_models.dart';
import '../../models/library_sort.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../platform/file_system_adapter.dart';
import '../../platform/platform_interfaces.dart';
import '../../services/library/library_application_facade.dart';
import '../../services/library/library_page_application_service.dart';
import '../../services/player/player_service.dart';
import '../../services/tags/tag_query_service.dart';
import '../../widgets/app_theme_tokens.dart';
import '../../widgets/library/library_local_view.dart';
import '../../widgets/player_shortcut_input.dart';
import 'library_page_runtime.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 页面协调 mixin 的最小宿主。
 *
 * 宿主只暴露组合根已经注入的边界和一个 Route 级运行时容器；具体方法由职责互斥的
 * mixin 实现，避免任何协调文件重新创建 Store、PlayerBackend 或缓存 owner。
 */
abstract class LibraryPageStateHost<T extends StatefulWidget> extends State<T> {
  /** 当前媒体库 Route 的运行时状态。 */
  final LibraryPageRuntime runtime = LibraryPageRuntime();

  /** facade、设置与媒体服务的页面应用边界。 */
  LibraryPageApplicationService get applicationService;
  /** 文件选择、枚举、检查与文件动作的平台边界。 */
  FileSystemAdapter get fileSystem;
  /** 播放器 Route 使用的播放服务工厂。 */
  PlayerServiceFactory get playerServiceFactory;
  /** 播放前媒体探测工厂。 */
  MediaProbeBackendFactory get mediaProbeBackendFactory;
  /** 设置/关于页使用的更新服务边界。 */
  AppUpdateService get updateService;

  /** 构建同步首帧使用的筛选结果，正式刷新仍走 query owner。 */
  FilterState buildImmediateFilterState(LibraryApplicationFacade store);

  /** 记录数据修订并按既有规则刷新可见结果与计数。 */
  void markLibraryDataChanged({bool tagDefinitionsChanged = false});

  /** 当前二级 folder 标签所属一级标签。 */
  String? get activeChildParentTag;

  /** 统一改变筛选并触发已有 latest-only 刷新链。 */
  void mutateFilters(
    VoidCallback mutation, {
    bool refreshCounts = false,
    bool collapseTagPanel = false,
  });

  /** 返回当前媒体库可展示的标签分组快照。 */
  List<TagGroup> tagGroupsForSidebar(LibraryApplicationFacade store);

  /** 静默清空搜索框，避免 controller listener 重复调度。 */
  void clearSearchSilently();

  /** 构建用户可见的筛选摘要。 */
  String filterSummary({
    required LibraryApplicationFacade store,
    required int resultCount,
    required int totalCount,
  });

  /** 构建诊断和 filtered queue 使用的筛选表达式。 */
  String filterExpression({
    required LibraryApplicationFacade store,
    required int resultCount,
    required int totalCount,
  });

  /** 返回标签展示名。 */
  String tagLabel(TagItem tag);

  /** 调度现有 latest-only 查询，并按需延后刷新标签计数。 */
  void scheduleFilterRefresh({
    bool refreshCounts = false,
    Iterable<VideoItem>? changedVideos,
  });

  /** 执行一次扫描并继续复用 Repository generation 与进度回调。 */
  Future<void> scan(
    Future<LibraryScanCommitResult> Function(
      LibraryScanProgressCallback onProgress,
    ) action,
  );

  /** 解除目录管理但保留用户数据。 */
  Future<int> removeLibraryRootData(String root);

  /** 返回查询结果与计数各自的版本凭证。 */
  LibraryResultEpoch resultEpoch(FilterQuery query);
  LibraryCountEpoch countEpoch(FilterQuery query);

  /** 重新扫描当前媒体库 roots。 */
  Future<void> rescan();

  /** 标签动作后的面板状态，真实标签选择才自动收起。 */
  bool libraryTagDiscoveryPanelOpenAfterMutation({
    required bool currentOpen,
    required bool collapseAfterMutation,
  }) =>
      collapseAfterMutation ? false : currentOpen;

  /** 失效只读派生缓存，不修改 Repository 数据。 */
  void invalidateDerivedCaches();

  /** 播放器和文件命令使用的显式动作。 */
  /** 通过既有文件系统边界定位一个视频；维护页复用该动作而不复制平台命令。 */
  Future<void> revealVideoLocation(VideoItem item);
  Future<void> deleteVideoFromPlayer(
    VideoItem item,
    bool moveLocalFileToTrash,
  );
  Future<void> editManualTagsFromPlayer(VideoItem item);

  /** 记录播放时间变化并只失效相关结果缓存。 */
  void markPlaybackTimestampChanged(VideoItem item);

  /** 返回筛选 UI 使用的已选/排除标签快照。 */
  List<TagItem> selectedGroupTagItems(LibraryApplicationFacade store);
  List<TagItem> excludedTagItems(LibraryApplicationFacade store);

  /** 应用排序字段或方向，不触发完整标签计数。 */
  void applySortChange({
    SortMode? sortMode,
    SortDirection? sortDirection,
  });

  /** 当前唯一选中的二级 folder 标签。 */
  String? get activeChildTagName;

  /** 异步读取当前本地路径的直接子项。 */
  Future<List<LocalLibraryEntry>> localLibraryEntries(
    LibraryApplicationFacade store,
  );

  /** 打开目录选择器并按原扫描链导入。 */
  Future<void> pickFolder();

  /** 立即刷新稳定标签计数，供低频结构变化使用。 */
  void refreshStableTagCountsNow(LibraryApplicationFacade store);

  /** 把扫描差量应用到现有 query owner。 */
  void applyLibraryScanDelta(LibraryScanCommitResult result);

  /** 串行清理失效数据库记录，不删除磁盘文件。 */
  Future<int> cleanupMissingOrUnreadableVideos(
    LibraryApplicationFacade store,
  );

  /** 构建当前 `FilterQuery`，不复制过滤算法。 */
  FilterQuery currentFilterQuery();

  /** 返回标签编辑器在指定 folder 层级可使用的名称候选。 */
  Set<String> tagEditorCandidates(
    Iterable<TagItem> tags, {
    String? parentTag,
  }) =>
      tagEditorCandidatesForScope(tags, parentTag: parentTag);

  /** 返回目录/文件选择器应使用的媒体上下文起点。 */
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

  /** 为页面跳转提供统一的轻量淡入与横向位移动画。 */
  Route<R> smoothRoute<R>(
    Widget page, {
    String Function()? backShortcutProvider,
  }) {
    return PageRouteBuilder<R>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (routeContext, __, ___) => backShortcutProvider == null
          ? page
          : AppRouteBackInputRegion(
              shortcutProvider: backShortcutProvider,
              onBack: () {
                unawaited(Navigator.of(routeContext).maybePop());
              },
              child: page,
            ),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: appMotionCurve,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.018, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}
