import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_manual_tag_command_executor.dart';
import 'package:local_tag_player/src/models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/** 创建同时包含一级和两个父级二级标签的视频。 */
VideoItem _item() => VideoItem(
      videoId: 'manual-tag-command',
      path: 'C:\\media\\parent\\child\\video.mp4',
      title: 'video',
      folder: 'C:\\media\\parent\\child',
      tags: <String>{'folder-old', 'manual-old'},
      childTags: <String, Set<String>>{
        'parent': <String>{'folder-child-old', 'manual-child-old'},
        'other': <String>{'other-child'},
      },
      addedAt: DateTime.utc(2026, 7, 29),
    );

void main() {
  const executor = LibraryManualTagCommandExecutor();

  test('一级 manual 替换规范化去重并强制保留 folder 锁定项', () async {
    final item = _item();
    String? committedParent = 'unexpected';

    await executor.replace(
      ReplaceVideoManualTagsCommand(
        item: item,
        selectedTags: const <String>[' Manual ', 'manual', ''],
        lockedFolderTags: const <String>['Folder'],
      ),
      commit: (target, parentTag, manualTags) async {
        committedParent = parentTag;
        expect(target.videoId, 'manual-tag-command');
        expect(target.tags, <String>{'Folder', 'Manual'});
        expect(manualTags, <String>{'Manual'});
      },
    );

    expect(committedParent, isNull);
    expect(item.childTags['other'], <String>{'other-child'});
  });

  test('二级 manual 替换只修改指定一级父级', () async {
    final item = _item();

    await executor.replace(
      ReplaceVideoManualTagsCommand(
        item: item,
        parentTag: 'parent',
        selectedTags: const <String>['manual-new'],
        lockedFolderTags: const <String>['folder-child'],
      ),
      commit: (target, parentTag, manualTags) async {
        expect(parentTag, 'parent');
        expect(manualTags, <String>{'manual-new'});
      },
    );

    expect(
      item.childTags['parent'],
      <String>{'folder-child', 'manual-new'},
    );
    expect(item.childTags['other'], <String>{'other-child'});
    expect(item.tags, <String>{'folder-old', 'manual-old'});
  });

  test('Repository 失败恢复完整一级和二级模型快照', () async {
    final item = _item();
    final previousTags = <String>{...item.tags};
    final previousChildren = <String, Set<String>>{
      for (final entry in item.childTags.entries)
        entry.key: <String>{...entry.value},
    };

    await expectLater(
      executor.replace(
        ReplaceVideoManualTagsCommand(
          item: item,
          parentTag: 'parent',
          selectedTags: const <String>['new'],
          lockedFolderTags: const <String>['folder'],
        ),
        commit: (_, __, ___) => Future<void>.error(StateError('commit failed')),
      ),
      throwsStateError,
    );

    expect(item.tags, previousTags);
    expect(item.childTags, previousChildren);
  });

  test('command 输入在创建后不可被调用方修改', () {
    final selected = <String>['manual'];
    final command = ReplaceVideoManualTagsCommand(
      item: _item(),
      selectedTags: selected,
      lockedFolderTags: const <String>['folder'],
    );
    selected.add('late');

    expect(command.selectedTags, <String>['manual']);
    expect(() => command.selectedTags.add('other'), throwsUnsupportedError);
  });

  test('同名 folder 与 manual 仍将 manual 集合明确交给保存层', () async {
    final item = _item();

    await executor.replace(
      ReplaceVideoManualTagsCommand(
        item: item,
        selectedTags: const <String>['Folder'],
        lockedFolderTags: const <String>['Folder'],
      ),
      commit: (target, parentTag, manualTags) async {
        expect(parentTag, isNull);
        expect(target.tags, <String>{'Folder'});
        expect(manualTags, <String>{'Folder'});
      },
    );
  });
}
