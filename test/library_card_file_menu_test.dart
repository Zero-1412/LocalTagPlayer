import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/core/data_backup_settings.dart';
import 'package:local_tag_player/src/core/playback_settings.dart';
import 'package:local_tag_player/src/core/tag_rules.dart';
import 'package:local_tag_player/src/features/update/domain/app_update_service.dart';
import 'package:local_tag_player/src/models/library_scan_models.dart';
import 'package:local_tag_player/src/models/library_sort.dart';
import 'package:local_tag_player/src/models/platform_models.dart';
import 'package:local_tag_player/src/models/video_item.dart';
import 'package:local_tag_player/src/pages/library/library_page.dart';
import 'package:local_tag_player/src/pages/library/library_page_state_host.dart';
import 'package:local_tag_player/src/platform/file_system_adapter.dart';
import 'package:local_tag_player/src/platform/platform_interfaces.dart';
import 'package:local_tag_player/src/repositories/repository_interfaces.dart';
import 'package:local_tag_player/src/services/library/library_application_facade.dart';
import 'package:local_tag_player/src/services/library/library_load_diagnostics.dart';
import 'package:local_tag_player/src/services/library/library_page_application_service.dart';
import 'package:local_tag_player/src/services/media/media_details_service.dart';
import 'package:local_tag_player/src/services/media/thumbnail_service.dart';
import 'package:local_tag_player/src/services/player/player_service.dart';
import 'package:local_tag_player/src/services/resources/resource_scheduler.dart';
import 'package:local_tag_player/src/widgets/library/library_smoke_keys.dart';
import 'package:local_tag_player/src/widgets/library/library_video_results.dart';
import 'package:path/path.dart' as p;

// ignore_for_file: slash_for_doc_comments

/**
 * 为媒体库卡片文件菜单回归提供最小内存 Repository，并记录页面是否意外刷新昂贵计数。
 */
