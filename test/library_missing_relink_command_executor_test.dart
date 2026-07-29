import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_missing_relink_command_executor.dart';
import 'package:local_tag_player/src/models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

VideoItem _missingItem() => VideoItem(
      videoId: 'stable-missing-id',
      path: 'C:\\old\\video.mp4',
      title: 'video',
      folder: 'C:\\old',
      tags: <String>{'manual'},
      addedAt: DateTime.utc(2026, 7, 29),
      mediaFingerprint: 'fingerprint',
      isFavorite: true,
      isMissing: true,
      playbackPosition: const Duration(seconds: 37),
    );

void main() {
  test('成功命令携带同一稳定身份并委托 Repository 最终校验', () async {
    final item = _missingItem();
    final executor = LibraryMissingRelinkCommandExecutor();
    final result = await executor.execute(
      RelinkMissingVideoCommand(
        item: item,
        newPath: 'E:\\new\\video.mp4',
      ),
      commit: (target, newPath) async {
        expect(target.videoId, 'stable-missing-id');
        expect(newPath, 'E:\\new\\video.mp4');
      },
    );

    expect(result.changed, isTrue);
    expect(result.videoId, 'stable-missing-id');
    expect(executor.runningVideoIds, isEmpty);
  });

  test('picker 返回后身份快照已变化会拒绝过期命令', () async {
    final item = _missingItem();
    final command = RelinkMissingVideoCommand(
      item: item,
      newPath: 'E:\\new\\video.mp4',
    );
    item.path = 'D:\\another\\video.mp4';
    var committed = false;

    final result = await LibraryMissingRelinkCommandExecutor().execute(
      command,
      commit: (_, __) async => committed = true,
    );

    expect(result.changed, isFalse);
    expect(result.error, isA<StateError>());
    expect(committed, isFalse);
  });

  test('同一 stable videoId 的重复提交被拒绝且不覆盖首个操作', () async {
    final item = _missingItem();
    final executor = LibraryMissingRelinkCommandExecutor();
    final release = Completer<void>();
    final first = executor.execute(
      RelinkMissingVideoCommand(item: item, newPath: 'E:\\first.mp4'),
      commit: (_, __) => release.future,
    );
    expect(executor.runningVideoIds, <String>{'stable-missing-id'});

    final duplicate = await executor.execute(
      RelinkMissingVideoCommand(item: item, newPath: 'E:\\second.mp4'),
      commit: (_, __) async => fail('重复命令不应进入 Repository'),
    );
    expect(duplicate.changed, isFalse);
    expect(duplicate.error, isA<StateError>());

    release.complete();
    expect((await first).changed, isTrue);
    expect(executor.runningVideoIds, isEmpty);
  });

  test('Repository 错误转换为失败结果并清理忙碌身份', () async {
    final item = _missingItem();
    final executor = LibraryMissingRelinkCommandExecutor();
    final result = await executor.execute(
      RelinkMissingVideoCommand(item: item, newPath: 'E:\\new.mp4'),
      commit: (_, __) => Future<void>.error(StateError('fingerprint mismatch')),
    );

    expect(result.changed, isFalse);
    expect(result.error, isA<StateError>());
    expect(executor.runningVideoIds, isEmpty);
  });
}
