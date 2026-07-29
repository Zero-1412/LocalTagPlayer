import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_revision_tracker.dart';

void main() {
  test('普通内容提交只推进数据代次', () {
    final tracker = LibraryRevisionTracker();

    final snapshot = tracker.record(LibraryDataChangeKind.content);

    expect(snapshot.dataRevision, 1);
    expect(snapshot.tagDefinitionRevision, 0);
  });

  test('标签定义提交同时推进结果与标签代次', () {
    final tracker = LibraryRevisionTracker();
    tracker.record(LibraryDataChangeKind.content);

    final tagSnapshot = tracker.record(LibraryDataChangeKind.tagDefinitions);
    final nextContent = tracker.record(LibraryDataChangeKind.content);

    expect(tagSnapshot.dataRevision, 2);
    expect(tagSnapshot.tagDefinitionRevision, 1);
    expect(nextContent.dataRevision, 3);
    expect(nextContent.tagDefinitionRevision, 1);
  });

  test('修订快照不会随 tracker 后续提交原地变化', () {
    final tracker = LibraryRevisionTracker();
    final before = tracker.snapshot;

    tracker.record(LibraryDataChangeKind.tagDefinitions);

    expect(before.dataRevision, 0);
    expect(before.tagDefinitionRevision, 0);
    expect(tracker.snapshot.dataRevision, 1);
    expect(tracker.snapshot.tagDefinitionRevision, 1);
  });
}
