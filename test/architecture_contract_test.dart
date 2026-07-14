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
    DynamicLibrary.open(
      File('windows/tools/sqlite/sqlite3.dll').absolute.path,
    );
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
    expect(dependencies.ffmpegBackend, isA<DesktopFFmpegBackend>());
    expect(dependencies.paths, isA<AppPaths>());
  });
}
