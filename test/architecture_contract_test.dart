import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/composition/local_tag_player_bootstrap.dart';
import 'package:local_tag_player/src/core/app_paths.dart';
import 'package:local_tag_player/src/features/update/data/github_release_update_service.dart';
import 'package:local_tag_player/src/models/platform_models.dart';
import 'package:local_tag_player/src/models/video_item.dart';
import 'package:local_tag_player/src/platform/database_provider.dart';
import 'package:local_tag_player/src/platform/desktop_file_system_adapter.dart';
import 'package:local_tag_player/src/repositories/repository_interfaces.dart';
import 'package:local_tag_player/src/services/library/library_application_facade.dart';
import 'package:local_tag_player/src/services/library/library_page_application_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ignore_for_file: slash_for_doc_comments

class _FakeLibraryRepository implements LibraryRepository {
  @override
  final List<String> roots = <String>['root'];
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
  TagQueryContext get tagQueryContext => const TagQueryContext();
  @override
  Iterable<TagItem> get allTagItems => tagsById.values;
  @override
  Set<String> get allTags => const <String>{};

  @override
  Future<void> addFavoriteTag(String tag) async => favoriteTags.add(tag);
  @override
  Future<void> removeFavoriteTag(String tag) async => favoriteTags.remove(tag);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTagRepository implements TagRepository {
  String? attachedVideoId;

  @override
  Future<void> attachTag({
    required String videoId,
    required String tagId,
    required TagSource source,
    bool locked = false,
  }) async {
    attachedVideoId = videoId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCacheRepository implements CacheRepository {
  @override
  Future<CacheStatus> thumbnailStatus(String videoId) async =>
      const CacheStatus(kind: CacheStatusKind.ready);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlaybackRepository implements PlaybackRepository {
  String? savedVideoId;

  @override
  Future<void> savePlaybackPosition({
    required String videoId,
    required Duration position,
    required Duration duration,
    required bool completed,
    required DateTime updatedAt,
  }) async {
    savedVideoId = videoId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Dart source uses independent libraries instead of part files', () {
    final violations = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => RegExp(
              r'^\s*part(?:\s+of)?\s+',
              multiLine: true,
            ).hasMatch(file.readAsStringSync()))
        .map((file) => file.path)
        .toList();

    expect(violations, isEmpty);
  });

  test('facade exposes read-only views and routes explicit repository commands',
      () async {
    final library = _FakeLibraryRepository();
    final tags = _FakeTagRepository();
    final cache = _FakeCacheRepository();
    final playback = _FakePlaybackRepository();
    final facade = LibraryApplicationFacade(
      queryRepository: library,
      commandRepository: library,
      tagRepository: tags,
      cacheRepository: cache,
      playbackRepository: playback,
    );

    expect(() => facade.roots.add('other'), throwsUnsupportedError);
    expect(() => facade.favoriteTags.add('tag'), throwsUnsupportedError);
    await facade.addFavoriteTag('tag');
    expect(facade.favoriteTags, contains('tag'));

    await facade.attachTag(
      videoId: 'video-1',
      tagId: 'manual:tag',
      source: TagSource.manual,
    );
    await facade.savePlaybackPosition(
      videoId: 'video-1',
      position: const Duration(seconds: 1),
      duration: const Duration(seconds: 10),
      completed: false,
      updatedAt: DateTime(2026),
    );
    expect(tags.attachedVideoId, 'video-1');
    expect(playback.savedVideoId, 'video-1');
    expect(
        (await facade.thumbnailStatus('video-1')).kind, CacheStatusKind.ready);
  });

  test('library facade depends on split query and command capabilities', () {
    final contracts = File('lib/src/repositories/repository_interfaces.dart')
        .readAsStringSync();
    final facade = File(
      'lib/src/services/library/library_application_facade.dart',
    ).readAsStringSync();
    final bootstrap = File(
      'lib/src/composition/local_tag_player_bootstrap.dart',
    ).readAsStringSync();

    expect(
      contracts,
      contains('abstract interface class LibraryQueryRepository'),
    );
    expect(
      contracts,
      contains('abstract interface class LibraryCommandRepository'),
    );
    final normalizedContracts = contracts.replaceAll('\r\n', '\n');
    expect(
      normalizedContracts,
      contains('LibraryQueryRepository,\n'
          '        LibraryCommandRepository,\n'
          '        LibraryRelinkRepository'),
    );
    expect(facade, contains('required LibraryQueryRepository queryRepository'));
    expect(
      facade,
      contains('required LibraryCommandRepository commandRepository'),
    );
    expect(facade, contains('final LibraryQueryRepository _queries'));
    expect(facade, contains('final LibraryCommandRepository _commands'));
    expect(facade, isNot(contains('final LibraryRepository _repository')));
    expect(bootstrap, contains('queryRepository: repository'));
    expect(bootstrap, contains('commandRepository: repository'));
  });

  test('sqflite provider owns factory and paths while Dart owns schema writes',
      () async {
    // Windows 使用仓库内固定 SQLite 动态库；macOS/Linux runner 使用系统 SQLite。
    if (Platform.isWindows) {
      DynamicLibrary.open(
        File('windows/tools/sqlite/sqlite3.dll').absolute.path,
      );
    }
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('ltp_db_provider_');
    addTearDown(() => directory.delete(recursive: true));
    final paths = AppPaths(dataDirectoryOverride: directory);
    final provider = SqfliteDatabaseProvider(
      paths: paths,
      factory: databaseFactoryFfi,
    );
    var schemaCalls = 0;
    final database = await provider.openLibraryDatabase(
      version: 1,
      createSchema: (database) async {
        schemaCalls++;
        await database.execute('CREATE TABLE contract_test (id INTEGER)');
      },
      maintainSchema: (database) async => schemaCalls++,
    );
    addTearDown(database.close);

    expect(schemaCalls, greaterThanOrEqualTo(2));
    expect(await (await paths.libraryDatabaseFile()).exists(), isTrue);
  });

  test('composition root selects concrete adapters without page globals', () {
    final dependencies = createLocalTagPlayerDependencies();
    expect(dependencies.fileSystem, isA<DesktopFileSystemAdapter>());
    if (Platform.isMacOS) {
      expect(dependencies.fileSystem, isA<MacOsFileSystemAdapter>());
    } else if (Platform.isLinux) {
      expect(dependencies.fileSystem, isA<LinuxFileSystemAdapter>());
    }
    expect(
      dependencies.libraryPageApplicationService,
      isA<LocalLibraryPageApplicationService>(),
    );
    expect(dependencies.paths, isA<AppPaths>());
    expect(dependencies.updateService, isA<GitHubReleaseUpdateService>());
  });

  test(
      'application shell and bootstrap keep composition responsibilities apart',
      () {
    final entry = File('lib/main.dart').readAsStringSync();
    final shell =
        File('lib/src/app/local_tag_player_app.dart').readAsStringSync();
    final bootstrap = File(
      'lib/src/composition/local_tag_player_bootstrap.dart',
    ).readAsStringSync();
    final compatibilityPath =
        <String>['lib', 'src', 'app.dart'].join(Platform.pathSeparator);

    expect(entry, contains('composition/local_tag_player_bootstrap.dart'));
    expect(entry, isNot(contains("import 'src/app.dart'")));
    expect(shell, contains('class LocalTagPlayerApp'));
    expect(shell, isNot(contains('Platform.')));
    expect(shell, isNot(contains('GitHubReleaseUpdateService')));
    expect(bootstrap, contains('GitHubReleaseUpdateService()'));
    expect(bootstrap, contains('createLocalTagPlayerDependencies'));
    expect(File(compatibilityPath).existsSync(), isFalse);
  });

  test('production source cannot restore the removed compatibility app barrel',
      () {
    final packageImport =
        <String>['package:local_tag_player/src/', 'app.dart'].join();
    final relativeImports = <String>[
      <String>["import 'src/", "app.dart'"].join(),
      <String>["import '../", "app.dart'"].join(),
      <String>["import '../../", "app.dart'"].join(),
    ];
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) {
          final source = file.readAsStringSync();
          return source.contains(packageImport) ||
              relativeImports.any(source.contains);
        })
        .map((file) => file.path)
        .toList();

    expect(offenders, isEmpty);
  });

  test('unit and integration tests import concrete production modules', () {
    final packageImport =
        <String>['package:local_tag_player/src/', 'app.dart'].join();
    final offenders = <String>[];
    for (final root in <String>['test', 'integration_test']) {
      offenders.addAll(
        Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .where((file) => file.readAsStringSync().contains(packageImport))
            .map((file) => file.path),
      );
    }

    // Phase 6 已删除兼容导出面；测试重新依赖万能 barrel 会掩盖真实模块边界。
    expect(offenders, isEmpty);
  });

