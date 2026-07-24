import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';
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
      libraryRepository: library,
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
  });

  test('LibraryPage depends on page services instead of the composition root',
      () {
    final source = File(
      'lib/src/pages/library/library_page.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('local_tag_player_dependencies.dart')));
    expect(source, isNot(contains('LocalTagPlayerDependencies')));
    expect(source, contains('LibraryPageApplicationService'));
    expect(source, contains('PlayerBackendFactory'));
    expect(source, contains('MediaProbeBackendFactory'));
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
}
