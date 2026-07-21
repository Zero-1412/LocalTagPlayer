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

/** 判断当前键盘焦点是否落在指定控件的子树中。 */
bool _primaryFocusIsInside(Finder ancestor) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) {
    return false;
  }
  final targets = ancestor.evaluate().toSet();
  if (targets.contains(context)) {
    return true;
  }
  var matched = false;
  context.visitAncestorElements((element) {
    if (targets.contains(element)) {
      matched = true;
      return false;
    }
    return true;
  });
  return matched;
}

/** Missing/Relink widget 测试只暴露页面读取的视频索引。 */
class _MissingRelinkTestRepository
    implements
        LibraryRepository,
        TagRepository,
        CacheRepository,
        PlaybackRepository {
  @override
  final List<String> roots = <String>[];
  @override
  final Map<String, VideoItem> videos = <String, VideoItem>{};
  @override
  final List<String> favoriteTags = <String>[];
  @override
  final List<TagGroup> tagGroups = <TagGroup>[];
  @override
  final Map<String, TagItem> tagsById = <String, TagItem>{};
  @override
  final Map<String, Set<String>> videoTagIdsByPathKey = <String, Set<String>>{};

  @override
  Set<String> get allTags => const <String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/** 模拟用户取消原生文件选择器，不执行任何磁盘操作。 */
class _CancellingFileSystemAdapter implements FileSystemAdapter {
  var pickFileCalls = 0;
  String? lastInitialDirectory;

  @override
  Future<String?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    List<String> allowedExtensions = const <String>[],
  }) async {
    pickFileCalls++;
    lastInitialDirectory = initialDirectory;
    return null;
  }

  @override
  String parentPath(String path) => p.dirname(path);

  @override
  Future<bool> directoryExists(String path) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

/** 队列布局测试不执行媒体探测，只提供可安全释放的平台边界。 */
class _NoopMediaProbeBackend implements MediaProbeBackend {
  /** 测试结束时接受代次取消，不保留任何后台状态。 */
  @override
  Future<void> cancelGeneration(int generationId) async {}

