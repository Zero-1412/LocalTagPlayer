import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_tag_player/src/app.dart';
import 'package:path/path.dart' as p;

// ignore_for_file: slash_for_doc_comments

VideoItem _testVideo({
  required String path,
  required String title,
  Set<String> tags = const <String>{},
}) {
  return VideoItem(
    path: path,
    title: title,
    folder: 'C:/queue',
    tags: <String>{...tags},
    addedAt: DateTime.utc(2026, 7, 11),
  );
}

/** 记录悬停取帧位置并写入最小有效 JPEG，隔离真实 FFmpeg 进程。 */
class _PreviewFFmpegBackend implements FFmpegBackend {
  var previewCalls = 0;
  final previewPositions = <Duration>[];

  /** 分页组件测试不需要生成真实缩略图，返回空结果即可。 */
  @override
  Future<File?> createThumbnail({
    required VideoItem item,
    required File output,
    bool allowFallback = false,
  }) async {
    return null;
  }

  @override
  Future<File?> createFramePreview({
    required VideoItem item,
    required File output,
    required Duration position,
  }) async {
    previewCalls++;
    previewPositions.add(position);
    await output.parent.create(recursive: true);
    await output.writeAsBytes(<int>[0xff, 0xd8, 0xff, 0xd9], flush: true);
    return output;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/** 记录全局播放偏好是否真实送入后端，不启动 media_kit 或桌面纹理。 */
class _PreferenceRecordingPlayerBackend implements PlayerBackend {
  final properties = <String, String>{};
  final rates = <double>[];

  @override
  Future<void> setProperty(String property, String value) async {
    properties[property] = value;
  }

  @override
  Future<void> setRate(double rate) async {
    rates.add(rate);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('library video card uses compact height and stable duration labels', () {
    expect(
      libraryVideoCardMainAxisExtent(
        gridWidth: 880,
        narrow: false,
        compact: false,
      ),
      207.5,
    );
    expect(
      libraryVideoCardMainAxisExtent(
        gridWidth: 590,
        narrow: false,
        compact: true,
      ),
      closeTo(157.63, 0.01),
    );
    expect(
      libraryVideoCardMainAxisExtent(
        gridWidth: 500,
        narrow: true,
        compact: true,
      ),
      321.5,
    );
    expect(
      libraryVideoGridCrossAxisSpacing(gridWidth: 680, compact: true),
      10,
    );
    expect(
      libraryVideoGridCrossAxisSpacing(gridWidth: 880, compact: false),
      14,
    );
    expect(
      libraryVideoGridCrossAxisSpacing(gridWidth: 1200, compact: false),
      18,
    );
    expect(
      libraryVideoGridCrossAxisSpacing(gridWidth: 1600, compact: false),
      22,
    );
    expect(
      libraryVideoGridMaxCrossAxisExtent(
        gridWidth: 1600,
        narrow: false,
        compact: false,
      ),
      360,
    );
    expect(
      libraryVideoGridMaxCrossAxisExtent(
        gridWidth: 2000,
        narrow: false,
        compact: false,
      ),
      430,
    );
    expect(libraryVideoCardTitleFontSize(200), 13.5);
    expect(libraryVideoCardTitleFontSize(260), 14.5);
    expect(libraryVideoCardTitleFontSize(320), 15.5);
    expect(libraryVideoCardTitleFontSize(420), 16);
    expect(libraryVideoCardRadius, 8);
    final compactOverlay = libraryVideoOverlayMetrics(200);
    expect(compactOverlay.edgeInset, 6);
    expect(compactOverlay.favoriteButtonSize, 30);
    expect(compactOverlay.favoriteIconSize, 17.5);
    expect(compactOverlay.durationFontSize, 10);
    final standardOverlay = libraryVideoOverlayMetrics(280);
    expect(standardOverlay.edgeInset, 7);
    expect(standardOverlay.favoriteButtonSize, 32);
    expect(standardOverlay.favoriteIconSize, 19);
    expect(standardOverlay.durationHorizontalPadding, 5.5);
    final wideOverlay = libraryVideoOverlayMetrics(420);
    expect(wideOverlay.edgeInset, 9);
    expect(wideOverlay.favoriteButtonSize, 34);
    expect(wideOverlay.durationFontSize, 11);
    expect(libraryFavoriteOverlayOpacity, 0.46);
    expect(libraryDurationOverlayOpacity, 0.56);
    expect(libraryVideoDurationLabel(Duration.zero), '--:--');
    expect(
      libraryVideoDurationLabel(const Duration(minutes: 9, seconds: 7)),
      '9:07',
    );
    expect(
      libraryVideoDurationLabel(
        const Duration(hours: 1, minutes: 2, seconds: 3),
      ),
      '1:02:03',
    );
  });

  testWidgets('thumbnail placeholders share one dark visual system',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              Expanded(
                child: LibraryThumbnailPlaceholder(
                  state: LibraryThumbnailPlaceholderState.loading,
                ),
              ),
              Expanded(
                child: LibraryThumbnailPlaceholder(
                  state: LibraryThumbnailPlaceholderState.failed,
                ),
              ),
              Expanded(
                child: LibraryThumbnailPlaceholder(
                  state: LibraryThumbnailPlaceholderState.empty,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('正在生成缩略图'), findsOneWidget);
    expect(find.text('缩略图生成失败'), findsOneWidget);
    expect(find.text('暂无缩略图'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    final loading = tester.widget<Container>(
      find.byKey(
        const ValueKey<String>('library-thumbnail-placeholder-loading'),
      ),
    );
    final decoration = loading.decoration! as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(
      gradient.colors,
      const <Color>[
        libraryThumbnailPlaceholderTop,
        libraryThumbnailPlaceholderBottom,
      ],
    );
  });

  testWidgets('card hover lifts only thumbnail and keeps title fixed',
      (tester) async {
    final directory = Directory(
      p.join(
        Directory.systemTemp.path,
        'local_tag_player_hover_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final item = _testVideo(
      path: p.join(directory.path, 'hover.mp4'),
      title: 'hover video',
    );
    final thumbnailService = ThumbnailService.forDirectory(
      directory,
      _PreviewFFmpegBackend(),
    );
    await tester.binding.setSurfaceSize(const Size(500, 350));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 230,
              child: InteractiveVideoCard(
                item: item,
                thumbnailService: thumbnailService,
                playbackSettings: PlaybackSettings.defaults,
                onOpen: () {},
                onToggleFavorite: () {},
              ),
            ),
          ),
        ),
      ),
    );
    // 加载占位的进度环会持续动画；固定推进一帧即可验证卡片布局和 hover 目标。
    await tester.pump();

    final titleFinder = find.text('hover video');
    final thumbnailFinder =
        find.byKey(LibrarySmokeKeys.cardThumbnailSurface(item.path));
    final titleTopBefore = tester.getTopLeft(titleFinder).dy;
    final initialThumbnail = tester.widget<AnimatedContainer>(thumbnailFinder);
    expect(initialThumbnail.transform!.storage[13], 0);
    final cardInkWell = tester.widget<InkWell>(
      find.byKey(LibrarySmokeKeys.cardOpen(item.path)),
    );
    expect(cardInkWell.hoverColor, Colors.transparent);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(titleFinder));
    await tester.pump();
    final hoveredThumbnail = tester.widget<AnimatedContainer>(thumbnailFinder);
    expect(hoveredThumbnail.transform!.storage[13], -libraryVideoHoverLift);
    await tester.pump(appMotionDuration);
    expect(tester.getTopLeft(titleFinder).dy, titleTopBefore);
    expect(libraryVideoHoverShadowOpacity, 0.30);
    await gesture.removePointer();
  });