  test('feature presentation modules do not import another presentation layer',
      () {
    final presentationFiles = Directory('lib/src/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) =>
            file.path.endsWith('.dart') &&
            file.path.contains(
                '${Platform.pathSeparator}presentation${Platform.pathSeparator}'));
    final offenders = <String>[];

    for (final file in presentationFiles) {
      final normalizedPath = file.path.replaceAll(r'\', '/');
      final ownFeature =
          RegExp(r'/features/([^/]+)/presentation/').firstMatch(normalizedPath);
      if (ownFeature == null) {
        continue;
      }
      final ownFeatureName = ownFeature.group(1);
      final imports = RegExp(
        r'''(?:import|export) ['"][^'"]*features/([^/]+)/presentation/''',
      ).allMatches(file.readAsStringSync());
      if (imports.any((match) => match.group(1) != ownFeatureName)) {
        offenders.add(file.path);
      }
    }

    // 跨功能流程必须通过 Route 输入或应用服务协作，不能耦合另一功能的 Widget 树。
    expect(offenders, isEmpty);
  });

  test('large page migration budgets can only shrink', () {
    final libraryLines = File('lib/src/pages/library/library_page.dart')
        .readAsLinesSync()
        .length;
    final playerLines =
        File('lib/src/pages/player/player_page.dart').readAsLinesSync().length;
    final libraryWidgetLines = File(
      'lib/src/widgets/library/library_widgets.dart',
    ).readAsLinesSync().length;
    final recentPlaybackLines = File(
      'lib/src/widgets/library/library_recent_playback_view.dart',
    ).readAsLinesSync().length;
    final tagEditorLines = File(
      'lib/src/widgets/library/library_tag_editor_dialog.dart',
    ).readAsLinesSync().length;
    final panelTransitionLines = File(
      'lib/src/widgets/library/library_panel_content_transition.dart',
    ).readAsLinesSync().length;
    final sidebarItemLines = File(
      'lib/src/widgets/library/library_sidebar_items.dart',
    ).readAsLinesSync().length;
    final resultViewToggleLines = File(
      'lib/src/widgets/library/library_result_view_toggle.dart',
    ).readAsLinesSync().length;
    final sidebarLines = File(
      'lib/src/widgets/library/library_sidebar.dart',
    ).readAsLinesSync().length;
    final collapsedSidebarLines = File(
      'lib/src/widgets/library/library_collapsed_sidebar.dart',
    ).readAsLinesSync().length;
    final sidebarBrandLines = File(
      'lib/src/widgets/library/library_sidebar_brand.dart',
    ).readAsLinesSync().length;
    final searchSurfaceLines = File(
      'lib/src/widgets/library/library_top_bar_search_surface.dart',
    ).readAsLinesSync().length;
    final filterStatusLines = File(
      'lib/src/widgets/library/library_top_bar_filter_status.dart',
    ).readAsLinesSync().length;
    final playbackBackendDropdownLines = File(
      'lib/src/features/settings/presentation/playback_backend_dropdowns.dart',
    ).readAsLinesSync().length;
    final playbackStreamCacheLines = File(
      'lib/src/features/settings/presentation/playback_stream_cache_card.dart',
    ).readAsLinesSync().length;
    final playbackQualityLines = File(
      'lib/src/features/settings/presentation/playback_quality_settings_panel.dart',
    ).readAsLinesSync().length;
    final deleteFileSettingsLines = File(
      'lib/src/features/settings/presentation/delete_file_settings_panel.dart',
    ).readAsLinesSync().length;
    final cacheFailureActionsLines = File(
      'lib/src/features/settings/presentation/cache_failure_actions.dart',
    ).readAsLinesSync().length;
    final playbackAndDecodingLines = File(
      'lib/src/features/settings/presentation/'
      'playback_and_decoding_settings_card.dart',
    ).readAsLinesSync().length;
    final playerInteractionLines = File(
      'lib/src/features/settings/presentation/'
      'player_interaction_settings_panels.dart',
    ).readAsLinesSync().length;
    final settingsWorkspaceScaffoldLines = File(
      'lib/src/features/settings/presentation/'
      'settings_workspace_scaffold.dart',
    ).readAsLinesSync().length;
    final cacheDiagnosticsSettingsCardLines = File(
      'lib/src/features/settings/presentation/'
      'cache_diagnostics_settings_card.dart',
    ).readAsLinesSync().length;
    final libraryTagDisplayHelpersLines = File(
      'lib/src/widgets/library/library_tag_display_helpers.dart',
    ).readAsLinesSync().length;
    final libraryFolderTagDiscoveryLines = File(
      'lib/src/widgets/library/library_folder_tag_discovery.dart',
    ).readAsLinesSync().length;
    final librarySelectionToolbarLines = File(
      'lib/src/widgets/library/library_selection_toolbar.dart',
    ).readAsLinesSync().length;
    final libraryTopToolbarTextButtonLines = File(
      'lib/src/widgets/library/library_top_toolbar_text_button.dart',
    ).readAsLinesSync().length;
    final libraryTagDiscoveryHeaderButtonLines = File(
      'lib/src/widgets/library/library_tag_discovery_header_button.dart',
    ).readAsLinesSync().length;
    final libraryReferenceIconButtonLines = File(
      'lib/src/widgets/library/library_reference_icon_button.dart',
    ).readAsLinesSync().length;
    final libraryCompactTopSortControlLines = File(
      'lib/src/widgets/library/library_compact_top_sort_control.dart',
    ).readAsLinesSync().length;
    final referenceTopBarSmokeHarnessLines = File(
      'lib/src/widgets/library/reference_top_bar_smoke_harness.dart',
    ).readAsLinesSync().length;
    final referenceTopBarResultHarnessLines = File(
      'lib/src/widgets/library/'
      'reference_top_bar_search_result_smoke_harness.dart',
    ).readAsLinesSync().length;
    final libraryAddTagDialogLines = File(
      'lib/src/widgets/library/library_add_tag_dialog.dart',
    ).readAsLinesSync().length;
    final libraryConfirmationDialogsLines = File(
      'lib/src/widgets/library/library_confirmation_dialogs.dart',
    ).readAsLinesSync().length;

    // 体积阈值随叶节点迁移继续下调；后续瘦身只能降低，禁止把代码塞回聚合文件。
    expect(libraryLines, lessThanOrEqualTo(4293));
    expect(playerLines, lessThanOrEqualTo(5226));
    expect(libraryWidgetLines, lessThanOrEqualTo(962));
    expect(recentPlaybackLines, lessThanOrEqualTo(299));
    expect(tagEditorLines, lessThanOrEqualTo(481));
    expect(panelTransitionLines, lessThanOrEqualTo(52));
    expect(sidebarItemLines, lessThanOrEqualTo(237));
    expect(resultViewToggleLines, lessThanOrEqualTo(221));
    expect(sidebarLines, lessThanOrEqualTo(418));
    expect(collapsedSidebarLines, lessThanOrEqualTo(213));
    expect(sidebarBrandLines, lessThanOrEqualTo(121));
    expect(searchSurfaceLines, lessThanOrEqualTo(241));
    expect(filterStatusLines, lessThanOrEqualTo(464));
    expect(playbackBackendDropdownLines, lessThanOrEqualTo(367));
    expect(playbackStreamCacheLines, lessThanOrEqualTo(47));
    expect(playbackQualityLines, lessThanOrEqualTo(371));
    expect(deleteFileSettingsLines, lessThanOrEqualTo(165));
    expect(cacheFailureActionsLines, lessThanOrEqualTo(158));
    expect(playbackAndDecodingLines, lessThanOrEqualTo(98));
    expect(playerInteractionLines, lessThanOrEqualTo(168));
    expect(settingsWorkspaceScaffoldLines, lessThanOrEqualTo(82));
    expect(cacheDiagnosticsSettingsCardLines, lessThanOrEqualTo(69));
    expect(libraryTagDisplayHelpersLines, lessThanOrEqualTo(157));
    expect(libraryFolderTagDiscoveryLines, lessThanOrEqualTo(153));
    expect(librarySelectionToolbarLines, lessThanOrEqualTo(120));
    expect(libraryTopToolbarTextButtonLines, lessThanOrEqualTo(56));
    expect(libraryTagDiscoveryHeaderButtonLines, lessThanOrEqualTo(90));
    expect(libraryReferenceIconButtonLines, lessThanOrEqualTo(39));
    expect(libraryCompactTopSortControlLines, lessThanOrEqualTo(171));
    expect(referenceTopBarSmokeHarnessLines, lessThanOrEqualTo(128));
    expect(referenceTopBarResultHarnessLines, lessThanOrEqualTo(108));
    expect(libraryAddTagDialogLines, lessThanOrEqualTo(126));
    expect(libraryConfirmationDialogsLines, lessThanOrEqualTo(74));
  });

  test('library widget leaves keep presentation ownership at the caller', () {
    final aggregate =
        File('lib/src/widgets/library/library_widgets.dart').readAsStringSync();
    final libraryPage =
        File('lib/src/pages/library/library_page.dart').readAsStringSync();
    final discoveryPanel = File(
      'lib/src/widgets/library/library_tag_discovery_panel.dart',
    ).readAsStringSync();
    final leafSources = <String, String>{
      'library_tag_display_helpers.dart': File(
        'lib/src/widgets/library/library_tag_display_helpers.dart',
      ).readAsStringSync(),
      'library_folder_tag_discovery.dart': File(
        'lib/src/widgets/library/library_folder_tag_discovery.dart',
      ).readAsStringSync(),
      'library_selection_toolbar.dart': File(
        'lib/src/widgets/library/library_selection_toolbar.dart',
      ).readAsStringSync(),
      'library_top_toolbar_text_button.dart': File(
        'lib/src/widgets/library/library_top_toolbar_text_button.dart',
      ).readAsStringSync(),
      'library_tag_discovery_header_button.dart': File(
        'lib/src/widgets/library/library_tag_discovery_header_button.dart',
      ).readAsStringSync(),
      'library_reference_icon_button.dart': File(
        'lib/src/widgets/library/library_reference_icon_button.dart',
      ).readAsStringSync(),
      'library_compact_top_sort_control.dart': File(
        'lib/src/widgets/library/library_compact_top_sort_control.dart',
      ).readAsStringSync(),
    };

    // 聚合层保留顶栏编排，只把可复用的纯展示叶子改为直接依赖。
    for (final importName in <String>[
      'library_selection_toolbar.dart',
      'library_top_toolbar_text_button.dart',
      'library_tag_discovery_header_button.dart',
      'library_reference_icon_button.dart',
      'library_compact_top_sort_control.dart',
    ]) {
      expect(aggregate, contains(importName));
    }
    expect(aggregate, isNot(contains('class _LibrarySelectionToolbar')));
    expect(aggregate, isNot(contains('class _CompactTopSortControl')));
    expect(aggregate, isNot(contains('Color libraryGroupColor(')));
    expect(
      aggregate,
      isNot(contains('List<TagGroup> folderTagGroupsFromLibraryPaths(')),
    );

    // 页面与标签发现面板直接依赖 helper，禁止经由旧聚合文件形成隐式耦合。
    for (final source in <String>[libraryPage, discoveryPanel]) {
      expect(source, contains('library_folder_tag_discovery.dart'));
      expect(source, contains('library_tag_display_helpers.dart'));
    }

    // 展示叶子只接收快照和回调，不能接管筛选、队列、缓存或应用 owner。
    for (final entry in leafSources.entries) {
      for (final forbiddenOwner in <String>[
        'FilterQuery',
        'TagQueryService',
        'PlaybackSession',
        'PlayerBackend',
        'ThumbnailService',
        'LibraryApplicationFacade',
        'setState(',
      ]) {
        expect(
          entry.value,
          isNot(contains(forbiddenOwner)),
          reason: '${entry.key} 不得接管 $forbiddenOwner',
        );
      }
    }
  });

  test('library dialogs return intents without taking page command ownership',
      () {
    final page =
        File('lib/src/pages/library/library_page.dart').readAsStringSync();
    final addTagDialog = File(
      'lib/src/widgets/library/library_add_tag_dialog.dart',
    ).readAsStringSync();
    final confirmationDialogs = File(
      'lib/src/widgets/library/library_confirmation_dialogs.dart',
    ).readAsStringSync();

    expect(page, contains('showLibraryAddTagDialog('));
    expect(page, contains('showRemoveLibraryRootConfirmation('));
    expect(page, contains('showClearAllRecentPlaybackConfirmation('));
    expect(page, isNot(contains('Future<String?> showLibraryAddTagDialog(')));
    expect(
      page,
      isNot(contains('Future<bool?> showRemoveLibraryRootConfirmation(')),
    );
    expect(
      page,
      isNot(contains('Future<bool?> showClearAllRecentPlaybackConfirmation(')),
    );

    // 叶子只返回用户意图，创建标签、移除目录和清理进度仍由页面 owner 执行。
    for (final source in <String>[addTagDialog, confirmationDialogs]) {
      for (final forbiddenCommand in <String>[
        'createManualTag(',
        'addFavoriteTag(',
        'removeLibraryRoot(',
        'clearPlaybackProgress(',
        'LibraryApplicationFacade',
        'FilterQuery',
        'PlaybackSession',
      ]) {
        expect(source, isNot(contains(forbiddenCommand)));
      }
    }
  });

  test('presentation files obey 200 500 and 1000 line governance', () {
    const bestPracticeLines = 200;
    const warningLines = 500;
    const refactorLines = 1000;
    const mandatoryRefactorOrder = <String>[
      'lib/src/pages/library/library_page.dart',
      'lib/src/pages/player/player_page.dart',
      'lib/src/widgets/library/library_video_results.dart',
      'lib/src/pages/player/player_queue_sidebar.dart',
      'lib/src/widgets/library/library_tag_discovery_panel.dart',
      'lib/src/pages/tags/tag_manager_page.dart',
      'lib/src/pages/library/missing_relink_page.dart',
    ];
    const legacyBudgets = <String, int>{
      'lib/src/pages/library/library_page.dart': 4293,
      'lib/src/pages/player/player_page.dart': 5226,
      'lib/src/widgets/library/library_widgets.dart': 962,
      'lib/src/widgets/library/library_video_results.dart': 2808,
      'lib/src/pages/player/player_queue_sidebar.dart': 1651,
      'lib/src/widgets/library/library_tag_discovery_panel.dart': 1511,
      'lib/src/pages/tags/tag_manager_page.dart': 1500,
      'lib/src/pages/library/missing_relink_page.dart': 1142,
      'lib/src/pages/player/player_settings_panel.dart': 985,
      'lib/src/widgets/app_theme_tokens.dart': 823,
      'lib/src/pages/player/player_control_slider.dart': 792,
      'lib/src/widgets/library/library_local_view.dart': 694,
      'lib/src/pages/player/player_context_panel.dart': 683,
      'lib/src/features/settings/presentation/'
          'data_backup_settings_workspace.dart': 666,
      'lib/src/features/settings/presentation/'
          'cache_diagnostics_snapshot_view.dart': 589,
      'lib/src/pages/library/directory_manager_page.dart': 571,
    };
    final presentationFiles = <File>[
      ...Directory('lib/src/pages')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory('lib/src/widgets')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory('lib/src/features')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) =>
              file.path.endsWith('.dart') &&
              file.path.replaceAll(r'\', '/').contains('/presentation/')),
    ];
    final activeLegacyBudgets = <String>{};
    final activeMandatoryRefactors = <String>{};

    for (final file in presentationFiles) {
      final path = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync().length;
      if (lines <= warningLines) {
        // 200 行是新增叶节点的最佳实践；201—500 行允许存在，但后续应优先继续拆分。
        expect(bestPracticeLines, lessThan(warningLines));
        continue;
      }
      final budget = legacyBudgets[path];
      activeLegacyBudgets.add(path);
      expect(
        budget,
        isNotNull,
        reason: '$path 已超过 $warningLines 行，必须先拆分，禁止新增超标 presentation 文件',
      );
      expect(
        lines,
        lessThanOrEqualTo(budget!),
        reason: '$path 的历史预算只能下降，当前 $lines 行、预算 $budget 行',
      );
      if (lines > refactorLines) {
        activeMandatoryRefactors.add(path);
        expect(
          mandatoryRefactorOrder.contains(path),
          isTrue,
          reason: '$path 已超过 $refactorLines 行，必须列入有序强制重构清单',
        );
      }
    }
    expect(
      activeLegacyBudgets,
      legacyBudgets.keys.toSet(),
      reason: '文件降到 $warningLines 行以内或被删除后，必须同步移除已失效的历史预算',
    );
    expect(
      activeMandatoryRefactors,
      mandatoryRefactorOrder.toSet(),
      reason: '所有超过 $refactorLines 行的 presentation 文件都必须进入有序治理清单',
    );
  });

  test('settings landing is a stateless feature leaf with preserved entry keys',
      () {
    final library =
        File('lib/src/pages/library/library_page.dart').readAsStringSync();
    final landing = File(
      'lib/src/features/settings/presentation/settings_landing_list.dart',
    ).readAsStringSync();

    expect(library, contains('settings_landing_list.dart'));
    expect(library, isNot(contains('class SettingsLandingList')));
    expect(
        landing, contains('class SettingsLandingList extends StatelessWidget'));
    for (final key in <String>[
      'settings.home',
      'settings.category.playback',
      'settings.category.videoQuality',
      'settings.category.playerInteraction',
      'settings.category.fileDeletion',
      'settings.category.dataBackup',
      'settings.category.cache',
      'settings.category.about',
      'settings.resumeBehavior.summary',
    ]) {
      expect(landing, contains(key), reason: '设置入口 Key 必须保留：$key');
    }
    expect(landing, isNot(contains('Navigator')));
    expect(landing, isNot(contains('showDialog')));
  });

  test('ordinary playback settings use one UI-independent consistency owner',
      () {
    final library =
        File('lib/src/pages/library/library_page.dart').readAsStringSync();
    final controller = File(
      'lib/src/features/settings/application/'
      'playback_settings_controller.dart',
    ).readAsStringSync();
    final serialController = File(
      'lib/src/features/settings/application/'
      'serial_settings_controller.dart',
    ).readAsStringSync();
    final settingsStateStart = library.indexOf('class _CacheSettingsPageState');
    final settingsStateEnd = library.indexOf(
      'class LibraryPage',
      settingsStateStart,
    );
    final settingsState =
        library.substring(settingsStateStart, settingsStateEnd);

    expect(
      controller,
      contains('extends SerialSettingsController<PlaybackSettings>'),
    );
    expect(
      serialController,
      contains('class SerialSettingsController<T> extends ChangeNotifier'),
    );
    expect(serialController, contains('_persistedValue'));
    expect(serialController, contains('_writeTail'));
    for (final forbidden in <String>[
      'BuildContext ',
      'Navigator.',
      'Route<',
      'ThumbnailService ',
      'CacheStats ',
      'DataBackupStatus ',
      'LibraryStore ',
      "import 'dart:io'",
      "import 'package:flutter/material.dart'",
    ]) {
      for (final source in <String>[controller, serialController]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: '普通播放设置 owner 不得持有跨边界资源：$forbidden',
        );
      }
    }
    expect(
      settingsState,
      contains('late final PlaybackSettingsController'),
    );
    expect(settingsState, isNot(contains('late PlaybackSettings _settings')));
    expect(settingsState, contains('DataBackupSettingsWorkspace('));
    expect(settingsState, contains('CacheDiagnosticsController<CacheStats>'));
  });

