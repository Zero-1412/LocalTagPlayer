import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_file_command_executor.dart';
import 'package:local_tag_player/src/models/video_item.dart';
import 'package:path/path.dart' as p;

// ignore_for_file: slash_for_doc_comments

/** 创建具有稳定身份的文件命令测试视频。 */
VideoItem _item(String id, String path) => VideoItem(
      videoId: id,
      path: path,
      title: id,
      folder: p.dirname(path),
      tags: const <String>{},
      addedAt: DateTime.utc(2026, 7, 29),
    );

void main() {
  const executor = LibraryFileCommandExecutor();

  test('定位命令吞掉平台异常且不泄漏底层错误', () async {
    final item = _item('reveal', p.join('C:', 'media', 'reveal.mp4'));
    expect(
      await executor.reveal(
        RevealVideoLocationCommand(item),
        revealInFileManager: (_) => Future<void>.error(
          StateError('C:\\private\\secret'),
        ),
      ),
      isFalse,
    );
  });

  test('改名保留扩展名并在物理成功后提交同一 stable videoId', () async {
    final item = _item('rename', p.join('C:', 'media', 'old.mp4'));
    final calls = <String>[];
    String? committedPath;

    await executor.rename(
      RenameVideoFileCommand(item: item, newBaseName: 'new'),
      normalizePath: p.normalize,
      parentPath: p.dirname,
      joinPath: p.joinAll,
      fileExists: (_) async => false,
      renameFile: (oldPath, newPath) async {
        calls.add('file:$oldPath->$newPath');
        return newPath;
      },
      commitRenamedPath: (target, newPath) async {
        calls.add('repository:${target.videoId}');
        committedPath = newPath;
      },
    );

    expect(calls.first, startsWith('file:'));
    expect(calls.last, 'repository:rename');
    expect(p.basename(committedPath!), 'new.mp4');
    expect(item.videoId, 'rename');
  });

  test('同名目标存在时不执行物理改名或 Repository 提交', () async {
    final item = _item('conflict', p.join('C:', 'media', 'old.mp4'));
    var renameCalls = 0;
    var commitCalls = 0;

    await expectLater(
      executor.rename(
        RenameVideoFileCommand(item: item, newBaseName: 'occupied'),
        normalizePath: p.normalize,
        parentPath: p.dirname,
        joinPath: p.joinAll,
        fileExists: (_) async => true,
        renameFile: (_, __) async {
          renameCalls += 1;
          return '';
        },
        commitRenamedPath: (_, __) async {
          commitCalls += 1;
        },
      ),
      throwsStateError,
    );
    expect(renameCalls, 0);
    expect(commitCalls, 0);
  });

  test('Repository 改名失败时按原路径补偿物理文件', () async {
    final item = _item('rollback', p.join('C:', 'media', 'old.mp4'));
    final calls = <String>[];
    final commitError = StateError('commit failed');

    await expectLater(
      executor.rename(
        RenameVideoFileCommand(item: item, newBaseName: 'new'),
        normalizePath: p.normalize,
        parentPath: p.dirname,
        joinPath: p.joinAll,
        fileExists: (_) async => false,
        renameFile: (oldPath, newPath) async {
          calls.add('$oldPath->$newPath');
          return newPath;
        },
        commitRenamedPath: (_, __) => Future<void>.error(commitError),
      ),
      throwsA(same(commitError)),
    );
    expect(calls, hasLength(2));
    expect(
      calls.last,
      '${p.join('C:', 'media', 'new.mp4')}->${item.path}',
    );
  });

  test('改名补偿也失败时返回固定重新扫描错误', () async {
    final item = _item('rollback-failed', p.join('C:', 'media', 'old.mp4'));
    var renameCalls = 0;

    await expectLater(
      executor.rename(
        RenameVideoFileCommand(item: item, newBaseName: 'new'),
        normalizePath: p.normalize,
        parentPath: p.dirname,
        joinPath: p.joinAll,
        fileExists: (_) async => false,
        renameFile: (_, newPath) async {
          renameCalls += 1;
          if (renameCalls == 2) {
            throw StateError('rollback failed');
          }
          return newPath;
        },
        commitRenamedPath: (_, __) =>
            Future<void>.error(StateError('commit failed')),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('重新扫描'),
        ),
      ),
    );
  });

  test('删除保持回收站到 Repository 顺序且忽略缓存清理失败', () async {
    final item = _item('delete', p.join('C:', 'media', 'delete.mp4'));
    final calls = <String>[];

    await executor.delete(
      DeleteVideoCommand(item: item, moveLocalFileToTrash: true),
      moveFileToTrash: (_) async {
        calls.add('trash');
      },
      deleteRecord: (_) async {
        calls.add('repository');
      },
      deleteThumbnail: (_) async {
        calls.add('cache');
        throw StateError('cache failed');
      },
    );

    expect(calls, <String>['trash', 'repository', 'cache']);
  });

  test('批量删除只发布成功 stable ID 并保留失败对象', () async {
    final first = _item('first', p.join('C:', 'media', 'first.mp4'));
    final second = _item('second', p.join('C:', 'media', 'second.mp4'));

    final result = await executor.deleteAll(
      <DeleteVideoCommand>[
        DeleteVideoCommand(item: first, moveLocalFileToTrash: false),
        DeleteVideoCommand(item: second, moveLocalFileToTrash: false),
      ],
      moveFileToTrash: (_) async {},
      deleteRecord: (path) async {
        if (path == second.path) {
          throw StateError('failed');
        }
      },
    );

    expect(result.deletedVideoIds, <String>{'first'});
    expect(result.failedItems, <VideoItem>[second]);
    expect(
      () => result.deletedVideoIds.add('other'),
      throwsUnsupportedError,
    );
  });
}
