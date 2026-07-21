import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';
import 'package:path/path.dart' as p;

// ignore_for_file: slash_for_doc_comments

/**
 * 为媒体库页面回归提供最小内存 Repository，并记录昂贵标签计数是否被误触发。
 */
class _RenameRefreshRepository
    implements
        LibraryRepository,
        TagRepository,
        CacheRepository,
        PlaybackRepository {
  /** 页面回归不扫描真实目录，因此保持空 root 集合。 */
  @override
  final List<String> roots = <String>[];
  /** 由测试直接维护、并在改名事务中重建路径键的视频索引。 */
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

  /**
   * 模拟 SQLite mutable path 事务：保持对象与 videoId，只替换路径索引和标题。
   */
  @override
  Future<void> renameVideoPath(VideoItem item, String newPath) async {
    videos.remove(TagRules.pathKey(item.path));
    item
      ..path = p.normalize(newPath)
      ..title = p.basenameWithoutExtension(newPath);
    videos[TagRules.pathKey(item.path)] = item;
  }

  @override
  Future<int> countUntrackedVideos() async => 0;

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/** 使用同步临时文件 I/O 完成页面确认改名，避免 Widget FakeAsync 截留文件 Future。 */
class _RenameRefreshFileSystem implements FileSystemAdapter {
  const _RenameRefreshFileSystem();

  @override
  String joinPath(List<String> parts) => p.joinAll(parts);

  @override
  String parentPath(String path) => p.dirname(path);

  @override
  String normalizePath(String path) => p.normalize(path);

  @override
  Future<bool> fileExists(String path) async => File(path).existsSync();

  @override
  Future<String> renameFile(String sourcePath, String targetPath) async {
    if (File(targetPath).existsSync()) {
      throw FileSystemException('目标文件已存在', targetPath);
    }
    return File(sourcePath).renameSync(targetPath).path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/** 缩略图测试只返回空结果，不启动 FFmpeg 或读取用户媒体。 */
class _RenameRefreshFFmpegBackend implements FFmpegBackend {
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
class _RenameRefreshProbeBackend implements MediaProbeBackend {
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
class _RenameRefreshPlayerBackend implements PlayerBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/**
 * 向真实 LibraryPage 注入内存 Repository、隔离缓存和名称升序偏好。
 */
class _RenameRefreshApplicationService
    implements LibraryPageApplicationService {
  _RenameRefreshApplicationService({
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
      probeBackend: _RenameRefreshProbeBackend(),
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
  testWidgets('卡片改名后关键字筛选与名称排序立即更新', (tester) async {
    tester.view.physicalSize = const Size(1248, 714);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final root = Directory(
      p.join(
        Directory.systemTemp.path,
        'ltp_library_rename_refresh_${DateTime.now().microsecondsSinceEpoch}',
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
      videoId: 'rename-refresh-bravo',
      path: bravoFile.path,
      title: 'bravo',
      folder: root.path,
      tags: const <String>{},
      addedAt: DateTime.utc(2026, 7, 21),
    );
    final charlie = VideoItem(
      videoId: 'rename-refresh-charlie',
      path: charlieFile.path,
      title: 'charlie',
      folder: root.path,
      tags: const <String>{},
      addedAt: DateTime.utc(2026, 7, 21),
    );
    final repository = _RenameRefreshRepository();
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
      _RenameRefreshFFmpegBackend(),
    );
    final applicationService = _RenameRefreshApplicationService(
      store: store,
      thumbnailService: thumbnailService,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          applicationService: applicationService,
          fileSystem: const _RenameRefreshFileSystem(),
          playerBackendFactory: ({
            required String hwdec,
            required bool enableHardwareAcceleration,
          }) =>
              _RenameRefreshPlayerBackend(),
          mediaProbeBackendFactory: _RenameRefreshProbeBackend.new,
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
    final countCallsBeforeRename = repository.resultCountsCalls;
    expect(countCallsBeforeRename, greaterThan(0));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(cardTitle('charlie')));
    await tester.pump(libraryCardMoreFadeDuration);
    await tester.tap(find.byKey(LibrarySmokeKeys.cardMore(charlie.path)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(LibrarySmokeKeys.videoMoreRenameFile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('player.renameFile.input')),
      'alpha',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('player.renameFile.confirm')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(cardTitle('alpha'), findsOneWidget);
    expect(cardTitle('charlie'), findsNothing);
    expect(
      tester.getTopLeft(cardTitle('alpha')).dx,
      lessThan(tester.getTopLeft(cardTitle('bravo')).dx),
    );
    expect(File(p.join(root.path, 'alpha.mp4')).existsSync(), isTrue);
    expect(charlieFile.existsSync(), isFalse);
    expect(charlie.videoId, 'rename-refresh-charlie');

    await tester.enterText(
      find.byKey(LibrarySmokeKeys.searchField),
      'charlie',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(cardTitle('alpha'), findsNothing);
    expect(cardTitle('bravo'), findsNothing);

    await tester.enterText(
      find.byKey(LibrarySmokeKeys.searchField),
      'alpha',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(cardTitle('alpha'), findsOneWidget);
    expect(cardTitle('bravo'), findsNothing);
    expect(repository.resultCountsCalls, countCallsBeforeRename);

    await gesture.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
