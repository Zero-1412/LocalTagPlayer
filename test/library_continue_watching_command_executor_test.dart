import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_continue_watching_command_executor.dart';
import 'package:local_tag_player/src/models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

VideoItem _playedItem(String videoId, String path) => VideoItem(
      videoId: videoId,
      path: path,
      title: videoId,
      folder: 'C:\\media',
      tags: <String>{'manual'},
      addedAt: DateTime.utc(2026, 7, 29),
      isFavorite: true,
      lastPlayedAt: DateTime.utc(2026, 7, 29, 10),
      playbackPosition: const Duration(seconds: 37),
      playbackDuration: const Duration(minutes: 3),
      playbackCompleted: false,
      playbackPositionUpdatedAt: DateTime.utc(2026, 7, 29, 10),
    );

void main() {
  const executor = LibraryContinueWatchingCommandExecutor();

  test('清理目标按 stable videoId 选择而不依赖 mutable path', () {
    final selected = _playedItem('selected', 'C:\\old\\video.mp4');
    final other = _playedItem('other', 'C:\\media\\other.mp4');
    selected.path = 'E:\\moved\\video.mp4';

    expect(
      recentPlaybackClearTargets(
        <VideoItem>[selected, other],
        selectedVideoIds: const <String>{'selected'},
        selectedOnly: true,
      ),
      <VideoItem>[selected],
    );
  });

  test('清理成功只重置继续观看字段并保留其它用户数据', () async {
    final item = _playedItem('stable', 'C:\\media\\video.mp4');
    final result = await executor.clear(
      <VideoItem>[item],
      commit: (items) async {
        expect(items, <VideoItem>[item]);
        expect(item.lastPlayedAt, isNull);
        expect(item.playbackPosition, Duration.zero);
      },
    );

    expect(result.succeeded, isTrue);
    expect(result.snapshots, hasLength(1));
    expect(item.videoId, 'stable');
    expect(item.isFavorite, isTrue);
    expect(item.tags, contains('manual'));
    expect(item.playbackDuration, const Duration(minutes: 3));
  });

  test('清理提交失败恢复精确播放快照', () async {
    final item = _playedItem('stable', 'C:\\media\\video.mp4');
    final lastPlayedAt = item.lastPlayedAt;
    final updatedAt = item.playbackPositionUpdatedAt;

    final result = await executor.clear(
      <VideoItem>[item],
      commit: (_) => Future<void>.error(StateError('commit failed')),
    );

    expect(result.succeeded, isFalse);
    expect(item.lastPlayedAt, lastPlayedAt);
    expect(item.playbackPosition, const Duration(seconds: 37));
    expect(item.playbackCompleted, isFalse);
    expect(item.playbackPositionUpdatedAt, updatedAt);
  });

  test('撤销不覆盖新播放且提交失败重新回到已清理状态', () async {
    final replayed = _playedItem('replayed', 'C:\\media\\replayed.mp4');
    final failed = _playedItem('failed', 'C:\\media\\failed.mp4');
    final cleared = await executor.clear(
      <VideoItem>[replayed, failed],
      commit: (_) async {},
    );
    replayed
      ..lastPlayedAt = DateTime.utc(2026, 7, 29, 11)
      ..playbackPosition = const Duration(seconds: 9)
      ..playbackPositionUpdatedAt = DateTime.utc(2026, 7, 29, 11);

    final undo = await executor.undo(
      cleared.snapshots,
      commit: (_) => Future<void>.error(StateError('undo failed')),
    );

    expect(undo.succeeded, isFalse);
    expect(
        undo.snapshots.map((snapshot) => snapshot.videoId), <String>['failed']);
    expect(replayed.playbackPosition, const Duration(seconds: 9));
    expect(failed.lastPlayedAt, isNull);
    expect(failed.playbackPosition, Duration.zero);
    expect(failed.playbackPositionUpdatedAt, isNull);
  });
}
