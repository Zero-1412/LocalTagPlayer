import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_favorite_command_executor.dart';
import 'package:local_tag_player/src/models/video_item.dart';

VideoItem _item({required bool favorite}) => VideoItem(
      videoId: 'stable-video',
      path: r'D:\library\video.mp4',
      title: 'video',
      folder: r'D:\library',
      tags: <String>{'manual'},
      addedAt: DateTime.utc(2026, 9, 4),
      isFavorite: favorite,
    );

void main() {
  test('收藏提交成功保留新状态与同一稳定身份', () async {
    final item = _item(favorite: false);
    String? committedVideoId;

    await const LibraryFavoriteCommandExecutor().toggle(
      item,
      commit: (candidate) async => committedVideoId = candidate.videoId,
    );

    expect(item.isFavorite, isTrue);
    expect(committedVideoId, 'stable-video');
    expect(item.tags, contains('manual'));
  });

  test('收藏提交失败恢复精确旧状态并上抛错误', () async {
    final item = _item(favorite: true);

    await expectLater(
      const LibraryFavoriteCommandExecutor().toggle(
        item,
        commit: (_) async => throw StateError('write failed'),
      ),
      throwsStateError,
    );

    expect(item.isFavorite, isTrue);
    expect(item.videoId, 'stable-video');
    expect(item.tags, contains('manual'));
  });
}
