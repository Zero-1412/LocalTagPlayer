import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Phase 3 keeps one shared context and separate repository ports', () {
    final context = File(
      'lib/src/services/library/library_repository_context.dart',
    ).readAsStringSync();
    final access = File(
      'lib/src/services/library/library_store_access.dart',
    ).readAsStringSync();
    final ports = File(
      'lib/src/services/library/library_repository_ports.dart',
    ).readAsStringSync();
    final bootstrap = File(
      'lib/src/composition/local_tag_player_bootstrap.dart',
    ).readAsStringSync();

    expect(context, contains('final Database database;'));
    expect(context, contains('Future<T> transaction<T>'));
    expect(context, contains('LibraryTagPersistence('));
    expect(access, contains('LibraryRepositoryContext get repositoryContext'));
    expect(ports, contains('class LibraryStoreQueryRepository'));
    expect(ports, contains('class LibraryStoreCommandRepository'));
    expect(bootstrap, contains('LibraryStoreQueryRepository(repository)'));
    expect(bootstrap, contains('LibraryStoreCommandRepository(repository)'));
  });
}
