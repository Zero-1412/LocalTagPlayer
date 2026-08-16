import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/domain/library_query_snapshot.dart';
import 'package:local_tag_player/src/features/player/application/player_session_controller.dart';
import 'package:local_tag_player/src/features/update/domain/app_release.dart';
import 'package:local_tag_player/src/models/platform_models.dart';
import 'package:local_tag_player/src/repositories/repository_interfaces.dart';
import 'package:local_tag_player/src/services/library/library_store.dart';
import 'package:local_tag_player/src/services/tags/tag_query_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/legacy_library_fixture.dart';

// ignore_for_file: slash_for_doc_comments

List<File> _dartFiles(String root) {
  return Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);
}

String _normalized(File file) => file.path.replaceAll(r'\', '/');

void main() {
  test('Phase 0 artifacts and metric entrypoint exist', () {
    expect(
      File('docs/architecture/ADR_002_PHASE_0_ARCHITECTURE_FOUNDATION.md')
          .existsSync(),
      isTrue,
    );
    expect(File('tool/architecture_metrics.ps1').existsSync(), isTrue);
    expect(
      File('test/support/legacy_library_fixture.dart').existsSync(),
      isTrue,
    );
    expect(
      File('test/architecture_phase0_contract_test.dart').existsSync(),
      isTrue,
    );
  });

  test('domain files do not depend on UI, persistence or platform code', () {
    final forbidden = <String>[
      'package:flutter/',
      'dart:io',
      'sqflite',
      '/repositories/',
      '/services/',
      '/platform/',
      '/pages/',
      '/widgets/',
      '/composition/',
    ];
    final offenders = <String>[];
    for (final file in _dartFiles('lib/src/features')) {
      if (!_normalized(file).contains('/domain/')) {
        continue;
      }
      final source = file.readAsStringSync();
      for (final token in forbidden) {
        if (source.contains(token)) {
          offenders.add('${_normalized(file)} -> $token');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('application owners do not import UI, routes or concrete adapters', () {
    final forbidden = <String>[
      'package:flutter/material.dart',
      'package:flutter/widgets.dart',
      'dart:io',
      'sqflite',
      '/platform/',
      '/composition/',
      '/pages/',
      '/widgets/',
    ];
    final offenders = <String>[];
    for (final file in _dartFiles('lib/src/features')) {
      if (!_normalized(file).contains('/application/')) {
        continue;
      }
      final source = file.readAsStringSync();
      final imports = RegExp(
        r'''(?:import|export)\s+['"][^'"]+['"]''',
      ).allMatches(source).map((match) => match.group(0)!).toList();
      for (final token in forbidden) {
        if (imports.any((import) => import.contains(token))) {
          offenders.add('${_normalized(file)} -> $token');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('cross-feature presentation imports remain forbidden', () {
    final offenders = <String>[];
    for (final file in _dartFiles('lib/src/features')) {
      final path = _normalized(file);
      final match = RegExp(r'/features/([^/]+)/presentation/').firstMatch(path);
      if (match == null) {
        continue;
      }
      final feature = match.group(1);
      final imports = RegExp(
        r'''(?:import|export) ['"][^'"]*features/([^/]+)/presentation/''',
      ).allMatches(file.readAsStringSync());
      for (final import in imports) {
        if (import.group(1) != feature) {
          offenders.add('$path -> ${import.group(1)}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('stable queue and query owners remain independent of concrete Store',
      () {
    final session = File(
      'lib/src/features/player/application/player_session_controller.dart',
    ).readAsStringSync();
    final queue = File(
      'lib/src/features/library/application/library_playback_queue_controller.dart',
    ).readAsStringSync();
    expect(session, contains('acceptedSourceVideoIds'));
    expect(session, isNot(contains('LibraryStore')));
    expect(session, isNot(contains('TagQueryService')));
    expect(queue, contains('LibraryQueueSnapshot.fromResult(result)'));
    expect(queue, isNot(contains('LibraryApplicationFacade')));
    expect(queue, isNot(contains('TagQueryService')));
  });

  test('legacy fixture stays path-keyed and contains only synthetic data', () {
    final fixture =
        File('test/support/legacy_library_fixture.dart').readAsStringSync();
    expect(fixture, contains('path TEXT PRIMARY KEY'));
    expect(fixture, contains('PRIMARY KEY (video_path, tag_id, source)'));
    expect(fixture, isNot(contains('video_id TEXT')));
    expect(fixture, contains('C:/fixture/'));
    expect(fixture, isNot(contains('D:/video')));
    expect(fixture, isNot(contains('E:/')));
  });

  test('legacy fixture creates a reusable pre-migration SQLite database',
      () async {
    if (Platform.isWindows) {
      DynamicLibrary.open(
        File('windows/tools/sqlite/sqlite3.dll').absolute.path,
      );
    }
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp(
      'ltp_legacy_fixture_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = await databaseFactoryFfi.openDatabase(
      '${directory.path}${Platform.pathSeparator}legacy.db',
    );
    addTearDown(database.close);

    await LegacyLibraryFixture.createSchema(database);
    await LegacyLibraryFixture.seed(database);

    final videoColumns = await database.rawQuery('PRAGMA table_info(videos)');
    final tagColumns = await database.rawQuery('PRAGMA table_info(video_tags)');
    expect(videoColumns.map((row) => row['name']), isNot(contains('video_id')));
    expect(tagColumns.map((row) => row['name']), isNot(contains('video_id')));
    expect(
      (await database.query('videos')).single['path'],
      LegacyLibraryFixture.samplePath,
    );
    expect(
      (await database.query('video_tags')).single['tag_id'],
      LegacyLibraryFixture.sampleTagId,
    );
  });

  test('Phase 0 reference symbols remain available for migration planning', () {
    expect(LegacyLibraryFixture.samplePath, startsWith('C:/fixture/'));
    expect(LibraryStore, isNotNull);
    expect(LibraryResultEpoch, isNotNull);
    expect(FilterQuery, isNotNull);
    expect(TagQueryService, isNotNull);
    expect(LibraryQueryRepository, isNotNull);
    expect(PlayerSessionController, isNotNull);
    expect(AppRelease, isNotNull);
  });
}
