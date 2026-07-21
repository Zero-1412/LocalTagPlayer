import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';
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
        PlaybackRepository {
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

  @override
  Set<String> get allTags => const <String>{};

  @override
  Map<String, int> resultCounts(FilterQuery query) {
    resultCountsCalls += 1;
    return const <String, int>{};
  }

  @override
  Future<int> countUntrackedVideos() async => 0;

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
  @override
  Future<List<MediaProbeResult>> probeBatch({
    required int generationId,
    required List<MediaProbeRequest> requests,
  }) async =>
      const <MediaProbeResult>[];

  @override
  Future<void> cancelGeneration(int generationId) async {}
}

/** 测试不会进入播放器，只提供满足组合边界的安全占位后端。 */
class _CardFileMenuPlayerBackend implements PlayerBackend {
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
    );
  }

  @override
  Future<void> savePlaybackSettings(PlaybackSettings settings) async {}

  @override
  Future<void> saveDataBackupSettings(DataBackupSettings settings) async {}

  @override
  Future<void> saveSortPreferences(
    LibrarySortPreferences preferences,
  ) async {}

  @override
  MediaDetailsService createMediaDetailsService({
    MediaDetailsUpdatedCallback? onUpdated,
    MediaDetailsBatchUpdatedCallback? onBatchUpdated,
    void Function(MediaDetailsProgress progress)? onProgress,
  }) {
    return MediaDetailsService(
      probeBackend: _CardFileMenuProbeBackend(),
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

void main() {
  testWidgets('媒体卡片菜单只保留当前文件定位与删除', (tester) async {
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
    repository.videos.addAll(<String, VideoItem>{
      TagRules.pathKey(bravo.path): bravo,
      TagRules.pathKey(charlie.path): charlie,
    });
    final store = LibraryApplicationFacade(
      libraryRepository: repository,
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
          playerBackendFactory: ({
            required String hwdec,
            required bool enableHardwareAcceleration,
          }) =>
              _CardFileMenuPlayerBackend(),
          mediaProbeBackendFactory: _CardFileMenuProbeBackend.new,
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
