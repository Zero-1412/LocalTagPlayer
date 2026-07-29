import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/player/application/player_session_controller.dart';
import 'package:local_tag_player/src/models/video_item.dart';

void main() {
  VideoItem item(String id, {String? path}) {
    return VideoItem(
      videoId: id,
      path: path ?? 'D:\\video\\$id.mp4',
      title: id,
      folder: r'D:\video',
      tags: const <String>{},
      addedAt: DateTime.utc(2026, 1, 1),
    );
  }

  PlayerSessionController createController(
    List<VideoItem> source, {
    String? initialVideoId,
    String? activeParentTag,
    PlayerChildTagMatcher? matchesChildTag,
  }) {
    return PlayerSessionController(
      sourcePlaylist: source,
      acceptedSourceVideoIds:
          source.map((video) => video.videoId).toList(growable: false),
      activeParentTag: activeParentTag,
      initialVideoId: initialVideoId ?? source.first.videoId,
      matchesChildTag: matchesChildTag ?? (_, __, ___) => false,
    );
  }

  test('来源对象必须与已接受 stable-ID 快照成员和顺序一致', () {
    final first = item('first');
    final second = item('second');

    expect(
      () => PlayerSessionController(
        sourcePlaylist: <VideoItem>[first, second],
        acceptedSourceVideoIds: <String>[second.videoId, first.videoId],
        activeParentTag: null,
        initialVideoId: first.videoId,
        matchesChildTag: (_, __, ___) => false,
      ),
      throwsArgumentError,
    );
  });

  test('来源与当前队列对页面只暴露不可写视图', () {
    final first = item('first');
    final second = item('second');
    final controller = createController(<VideoItem>[first, second]);

    expect(
      () => controller.sourcePlaylist.add(item('third')),
      throwsUnsupportedError,
    );
    expect(
      () => controller.queue.removeAt(0),
      throwsUnsupportedError,
    );
    expect(controller.currentItem.videoId, first.videoId);
  });

  test('二级标签只在来源快照内派生且空结果回退同一来源', () {
    final first = item('first');
    final second = item('second');
    final controller = createController(
      <VideoItem>[first, second],
      activeParentTag: 'Series',
      matchesChildTag: (video, parent, child) =>
          parent == 'Series' &&
          child == 'AlbumB' &&
          video.videoId == second.videoId,
    );

    controller.toggleChildTag(
      'AlbumB',
      preferredVideoId: first.videoId,
    );
    expect(
      controller.queue.map((video) => video.videoId),
      <String>[second.videoId],
    );

    controller.setPlaylistForChildTag(
      'Missing',
      preferredVideoId: second.videoId,
    );
    expect(
      controller.queue.map((video) => video.videoId),
      <String>[first.videoId, second.videoId],
    );
    expect(controller.currentItem.videoId, second.videoId);
  });

  test('路径变化后初始化与删除仍只按 stable videoId', () {
    final first = item('first', path: r'D:\old\shared.mp4');
    final second = item('second', path: r'D:\other\shared.mp4');
    final controller = createController(
      <VideoItem>[first, second],
      initialVideoId: second.videoId,
    );
    second.path = r'E:\moved\shared.mp4';

    expect(controller.currentItem.videoId, second.videoId);
    expect(controller.removeItemAt(1), isTrue);
    expect(
      controller.sourcePlaylist.map((video) => video.videoId),
      <String>[first.videoId],
    );
    expect(controller.currentItem.videoId, first.videoId);
  });

  test('删除播放项之前的视频只回退索引并保持播放身份', () {
    final first = item('first');
    final second = item('second');
    final third = item('third');
    final controller = createController(
      <VideoItem>[first, second, third],
      initialVideoId: second.videoId,
    );

    expect(controller.removeItemAt(0), isFalse);
    expect(controller.currentItem.videoId, second.videoId);
    expect(controller.playingIndex, 0);
    expect(controller.nextIndex, 1);
    expect(controller.select(1), isTrue);
    expect(controller.locatePlayingIndex(), 0);
    expect(controller.selectedIndex, 1);
  });
}