  /** 缺失队列项不会发起探测；若误调用也返回安全空结果。 */
  @override
  Future<List<MediaProbeResult>> probeBatch({
    required int generationId,
    required List<MediaProbeRequest> requests,
  }) async =>
      const <MediaProbeResult>[];
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
      closeTo(210.25, 0.01),
    );
    expect(
      libraryVideoCardMainAxisExtent(
        gridWidth: 590,
        narrow: false,
        compact: true,
      ),
      closeTo(159.63, 0.01),
    );
    expect(
      libraryVideoCardMainAxisExtent(
        gridWidth: 500,
        narrow: true,
        compact: true,
      ),
      323.5,
    );
    expect(
      libraryVideoGridCrossAxisSpacing(gridWidth: 680, compact: true),
      10,
    );
    expect(
      libraryVideoGridCrossAxisSpacing(gridWidth: 880, compact: false),
      12,
    );
    expect(
      libraryVideoGridCrossAxisSpacing(gridWidth: 1200, compact: false),
      16,
    );
    expect(
      libraryVideoGridCrossAxisSpacing(gridWidth: 1600, compact: false),
      20,
    );
    expect(libraryVideoGridHorizontalPadding(false), 44);
    expect(
      libraryVideoGridMaxCrossAxisExtent(
        gridWidth: 1600,
        narrow: false,
        compact: false,
      ),
      430,
    );
    expect(
      libraryVideoGridMaxCrossAxisExtent(
        gridWidth: 2000,
        narrow: false,
        compact: false,
      ),
      500,
    );
    expect(libraryVideoCardTitleFontSize(200), 13.5);
    expect(libraryVideoCardTitleFontSize(260), 14.5);
    expect(libraryVideoCardTitleFontSize(320), 15.5);
    expect(libraryVideoCardTitleFontSize(420), 16);
    expect(libraryVideoCardMetadataHeight, 42);
    expect(libraryVideoCardMetadataHeightForTextScale(1), 42);
    expect(libraryVideoCardMetadataHeightForTextScale(1.25), 50);
    expect(libraryVideoCardMetadataHeightForTextScale(1.5), 58);
    expect(
      libraryVideoCardMainAxisExtent(
        gridWidth: 880,
        narrow: false,
        compact: false,
        textScaleFactor: 1.5,
      ),
      greaterThan(
        libraryVideoCardMainAxisExtent(
          gridWidth: 880,
          narrow: false,
          compact: false,
        ),
      ),
    );
    expect(
      libraryVideoCardMainAxisExtentForColumnCount(
        gridWidth: 1200,
        compact: false,
        columnCount: 3,
      ),
      greaterThan(
        libraryVideoCardMainAxisExtentForColumnCount(
          gridWidth: 900,
          compact: false,
          columnCount: 3,
        ),
      ),
    );
    expect(libraryVideoCardRadius, AppRadius.card);
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
    expect(libraryFavoriteOverlayOpacity, 0);
    expect(libraryDurationOverlayOpacity, 0.56);
    expect(libraryDurationOpacityForPreview(false), 1);
    expect(libraryDurationOpacityForPreview(true), 0);
    expect(libraryVideoHoverScale, 1.06);
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

  testWidgets('hover preview intent ignores fast pointer passes',
      (tester) async {
    var enterCount = 0;
    var intentCount = 0;
    var exitCount = 0;
    await tester.binding.setSurfaceSize(const Size(400, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: LibraryHoverIntentRegion(
                onEnter: () => enterCount++,
                onIntent: () => intentCount++,
                onExit: () => exitCount++,
                child: const SizedBox(width: 120, height: 80),
              ),
            ),
          ),
        ),
      ),
    );

    final region = find.byType(LibraryHoverIntentRegion);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(350, 250));
    await gesture.moveTo(tester.getCenter(region));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveTo(const Offset(350, 250));
    await tester.pump(libraryHoverPreviewStartDelay);
    expect(enterCount, 1);
    expect(exitCount, 1);
    expect(intentCount, 0);

    await gesture.moveTo(tester.getCenter(region));
    await tester.pump(
      libraryHoverPreviewStartDelay - const Duration(milliseconds: 1),
    );
    expect(intentCount, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(intentCount, 1);
    await gesture.removePointer();
  });

  testWidgets('hover preview uses a short thumbnail crossfade', (tester) async {
    var visible = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return LibraryHoverPreviewFade(
              key: const ValueKey<String>('hover-preview-fade-test'),
              visible: visible,
              child: const ColoredBox(
                key: ValueKey<String>('hover-preview-fade-child'),
                color: Colors.black,
              ),
            );
          },
        ),
      ),
    );

    update(() => visible = false);
    await tester.pump();
    final fade = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('hover-preview-fade-test')),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(fade.opacity, 0);
    expect(fade.duration, libraryHoverPreviewFadeDuration);
    expect(fade.curve, Curves.easeOutCubic);
    expect(
      find.byKey(const ValueKey<String>('hover-preview-fade-child')),
      findsOneWidget,
    );
    await tester.pump(libraryHoverPreviewFadeDuration);
  });

  testWidgets('card hover zooms only thumbnail and keeps title fixed',
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
    final zoomFinder =
        find.byKey(LibrarySmokeKeys.cardThumbnailZoom(item.path));
    final titleTopBefore = tester.getTopLeft(titleFinder).dy;
    expect(thumbnailFinder, findsOneWidget);
    ScaleTransition scaleTransition() => tester.widget<ScaleTransition>(
          find.descendant(
            of: zoomFinder,
            matching: find.byType(ScaleTransition),
          ),
        );
    expect(scaleTransition().scale.value, 1);
    final cardInkWell = tester.widget<InkWell>(
      find.byKey(LibrarySmokeKeys.cardOpen(item.path)),
    );
    expect(cardInkWell.hoverColor, Colors.transparent);
    final metadataSlots = tester
        .widgetList<SizedBox>(
          find.descendant(
            of: find.byKey(LibrarySmokeKeys.cardOpen(item.path)),
            matching: find.byType(SizedBox),
          ),
        )
        .where((box) => box.height == libraryVideoCardMetadataHeight);
    // 标题无论一行还是两行都必须真实使用同一个固定高度槽位。
    expect(metadataSlots, hasLength(1));
    final favoriteButton = tester.widget<IconButton>(
      find.byKey(LibrarySmokeKeys.cardFavorite(item.path)),
    );
    expect(
      favoriteButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      Colors.transparent,
    );
    for (final state in <WidgetState>{
      WidgetState.hovered,
      WidgetState.focused,
      WidgetState.pressed,
    }) {
      expect(
        favoriteButton.style?.overlayColor?.resolve(<WidgetState>{state}),
        Colors.transparent,
      );
    }
    final durationOverlay = tester.widget<AnimatedOpacity>(
      find.byKey(LibrarySmokeKeys.cardDuration(item.path)),
    );
    expect(durationOverlay.opacity, 1);
    expect(durationOverlay.duration, libraryHoverPreviewFadeDuration);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(titleFinder));
    await tester.pump();
    await tester.pump(
      Duration(
        milliseconds: libraryVideoHoverScaleDuration.inMilliseconds ~/ 2,
      ),
    );
    final enteringScale = scaleTransition().scale.value;
    expect(enteringScale, greaterThan(1));
    expect(enteringScale, lessThan(libraryVideoHoverScale));
    await tester.pump(libraryVideoHoverScaleDuration);
    expect(
      scaleTransition().scale.value,
      closeTo(libraryVideoHoverScale, 0.001),
    );
    expect(tester.getTopLeft(titleFinder).dy, titleTopBefore);

    // 快速移出后再移入应从当前动画进度反向衔接，不重置为 1 或 1.06。
    await gesture.moveTo(const Offset(480, 330));
    await tester.pump();
    await tester.pump(
      Duration(
        milliseconds: libraryVideoHoverScaleReverseDuration.inMilliseconds ~/ 2,
      ),
    );
    final reversingScale = scaleTransition().scale.value;
    expect(reversingScale, greaterThan(1));
    expect(reversingScale, lessThan(libraryVideoHoverScale));
    await gesture.moveTo(tester.getCenter(titleFinder));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(scaleTransition().scale.value, greaterThan(reversingScale));
    await gesture.removePointer();
  });

  testWidgets('library card keeps two-line title visible at 150% text',
      (tester) async {
    final directory = Directory(
      p.join(
        Directory.systemTemp.path,
        'local_tag_player_text_scale_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final item = _testVideo(
      path: p.join(directory.path, 'scaled-title.mp4'),
      title: '这是用于验证百分之一百五十文字缩放的双行视频标题',
    );
    final thumbnailService = ThumbnailService.forDirectory(
      directory,
      _PreviewFFmpegBackend(),
    );
    const cardWidth = 300.0;
    final cardHeight = libraryVideoCardMainAxisExtentForColumnCount(
      // 真实网格宽度包含左右 22px 内容留白；扣除后卡片宽度才是 300px。
      gridWidth: cardWidth + 44,
      compact: false,
      columnCount: 1,
      textScaleFactor: 1.5,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(500, 420),
            textScaler: TextScaler.linear(1.5),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: InteractiveVideoCard(
                  item: item,
                  thumbnailService: thumbnailService,
                  playbackSettings: PlaybackSettings.defaults,
                  onOpen: () {},
                  onEditTags: () {},
                  onToggleFavorite: () {},
                  onDelete: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final scaledMetadataSlots = tester
        .widgetList<SizedBox>(
          find.descendant(
            of: find.byKey(LibrarySmokeKeys.cardOpen(item.path)),
            matching: find.byType(SizedBox),
          ),
        )
        .where((box) => box.height == 58);
    expect(scaledMetadataSlots, hasLength(1));
    expect(find.text(item.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card more menu follows hover and keeps open action isolated',
      (tester) async {
    final directory = Directory(
      p.join(
        Directory.systemTemp.path,
        'local_tag_player_more_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final item = _testVideo(
      path: p.join(directory.path, 'more.mp4'),
      title: 'video title with more action',
    );
    final thumbnailService = ThumbnailService.forDirectory(
      directory,
      _PreviewFFmpegBackend(),
    );
    var openCount = 0;
    var editCount = 0;
    var deleteCount = 0;
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
                onOpen: () => openCount += 1,
                onEditTags: () => editCount += 1,
                onToggleFavorite: () {},
                onDelete: () => deleteCount += 1,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final titleFinder = find.text('video title with more action');
    final moreFinder = find.byKey(LibrarySmokeKeys.cardMore(item.path));
    AnimatedOpacity moreOpacity() => tester.widget<AnimatedOpacity>(
          find.ancestor(
            of: moreFinder,
            matching: find.byType(AnimatedOpacity),
          ),
        );
    final titleSizeBefore = tester.getSize(titleFinder);
    expect(moreFinder, findsOneWidget);
    expect(moreOpacity().opacity, 0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(titleFinder));
    await tester.pump();
    await tester.pump(libraryCardMoreFadeDuration);
    expect(moreOpacity().opacity, 1);
    expect(tester.getSize(titleFinder), titleSizeBefore);

    await tester.tap(moreFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(openCount, 0);
    expect(find.byKey(LibrarySmokeKeys.videoMoreEditTags), findsOneWidget);
    expect(find.byKey(LibrarySmokeKeys.videoMoreDelete), findsOneWidget);
    expect(find.text('删除文件'), findsOneWidget);

    await tester.tap(find.byKey(LibrarySmokeKeys.videoMoreEditTags));
    await tester.pump(const Duration(milliseconds: 300));
    expect(openCount, 0);
    expect(editCount, 1);
    expect(deleteCount, 0);

    await gesture.moveTo(const Offset(480, 330));
    await tester.pump();
    await tester.pump(libraryCardMoreFadeDuration);
    expect(moreOpacity().opacity, 0);

    await gesture.moveTo(tester.getCenter(titleFinder));
    await tester.pump();
    await tester.pump(libraryCardMoreFadeDuration);
    await tester.tap(moreFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(LibrarySmokeKeys.videoMoreDelete));
    await tester.pump(const Duration(milliseconds: 300));
    expect(openCount, 0);
    expect(editCount, 1);
    expect(deleteCount, 1);
    await gesture.removePointer();
  });

  testWidgets('video more menu exposes open location through platform callback',
      (tester) async {
    final directory = Directory(
      p.join(
        Directory.systemTemp.path,
        'local_tag_player_reveal_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final item = _testVideo(
      path: p.join(directory.path, 'reveal.mp4'),
      title: 'reveal location',
    );
    final thumbnailService = ThumbnailService.forDirectory(
      directory,
      _PreviewFFmpegBackend(),
    );
    var revealCount = 0;
    await tester.binding.setSurfaceSize(const Size(500, 500));
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
                onEditTags: () {},
                onRevealLocation: () => revealCount++,
                onToggleFavorite: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('reveal location')));
    await tester.pump();
    await tester.pump(libraryCardMoreFadeDuration);
    await tester.tap(find.byKey(LibrarySmokeKeys.cardMore(item.path)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(LibrarySmokeKeys.videoMoreRevealLocation),
      findsOneWidget,
    );
    expect(find.text('打开位置'), findsOneWidget);
    await tester.tap(
      find.byKey(LibrarySmokeKeys.videoMoreRevealLocation),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(revealCount, 1);
    await gesture.removePointer();
  });

  testWidgets('card selection replaces favorite and blocks playback',
      (tester) async {
    final directory = Directory(
      p.join(
        Directory.systemTemp.path,
        'local_tag_player_select_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final item = _testVideo(
      path: p.join(directory.path, 'select.mp4'),
      title: 'select video',
    );
    final thumbnailService = ThumbnailService.forDirectory(
      directory,
      _PreviewFFmpegBackend(),
    );
    var openCount = 0;
    var selectCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 230,
            child: InteractiveVideoCard(
              item: item,
              thumbnailService: thumbnailService,
              playbackSettings: PlaybackSettings.defaults,
              onOpen: () => openCount += 1,
              onEditTags: () {},
              onToggleFavorite: () {},
              onDelete: () {},
              selectionMode: true,
              selected: false,
              onToggleSelected: () => selectCount += 1,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(LibrarySmokeKeys.cardFavorite(item.path)), findsNothing);
    expect(find.byKey(LibrarySmokeKeys.cardMore(item.path)), findsNothing);
    expect(
      find.byKey(LibrarySmokeKeys.cardSelection(item.path)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(LibrarySmokeKeys.cardSelection(item.path)));
    await tester.pump();
    expect(selectCount, 1);
    expect(openCount, 0);

    await tester.tap(find.byKey(LibrarySmokeKeys.cardOpen(item.path)));
    await tester.pump();
    expect(selectCount, 2);
    expect(openCount, 0);
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
        gridWidth: 1600,
        narrow: false,
        compact: false,
      ),
      4,
    );
    expect(
      libraryVideoGridColumnCount(
        gridWidth: 2000,
        narrow: false,
        compact: false,
      ),
      4,
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

  testWidgets(
      'library scroll header hides and restores with interruptible motion',
      (WidgetTester tester) async {
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AppAccessibilityScope(
          data: const AppAccessibilityData(
            disableAnimations: false,
            accessibleNavigation: false,
            highContrast: false,
            textScaler: TextScaler.noScaling,
          ),
          child: Scaffold(
            body: Column(
              children: [
                LibraryScrollResponsiveHeader(
                  key: LibrarySmokeKeys.scrollResponsiveHeader,
                  visibleListenable: visible,
                  child: const SizedBox(height: 100),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final header = find.byKey(LibrarySmokeKeys.scrollResponsiveHeader);
    expect(tester.getSize(header).height, 100);

    visible.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getSize(header).height, inExclusiveRange(0, 100));
    await tester.pumpAndSettle();
    expect(tester.getSize(header).height, closeTo(0, 0.01));

    visible.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(header).height, inExclusiveRange(0, 100));
    await tester.pumpAndSettle();
    expect(tester.getSize(header).height, closeTo(100, 0.01));
  });

  testWidgets('library scroll chrome stays hidden until returning to top',
      (WidgetTester tester) async {
    final directory = Directory(
      p.join(
        Directory.systemTemp.path,
        'local_tag_player_scroll_chrome_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final videos = List<VideoItem>.generate(
      90,
      (index) => _testVideo(
        path: p.join(directory.path, 'video_$index.mp4'),
        title: 'video $index',
      ),
    );
    final headerEvents = <bool>[];

    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AppAccessibilityScope(
          data: const AppAccessibilityData(
            disableAnimations: false,
            accessibleNavigation: false,
            highContrast: false,
            textScaler: TextScaler.noScaling,
          ),
          child: Scaffold(
            body: VideoGrid(
              videos: videos,
              thumbnailService: ThumbnailService.forDirectory(
                directory,
                _PreviewFFmpegBackend(),
              ),
              playbackSettings: PlaybackSettings.defaults,
              dense: false,
              scrollChromeEnabled: true,
              onHeaderVisibilityChanged: headerEvents.add,
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

    final results = find.byKey(LibrarySmokeKeys.incrementalResults);
    final button = find.byKey(LibrarySmokeKeys.returnToTopButton);
    AnimatedOpacity buttonOpacity() => tester.widget<AnimatedOpacity>(
          find
              .ancestor(of: button, matching: find.byType(AnimatedOpacity))
              .first,
        );
    expect(buttonOpacity().opacity, 0);

    final controller = tester.widget<GridView>(results).controller!;
    final gesture = await tester.startGesture(tester.getCenter(results));
    // 先越过滚动手势阈值，再继续向下浏览，避免单次位移仍处于手势竞争阶段。
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -216));
    await tester.pump();
    expect(controller.offset, greaterThan(0));
    expect(headerEvents, contains(false));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 600));
    expect(headerEvents.last, isFalse);

    final firstViewport = controller.position.viewportDimension;
    controller.jumpTo(firstViewport - 1);
    await tester.pump();
    expect(buttonOpacity().opacity, 0);

    controller.jumpTo(firstViewport + 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(buttonOpacity().opacity, 1);

    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button.hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.offset, closeTo(0, 0.01));
    expect(buttonOpacity().opacity, 0);
    await tester.pump(const Duration(milliseconds: 160));
    expect(headerEvents.last, isTrue);
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
  });

  testWidgets('library scroll header removes structural motion when requested',
      (WidgetTester tester) async {
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AppAccessibilityScope(
          data: const AppAccessibilityData(
            disableAnimations: true,
            accessibleNavigation: false,
            highContrast: false,
            textScaler: TextScaler.noScaling,
          ),
          child: Scaffold(
            body: LibraryScrollResponsiveHeader(
              key: LibrarySmokeKeys.scrollResponsiveHeader,
              visibleListenable: visible,
              child: const SizedBox(height: 100),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final header = find.byKey(LibrarySmokeKeys.scrollResponsiveHeader);
    visible.value = false;
    await tester.pump();
    expect(tester.getSize(header).height, closeTo(0, 0.01));
    visible.value = true;
    await tester.pump();
    expect(tester.getSize(header).height, closeTo(100, 0.01));
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

  testWidgets('library grid keeps columns stable after sidebar width settles',
      (WidgetTester tester) async {
    final directory = Directory(
      p.join(
        Directory.systemTemp.path,
        'local_tag_player_resize_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final width = ValueNotifier<double>(900);
    addTearDown(width.dispose);
    final thumbnailService = ThumbnailService.forDirectory(
      directory,
      _PreviewFFmpegBackend(),
    );
    final videos = List<VideoItem>.generate(
      12,
      (index) => _testVideo(
        path: p.join(directory.path, 'video_$index.mp4'),
        title: index.isEven ? '短标题 $index' : '用于验证固定两行高度的较长标题 $index',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1300, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder<double>(
              valueListenable: width,
              builder: (context, currentWidth, _) => SizedBox(
                width: currentWidth,
                height: 700,
                child: VideoGrid(
                  videos: videos,
                  thumbnailService: thumbnailService,
                  playbackSettings: PlaybackSettings.defaults,
                  dense: false,
                  columnReferenceWidth: 900,
                  onOpen: (_, __) {},
                  onEditTags: (_) {},
                  onToggleFavorite: (_) {},
                  onDelete: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final resultsFinder = find.byKey(LibrarySmokeKeys.incrementalResults);
    expect(tester.getSize(resultsFinder).width, closeTo(900, 0.01));
    SliverGridDelegateWithFixedCrossAxisCount gridDelegate() =>
        tester.widget<GridView>(resultsFinder).gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount;
    expect(gridDelegate().crossAxisCount, 3);

    width.value = 1200;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // 侧栏动画期间结果区连续占满新宽度，但列数保持稳定，卡片只平滑改变尺寸。
    expect(tester.getSize(resultsFinder).width, closeTo(1200, 0.01));
    expect(gridDelegate().crossAxisCount, 3);

    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getSize(resultsFinder).width, closeTo(1200, 0.01));
    // 窗口基准宽度没有变化时，侧栏动画结束后也不能跨断点增加列数。
    expect(gridDelegate().crossAxisCount, 3);
    expect(tester.takeException(), isNull);
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
      debugTextScaleFactor: 1.5,
    ));
    await tester.pump();

    expect(find.byType(LocalTagPlayerApp), findsOneWidget);
    final accessibility = tester.widget<AppAccessibilityScope>(
      find.byType(AppAccessibilityScope),
    );
    expect(accessibility.data.textScaler.scale(20), 30);
  });

  test('debug text scale environment accepts only QA baselines', () {
    expect(
      debugTextScaleFactorFromEnvironment(
        environment: const {'LOCAL_TAG_PLAYER_QA_TEXT_SCALE': '1.25'},
      ),
      1.25,
    );
    expect(
      debugTextScaleFactorFromEnvironment(
        environment: const {'LOCAL_TAG_PLAYER_QA_TEXT_SCALE': '1.75'},
      ),
      isNull,
    );
    expect(
      debugTextScaleFactorFromEnvironment(environment: const {}),
      isNull,
    );
  });

  test('player time label yields space to centered transport at large text',
      () {
    expect(
      playerControlsShowTime(availableWidth: 780, textScaleFactor: 1),
      isTrue,
    );
    expect(
      playerControlsShowTime(availableWidth: 780, textScaleFactor: 1.25),
      isFalse,
    );
    expect(
      playerControlsShowTime(availableWidth: 840, textScaleFactor: 1.25),
      isTrue,
    );
    expect(
      playerControlsShowTime(availableWidth: 899, textScaleFactor: 1.5),
      isFalse,
    );
    expect(
      playerControlsShowTime(availableWidth: 900, textScaleFactor: 1.5),
      isTrue,
    );
  });

  testWidgets('library panel motion combines visible slide fade and scale',
      (WidgetTester tester) async {
    const motionKey = ValueKey('test.libraryPanelMotion');

    await tester.pumpWidget(
      const MaterialApp(
        home: LibraryPanelContentTransition(
          key: motionKey,
          animation: AlwaysStoppedAnimation<double>(0),
          horizontalOffset: 0.28,
          alignment: Alignment.centerRight,
          child: SizedBox(width: 200, height: 300),
        ),
      ),
    );

    final motion = find.byKey(motionKey);
    expect(
      tester
          .widget<SlideTransition>(
            find.descendant(of: motion, matching: find.byType(SlideTransition)),
          )
          .position
          .value,
      const Offset(0.28, 0),
    );
    expect(
      tester
          .widget<ScaleTransition>(
            find.descendant(of: motion, matching: find.byType(ScaleTransition)),
          )
          .scale
          .value,
      closeTo(0.965, 0.0001),
    );
    expect(
      tester
          .widget<FadeTransition>(
            find.descendant(of: motion, matching: find.byType(FadeTransition)),
          )
          .opacity
          .value,
      0,
    );
    expect(libraryPanelMotionDuration, const Duration(milliseconds: 320));
  });

  testWidgets('library sidebar collapses to icons and keeps actions reachable',
      (WidgetTester tester) async {
    var pickFolderCount = 0;
    var tagCenterCount = 0;
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
                onOpenTagManager: () => tagCenterCount++,
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
    expect(find.text('标签中心'), findsOneWidget);
    await tester.tap(find.byKey(LibrarySmokeKeys.sidebarTagCenter));
    await tester.pump();
    expect(tagCenterCount, 1);
    expect(find.text('添加目录'), findsNothing);
    expect(find.byTooltip('新增本地库路径'), findsOneWidget);
    expect(
      find.byKey(LibrarySmokeKeys.sidebarCollapseToggle),
      findsOneWidget,
    );
    expect(find.byTooltip('折叠功能栏'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedRotation>(
            find.descendant(
              of: find.byKey(LibrarySmokeKeys.sidebarCollapseToggle),
              matching: find.byType(AnimatedRotation),
            ),
          )
          .turns,
      0,
    );
    expect(
      find.byIcon(Icons.keyboard_double_arrow_left_rounded),
      findsNothing,
    );
    expect(
      find.byIcon(Icons.keyboard_double_arrow_right_rounded),
      findsNothing,
    );
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);
    await tester.tap(find.byTooltip('新增本地库路径'));
    await tester.pump();
    expect(pickFolderCount, 1);

    await tester.tap(find.byKey(LibrarySmokeKeys.sidebarCollapseToggle));
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      find.descendant(
        of: find.byKey(LibrarySmokeKeys.sidebarSurface),
        matching: find.byType(LibraryPanelContentTransition),
      ),
      findsWidgets,
    );
    await tester.pumpAndSettle();
    expect(find.text('媒体库'), findsNothing);
    expect(find.text('标签中心'), findsNothing);
    expect(find.byTooltip('媒体库'), findsOneWidget);
    expect(find.byTooltip('标签中心'), findsOneWidget);
    await tester.tap(find.byKey(LibrarySmokeKeys.sidebarTagCenter));
    await tester.pump();
    expect(tagCenterCount, 2);
    expect(
        tester.getSize(find.byKey(LibrarySmokeKeys.sidebarSurface)).width, 76);
    expect(find.byTooltip('展开功能栏'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedRotation>(
            find.descendant(
              of: find.byKey(LibrarySmokeKeys.sidebarCollapseToggle),
              matching: find.byType(AnimatedRotation),
            ),
          )
          .turns,
      0.25,
    );
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);

    await tester.tap(find.byKey(LibrarySmokeKeys.sidebarCollapseToggle));
    await tester.pumpAndSettle();
    expect(find.text('媒体库'), findsOneWidget);
  });

  testWidgets('compact sort menu opens below its trigger without covering it',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(452, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        onSearchChanged: (_) {},
        layoutSize: LayoutSize.medium,
        videoCount: 171,
        selectedTags: const <String>['原神'],
        onEnterSelectionMode: () {},
      ),
    );

    await tester.tap(find.byKey(LibrarySmokeKeys.topSortFieldButton));
    await tester.pumpAndSettle();

    final buttonRect =
        tester.getRect(find.byKey(LibrarySmokeKeys.topSortFieldButton));
    final firstItemRect = tester.getRect(
      find.byKey(LibrarySmokeKeys.topSortMenuItem(SortMode.name)),
    );
    expect(firstItemRect.top, greaterThanOrEqualTo(buttonRect.bottom + 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded sort field and menu share a compact width',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        onSearchChanged: (_) {},
        videoCount: 171,
        onEnterSelectionMode: () {},
      ),
    );

    final buttonFinder = find.byKey(LibrarySmokeKeys.topSortFieldButton);
    final buttonRect = tester.getRect(buttonFinder);
    expect(buttonRect.width, closeTo(168, 0.01));

    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();

    final firstItemRect = tester.getRect(
      find.byKey(LibrarySmokeKeys.topSortMenuItem(SortMode.name)),
    );
    expect(firstItemRect.width, closeTo(buttonRect.width, 0.01));
    expect(firstItemRect.left, closeTo(buttonRect.left, 0.01));
    expect(firstItemRect.top, greaterThanOrEqualTo(buttonRect.bottom + 6));
    expect(tester.takeException(), isNull);
  });

  test('reference top bar collapses actions below expanded width', () {
    expect(LayoutBreakpoints.fromWidth(699), LayoutSize.compact);
    expect(LayoutBreakpoints.fromWidth(900), LayoutSize.medium);
    expect(LayoutBreakpoints.fromWidth(1280), LayoutSize.expanded);

    expect(
      referenceTopBarSearchShouldFillRow(LayoutSize.expanded, 1600),
      isFalse,
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

  testWidgets('medium top bar keeps search and actions on one line',
      (tester) async {
    tester.view.physicalSize = const Size(452, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        onSearchChanged: (_) {},
        layoutSize: LayoutSize.medium,
        videoCount: 171,
        selectedTags: const <String>['原神', '雷神'],
        onEnterSelectionMode: () {},
      ),
    );
    await tester.pump();

    expect(find.byKey(LibrarySmokeKeys.searchField), findsOneWidget);
    expect(find.byTooltip('排序字段：日期'), findsOneWidget);
    expect(find.byTooltip('多选'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded library header separates title, actions, and filters',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        onSearchChanged: (_) {},
        videoCount: 171,
        selectedTags: const <String>['原神', '雷神'],
        onClearAll: () {},
        onEnterSelectionMode: () {},
      ),
    );
    await tester.pump();

    expect(find.text('原神'), findsOneWidget);
    expect(find.text('雷神'), findsOneWidget);
    final searchRect =
        tester.getRect(find.byKey(LibrarySmokeKeys.searchSurface));
    final statusRect =
        tester.getRect(find.byKey(LibrarySmokeKeys.filterStatusArea));
    final actionsRect =
        tester.getRect(find.byKey(LibrarySmokeKeys.toolbarActions));
    final sortRect =
        tester.getRect(find.byKey(LibrarySmokeKeys.topSortFieldButton));
    final directionRect =
        tester.getRect(find.byTooltip('\u5207\u6362\u4e3a\u6b63\u5e8f'));
    final resultRect =
        tester.getRect(find.byKey(LibrarySmokeKeys.toolbarResultStatus));
    expect(resultRect.bottom, lessThan(searchRect.top));
    expect(searchRect.right, lessThan(actionsRect.left));
    expect(sortRect.left - searchRect.right, lessThanOrEqualTo(24));
    expect(searchRect.bottom, lessThan(statusRect.top));
    expect(sortRect.right, lessThanOrEqualTo(actionsRect.left));
    // 桌面排序字段保持紧凑稳定，少量响应式余量只留在动作分组之间。
    expect(sortRect.width, closeTo(168, 0.01));
    expect(
      directionRect.left - sortRect.right,
      inInclusiveRange(6, 10),
    );
    expect(
      actionsRect.left - directionRect.right,
      inInclusiveRange(12, 40),
    );
    expect(find.text(sortModeLabel(SortMode.recent)), findsOneWidget);
    expect(
      tester.getSize(find.byKey(LibrarySmokeKeys.searchInputLane)).width,
      greaterThan(600),
    );
    final chips = tester.widgetList<InputChip>(
      find.descendant(
        of: find.byKey(LibrarySmokeKeys.filterStatusArea),
        matching: find.byType(InputChip),
      ),
    );
    expect(chips, hasLength(2));
    for (final chip in chips) {
      expect(chip.side, BorderSide.none);
      expect(chip.labelStyle?.color, libraryText);
      expect(chip.color?.resolve(<WidgetState>{}), librarySurfaceAlt);
      expect(
        chip.color?.resolve(<WidgetState>{WidgetState.hovered}),
        isNot(librarySurfaceAlt),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded library header stays compact at 150 percent text',
      (tester) async {
    tester.view.physicalSize = const Size(1870, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        onSearchChanged: (_) {},
        videoCount: 11163,
        onEnterSelectionMode: () {},
        onToggleTagPanel: () {},
        accessibility: const AppAccessibilityData(
          disableAnimations: false,
          accessibleNavigation: false,
          highContrast: false,
          textScaler: TextScaler.linear(1.5),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('11163 个视频'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(LibrarySmokeKeys.libraryResultToolbar)).height,
      lessThan(170),
    );
    expect(tester.takeException(), isNull);
  });

  test('library toolbar keeps clear breathing room above the first card row',
      () {
    expect(libraryTopBarBottomSpacing, 18);
    expect(libraryTopBarBottomSpacing, greaterThan(12));
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

  test('player queue sidebar preserves Apple-style video-first proportions',
      () {
    expect(playerQueueLocatorHeight, 48);
    expect(playerQueueSidebarWidthForWindow(960), 360);
    expect(playerQueueSidebarWidthForWindow(1280), 360);
    expect(playerQueueSidebarWidthForWindow(1600), closeTo(448, 0.001));
    expect(playerQueueSidebarWidthForWindow(1920), 460);
  });

  testWidgets('player queue search expands from the count action',
      (tester) async {
    String? submittedQuery;
    var searchOutcome = PlayerQueueSearchOutcome.played;
    final searchVisibility = <bool>[];
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
              onSearch: (query) {
                submittedQuery = query;
                return searchOutcome;
              },
              onSearchVisibilityChanged: searchVisibility.add,
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
    expect(find.text('查找并播放下一条'), findsOneWidget);
    expect(find.text('Enter 查找并播放下一条匹配视频'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byKey(searchFieldKey)).autofocus, isTrue);
    expect(searchVisibility, <bool>[true]);
    expect(
      playerFocusIsEditable(FocusManager.instance.primaryFocus),
      isTrue,
    );
    await tester.enterText(find.byKey(searchFieldKey), 'chamosan');
    await tester.tap(find.byKey(const ValueKey('player.queueSearchSubmit')));
    await tester.pump();
    expect(submittedQuery, 'chamosan');
    expect(find.text('已切换到下一条匹配视频'), findsOneWidget);

    searchOutcome = PlayerQueueSearchOutcome.noMatch;
    await tester.enterText(find.byKey(searchFieldKey), 'missing');
    await tester.tap(find.byKey(const ValueKey('player.queueSearchSubmit')));
    await tester.pump();
    expect(find.text('当前筛选队列没有匹配项'), findsOneWidget);

    await tester.enterText(find.byKey(searchFieldKey), '');
    searchOutcome = PlayerQueueSearchOutcome.emptyQuery;
    await tester.tap(find.byKey(const ValueKey('player.queueSearchSubmit')));
    await tester.pump();
    expect(find.text('请先输入关键词'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(searchFieldKey), findsNothing);
    expect(searchVisibility, <bool>[true, false]);
  });

  testWidgets('player route owns semantics and shortcut feedback is live',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PlayerRouteSemantics(
          child: PlayerShortcutFeedback(
            visible: true,
            label: '前进 5 秒',
            icon: Icons.forward_5_rounded,
          ),
        ),
      ),
    );

    final blocker = tester.widget<BlockSemantics>(
      find.byKey(const ValueKey('player.route.blockSemantics')),
    );
    final routeSemantics = tester.widget<Semantics>(
      find.byKey(const ValueKey('player.route.semantics')),
    );
    final feedbackSemantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('player.shortcutFeedback')),
            matching: find.byType(Semantics),
          )
          .first,
    );

    expect(blocker.blocking, isTrue);
    expect(routeSemantics.properties.scopesRoute, isTrue);
    expect(routeSemantics.properties.namesRoute, isTrue);
    expect(routeSemantics.properties.label, '播放器');
    expect(feedbackSemantics.properties.liveRegion, isTrue);
    expect(feedbackSemantics.properties.label, '快捷键反馈：前进 5 秒');
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('player.shortcutFeedback')),
          )
          .opacity,
      1,
    );
  });

  test('player exit preserves texture after acknowledged pause', () {
    expect(
      playerExitStopShouldStartBeforePop(pauseAcknowledged: true),
      isFalse,
    );
    expect(
      playerExitStopShouldStartBeforePop(pauseAcknowledged: false),
      isTrue,
    );
  });

  test('library excludes semantics only while player route is active', () {
    expect(
      libraryRouteShouldExcludeSemantics(playerRouteActive: true),
      isTrue,
    );
    expect(
      libraryRouteShouldExcludeSemantics(playerRouteActive: false),
      isFalse,
    );
  });

  testWidgets('player delete dialog keeps recycle-bin action explicit',
      (tester) async {
    final item = _testVideo(path: r'X:\test-media\clip.mp4', title: 'clip');
    VideoDeleteDecision? result;
    var initialMoveToTrash = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showPlayerDeleteConfirmationDialog(
                context,
                item,
                initialMoveLocalFileToTrash: initialMoveToTrash,
              );
            },
            child: const Text('打开删除确认'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开删除确认'));
    await tester.pumpAndSettle();
    final dialogTheme = Theme.of(tester.element(find.byType(AlertDialog)));
    expect(dialogTheme.colorScheme.brightness, Brightness.dark);
    expect(dialogTheme.dialogTheme.backgroundColor, librarySurface);
    expect(
      tester
          .widget<Checkbox>(
            find.descendant(
              of: find.byKey(const ValueKey('deleteDialog.moveToTrash')),
              matching: find.byType(Checkbox),
            ),
          )
          .value,
      isFalse,
    );
    expect(find.text('不再提示'), findsOneWidget);
    expect(find.text('仅移出媒体库'), findsOneWidget);
    await tester.tap(find.text('仅移出媒体库'));
    await tester.pumpAndSettle();
    expect(result?.moveLocalFileToTrash, isFalse);
    expect(result?.dontAskAgain, isFalse);

    result = null;
    initialMoveToTrash = true;
    await tester.tap(find.text('打开删除确认'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Checkbox>(
            find.descendant(
              of: find.byKey(const ValueKey('deleteDialog.moveToTrash')),
              matching: find.byType(Checkbox),
            ),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.text('不再提示'));
    await tester.pump();
    await tester.tap(find.text('移入回收站并移除记录'));
    await tester.pumpAndSettle();
    expect(result?.moveLocalFileToTrash, isTrue);
    expect(result?.dontAskAgain, isTrue);
  });

  testWidgets('player side panel switches between queue and current details',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var editCount = 0;
    var renameCount = 0;
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
              onRenameFile: () => renameCount++,
              onEditManualTags: () => editCount++,
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
    expect(segmentSize.height, 36);
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
    expect(initialQueueDecoration.gradient, isNull);
    expect(initialQueueDecoration.color, isNot(Colors.transparent));
    expect(initialDetailsDecoration.gradient, isNull);
    expect(initialDetailsDecoration.color, Colors.transparent);

    await tester.tap(find.byKey(const ValueKey('player.sidebar.tab.details')));
    await tester.pump(const Duration(milliseconds: 60));

    // 旧层级先退出，新层级后进入；中点两侧均不可同时绘制。
    expect(find.text('筛选结果列表测试'), findsOneWidget);
    expect(find.text('当前视频详情'), findsOneWidget);
    final queueOpacity = tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.text('筛选结果列表测试'),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    final detailsOpacity = tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.text('当前视频详情'),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    expect(queueOpacity == 0 || detailsOpacity == 0, isTrue);
    await tester.pumpAndSettle();

    expect(find.text('筛选结果列表测试'), findsNothing);
    expect(find.text('当前视频详情'), findsOneWidget);
    final selectedDetailsDecoration = tester
        .widget<AnimatedContainer>(
          find.byKey(
            const ValueKey('player.sidebar.tab.details.surface'),
          ),
        )
        .decoration as BoxDecoration;
    expect(selectedDetailsDecoration.gradient, isNull);
    expect(selectedDetailsDecoration.color, isNot(Colors.transparent));
    expect(find.text('clip.mp4'), findsOneWidget);
    expect(find.text('1920×1080'), findsOneWidget);
    expect(find.text('H264 / AAC'), findsOneWidget);
    expect(find.text('原神'), findsOneWidget);
    expect(find.text('雷神'), findsOneWidget);
    expect(find.text('编辑标签'), findsNothing);
    expect(find.byTooltip('重命名文件'), findsOneWidget);
    expect(find.text('打开位置'), findsNothing);
    expect(find.text('更多操作'), findsNothing);
    expect(find.byKey(const ValueKey('player.more')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('player.details.renameFile')));
    await tester.pump();
    expect(renameCount, 1);
    expect(editCount, 0);

    await tester.ensureVisible(
      find.byKey(const ValueKey('player.details.editTags')),
    );
    await tester.tap(find.widgetWithText(ActionChip, '继续添加'));
    await tester.pump();
    expect(editCount, 1);

    await tester.tap(find.byKey(const ValueKey('player.sidebar.tab.queue')));
    await tester.pumpAndSettle();
    expect(find.text('筛选结果列表测试'), findsOneWidget);
    expect(find.text('当前视频详情'), findsNothing);
  });

  testWidgets('player rename dialog preserves extension and validates basename',
      (tester) async {
    final item = VideoItem(
      path: r'X:\test-media\clip.mp4',
      title: 'clip',
      folder: r'X:\test-media',
      tags: <String>{},
      addedAt: DateTime.utc(2026, 7, 21),
    );
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showPlayerRenameFileDialog(context, item: item);
            },
            child: const Text('打开重命名'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开重命名'));
    await tester.pumpAndSettle();
    expect(find.text('只修改文件名，标签请在下方“标签”区域维护。'), findsOneWidget);
    expect(find.text('.mp4'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('player.renameFile.confirm')),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('player.renameFile.input')),
      'bad/name',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('player.renameFile.confirm')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('player.renameFile.confirm')));
    await tester.pump();
    expect(find.textContaining('文件名不能包含'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('player.renameFile.input')),
      'renamed clip',
    );
    await tester.tap(find.byKey(const ValueKey('player.renameFile.confirm')));
    await tester.pumpAndSettle();
    expect(result, 'renamed clip');
  });

  test('player rename filename validation rejects unsafe desktop names', () {
    expect(playerRenameFileNameError(''), isNotNull);
    expect(playerRenameFileNameError('bad/name'), isNotNull);
    expect(playerRenameFileNameError('CON'), isNotNull);
    expect(playerRenameFileNameError('clip.'), isNotNull);
    expect(playerRenameFileNameError('新文件名'), isNull);
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
      denseResultGrid: true,
    );
    await saveLibrarySortPreferences(paths, preferences);
    final loaded = await loadLibrarySortPreferences(paths);

    expect(loaded.mode, SortMode.folder);
    expect(loaded.direction, SortDirection.ascending);
    expect(loaded.denseResultGrid, isTrue);
    expect(await paths.settingsFile(),
        isNot(await paths.librarySortPreferencesFile()));
  });

  test('library picker prefers current path then managed root', () {
    expect(
      preferredLibraryPickerDirectory(
        currentPath: r'X:\test-media\album',
        roots: const <String>[r'X:\test-media'],
      ),
      r'X:\test-media\album',
    );
    expect(
      preferredLibraryPickerDirectory(
        currentPath: null,
        roots: const <String>[r'X:\test-media', r'E:\archive'],
      ),
      r'X:\test-media',
    );
    expect(
      preferredLibraryPickerDirectory(
        currentPath: null,
        roots: const <String>[],
      ),
      isNull,
    );
  });

  test('cache failures are an explained subset of missing items', () async {
    final directory = await Directory.systemTemp.createTemp('ltp_cache_p2_');
    addTearDown(() async {
      await directory.delete(recursive: true);
    });
    final service = ThumbnailService.forDirectory(
      directory,
      _PreviewFFmpegBackend(),
    );
    final item = _testVideo(
      path: p.join(directory.path, 'missing.mp4'),
      title: 'broken thumbnail',
    )..thumbnailError = 'ffmpeg: test failure';

    final stats = await service.statsFor(<VideoItem>[item]);

    expect(stats.total, 1);
    expect(stats.missing, 1);
    expect(stats.errors, 1);
    expect(stats.failures.single.item.videoId, item.videoId);
    expect(stats.failures.single.reason, 'ffmpeg: test failure');
    expect(service.clearFailures(<VideoItem>[item]), 1);
    expect(item.thumbnailError, isNull);
  });

  test('ultrawide list file size labels stay compact', () {
    expect(libraryVideoFileSizeLabel(null), '大小读取中');
    expect(libraryVideoFileSizeLabel(512), '512 B');
    expect(libraryVideoFileSizeLabel(1536), '1.5 KB');
    expect(libraryVideoFileSizeLabel(3 * 1024 * 1024 * 1024), '3.0 GB');
  });

  test('maintenance workspaces reuse the media library dark surfaces', () {
    final theme = maintenanceWorkspaceTheme(ThemeData(useMaterial3: true));

    expect(theme.scaffoldBackgroundColor, libraryBackground);
    expect(theme.cardTheme.color, librarySurface);
    expect(theme.dialogTheme.backgroundColor, librarySurface);
    expect(
      theme.inputDecorationTheme.fillColor,
      librarySurfaceAlt,
    );
    expect(
      theme.outlinedButtonTheme.style?.foregroundColor
          ?.resolve(const <WidgetState>{}),
      libraryText,
    );
    expect(
      theme.textButtonTheme.style?.foregroundColor
          ?.resolve(const <WidgetState>{}),
      libraryAccent,
    );
    expect(
      theme.filledButtonTheme.style?.backgroundColor
          ?.resolve(const <WidgetState>{}),
      appAccentViolet,
    );
  });

  test('settings workspace uses the shared Apple card radius', () {
    final theme = settingsWorkspaceTheme(ThemeData(useMaterial3: true));
    final shape = theme.cardTheme.shape! as RoundedRectangleBorder;

    expect(shape.borderRadius, BorderRadius.circular(AppRadius.card));
    expect(shape.side.color, libraryBorder);
    expect(theme.canvasColor, librarySurfaceAlt);
    expect(theme.hoverColor, appAccentViolet.withValues(alpha: 0.10));
    expect(theme.focusColor, appAccentViolet.withValues(alpha: 0.16));
  });

  testWidgets('player chrome keeps non-primary button surface clear at rest',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerChromeButton(
            tooltip: '测试按钮',
            icon: Icons.settings_rounded,
            onPressed: () {},
          ),
        ),
      ),
    );

    final surface = tester.widget<AppInteractionSurface>(
      find.byType(AppInteractionSurface),
    );
    expect(surface.backgroundColor, Colors.transparent);
    expect(surface.material, AppSurfaceMaterial.solid);
    expect(surface.showBorder, isFalse);
  });

  testWidgets('settings landing page only shows grouped feature entries',
      (tester) async {
    final openedSections = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsLandingList(
            resumeBehavior: PlaybackResumeBehavior.ask,
            confirmBeforeDeletingVideo: true,
            moveDeletedFileToTrash: false,
            onOpenPlayback: () => openedSections.add('playback'),
            onOpenPlayerInteraction: () => openedSections.add('interaction'),
            onOpenFileDeletion: () => openedSections.add('deletion'),
            onOpenDataBackup: () => openedSections.add('backup'),
            onOpenCache: () => openedSections.add('cache'),
          ),
        ),
      ),
    );

    expect(find.text('播放设置'), findsOneWidget);
    expect(find.text('数据与维护'), findsOneWidget);
    expect(find.text('当前策略：每次询问 · 解码设置'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings.resumeBehavior.summary')),
      findsOneWidget,
    );
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(DropdownButtonFormField<dynamic>), findsNothing);
    expect(find.byType(AppInteractionSurface), findsNWidgets(5));

    for (final entry in <(String, String)>[
      ('settings.category.playback', 'playback'),
      ('settings.category.playerInteraction', 'interaction'),
      ('settings.category.fileDeletion', 'deletion'),
      ('settings.category.dataBackup', 'backup'),
      ('settings.category.cache', 'cache'),
    ]) {
      await tester.tap(find.byKey(ValueKey(entry.$1)));
      await tester.pump();
      expect(openedSections.last, entry.$2);
    }
  });

  testWidgets('delete file settings remain readable at 150 percent',
      (tester) async {
    bool? confirmChanged;
    bool? trashChanged;
    await tester.pumpWidget(
      deleteFileSettingsSmokeHarness(
        confirmBeforeDeletingVideo: false,
        moveDeletedFileToTrash: true,
        textScaler: TextScaler.linear(1.5),
        onConfirmChanged: (value) => confirmChanged = value,
        onMoveToTrashChanged: (value) => trashChanged = value,
      ),
    );
    await tester.pump();

    expect(find.text('删除前显示提示框'), findsOneWidget);
    expect(find.text('同步将本地文件移入回收站'), findsOneWidget);
    expect(find.textContaining('直接把本地文件移入回收站'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('settings.fileDeletion.confirm')),
    );
    await tester.tap(
      find.byKey(const ValueKey('settings.fileDeletion.moveToTrash')),
    );
    expect(confirmChanged, isTrue);
    expect(trashChanged, isFalse);
  });

  testWidgets('shortcut recorder captures keys and keeps conflicts visible',
      (tester) async {
    String? captured;
    String? error;
    await tester.pumpWidget(
      MaterialApp(
        theme: settingsWorkspaceTheme(ThemeData(useMaterial3: true)),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(720, 600),
            textScaler: TextScaler.linear(1.5),
          ),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 360,
                child: PlayerShortcutRecorder(
                  action: PlayerShortcutAction.playPause,
                  shortcut: 'Space',
                  errorText: error,
                  onCaptured: (shortcut) {
                    captured = shortcut;
                    setState(
                      () => error = '与“全屏 / 退出全屏”冲突，请按其它按键',
                    );
                    return false;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('settings.shortcut.playPause')),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(captured, 'Control+F');
    final errorText = tester.widget<Text>(
      find.byKey(const ValueKey('settings.shortcut.playPause.error')),
    );
    expect(errorText.style?.color, playerDanger);
    expect(find.text('请按键…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-main route accepts keyboard and mouse back input',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (homeContext) => FilledButton(
            onPressed: () {
              Navigator.of(homeContext).push(
                MaterialPageRoute<void>(
                  builder: (pageContext) => AppRouteBackInputRegion(
                    shortcutProvider: () => 'Escape',
                    onBack: () {
                      Navigator.of(pageContext).maybePop();
                    },
                    child: const Scaffold(body: Text('二级页面')),
                  ),
                ),
              );
            },
            child: const Text('打开二级页'),
          ),
        ),
      ),
    );

    Future<void> openPage() async {
      await tester.tap(find.text('打开二级页'));
      await tester.pumpAndSettle();
      expect(find.text('二级页面'), findsOneWidget);
    }

    await openPage();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('打开二级页'), findsOneWidget);

    await openPage();
    final target = tester.getCenter(find.text('二级页面'));
    tester.binding.handlePointerEvent(
      PointerDownEvent(
        position: target,
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('打开二级页'), findsOneWidget);
  });

  testWidgets('route back survives shortcut recorder focus release',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (homeContext) => FilledButton(
            onPressed: () {
              Navigator.of(homeContext).push(
                MaterialPageRoute<void>(
                  builder: (pageContext) => AppRouteBackInputRegion(
                    shortcutProvider: () => 'Escape',
                    onBack: () => Navigator.of(pageContext).maybePop(),
                    child: Scaffold(
                      body: PlayerShortcutRecorder(
                        action: PlayerShortcutAction.navigateBack,
                        shortcut: 'Escape',
                        onCaptured: (shortcut) => true,
                      ),
                    ),
                  ),
                ),
              );
            },
            child: const Text('打开录制页'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开录制页'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('settings.shortcut.navigateBack')),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('打开录制页'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('打开录制页'), findsOneWidget);
  });

  test('shortcut conflicts are rejected without swapping bindings', () {
    final bindings = Map<PlayerShortcutAction, String>.of(
      PlaybackSettings.defaultShortcuts,
    );
    expect(
      playerShortcutConflictMessage(
        action: PlayerShortcutAction.playPause,
        shortcut: 'F',
        bindings: bindings,
      ),
      contains('全屏 / 退出全屏'),
    );
    expect(
      playerShortcutConflictMessage(
        action: PlayerShortcutAction.playPause,
        shortcut: 'Control+Shift+Delete',
        bindings: bindings,
      ),
      contains('系统保留操作'),
    );
    expect(bindings, PlaybackSettings.defaultShortcuts);
  });

  testWidgets(
      'data backup panel groups scope status and actions at 150 percent',
      (tester) async {
    final actions = <String>[];
    bool? enabled;

    await tester.pumpWidget(
      dataBackupSettingsSmokeHarness(
        progress: 0.72,
        textScaler: TextScaler.linear(1.5),
        onEnabledChanged: (value) => enabled = value,
        onRunNow: () => actions.add('run'),
        onCheckIntegrity: () => actions.add('check'),
        onExport: () => actions.add('export'),
      ),
    );
    await tester.pump();

    expect(find.text('同步状态'), findsOneWidget);
    expect(
      find.textContaining('不复制视频文件，也不改变 folder 标签来源'),
      findsOneWidget,
    );
    expect(find.text('维护动作'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(enabled, isFalse);

    for (final entry in <(String, String)>[
      ('settings.dataBackup.runNow', 'run'),
      ('settings.dataBackup.checkIntegrity', 'check'),
      ('settings.dataBackup.export', 'export'),
    ]) {
      final action = find.byKey(ValueKey(entry.$1));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();
      expect(actions.last, entry.$2);
    }
  });

  testWidgets('cache diagnostics groups stats at 150 percent text scale',
      (tester) async {
    const stats = CacheStats(
      total: 11163,
      cached: 1682,
      missing: 9481,
      errors: 0,
      queued: 0,
      pendingBackgroundRequests: 0,
      active: 0,
      activeBackground: 0,
      maxConcurrent: 4,
      maxBackground: 2,
      maxBackgroundQueued: 500,
      paused: false,
      completedThisRun: 0,
      failedThisRun: 0,
      ffmpegCompleted: 0,
      fallbackCompleted: 0,
      averageMs: 0,
      failures: <CacheFailureDetail>[],
    );

    await tester.pumpWidget(
      cacheDiagnosticsSmokeHarness(
        stats: stats,
        textScaler: const TextScaler.linear(1.5),
      ),
    );

    expect(
        find.byKey(const ValueKey('settings.cache.coverage')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.cache.metric.total')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings.cache.metric.cached')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings.cache.metric.missing')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings.cache.metric.errors')),
        findsOneWidget);
    expect(find.text('当前没有失败项'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('settings.cache.retryFailures')),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cache diagnostics preserves failure actions', (tester) async {
    final item = _testVideo(
      path: r'C:\cache\broken.mp4',
      title: 'broken thumbnail',
    );
    final stats = CacheStats(
      total: 1,
      cached: 0,
      missing: 1,
      errors: 1,
      queued: 0,
      pendingBackgroundRequests: 0,
      active: 0,
      activeBackground: 0,
      maxConcurrent: 4,
      maxBackground: 2,
      maxBackgroundQueued: 500,
      paused: false,
      completedThisRun: 0,
      failedThisRun: 1,
      ffmpegCompleted: 0,
      fallbackCompleted: 0,
      averageMs: 12,
      failures: <CacheFailureDetail>[
        CacheFailureDetail(item: item, reason: 'ffmpeg: test failure'),
      ],
    );
    var retryCount = 0;
    var clearCount = 0;

    await tester.pumpWidget(
      cacheDiagnosticsSmokeHarness(
        stats: stats,
        onRetry: () => retryCount++,
        onClear: () => clearCount++,
      ),
    );

    expect(
      find.byKey(const ValueKey('settings.cache.failureSemantics')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings.cache.failureDetails')),
      findsOneWidget,
    );
    final retryButton =
        find.byKey(const ValueKey('settings.cache.retryFailures'));
    await tester.ensureVisible(retryButton);
    await tester.tap(retryButton);
    await tester.pump();
    final clearButton =
        find.byKey(const ValueKey('settings.cache.clearFailures'));
    await tester.ensureVisible(clearButton);
    await tester.tap(clearButton);
    await tester.pump();

    expect(retryCount, 1);
    expect(clearCount, 1);
  });

  testWidgets('maintenance actions keep visual keyboard order at 125 and 150',
      (tester) async {
    for (final scale in <double>[1.25, 1.5]) {
      await tester.pumpWidget(
        dataBackupSettingsSmokeHarness(
          textScaler: TextScaler.linear(scale),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(_primaryFocusIsInside(find.byType(SwitchListTile)), isTrue);
      for (final key in <String>[
        'settings.dataBackup.runNow',
        'settings.dataBackup.checkIntegrity',
        'settings.dataBackup.export',
      ]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        expect(_primaryFocusIsInside(find.byKey(ValueKey(key))), isTrue);
      }

      final failedItem = _testVideo(
        path: r'C:\cache\focus.mp4',
        title: 'focus thumbnail',
      );
      await tester.pumpWidget(
        cacheDiagnosticsSmokeHarness(
          textScaler: TextScaler.linear(scale),
          stats: CacheStats(
            total: 1,
            cached: 0,
            missing: 1,
            errors: 1,
            queued: 0,
            pendingBackgroundRequests: 0,
            active: 0,
            activeBackground: 0,
            maxConcurrent: 4,
            maxBackground: 2,
            maxBackgroundQueued: 500,
            paused: false,
            completedThisRun: 0,
            failedThisRun: 1,
            ffmpegCompleted: 0,
            fallbackCompleted: 0,
            averageMs: 12,
            failures: <CacheFailureDetail>[
              CacheFailureDetail(
                item: failedItem,
                reason: 'focused failure',
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(
        _primaryFocusIsInside(
          find.byKey(const ValueKey('settings.cache.failureDetails')),
        ),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(
        _primaryFocusIsInside(
          find.byKey(const ValueKey('settings.cache.retryFailures')),
        ),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(
        _primaryFocusIsInside(
          find.byKey(const ValueKey('settings.cache.clearFailures')),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('tag manager search uses one stable TextField chain',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var changeCount = 0;

    await tester.pumpWidget(
      tagManagerSearchSmokeHarness(
        controller: controller,
        onChanged: () => changeCount++,
      ),
    );

    expect(find.byType(SearchBar), findsNothing);
    final field = find.byKey(const ValueKey('tagManager.search'));
    expect(field, findsOneWidget);
    await tester.enterText(field, '雷神');
    await tester.pump();
    expect(controller.text, '雷神');
    expect(changeCount, 1);
    await tester.tap(find.byTooltip('清除标签搜索'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(changeCount, 2);
  });

  testWidgets('tag manager group chips expose selected feedback',
      (tester) async {
    const groups = <TagGroup>[
      TagGroup(id: 'genre', name: 'genre', displayName: '类型', items: []),
      TagGroup(id: 'actor', name: 'actor', displayName: '人物', items: []),
    ];
    await tester.pumpWidget(tagManagerGroupSummarySmokeHarness(groups));

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('tagManager.group.all')),
          )
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('tagManager.group.genre')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('tagManager.group.genre')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('tagManager.group.all')),
          )
          .selected,
      isFalse,
    );
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('tag detail anchors its menu and keeps explicit focus order',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final scale in <double>[1.25, 1.5]) {
      await tester.pumpWidget(
        KeyedSubtree(
          key: ValueKey('tagManager.detail.scale.$scale'),
          child: tagManagerDetailSmokeHarness(
            textScaler: TextScaler.linear(scale),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final displayName = find.byKey(
        const ValueKey('tagManager.detail.displayName'),
      );
      final aliases = find.byKey(
        const ValueKey('tagManager.detail.aliases'),
      );
      final group = find.byKey(
        const ValueKey('tagManager.detail.group'),
      );
      final sortOrder = find.byKey(
        const ValueKey('tagManager.detail.sortOrder'),
      );

      await tester.ensureVisible(displayName);
      await tester.tap(displayName);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: aliases, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final menuItem = find.byKey(
        const ValueKey('tagManager.detail.group.favorite'),
      );
      final lastMenuItem = find.byKey(
        const ValueKey('tagManager.detail.group.archive'),
      );
      // 当前分组会同时出现在字段本体和弹层列表中，末节点才是浮层选项。
      expect(menuItem, findsNWidgets(2));
      expect(lastMenuItem, findsOneWidget);
      final fieldRect = tester.getRect(group);
      final itemRect = tester.getRect(menuItem.last);
      final lastItemRect = tester.getRect(lastMenuItem);
      // Material 下拉层保留 8px 阴影安全区，但仍须以触发字段为同一空间锚点。
      expect(itemRect.left, closeTo(fieldRect.left, 10));
      expect(itemRect.right, closeTo(fieldRect.right, 10));
      expect(itemRect.top, greaterThanOrEqualTo(0));
      expect(itemRect.bottom, lessThanOrEqualTo(720));
      expect(lastItemRect.top, greaterThanOrEqualTo(0));
      expect(lastItemRect.bottom, lessThanOrEqualTo(720));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: sortOrder,
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('tagManager.detail.delete')),
        360,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('检查合并影响'), findsOneWidget);
      expect(find.text('检查删除影响'), findsOneWidget);
      expect(find.textContaining('当前版本不会执行合并或删除'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('tag danger feedback stays safe and readable at 150 percent',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      tagManagerBlockedOperationSmokeHarness(
        textScaler: const TextScaler.linear(1.5),
      ),
    );

    await tester.tap(find.text('检查删除影响'));
    await tester.pumpAndSettle();
    final dialog = find.byKey(
      const ValueKey('tagManager.blockedOperation.dialog'),
    );
    expect(dialog, findsOneWidget);
    expect(
      Theme.of(tester.element(dialog)).dialogTheme.backgroundColor,
      librarySurface,
    );
    expect(find.text('暂不能删除此标签'), findsOneWidget);
    expect(find.textContaining('本次未删除标签或任何视频关联'), findsOneWidget);
    final close = find.byKey(
      const ValueKey('tagManager.blockedOperation.close'),
    );
    expect(_primaryFocusIsInside(close), isTrue);
    expect(find.text('确认删除'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('tagManager.blockedOperation.dialog')),
      findsNothing,
    );
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
      'shortcuts': {
        'navigateBack': 'Control+B',
        'playPause': 'Control+F',
        'fullscreen': 'Space',
      },
      'confirmBeforeDeletingVideo': false,
      'moveDeletedFileToTrash': true,
    });
    expect(settings.shortcuts[PlayerShortcutAction.navigateBack], 'Control+B');
    expect(settings.shortcuts[PlayerShortcutAction.playPause], 'Control+F');
    expect(settings.shortcuts[PlayerShortcutAction.fullscreen], 'Space');
    expect(settings.shortcuts[PlayerShortcutAction.screenshot], 'S');
    expect(settings.confirmBeforeDeletingVideo, isFalse);
    expect(settings.moveDeletedFileToTrash, isTrue);
    expect(settings.toJson()['shortcuts'], isA<Map>());
    expect(settings.toJson()['confirmBeforeDeletingVideo'], isFalse);
    expect(settings.toJson()['moveDeletedFileToTrash'], isTrue);
    expect(settings.fullscreenQueueEdgeWidth, 12);
    expect(settings.fullscreenQueueHideDelayMs, 180);
  });

  test('old settings keep safe delete defaults and reject invalid shortcuts',
      () {
    final settings = PlaybackSettings.fromJson({
      'shortcuts': {
        'navigateBack': 'Control+Alt+Shift+Meta+B',
        'playPause': 'Control+K',
      },
    });
    expect(settings.confirmBeforeDeletingVideo, isTrue);
    expect(settings.moveDeletedFileToTrash, isFalse);
    expect(settings.shortcuts[PlayerShortcutAction.navigateBack], 'Escape');
    expect(settings.shortcuts[PlayerShortcutAction.playPause], 'Control+K');
    expect(PlaybackSettings.isSupportedShortcut('Alt+K'), isTrue);
    expect(PlaybackSettings.isSupportedShortcut('Shift+Alt+K'), isFalse);
    expect(PlaybackSettings.shortcutKeyLabel('Control+K'), 'Ctrl + K');
  });

  test('disabled delete prompt executes the persisted final choice', () {
    expect(
      videoDeleteDecisionWithoutPrompt(PlaybackSettings.defaults),
      isNull,
    );
    final decision = videoDeleteDecisionWithoutPrompt(
      PlaybackSettings.defaults.copyWith(
        confirmBeforeDeletingVideo: false,
        moveDeletedFileToTrash: true,
      ),
    );
    expect(decision?.moveLocalFileToTrash, isTrue);
    expect(decision?.dontAskAgain, isTrue);
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
      confirmBeforeDeletingVideo: false,
      moveDeletedFileToTrash: true,
    );
    await changed.save(paths);
    final loaded = await PlaybackSettings.load(paths);

    expect(loaded.mirrorVideo, isTrue);
    expect(loaded.playbackMode, PlayerPlaybackMode.repeatAll);
    expect(loaded.videoAspectMode, PlayerVideoAspectMode.cover);
    expect(loaded.playbackRate, 1.5);
    expect(loaded.confirmBeforeDeletingVideo, isFalse);
    expect(loaded.moveDeletedFileToTrash, isTrue);
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
    expect(openingScale.scale.value, closeTo(0.97, 0.01));
    await tester.pump(const Duration(milliseconds: 90));
    expect(openingScale.scale.value, greaterThan(0.97));
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
    expect(
      playerPointerInFullscreenQueueActivationZone(
        localX: 995,
        surfaceWidth: 1000,
        queueVisible: false,
        edgeWidth: 12,
      ),
      isTrue,
    );
    expect(
      playerPointerInFullscreenQueueActivationZone(
        localX: 700,
        surfaceWidth: 1000,
        queueVisible: true,
        edgeWidth: 12,
      ),
      isTrue,
    );
    expect(
      playerPointerInFullscreenQueueActivationZone(
        localX: 500,
        surfaceWidth: 1000,
        queueVisible: true,
        edgeWidth: 12,
      ),
      isFalse,
    );
    expect(
      playerWindowTopBarShouldShow(
        isFullscreen: false,
        queueCollapsed: false,
        pointerInTopBarRegion: false,
        accessibleNavigation: false,
      ),
      isTrue,
    );
    expect(
      playerWindowTopBarShouldShow(
        isFullscreen: false,
        queueCollapsed: true,
        pointerInTopBarRegion: false,
        accessibleNavigation: false,
      ),
      isFalse,
    );
    expect(
      playerWindowTopBarShouldShow(
        isFullscreen: false,
        queueCollapsed: true,
        pointerInTopBarRegion: true,
        accessibleNavigation: false,
      ),
      isTrue,
    );
    expect(
      playerWindowTopBarShouldShow(
        isFullscreen: false,
        queueCollapsed: true,
        pointerInTopBarRegion: false,
        accessibleNavigation: true,
      ),
      isTrue,
    );
    expect(
      playerWindowTopBarShouldShow(
        isFullscreen: true,
        queueCollapsed: false,
        pointerInTopBarRegion: true,
        accessibleNavigation: true,
      ),
      isFalse,
    );
    expect(
      playerPointerInWindowTopBarActivationZone(
        localY: 32,
        hasWideQueueSidebar: true,
        queueCollapsed: true,
      ),
      isTrue,
    );
    expect(
      playerPointerInWindowTopBarActivationZone(
        localY: 80,
        hasWideQueueSidebar: true,
        queueCollapsed: true,
      ),
      isFalse,
    );
    expect(
      playerPointerInWindowTopBarActivationZone(
        localY: 32,
        hasWideQueueSidebar: true,
        queueCollapsed: false,
      ),
      isFalse,
    );
    expect(
      playerPointerInWindowTopBarActivationZone(
        localY: 32,
        hasWideQueueSidebar: false,
        queueCollapsed: true,
      ),
      isFalse,
    );
  });

  testWidgets('player shortcut gate detects a blocking overlay route',
      (tester) async {
    late BuildContext playerContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              playerContext = context;
              return FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(
                    content: Text('播放器弹窗'),
                  ),
                ),
                child: const Text('打开弹窗'),
              );
            },
          ),
        ),
      ),
    );
    expect(playerRouteHasBlockingOverlay(playerContext), isFalse);

    await tester.tap(find.text('打开弹窗'));
    await tester.pumpAndSettle();
    expect(playerRouteHasBlockingOverlay(playerContext), isTrue);
  });

  testWidgets(
      'player reveal file button identifies current video and invokes callback',
      (tester) async {
    var revealRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: PlayerRevealFileButton(
            onPressed: () => revealRequests++,
          ),
        ),
      ),
    );

    final button = find.byKey(const ValueKey('player.revealFile'));
    expect(button, findsOneWidget);
    expect(find.byIcon(Icons.eject_rounded), findsOneWidget);
    expect(find.byTooltip('在文件管理器中显示当前视频'), findsOneWidget);

    await tester.tap(button);
    expect(revealRequests, 1);
  });

  test('player reveal path follows playing item instead of queue selection',
      () {
    final playing = _testVideo(
      path: r'X:\test-media\playing.mp4',
      title: 'playing',
    );
    final selected = _testVideo(
      path: r'X:\test-media\selected.mp4',
      title: 'selected',
    );
    final playback = PlayerPlaybackController(
      sourcePlaylist: <VideoItem>[playing, selected],
      activeParentTag: null,
      initialPath: playing.path,
    );

    expect(playback.select(1), isTrue);
    expect(playback.selectedIndex, 1);
    expect(playback.playingIndex, 0);
    expect(playerCurrentRevealPath(playback), playing.path);
  });

  test('player volume steps clamp and mute restores the last audible value',
      () {
    expect(playerVolumeAfterStep(98, 5), 100);
    expect(playerVolumeAfterStep(2, -5), 0);
    expect(playerVolumeDeltaForScroll(-120), 5);
    expect(playerVolumeDeltaForScroll(120), -5);
    expect(playerVolumeDeltaForScroll(0), 0);
    expect(
      playerVolumeAfterMuteToggle(
        currentVolume: 65,
        lastAudibleVolume: 65,
      ),
      0,
    );
    expect(
      playerVolumeAfterMuteToggle(
        currentVolume: 0,
        lastAudibleVolume: 65,
      ),
      65,
    );
  });

  testWidgets('player top bar shows current file name without search field',
      (tester) async {
    var backCount = 0;
    var queueCount = 0;
    const currentPath = r'X:\test-media\原神\雷神\当前播放.mp4';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: PlayerTopBar(
            currentFileName: playerTopBarFileName(currentPath),
            contextLabel: '3 / 120 · 原神 / 雷神',
            onBack: () => backCount++,
            onOpenQueue: () => queueCount++,
          ),
        ),
      ),
    );

    expect(find.text('当前播放.mp4'), findsOneWidget);
    expect(find.text('3 / 120 · 原神 / 雷神'), findsOneWidget);
    expect(
      tester.getSize(find.byType(PlayerTopBar)).height,
      64,
    );
    expect(find.text('local_tag_player'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('搜索当前队列'), findsNothing);
    expect(
      tester.getCenter(find.text('当前播放.mp4')).dx,
      closeTo(tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
          0.5),
    );

    await tester.tap(find.byKey(const ValueKey('player.back')));
    await tester.tap(find.byTooltip('播放队列'));
    expect(backCount, 1);
    expect(queueCount, 1);
  });

  testWidgets('player volume button toggles icon tooltip and callback',
      (tester) async {
    var toggleRequests = 0;

    Future<void> pumpVolume(double volume) => tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: PlayerVolumeButton(
                volume: volume,
                onPressed: () => toggleRequests++,
              ),
            ),
          ),
        );

    await pumpVolume(65);
    final button = find.byKey(const ValueKey('player.volume.toggleMute'));
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(find.byTooltip('静音'), findsOneWidget);
    await tester.tap(button);
    expect(toggleRequests, 1);

    await pumpVolume(0);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    expect(find.byTooltip('恢复音量'), findsOneWidget);
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

  testWidgets(
      'player queue action panel matches card height without heart glow',
      (tester) async {
    final directory = Directory(
      p.join(
        Directory.systemTemp.path,
        'local_tag_player_queue_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    final item = VideoItem(
      videoId: 'queue-layout-item',
      path: p.join(directory.path, 'missing.mp4'),
      title: 'queue layout item',
      folder: directory.path,
      tags: const <String>{},
      addedAt: DateTime.utc(2026, 7, 17),
      isFavorite: true,
      isMissing: true,
    );
    final scrollController = ScrollController();
    final detailsService = MediaDetailsService(
      probeBackend: _NoopMediaProbeBackend(),
    );
    addTearDown(() {
      scrollController.dispose();
      detailsService.dispose();
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    await tester.binding.setSurfaceSize(const Size(460, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: PlayerQueueSidebar(
              playlist: <VideoItem>[item],
              sourcePlaylist: <VideoItem>[item],
              playingIndex: 0,
              selectedIndex: 0,
              scrollController: scrollController,
              thumbnailService: ThumbnailService.forDirectory(
                directory,
                _PreviewFFmpegBackend(),
              ),
              detailsService: detailsService,
              activeTags: const <String>[],
              selectedChildTag: null,
              onChildTagSelected: (_) {},
              onSelect: (_) {},
              onPlay: (_) {},
              onReturnToPlaying: () {},
              onLocateSelected: () {},
              onDeleteSelected: null,
              onToggleFavorite: (_) {},
              onDeleteItem: (_) {},
              onSearchQueue: (_) => PlayerQueueSearchOutcome.noMatch,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final card =
        find.byKey(const ValueKey('player.queue.card.queue-layout-item'));
    final hiddenActionPanel = find.byKey(
      const ValueKey('player.queue.actionPanel.queue-layout-item'),
    );
    expect(hiddenActionPanel, findsNothing);
    await tester.drag(card, const Offset(-96, 0));
    await tester.pumpAndSettle();
    final actionPanel = find.byKey(
      const ValueKey('player.queue.actionPanel.queue-layout-item'),
    );
    final favoriteSurface = tester.widget<Material>(
      find.byKey(
        const ValueKey(
          'player.queue.favoriteActionSurface.queue-layout-item',
        ),
      ),
    );
    final actionDecoration =
        tester.widget<DecoratedBox>(actionPanel).decoration as BoxDecoration;
    expect(card, findsOneWidget);
    expect(actionPanel, findsOneWidget);
    expect(tester.getSize(actionPanel).height, tester.getSize(card).height);
    expect(actionDecoration.boxShadow, isNull);
    expect(favoriteSurface.color, Colors.transparent);
  });

  testWidgets('playing queue item closes a retained swipe action panel',
      (tester) async {
    final directory = Directory(
      p.join(
        Directory.systemTemp.path,
        'local_tag_player_queue_playing_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    final items = <VideoItem>[
      VideoItem(
        videoId: 'queue-transition-first',
        path: p.join(directory.path, 'first.mp4'),
        title: 'first item',
        folder: directory.path,
        tags: const <String>{},
        addedAt: DateTime.utc(2026, 7, 18),
        isMissing: true,
      ),
      VideoItem(
        videoId: 'queue-transition-second',
        path: p.join(directory.path, 'second.mp4'),
        title: 'second item',
        folder: directory.path,
        tags: const <String>{},
        addedAt: DateTime.utc(2026, 7, 18),
        isMissing: true,
      ),
    ];
    final scrollController = ScrollController();
    final detailsService = MediaDetailsService(
      probeBackend: _NoopMediaProbeBackend(),
    );
    final thumbnailService = ThumbnailService.forDirectory(
      directory,
      _PreviewFFmpegBackend(),
    );
    addTearDown(() {
      scrollController.dispose();
      detailsService.dispose();
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    await tester.binding.setSurfaceSize(const Size(460, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var playingIndex = 1;
    late StateSetter updateHarness;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateHarness = setState;
              return SizedBox(
                width: 360,
                child: PlayerQueueSidebar(
                  playlist: items,
                  sourcePlaylist: items,
                  playingIndex: playingIndex,
                  selectedIndex: 0,
                  scrollController: scrollController,
                  thumbnailService: thumbnailService,
                  detailsService: detailsService,
                  activeTags: const <String>[],
                  selectedChildTag: null,
                  onChildTagSelected: (_) {},
                  onSelect: (_) {},
                  onPlay: (_) {},
                  onReturnToPlaying: () {},
                  onLocateSelected: () {},
                  onDeleteSelected: null,
                  onToggleFavorite: (_) {},
                  onDeleteItem: (_) {},
                  onSearchQueue: (_) => PlayerQueueSearchOutcome.noMatch,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey(
          'player.queue.favoriteIndicator.queue-transition-first',
        ),
      ),
      findsNothing,
    );

    final card = find.byKey(
      const ValueKey('player.queue.card.queue-transition-first'),
    );
    final closedLeft = tester.getTopLeft(card).dx;
    await tester.drag(card, const Offset(-96, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(card).dx, lessThan(closedLeft - 70));

    updateHarness(() => playingIndex = 0);
    await tester.pump();
    expect(tester.getTopLeft(card).dx, closeTo(closedLeft, 0.01));
    expect(tester.takeException(), isNull);
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

  testWidgets('cancelling single relink picker keeps the row enabled',
      (tester) async {
    final repository = _MissingRelinkTestRepository();
    final item = _testVideo(
      path: r'D:\missing\cancel.mp4',
      title: 'cancel relink',
    )..isMissing = true;
    repository.videos[TagRules.pathKey(item.path)] = item;
    final store = LibraryApplicationFacade(
      libraryRepository: repository,
      tagRepository: repository,
      cacheRepository: repository,
      playbackRepository: repository,
    );
    final fileSystem = _CancellingFileSystemAdapter();

    await tester.pumpWidget(
      MaterialApp(
        home: MissingRelinkPage(
          store: store,
          fileSystem: fileSystem,
        ),
      ),
    );
    final relinkButton = find.byKey(ValueKey('missingRelink.${item.videoId}'));
    expect(relinkButton, findsOneWidget);

    await tester.tap(relinkButton);
    await tester.pumpAndSettle();

    expect(fileSystem.pickFileCalls, 1);
    expect(fileSystem.lastInitialDirectory, r'D:\missing');
    expect(
      Theme.of(tester.element(relinkButton)).cardTheme.color,
      librarySurface,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<FilledButton>(relinkButton).onPressed, isNotNull);
  });

  testWidgets('directory manager preserves data policy and scales to 150%',
      (tester) async {
    tester.view.physicalSize = const Size(1248, 714);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _MissingRelinkTestRepository()
      ..roots.addAll(<String>[r'X:\test-media', r'E:\archive\media']);
    final store = LibraryApplicationFacade(
      libraryRepository: repository,
      tagRepository: repository,
      cacheRepository: repository,
      playbackRepository: repository,
    );
    String? removedRoot;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: DirectoryManagerPage(
            store: store,
            scanning: false,
            onAddDirectory: () async {},
            onRescan: () async {},
            onRemoveRoot: (root) async {
              removedRoot = root;
              repository.roots.remove(root);
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('2 个受管理目录'), findsOneWidget);
    expect(find.textContaining('不会删除磁盘文件'), findsOneWidget);
    expect(find.byKey(const ValueKey('directoryManager.add')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('directoryManager.rescan')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey(r'directoryManager.remove.X:\test-media')),
    );
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(AlertDialog)))
          .dialogTheme
          .backgroundColor,
      librarySurface,
    );
    expect(find.text('解除目录管理'), findsOneWidget);
    expect(find.textContaining('稳定视频身份'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('directoryManager.confirmRemove')),
    );
    await tester.pumpAndSettle();
    expect(removedRoot, r'X:\test-media');
    expect(find.text('1 个受管理目录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing relink workspace and bulk preview scale to 150%',
      (tester) async {
    tester.view.physicalSize = const Size(1248, 714);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _MissingRelinkTestRepository();
    for (final item in <VideoItem>[
      _testVideo(
        path: r'D:\missing\alpha-long-name.mp4',
        title: '一个很长但仍需完整可达的缺失视频标题 Alpha',
      )..isMissing = true,
      _testVideo(
        path: r'E:\missing\beta.mp4',
        title: 'Beta',
      )..isMissing = true,
    ]) {
      repository.videos[TagRules.pathKey(item.path)] = item;
    }
    final store = LibraryApplicationFacade(
      libraryRepository: repository,
      tagRepository: repository,
      cacheRepository: repository,
      playbackRepository: repository,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: MissingRelinkPage(
            store: store,
            fileSystem: _CancellingFileSystemAdapter(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('2 个视频路径失效'), findsOneWidget);
    expect(find.text('标签与播放记录已保留'), findsOneWidget);
    expect(find.byKey(const ValueKey('missingRelink.list')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('missingRelink.bulkPreview')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(AlertDialog)))
          .dialogTheme
          .backgroundColor,
      librarySurface,
    );
    expect(find.text('批量路径替换'), findsWidgets);
    expect(
        find.byKey(const ValueKey('missingRelink.oldPrefix')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('missingRelink.newPrefix')), findsOneWidget);
    expect(find.textContaining('不会移动或删除文件'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  test('tag editor candidates include every normalized name in scope', () {
    const tags = <TagItem>[
      TagItem(
        id: 'manual:top',
        name: '顶级标签',
        source: TagSource.manual,
        groupId: 'manual',
      ),
      TagItem(
        id: 'manual:used',
        name: '已使用标签',
        source: TagSource.manual,
        groupId: 'manual',
        parentId: '原神',
        usageCount: 8,
      ),
      TagItem(
        id: 'manual:unused',
        name: '未使用标签',
        source: TagSource.manual,
        groupId: 'manual',
        parentId: '原神',
      ),
      TagItem(
        id: 'manual:hidden',
        name: '隐藏标签',
        source: TagSource.manual,
        groupId: 'manual',
        parentId: '原神',
        isHidden: true,
      ),
      TagItem(
        id: 'folder:child',
        name: '文件夹标签',
        source: TagSource.folder,
        groupId: 'folder.child',
        parentId: '原神',
      ),
      TagItem(
        id: 'manual:other-parent',
        name: '其它父级标签',
        source: TagSource.manual,
        groupId: 'manual',
        parentId: '崩坏三',
      ),
    ];

    expect(
      tagEditorCandidates(tags, parentTag: '原神'),
      <String>{'已使用标签', '未使用标签', '文件夹标签'},
    );
    expect(
      tagEditorCandidates(tags),
      <String>{'顶级标签'},
    );
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

    expect(
      Theme.of(tester.element(find.byKey(const ValueKey('tagEditor.dialog'))))
          .dialogTheme
          .backgroundColor,
      librarySurface,
    );
    await tester.tap(find.byKey(const ValueKey('tagEditor.clearSearch')));
    await tester.pump();
    expect(find.text('RecentTag'), findsOneWidget);
    expect(find.byKey(const ValueKey('tagEditor.clearSearch')), findsNothing);

    manualChip.onDeleted!();
    await tester.pump();
    expect(find.text('ManualTag'), findsNothing);
    expect(
      find.byKey(const ValueKey('tagEditor.unsavedChanges')),
      findsOneWidget,
    );
    expect(find.textContaining('取消将放弃本次调整'), findsOneWidget);
  });

  testWidgets('manual tag editor remains usable at 150 percent text scale',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(900, 720),
            textScaler: TextScaler.linear(1.5),
          ),
          child: Scaffold(
            body: TagEditorDialog(
              title: '一段很长的媒体标题用于验证标签编辑器',
              helperText: '只修改手动标签；文件夹标签由目录结构维护。',
              initialTags: {'FolderTag', 'ManualTag'},
              existingTags: {'SuggestedTag', 'AnotherTag'},
              lockedTags: {'FolderTag'},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('管理当前视频关联的标签'), findsOneWidget);
    expect(find.byKey(const ValueKey('tagEditor.save')), findsOneWidget);
    expect(find.byKey(const ValueKey('tagEditor.cancel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual tag editor shows every available candidate',
      (tester) async {
    final candidates = <String>{
      for (var index = 1; index <= 30; index++) '候选标签 $index',
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TagEditorDialog(
            title: '完整候选标签',
            initialTags: const <String>{},
            existingTags: candidates,
          ),
        ),
      ),
    );

    expect(find.text('全部可用标签'), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(30));
    expect(find.text('候选标签 1'), findsOneWidget);
    expect(find.text('候选标签 30'), findsOneWidget);
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

  testWidgets('clear all watching progress confirms data scope explicitly',
      (tester) async {
    bool? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                confirmed = await showClearAllRecentPlaybackConfirmation(
                  context,
                  count: 11,
                );
              },
              child: const Text('测试清空'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('测试清空'));
    await tester.pumpAndSettle();
    expect(find.text('清空全部观看进度？'), findsOneWidget);
    expect(find.textContaining('不会删除视频文件、标签或收藏'), findsOneWidget);
    expect(find.textContaining('10 秒内撤销'), findsOneWidget);
    expect(find.text('只清除进度'), findsOneWidget);

    await tester.tap(find.text('只清除进度'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  test(
      'continue watching undo restores exact state but never overwrites replay',
      () {
    final playedAt = DateTime.utc(2026, 7, 17, 10);
    final updatedAt = DateTime.utc(2026, 7, 17, 10, 1);
    final item = _testVideo(path: 'D:/video/undo.mp4', title: 'undo')
      ..lastPlayedAt = playedAt
      ..playbackPosition = const Duration(seconds: 137)
      ..playbackCompleted = false
      ..playbackPositionUpdatedAt = updatedAt;
    final snapshot = ContinueWatchingClearSnapshot.capture(item);

    item
      ..lastPlayedAt = null
      ..playbackPosition = Duration.zero
      ..playbackCompleted = false
      ..playbackPositionUpdatedAt = null;
    expect(snapshot.canRestoreWithoutOverwritingNewPlayback, isTrue);
    snapshot.restore();
    expect(item.lastPlayedAt, playedAt);
    expect(item.playbackPosition, const Duration(seconds: 137));
    expect(item.playbackPositionUpdatedAt, updatedAt);

    final replayGuard = ContinueWatchingClearSnapshot.capture(item);
    item
      ..lastPlayedAt = null
      ..playbackPosition = Duration.zero
      ..playbackPositionUpdatedAt = null;
    item
      ..lastPlayedAt = DateTime.utc(2026, 7, 17, 10, 2)
      ..playbackPosition = const Duration(seconds: 2);
    expect(replayGuard.canRestoreWithoutOverwritingNewPlayback, isFalse);
  });

  test('backup integrity summary separates stale data from duplicate identity',
      () {
    final checkedAt = DateTime.utc(2026, 7, 17);
    expect(
      dataBackupIntegritySafetySummary(
        DataBackupIntegrityReport(
          checkedAt: checkedAt,
          sqliteHealthy: true,
          backupRecords: 11163,
          currentVideos: 11163,
          invalidPayloads: 0,
          missingFingerprints: 0,
          missingCurrentSnapshots: 0,
          staleCurrentSnapshots: 6719,
          ambiguousFingerprints: 88,
          recoverableSnapshots: 0,
        ),
      ),
      contains('立即备份'),
    );
    expect(
      dataBackupIntegritySafetySummary(
        DataBackupIntegrityReport(
          checkedAt: checkedAt,
          sqliteHealthy: true,
          backupRecords: 11163,
          currentVideos: 11163,
          invalidPayloads: 0,
          missingFingerprints: 0,
          missingCurrentSnapshots: 0,
          staleCurrentSnapshots: 0,
          ambiguousFingerprints: 88,
          recoverableSnapshots: 0,
        ),
      ),
      allOf(contains('当前用户数据已覆盖'), contains('自动恢复会安全跳过')),
    );
  });

  testWidgets('result view slider toggles as one target and animates thumb',
      (tester) async {
    var dense = false;
    final committed = <bool>[];
    late StateSetter rebuildHost;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuildHost = setState;
              return ResultViewToggle(
                dense: dense,
                onChanged: (value) => setState(() {
                  committed.add(value);
                  dense = value;
                }),
              );
            },
          ),
        ),
      ),
    );

    final thumb = find.byKey(LibrarySmokeKeys.resultViewToggleThumb);
    final initialLeft = tester.getTopLeft(thumb).dx;

    await tester.tap(find.byKey(LibrarySmokeKeys.resultViewToggle));
    await tester.pump();
    await tester.pump(appMotionDuration ~/ 2);
    final movingLeft = tester.getTopLeft(thumb).dx;
    expect(movingLeft, greaterThan(initialLeft));
    // 重型结果视图切换延后到滑块稳定后，避免阻塞动画首帧。
    expect(dense, isFalse);
    expect(committed, isEmpty);

    // 无关父级重建不能把尚未提交的视觉目标拉回旧状态。
    rebuildHost(() {});
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.getTopLeft(thumb).dx, greaterThan(movingLeft));

    await tester.pumpAndSettle();
    final listLeft = tester.getTopLeft(thumb).dx;
    expect(listLeft, greaterThan(movingLeft));
    expect(dense, isTrue);
    expect(committed, <bool>[true]);

    // 动画中再次点击会从当前位置反向，不提交已经过期的中间目标。
    await tester.tap(find.byKey(LibrarySmokeKeys.resultViewToggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final reversingLeft = tester.getTopLeft(thumb).dx;
    expect(reversingLeft, lessThan(listLeft));

    await tester.tap(find.byKey(LibrarySmokeKeys.resultViewToggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getTopLeft(thumb).dx, greaterThan(reversingLeft));
    await tester.pumpAndSettle();
    expect(dense, isTrue);
    expect(committed, <bool>[true]);

    // 整个控件只有一个点击语义，稳定点击一次会切回网格。
    await tester.tap(find.byKey(LibrarySmokeKeys.resultViewToggle));
    await tester.pumpAndSettle();
    expect(dense, isFalse);
    expect(committed, <bool>[true, false]);
    expect(tester.getTopLeft(thumb).dx, closeTo(initialLeft, 0.01));
  });

  testWidgets('library header exposes a stable tag panel toggle',
      (tester) async {
    var expanded = false;
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        onSearchChanged: (_) {},
        onToggleTagPanel: () => expanded = true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(LibrarySmokeKeys.collapsedTagRail), findsOneWidget);
    expect(find.byTooltip('展开标签筛选'), findsOneWidget);
    expect(find.text('标签'), findsOneWidget);
    expect(find.byType(RotatedBox), findsNothing);

    await tester.tap(find.byKey(LibrarySmokeKeys.collapsedTagRail));
    await tester.pump(const Duration(milliseconds: 100));
    expect(expanded, isTrue);
  });

  testWidgets('expanded tag panel collapses from its title without an arrow',
      (tester) async {
    var collapsed = false;
    await tester.pumpWidget(
      TagDiscoverySmokeHarness(
        childCount: 12,
        onCollapse: () => collapsed = true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final titleAction = find.byKey(LibrarySmokeKeys.tagPanelCollapseHeader);
    expect(titleAction, findsOneWidget);
    expect(find.byTooltip('收起标签筛选'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing);

    await tester.tap(titleAction);
    await tester.pump(const Duration(milliseconds: 100));
    expect(collapsed, isTrue);
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

  testWidgets('narrow top bar keeps active filter and clear entry visible',
      (tester) async {
    tester.view.physicalSize = const Size(780, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var clearCount = 0;

    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        onSearchChanged: (_) {},
        selectedTags: const <String>['171 条筛选'],
        layoutSize: LayoutSize.medium,
        onClearAll: () => clearCount++,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('171 条筛选'), findsOneWidget);
    expect(find.byTooltip('清空全部筛选'), findsOneWidget);
    await tester.tap(find.byTooltip('清空全部筛选'));
    expect(clearCount, 1);
  });

  testWidgets('scan progress exposes a dedicated cancel action',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var cancelCount = 0;

    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        onSearchChanged: (_) {},
        progressLabel: '校验文件 20/100 · 20% · 剩余10秒',
        progressValue: 0.2,
        onToggleProgressPaused: () {},
        onCancelProgress: () => cancelCount++,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final cancel = find.byKey(const ValueKey('qa.library_scan.cancel'));
    expect(cancel, findsOneWidget);
    expect(find.byTooltip('取消扫描'), findsOneWidget);
    await tester.tap(cancel);
    expect(cancelCount, 1);
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
    expect(find.byTooltip('切换为正序'), findsOneWidget);

    await tester.tap(find.byKey(LibrarySmokeKeys.topSortFieldButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(LibrarySmokeKeys.topSortMenuItem(
      SortMode.recent,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('切换为正序'));
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

  test('local library summary distinguishes folders from videos', () {
    final video = _testVideo(
      path: r'C:\smoke\media\clip.mp4',
      title: 'clip',
    );
    expect(
      localLibraryEntrySummary(<LocalLibraryEntry>[
        const LocalLibraryEntry.folder(r'C:\smoke\media\Alpha'),
        const LocalLibraryEntry.folder(r'C:\smoke\media\Beta'),
        LocalLibraryEntry.video(video),
      ]),
      '2 个文件夹 · 1 个视频',
    );
  });

  testWidgets('mixed local result summary keeps enough desktop width',
      (tester) async {
    tester.view.physicalSize = const Size(1268, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        onSearchChanged: (_) {},
        resultCountLabel: '40 个文件夹 · 0 个视频',
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('40 个文件夹 · 0 个视频'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(LibrarySmokeKeys.toolbarResultStatus)).width,
      200,
    );
  });

  testWidgets('empty manual tag stays in dialog with a Chinese field error',
      (tester) async {
    await tester.pumpWidget(createTagDialogSmokeHarness());
    await tester.tap(find.text('打开新建标签'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('创建'));
    await tester.pump();
    expect(find.text('新建标签'), findsOneWidget);
    expect(find.text('请输入标签名'), findsOneWidget);
    expect(find.textContaining('Invalid argument'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '  新标签  ');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(find.text('新建标签'), findsNothing);
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
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        onSearchChanged: (_) {},
        videoCount: 11163,
        progressLabel: '媒体解析 3200/6308 · 50% · 120个/秒 · 剩余26秒',
        progressValue: 3200 / 6308,
        onToggleProgressPaused: () => pauseCount++,
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
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip && widget.message == '全部视频 | 11163 / 11163',
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('qa.media_import.pause')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('qa.media_import.pause')));
    await tester.pump();
    expect(pauseCount, 1);
  });

  testWidgets('library toolbar switches between filter and batch modes',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selectionMode = false;
    var selectedCount = 0;
    var selectAllCount = 0;
    var deleteCount = 0;
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => referenceTopBarSearchSmokeHarness(
          controller: controller,
          onSearchChanged: (_) {},
          videoCount: 171,
          selectedTags: const <String>[
            '原神',
            '雷神',
            '稻妻',
            '八重神子',
          ],
          onClearAll: () {},
          selectionMode: selectionMode,
          selectedCount: selectedCount,
          allSelected: selectedCount == 171,
          onEnterSelectionMode: () => setState(() {
            selectionMode = true;
            selectedCount = 0;
          }),
          onToggleSelectAll: () => setState(() {
            selectAllCount += 1;
            selectedCount = selectedCount == 171 ? 0 : 171;
          }),
          onDeleteSelected: selectedCount == 0 ? null : () => deleteCount += 1,
          onCancelSelectionMode: () => setState(() {
            selectionMode = false;
            selectedCount = 0;
          }),
        ),
      ),
    );

    expect(find.text('当前筛选（AND）'), findsNothing);
    expect(find.text('原神'), findsOneWidget);
    expect(find.text('雷神'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('171 个视频'), findsOneWidget);
    expect(find.textContaining('原神 / 雷神'), findsNothing);
    final searchWidthBeforeSelection =
        tester.getSize(find.byKey(LibrarySmokeKeys.searchSurface)).width;
    expect(
      tester.getSize(find.byKey(LibrarySmokeKeys.searchInputLane)).width,
      greaterThan(600),
    );
    expect(
      tester.getSize(find.byKey(LibrarySmokeKeys.libraryEnterSelection)).height,
      48,
    );
    final weakMultiButton = tester.widget<TextButton>(
      find.descendant(
        of: find.byKey(LibrarySmokeKeys.libraryEnterSelection),
        matching: find.byType(TextButton),
      ),
    );
    expect(
      weakMultiButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      Colors.transparent,
    );
    expect(
      weakMultiButton.style?.side?.resolve(<WidgetState>{}),
      BorderSide.none,
    );
    expect(
      tester.getSize(find.byKey(LibrarySmokeKeys.resultViewToggle)).height,
      48,
    );

    await tester.tap(find.byKey(LibrarySmokeKeys.libraryEnterSelection));
    await tester.pump();
    expect(find.text('原神'), findsNothing);
    expect(find.text('+2'), findsNothing);
    expect(find.byKey(LibrarySmokeKeys.searchField), findsOneWidget);
    expect(find.byKey(LibrarySmokeKeys.filterStatusArea), findsNothing);
    expect(find.byKey(LibrarySmokeKeys.toolbarActions), findsNothing);
    expect(find.byKey(LibrarySmokeKeys.selectionStatusArea), findsOneWidget);
    expect(
      tester.getSize(find.byKey(LibrarySmokeKeys.searchSurface)).width,
      closeTo(searchWidthBeforeSelection, 0.01),
    );
    expect(find.text('已选择 0 项'), findsOneWidget);
    final disabledDelete = tester.widget<TextButton>(
      find.byKey(LibrarySmokeKeys.libraryDeleteSelected),
    );
    expect(disabledDelete.onPressed, isNull);

    await tester.tap(find.byKey(LibrarySmokeKeys.librarySelectAll));
    await tester.pump();
    expect(selectAllCount, 1);
    expect(find.text('已选择 171 项'), findsOneWidget);
    await tester.tap(find.byKey(LibrarySmokeKeys.libraryDeleteSelected));
    await tester.pump();
    expect(deleteCount, 1);

    await tester.tap(find.byKey(LibrarySmokeKeys.libraryCancelSelection));
    await tester.pump();
    expect(find.text('原神'), findsOneWidget);
    expect(find.text('171 个视频'), findsOneWidget);
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
    expect(playerProgressThumbIsCat(sliderTheme().data), isTrue);
    expect(
      sliderTheme().data.thumbShape!.getPreferredSize(true, false),
      const Size.square(28),
    );
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