class _CardFileMenuRepository
    implements
        LibraryRepository,
        TagRepository,
        CacheRepository,
        PlaybackRepository,
        LibraryQueryCandidateRepository {
  @override
  int dataRevision = 0;
  /** 可控候选返回用于复现扫描提交跨越 pending 查询；最终过滤仍执行生产 TagQueryService。 */
  Future<List<VideoItem>?> Function(FilterQuery)? candidateLoader;
  @override
  Future<List<VideoItem>?> queryCandidatesFor(FilterQuery query) async =>
      candidateLoader == null ? null : await candidateLoader!(query);
  /** 页面回归不扫描真实目录，因此保持空 root 集合。 */
  @override
  final List<String> roots = <String>[];
  /** 由测试直接维护的两项视频索引，用于确认具体卡片的路径传递。 */
  @override
  final Map<String, VideoItem> videos = <String, VideoItem>{};
  /** 本回归不涉及收藏标签。 */
  @override
  final List<String> favoriteTags = <String>[];
  /** 本回归不构造标签分组，避免把排序刷新和标签展示耦合。 */
  @override
  final List<TagGroup> tagGroups = <TagGroup>[];
  /** 空标签实体索引用于建立真实 TagQueryService 上下文。 */
  @override
  final Map<String, TagItem> tagsById = <String, TagItem>{};
  /** 两个测试视频都不附加标签关系。 */
  @override
  final Map<String, Set<String>> videoTagIdsByPathKey = <String, Set<String>>{};

  /** 页面空闲期执行全库标签计数的次数。 */
  var resultCountsCalls = 0;
  /** 页面级扫描可达性回归记录的启动次数。 */
  var scanCalls = 0;
  LibraryScanProgressCallback? activeProgress;
  /** 启动后新增视频检查的调用次数，用于保护其不被后台清理阻塞。 */
  var untrackedVideoCountCalls = 0;
  /** 测试可指定尚未入库的视频数。 */
  var untrackedVideoCount = 0;
  /** 缺失记录清理调用次数；页面启动和扫描都必须保持为零。 */
  var unavailableCleanupCalls = 0;
  /** 页面暂停/继续按钮发给 Repository 的顺序。 */
  final pausedStates = <bool>[];
  /** 页面取消按钮发给 Repository 的次数。 */
  var cancelCalls = 0;
  /** 当前由测试控制退出时机的扫描 Future。 */
  Completer<LibraryScanCommitResult>? activeScan;

  @override
  Set<String> get allTags => const <String>{};

  @override
  Map<String, int> resultCounts(FilterQuery query) {
    resultCountsCalls += 1;
    return const <String, int>{};
  }

  @override
  Future<int> countUntrackedVideos() async {
    untrackedVideoCountCalls += 1;
    return untrackedVideoCount;
  }

  /** 记录显式维护命令；页面生命周期不得调用。 */
  @override
  Future<int> removeMissingOrUnreadableVideos() async {
    unavailableCleanupCalls += 1;
    return 0;
  }

  @override
  Future<LibraryScanCommitResult> scanWithChanges({
    LibraryScanProgressCallback? onProgress,
  }) {
    scanCalls += 1;
    activeProgress = onProgress;
    final completer = Completer<LibraryScanCommitResult>();
    activeScan = completer;
    onProgress?.call(const LibraryScanProgress(
      generationId: 41,
      phase: LibraryScanPhase.fingerprinting,
      processed: 1,
      discovered: 2,
      total: 2,
    ));
    return completer.future;
  }

  @override
  Future<void> setScanPaused(bool paused) async {
    pausedStates.add(paused);
  }

  @override
  Future<void> cancelActiveScan() async {
    cancelCalls += 1;
    final completer = activeScan;
    if (completer != null && !completer.isCompleted) {
      completer.complete(LibraryScanCommitResult.cancelled(41));
    }
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/** 记录页面交给平台边界的目标路径，确保卡片动作定位当前视频而不是媒体库目录。 */
class _CardFileMenuFileSystem implements FileSystemAdapter {
  /** 最近一次要求文件管理器定位的完整视频路径。 */
  String? revealedPath;

  @override
  Future<void> revealInFileManager(String path) async {
    revealedPath = p.normalize(path);
  }

  @override
  String joinPath(List<String> parts) => p.joinAll(parts);

  @override
  String parentPath(String path) => p.dirname(path);

  @override
  String normalizePath(String path) => p.normalize(path);

  @override
  Future<bool> fileExists(String path) async => File(path).existsSync();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/** 缩略图测试只返回空结果，不启动 FFmpeg 或读取用户媒体。 */
class _CardFileMenuFFmpegBackend implements FFmpegBackend {
  @override
  Future<File?> createThumbnail({
    required VideoItem item,
    required File output,
    bool allowFallback = true,
  }) async =>
      null;

  @override
  Future<File?> createFramePreview({
    required VideoItem item,
    required File output,
    required Duration position,
  }) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/** 页面可见项探测返回空批次，避免启动 FFprobe。 */
class _CardFileMenuProbeBackend implements MediaProbeBackend {
  _CardFileMenuProbeBackend({this.onProbe});

  final VoidCallback? onProbe;

  @override
  Future<List<MediaProbeResult>> probeBatch({
    required int generationId,
    required List<MediaProbeRequest> requests,
  }) async {
    onProbe?.call();
    return const <MediaProbeResult>[];
  }

  @override
  Future<void> cancelGeneration(int generationId) async {}
}

/** 测试不会进入播放器，只提供满足组合边界的安全占位后端。 */
class _CardFileMenuPlayerBackend implements PlayerBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/**
 * 卡片菜单测试不会打开关于页；该假实现只用于满足页面依赖注入合同。
 */
class _CardFileMenuUpdateService implements AppUpdateService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/**
 * 向真实 LibraryPage 注入内存 Repository、隔离缓存和名称升序偏好。
 */
class _CardFileMenuApplicationService implements LibraryPageApplicationService {
  _CardFileMenuApplicationService({
    required this.store,
    required this.thumbnailService,
  });

  /** 页面读取的真实 facade，底层由测试内存 Repository 承载。 */
  final LibraryApplicationFacade store;
  /** 使用隔离目录和空 FFmpeg 后端的缩略图服务。 */
  final ThumbnailService thumbnailService;
  /** 测试页与生产页保持同一共享资源预算边界。 */
  final resourceScheduler = ResourceScheduler();
  /** 记录应用启动后是否自动登记了媒体详情补全。 */
  var mediaProbeBatchCalls = 0;
  /** 最近一次保存的展示偏好，用于确认排序由页面持久化而非 controller 越界写盘。 */
  LibrarySortPreferences? savedSortPreferences;

  @override
  Future<LibraryPageStartupData> load({
    LibraryLoadDiagnostics? diagnostics,
  }) async {
    return LibraryPageStartupData(
      store: store,
      thumbnailService: thumbnailService,
      playbackSettings: PlaybackSettings.defaults,
      sortPreferences: const LibrarySortPreferences(
        mode: SortMode.name,
        direction: SortDirection.ascending,
      ),
      dataBackupSettings: DataBackupSettings.defaults,
      resourceScheduler: resourceScheduler,
    );
  }

  @override
  Future<void> savePlaybackSettings(PlaybackSettings settings) async {}

  @override
  Future<void> saveDataBackupSettings(DataBackupSettings settings) async {}

  @override
  Future<void> saveSortPreferences(
    LibrarySortPreferences preferences,
  ) async {
    savedSortPreferences = preferences;
  }

  @override
  MediaDetailsService createMediaDetailsService({
    MediaDetailsUpdatedCallback? onUpdated,
    MediaDetailsBatchUpdatedCallback? onBatchUpdated,
    void Function(MediaDetailsProgress progress)? onProgress,
  }) {
    return MediaDetailsService(
      probeBackend: _CardFileMenuProbeBackend(
        onProbe: () => mediaProbeBatchCalls++,
      ),
      onUpdated: onUpdated,
      onBatchUpdated: onBatchUpdated,
      onProgress: onProgress,
    );
  }

  @override
  String? get stressRoot => null;

  @override
  Future<void> writeStartupDiagnostics({
    required LibraryLoadDiagnostics diagnostics,
    required Duration totalElapsed,
    required String marker,
  }) async {}
}

/** 首次加载失败、第二次成功，用于证明错误页的重试真实回到同一应用边界。 */
class _RetryingCardFileMenuApplicationService
    extends _CardFileMenuApplicationService {
  _RetryingCardFileMenuApplicationService({
    required super.store,
    required super.thumbnailService,
  });

  var loadCalls = 0;

  @override
  Future<LibraryPageStartupData> load({
    LibraryLoadDiagnostics? diagnostics,
  }) async {
    loadCalls += 1;
    if (loadCalls == 1) {
      throw StateError('controlled startup failure');
    }
    return super.load(diagnostics: diagnostics);
  }
}

void main() {
  for (final newestInput in ['alpha', 'beta']) {
    testWidgets('零差量扫描跨越 pending 查询后重新发布最新输入 $newestInput', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory.systemTemp.createTempSync('ltp_pending_scan_');
      addTearDown(() => root.deleteSync(recursive: true));
      final repository = _CardFileMenuRepository();
      repository.roots.add(root.path);
      for (final name in ['alpha', 'beta']) {
        final path = p.join(root.path, '$name.mp4');
        repository.videos[TagRules.pathKey(path)] = VideoItem(
            videoId: name,
            path: path,
            title: name,
            folder: root.path,
            tags: const {},
            addedAt: DateTime.utc(2026, 9, 5));
      }
      final store = LibraryApplicationFacade(
          queryRepository: repository,
          commandRepository: repository,
          tagRepository: repository,
          cacheRepository: repository,
          playbackRepository: repository);
      await tester.pumpWidget(MaterialApp(
          home: LibraryPage(
        applicationService: _CardFileMenuApplicationService(
            store: store,
            thumbnailService: ThumbnailService.forDirectory(
                Directory(p.join(root.path, 'thumbs')),
                _CardFileMenuFFmpegBackend())),
        fileSystem: _CardFileMenuFileSystem(),
        updateService: _CardFileMenuUpdateService(),
        playerServiceFactory: (
                {required String hwdec,
                required bool enableHardwareAcceleration,
                required PlayerRendererPreference rendererPreference}) =>
            PlayerService(backend: _CardFileMenuPlayerBackend()),
        mediaProbeBackendFactory: _CardFileMenuProbeBackend.new,
      )));
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pump(const Duration(milliseconds: 1300));
      final host =
          tester.state(find.byType(LibraryPage)) as LibraryPageStateHost;
      final oldCandidates = Completer<List<VideoItem>?>();
      var oldLoads = 0;
      repository.candidateLoader = (_) {
        oldLoads++;
        return oldCandidates.future;
      };
      final countsBefore = repository.resultCountsCalls;
      await tester.tap(find.byKey(LibrarySmokeKeys.rescanButton));
      await tester.pump();
      expect(repository.scanCalls, 1);
      await tester.enterText(find.byKey(LibrarySmokeKeys.searchField), 'alpha');
      await tester.pump();
      if (newestInput != 'alpha') {
        await tester.enterText(
            find.byKey(LibrarySmokeKeys.searchField), newestInput);
        await tester.pump();
      }
      expect(oldLoads, greaterThan(0));
      // Repository 已成功提交；即使没有视频差量，也必须淘汰旧候选并重调当前输入。
      repository.dataRevision++;
      repository.candidateLoader = (_) async => null;
      repository.activeScan!.complete(LibraryScanCommitResult(
          generationId: 41,
          addedCount: 0,
          modifiedCount: 0,
          missingCount: 0,
          relinkedCount: 0,
          changedVideos: const [],
          probeCandidates: const []));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(host.runtime.queryController.state!.query.keyword, newestInput);
      expect(
          host.runtime.queryController.state!.filteredVideos
              .map((v) => v.videoId),
          [newestInput]);
      expect(host.runtime.queryController.state!.epoch,
          host.resultEpoch(host.currentFilterQuery()));
      oldCandidates.complete([]);
      await tester.pump();
      expect(
          host.runtime.queryController.state!.filteredVideos
              .map((v) => v.videoId),
          [newestInput]);
      expect(repository.resultCountsCalls, countsBefore);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });
  }
  testWidgets('媒体库启动失败显示安全重试并可恢复到就绪态', (tester) async {
    final repository = _CardFileMenuRepository();
    final store = LibraryApplicationFacade(
      queryRepository: repository,
      commandRepository: repository,
      tagRepository: repository,
      cacheRepository: repository,
      playbackRepository: repository,
    );
    final root = Directory(
      p.join(
        Directory.systemTemp.path,
        'ltp_startup_retry_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final service = _RetryingCardFileMenuApplicationService(
      store: store,
      thumbnailService: ThumbnailService.forDirectory(
        Directory(p.join(root.path, 'thumbs')),
        _CardFileMenuFFmpegBackend(),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: LibraryPage(
        applicationService: service,
        fileSystem: _CardFileMenuFileSystem(),
        playerServiceFactory: ({
          required String hwdec,
          required bool enableHardwareAcceleration,
          required PlayerRendererPreference rendererPreference,
        }) =>
            PlayerService(backend: _CardFileMenuPlayerBackend()),
        mediaProbeBackendFactory: _CardFileMenuProbeBackend.new,
        updateService: _CardFileMenuUpdateService(),
      ),
    ));
    await tester.pump();

    expect(
        find.byKey(const ValueKey('library.startup.failed')), findsOneWidget);
    expect(find.text('媒体库暂时无法加载'), findsOneWidget);
    expect(find.textContaining('媒体文件不会被修改'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('library.startup.retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(service.loadCalls, 2);
    expect(find.byKey(const ValueKey('library.startup.failed')), findsNothing);
    expect(find.byKey(const ValueKey('library.startup.loading')), findsNothing);
  });

  testWidgets('媒体库首帧后自动启动缺失缩略图补全', (tester) async {
    final root = Directory(
      p.join(
        Directory.systemTemp.path,
        'ltp_startup_thumbnail_backfill_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });
    final repository = _CardFileMenuRepository()..roots.add(root.path);
    for (var index = 0; index < 600; index++) {
      final path = p.join(root.path, 'startup-$index.mp4');
      final item = VideoItem(
        videoId: 'startup-backfill-$index',
        path: path,
        title: 'startup-$index',
        folder: root.path,
        tags: const <String>{},
        addedAt: DateTime.utc(2026, 8, 16),
        mediaFingerprint: 'startup-backfill-fingerprint-$index',
      );
      repository.videos[TagRules.pathKey(path)] = item;
    }
    final store = LibraryApplicationFacade(
      queryRepository: repository,
      commandRepository: repository,
      tagRepository: repository,
      cacheRepository: repository,
      playbackRepository: repository,
    );
    final thumbnailService = ThumbnailService.forDirectory(
      Directory(p.join(root.path, 'thumbs')),
      _CardFileMenuFFmpegBackend(),
    );
    final applicationService = _CardFileMenuApplicationService(
      store: store,
      thumbnailService: thumbnailService,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          applicationService: applicationService,
          fileSystem: _CardFileMenuFileSystem(),
          playerServiceFactory: ({
            required String hwdec,
            required bool enableHardwareAcceleration,
            required PlayerRendererPreference rendererPreference,
          }) =>
              PlayerService(backend: _CardFileMenuPlayerBackend()),
          mediaProbeBackendFactory: _CardFileMenuProbeBackend.new,
          updateService: _CardFileMenuUpdateService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 900));

    // 首帧后的自动登记必须已经填满受控窗口；若只依赖可见卡片优先队列，
    // 这里最多只会有少量任务，不能证明启动补全已挂载。
    expect(thumbnailService.queuedJobs, greaterThanOrEqualTo(476));
    expect(applicationService.mediaProbeBatchCalls, greaterThan(0));
  });

  testWidgets('启动新增视频检查不会自动清理缺失记录', (tester) async {
    final repository = _CardFileMenuRepository()
      ..roots.add(r'D:\\library')
      ..untrackedVideoCount = 2;
    final store = LibraryApplicationFacade(
      queryRepository: repository,
      commandRepository: repository,
      tagRepository: repository,
      cacheRepository: repository,
      playbackRepository: repository,
    );
    // Windows 测试 runner 的 `Directory.createTemp` 偶发在目录已创建后仍不回调；本
    // 用例只需要隔离空目录，改用同步创建的唯一路径，避免测试在首次挂载前悬挂。
    final root = Directory(
      p.join(
        Directory.systemTemp.path,
        'ltp_startup_scan_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });
    final thumbnailService = ThumbnailService.forDirectory(
      Directory(p.join(root.path, 'thumbs')),
      _CardFileMenuFFmpegBackend(),
    );
    final applicationService = _CardFileMenuApplicationService(
      store: store,
      thumbnailService: thumbnailService,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          applicationService: applicationService,
          fileSystem: _CardFileMenuFileSystem(),
          playerServiceFactory: ({
            required String hwdec,
            required bool enableHardwareAcceleration,
            required PlayerRendererPreference rendererPreference,
          }) =>
              PlayerService(backend: _CardFileMenuPlayerBackend()),
          mediaProbeBackendFactory: _CardFileMenuProbeBackend.new,
          updateService: _CardFileMenuUpdateService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repository.untrackedVideoCountCalls, 1);
    expect(repository.unavailableCleanupCalls, 0);
    expect(find.text('发现新增视频'), findsOneWidget);
    expect(find.text('当前目录发现 2 个未入库视频，是否现在重新扫描？'), findsOneWidget);

    // 关闭启动提示，确认页面整个首帧生命周期都没有偷偷进入破坏性维护命令。
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(repository.unavailableCleanupCalls, 0);
  });

  testWidgets('媒体卡片菜单可达且查询与排序只发布最新结果', (tester) async {
    tester.view.physicalSize = const Size(1248, 714);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final root = Directory(
      p.join(
        Directory.systemTemp.path,
        'ltp_library_card_file_menu_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });
    final bravoFile = File(p.join(root.path, 'bravo.mp4'))
      ..writeAsBytesSync(<int>[1], flush: true);
    final charlieFile = File(p.join(root.path, 'charlie.mp4'))
      ..writeAsBytesSync(<int>[2], flush: true);
    final bravo = VideoItem(
      videoId: 'card-file-menu-bravo',
      path: bravoFile.path,
      title: 'bravo',
      folder: root.path,
      tags: const <String>{},
      addedAt: DateTime.utc(2026, 7, 21),
    );
    final charlie = VideoItem(
      videoId: 'card-file-menu-charlie',
      path: charlieFile.path,
      title: 'charlie',
      folder: root.path,
      tags: const <String>{},
      addedAt: DateTime.utc(2026, 7, 21),
    );
    final repository = _CardFileMenuRepository();
    repository.roots.add(root.path);
    repository.videos.addAll(<String, VideoItem>{
      TagRules.pathKey(bravo.path): bravo,
      TagRules.pathKey(charlie.path): charlie,
    });
    final store = LibraryApplicationFacade(
      queryRepository: repository,
      commandRepository: repository,
      tagRepository: repository,
      cacheRepository: repository,
      playbackRepository: repository,
    );
    final thumbnailService = ThumbnailService.forDirectory(
      Directory(p.join(root.path, 'thumbs')),
      _CardFileMenuFFmpegBackend(),
    );
    final applicationService = _CardFileMenuApplicationService(
      store: store,
      thumbnailService: thumbnailService,
    );
    final fileSystem = _CardFileMenuFileSystem();

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          applicationService: applicationService,
          fileSystem: fileSystem,
          playerServiceFactory: ({
            required String hwdec,
            required bool enableHardwareAcceleration,
            required PlayerRendererPreference rendererPreference,
          }) =>
              PlayerService(backend: _CardFileMenuPlayerBackend()),
          mediaProbeBackendFactory: _CardFileMenuProbeBackend.new,
          updateService: _CardFileMenuUpdateService(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 1300));

    // 只匹配结果卡片标题，排除搜索输入框中的同名文本。
    Finder cardTitle(String title) => find.descendant(
          of: find.byType(InteractiveVideoCard),
          matching: find.text(title),
        );

    expect(cardTitle('bravo'), findsOneWidget);
    expect(cardTitle('charlie'), findsOneWidget);
    expect(
      tester.getTopLeft(cardTitle('bravo')).dx,
      lessThan(tester.getTopLeft(cardTitle('charlie')).dx),
    );
    expect(repository.resultCountsCalls, greaterThan(0));

    await tester.tap(find.byKey(LibrarySmokeKeys.rescanButton));
    await tester.pump();
    expect(repository.scanCalls, 1);
    expect(find.byKey(const ValueKey('qa.media_import.pause')), findsOneWidget);
    final resultsBeforeProgress =
        tester.widget(find.byKey(LibrarySmokeKeys.incrementalResults));
    // 真实挂载页面收到进度时应更新文案，同时保持结果子树，避免每次进度全页构建。
    repository.activeProgress!(const LibraryScanProgress(
      generationId: 41,
      phase: LibraryScanPhase.fingerprinting,
      processed: 3,
      discovered: 4,
      total: 4,
    ));
    await tester.pump();
    expect(find.textContaining('校验文件 3/4'), findsOneWidget);
    expect(tester.widget(find.byKey(LibrarySmokeKeys.incrementalResults)),
        same(resultsBeforeProgress));
    await tester.tap(find.byKey(const ValueKey('qa.media_import.pause')));
    await tester.pump();
    expect(repository.pausedStates, <bool>[true]);
    expect(
        find.byKey(const ValueKey('qa.media_import.resume')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('qa.media_import.resume')));
    await tester.pump();
    expect(repository.pausedStates, <bool>[true, false]);
    await tester.tap(find.byKey(const ValueKey('qa.library_scan.cancel')));
    await tester.pump();
    expect(repository.cancelCalls, 1);
    expect(find.byKey(LibrarySmokeKeys.rescanButton), findsOneWidget);

    final countCallsBeforeSort = repository.resultCountsCalls;
    await tester.tap(
      find.byKey(LibrarySmokeKeys.topSortDirectionButton),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      applicationService.savedSortPreferences?.direction,
      SortDirection.descending,
    );
    expect(repository.resultCountsCalls, countCallsBeforeSort);
    expect(
      tester.getTopLeft(cardTitle('charlie')).dx,
      lessThan(tester.getTopLeft(cardTitle('bravo')).dx),
    );
    expect(cardTitle('bravo'), findsOneWidget);
    expect(cardTitle('charlie'), findsOneWidget);

    final countCallsBeforeSearch = repository.resultCountsCalls;
    await tester.enterText(
      find.byKey(LibrarySmokeKeys.searchField),
      'bravo',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(cardTitle('bravo'), findsOneWidget);
    expect(cardTitle('charlie'), findsNothing);
    expect(repository.resultCountsCalls, countCallsBeforeSearch);

    await tester.enterText(
      find.byKey(LibrarySmokeKeys.searchField),
      '',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(cardTitle('bravo'), findsOneWidget);
    expect(cardTitle('charlie'), findsOneWidget);
    expect(
      tester.getTopLeft(cardTitle('charlie')).dx,
      lessThan(tester.getTopLeft(cardTitle('bravo')).dx),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(cardTitle('charlie')));
    await tester.pump(libraryCardMoreFadeDuration);
    await tester.tap(find.byKey(LibrarySmokeKeys.cardMore(charlie.path)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('打开文件'), findsOneWidget);
    expect(find.text('删除文件'), findsOneWidget);
    expect(find.text('编辑标签'), findsNothing);
    expect(find.text('重命名文件'), findsNothing);
    expect(find.byKey(LibrarySmokeKeys.videoMoreEditTags), findsNothing);
    expect(find.byKey(LibrarySmokeKeys.videoMoreRenameFile), findsNothing);
    final openItemRect = tester.getRect(
      find.byKey(LibrarySmokeKeys.videoMoreRevealLocation),
    );
    final deleteItemRect = tester.getRect(
      find.byKey(LibrarySmokeKeys.videoMoreDelete),
    );
    expect(openItemRect.height, libraryVideoMoreMenuItemHeight);
    expect(deleteItemRect.height, libraryVideoMoreMenuItemHeight);
    expect(openItemRect.width, lessThanOrEqualTo(156));

    await tester.tap(find.byKey(LibrarySmokeKeys.videoMoreRevealLocation));
    await tester.pump(const Duration(milliseconds: 300));
    expect(fileSystem.revealedPath, p.normalize(charlie.path));
    expect(File(charlie.path).existsSync(), isTrue);

    await gesture.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
