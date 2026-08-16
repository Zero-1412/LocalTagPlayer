import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:local_tag_player/src/models/platform_models.dart';
import 'package:local_tag_player/src/services/library/library_query_compiler.dart';

void main() {
  const compiler = LibraryQueryCompiler();

  test('small libraries stay in memory even when FTS5 exists', () {
    final plan = compiler.compile(
      const FilterQuery(keyword: 'nature'),
      const LibraryQueryProfile(videoCount: 1999, fts5Available: true),
    );
    expect(plan.mode, LibraryQueryExecutionMode.inMemory);
    expect(plan.hasSqlCandidate, isFalse);
  });

  test(
      'large libraries compile safe FTS5 candidates and require Dart verification',
      () {
    final plan = compiler.compile(
      const FilterQuery(keyword: 'nature sunset'),
      const LibraryQueryProfile(videoCount: 2000, fts5Available: true),
    );
    expect(plan.mode, LibraryQueryExecutionMode.sqliteFts5);
    expect(plan.whereSql, contains('library_search_fts MATCH ?'));
    expect(plan.whereArgs.single, '"nature" AND "sunset"');
    expect(plan.requiresDartVerification, isTrue);
  });

  test('short tokens and unavailable FTS5 never change search semantics', () {
    final shortToken = compiler.compile(
      const FilterQuery(keyword: '猫'),
      const LibraryQueryProfile(videoCount: 5000, fts5Available: true),
    );
    final unavailable = compiler.compile(
      const FilterQuery(keyword: 'nature'),
      const LibraryQueryProfile(videoCount: 5000, fts5Available: false),
    );
    expect(shortToken.hasSqlCandidate, isFalse);
    expect(unavailable.hasSqlCandidate, isFalse);
  });

  test('FTS candidate text includes stable tag ids before Dart verification',
      () {
    final source = File(
      'lib/src/services/library/library_query_compiler.dart',
    ).readAsStringSync();
    expect(source, contains("COALESCE(t.id, '')"));
    expect(source, contains('requiresDartVerification: true'));
  });
}