  testWidgets('library scrolling appends ten rows and keeps full play queue',
      (WidgetTester tester) async {
    expect(libraryRowsPerLoad, 10);
    expect(libraryPreloadRowsAhead, 4);
    expect(
      libraryVideoGridColumnCount(
        gridWidth: 900,
        narrow: false,
        compact: false,
      ),
      3,
    );
    expect(
      libraryVideoGridColumnCount(
        gridWidth: 2200,
        narrow: false,
        compact: false,
      ),
      5,
    );
    expect(
      libraryIncrementalItemCount(
        totalCount: 205,
        currentCount: 0,
        columnCount: 3,
      ),
      30,
    );
    expect(
      libraryIncrementalItemCount(
        totalCount: 205,
        currentCount: 30,
        columnCount: 3,
      ),
      60,
    );

    final directory = Directory(
      p.join(
        Directory.systemTemp.path,
        'local_tag_player_incremental_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final videos = List<VideoItem>.generate(
      205,
      (index) => _testVideo(
        path: p.join(directory.path, 'video_$index.mp4'),
        title: 'video $index',
      ),
    );
    final thumbnailService = ThumbnailService.forDirectory(
      directory,
      _PreviewFFmpegBackend(),
    );
    VideoItem? openedItem;
    List<VideoItem>? openedQueue;

    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoGrid(
            videos: videos,
            thumbnailService: thumbnailService,
            playbackSettings: PlaybackSettings.defaults,
            dense: true,
            onOpen: (item, playlist) {
              openedItem = item;
              openedQueue = playlist;
            },
            onEditTags: (_) {},
            onToggleFavorite: (_) {},
            onDelete: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    SliverChildBuilderDelegate resultDelegate() => tester
        .widget<ListView>(
          find.byKey(LibrarySmokeKeys.incrementalResults),
        )
        .childrenDelegate as SliverChildBuilderDelegate;

    expect(resultDelegate().estimatedChildCount, 10);
    expect(find.textContaining('第 1 /'), findsNothing);
    final scrollController = tester
        .widget<ListView>(find.byKey(LibrarySmokeKeys.incrementalResults))
        .controller!;
    final firstBatchMaxExtent = scrollController.position.maxScrollExtent;
    scrollController.jumpTo(
      math.max(0, firstBatchMaxExtent - 360),
    );
    expect(scrollController.offset, lessThan(firstBatchMaxExtent));
    await tester.pump();
    await tester.pump();
    expect(resultDelegate().estimatedChildCount, 20);

    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    final offsetBeforeAppend = scrollController.offset;
    await tester.pump();
    await tester.pump();
    expect(resultDelegate().estimatedChildCount, 30);
    expect(scrollController.offset, offsetBeforeAppend);

    scrollController.jumpTo(1200);
    await tester.pump();
    final appendedFirstPath = videos[10].path;
    await tester.tap(
      find.byKey(LibrarySmokeKeys.listPlay(appendedFirstPath)),
    );
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    expect(openedItem, same(videos[10]));
    expect(openedQueue, same(videos));
    expect(openedQueue, hasLength(205));
  });

  testWidgets('library filtering reuses retained card thumbnail state',
      (WidgetTester tester) async {
    final directory = Directory(
      p.join(
        Directory.systemTemp.path,
        'local_tag_player_filter_reuse_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final videos = List<VideoItem>.generate(
      10,
      (index) => _testVideo(
        path: p.join(directory.path, 'video_$index.mp4'),
        title: 'video $index',
      ),
    );
    final visibleCalls = <String, int>{};
    final displayedVideos = ValueNotifier<List<VideoItem>>(videos);
    final thumbnailService = ThumbnailService.forDirectory(
      directory,
      _PreviewFFmpegBackend(),
    );
    addTearDown(displayedVideos.dispose);

    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<List<VideoItem>>(
            valueListenable: displayedVideos,
            builder: (context, currentVideos, _) => VideoGrid(
              videos: currentVideos,
              thumbnailService: thumbnailService,
              playbackSettings: PlaybackSettings.defaults,
              dense: true,
              onVisible: (item) => visibleCalls.update(
                item.videoId,
                (count) => count + 1,
                ifAbsent: () => 1,
              ),
              onOpen: (_, __) {},
              onEditTags: (_) {},
              onToggleFavorite: (_) {},
              onDelete: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final retained = videos[4];
    expect(visibleCalls[retained.videoId], 1);

    displayedVideos.value = videos.sublist(4);
    await tester.pump();
    await tester.pump();

    // retained 从下标 4 移到 0，但同一 State 不应重新请求缩略图或重复报告可见。
    expect(visibleCalls[retained.videoId], 1);
  });

  test('tag discovery starts collapsed and tag selection collapses it', () {
    expect(libraryTagDiscoveryPanelInitiallyOpen, isFalse);
    expect(
      libraryTagDiscoveryPanelOpenAfterMutation(
        currentOpen: true,
        collapseAfterMutation: true,
      ),
      isFalse,
    );
    expect(
      libraryTagDiscoveryPanelOpenAfterMutation(
        currentOpen: true,
        collapseAfterMutation: false,
      ),
      isTrue,
    );
  });

  testWidgets('app mounts', (WidgetTester tester) async {
    await tester.pumpWidget(LocalTagPlayerApp(
      dependencies: createLocalTagPlayerDependencies(),
    ));
    await tester.pump();

    expect(find.byType(LocalTagPlayerApp), findsOneWidget);
  });

  testWidgets('library sidebar collapses to icons and keeps actions reachable',
      (WidgetTester tester) async {
    var pickFolderCount = 0;
    var collapsed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Row(
            children: <Widget>[
              LibrarySidebar(
                roots: const <String>[],
                tags: const <String>[],
                tagGroups: const <TagGroup>[],
                resultCounts: const <String, int>{},
                selectedLocalLibraryPath: null,
                childParentTag: null,
                childTags: const <String>[],
                selectedChildTags: const <String>{},
                selectedGroupTagIds: const <String, Set<String>>{},
                excludedTagIds: const <String>{},
                favoriteCount: 0,
                missingCount: 0,
                favoriteVideosSelected: false,
                recentPlaybackSelected: false,
                localLibrarySelected: false,
                selectedTags: const <String>{},
                isScanning: false,
                dense: false,
                collapsed: collapsed,
                onToggleCollapsed: () => setState(() => collapsed = !collapsed),
                onPickFolder: () => pickFolderCount++,
                onShowAllLibrary: () {},
                onRescan: () {},
                onRemoveLocalLibraryRoot: (_) {},
                onFavoritesToggle: () {},
                onOpenRecentPlayback: () {},
                onOpenLocalLibraryRoot: (_) {},
                onOpenDirectoryManager: () {},
                onOpenMissingRelink: () {},
                onOpenSettings: () {},
                onChildTagToggle: (_) {},
                onClearChildTags: () {},
                onGroupTagToggle: (_) {},
                onGroupTagExcludeToggle: (_) {},
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );

    expect(find.text('媒体库'), findsOneWidget);
    expect(find.text('添加目录'), findsNothing);
    expect(find.byTooltip('新增本地库路径'), findsOneWidget);
    await tester.tap(find.byTooltip('新增本地库路径'));
    await tester.pump();
    expect(pickFolderCount, 1);

    await tester.tap(find.byKey(LibrarySmokeKeys.sidebarCollapseToggle));
    await tester.pumpAndSettle();
    expect(find.text('媒体库'), findsNothing);
    expect(find.byTooltip('媒体库'), findsOneWidget);
    expect(
        tester.getSize(find.byKey(LibrarySmokeKeys.sidebarSurface)).width, 76);

    await tester.tap(find.byKey(LibrarySmokeKeys.sidebarCollapseToggle));
    await tester.pumpAndSettle();
    expect(find.text('媒体库'), findsOneWidget);
  });

  test('reference top bar collapses actions below expanded width', () {
    expect(LayoutBreakpoints.fromWidth(699), LayoutSize.compact);
    expect(LayoutBreakpoints.fromWidth(900), LayoutSize.medium);
    expect(LayoutBreakpoints.fromWidth(1280), LayoutSize.expanded);

    expect(referenceTopBarShouldCollapseActions(LayoutSize.compact), isTrue);
    expect(referenceTopBarShouldCollapseActions(LayoutSize.medium), isTrue);
    expect(referenceTopBarShouldCollapseActions(LayoutSize.expanded), isFalse);

    expect(
      referenceTopBarSearchShouldFillRow(LayoutSize.expanded, 1600),
      isTrue,
    );
    expect(
      referenceTopBarSearchShouldFillRow(LayoutSize.medium, 900),
      isTrue,
    );

    expect(sortModeLabel(SortMode.name), '名称');
    expect(sortModeLabel(SortMode.recent), '日期');
    expect(sortModeLabel(SortMode.type), '类型');
    expect(sortModeLabel(SortMode.size), '大小');
    expect(sortModeLabel(SortMode.folder), '目录');
    expect(sortModeLabel(SortMode.added), '添加时间');
  });

  test('expanded main layout keeps proportional slots while resizing', () {
    final narrow = mainLibraryLayoutSlotsForWidth(1280);
    final regular = mainLibraryLayoutSlotsForWidth(1600);
    final wide = mainLibraryLayoutSlotsForWidth(1920);

    expect(narrow.sidebarWidth, closeTo(256, 0.01));
    expect(narrow.filterPanelWidth, closeTo(409.6, 0.01));
    expect(narrow.contentWidth, greaterThan(600));

    expect(regular.sidebarWidth, greaterThan(narrow.sidebarWidth));
    expect(regular.filterPanelWidth, greaterThan(narrow.filterPanelWidth));
    expect(regular.contentWidth, greaterThan(narrow.contentWidth));

    expect(wide.sidebarWidth / 1920, inInclusiveRange(0.17, 0.18));
    expect(wide.filterPanelWidth / 1920, inInclusiveRange(0.31, 0.33));
    expect(
      wide.sidebarWidth + wide.filterPanelWidth + wide.contentWidth,
      closeTo(1920, 0.01),
    );
  });

  test('player queue visibility detects offscreen locator targets', () {
    const itemExtent = 82.0;
    const viewportExtent = itemExtent * 4;

    expect(
      playerQueueIndexIsVisible(
        index: 0,
        scrollOffset: 0,
        viewportExtent: viewportExtent,
        itemExtent: itemExtent,
      ),
      isTrue,
    );
    expect(
      playerQueueIndexIsVisible(
        index: 5,
        scrollOffset: 0,
        viewportExtent: viewportExtent,
        itemExtent: itemExtent,
      ),
      isFalse,
    );
    expect(
      playerQueueIndexIsVisible(
        index: 5,
        scrollOffset: itemExtent * 4,
        viewportExtent: viewportExtent,
        itemExtent: itemExtent,
      ),
      isTrue,
    );

    expect(
      playerQueueScrollOffsetForIndex(
        index: 500,
        viewportExtent: itemExtent * 4,
        itemExtent: itemExtent,
        minScrollExtent: 0,
        maxScrollExtent: itemExtent * 1000,
        center: true,
      ),
      closeTo(6 + itemExtent * 500 - itemExtent * 1.5, 0.001),
    );
  });

  test('player queue restores full items after programmatic scroll settles',
      () {
    expect(
      playerQueueShouldDeferItem(
        scrollSettled: false,
        recommendsDeferredLoading: true,
      ),
      isTrue,
    );
    expect(
      playerQueueShouldDeferItem(
        scrollSettled: true,
        recommendsDeferredLoading: true,
      ),
      isFalse,
    );
    expect(
      playerQueueShouldDeferItem(
        scrollSettled: false,
        recommendsDeferredLoading: false,
      ),
      isFalse,
    );
  });

  test('player queue sidebar follows blueprint proportions on wide windows',
      () {
    expect(playerQueueLocatorHeight, 48);
    expect(playerQueueSidebarWidthForWindow(960), 360);
    expect(playerQueueSidebarWidthForWindow(1280), 384);
    expect(playerQueueSidebarWidthForWindow(1600), 480);
    expect(playerQueueSidebarWidthForWindow(1920), 500);
  });

  testWidgets('player queue search expands from the count action',
      (tester) async {
    String? submittedQuery;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 384,
            child: PlayerQueueHeader(
              playlistLength: 11165,
              playingIndex: 2,
              onLocateSelected: () {},
              onDeleteSelected: () {},
              onSearch: (query) => submittedQuery = query,
            ),
          ),
        ),
      ),
    );

    const positionKey = ValueKey('player.queue.position');
    const searchToggleKey = ValueKey('player.queue.search.toggle');
    const locateKey = ValueKey('player.queue.locate.selected');
    const deleteKey = ValueKey('player.queue.delete.selected');
    const searchFieldKey = ValueKey('player.queueSearch');
    final position = find.byKey(positionKey);
    final searchToggle = find.byKey(searchToggleKey);
    final locate = find.byKey(locateKey);
    final delete = find.byKey(deleteKey);

    expect(find.byKey(searchFieldKey), findsNothing);
    expect(tester.getCenter(position).dx,
        lessThan(tester.getCenter(searchToggle).dx));
    expect(tester.getCenter(searchToggle).dx,
        lessThan(tester.getCenter(locate).dx));
    expect(tester.getCenter(locate).dx, lessThan(tester.getCenter(delete).dx));

    await tester.tap(searchToggle);
    await tester.pump();

    expect(find.byKey(searchFieldKey), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byKey(searchFieldKey)).autofocus, isTrue);
    await tester.enterText(find.byKey(searchFieldKey), 'clip');
    await tester.tap(find.byKey(const ValueKey('player.queueSearchSubmit')));
    expect(submittedQuery, 'clip');

    await tester.tap(searchToggle);
    await tester.pump();
    expect(find.byKey(searchFieldKey), findsNothing);
  });

  testWidgets('player delete dialog keeps recycle-bin action explicit',
      (tester) async {
    final item = _testVideo(path: r'X:\test-media\clip.mp4', title: 'clip');
    Object? result = 'pending';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showPlayerDeleteConfirmationDialog(context, item);
            },
            child: const Text('打开删除确认'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开删除确认'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(find.text('仅移出媒体库'), findsOneWidget);
    await tester.tap(find.text('仅移出媒体库'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    result = 'pending';
    await tester.tap(find.text('打开删除确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同时将本地视频移入回收站'));
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await tester.tap(find.text('移入回收站并移除记录'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('player side panel switches between queue and current details',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var editCount = 0;
    final item = VideoItem(
      path: r'X:\test-media\原神\雷神\clip.mp4',
      title: 'clip',
      folder: r'X:\test-media\原神\雷神',
      tags: <String>{'原神', '雷神'},
      addedAt: DateTime.utc(2026, 7, 14),
      fileSize: 307 * 1024 * 1024,
      playbackDuration: const Duration(minutes: 2),
      mediaDetails: const MediaDetails(
        videoCodec: 'h264',
        audioCodec: 'aac',
        width: 1920,
        height: 1080,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: PlayerSidePanel(
              queuePanel: const Center(child: Text('筛选结果列表测试')),
              item: item,
              queueEndReached: false,
              onToggleFavorite: () {},
              onEditManualTags: () => editCount++,
              onRevealFile: () {},
              onVideoInfo: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('筛选结果列表测试'), findsOneWidget);
    expect(find.text('当前视频详情'), findsNothing);
    final segmentSize = tester.getSize(
      find.byKey(const ValueKey('player.sidebar.tabs.segment')),
    );
    final queueSurfaceSize = tester.getSize(
      find.byKey(const ValueKey('player.sidebar.tab.queue.surface')),
    );
    final detailsSurfaceSize = tester.getSize(
      find.byKey(const ValueKey('player.sidebar.tab.details.surface')),
    );
    expect(segmentSize.height, 34);
    expect(queueSurfaceSize.height, segmentSize.height);
    expect(detailsSurfaceSize.height, segmentSize.height);
    final initialQueueDecoration = tester
        .widget<AnimatedContainer>(
          find.byKey(
            const ValueKey('player.sidebar.tab.queue.surface'),
          ),
        )
        .decoration as BoxDecoration;
    final initialDetailsDecoration = tester
        .widget<AnimatedContainer>(
          find.byKey(
            const ValueKey('player.sidebar.tab.details.surface'),
          ),
        )
        .decoration as BoxDecoration;
    expect(initialQueueDecoration.gradient, isA<LinearGradient>());
    expect(initialDetailsDecoration.gradient, isNull);

    await tester.tap(find.byKey(const ValueKey('player.sidebar.tab.details')));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('筛选结果列表测试'), findsNothing);
    expect(find.text('当前视频详情'), findsOneWidget);
    final selectedDetailsDecoration = tester
        .widget<AnimatedContainer>(
          find.byKey(
            const ValueKey('player.sidebar.tab.details.surface'),
          ),
        )
        .decoration as BoxDecoration;
    expect(selectedDetailsDecoration.gradient, isA<LinearGradient>());
    expect(find.text('clip.mp4'), findsOneWidget);
    expect(find.text('1920×1080'), findsOneWidget);
    expect(find.text('H264 / AAC'), findsOneWidget);
    expect(find.text('原神'), findsOneWidget);
    expect(find.text('雷神'), findsOneWidget);

    await tester
        .ensureVisible(find.byKey(const ValueKey('player.editManualTags')));
    await tester.tap(find.byKey(const ValueKey('player.editManualTags')));
    await tester.pump();
    expect(editCount, 1);

    await tester.tap(find.byKey(const ValueKey('player.sidebar.tab.queue')));
    await tester.pump();
    expect(find.text('筛选结果列表测试'), findsOneWidget);
    expect(find.text('当前视频详情'), findsNothing);
  });

  test('tag accordion children are scoped to their parent tag', () {
    const genshin = TagItem(
      id: 'folder.primary:genshin',
      name: '原神',
      source: TagSource.folder,
      groupId: 'folder.primary',
    );
    const honkai = TagItem(
      id: 'folder.primary:honkai',
      name: '崩坏三',
      source: TagSource.folder,
      groupId: 'folder.primary',
    );
    const lisa = TagItem(
      id: 'folder.child:genshin:lisa',
      name: '丽莎',
      source: TagSource.folder,
      groupId: 'folder.child',
      parentId: '原神',
      usageCount: 12,
    );
    const kiana = TagItem(
      id: 'folder.child:honkai:kiana',
      name: '琪亚娜',
      source: TagSource.folder,
      groupId: 'folder.child',
      parentId: '崩坏三',
      usageCount: 30,
    );

    final mapping = childTagItemsByParentId(
      const [genshin, honkai, lisa, kiana],
      TagQueryContext(tagsById: {
        genshin.id: genshin,
        honkai.id: honkai,
        lisa.id: lisa,
        kiana.id: kiana,
      }),
    );

    expect(strictChildItemsForParent(genshin, mapping), [lisa]);
    expect(strictChildItemsForParent(honkai, mapping), [kiana]);
  });

  test('tag discovery separates primary and secondary candidates', () {
    const genshin = TagItem(
      id: 'folder.primary:genshin',
      name: '原神',
      source: TagSource.folder,
      groupId: 'folder.primary',
    );
    const lisa = TagItem(
      id: 'folder.child:genshin:lisa',
      name: '丽莎',
      source: TagSource.folder,
      groupId: 'folder.child',
      parentId: '原神',
    );
    const yae = TagItem(
      id: 'folder.child:genshin:yae',
      name: '八重神子',
      source: TagSource.folder,
      groupId: 'folder.child',
      parentId: '原神',
    );
    const manual = TagItem(
      id: 'manual:剧情',
      name: '剧情',
      source: TagSource.manual,
      groupId: 'manual',
    );
    const pollutedChildInPrimaryGroup = TagItem(
      id: 'folder.child:genshin:polluted',
      name: '污染二级',
      source: TagSource.folder,
      groupId: 'folder.primary',
      parentId: '原神',
    );
    const pollutedManualInPrimaryGroup = TagItem(
      id: 'folder.primary:manual',
      name: '手动污染',
      source: TagSource.manual,
      groupId: 'folder.primary',
    );
    const groups = [
      TagGroup(
        id: 'folder.primary',
        name: '一级标签',
        items: [
          genshin,
          pollutedChildInPrimaryGroup,
          pollutedManualInPrimaryGroup
        ],
      ),
      TagGroup(id: 'folder.child', name: '二级标签', items: [lisa, yae]),
      TagGroup(id: 'manual', name: '手动标签', items: [manual]),
    ];

    expect(primaryTagGroupsForDiscovery(groups).single.items, [genshin]);
    expect(
      secondaryTagsForDiscovery(groups, {
        lisa.id: 3,
        yae.id: 9,
        manual.id: 99,
      }),
      [yae, lisa],
    );
  });

  test('folder discovery derives hierarchy from library root paths', () {
    final item = VideoItem(
      path: r'X:\test-media\崩坏三\李素裳\clip.mp4',
      title: 'clip',
      folder: r'X:\test-media\崩坏三\李素裳',
      rootPath: r'X:\test-media\崩坏三',
      tags: {'李素裳'},
      childTags: const {
        '李素裳': {'默认专辑'},
      },
      addedAt: DateTime.utc(2026, 7, 8),
    );
    final groups = folderTagGroupsFromLibraryPaths(
      videos: [item],
      roots: const [r'X:\test-media', r'X:\test-media\崩坏三'],
      templates: const [
        TagGroup(id: 'folder.primary', name: '一级标签', items: []),
        TagGroup(id: 'folder.child', name: '二级标签', items: []),
      ],
    );
    final primary = groups.firstWhere((group) => group.id == 'folder.primary');
    final child = groups.firstWhere((group) => group.id == 'folder.child');

    expect(primary.items.map((tag) => tag.name), ['崩坏三']);
    expect(
        child.items.map((tag) => '${tag.parentId}/${tag.name}'), ['崩坏三/李素裳']);
  });

  test('folder filter matches hierarchy derived from current library roots',
      () {
    final item = VideoItem(
      path: r'X:\test-media\鸣潮\尤诺\clip.mp4',
      title: 'clip',
      folder: r'X:\test-media\鸣潮\尤诺',
      rootPath: r'X:\test-media\鸣潮',
      tags: {'尤诺'},
      childTags: const {
        '尤诺': {'默认专辑'},
      },
      addedAt: DateTime.utc(2026, 7, 8),
    );
    final query = FilterQuery(
      primaryTagId: '鸣潮',
      childTagId: '尤诺',
      folderRoots: const [r'X:\test-media', r'X:\test-media\鸣潮'],
    );

    expect(query.matches(item), isTrue);
  });

  testWidgets('primary discovery tab does not render secondary tag cloud',
      (tester) async {
    await tester.pumpWidget(const TagDiscoverySmokeHarness(childCount: 12));

    expect(find.byKey(LibrarySmokeKeys.primaryTab), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Child01'), findsNothing);
  });

  test('library sort comparator applies default order immediately', () {
    final older = VideoItem(
      path: 'D:\\video\\older.mp4',
      title: 'B',
      folder: 'D:\\video',
      tags: const {},
      addedAt: DateTime.utc(2026, 1, 1),
      modifiedMs: DateTime.utc(2026, 1, 3).millisecondsSinceEpoch,
      lastPlayedAt: DateTime.utc(2026, 7, 8),
    );
    final newer = VideoItem(
      path: 'D:\\video\\newer.mp4',
      title: 'A',
      folder: 'D:\\video',
      tags: const {},
      addedAt: DateTime.utc(2026, 2, 1),
      modifiedMs: DateTime.utc(2026, 1, 2).millisecondsSinceEpoch,
    );

    final videos = [older, newer]..sort((a, b) => compareLibraryVideosForSort(
          a,
          b,
          sortMode: SortMode.recent,
          sortDirection: SortDirection.descending,
        ));
    expect(videos, [older, newer]);

    videos.sort((a, b) => compareLibraryVideosForSort(
          a,
          b,
          sortMode: SortMode.name,
          sortDirection: SortDirection.ascending,
        ));
    expect(videos, [newer, older]);
  });

  test('library sort comparator follows Windows style fields', () {
    final video2 = VideoItem(
      path: 'D:\\video\\B\\video2.mp4',
      title: 'video2',
      folder: 'D:\\video\\B',
      tags: const {},
      fileSize: 200,
      modifiedMs: DateTime.utc(2026, 1, 2).millisecondsSinceEpoch,
      addedAt: DateTime.utc(2026, 1, 10),
    );
    final video10 = VideoItem(
      path: 'D:\\video\\A\\video10.avi',
      title: 'video10',
      folder: 'D:\\video\\A',
      tags: const {},
      fileSize: 100,
      modifiedMs: DateTime.utc(2026, 1, 3).millisecondsSinceEpoch,
      addedAt: DateTime.utc(2026, 1, 1),
    );

    expect(
      sortedLibraryVideos(
        [video10, video2],
        sortMode: SortMode.name,
        sortDirection: SortDirection.ascending,
      ),
      [video2, video10],
    );
    expect(
      sortedLibraryVideos(
        [video2, video10],
        sortMode: SortMode.type,
        sortDirection: SortDirection.ascending,
      ),
      [video10, video2],
    );
    expect(
      sortedLibraryVideos(
        [video2, video10],
        sortMode: SortMode.size,
        sortDirection: SortDirection.ascending,
      ),
      [video10, video2],
    );
    expect(
      sortedLibraryVideos(
        [video2, video10],
        sortMode: SortMode.recent,
        sortDirection: SortDirection.descending,
      ),
      [video10, video2],
    );
    expect(
      sortedLibraryVideos(
        [video2, video10],
        sortMode: SortMode.added,
        sortDirection: SortDirection.descending,
      ),
      [video2, video10],
    );
  });

  test('library sort preferences persist outside playback settings', () async {
    final directory = await Directory.systemTemp.createTemp('ltp_sort_pref_');
    addTearDown(() async {
      await directory.delete(recursive: true);
    });
    final paths = AppPaths(dataDirectoryOverride: directory);

    const preferences = LibrarySortPreferences(
      mode: SortMode.folder,
      direction: SortDirection.ascending,
    );
    await saveLibrarySortPreferences(paths, preferences);
    final loaded = await loadLibrarySortPreferences(paths);

    expect(loaded.mode, SortMode.folder);
    expect(loaded.direction, SortDirection.ascending);
    expect(await paths.settingsFile(),
        isNot(await paths.librarySortPreferencesFile()));
  });

  testWidgets('playback decoder dropdown only changes after confirmation',
      (tester) async {
    PlaybackSettings? savedSettings;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackDecoderDropdown(
            settings: PlaybackSettings.defaults,
            onChanged: (settings) async {
              savedSettings = settings;
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('高级选项'));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byType(DropdownButtonFormField<String>).last);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text(PlaybackSettings.labelFor('d3d11va')).last);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('切换播放解码'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(savedSettings, isNull);
    expect(
      (tester
              .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>).first,
              )
              .key! as ValueKey<String>)
          .value,
      startsWith('common:auto-safe:'),
    );
    expect(find.text(PlaybackSettings.labelFor('d3d11va')), findsNothing);

    await tester
        .ensureVisible(find.byType(DropdownButtonFormField<String>).last);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text(PlaybackSettings.labelFor('d3d11va')).last);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('确认切换'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(savedSettings?.hwdec, 'd3d11va');
    expect(
      (tester
              .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>).last,
              )
              .key! as ValueKey<String>)
          .value,
      startsWith('advanced:d3d11va:'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackDecoderDropdown(
            settings: savedSettings!,
            onChanged: (settings) async {
              savedSettings = settings;
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      (tester
              .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>).last,
              )
              .key! as ValueKey<String>)
          .value,
      startsWith('advanced:d3d11va:'),
    );
  });

  test('playback settings default to continuing without a prompt', () {
    expect(
      PlaybackSettings.defaults.resumeBehavior,
      PlaybackResumeBehavior.continueWatching,
    );
    final ask = PlaybackSettings.fromJson({
      'hwdec': 'no',
      'resumeBehavior': 'ask',
    });
    expect(ask.resumeBehavior, PlaybackResumeBehavior.ask);
    expect(ask.toJson()['resumeBehavior'], 'ask');
    expect(
      ask.copyWith(hwdec: 'auto-safe').resumeBehavior,
      PlaybackResumeBehavior.ask,
    );
  });

  test('playback settings preserve custom shortcut bindings safely', () {
    final settings = PlaybackSettings.fromJson({
      'hwdec': 'auto-safe',
      'resumeBehavior': 'continueWatching',
      'shortcuts': {'playPause': 'F', 'fullscreen': 'Space'},
    });
    expect(settings.shortcuts[PlayerShortcutAction.playPause], 'F');
    expect(settings.shortcuts[PlayerShortcutAction.fullscreen], 'Space');
    expect(settings.shortcuts[PlayerShortcutAction.screenshot], 'S');
    expect(settings.toJson()['shortcuts'], isA<Map>());
    expect(settings.fullscreenQueueEdgeWidth, 12);
    expect(settings.fullscreenQueueHideDelayMs, 180);
  });

  test('playback visual settings persist with safe backward-compatible values',
      () async {
    final oldSettings = PlaybackSettings.fromJson({'hwdec': 'auto-safe'});
    expect(oldSettings.mirrorVideo, isFalse);
    expect(oldSettings.playbackMode, PlayerPlaybackMode.sequential);
    expect(oldSettings.videoAspectMode, PlayerVideoAspectMode.automatic);
    expect(oldSettings.playbackRate, 1);

    final directory = await Directory.systemTemp.createTemp(
      'local_tag_player_playback_settings_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final paths = AppPaths(dataDirectoryOverride: directory);
    final changed = oldSettings.copyWith(
      mirrorVideo: true,
      playbackMode: PlayerPlaybackMode.repeatAll,
      videoAspectMode: PlayerVideoAspectMode.cover,
      playbackRate: 1.5,
    );
    await changed.save(paths);
    final loaded = await PlaybackSettings.load(paths);

    expect(loaded.mirrorVideo, isTrue);
    expect(loaded.playbackMode, PlayerPlaybackMode.repeatAll);
    expect(loaded.videoAspectMode, PlayerVideoAspectMode.cover);
    expect(loaded.playbackRate, 1.5);
    expect(loaded.toJson()['playbackMode'], 'repeatAll');
    expect(loaded.toJson()['videoAspectMode'], 'cover');

    final unsafe = PlaybackSettings.fromJson({
      'playbackMode': 'unknown',
      'videoAspectMode': 'stretched',
      'playbackRate': 9,
    });
    expect(unsafe.playbackMode, PlayerPlaybackMode.sequential);
    expect(unsafe.videoAspectMode, PlayerVideoAspectMode.automatic);
    expect(unsafe.playbackRate, 1);
  });

  test('persisted visual settings are applied to the playback backend',
      () async {
    final backend = _PreferenceRecordingPlayerBackend();

    await applyPlayerOpenPreferences(
      backend: backend,
      videoAspectMode: PlayerVideoAspectMode.cover,
      playbackRate: 1.5,
    );

    expect(backend.properties['video-aspect-override'], '-1');
    expect(backend.properties['panscan'], '1.0');
    expect(backend.properties['video-zoom'], '0');
    expect(backend.rates, <double>[1.5]);
  });

  test('playback settings clamp fullscreen queue interaction values', () {
    final settings = PlaybackSettings.fromJson({
      'fullscreenQueueEdgeWidth': 99,
      'fullscreenQueueHideDelayMs': -20,
    });
    expect(settings.fullscreenQueueEdgeWidth, 40);
    expect(settings.fullscreenQueueHideDelayMs, 0);
    final changed = settings.copyWith(
      fullscreenQueueEdgeWidth: 20,
      fullscreenQueueHideDelayMs: 450,
    );
    expect(changed.toJson()['fullscreenQueueEdgeWidth'], 20);
    expect(changed.toJson()['fullscreenQueueHideDelayMs'], 450);
    final reset = changed.resetFullscreenQueueInteraction();
    expect(reset.fullscreenQueueEdgeWidth, 12);
    expect(reset.fullscreenQueueHideDelayMs, 180);
    expect(reset.hwdec, changed.hwdec);
    expect(reset.resumeBehavior, changed.resumeBehavior);
    expect(reset.shortcuts, changed.shortcuts);
  });

  test('desktop window layout rejects unsafe tiny snapshots', () {
    expect(
      DesktopWindowLayout.fromJson(
        <String, Object?>{'width': 640, 'height': 480, 'maximized': false},
      ),
      isNull,
    );
    final layout = DesktopWindowLayout.fromJson(
      <String, Object?>{'width': 1440, 'height': 900, 'maximized': true},
    );
    expect(layout?.width, 1440);
    expect(layout?.height, 900);
    expect(layout?.maximized, isTrue);
  });

  test('library sort helper applies to every video source list', () {
    final alpha = VideoItem(
      path: 'D:\\video\\B\\alpha.mp4',
      title: 'Alpha',
      folder: 'D:\\video\\B',
      tags: const {},
      isFavorite: true,
      addedAt: DateTime.utc(2026, 1, 3),
      lastPlayedAt: DateTime.utc(2026, 7, 8),
    );
    final beta = VideoItem(
      path: 'D:\\video\\A\\beta.mp4',
      title: 'Beta',
      folder: 'D:\\video\\A',
      tags: const {},
      isFavorite: true,
      addedAt: DateTime.utc(2026, 1, 1),
      lastPlayedAt: DateTime.utc(2026, 7, 9),
    );
    final filtered = [alpha, beta];
    final favorites = filtered.where((item) => item.isFavorite);
    final recent = filtered.where((item) => item.lastPlayedAt != null);

    for (final source in [filtered, favorites, recent]) {
      expect(
        sortedLibraryVideos(
          source,
          sortMode: SortMode.folder,
          sortDirection: SortDirection.ascending,
        ),
        [beta, alpha],
      );
    }
  });

  test('player playback controller keeps queue stable on child switches', () {
    final alpha = VideoItem(
      path: 'D:\\video\\alpha.mp4',
      title: 'alpha',
      folder: 'D:\\video',
      tags: {'Series'},
      addedAt: DateTime.utc(2026, 1, 1),
      childTags: {
        'Series': {'AlbumA'},
      },
    );
    final beta = VideoItem(
      path: 'D:\\video\\beta.mp4',
      title: 'beta',
      folder: 'D:\\video',
      tags: {'Series'},
      addedAt: DateTime.utc(2026, 1, 2),
      childTags: {
        'Series': {'AlbumB'},
      },
    );
    final playback = PlayerPlaybackController(
      sourcePlaylist: [alpha, beta],
      activeParentTag: 'Series',
      initialPath: alpha.path,
    );

    expect(playback.previousIndex, isNull);
    expect(playback.nextIndex, 1);

    // 单击语义只移动选择，不改变正在播放项；双击/Enter 才调用 jumpTo 对齐两者。
    expect(playback.select(1), isTrue);
    expect(playback.playingIndex, 0);
    expect(playback.selectedIndex, 1);
    expect(playback.jumpTo(playback.selectedIndex), isTrue);
    expect(playback.playingIndex, 1);
    expect(playback.selectedIndex, 1);
    playback.jumpTo(0);

    playback.toggleChildTag('AlbumB', preferredPath: alpha.path);
    expect(playback.queue, [beta]);
    expect(playback.currentItem, beta);

    playback.toggleChildTag('AlbumB', preferredPath: beta.path);
    expect(playback.queue, [alpha, beta]);
    expect(playback.currentItem, beta);

    playback.setPlaylistForChildTag('Missing', preferredPath: beta.path);
    expect(playback.queue, [alpha, beta]);
    expect(playback.currentItem, beta);
    expect(playback.previousIndex, 0);
    expect(playback.nextIndex, isNull);
  });

  test('player playback controller stops sequential continuation at queue end',
      () {
    final first = VideoItem(
      path: 'D:\\video\\first.mp4',
      title: 'first',
      folder: 'D:\\video',
      tags: const {},
      addedAt: DateTime.utc(2026, 1, 1),
    );
    final second = VideoItem(
      path: 'D:\\video\\second.mp4',
      title: 'second',
      folder: 'D:\\video',
      tags: const {},
      addedAt: DateTime.utc(2026, 1, 2),
    );
    final playback = PlayerPlaybackController(
      sourcePlaylist: [first, second],
      activeParentTag: null,
      initialPath: first.path,
    );

    expect(playback.nextIndex, 1);
    expect(playback.jumpTo(playback.nextIndex!), isTrue);
    expect(playback.currentItem, second);
    expect(playback.nextIndex, isNull);
    expect(playback.queue, [first, second]);
  });

  test(
      'player playback controller deletes queue items without changing identity',
      () {
    VideoItem item(String name) => VideoItem(
          path: 'D:\\video\\$name.mp4',
          title: name,
          folder: 'D:\\video',
          tags: const {},
          addedAt: DateTime.utc(2026, 1, 1),
        );

    final first = item('first');
    final second = item('second');
    final third = item('third');
    final playback = PlayerPlaybackController(
      sourcePlaylist: [first, second, third],
      activeParentTag: null,
      initialPath: second.path,
    );

    expect(playback.removeItemAt(0), isFalse);
    expect(playback.currentItem, second);
    expect(playback.playingIndex, 0);
    expect(playback.queue, [second, third]);

    expect(playback.removeItemAt(0), isTrue);
    expect(playback.currentItem, third);
    expect(playback.selectedIndex, playback.playingIndex);
    expect(playback.sourcePlaylist, [third]);
  });

  test('player completion modes preserve filtered queue boundaries', () {
    expect(
      playerCompletionTargetIndex(
        mode: PlayerPlaybackMode.sequential,
        currentIndex: 2,
        queueLength: 3,
      ),
      isNull,
    );
    expect(
      playerCompletionTargetIndex(
        mode: PlayerPlaybackMode.repeatOne,
        currentIndex: 1,
        queueLength: 3,
      ),
      1,
    );
    expect(
      playerCompletionTargetIndex(
        mode: PlayerPlaybackMode.repeatAll,
        currentIndex: 2,
        queueLength: 3,
      ),
      0,
    );
    expect(
      playerCompletionTargetIndex(
        mode: PlayerPlaybackMode.shuffle,
        currentIndex: 1,
        queueLength: 3,
        randomValue: 0,
      ),
      0,
    );
    expect(
      playerCompletionTargetIndex(
        mode: PlayerPlaybackMode.shuffle,
        currentIndex: 1,
        queueLength: 3,
        randomValue: 0.99,
      ),
      2,
    );
  });

  testWidgets('advanced player settings only expose aspect and speed routes',
      (tester) async {
    var aspectOpened = false;
    var rateOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: PlayerSettingsAdvancedList(
              videoAspectMode: PlayerVideoAspectMode.automatic,
              playbackRate: 1,
              onShowVideoAspect: () => aspectOpened = true,
              onShowPlaybackRate: () => rateOpened = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('播放方式'), findsNothing);
    expect(find.text('视频比例'), findsOneWidget);
    expect(find.text('播放速度'), findsOneWidget);
    expect(find.text('快捷键'), findsNothing);
    expect(find.text('播放诊断'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('player.settings.aspect.open')),
    );
    await tester.tap(
      find.byKey(const ValueKey('player.settings.rate.open')),
    );

    expect(aspectOpened, isTrue);
    expect(rateOpened, isTrue);
    expect(PlayerVideoAspectMode.automatic.mpvAspectOverride, '-1');
    expect(PlayerVideoAspectMode.ratio4x3.mpvAspectOverride, '4:3');
    expect(PlayerVideoAspectMode.ratio16x9.mpvAspectOverride, '16:9');
    expect(PlayerVideoAspectMode.cover.mpvPanscan, '1.0');
    expect(PlayerVideoAspectMode.automatic.surfaceFit, BoxFit.contain);
    expect(PlayerVideoAspectMode.cover.surfaceFit, BoxFit.cover);
    expect(PlayerVideoAspectMode.ratio4x3.surfaceAspectRatio,
        closeTo(4 / 3, 0.001));
    expect(PlayerVideoAspectMode.ratio16x9.surfaceAspectRatio,
        closeTo(16 / 9, 0.001));
  });

  testWidgets('player settings use compact primary and advanced pages',
      (tester) async {
    bool? mirrorVideo;
    PlayerPlaybackMode? selectedPlaybackMode;
    PlayerVideoAspectMode? selectedAspectMode;
    double? selectedRate;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: IconButton(
                key: const ValueKey('test.player.settings.open'),
                onPressed: () => showPlayerSettingsDialog(
                  context,
                  anchorRect: const Rect.fromLTWH(720, 520, 40, 40),
                  mirrorVideo: false,
                  playbackMode: PlayerPlaybackMode.sequential,
                  videoAspectMode: PlayerVideoAspectMode.automatic,
                  playbackRate: 1,
                  playbackRates: const <double>[0.5, 1, 1.5],
                  onMirrorVideoChanged: (enabled) {
                    mirrorVideo = enabled;
                  },
                  onPlaybackModeChanged: (mode) {
                    selectedPlaybackMode = mode;
                  },
                  onVideoAspectModeChanged: (mode) {
                    selectedAspectMode = mode;
                  },
                  onPlaybackRateChanged: (rate) {
                    selectedRate = rate;
                  },
                ),
                icon: const Icon(Icons.settings_outlined),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('test.player.settings.open')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player.settings.open.fade')),
      findsOneWidget,
    );
    final openingScale = tester.widget<ScaleTransition>(
      find.byKey(const ValueKey('player.settings.open.scale')),
    );
    expect(openingScale.scale.value, closeTo(0.94, 0.01));
    await tester.pump(const Duration(milliseconds: 90));
    expect(openingScale.scale.value, greaterThan(0.94));
    expect(openingScale.scale.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('player.settings.dialog')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('player.settings.shell'))).width,
      closeTo(300, 0.1),
    );
    final primaryRect =
        tester.getRect(find.byKey(const ValueKey('player.settings.shell')));
    expect(primaryRect.right, closeTo(760, 0.1));
    expect(primaryRect.bottom, closeTo(512, 0.1));
    expect(
      find.byKey(const ValueKey('player.settings.close')),
      findsNothing,
    );
    expect(find.text('镜像画面'), findsOneWidget);
    expect(find.text('单曲循环'), findsOneWidget);
    expect(find.text('列表循环'), findsOneWidget);
    expect(find.text('更多播放设置'), findsOneWidget);
    expect(find.text('视频比例'), findsNothing);
    expect(find.text('播放速度'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('player.settings.mirror')),
    );
    await tester.pump();
    expect(mirrorVideo, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('player.settings.repeatOne')),
    );
    await tester.pump();
    expect(selectedPlaybackMode, PlayerPlaybackMode.repeatOne);

    await tester.tap(
      find.byKey(const ValueKey('player.settings.repeatAll')),
    );
    await tester.pump();
    expect(selectedPlaybackMode, PlayerPlaybackMode.repeatAll);

    await tester.tap(
      find.byKey(const ValueKey('player.settings.advanced.open')),
    );
    await tester.pump(const Duration(milliseconds: 90));
    expect(find.byType(SlideTransition), findsWidgets);
    expect(
      find.byKey(const ValueKey('player.settings.primary.page')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('player.settings.advanced.page')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('player.settings.shell'))).width,
      closeTo(300, 0.1),
    );
    expect(find.text('更多播放设置'), findsOneWidget);
    expect(find.text('视频比例'), findsOneWidget);
    expect(find.text('播放速度'), findsOneWidget);
    expect(find.text('播放方式'), findsNothing);
    expect(find.text('快捷键'), findsNothing);
    expect(find.text('播放诊断'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('player.settings.aspect.open')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('player.settings.aspect.page')),
      findsOneWidget,
    );
    expect(find.text('视频比例'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('player.settings.aspect.cover')),
    );
    await tester.pump();
    expect(selectedAspectMode, PlayerVideoAspectMode.cover);
    expect(
        find.byKey(const ValueKey('player.settings.dialog')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player.settings.back')));
    await tester.pumpAndSettle();
    expect(find.text('更多播放设置'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('player.settings.rate.open')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('player.settings.rate.page')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('player.settings.rate.1.5')),
    );
    await tester.pump();
    expect(selectedRate, 1.5);

    await tester.tap(find.byKey(const ValueKey('player.settings.back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('player.settings.back')));
    await tester.pumpAndSettle();
    expect(find.text('镜像画面'), findsOneWidget);
    expect(find.text('视频比例'), findsNothing);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player.settings.dialog')), findsNothing);
  });

  test('player controls hide only outside controls and settings', () {
    expect(
      playerPointerInControlBar(localY: 500, surfaceHeight: 700),
      isFalse,
    );
    expect(
      playerPointerInControlBar(localY: 600, surfaceHeight: 700),
      isTrue,
    );
    expect(
      playerControlsShouldAutoHide(
        settingsOpen: false,
        pointerInControlBar: false,
      ),
      isTrue,
    );
    expect(
      playerControlsShouldAutoHide(
        settingsOpen: true,
        pointerInControlBar: false,
      ),
      isFalse,
    );
    expect(
      playerControlsShouldAutoHide(
        settingsOpen: false,
        pointerInControlBar: true,
      ),
      isFalse,
    );
  });

  test('player queue swipe actions snap smoothly by distance and velocity', () {
    expect(
      playerQueueActionShouldOpen(
        progress: 0.5,
        horizontalVelocity: 0,
      ),
      isTrue,
    );
    expect(
      playerQueueActionShouldOpen(
        progress: 0.2,
        horizontalVelocity: -500,
      ),
      isTrue,
    );
    expect(
      playerQueueActionShouldOpen(
        progress: 0.8,
        horizontalVelocity: 500,
      ),
      isFalse,
    );
  });

  test('player open request controller keeps latest request after failure', () {
    final requests = PlayerOpenRequestController();

    expect(requests.request('first.mp4'), isTrue);
    requests.beginDrain();
    expect(requests.takePendingPath(), 'first.mp4');
    expect(requests.request('second.mp4'), isFalse);
    expect(requests.hasPending, isTrue);

    requests.finishDrain(keepOpening: true);
    expect(requests.isOpening, isTrue);
    expect(requests.takePendingPath(), 'second.mp4');

    requests.finishDrain(keepOpening: false);
    expect(requests.isOpening, isFalse);
    expect(requests.hasPending, isFalse);
  });

  test('player open request controller keeps recoverable safe failure state',
      () {
    final requests = PlayerOpenRequestController();

    requests.markFailure('D:\\private\\broken.mp4', code: 'StateError');
    expect(requests.hasFailure, isTrue);
    expect(requests.failureCode, 'StateError');

    expect(requests.retryFailure(), isTrue);
    expect(requests.hasFailure, isFalse);
    requests.beginDrain();
    expect(requests.takePendingPath(), 'D:\\private\\broken.mp4');
    requests.markFailure('D:\\private\\broken.mp4', code: 'StateError');
    requests.markSuccess();
    requests.finishDrain(keepOpening: false);

    expect(requests.hasFailure, isFalse);
    expect(requests.failureCode, isNull);
  });

  test('player media readiness rejects zero-duration media without codecs', () {
    expect(
      playerMediaStateIsPlayable(
        duration: Duration.zero,
        videoCodec: 'empty',
        audioCodec: 'unavailable',
      ),
      isFalse,
    );
    expect(
      playerMediaStateIsPlayable(
        duration: const Duration(seconds: 2),
        videoCodec: 'empty',
        audioCodec: 'empty',
      ),
      isTrue,
    );
    expect(
      playerMediaStateIsPlayable(
        duration: Duration.zero,
        videoCodec: 'h264',
        audioCodec: 'empty',
      ),
      isTrue,
    );
  });

  test('player resume position rejects queue-end progress', () {
    expect(
      playerResumePosition(
        saved: const Duration(seconds: 37),
        duration: const Duration(minutes: 2),
      ),
      const Duration(seconds: 37),
    );
    expect(
      playerResumePosition(
        saved: const Duration(seconds: 58),
        duration: const Duration(minutes: 1),
      ),
      isNull,
    );
    expect(
      playerResumePosition(
        saved: const Duration(seconds: 18),
        duration: const Duration(seconds: 20),
      ),
      isNull,
    );
    expect(
      playerResumePosition(
        saved: const Duration(seconds: 2),
        duration: const Duration(seconds: 20),
      ),
      isNull,
    );
    expect(
      playerResumePosition(
        saved: const Duration(seconds: 20),
        duration: const Duration(minutes: 2),
        completed: true,
      ),
      isNull,
    );
  });

  test('continue watching requires meaningful unfinished stable progress', () {
    final item = _testVideo(path: 'C:/queue/continue.mp4', title: 'Continue')
      ..lastPlayedAt = DateTime.utc(2026, 7, 11)
      ..playbackPosition = const Duration(seconds: 30)
      ..playbackDuration = const Duration(minutes: 2);
    expect(videoIsContinueWatching(item), isTrue);
    expect(videoPlaybackProgressFraction(item), closeTo(0.25, 0.001));

    item.playbackCompleted = true;
    expect(videoIsContinueWatching(item), isFalse);
    item
      ..playbackCompleted = false
      ..playbackPosition = const Duration(seconds: 119);
    expect(videoIsContinueWatching(item), isFalse);
  });

  test('playback snapshot queue coalesces by videoId and writes serially',
      () async {
    final firstWriteGate = Completer<void>();
    final writes = <Duration>[];
    var activeWriters = 0;
    var maxActiveWriters = 0;
    final queue = PlaybackSnapshotWriteQueue(
      writer: (snapshot) async {
        activeWriters++;
        maxActiveWriters = math.max(maxActiveWriters, activeWriters);
        writes.add(snapshot.position);
        if (writes.length == 1) {
          await firstWriteGate.future;
        }
        activeWriters--;
      },
    );
    final item = _testVideo(path: 'C:/queue/snapshot.mp4', title: 'Snapshot');
    PlaybackSnapshot snapshot(int seconds) => PlaybackSnapshot(
          item: item,
          position: Duration(seconds: seconds),
          duration: const Duration(minutes: 2),
          completed: false,
          updatedAt: DateTime.utc(2026, 7, 11, 14, 30, seconds),
        );

    queue.enqueue(snapshot(1));
    await Future<void>.delayed(Duration.zero);
    queue
      ..enqueue(snapshot(2))
      ..enqueue(snapshot(3));
    firstWriteGate.complete();
    await queue.flush();

    expect(writes, [const Duration(seconds: 1), const Duration(seconds: 3)]);
    expect(maxActiveWriters, 1);
    await queue.dispose();
  });

  test('bulk relink preview search and audit summary stay local and private',
      () {
    final ready = BulkPathRelinkPreview(
      item: _testVideo(path: r'C:\private\alpha.mp4', title: 'Private Alpha'),
      newPath: r'E:\moved\alpha.mp4',
      status: BulkRelinkStatus.ready,
    );
    final missing = BulkPathRelinkPreview(
      item: _testVideo(path: r'C:\private\beta.mp4', title: 'Private Beta'),
      newPath: r'E:\moved\beta.mp4',
      status: BulkRelinkStatus.targetMissing,
    );
    expect(filterBulkRelinkPreviews([ready, missing], 'alpha'), [ready]);
    expect(filterBulkRelinkPreviews([ready, missing], '目标不存在'), [missing]);

    final summary = bulkRelinkAuditSummary(
      [ready, missing],
      result: const BulkRelinkExecutionResult(
        succeededCount: 1,
        failedVideoIds: <String>{},
      ),
    );
    expect(summary, contains('预览总数: 2'));
    expect(summary, contains('执行成功: 1'));
    expect(summary, isNot(contains(r'C:\private')));
    expect(summary, isNot(contains('Private Alpha')));
  });

  testWidgets('resume dialog offers continue and restart choices',
      (tester) async {
    PlayerResumeChoice? choice;
    final item = _testVideo(path: 'C:/queue/resume.mp4', title: 'Resume');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              choice = await showPlayerResumeDialog(
                context,
                item: item,
                position: const Duration(seconds: 37),
                duration: const Duration(minutes: 2),
              );
            },
            child: const Text('打开恢复选择'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开恢复选择'));
    await tester.pumpAndSettle();
    expect(find.text('从上次位置继续'), findsOneWidget);
    expect(find.text('从头播放'), findsOneWidget);
    expect(find.textContaining('00:37 / 02:00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('player.resume.restart')));
    await tester.pumpAndSettle();
    expect(choice, PlayerResumeChoice.restart);
  });

  test('player queue search stays within the provided queue', () {
    final items = [
      _testVideo(path: 'C:/queue/alpha.mp4', title: 'Alpha'),
      _testVideo(path: 'C:/queue/beta.mp4', title: 'Beta', tags: {'favorite'}),
      _testVideo(path: 'C:/queue/gamma.mp4', title: 'Gamma'),
    ];

    expect(playerQueueSearchIndex(items, 'favorite', startIndex: 0), 1);
    expect(playerQueueSearchIndex(items, 'alpha', startIndex: 0), 0);
    expect(playerQueueSearchIndex(items, 'missing', startIndex: 0), isNull);
  });

  test('player queue search keeps a 50000 item baseline lightweight', () {
    final items = List<VideoItem>.generate(
      50000,
      (index) => _testVideo(
        path: 'C:/queue/video_$index.mp4',
        title: index == 49999 ? 'Target Needle' : 'Video $index',
      ),
      growable: false,
    );
    final stopwatch = Stopwatch()..start();
    final result = playerQueueSearchIndex(items, 'target needle');
    stopwatch.stop();
    debugPrint(
      'PLAYER_QUEUE_BENCHMARK items=50000 elapsed_us=${stopwatch.elapsedMicroseconds}',
    );

    expect(result, 49999);
    // 宽松阈值只防止误接全库扫描或明显的超线性退化，不绑定具体开发机性能。
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  testWidgets('manual tag editor locks folder tags', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TagEditorDialog(
            title: '视频 / 手动标签',
            helperText: '只修改手动标签；文件夹标签由目录结构维护。',
            initialTags: {'FolderTag', 'ManualTag'},
            existingTags: {'SuggestedTag'},
            lockedTags: {'FolderTag'},
            recentTags: ['RecentTag'],
            favoriteTags: {'FavoriteTag'},
          ),
        ),
      ),
    );

    final chips = tester.widgetList<InputChip>(find.byType(InputChip));
    final folderChip = chips.firstWhere(
      (chip) => (chip.label as Text).data == 'FolderTag',
    );
    final manualChip = chips.firstWhere(
      (chip) => (chip.label as Text).data == 'ManualTag',
    );

    expect(folderChip.onDeleted, isNull);
    expect(manualChip.onDeleted, isNotNull);
    expect(find.text('只修改手动标签；文件夹标签由目录结构维护。'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.text('最近使用'), findsOneWidget);
    expect(find.text('RecentTag'), findsOneWidget);
    expect(find.text('收藏标签'), findsOneWidget);
    expect(find.text('FavoriteTag'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Suggested');
    await tester.pump();
    expect(find.text('搜索结果'), findsOneWidget);
    expect(find.text('SuggestedTag'), findsOneWidget);
    expect(find.text('RecentTag'), findsNothing);
  });

  testWidgets('manual tag editor supports keyboard save', (tester) async {
    Set<String>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  saved = await showDialog<Set<String>>(
                    context: context,
                    builder: (_) => const TagEditorDialog(
                      title: '键盘标签编辑',
                      initialTags: <String>{},
                      existingTags: <String>{'Existing'},
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ctrl+Enter'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      tester.widgetList<InputChip>(find.byType(InputChip)).any(
            (chip) => (chip.label as Text).data == 'Existing',
          ),
      isTrue,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(saved, contains('Existing'));
    expect(find.text('键盘标签编辑'), findsNothing);
  });

  test('secondary discovery hides default album from secondary lists', () {
    const defaultAlbum = TagItem(
      id: 'folder.child:genshin:default',
      name: TagRules.defaultAlbumTag,
      source: TagSource.folder,
      groupId: 'folder.child',
      parentId: '原神',
      usageCount: 100,
    );
    const lisa = TagItem(
      id: 'folder.child:genshin:lisa',
      name: '丽莎',
      source: TagSource.folder,
      groupId: 'folder.child',
      parentId: '原神',
      usageCount: 12,
    );
    const groups = [
      TagGroup(id: 'folder.child', name: '二级标签', items: [defaultAlbum, lisa]),
    ];

    expect(secondaryTagsForDiscovery(groups, const {}), [lisa]);
  });

  test('primary child display keeps only the leading virtual default album',
      () {
    const genshin = TagItem(
      id: 'folder.primary:genshin',
      name: '原神',
      source: TagSource.folder,
      groupId: 'folder.primary',
    );
    const defaultAlbum = TagItem(
      id: 'folder.child:genshin:default',
      name: TagRules.defaultAlbumTag,
      source: TagSource.folder,
      groupId: 'folder.child',
      parentId: '原神',
      usageCount: 100,
    );
    const lisa = TagItem(
      id: 'folder.child:genshin:lisa',
      name: '丽莎',
      source: TagSource.folder,
      groupId: 'folder.child',
      parentId: '原神',
      usageCount: 12,
    );

    expect(
      displayChildItemsForPrimary(genshin, {
        genshin.id: [defaultAlbum, lisa],
      }),
      [lisa],
    );
  });

  test('hot secondary tags hide parent labels', () {
    const lisa = TagItem(
      id: 'folder.child:genshin:lisa',
      name: '丽莎',
      source: TagSource.folder,
      groupId: 'folder.child',
      parentId: '原神',
    );

    expect(secondaryTagParentLabel(lisa, showParentLabel: false), isNull);
    expect(secondaryTagParentLabel(lisa, showParentLabel: true), '原神');
  });

  test('hot secondary tag conflicts require parent labels', () {
    const lisa = TagItem(
      id: 'folder.child:genshin:lisa',
      name: 'Lisa',
      source: TagSource.folder,
      groupId: 'folder.child',
      parentId: 'Genshin',
    );
    const ntrA = TagItem(
      id: 'folder.child:genshin:ntr',
      name: 'ntr',
      source: TagSource.folder,
      groupId: 'folder.child',
      parentId: 'Genshin',
    );
    const ntrB = TagItem(
      id: 'folder.child:honkai:ntr',
      name: 'ntr',
      source: TagSource.folder,
      groupId: 'folder.child',
      parentId: 'Honkai',
    );

    expect(
      secondaryTagNameHasConflict(lisa, const [lisa, ntrA, ntrB]),
      isFalse,
    );
    expect(
      secondaryTagNameHasConflict(ntrA, const [lisa, ntrA, ntrB]),
      isTrue,
    );
  });

  test('tag manager coalesces case variants within the same source boundary',
      () {
    const manualUpper = TagItem(
      id: 'manual:ntr-upper',
      name: 'NTR',
      source: TagSource.manual,
      groupId: 'manual',
    );
    const manualLower = TagItem(
      id: 'manual:ntr-lower',
      name: 'ntr',
      source: TagSource.manual,
      groupId: 'manual',
    );
    const folderAlpha = TagItem(
      id: 'folder.child:alpha:ntr',
      name: 'ntr',
      source: TagSource.folder,
      groupId: 'folder.child',
      parentId: 'Alpha',
    );
    const folderBeta = TagItem(
      id: 'folder.child:beta:ntr',
      name: 'NTR',
      source: TagSource.folder,
      groupId: 'folder.child',
      parentId: 'Beta',
    );

    expect(
      tagManagerDisplayRowsForTesting(
        tags: const [manualUpper, manualLower, folderAlpha, folderBeta],
        usage: const {
          'manual:ntr-upper': TagUsageSummary(total: 2, manual: 2),
          'manual:ntr-lower': TagUsageSummary(total: 3, manual: 3),
          'folder.child:alpha:ntr': TagUsageSummary(total: 4, folder: 4),
          'folder.child:beta:ntr': TagUsageSummary(total: 5, folder: 5),
        },
      ),
      ['Alpha / ntr|4|1', 'Beta / NTR|5|1', 'ntr|5|2'],
    );
  });

  test('recent playback clear targets honor single and bulk selection', () {
    final playedA = VideoItem(
      path: 'D:/video/a.mp4',
      title: 'a',
      folder: 'video',
      tags: const {'原神'},
      addedAt: DateTime(2026),
      lastPlayedAt: DateTime(2026, 1, 2),
    );
    final playedB = VideoItem(
      path: 'D:/video/b.mp4',
      title: 'b',
      folder: 'video',
      tags: const {'原神'},
      addedAt: DateTime(2026),
      lastPlayedAt: DateTime(2026, 1, 3),
    );
    final neverPlayed = VideoItem(
      path: 'D:/video/c.mp4',
      title: 'c',
      folder: 'video',
      tags: const {'原神'},
      addedAt: DateTime(2026),
    );

    expect(
      recentPlaybackClearTargets(
        [playedA, playedB, neverPlayed],
        selectedPathKeys: {TagRules.pathKey(playedB.path)},
        selectedOnly: true,
      ),
      [playedB],
    );
    expect(
      recentPlaybackClearTargets(
        [playedA, playedB, neverPlayed],
        selectedPathKeys: const {},
        selectedOnly: false,
      ),
      [playedA, playedB],
    );
  });

  testWidgets('result view toggle switches to dense list mode', (tester) async {
    var dense = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResultViewToggle(
            dense: dense,
            onChanged: (value) => dense = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.view_list_rounded));
    await tester.pump();

    expect(dense, isTrue);
  });

  testWidgets('collapsed tag rail exposes a stable expand action',
      (tester) async {
    var expanded = false;
    await tester.pumpWidget(
      collapsedTagDiscoveryRailSmokeHarness(
        onExpand: () => expanded = true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(LibrarySmokeKeys.collapsedTagRail), findsOneWidget);
    expect(find.byTooltip('展开标签筛选'), findsOneWidget);

    await tester.tap(find.byKey(LibrarySmokeKeys.collapsedTagRail));
    await tester.pump(const Duration(milliseconds: 100));
    expect(expanded, isTrue);
  });

  testWidgets('top search field accepts keyboard input', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var latestKeyword = '';
    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        onSearchChanged: (value) => latestKeyword = value,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byKey(LibrarySmokeKeys.searchField), 'lupa');
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.text, 'lupa');
    expect(latestKeyword, 'lupa');
  });

  testWidgets('Ctrl+K search input updates result count and visible list',
      (tester) async {
    await tester.pumpWidget(
      const ReferenceTopBarSearchResultSmokeHarness(
        items: [
          'firefly-x-celestia-strinova_1080p',
          'ntr-bronya-sex-02_720p',
          'firefly-holiday-720p',
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    await tester.enterText(find.byKey(LibrarySmokeKeys.searchField), 'firefly');
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('结果 2/3'), findsOneWidget);
    expect(find.text('firefly-x-celestia-strinova_1080p'), findsOneWidget);
    expect(find.text('firefly-holiday-720p'), findsOneWidget);
    expect(find.text('ntr-bronya-sex-02_720p'), findsNothing);
  });

  test('count refresh coordinator drops stale queued counts', () async {
    final coordinator = LibraryCountRefreshCoordinator(
      idleDelay: const Duration(milliseconds: 20),
    );
    addTearDown(coordinator.dispose);
    final completed = <Map<String, int>>[];
    var computeCalls = 0;

    coordinator.schedule(
      query: const FilterQuery(keyword: 'old'),
      compute: (_) {
        computeCalls++;
        return {'old': 1};
      },
      isStillCurrent: (_) => true,
      onComplete: completed.add,
    );
    coordinator.cancelPending();
    coordinator.schedule(
      query: const FilterQuery(keyword: 'new'),
      compute: (_) {
        computeCalls++;
        return {'new': 2};
      },
      isStillCurrent: (_) => true,
      onComplete: completed.add,
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(computeCalls, 1);
    expect(completed, [
      {'new': 2},
    ]);
  });

  testWidgets(
      'top bar removes duplicate favorite filter and toggles sort order',
      (tester) async {
    tester.view.physicalSize = const Size(2400, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var directionToggles = 0;

    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        onSearchChanged: (_) {},
        onSortDirectionToggle: () => directionToggles++,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('收藏筛选'), findsNothing);
    expect(find.text('倒序'), findsOneWidget);

    final sortButtonRect =
        tester.getRect(find.byKey(LibrarySmokeKeys.topSortFieldButton));
    await tester.tap(find.byKey(LibrarySmokeKeys.topSortFieldButton));
    await tester.pumpAndSettle();
    final menuPanelRect =
        tester.getRect(find.byKey(LibrarySmokeKeys.topSortMenuPanel));
    expect(menuPanelRect.top, closeTo(sortButtonRect.bottom - 1, 1.5));
    expect(menuPanelRect.left, closeTo(sortButtonRect.left, 1));
    expect(menuPanelRect.width, greaterThanOrEqualTo(sortButtonRect.width));
    expect(menuPanelRect.width, greaterThanOrEqualTo(136));

    await tester.tap(find.byKey(LibrarySmokeKeys.topSortMenuItem(
      SortMode.recent,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('倒序'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(directionToggles, 1);
  });

  test('cleared filter query returns to empty state', () {
    const active = FilterQuery(
      primaryTagId: '原神',
      childTagId: '丽莎',
      favoriteOnly: true,
    );
    expect(active.isEmpty, isFalse);

    const cleared = FilterQuery();
    expect(cleared.isEmpty, isTrue);
  });

  testWidgets('smoke path opens local folders and returns by button or mouse',
      (tester) async {
    const rootPath = r'C:\smoke\media';
    const childPath = r'C:\smoke\media\Alpha';
    await tester.pumpWidget(
      const LocalLibrarySmokeHarness(rootPath: rootPath, childPath: childPath),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(LibrarySmokeKeys.localFolder(childPath)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(LibrarySmokeKeys.localFolder(childPath)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(childPath), findsOneWidget);

    await tester.tap(find.byKey(LibrarySmokeKeys.localBackButton));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(rootPath), findsOneWidget);

    await tester.tap(find.byKey(LibrarySmokeKeys.localFolder(childPath)));
    await tester.pump(const Duration(milliseconds: 100));
    final backRegion =
        tester.getCenter(find.byKey(LibrarySmokeKeys.localPointerBackRegion));
    tester.binding.handlePointerEvent(
      PointerDownEvent(position: backRegion, buttons: kBackMouseButton),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(rootPath), findsOneWidget);
  });

  testWidgets('empty library shows a square add-files entry', (tester) async {
    var addCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(
            hasLibrary: false,
            onAddFiles: () => addCount += 1,
          ),
        ),
      ),
    );

    expect(find.byKey(LibrarySmokeKeys.emptyAddFiles), findsOneWidget);
    expect(find.text('添加视频文件'), findsOneWidget);
    expect(find.textContaining('拖到媒体库区域'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(LibrarySmokeKeys.emptyAddFiles)),
      const Size(108, 108),
    );
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(LibrarySmokeKeys.emptyAddFiles),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xff243145));
    final border = decoration.border! as Border;
    expect(border.top.color, const Color(0x596d5dfc));
    expect(border.top.width, 1.25);

    await tester.tap(find.byKey(LibrarySmokeKeys.emptyAddFiles));
    await tester.pump();
    expect(addCount, 1);
  });

  testWidgets('library result line shows determinate import progress',
      (tester) async {
    var pauseCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryHeroArea(
            selectedTags: const <String>[],
            selectedChildTags: const <String>[],
            selectedGroupTags: const <TagItem>[],
            excludedTags: const <TagItem>[],
            keyword: '',
            defaultChipLabel: '全部视频',
            querySummary: '全部视频 · 11163 个结果',
            queryExpression: '全部视频 | 11163 / 11163',
            showFavoritesOnly: false,
            resultCount: 11163,
            totalCount: 11163,
            refreshing: false,
            progressLabel: '媒体解析 3200/6308 · 50% · 120个/秒 · 剩余26秒',
            progressValue: 3200 / 6308,
            onToggleProgressPaused: () => pauseCount++,
            onRemovePrimaryTag: (_) {},
            onRemoveChildTag: (_) {},
            onRemoveGroupTag: (_) {},
            onRemoveExcludedTag: (_) {},
            onClearKeyword: () {},
            onClearFavoritesOnly: () {},
            onClearAll: null,
          ),
        ),
      ),
    );

    expect(
      find.text('媒体解析 3200/6308 · 50% · 120个/秒 · 剩余26秒'),
      findsOneWidget,
    );
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, closeTo(3200 / 6308, 0.0001));
    expect(find.text('全部视频 · 11163 个结果'), findsNothing);
    expect(find.byKey(const ValueKey('qa.media_import.pause')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('qa.media_import.pause')));
    await tester.pump();
    expect(pauseCount, 1);
  });

  test('file imports collapse to uncovered top-level roots', () {
    final existingRoot = p.join('library', 'existing');
    final newRoot = p.join('library', 'new');
    final selectedParent = p.join('library', 'selected');
    final roots = libraryImportRoots(
      existingRoots: <String>[existingRoot],
      imports: <LibraryImportPath>[
        (path: p.join(existingRoot, 'known.mp4'), isDirectory: false),
        (path: p.join(newRoot, 'first.mp4'), isDirectory: false),
        (path: p.join(newRoot, 'second.mkv'), isDirectory: false),
        (path: selectedParent, isDirectory: true),
        (
          path: p.join(selectedParent, 'child', 'nested.mp4'),
          isDirectory: false,
        ),
        (path: p.join('library', 'ignored.txt'), isDirectory: false),
      ],
    );

    expect(roots, <String>[newRoot, selectedParent]);
  });

  testWidgets('smoke path opens local folders in dense list mode',
      (tester) async {
    const rootPath = r'C:\smoke\media';
    const childPath = r'C:\smoke\media\Alpha';
    await tester.pumpWidget(
      const LocalLibrarySmokeHarness(
        rootPath: rootPath,
        childPath: childPath,
        dense: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(LibrarySmokeKeys.localFolder(childPath)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(childPath), findsOneWidget);

    await tester.tap(find.byKey(LibrarySmokeKeys.localBackButton));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(rootPath), findsOneWidget);
  });

  testWidgets('smoke path hits list row play favorite and more',
      (tester) async {
    const path = r'C:\smoke\media\Alpha\clip.mp4';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const VideoListRowSmokeHarness());
    await tester.pump(const Duration(milliseconds: 100));

    String actionState() =>
        tester.widget<Text>(find.byKey(LibrarySmokeKeys.listActionState)).data!;

    expect(actionState(), 'open=0 favorite=0 more=0');
    final rowRect =
        tester.getRect(find.byKey(LibrarySmokeKeys.videoListRow(path)));
    final moreRect =
        tester.getRect(find.byKey(LibrarySmokeKeys.listMore(path)));
    expect(rowRect.right - moreRect.right, inInclusiveRange(6, 18));

    await tester.ensureVisible(find.byKey(LibrarySmokeKeys.listPlay(path)));
    await tester.tap(find.byKey(LibrarySmokeKeys.listPlay(path)));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    expect(actionState(), 'open=1 favorite=0 more=0');

    await tester.ensureVisible(find.byKey(LibrarySmokeKeys.listFavorite(path)));
    await tester.tap(find.byKey(LibrarySmokeKeys.listFavorite(path)));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    expect(actionState(), 'open=1 favorite=1 more=0');

    await tester.ensureVisible(find.byKey(LibrarySmokeKeys.listMore(path)));
    await tester.tap(find.byKey(LibrarySmokeKeys.listMore(path)));
    await tester.pump(const Duration(seconds: 1));
    expect(actionState(), 'open=1 favorite=1 more=0');
    expect(find.byKey(LibrarySmokeKeys.videoMoreEditTags), findsOneWidget);
    expect(find.byKey(LibrarySmokeKeys.videoMoreDelete), findsOneWidget);
    expect(find.text('编辑标签'), findsOneWidget);
  });

  testWidgets('smoke path toggles tag panel rows and child expansion',
      (tester) async {
    const alphaTagId = 'folder.primary:alpha';
    await tester.pumpWidget(const TagDiscoverySmokeHarness(childCount: 12));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(LibrarySmokeKeys.primaryRow(alphaTagId)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(LibrarySmokeKeys.primaryHeader(alphaTagId)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(LibrarySmokeKeys.primaryHeader(alphaTagId)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(LibrarySmokeKeys.primaryRow(alphaTagId)), findsOneWidget);

    await tester.tap(find.byKey(LibrarySmokeKeys.primaryRow(alphaTagId)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('展开全部'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(LibrarySmokeKeys.childExpandButton(alphaTagId)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester
        .tap(find.byKey(LibrarySmokeKeys.childExpandButton(alphaTagId)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('收起'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(LibrarySmokeKeys.childExpandButton(alphaTagId)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester
        .tap(find.byKey(LibrarySmokeKeys.childExpandButton(alphaTagId)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('展开全部'), findsOneWidget);

    await tester.tap(find.byKey(LibrarySmokeKeys.secondaryTab));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Child01'), findsWidgets);

    await tester.tap(find.byKey(LibrarySmokeKeys.primaryTab));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(LibrarySmokeKeys.primaryHeader(alphaTagId)),
      findsOneWidget,
    );
  });

  testWidgets('smoke path shows all secondary only in secondary tab',
      (tester) async {
    await tester.pumpWidget(const TagDiscoverySmokeHarness(childCount: 13));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Child13'), findsNothing);
    await tester.tap(find.byKey(LibrarySmokeKeys.secondaryTab));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Child13'), findsWidgets);
  });

  testWidgets('smoke path updates tag result state after chip selection',
      (tester) async {
    const alphaTagId = 'folder.primary:alpha';
    const defaultAlbumChipId = 'folder.primary:alpha::default-album';
    const child01ChipId = 'folder.child:alpha:child01';
    await tester.pumpWidget(const TagDiscoverySmokeHarness(childCount: 12));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(LibrarySmokeKeys.primaryRow(alphaTagId)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(LibrarySmokeKeys.tagChip(defaultAlbumChipId)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(LibrarySmokeKeys.tagResult('Alpha Default Video')),
      findsOneWidget,
    );
    expect(
      find.byKey(LibrarySmokeKeys.tagResult('Child01 Video')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(LibrarySmokeKeys.tagChip(child01ChipId)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(LibrarySmokeKeys.tagResult('Child01 Video')),
      findsOneWidget,
    );
    expect(
      find.byKey(LibrarySmokeKeys.tagResult('Alpha Default Video')),
      findsNothing,
    );
    expect(
      find.byKey(LibrarySmokeKeys.tagResult('Child02 Video')),
      findsNothing,
    );
  });

  test('media details disposal discards new reads and keeps cached snapshots',
      () async {
    const cached = MediaDetails(
      videoCodec: 'h264',
      audioCodec: 'aac',
      width: 1920,
      height: 1080,
    );
    final cachedItem = _testVideo(path: 'C:/queue/cached.mp4', title: 'cached')
      ..mediaDetails = cached;
    final uncachedItem =
        _testVideo(path: 'C:/queue/uncached.mp4', title: 'uncached');
    final service = MediaDetailsService(
      probeBackend: CompatibleMediaProbeBackend(DesktopFFmpegBackend()),
    );

    expect(service.cachedDetailsFor(cachedItem), same(cached));
    service.dispose();
    final result = await service.detailsFor(uncachedItem);

    expect(service.isDisposed, isTrue);
    expect(service.queuedReads, 0);
    expect(result.width, isNull);
  });

  test(
      'filter state source applies scan delta without rebuilding unchanged rows',
      () {
    final changedOut = _testVideo(
      path: 'C:/queue/changed-out.mp4',
      title: 'target old',
    );
    final unchanged = _testVideo(
      path: 'C:/queue/unchanged.mp4',
      title: 'target unchanged',
    );
    final changedIn = _testVideo(
      path: 'C:/queue/changed-in.mp4',
      title: 'other',
    );
    final source = FilterStateSource()
      ..configure(
        engine: TagQueryService(
          videos: [changedOut, unchanged, changedIn],
          tagContext: const TagQueryContext(),
        ),
        totalCount: 3,
        sourceKey: 0,
      );
    const query = FilterQuery(keyword: 'target');
    expect(
      source.update(query).filteredVideos.map((item) => item.videoId),
      [changedOut.videoId, unchanged.videoId],
    );

    changedOut.title = 'other now';
    changedIn.title = 'target new';
    final added = _testVideo(
      path: 'C:/queue/added.mp4',
      title: 'target added',
    );
    source.configure(
      engine: TagQueryService(
        videos: [changedOut, unchanged, changedIn, added],
        tagContext: const TagQueryContext(),
      ),
      totalCount: 4,
      sourceKey: 1,
    );
    final next = source.applyVideoDelta(query, [changedOut, changedIn, added]);

    expect(
      next.filteredVideos.map((item) => item.videoId).toSet(),
      {unchanged.videoId, changedIn.videoId, added.videoId},
    );
    expect(
        next.filteredVideos.singleWhere(
          (item) => item.videoId == unchanged.videoId,
        ),
        same(unchanged));
    expect(next.totalCount, 4);

    source.configure(
      engine: TagQueryService(
        videos: [changedOut, unchanged, changedIn, added],
        tagContext: const TagQueryContext(),
      ),
      totalCount: 4,
      sourceKey: 2,
    );
    final zeroDelta = source.applyVideoDelta(query, const <VideoItem>[]);
    expect(zeroDelta.filteredVideos, same(next.filteredVideos));
  });

  test('filter state source drops removed rows when source revision changes',
      () {
    final removed = _testVideo(
      path: 'C:/queue/removed.mp4',
      title: 'removed',
    );
    final retained = _testVideo(
      path: 'C:/queue/retained.mp4',
      title: 'retained',
    );
    final source = FilterStateSource()
      ..configure(
        engine: TagQueryService(
          videos: [removed, retained],
          tagContext: const TagQueryContext(),
        ),
        totalCount: 2,
        sourceKey: 0,
      );
    expect(source.update(const FilterQuery()).resultCount, 2);

    source.configure(
      engine: TagQueryService(
        videos: [retained],
        tagContext: const TagQueryContext(),
      ),
      totalCount: 1,
      sourceKey: 1,
    );

    final refreshed = source.update(const FilterQuery());
    expect(refreshed.filteredVideos, [retained]);
    expect(refreshed.totalCount, 1);
  });

  test('visible thumbnail requests share one bounded queue job', () async {
    final directory =
        await Directory.systemTemp.createTemp('ltp_thumbnail_queue_');
    addTearDown(() async {
      await directory.delete(recursive: true);
    });
    final paths = AppPaths(dataDirectoryOverride: directory);
    final service = await ThumbnailService.create(
      paths,
      DesktopFFmpegBackend(),
    );
    final item = _testVideo(
      path: '${directory.path}/missing.mp4',
      title: 'missing',
    )
      ..fileSize = 123
      ..modifiedMs = 456;

    final results = await Future.wait<File?>([
      service.ensureThumbnailFor(item),
      service.ensureThumbnailFor(item),
    ]);
    final stats = await service.statsFor([item]);

    expect(results, [isNull, isNull]);
    expect(stats.failedThisRun, 1);
    expect(stats.queued, 0);
    expect(stats.active, 0);
  });

  test('background thumbnail candidates stay dormant while paused', () async {
    final directory =
        await Directory.systemTemp.createTemp('ltp_thumbnail_candidates_');
    addTearDown(() async {
      await directory.delete(recursive: true);
    });
    final paths = AppPaths(dataDirectoryOverride: directory);
    final service = (await ThumbnailService.create(
      paths,
      DesktopFFmpegBackend(),
    ))
      ..pause();
    final items = List<VideoItem>.generate(
      80,
      (index) => _testVideo(
        path: '${directory.path}/candidate_$index.mp4',
        title: 'candidate $index',
      )
        ..fileSize = index + 1
        ..modifiedMs = index + 100,
    );

    service.prefetchAll(items);
    final stats = await service.statsFor(const <VideoItem>[]);

    expect(stats.pendingBackgroundRequests, 80);
    expect(stats.queued, 80);
    expect(stats.active, 0);
  });

  test('player pause keeps background dormant but serves visible thumbnail',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('ltp_thumbnail_player_priority_');
    addTearDown(() async {
      await directory.delete(recursive: true);
    });
    final service = (await ThumbnailService.create(
      AppPaths(dataDirectoryOverride: directory),
      DesktopFFmpegBackend(),
    ))
      ..pause(allowPriorityRequests: true);
    final background = _testVideo(
      path: '${directory.path}/background.mp4',
      title: 'background',
    )
      ..fileSize = 1
      ..modifiedMs = 10;
    final visible = _testVideo(
      path: '${directory.path}/visible.mp4',
      title: 'visible',
    )
      ..fileSize = 2
      ..modifiedMs = 20;

    service.prefetchAll(<VideoItem>[background]);
    final result = await service.ensureThumbnailFor(visible);
    final stats = await service.statsFor(const <VideoItem>[]);

    expect(result, isNull);
    expect(stats.pendingBackgroundRequests, 1);
    expect(stats.failedThisRun, 1);
    expect(stats.active, 0);
  });

  test('Windows recommended decoding requests stable D3D11 copy mode', () {
    final resolved = PlayerHardwareAcceleration.resolve('auto-safe');
    expect(resolved, Platform.isWindows ? 'd3d11va-copy' : 'auto-safe');
    expect(PlayerHardwareAcceleration.resolve('no'), 'no');
    expect(PlayerHardwareAcceleration.resolve('nvdec'), 'nvdec');
  });

  test('4K H264 HEVC and AV1 matrix does not show false warnings', () {
    for (final codec in const ['H264', 'HEVC', 'AV1']) {
      final result = PlayerHardwareCompatibility.assess(
        details: MediaDetails(
          videoCodec: codec,
          width: 3840,
          height: 2160,
        ),
        settings: PlaybackSettings.defaults,
        isWindows: true,
      );
      expect(result.status, HardwareDecodeCompatibilityStatus.verified);
    }
  });

  test('8K H264 matrix requires software decode confirmation', () {
    final result = PlayerHardwareCompatibility.assess(
      details: const MediaDetails(
        videoCodec: 'H264',
        width: 7680,
        height: 4320,
      ),
      settings: PlaybackSettings.defaults,
      isWindows: true,
    );

    expect(result.status, HardwareDecodeCompatibilityStatus.unsupported);
    expect(result.reason, contains('CPU 软件解码'));
  });

  test('unknown or intentionally software-decoded media is not over-warned',
      () {
    final unknown = PlayerHardwareCompatibility.assess(
      details: const MediaDetails(videoCodec: 'VP9', width: 7680, height: 4320),
      settings: PlaybackSettings.defaults,
      isWindows: true,
    );
    final software = PlayerHardwareCompatibility.assess(
      details:
          const MediaDetails(videoCodec: 'H264', width: 7680, height: 4320),
      settings: PlaybackSettings.defaults.copyWith(hwdec: 'no'),
      isWindows: true,
    );

    expect(unknown.status, HardwareDecodeCompatibilityStatus.unknown);
    expect(software.status, HardwareDecodeCompatibilityStatus.unknown);
  });

  testWidgets('unsupported hardware decode dialog offers proxy advice',
      (tester) async {
    var result = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showPlayerHardwareDecodeWarningDialog(
                  context,
                  const HardwareDecodeCompatibilityAssessment(
                    status: HardwareDecodeCompatibilityStatus.unsupported,
                    codec: 'H.264',
                    width: 7680,
                    height: 4320,
                    reason: '测试软解回退',
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('该视频无法可靠硬件解码'), findsOneWidget);
    expect(find.textContaining('3840×2160 H.264 代理'), findsOneWidget);
    expect(find.byKey(const ValueKey('player.hwdecWarning.proxyCommand')),
        findsOneWidget);
    expect(find.textContaining('已阻止直接播放'), findsOneWidget);
    expect(find.byKey(const ValueKey('player.hwdecWarning.continue')),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey('player.hwdecWarning.cancel')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  test('player hidden progress fraction clamps invalid and overflow values',
      () {
    expect(playerProgressFraction(Duration.zero, Duration.zero), 0);
    expect(
      playerProgressFraction(
        const Duration(seconds: 25),
        const Duration(seconds: 100),
      ),
      0.25,
    );
    expect(
      playerProgressFraction(
        const Duration(seconds: -1),
        const Duration(seconds: 100),
      ),
      0,
    );
    expect(
      playerProgressFraction(
        const Duration(seconds: 120),
        const Duration(seconds: 100),
      ),
      1,
    );
  });

  testWidgets('player hidden progress bar keeps a three pixel progress hint',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayerHiddenProgressBar(
            position: Duration(seconds: 25),
            duration: Duration(seconds: 100),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('player.hiddenProgressBar'))),
      const Size(800, 3),
    );
    final active = tester.widget<FractionallySizedBox>(
      find.byKey(const ValueKey('player.hiddenProgressBar.active')),
    );
    expect(active.widthFactor, 0.25);
  });

  testWidgets('player progress expands on hover and delays frame preview',
      (tester) async {
    final previewRequest = Completer<File?>();
    Duration? requestedPosition;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PlayerProgressSlider(
                sliderKey: const ValueKey('test.progress'),
                value: 25000,
                max: 100000,
                previewIdentity: 'video-1',
                loadPreview: (position) {
                  requestedPosition = position;
                  return previewRequest.future;
                },
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    SliderTheme sliderTheme() => tester.widget<SliderTheme>(
          find.descendant(
            of: find.byType(PlayerProgressSlider),
            matching: find.byType(SliderTheme),
          ),
        );
    expect(sliderTheme().data.trackHeight, 2);
    expect(find.byKey(const ValueKey('player.progress.preview')), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(-10, -10));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(
      find.byKey(const ValueKey('player.progress.hoverRegion')),
    ));
    await tester.pump();
    final hoverAnimation = tester.widget<TweenAnimationBuilder<double>>(
      find.byKey(const ValueKey('player.progress.hoverAnimation')),
    );
    expect(hoverAnimation.tween.end, 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(sliderTheme().data.trackHeight, 5);
    expect(requestedPosition, isNull);
    await tester.pump(const Duration(milliseconds: 149));
    expect(requestedPosition, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    expect(requestedPosition, const Duration(seconds: 50));
    expect(
        find.byKey(const ValueKey('player.progress.preview')), findsOneWidget);

    await mouse.removePointer();
  });

  test('fullscreen progress thumb scales only on high resolution viewports',
      () {
    expect(
      playerProgressThumbScale(
        isFullscreen: false,
        viewportSize: const Size(3840, 2160),
      ),
      1,
    );
    expect(
      playerProgressThumbScale(
        isFullscreen: true,
        viewportSize: const Size(1280, 720),
      ),
      1,
    );
    expect(
      playerProgressThumbScale(
        isFullscreen: true,
        viewportSize: const Size(3840, 2160),
      ),
      1.25,
    );
    expect(
      playerProgressThumbScale(
        isFullscreen: true,
        viewportSize: const Size(7680, 4320),
      ),
      1.25,
    );
  });

  test('hover preview frame is generated once and reused by second bucket',
      () async {
    final directory = await Directory.systemTemp.createTemp('ltp_hover_frame_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}video.mp4');
    await source.writeAsBytes(<int>[1, 2, 3]);
    final backend = _PreviewFFmpegBackend();
    final service = ThumbnailService.forDirectory(directory, backend);
    final item = _testVideo(path: source.path, title: 'preview');

    final first = await service.previewFrameFor(
      item,
      const Duration(milliseconds: 10200),
    );
    final reused = await service.previewFrameFor(
      item,
      const Duration(milliseconds: 10400),
    );

    expect(first, isNotNull);
    expect(reused?.path, first?.path);
    expect(backend.previewCalls, 1);
    expect(backend.previewPositions, <Duration>[const Duration(seconds: 10)]);
  });
}