  test('settings display leaves only emit intents to the page owner', () {
    final library =
        File('lib/src/pages/library/library_page.dart').readAsStringSync();
    final leaves = <String, String>{
      for (final path in <String>[
        'lib/src/features/settings/presentation/playback_stream_cache_card.dart',
        'lib/src/features/settings/presentation/playback_quality_settings_panel.dart',
        'lib/src/features/settings/presentation/delete_file_settings_panel.dart',
        'lib/src/features/settings/presentation/cache_failure_actions.dart',
        'lib/src/features/settings/presentation/playback_and_decoding_settings_card.dart',
        'lib/src/features/settings/presentation/player_interaction_settings_panels.dart',
        'lib/src/features/settings/presentation/settings_workspace_scaffold.dart',
        'lib/src/features/settings/presentation/cache_diagnostics_settings_card.dart',
      ])
        path: File(path).readAsStringSync(),
    };

    for (final mount in <String>[
      'PlaybackStreamCacheCard(',
      'PlaybackQualitySettingsPanel(',
      'DeleteFileSettingsPanel(',
      'PlaybackAndDecodingSettingsCard(',
      'FullscreenQueueSettingsCard(',
      'PlayerShortcutsSettingsCard(',
      'SettingsWorkspaceScaffold(',
      'CacheDiagnosticsSettingsCard(',
    ]) {
      expect(library, contains(mount), reason: '设置页必须继续挂载展示叶节点：$mount');
    }
    final cacheCard = leaves.entries
        .singleWhere(
          (entry) => entry.key.endsWith('cache_diagnostics_settings_card.dart'),
        )
        .value;
    expect(cacheCard, contains('CacheDiagnosticsLoadStateView('));
    expect(cacheCard, contains('CacheFailureActions('));
    for (final entry in leaves.entries) {
      for (final forbidden in <String>[
        'PlaybackSettingsController',
        'CacheDiagnosticsController',
        'LibraryApplicationFacade',
        'ThumbnailService ',
        'TagQueryService',
        'FilterQuery',
        'PlayerPage',
        'Navigator.push',
      ]) {
        expect(
          entry.value,
          isNot(contains(forbidden)),
          reason: '${entry.key} 不得取得页面状态或业务命令所有权：$forbidden',
        );
      }
    }
  });

  test('data backup settings are a bounded vertical slice', () {
    final library =
        File('lib/src/pages/library/library_page.dart').readAsStringSync();
    final workspace = File(
      'lib/src/features/settings/presentation/'
      'data_backup_settings_workspace.dart',
    ).readAsStringSync();
    final serialController = File(
      'lib/src/features/settings/application/'
      'serial_settings_controller.dart',
    ).readAsStringSync();
    final controllers = File(
      'lib/src/features/settings/application/'
      'data_backup_controllers.dart',
    ).readAsStringSync();

    expect(
      workspace,
      contains('class DataBackupSettingsWorkspace extends StatefulWidget'),
    );
    expect(
      workspace,
      contains('SerialSettingsController<DataBackupSettings>'),
    );
    expect(
      workspace,
      contains('DataBackupStatusController<DataBackupStatus>'),
    );
    expect(
      workspace,
      contains(
        'DataBackupMaintenanceController<DataBackupIntegrityReport>',
      ),
    );
    expect(
      serialController,
      contains('class SerialSettingsController<T> extends ChangeNotifier'),
    );
    expect(
      controllers,
      contains('class DataBackupStatusController<T> extends ChangeNotifier'),
    );
    expect(controllers, contains('_subscription.cancel()'));
    expect(
      controllers,
      contains(
        'class DataBackupMaintenanceController<TReport> '
        'extends ChangeNotifier',
      ),
    );
    expect(controllers, contains('var _busy = false'));
    for (final forbidden in <String>[
      'LibraryStore ',
      'FileSystemAdapter ',
      'Database ',
      'BuildContext ',
      'Navigator.',
      'Route<',
      "import 'dart:io'",
      '/services/',
      '/repositories/',
    ]) {
      expect(
        controllers,
        isNot(contains(forbidden)),
        reason: '备份应用 controller 不得越过资源边界：$forbidden',
      );
      expect(
        serialController,
        isNot(contains(forbidden)),
        reason: '通用设置 owner 不得越过资源边界：$forbidden',
      );
    }
    for (final key in <String>[
      'settings.dataBackup.card',
      'settings.dataBackup.toggle',
      'settings.dataBackup.runNow',
      'settings.dataBackup.checkIntegrity',
      'settings.dataBackup.export',
    ]) {
      expect(workspace, contains(key), reason: '备份设置 Key 必须保留：$key');
    }
    expect(library, contains('DataBackupSettingsWorkspace('));
    expect(library, isNot(contains('class _DataBackupSettingsPanel')));
    expect(library, isNot(contains('_backupMaintenanceRunning')));
    expect(
      library,
      isNot(contains('StreamSubscription<DataBackupStatus>')),
    );
    // 跨服务原子边界仍留在页面应用服务回调：设置文件失败恢复运行态，导出继续通过平台 adapter。
    expect(
      library,
      contains('await store.setDataBackupEnabled(previous.enabled);'),
    );
    expect(library, contains('await _fileSystem.pickSavePath('));
    expect(
      library,
      contains('await _fileSystem.writeBytes(path, bytes, flush: true);'),
    );
  });

  test('cache diagnostics header is a read-only settings feature leaf', () {
    final library =
        File('lib/src/pages/library/library_page.dart').readAsStringSync();
    final settingsCard = File(
      'lib/src/features/settings/presentation/'
      'cache_diagnostics_settings_card.dart',
    ).readAsStringSync();
    final header = File(
      'lib/src/features/settings/presentation/cache_diagnostics_header.dart',
    ).readAsStringSync();
    final snapshot = File(
      'lib/src/features/settings/presentation/'
      'cache_diagnostics_snapshot_view.dart',
    ).readAsStringSync();
    final failureActions = File(
      'lib/src/features/settings/presentation/cache_failure_actions.dart',
    ).readAsStringSync();

    expect(library, contains('CacheDiagnosticsSettingsCard('));
    expect(settingsCard, contains('CacheDiagnosticsLoadStateView('));
    expect(settingsCard, contains('CacheFailureActions('));
    expect(failureActions, contains('CacheDiagnosticsSnapshotView('));
    expect(library, isNot(contains('class _CacheDiagnosticsHeader')));
    expect(snapshot, contains('CacheDiagnosticsHeader('));
    expect(header,
        contains('class CacheDiagnosticsHeader extends StatelessWidget'));
    expect(header, isNot(contains('ThumbnailService')));
    expect(header, isNot(contains('CacheStats')));
    expect(header, isNot(contains('FutureBuilder')));
    expect(header, isNot(contains('setState')));
    expect(header, isNot(contains('onRetry')));
    expect(header, isNot(contains('onClear')));
  });

  test('cache diagnostics snapshot is read-only while commands stay mounted',
      () {
    final library =
        File('lib/src/pages/library/library_page.dart').readAsStringSync();
    final failureActions = File(
      'lib/src/features/settings/presentation/cache_failure_actions.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/src/features/settings/application/'
      'cache_diagnostics_controller.dart',
    ).readAsStringSync();
    final maintenance = File(
      'lib/src/features/settings/application/'
      'cache_diagnostics_maintenance_controller.dart',
    ).readAsStringSync();
    final snapshot = File(
      'lib/src/features/settings/presentation/'
      'cache_diagnostics_snapshot_view.dart',
    ).readAsStringSync();
    final settingsCard = File(
      'lib/src/features/settings/presentation/'
      'cache_diagnostics_settings_card.dart',
    ).readAsStringSync();

    expect(
      snapshot,
      contains('class CacheDiagnosticsSnapshotView extends StatelessWidget'),
    );
    expect(snapshot, contains('final CacheStats stats'));
    expect(snapshot, contains('final Widget failureActions'));
    expect(snapshot, isNot(contains('FutureBuilder')));
    expect(snapshot, isNot(contains('ThumbnailService')));
    expect(snapshot, isNot(contains('retryFailed')));
    expect(snapshot, isNot(contains('clearFailures')));
    expect(snapshot, isNot(contains('setState')));
    expect(snapshot, isNot(contains('dart:io')));
    expect(
      snapshot,
      contains('class CacheDiagnosticsLoadStateView extends StatelessWidget'),
    );
    expect(snapshot, contains('class CacheDiagnosticsLoadError'));
    expect(snapshot, contains('failureActionsBuilder(stats, cacheBusy)'));
    for (final key in <String>[
      'settings.cache.coverage',
      'settings.cache.metric.',
      'settings.cache.taskSummary',
      'settings.cache.failureSemantics',
      'settings.cache.failureDetails',
    ]) {
      expect(snapshot, contains(key), reason: '缓存只读 Key 必须保留：$key');
    }
    expect(
      controller,
      contains('class CacheDiagnosticsController<T> extends ChangeNotifier'),
    );
    expect(controller, contains('_generation'));
    expect(controller, contains('_canPublish'));
    expect(controller, isNot(contains('services/')));
    expect(controller, isNot(contains('ThumbnailService ')));
    expect(controller, isNot(contains('BuildContext ')));
    expect(controller, isNot(contains('retryFailed')));
    expect(controller, isNot(contains('clearFailures')));
    expect(controller, isNot(contains('dart:io')));
    expect(
      maintenance,
      contains(
        'class CacheDiagnosticsMaintenanceController<T> '
        'extends ChangeNotifier',
      ),
    );
    expect(maintenance, contains('await _persistChanges(changed)'));
    expect(
        maintenance, contains('_restoreFailure(target.item, target.reason)'));
    expect(maintenance, isNot(contains('services/')));
    expect(maintenance, isNot(contains('BuildContext ')));
    expect(maintenance, isNot(contains('Navigator.')));
    expect(maintenance, isNot(contains('Route<')));
    expect(maintenance, isNot(contains('dart:io')));
    expect(library, isNot(contains('FutureBuilder<CacheStats>')));
    expect(library, contains('CacheDiagnosticsController<CacheStats>'));
    expect(
      library,
      contains('CacheDiagnosticsMaintenanceController<VideoItem>'),
    );
    expect(library, isNot(contains('bool _cacheActionRunning')));
    expect(library, contains('_cacheMaintenanceController.retry('));
    expect(library, contains('_cacheMaintenanceController.clear('));
    expect(library, contains('CacheDiagnosticsSettingsCard('));
    expect(settingsCard, contains('CacheDiagnosticsLoadStateView('));
    expect(settingsCard, contains('CacheFailureActions('));
    expect(failureActions, contains('class CacheFailureActions'));
    expect(failureActions, isNot(contains('ThumbnailService ')));
    expect(failureActions, isNot(contains('_retryFailedThumbnails')));
    expect(failureActions, isNot(contains('_clearThumbnailFailureMarkers')));
    expect(library, contains('_retryFailedThumbnails(stats)'));
    expect(library, contains('_clearThumbnailFailureMarkers(stats)'));
  });

