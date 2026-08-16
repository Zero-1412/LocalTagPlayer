import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/player/application/player_session_controller.dart';
import 'package:local_tag_player/src/models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放队列的有限穷举门禁。
 *
 * “所有可能组合”在无界操作序列上不可计算；本测试把生产命令类型、边界参数和
 * 三步组合固定成可重复 manifest，并在每一步检查 stable identity、索引和来源队列
 * 不变量。页面/后端的异步竞态仍由 PlayerPage 稳定性矩阵另行覆盖。
 */
void main() {
  test('三步枚举所有队列命令类型并保持会话不变量', () {
    final actions = <void Function(PlayerSessionController)>[
      (playback) => playback.select(0),
      (playback) => playback.select(3),
      (playback) => playback.jumpTo(1),
      (playback) => playback.moveSelection(-1),
      (playback) => playback.moveSelection(1),
      (playback) => playback.selectQueueIndex(99),
      (playback) => playback.removeItemAt(0),
      (playback) => playback.removeItemAt(3),
      (playback) => playback.toggleChildTag(
            'A',
            preferredVideoId: 'video-a',
          ),
      (playback) => playback.toggleChildTag(
            'B',
            preferredVideoId: 'video-b',
          ),
      (playback) => playback.setPlaylistForChildTag(
            'missing',
            preferredVideoId: 'video-c',
          ),
      (playback) => playback.setPlaylistForChildTag(
            null,
            preferredVideoId: 'video-d',
          ),
      (playback) => playback.sourceItemForVideoId('video-b'),
      (playback) => playback.playlistForChildTag('A'),
      (playback) => playback.locatePlayingIndex(),
    ];

    var cases = 0;
    for (final first in actions) {
      for (final second in actions) {
        for (final third in actions) {
          final playback = _createPlayback();
          for (final action in <void Function(PlayerSessionController)>[
            first,
            second,
            third,
          ]) {
            expect(() => action(playback), returnsNormally);
            _expectInvariants(playback);
          }
          cases++;
        }
      }
    }

    expect(cases, actions.length * actions.length * actions.length);
  });

  test('索引、构造和删除边界保持安全且不漂移 stable identity', () {
    final invalid = _createPlayback();
    for (final index in <int>[-2, -1, 4, 99]) {
      expect(invalid.select(index), isFalse);
      expect(invalid.jumpTo(index), isFalse);
      expect(invalid.removeItemAt(index), isFalse);
      expect(invalid.selectQueueIndex(index), index.clamp(0, 3));
      _expectInvariants(invalid);
    }

    final beforeCurrent = _createPlayback()..jumpTo(2);
    expect(beforeCurrent.removeItemAt(0), isFalse);
    expect(beforeCurrent.currentItem.videoId, 'video-c');
    expect(beforeCurrent.playingIndex, 1);
    _expectInvariants(beforeCurrent);

    final selectedOnly = _createPlayback()..select(3);
    expect(selectedOnly.removeItemAt(3), isFalse);
    expect(selectedOnly.currentItem.videoId, 'video-a');
    expect(selectedOnly.selectedIndex, selectedOnly.playingIndex);
    _expectInvariants(selectedOnly);

    final currentMiddle = _createPlayback()..jumpTo(1);
    expect(currentMiddle.removeItemAt(1), isTrue);
    expect(currentMiddle.currentItem.videoId, 'video-c');
    _expectInvariants(currentMiddle);

    final currentLast = _createPlayback()..jumpTo(3);
    expect(currentLast.removeItemAt(3), isTrue);
    expect(currentLast.currentItem.videoId, 'video-c');
    _expectInvariants(currentLast);

    final removeAll = _createPlayback();
    while (removeAll.queue.isNotEmpty) {
      removeAll.removeItemAt(0);
      if (removeAll.queue.isNotEmpty) {
        _expectInvariants(removeAll);
      }
    }
    expect(removeAll.queue, isEmpty);
    expect(removeAll.sourcePlaylist, isEmpty);

    expect(
      () => PlayerSessionController(
        sourcePlaylist: const <VideoItem>[],
        acceptedSourceVideoIds: const <String>[],
        activeParentTag: null,
        initialVideoId: 'missing',
        matchesChildTag: (_, __, ___) => true,
      ),
      throwsArgumentError,
    );
    final duplicate = _item('video-a', 'duplicate.mp4');
    expect(
      () => PlayerSessionController(
        sourcePlaylist: <VideoItem>[duplicate, duplicate],
        acceptedSourceVideoIds: const <String>['video-a', 'video-a'],
        activeParentTag: null,
        initialVideoId: 'video-a',
        matchesChildTag: (_, __, ___) => true,
      ),
      throwsArgumentError,
    );
    expect(
      () => PlayerSessionController(
        sourcePlaylist: <VideoItem>[_item('video-a', 'a.mp4')],
        acceptedSourceVideoIds: const <String>['other'],
        activeParentTag: null,
        initialVideoId: 'video-a',
        matchesChildTag: (_, __, ___) => true,
      ),
      throwsArgumentError,
    );
  });
}

PlayerSessionController _createPlayback() {
  final items = <VideoItem>[
    _item('video-a', 'a.mp4', childTags: const <String>{'A'}),
    _item('video-b', 'b.mp4', childTags: const <String>{'A', 'B'}),
    _item('video-c', 'c.mp4', childTags: const <String>{'B'}),
    _item('video-d', 'd.mp4', childTags: const <String>{'C'}),
  ];
  return PlayerSessionController(
    sourcePlaylist: items,
    acceptedSourceVideoIds: items.map((item) => item.videoId),
    activeParentTag: 'Series',
    initialVideoId: 'video-a',
    matchesChildTag: (item, parent, child) =>
        parent == 'Series' && item.childTags['Series']?.contains(child) == true,
  );
}

VideoItem _item(
  String videoId,
  String name, {
  Set<String> childTags = const <String>{},
}) {
  return VideoItem(
    videoId: videoId,
    path: 'D:\\video\\$name',
    title: name,
    folder: 'D:\\video',
    tags: const <String>{'Series'},
    childTags: <String, Set<String>>{'Series': childTags},
    addedAt: DateTime.utc(2026, 1, 1),
  );
}

void _expectInvariants(PlayerSessionController playback) {
  final sourceIds =
      playback.sourcePlaylist.map((item) => item.videoId).toList();
  final queueIds = playback.queue.map((item) => item.videoId).toList();
  expect(sourceIds.toSet().length, sourceIds.length);
  expect(queueIds.toSet().length, queueIds.length);
  expect(sourceIds, containsAll(queueIds));
  if (playback.queue.isEmpty) return;
  expect(playback.playingIndex, inInclusiveRange(0, playback.queue.length - 1));
  expect(
      playback.selectedIndex, inInclusiveRange(0, playback.queue.length - 1));
  expect(playback.currentItem.videoId, queueIds[playback.playingIndex]);
  expect(playback.hasPrevious, playback.playingIndex > 0);
  expect(
    playback.hasNext,
    playback.playingIndex < playback.queue.length - 1,
  );
}
