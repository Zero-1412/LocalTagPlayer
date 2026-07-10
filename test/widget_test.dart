import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_tag_player/src/app.dart';

void main() {
  testWidgets('app mounts', (WidgetTester tester) async {
    await tester.pumpWidget(const LocalTagPlayerApp());
    await tester.pump();

    expect(find.byType(LocalTagPlayerApp), findsOneWidget);
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
      AppPaths.debugUseDataDirectoryForTesting(null);
      await directory.delete(recursive: true);
    });
    AppPaths.debugUseDataDirectoryForTesting(directory);

    const preferences = LibrarySortPreferences(
      mode: SortMode.folder,
      direction: SortDirection.ascending,
    );
    await preferences.save();
    final loaded = await LibrarySortPreferences.load();

    expect(loaded.mode, SortMode.folder);
    expect(loaded.direction, SortDirection.ascending);
    expect(await AppPaths.settingsFile(),
        isNot(await AppPaths.librarySortPreferencesFile()));
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

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text(PlaybackSettings.labelFor('d3d11va')).last);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('切换播放解码'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(savedSettings, isNull);
    expect(
      (tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      ).key! as ValueKey<String>)
          .value,
      startsWith('auto-safe:'),
    );
    expect(find.text(PlaybackSettings.labelFor('d3d11va')), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text(PlaybackSettings.labelFor('d3d11va')).last);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('确认切换'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(savedSettings?.hwdec, 'd3d11va');
    expect(
      (tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      ).key! as ValueKey<String>)
          .value,
      startsWith('d3d11va:'),
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
      (tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      ).key! as ValueKey<String>)
          .value,
      startsWith('d3d11va:'),
    );
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

    playback.toggleChildTag('AlbumB', preferredPath: alpha.path);
    expect(playback.queue, [beta]);
    expect(playback.currentItem, beta);

    playback.toggleChildTag('AlbumB', preferredPath: beta.path);
    expect(playback.queue, [alpha, beta]);
    expect(playback.currentItem, beta);

    playback.setPlaylistForChildTag('Missing', preferredPath: beta.path);
    expect(playback.queue, [alpha, beta]);
    expect(playback.currentItem, beta);
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
    tester.view.physicalSize = const Size(1500, 420);
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
}