  test('update feature follows domain data presentation dependency direction',
      () {
    final domain = Directory('lib/src/features/update/domain')
        .listSync()
        .whereType<File>()
        .map((file) => file.readAsStringSync())
        .join('\n');
    final data = File(
      'lib/src/features/update/data/github_release_update_service.dart',
    ).readAsStringSync();
    final presentation = Directory('lib/src/features/update/presentation')
        .listSync()
        .whereType<File>()
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(domain, isNot(contains('package:flutter/')));
    expect(domain, isNot(contains('dart:io')));
    expect(domain, isNot(contains('../data/')));
    expect(data, contains('../domain/app_update_service.dart'));
    expect(presentation, contains('../domain/app_update_service.dart'));
    expect(
      presentation,
      isNot(contains('../data/github_release_update_service.dart')),
    );
    expect(Directory('lib/src/services/update').existsSync(), isFalse);
    expect(
        File('lib/src/widgets/app_update_prompt.dart').existsSync(), isFalse);
    expect(
      File('lib/src/pages/settings/about_settings_page.dart').existsSync(),
      isFalse,
    );
  });

  test('LibraryPage depends on page services instead of the composition root',
      () {
    final source = File(
      'lib/src/pages/library/library_page.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('local_tag_player_dependencies.dart')));
    expect(source, isNot(contains('LocalTagPlayerDependencies')));
    expect(source, contains('LibraryPageApplicationService'));
    expect(source, contains('PlayerServiceFactory'));
    expect(source, contains('MediaProbeBackendFactory'));
  });

  test('library query epochs remain pure domain contracts', () {
    final source = File(
      'lib/src/features/library/domain/library_query_snapshot.dart',
    ).readAsStringSync();
    final revisions = File(
      'lib/src/features/library/application/library_revision_tracker.dart',
    ).readAsStringSync();
    final filterSource = File(
      'lib/src/services/tags/tag_query_service.dart',
    ).readAsStringSync();
    final pageSource = File(
      'lib/src/pages/library/library_page.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('package:flutter/')));
    expect(source, isNot(contains('dart:io')));
    expect(source, isNot(contains('BuildContext')));
    expect(source, isNot(contains('sqlite')));
    expect(
      revisions,
      contains('class LibraryRevisionTracker'),
    );
    expect(revisions, contains('LibraryDataChangeKind.tagDefinitions'));
    expect(revisions, isNot(contains('package:flutter/')));
    expect(revisions, isNot(contains('dart:io')));
    expect(revisions, isNot(contains('LibraryStore')));
    expect(revisions, isNot(contains('FilterQuery')));
    expect(filterSource, contains('LibraryResultEpoch'));
    expect(filterSource, isNot(contains('_querySignature')));
    expect(pageSource, contains('LibraryCountEpoch.fromQuery'));
    expect(pageSource, contains('final _libraryRevisionTracker'));
    expect(
      pageSource,
      contains('tagDefinitionRevision: _tagDefinitionRevision'),
    );
    expect(pageSource, isNot(contains('_libraryDataRevision += 1')));
    expect(
      pageSource,
      isNot(contains('tagDefinitionRevision: _libraryDataRevision')),
    );
    expect(pageSource, isNot(contains('sourceKey:')));
    expect(pageSource, isNot(contains('sortKey:')));
  });

  test('library selection and view preferences are bounded application owners',
      () {
    final page = File(
      'lib/src/pages/library/library_page.dart',
    ).readAsStringSync();
    final selection = File(
      'lib/src/features/library/application/'
      'library_selection_controller.dart',
    ).readAsStringSync();
    final viewPreferences = File(
      'lib/src/features/library/application/'
      'library_view_preferences_controller.dart',
    ).readAsStringSync();

    expect(selection, contains('class LibrarySelectionController'));
    expect(selection, contains('UnmodifiableSetView<String>'));
    expect(selection, contains('toggle(String videoId)'));
    expect(
        selection, isNot(contains("import '../../../models/video_item.dart'")));
    expect(selection, isNot(contains('final VideoItem')));
    expect(selection, isNot(contains('String path')));
    expect(viewPreferences, contains('class LibraryViewPreferencesController'));
    for (final forbidden in <String>[
      'BuildContext',
      'Navigator',
      'Route<',
      'FilterQuery',
      'TagQueryService',
      'ThumbnailService',
      'LibraryStore',
      'dart:io',
    ]) {
      expect(selection, isNot(contains(forbidden)));
      expect(viewPreferences, isNot(contains(forbidden)));
    }
    expect(page, contains('final _librarySelection ='));
    expect(page, contains('final _viewPreferences ='));
    expect(page, isNot(contains('var _librarySelectionMode =')));
    expect(page, isNot(contains('final _selectedLibraryVideoIds =')));
    expect(page, isNot(contains('var _denseResultGrid =')));
    expect(page, isNot(contains('var _isMainSidebarCollapsed =')));
    expect(page, isNot(contains('var _isTagDiscoveryPanelOpen =')));
    expect(page, contains('onEnterSelectionMode:'));
    expect(page, contains('onToggleSelectAll:'));
    expect(page, contains('onDeleteSelected:'));
    expect(page, contains('onCancelSelectionMode:'));
  });

  test(
      'library result sources and local history have one pure application owner',
      () {
    final page = File(
      'lib/src/pages/library/library_page.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/src/features/library/application/'
      'library_source_navigation_controller.dart',
    ).readAsStringSync();

    expect(
      controller,
      contains('class LibrarySourceNavigationController'),
    );
    expect(controller, contains('enum LibraryResultMode'));
    expect(controller, contains('void showLibraryResults()'));
    expect(controller, contains('void resetToLibrary()'));
    expect(controller, contains('void showLocalRoot(String rootPath)'));
    expect(controller, contains('void openLocalFolder(String folderPath)'));
    expect(controller, contains('bool goBack()'));
    expect(controller, contains('bool leaveRemovedRoot(String rootPath)'));
    for (final forbidden in <String>[
      "import 'dart:io'",
      "import 'package:flutter/",
      "import '../../../core/tag_rules.dart'",
      'BuildContext',
      'Navigator',
      'Route<',
      'LibraryStore',
      'LibraryApplicationFacade',
      'FilterQuery',
      'TagQueryService',
      'VideoItem',
      'ThumbnailService',
      'setState(',
    ]) {
      expect(
        controller,
        isNot(contains(forbidden)),
        reason: '来源导航 owner 不得越过页面、数据或平台边界：$forbidden',
      );
    }
    expect(
      page,
      contains('final _sourceNavigation = LibrarySourceNavigationController('),
    );
    expect(page, contains('normalizePath: TagRules.normalizeRootPath'));
    expect(page, contains('pathKey: TagRules.pathKey'));
    expect(page, contains('_sourceNavigation.showLibraryResults()'));
    expect(page, contains('_sourceNavigation.resetToLibrary()'));
    expect(page, contains('_sourceNavigation.showRecent()'));
    expect(page, contains('_sourceNavigation.showFavorites()'));
    expect(page, contains('_sourceNavigation.showLocalRoot(rootPath)'));
    expect(page, contains('_sourceNavigation.openLocalFolder(folderPath)'));
    expect(page, contains('_sourceNavigation.leaveRemovedRoot(root)'));
    expect(page, isNot(contains('enum _LibraryResultMode')));
    expect(page, isNot(contains('var _resultMode =')));
    expect(page, isNot(contains('String? _localLibraryPath;')));
    expect(page, isNot(contains('final _localLibraryBackStack =')));
    // 页面仍负责入口与复合筛选清理，controller 不吞掉可达性或标签语义。
    expect(page, contains('onShowAllLibrary: _showAllLibraryVideos'));
    expect(page, contains('onFavoritesToggle: _showFavoriteVideos'));
    expect(
      page,
      contains('onOpenRecentPlayback: _showRecentPlaybackVideos'),
    );
    expect(page, contains('onOpenLocalLibraryRoot: _showLocalLibraryPath'));
    expect(page, contains('onBack: _goBackLocalLibraryPath'));
    expect(page, contains('onOpenFolder: _openLocalLibraryFolder'));
  });

  test('library sorting is a pure owner and never re-runs filter or counts',
      () {
    final page = File(
      'lib/src/pages/library/library_page.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/src/features/library/application/library_sort_controller.dart',
    ).readAsStringSync();
    final domain = File(
      'lib/src/features/library/domain/library_sorting.dart',
    ).readAsStringSync();
    final applyStart = page.indexOf('void _applySortChange({');
    final applyEnd = page.indexOf(
      'void _setResultView(bool dense)',
      applyStart,
    );
    final applySort = page.substring(applyStart, applyEnd);

    expect(controller, contains('class LibrarySortController'));
    expect(controller, contains('String get fingerprint'));
    expect(controller, contains('List<VideoItem> sort('));
    expect(domain, contains('List<VideoItem> sortedLibraryVideos('));
    expect(page, contains('final _sortController = LibrarySortController()'));
    expect(page, contains('sortVideos: _sortController.sort'));
    expect(page, isNot(contains('var _sortMode =')));
    expect(page, isNot(contains('var _sortDirection =')));
    for (final forbidden in <String>[
      'BuildContext',
      'Navigator',
      'Route<',
      'TagQueryService',
      '.resultCounts(',
      'LibraryStore',
      'saveSortPreferences',
      'LibraryQueueSnapshot(',
      'dart:io',
    ]) {
      expect(controller, isNot(contains(forbidden)));
      expect(domain, isNot(contains(forbidden)));
    }
    expect(applySort, isNot(contains('_scheduleFilterRefresh(')));
    expect(applySort, isNot(contains('.resultCounts(')));
    expect(applySort, isNot(contains('LibraryQueueSnapshot(')));
    expect(applySort, contains('_sortController.sort'));
    expect(applySort, contains('saveSortPreferences'));
  });

  test('library query and facet counts have independent latest-only owners',
      () {
    final page = File(
      'lib/src/pages/library/library_page.dart',
    ).readAsStringSync();
    final query = File(
      'lib/src/features/library/application/library_query_controller.dart',
    ).readAsStringSync();
    final facets = File(
      'lib/src/features/library/application/'
      'library_facet_count_controller.dart',
    ).readAsStringSync();
    final refreshStart = page.indexOf('void _scheduleFilterRefresh({');
    final refreshEnd = page.indexOf(
      'LibraryResultEpoch _resultEpoch',
      refreshStart,
    );
    final refresh = page.substring(refreshStart, refreshEnd);

    expect(query, contains('class LibraryQueryController'));
    expect(query, contains('FilterState? _state'));
    expect(query, contains('FilterQuery? _requestedQuery'));
    expect(query, contains('requestRevision != _revision'));
    expect(query, contains('candidate.epoch != expectedEpoch'));
    expect(facets, contains('class LibraryFacetCountController'));
    expect(facets, contains('Map<String, int> _visibleCounts'));
    expect(facets, contains('Map<String, int> _stableCounts'));
    expect(facets, contains('Map<String, int>.unmodifiable'));
    expect(
      query,
      isNot(contains('library_facet_count_controller.dart')),
    );
    expect(
      facets,
      isNot(contains('library_query_controller.dart')),
    );
    expect(query, isNot(contains('LibraryCountEpoch')));
    expect(facets, isNot(contains('LibraryResultEpoch')));
    for (final source in <String>[query, facets]) {
      for (final forbidden in <String>[
        "import 'dart:io'",
        "import 'package:flutter/",
        'BuildContext ',
        'Navigator.',
        'Route<',
        'LibraryStore ',
        'ThumbnailService ',
        'MediaDetailsService ',
        'LibraryQueueSnapshot(',
      ]) {
        expect(source, isNot(contains(forbidden)));
      }
    }
    expect(page, contains('final _queryController ='));
    expect(page, contains('final _facetCountController ='));
    expect(page, isNot(contains('final _filterStateSource =')));
    expect(page, isNot(contains('final _countRefreshCoordinator =')));
    expect(page, isNot(contains('FilterState? _filterState;')));
    expect(page, isNot(contains('var _filterRevision =')));
    expect(
      page,
      isNot(contains('Map<String, int> _visibleResultCounts =')),
    );
    expect(page, isNot(contains('Map<String, int> _stableTagCounts =')));
    expect(refresh, contains('_queryController.schedule('));
    expect(refresh, contains('_facetCountController.scheduleVisible('));
    expect(
      refresh.indexOf('_queryController.schedule('),
      lessThan(refresh.indexOf('_facetCountController.scheduleVisible(')),
    );
  });

  test('playback queue only comes from an accepted stable-ID result snapshot',
      () {
    final page = File(
      'lib/src/pages/library/library_page.dart',
    ).readAsStringSync();
    final player = File(
      'lib/src/pages/player/player_page.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/src/features/library/application/'
      'library_playback_queue_controller.dart',
    ).readAsStringSync();
    final binding = File(
      'lib/src/features/library/presentation/library_queue_title.dart',
    ).readAsStringSync();
    final openStart = page.indexOf('Future<void> _openVideo(');
    final openEnd = page.indexOf(
      'Future<MediaDetails> _probeSelectedVideoBeforePlayback(',
      openStart,
    );
    final openFlow = page.substring(openStart, openEnd);

    expect(controller, contains('class LibraryPlaybackQueueController'));
    expect(controller, contains('LibraryQueueSnapshot.fromResult(result)'));
    expect(controller, contains('prepareSelection({'));
    expect(controller, contains('Future<void> warmNearby<T>({'));
    expect(controller, contains('video.videoId'));
    expect(controller, isNot(contains('TagQueryService')));
    expect(controller, isNot(contains('resultCounts(')));
    expect(controller, isNot(contains('sortedLibraryVideos')));
    expect(controller, isNot(contains('LibraryApplicationFacade')));
    expect(controller, isNot(contains('BuildContext ')));
    expect(controller, isNot(contains('Navigator.')));
    expect(controller, isNot(contains('PlayerPage(')));
    expect(binding, contains('class LibraryDisplayedPlaybackBinding'));
    expect(binding, isNot(contains('LibraryStore')));
    expect(binding, isNot(contains('TagQueryService')));
    expect(page, contains('bindDisplayedPlaybackResult('));
    expect(page, contains('_playbackQueueController.prepareSelection('));
    expect(page, contains('queueSnapshot: preparedQueue.snapshot'));
    expect(page, isNot(contains('onOpen: _openVideo')));
    expect(page, isNot(contains('onOpenVideo: _openVideo')));
    expect(page, isNot(contains('LibraryQueueSnapshot(')));
    expect(page, isNot(contains('LibraryResultSnapshot(')));
    expect(openFlow, isNot(contains('store.videos.values')));
    expect(openFlow, contains('playlist: playlist'));
    expect(player, contains('final LibraryQueueSnapshot? queueSnapshot'));
  });

  test('player session owns stable-ID queue state outside presentation', () {
    final page = File(
      'lib/src/pages/player/player_page.dart',
    ).readAsStringSync();
    final session = File(
      'lib/src/features/player/application/player_session_controller.dart',
    ).readAsStringSync();
    final compatibility = File(
      'lib/src/pages/player/player_playback_controller.dart',
    ).readAsStringSync();

    expect(session, contains('class PlayerSessionController'));
    expect(session, contains('acceptedSourceVideoIds'));
    expect(session, contains('UnmodifiableListView<VideoItem>'));
    expect(
      session,
      contains('video.videoId == item.videoId'),
    );
    expect(
      session,
      contains('item.videoId == preferredVideoId'),
    );
    expect(session, isNot(contains('item.path ==')));
    expect(session, isNot(contains('video.path ==')));
    for (final forbidden in <String>[
      "import 'dart:io'",
      "import 'package:flutter/",
      'BuildContext',
      'Navigator',
      'Route<',
      'LibraryStore',
      'LibraryApplicationFacade',
      'FilterQuery',
      'TagQueryService',
      '/services/player/',
      'TagRules',
      'setState(',
    ]) {
      expect(
        session,
        isNot(contains(forbidden)),
        reason: '播放器会话 owner 不得越过 UI、Store 或后端边界：$forbidden',
      );
    }
    expect(page, contains('late final PlayerSessionController _playback'));
    expect(page, contains('_playback = PlayerSessionController('));
    expect(
      page,
      contains(
        'acceptedSourceVideoIds: widget.queueSnapshot?.orderedVideoIds',
      ),
    );
    expect(page, contains('initialVideoId: widget.initialItem.videoId'));
    expect(page, contains('matchesChildTag: TagRules.matchesChildTag'));
    expect(page, contains('sourcePlaylist: _sourcePlaylist'));
    expect(page, contains('playingIndex: _index'));
    expect(page, contains('selectedIndex: _selectedIndex'));
    expect(page, contains('onChildTagSelected: _selectChildTag'));
    expect(page, contains('onSelect: _select'));
    expect(page, contains('onPlay: _jumpTo'));
    expect(
      compatibility,
      contains(
        "export '../../features/player/application/"
        "player_session_controller.dart';",
      ),
    );
    expect(compatibility, isNot(contains('class PlayerPlaybackController')));
  });

  test('player open requests and backend events have pure lifecycle owners',
      () {
    final page = File(
      'lib/src/pages/player/player_page.dart',
    ).readAsStringSync();
    final requests = File(
      'lib/src/features/player/application/'
      'player_open_request_controller.dart',
    ).readAsStringSync();
    final events = File(
      'lib/src/features/player/application/player_backend_event_bridge.dart',
    ).readAsStringSync();
    final resources = File(
      'lib/src/services/player/player_resource_lifecycle_coordinator.dart',
    ).readAsStringSync();
    final progress = File(
      'lib/src/features/player/domain/player_playback_progress.dart',
    ).readAsStringSync();
    final compatibility = File(
      'lib/src/pages/player/player_open_request_controller.dart',
    ).readAsStringSync();
    final libraryPage = File(
      'lib/src/pages/library/library_page.dart',
    ).readAsStringSync();
    final recentPlayback = File(
      'lib/src/widgets/library/library_recent_playback_view.dart',
    ).readAsStringSync();

    expect(requests, contains('class PlayerOpenRequestController'));
    expect(requests, contains('final int revision'));
    expect(requests, contains('final String videoId'));
    expect(requests, contains('final String path'));
    expect(requests, contains('bool hasSuperseded(PlayerOpenRequest request)'));
    expect(requests, isNot(contains("import 'package:flutter")));
    expect(events, contains('class PlayerBackendEventBridge'));
    expect(events, contains('Future<void> dispose()'));
    expect(events, isNot(contains("import 'package:flutter")));
    expect(events, isNot(contains('../services/')));
    expect(progress, contains('bool videoIsContinueWatching(VideoItem item)'));
    expect(
        page, contains('late final PlayerBackendEventBridge _backendEvents'));
    expect(page, contains('cancelBackendEvents: _backendEvents.dispose'));
    expect(page, isNot(contains('StreamSubscription<bool>?')));
    expect(
      resources.indexOf('await _cancelBackendEvents();'),
      lessThan(resources.indexOf('await _disposeResource();')),
    );
    expect(
      compatibility,
      contains(
        "export '../../features/player/application/"
        "player_open_request_controller.dart';",
      ),
    );
    expect(
      compatibility,
      contains(
        "export '../../features/player/domain/"
        "player_playback_progress.dart';",
      ),
    );
    expect(compatibility, isNot(contains('class PlayerOpenRequestController')));
    expect(
      libraryPage,
      contains(
        "import '../../features/player/domain/"
        "player_playback_progress.dart';",
      ),
    );
    expect(
      recentPlayback,
      contains(
        "import '../../features/player/domain/"
        "player_playback_progress.dart';",
      ),
    );
  });

  test('player native resources and fullscreen have single lifecycle owners',
      () {
    final page = File(
      'lib/src/pages/player/player_page.dart',
    ).readAsStringSync();
    final fullscreen = File(
      'lib/src/features/player/application/'
      'player_fullscreen_lifecycle_controller.dart',
    ).readAsStringSync();
    final resources = File(
      'lib/src/services/player/player_resource_lifecycle_coordinator.dart',
    ).readAsStringSync();

    expect(
      fullscreen,
      contains('class PlayerFullscreenLifecycleController'),
    );
    expect(fullscreen, contains('Future<void> restoreSession('));
    expect(fullscreen, contains('Future<void> toggle('));
    expect(fullscreen, contains('Future<void> prepareForExit('));
    for (final forbidden in <String>[
      "import 'package:flutter",
      'BuildContext ',
      'Navigator.',
      'Route<',
      'PlayerBackend ',
      'PlayerService ',
      'window_manager',
      'setState(',
    ]) {
      expect(
        fullscreen,
        isNot(contains(forbidden)),
        reason: '全屏状态机不得持有 UI、后端或原生窗口资源：$forbidden',
      );
    }

    expect(
      resources,
      contains('class PlayerResourceLifecycleCoordinator'),
    );
    expect(resources, contains('Future<void> stopForExit()'));
    expect(resources, contains('Future<void> release()'));
    final cancelIndex = resources.indexOf('await _cancelBackendEvents();');
    final stopIndex = resources.indexOf('await stopForExit();');
    final disposeIndex = resources.indexOf('await _disposeResource();');
    final releasedIndex = resources.indexOf('await _awaitReleased();');
    expect(cancelIndex, greaterThanOrEqualTo(0));
    expect(cancelIndex, lessThan(stopIndex));
    expect(stopIndex, lessThan(disposeIndex));
    expect(disposeIndex, lessThan(releasedIndex));

    expect(
      page,
      contains(
        'late final PlayerResourceLifecycleCoordinator _playerResources',
      ),
    );
    expect(
      page,
      contains(
        'late final PlayerFullscreenLifecycleController _windowFullscreen',
      ),
    );
    expect(page, contains('unawaited(_playerResources.release())'));
    expect(page, isNot(contains('_playerService.dispose()')));
    expect(page, contains('awaitReleased: () => _playerService.released'));
    expect(page, isNot(contains('await _playerService.released')));
    expect(page, isNot(contains('textureId.addListener')));
    expect(page, isNot(contains('textureId.removeListener')));
    expect(page, contains('await _windowFullscreen.toggle('));
    expect(page, contains('canExecuteWindowCommand: () => mounted'));
    expect(
      page,
      contains('setFullscreen: windowManager.setFullScreen'),
    );
  });

  test('player diagnostics presentation only consumes snapshots and callbacks',
      () {
    final page = File(
      'lib/src/pages/player/player_page.dart',
    ).readAsStringSync();
    final dialog = File(
      'lib/src/pages/player/player_diagnostics_dialog.dart',
    ).readAsStringSync();
    final snapshot = File(
      'lib/src/features/player/domain/playback_diagnostics_snapshot.dart',
    ).readAsStringSync();

    expect(snapshot, contains('class PlaybackDiagnosticsSnapshot'));
    expect(snapshot, isNot(contains("import 'package:flutter")));
    expect(snapshot, isNot(contains('/services/player/')));
    expect(snapshot, isNot(contains('PlayerBackend ')));
    expect(dialog, contains('final Stream<bool> playingChanges'));
    expect(dialog, contains('final PlaybackDiagnosticsSampler sample'));
    expect(dialog, contains('widget.playingChanges.listen'));
    expect(dialog, contains('await widget.sample()'));
    expect(dialog, isNot(contains("import 'player_page.dart'")));
    expect(dialog, isNot(contains('PlayerPageState ')));
    expect(dialog, isNot(contains('PlayerService ')));
    expect(page, contains('playingChanges: _playerService.playingChanges'));
    expect(page, contains('sample: buildDiagnosticsSnapshot'));
    expect(page, isNot(contains('playerPage: this')));
  });

  test('player control visibility and feedback timers have one pure owner', () {
    final page = File(
      'lib/src/pages/player/player_page.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/src/features/player/application/'
      'player_interaction_state_controller.dart',
    ).readAsStringSync();

    expect(controller, contains('class PlayerInteractionStateController'));
    expect(controller, contains('Timer? _controlsHideTimer'));
    expect(controller, contains('Timer? _feedbackHideTimer'));
    expect(controller, contains('void showControls('));
    expect(controller, contains('void showFeedback('));
    expect(controller, contains('void dispose()'));
    expect(controller, isNot(contains("import 'package:flutter")));
    expect(controller, isNot(contains('BuildContext ')));
    expect(controller, isNot(contains('FocusNode')));
    expect(page, contains('PlayerInteractionStateController<IconData>'));
    expect(page, contains('_interaction.openSettings();'));
    expect(page, contains('_interaction.closeSettings();'));
    expect(page, contains('_interaction.dispose();'));
    expect(page, isNot(contains('Timer? _controlsHideTimer')));
    expect(page, isNot(contains('Timer? _shortcutFeedbackTimer')));
    expect(page, contains('Timer? _fullscreenQueueHideTimer'));
    expect(page, contains("FocusNode(debugLabel: 'player-shortcuts')"));
  });

  test('player shortcut suspension and focus eligibility have one pure owner',
      () {
    final page = File(
      'lib/src/pages/player/player_page.dart',
    ).readAsStringSync();
    final gate = File(
      'lib/src/features/player/application/'
      'player_shortcut_gate_controller.dart',
    ).readAsStringSync();

    expect(gate, contains('class PlayerShortcutGateController'));
    expect(gate, contains('void beginSuspension()'));
    expect(gate, contains('void endSuspension()'));
    expect(gate, contains('bool canHandle('));
    expect(gate, contains('bool canRestoreFocus('));
    expect(gate, isNot(contains("import 'package:flutter")));
    expect(
        page, contains('final _shortcutGate = PlayerShortcutGateController'));
    expect(page, contains('_shortcutGate.beginSuspension();'));
    expect(page, contains('_shortcutGate.endSuspension();'));
    expect(page, contains('_shortcutGate.canHandle('));
    expect(page, contains('_shortcutGate.canRestoreFocus('));
    expect(page, isNot(contains('var _shortcutSuspensionDepth')));
    expect(page, isNot(contains('var _editingManualTags')));
    expect(page, contains('FocusManager.instance.primaryFocus'));
    expect(page, contains('HardwareKeyboard.instance'));
  });

  test('scan and import lifecycle has one latest-only application owner', () {
    final page = File(
      'lib/src/pages/library/library_page.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/src/features/library/application/'
      'library_scan_lifecycle_controller.dart',
    ).readAsStringSync();
    final labels = File(
      'lib/src/features/library/presentation/'
      'library_scan_progress_labels.dart',
    ).readAsStringSync();

    expect(
      controller,
      contains('class LibraryScanLifecycleController<TMediaProgress>'),
    );
    expect(controller, contains('_scanOperationRevision'));
    expect(controller, contains('_activeScanGeneration'));
    expect(controller, contains('beginPathImportInspection()'));
    expect(controller, contains('toggleScanPaused({'));
    expect(controller, contains('cancelScan({'));
    expect(controller, contains('beginMediaImport({'));
    expect(controller, contains('publishMediaImportProgress({'));
    expect(controller, isNot(contains('LibraryApplicationFacade')));
    expect(controller, isNot(contains('LibraryStore')));
    expect(
      controller,
      isNot(contains("import '../../../platform/file_system_adapter.dart'")),
    );
    expect(controller, isNot(contains('MediaDetailsService')));
    expect(controller, isNot(contains('ThumbnailService')));
    expect(controller, isNot(contains("import 'package:flutter/")));
    expect(controller, isNot(contains('Navigator.')));
    expect(controller, isNot(contains('setState(')));
    expect(labels, contains('libraryScanProgressLabel('));
    expect(labels, contains('libraryMediaImportProgressLabel('));
    expect(labels, isNot(contains('BuildContext')));
    expect(
        page, contains('LibraryScanLifecycleController<MediaDetailsProgress>'));
    expect(page, contains('beginPathImportInspection()'));
    expect(page, contains('_scanLifecycleController.run('));
    expect(page, contains('_scanLifecycleController.toggleScanPaused('));
    expect(page, contains('_scanLifecycleController.cancelScan('));
    expect(page, contains('publishPlaybackPause('));
    expect(page, contains('publishMediaImportProgress('));
    expect(page, isNot(contains('var _isScanning =')));
    expect(page, isNot(contains('var _isCancellingScan =')));
    expect(page, isNot(contains('LibraryScanProgress? _scanProgress;')));
    expect(page, contains('LibraryImportDropRegion('));
    expect(page, contains('Future<void> _pickFolder()'));
    expect(page, contains('Future<void> _pickVideoFiles()'));
    expect(page, contains('Future<void> _rescan()'));
    expect(page, contains('setPaused: store.setScanPaused'));
  });

  test('library file actions are explicit UI-independent commands', () {
    final page = File(
      'lib/src/pages/library/library_page.dart',
    ).readAsStringSync();
    final executor = File(
      'lib/src/features/library/application/'
      'library_file_command_executor.dart',
    ).readAsStringSync();
    final deleteDialog = File(
      'lib/src/pages/player/player_delete_dialog.dart',
    ).readAsStringSync();

    expect(executor, contains('class RevealVideoLocationCommand'));
    expect(executor, contains('class RenameVideoFileCommand'));
    expect(executor, contains('class DeleteVideoCommand'));
    expect(executor, contains('class LibraryFileCommandExecutor'));
    expect(executor, contains('Future<LibraryBatchDeleteResult> deleteAll('));
    expect(executor, contains('await commitRenamedPath(item, renamedPath)'));
    expect(executor, contains('await renameFile(renamedPath, oldPath)'));
    expect(executor, contains('await moveFileToTrash(item.path)'));
    expect(executor, contains('await deleteRecord(item.path)'));
    expect(executor, isNot(contains("import 'package:flutter/")));
    expect(executor, isNot(contains('LibraryApplicationFacade')));
    expect(executor, isNot(contains('LibraryStore')));
    expect(
      executor,
      isNot(contains("import '../../../platform/file_system_adapter.dart'")),
    );
    expect(executor, isNot(contains('ThumbnailService')));
    expect(executor, isNot(contains('Navigator.')));
    expect(executor, isNot(contains('ScaffoldMessenger')));
    expect(page, contains('const LibraryFileCommandExecutor()'));
    expect(page, contains('_fileCommandExecutor.reveal('));
    expect(page, contains('_fileCommandExecutor.rename('));
    expect(page, contains('_fileCommandExecutor.delete('));
    expect(page, contains('_fileCommandExecutor.deleteAll('));
    expect(page, contains('showPlayerDeleteConfirmationDialog('));
    expect(page, contains('showBatchVideoDeleteConfirmationDialog('));
    expect(deleteDialog, contains("ValueKey('deleteDialog.moveToTrash')"));
    expect(deleteDialog, contains("ValueKey('deleteDialog.dontAskAgain')"));
  });

  test('manual tag replacement is an explicit compensating command', () {
    final page = File(
      'lib/src/pages/library/library_page.dart',
    ).readAsStringSync();
    final executor = File(
      'lib/src/features/library/application/'
      'library_manual_tag_command_executor.dart',
    ).readAsStringSync();
    final maintenance = File(
      'lib/src/services/library/library_tag_maintenance.dart',
    ).readAsStringSync();
    final store = File(
      'lib/src/services/library/library_store.dart',
    ).readAsStringSync();
    final backup = File(
      'lib/src/services/library/library_data_backup_service.dart',
    ).readAsStringSync();

    expect(executor, contains('class ReplaceVideoManualTagsCommand'));
    expect(executor, contains('class LibraryManualTagCommandExecutor'));
    expect(executor, contains('..._normalize(command.lockedFolderTags)'));
    expect(executor, contains('..._normalize(command.selectedTags)'));
    expect(executor, contains('await commit(item, parentTag)'));
    expect(executor, contains('..addAll(previousTags)'));
    expect(executor, contains('..addAll(previousChildTags)'));
    expect(executor, isNot(contains("import 'package:flutter/")));
    expect(executor, isNot(contains('LibraryApplicationFacade')));
    expect(executor, isNot(contains('LibraryStore')));
    expect(executor, isNot(contains('TagQueryService')));
    expect(executor, isNot(contains('Navigator.')));
    expect(page, contains('const LibraryManualTagCommandExecutor()'));
    expect(page, contains('_manualTagCommandExecutor.replace('));
    expect(page, contains('ReplaceVideoManualTagsCommand('));
    expect(page, contains('lockedTags: lockedTags'));
    expect(page, contains('TagEditorDialog('));
    expect(page, isNot(contains('Set<String> _normalizeTagSet(')));
    expect(maintenance, contains('final previousLinks ='));
    expect(maintenance, contains('final previousTagIds ='));
    expect(maintenance, contains('_store.videoTagIdsByPathKey[pathKey] ='));
    expect(maintenance, contains('_store.tagsById.removeWhere('));
    expect(store, contains('enqueueVideoBestEffort(item.videoId)'));
    expect(backup, contains('Future<void> enqueueVideoBestEffort('));
    expect(backup, contains('phase: DataBackupPhase.failed'));
  });

  test('single missing relink is a stale-safe UI-independent command', () {
    final page = File(
      'lib/src/pages/library/missing_relink_page.dart',
    ).readAsStringSync();
    final libraryPage = File(
      'lib/src/pages/library/library_page.dart',
    ).readAsStringSync();
    final executor = File(
      'lib/src/features/library/application/'
      'library_missing_relink_command_executor.dart',
    ).readAsStringSync();
    final coordinator = File(
      'lib/src/services/library/library_scan_coordinator.dart',
    ).readAsStringSync();

    expect(executor, contains('class RelinkMissingVideoCommand'));
    expect(executor, contains('class LibraryMissingRelinkCommandExecutor'));
    expect(executor, contains('item.path != command.previousPath'));
    expect(executor, contains('item.mediaFingerprint !='));
    expect(executor, contains('_runningVideoIds.add(command.videoId)'));
    expect(executor, isNot(contains("import 'package:flutter/")));
    expect(executor, isNot(contains('LibraryApplicationFacade')));
    expect(executor, isNot(contains('LibraryStore')));
    expect(executor, isNot(contains('FileSystemAdapter')));
    expect(executor, isNot(contains('BuildContext context')));
    expect(executor, isNot(contains('Navigator.')));
    expect(page, contains('pickMissingVideoReplacementFile('));
    expect(page, contains('_relinkCommandExecutor.execute('));
    expect(page, contains('showMissingRelinkCommandResult('));
    expect(page, contains("ValueKey('missingRelink.bulkPreview')"));
    expect(page, contains("ValueKey('missingRelink.list')"));
    expect(page, contains('pickAndRelinkMissingVideo('));
    expect(libraryPage, contains('pickAndRelinkMissingVideo('));
    expect(coordinator, contains('final itemSnapshot ='));
    expect(coordinator, contains('_restoreVideoItem(missing, itemSnapshot)'));
  });

  test('continue watching commands use stable identity outside LibraryPage',
      () {
    final page = File(
      'lib/src/pages/library/library_page.dart',
    ).readAsStringSync();
    final widgets = File(
      'lib/src/widgets/library/library_recent_playback_view.dart',
    ).readAsStringSync();
    final executor = File(
      'lib/src/features/library/application/'
      'library_continue_watching_command_executor.dart',
    ).readAsStringSync();

    expect(executor, contains('class ContinueWatchingClearSnapshot'));
    expect(
      executor,
      contains('class LibraryContinueWatchingCommandExecutor'),
    );
    expect(executor, contains('selectedVideoIds.contains(item.videoId)'));
    expect(
        executor, contains('snapshot.canRestoreWithoutOverwritingNewPlayback'));
    expect(executor, contains('await commit('));
    expect(executor, isNot(contains("import 'package:flutter/")));
    expect(executor, isNot(contains('LibraryApplicationFacade')));
    expect(executor, isNot(contains('LibraryStore')));
    expect(executor, isNot(contains('BuildContext context')));
    expect(executor, isNot(contains('ScaffoldMessenger')));
    expect(page, contains('_continueWatchingCommands.clear('));
    expect(page, contains('_continueWatchingCommands.undo('));
    expect(page, contains('_recentPlaybackSelection.selectedVideoIds'));
    expect(page, isNot(contains('_selectedRecentPathKeys')));
    expect(page, isNot(contains('class ContinueWatchingClearSnapshot')));
    expect(widgets, contains('selectedVideoIds.contains(item.videoId)'));
    expect(widgets, isNot(contains('selectedPathKeys')));
  });

  test('PlayerPage keeps hidden progress mounted before the full controls', () {
    final source = File(
      'lib/src/pages/player/player_page.dart',
    ).readAsStringSync();
    final hiddenLayerIndex = source.indexOf(
      "key: const ValueKey('player.controls.hiddenProgress')",
    );
    final hiddenWidgetIndex = source.indexOf(
      'child: PlayerHiddenProgressBar(',
      hiddenLayerIndex < 0 ? 0 : hiddenLayerIndex,
    );
    final fullControlsIndex = source.indexOf(
      "key: const ValueKey('player.controls.opacity')",
    );

    // 该保护专门捕获组件仍存在、孤立组件测试仍通过，但真实页面挂载被删除的事故。
    expect(hiddenLayerIndex, greaterThanOrEqualTo(0));
    expect(hiddenWidgetIndex, greaterThan(hiddenLayerIndex));
    expect(fullControlsIndex, greaterThan(hiddenWidgetIndex));
    expect(
      source.substring(hiddenLayerIndex, fullControlsIndex),
      contains('opacity: _controlsVisible ? 0 : 1'),
    );
  });

  test('PlayerPage gear keeps compression enhancement mounted and reachable',
      () {
    final pageSource = File(
      'lib/src/pages/player/player_page.dart',
    ).readAsStringSync();
    final panelSource = File(
      'lib/src/pages/player/player_settings_panel.dart',
    ).readAsStringSync();

    // 同时保护齿轮按钮、页面回调和三档入口，避免组件仍存在但从真实播放器孤立。
    expect(pageSource, contains("'player.settings'"));
    expect(pageSource, contains('_showControlSettingsDialog()'));
    expect(
      pageSource,
      contains('compressionEnhancementMode: _compressionEnhancementMode'),
    );
    expect(
      pageSource,
      contains('onCompressionEnhancementModeChanged:'),
    );
    expect(pageSource, isNot(contains('nvidiaVideoEnhancementCapability:')));
    expect(
      pageSource,
      isNot(contains('onNvidiaVideoEnhancementExperimentChanged:')),
    );
    expect(
      pageSource,
      isNot(contains('onNvidiaVideoHdrExperimentChanged:')),
    );
    expect(pageSource, contains('_setCompressionEnhancementMode'));
    expect(
      panelSource,
      contains("ValueKey('player.settings.compression.open')"),
    );
    expect(
      panelSource,
      contains("'player.settings.compression.\${mode.name}'"),
    );
    expect(
      panelSource,
      isNot(contains("'player.settings.nvidiaVideoEnhancementExperiment'")),
    );
    expect(
      panelSource,
      isNot(contains("'player.settings.nvidiaVideoHdrExperiment'")),
    );
  });

  test('Windows build patches media texture callbacks to stable descriptors',
      () {
    final nativeBuild =
        File('windows/native_player/CMakeLists.txt').readAsStringSync();
    final windowsBuild = File('windows/CMakeLists.txt').readAsStringSync();
    final generatedPatchStart =
        nativeBuild.indexOf('set(LTP_VIDEO_OUTPUT_GPU_PATCH');
    final generatedPatchEnd = nativeBuild.indexOf(
      r'file(WRITE "${LTP_PATCHED_MEDIA_KIT_VIDEO_OUTPUT_SOURCE}"',
    );
    expect(generatedPatchStart, greaterThanOrEqualTo(0));
    expect(generatedPatchEnd, greaterThan(generatedPatchStart));
    final generatedPatch =
        nativeBuild.substring(generatedPatchStart, generatedPatchEnd);

    // RegisterTexture 允许同步取帧；回调必须绑定自己的描述符，不能读取尚未入表或已切换的全局 ID。
    expect(generatedPatch, contains('[&, texture_descriptor]'));
    expect(generatedPatch, contains('return texture_descriptor'));
    expect(generatedPatch, contains('[&, pixel_buffer_descriptor]'));
    expect(generatedPatch, contains('return pixel_buffer_descriptor'));
    expect(
      windowsBuild,
      contains('LTP_PATCHED_MEDIA_KIT_VIDEO_OUTPUT_SOURCE'),
    );
    expect(
      windowsBuild,
      contains('(angle_surface_manager|video_output)\\\\.cc'),
    );
  });

  test('local video enhancement prototype is explicit and never installed', () {
    final nativeBuild =
        File('windows/native_player/CMakeLists.txt').readAsStringSync();
    final runnerBuild =
        File('windows/runner/CMakeLists.txt').readAsStringSync();
    final bridge =
        File('windows/runner/native_player_bridge.cpp').readAsStringSync();
    final host = File(
      'windows/runner/local_video_enhancement_plugin.cpp',
    ).readAsStringSync();
    final api = File(
      'windows/native_player/local_video_enhancement_plugin_api.h',
    ).readAsStringSync();

    // 原型只能通过绝对路径显式加载；标准构建不启用、不安装探针，也不引用厂商 SDK。
    expect(
      host,
      contains('LOCAL_TAG_PLAYER_VIDEO_PLUGIN_PATH'),
    );
    expect(host, contains('plugin-path-must-be-absolute'));
    expect(host, contains('LoadLibraryExW'));
    expect(api, contains('kLtpLocalVideoPluginAbiVersion = 1'));
    expect(
      nativeBuild,
      contains('option(LTP_BUILD_LOCAL_VIDEO_PLUGIN_PROBE'),
    );
    expect(
      nativeBuild,
      contains('"Build the local D3D11 video enhancement probe DLL" OFF'),
    );
    expect(nativeBuild, isNot(contains('install(TARGETS ltp_local_video')));
    expect(runnerBuild, contains('local_video_enhancement_plugin.cpp'));
    final prototypeSource =
        '$nativeBuild$runnerBuild$bridge$host$api'.toLowerCase();
    expect(prototypeSource, isNot(contains('#include <nvvfx')));
    expect(prototypeSource, isNot(contains('nvvfx.dll')));
    expect(prototypeSource, isNot(contains('maxine')));

    // 共享纹理必须在工作线程复制和处理；插件失败前已有宿主备份可恢复。
    final renderStart = bridge.indexOf('void NativePlayerBridge::RenderFrame');
    final enqueueStart = bridge.indexOf('void NativePlayerBridge::Enqueue');
    final renderBody = bridge.substring(renderStart, enqueueStart);
    expect(renderBody, contains('surface_manager_->Read()'));
    expect(renderBody, contains('video_enhancement_plugin_.ProcessFrame'));
    expect(
      renderBody.indexOf('surface_manager_->Read()'),
      lessThan(renderBody.indexOf('video_enhancement_plugin_.ProcessFrame')),
    );
    expect(host, contains('CopyResource(backup_texture_.Get(), texture)'));
    expect(host, contains('CopyResource(texture, backup_texture_.Get())'));
  });

  test('Windows MPV 状态由事件唤醒与属性观察驱动', () {
    final bridge =
        File('windows/runner/native_player_bridge.cpp').readAsStringSync();

    expect(bridge, contains('mpv_set_wakeup_callback('));
    expect(bridge, contains('mpv_observe_property('));
    expect(bridge, contains('MPV_EVENT_PROPERTY_CHANGE'));
    expect(bridge, contains('condition_.wait(lock'));
    expect(bridge, contains('kMaxEventsPerBatch = 128'));
    expect(bridge, contains('event_batch_yield_count_'));
    expect(
      bridge,
      contains('native_hwnd_enabled_ ? "v" : "warn"'),
      reason: 'Texture 会话不需要为不可用的 NVIDIA 门禁持续接收 verbose 日志',
    );
    expect(
      bridge,
      isNot(contains('condition_.wait_for(lock')),
      reason: '原生工作线程不得恢复为固定 50ms 全属性扫描',
    );
    expect(
      bridge,
      isNot(contains('void NativePlayerBridge::SamplePlayerState()')),
      reason: '状态读取必须消费 libmpv 合并事件，而不是周期性读取全部属性',
    );
  });

  test('生产增强配置复用 MediaKit 的同一个 NativePlayer', () {
    final selection = File(
      'lib/src/services/player/player_backend_selection.dart',
    ).readAsStringSync();
    final backend = File(
      'lib/src/services/player/media_kit_player_backend.dart',
    ).readAsStringSync();

    expect(
      selection,
      contains('return PlayerBackendSelection.mediaKitLibmpvEnhanced;'),
    );
    expect(
      selection,
      contains("normalizedOverride == 'windows-native-mpv'"),
      reason: '自研 Texture 只能由显式 QA 环境变量进入',
    );
    expect(backend, contains('platform is NativePlayer'));
    expect(backend, contains('PlayerPropertyBatchBoundary'));
    expect(backend, contains('PlayerBackendTelemetryBoundary'));
    expect(
      File(
        'lib/src/services/player/player_service.dart',
      ).readAsStringSync(),
      allOf(
        contains('PlayerFilterTransactionBoundary'),
        contains('_restoreFilterProperties(previousValues)'),
        isNot(contains('NativePlayer(')),
      ),
      reason: '滤镜验证和回滚必须复用当前后端，不能创建第二个 NativePlayer',
    );
    expect(backend, contains('waitForInitialization: waitForInitialization'));
    expect(backend, contains('waitUntilFirstFrameRendered'));
    expect(backend, contains("'estimated-frame-number'"));
    expect(
      backend,
      isNot(contains('(platform as dynamic)')),
      reason: '高级属性必须走 media_kit 公开的类型化 NativePlayer 边界',
    );
    expect(
      File(
        'integration_test/media_kit_libmpv_facade_test.dart',
      ).existsSync(),
      isTrue,
      reason: '必须用真实 MediaKit Texture 会话证明同实例高级属性可用',
    );
  });

  test('NVIDIA automatic policy and fixed-frame visual gate stay explicit', () {
    final panel = File(
      'lib/src/pages/player/player_settings_panel.dart',
    ).readAsStringSync();
    final page = File(
      'lib/src/pages/player/player_page.dart',
    ).readAsStringSync();
    final autoPolicy = File(
      'lib/src/services/player/player_nvidia_video_auto_policy.dart',
    ).readAsStringSync();
    final backendSelection = File(
      'lib/src/services/player/player_backend_selection.dart',
    ).readAsStringSync();
    final nativeBridge = File(
      'windows/runner/native_player_bridge.cpp',
    ).readAsStringSync();
    final nativeBackend = File(
      'lib/src/services/player/windows_native_player_backend.dart',
    ).readAsStringSync();
    final abRunner = File('tool/run_nvidia_scaling_ab.ps1').readAsStringSync();
    final baselineGate = File(
      'integration_test/player_fixed_quality_baseline_test.dart',
    ).readAsStringSync();
    final roadmap = File('ROADMAP.md').readAsStringSync();

    // 手动开关已经获授权删除；自动策略仍必须保留驱动诊断、门禁与回滚。
    expect(panel, isNot(contains('NVIDIA RTX 视频超分')));
    expect(panel, isNot(contains('NVIDIA RTX Video HDR')));
    expect(page, contains('NVIDIA RTX 视频超分:'));
    expect(page, contains('NVIDIA RTX Video HDR:'));
    expect(page, contains('_applyAutomaticNvidiaVideoEnhancement'));
    expect(page, contains('NVIDIA 自动策略:'));
    expect(autoPolicy, contains('PlayerNvidiaVideoAutoPolicy'));
    expect(autoPolicy, contains('output.hdrSignalActive'));
    expect(nativeBridge, contains('video-params/w'));
    expect(nativeBridge, contains('video-params/h'));
    expect(nativeBackend, contains("'video-params/w'"));
    expect(nativeBackend, contains("'video-params/h'"));
    expect(
      backendSelection,
      contains(
        'rendererPreference != PlayerRendererPreference.mediaKit',
      ),
    );
    expect(
      backendSelection,
      contains('return PlayerBackendSelection.mediaKitLibmpvEnhanced;'),
    );
    expect(
      backendSelection,
      contains("normalizedOverride == 'windows-native-mpv'"),
      reason: '自研 MPV Texture 只允许显式 QA 覆盖，不能恢复为生产默认后端',
    );
    expect(
      backendSelection,
      contains("normalizedOverride == 'windows-native-hwnd'"),
    );
    expect(page, contains('_suspendCpuEnhancementsForNvidia'));
    expect(page, contains('_restoreCpuEnhancementsAfterNvidia'));
    expect(page, contains('NVIDIA 滤镜互斥处理:'));
    expect(baselineGate, contains("'playerBackend':"));
    expect(baselineGate, contains("'rendererPreference':"));

    // 肉眼 A/B 必须锁定同一媒体时间和最终窗口尺寸，不能退回 mpv 内部截图。
    expect(abRunner, contains('fixedFrameSecond = 12'));
    expect(abRunner, contains('PW_RENDERFULLCONTENT'));
    expect(abRunner, contains('sameWindowDimensions'));
    expect(abRunner, contains('allVisualCaptureGatesPassed'));

    // NVOFA 与 patched libmpv 只保留长期研究，不得重新成为自动发布门禁。
    expect(roadmap, contains('NVOFA 插帧降级为独立长期研究'));
    expect(roadmap, contains('非自动后续'));
  });

  test('Windows debug package gate rebuilds the production entrypoint', () {
    final verifier =
        File('tool/verify_windows_debug_package.ps1').readAsStringSync();
    final buildIndex = verifier.indexOf('flutter build windows --debug');
    final launchIndex = verifier.indexOf('Start-Process');

    // integration_test 会复用 Debug 目录；交付门禁必须先恢复正式 main.dart 再双击。
    expect(buildIndex, greaterThanOrEqualTo(0));
    expect(launchIndex, greaterThan(buildIndex));
    expect(verifier, contains('local_tag_player.exe'));
    expect(verifier, contains(r'$process.MainWindowHandle -ne 0'));
    expect(verifier, contains(r'$process.HasExited'));
    expect(verifier, contains('CloseMainWindow'));
  });

  test('motion interpolation runtime uses structured vf and local-only paths',
      () {
    final runnerBuild =
        File('windows/runner/CMakeLists.txt').readAsStringSync();
    final bridge =
        File('windows/runner/native_player_bridge.cpp').readAsStringSync();
    final bridgeHeader =
        File('windows/runner/native_player_bridge.h').readAsStringSync();
    final nvofaDriver = File(
      'windows/runner/nvidia_optical_flow_driver_probe.cpp',
    ).readAsStringSync();
    final nvofaExecute = File(
      'windows/nvidia_optical_flow_probe/nvofa_cuda_execute_probe.cpp',
    ).readAsStringSync();
    final d3d11AdapterSelector = File(
      'windows/runner/d3d11_adapter_selector.cpp',
    ).readAsStringSync();
    final nvofaScript =
        File('tool/run_nvofa_execute_probe.ps1').readAsStringSync();
    final nvofaInterpolation = File(
      'windows/nvidia_optical_flow_probe/nvofa_vapoursynth_plugin.cpp',
    ).readAsStringSync();
    final nvofaD3d11Warp = File(
      'windows/nvidia_optical_flow_probe/d3d11_midpoint_warper.cpp',
    ).readAsStringSync();
    final nvofaD3d11WarpProbe = File(
      'windows/nvidia_optical_flow_probe/'
      'd3d11_midpoint_warper_probe.cpp',
    ).readAsStringSync();
    final nvofaInterpolationScript = File(
      'tool/vapoursynth_nvofa_interpolation.vpy',
    ).readAsStringSync();
    final nvofaInterpolationProbe = File(
      'tool/run_nvofa_vapoursynth_interpolation_probe.ps1',
    ).readAsStringSync();
    final nvofaMotionAb = File(
      'tool/run_nvofa_motion_ab.ps1',
    ).readAsStringSync();
    final nvofaMotionStress = File(
      'tool/generate_nvofa_motion_stress_samples.ps1',
    ).readAsStringSync();
    final nativeBuild =
        File('windows/native_player/CMakeLists.txt').readAsStringSync();
    final runtime = File(
      'windows/runner/vapoursynth_motion_runtime.cpp',
    ).readAsStringSync();
    final boundary =
        File('lib/src/platform/platform_interfaces.dart').readAsStringSync();
    final flutterBackend = File(
      'lib/src/services/player/windows_native_player_backend.dart',
    ).readAsStringSync();

    // 本机原型不分发第三方运行时；只有两个绝对路径环境变量能开启探测。
    expect(runnerBuild, contains('vapoursynth_motion_runtime.cpp'));
    expect(
      runtime,
      contains('LOCAL_TAG_PLAYER_VAPOURSYNTH_RUNTIME_DIR'),
    );
    expect(
      runtime,
      contains('LOCAL_TAG_PLAYER_MOTION_INTERPOLATION_SCRIPT_PATH'),
    );
    expect(runtime, contains('runtime-and-script-paths-must-be-absolute'));
    expect(runtime, contains('LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR'));
    expect(runtime, contains('getVSScriptAPI'));

    // `vf` 必须按结构化节点保留现有压缩增强；禁止把 Windows 路径拼成滤镜字符串。
    expect(runtime, contains('MPV_FORMAT_NODE_ARRAY'));
    expect(runtime, contains('MPV_FORMAT_NODE_MAP'));
    expect(runtime, contains('mpv_get_property(player, "vf"'));
    expect(runtime, contains('mpv_set_property(player, "vf"'));
    expect(runtime, contains('ltp-motion-interpolation'));
    expect(runtime, isNot(contains('mpv_set_property_string(player, "vf"')));
    expect(
      bridge,
      contains('ReapplyAfterFilterGraphChange(player_)'),
    );
    expect(
      bridge,
      contains('windows-native-mpv-selected-d3d11-adapter'),
    );
    expect(bridge, contains('"d3d11-adapter"'));
    expect(
      bridge,
      contains('SelectNvidiaD3D11Adapter()'),
    );
    // 直接采样 D3D11VA 解码表面可能触发驱动问题，只允许显式 QA 请求，产品默认关闭。
    expect(
      bridge,
      contains('LOCAL_TAG_PLAYER_D3D11VA_ZERO_COPY_QA'),
    );
    expect(bridge, contains('IsQaEnvironmentEnabled('));
    expect(bridge, contains('"d3d11va-zero-copy", "yes"'));
    expect(bridgeHeader, contains('d3d11va_zero_copy_ = "no"'));
    expect(
      boundary,
      contains('abstract interface class PlayerMotionInterpolationBoundary'),
    );
    // 平台命令返回不等于滤镜已经生效；Flutter 边界必须等待原生状态确认。
    expect(flutterBackend, contains("'motion-interpolation'"));
    expect(
      flutterBackend,
      contains('const Duration(milliseconds: 50)'),
    );
    expect(
      flutterBackend,
      contains('PlayerMotionInterpolationStatus.requested'),
    );
    expect(
      flutterBackend,
      contains('PlayerMotionInterpolationStatus.active'),
    );

    // NVOFA 只从 System32 探测官方驱动入口，不把驱动存在冒充 FRUC 已安装。
    expect(nvofaDriver, contains('LOAD_LIBRARY_SEARCH_SYSTEM32'));
    expect(nvofaDriver, contains('NvOFGetMaxSupportedApiVersion'));
    expect(nvofaDriver, contains('NvOFAPICreateInstanceD3D11'));
    expect(
      bridge,
      contains('native-nvofa-driver-state'),
    );
    expect(
      bridge,
      contains('ProbeNvidiaOpticalFlowDriver()'),
    );

    // 真实硬件执行证据必须保持为显式、零分发的隔离目标，不能悄悄进入正式应用。
    expect(nativeBuild, contains('LTP_BUILD_NVOFA_EXECUTE_PROBE'));
    expect(
      nativeBuild,
      contains('ltp_nvofa_cuda_execute_probe EXCLUDE_FROM_ALL'),
    );
    expect(
      nativeBuild,
      isNot(contains('install(TARGETS ltp_nvofa_cuda_execute_probe')),
    );
    expect(nvofaExecute, contains('NvOFAPICreateInstanceCuda'));
    expect(nvofaExecute, contains('nvOFExecute'));
    expect(nvofaExecute, contains('validate-nonzero-flow'));
    expect(nvofaExecute, contains('cuDeviceGetLuid'));
    expect(nvofaExecute, contains('luid-match=passed'));
    expect(nvofaExecute, contains('LOAD_LIBRARY_SEARCH_SYSTEM32'));
    expect(
      d3d11AdapterSelector,
      contains('DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE'),
    );
    expect(
      d3d11AdapterSelector,
      contains('duplicate-nvidia-adapter-description'),
    );
    expect(
      d3d11AdapterSelector,
      contains('LOCAL_TAG_PLAYER_NVIDIA_ADAPTER_LUID'),
    );
    expect(
      nvofaScript,
      contains('edb50da3cf849840d680249aa6dbef248ebce2ca'),
    );
    expect(nvofaScript, contains('Get-FileHash'));

    // 生成中间帧的本机插件仍是显式 QA 目标：不进入默认构建、不安装、不分发。
    expect(nativeBuild, contains('LTP_BUILD_NVOFA_VAPOURSYNTH_PLUGIN'));
    expect(
      nativeBuild,
      contains('ltp_nvofa_vapoursynth_plugin MODULE EXCLUDE_FROM_ALL'),
    );
    expect(
      nativeBuild,
      isNot(contains('install(TARGETS ltp_nvofa_vapoursynth_plugin')),
    );
    expect(
      runtime,
      contains('LOCAL_TAG_PLAYER_NVOFA_VS_PLUGIN_PATH'),
    );
    expect(runtime, contains('const_cast<char*>("user-data")'));
    expect(nvofaInterpolation, contains('nvOFExecute'));
    expect(
      nvofaInterpolation,
      contains('input_, reference_, &flow->forward,'),
    );
    expect(
      nvofaInterpolation,
      contains('reference_, input_, &flow->backward,'),
    );
    expect(nvofaInterpolation, contains('cuDeviceGetLuid'));
    expect(
      nvofaInterpolation,
      contains('match-cuda-device-by-d3d11-luid'),
    );
    expect(nvofaInterpolation, contains('adapter_luid:data'));
    expect(nvofaInterpolation, contains('LTPNVOFAInterpolated'));
    expect(nvofaInterpolation, contains('LTPNVOFAAdapterMatched'));
    expect(nvofaInterpolation, contains('LTPNVOFAD3D11Warp'));
    expect(
      nvofaInterpolation,
      contains('LTPNVOFAConsistencyProtected'),
    );
    expect(nvofaInterpolation, contains('LTPNVOFASceneCut'));
    expect(nvofaInterpolation, contains('enableOutputCost = NV_OF_TRUE'));
    expect(nvofaInterpolation, contains('NV_OF_BUFFER_FORMAT_UINT8'));
    expect(
      nvofaInterpolation,
      isNot(contains('concurrency::parallel_for')),
    );
    expect(nvofaD3d11Warp, contains('D3DCompile'));
    expect(nvofaD3d11Warp, contains('"cs_5_0"'));
    expect(nvofaD3d11Warp, contains('context_->Dispatch'));
    expect(nvofaD3d11Warp, contains('DXGI_FORMAT_R16G16_SINT'));
    expect(nvofaD3d11Warp, contains('DXGI_FORMAT_R8_UINT'));
    expect(nvofaD3d11Warp, contains('DXGI_FORMAT_R32_FLOAT'));
    expect(
      nvofaD3d11Warp,
      contains('DXGI_FORMAT_R32G32B32A32_FLOAT'),
    );
    expect(nvofaD3d11Warp, contains('FlowConfidence'));
    expect(nvofaD3d11Warp, contains('ResolveForward'));
    expect(nvofaD3d11Warp, contains('ResolveBackward'));
    expect(nvofaD3d11Warp, contains('WarpCandidate'));
    expect(nvofaD3d11Warp, contains('kHoleFillShader'));
    expect(
      nvofaD3d11WarpProbe,
      contains('d3d11-warp-occlusion=passed'),
    );
    expect(nvofaD3d11WarpProbe, contains('vector-infill='));
    expect(nvofaD3d11WarpProbe, contains('image-hole-fill='));
    expect(
      nativeBuild,
      contains('ltp_d3d11_midpoint_warper_probe EXCLUDE_FROM_ALL'),
    );
    expect(
      nativeBuild,
      isNot(contains('install(TARGETS ltp_d3d11_midpoint_warper_probe')),
    );
    expect(
      nvofaInterpolationScript,
      contains('plugin_path, adapter_luid = user_data.rsplit("|", 1)'),
    );
    expect(nvofaInterpolationScript, contains('video_out.set_output()'));
    expect(
      nvofaInterpolationProbe,
      contains('expect-active-performance'),
    );
    expect(nvofaInterpolationProbe, contains('d3d11-warp=passed'));
    expect(
      nvofaInterpolationProbe,
      contains('consistency-protected=passed'),
    );
    expect(
      nvofaInterpolationProbe,
      contains('image-hole-fill=201'),
    );
    expect(nvofaMotionAb, contains('plugin-sha256.txt'));
    expect(nvofaMotionAb, contains('pluginSha256 = \$pluginHash'));
    expect(nvofaMotionAb, contains('CaseManifest'));
    expect(nvofaMotionAb, contains('allRuntimeGatesPassed'));
    expect(nvofaMotionAb, contains('productEnablement'));
    expect(nvofaMotionAb, contains('D3D11VaZeroCopyQa'));
    expect(nvofaMotionAb, contains('d3d11vaZeroCopyGatePassed'));
    // 连续压力样本必须覆盖五类已知风险，且只生成到本机 QA 目录。
    expect(nvofaMotionStress, contains('"fast-pan"'));
    expect(nvofaMotionStress, contains('"fine-fence"'));
    expect(nvofaMotionStress, contains('"subtitles"'));
    expect(nvofaMotionStress, contains('"motion-blur"'));
    expect(nvofaMotionStress, contains('"scene-cut"'));
    expect(nvofaMotionStress, contains('.local/qa/nvofa-motion-stress'));
  });

  test('desktop startup centers size-only persisted window layouts', () {
    final source = File(
      'lib/src/services/window/desktop_window_state_service.dart',
    ).readAsStringSync();

    // 窗口快照没有坐标时不能要求插件按缺失的位置恢复，否则独立 EXE 可能保持隐藏。
    expect(source, contains('center: true'));
    expect(source, isNot(contains('center: layout == null')));
  });

  test('player stress fullscreen uses the production state machine directly',
      () {
    final playerSource =
        File('lib/src/pages/player/player_page.dart').readAsStringSync();
    final stressSource = File(
      'integration_test/player_real_library_stress_test.dart',
    ).readAsStringSync();

    // 控制条可见性属于动画状态，长跑门禁必须稳定覆盖真正的窗口与纹理切换路径。
    expect(
      playerSource,
      contains('toggleWindowFullscreenForStressTest'),
    );
    expect(
      stressSource,
      contains('.toggleWindowFullscreenForStressTest()'),
    );
    final roundTripStart =
        stressSource.indexOf('Future<void> _toggleFullscreenRoundTrip');
    final helperStart = stressSource
        .indexOf('Future<void> _toggleFullscreenThroughPlayerState');
    expect(roundTripStart, greaterThanOrEqualTo(0));
    expect(helperStart, greaterThan(roundTripStart));
    expect(
      stressSource.substring(roundTripStart, helperStart),
      isNot(contains("find.byKey(const ValueKey('player.fullscreen.toggle'))")),
    );
  });

  test('双后端稳定性矩阵覆盖四类场景并保留跨平台原生门禁', () {
    final integrationSource = File(
      'integration_test/player_backend_stability_matrix_test.dart',
    ).readAsStringSync();
    final runnerSource = File(
      'tool/run_player_backend_stability_matrix.ps1',
    ).readAsStringSync();

    expect(integrationSource, contains('_runFullscreenScenario'));
    expect(integrationSource, contains('_runDpiScenario'));
    expect(integrationSource, contains('_runRapidSwitchScenario'));
    expect(integrationSource, contains('_runLongPlayScenario'));
    expect(
      integrationSource,
      contains('jumpToQueueIndexForStabilityTest'),
      reason: '快速切换必须走 PlayerPage 的 latest-request 正式链路',
    );
    expect(runnerSource, contains("@('mediaKit', 'mpv')"));
    expect(
      runnerSource,
      contains('pending-physical-cross-dpi'),
      reason: '模拟 metrics 不能冒充真实跨显示器 DPI 已通过',
    );
    expect(
      runnerSource,
      contains("mpv = 'blocked-native-backend-not-implemented'"),
      reason: 'macOS/Linux 未实现各自原生后端前必须保持 MPV 门禁',
    );
  });
}
