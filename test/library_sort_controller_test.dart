import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_sort_controller.dart';
import 'package:local_tag_player/src/models/library_sort.dart';
import 'package:local_tag_player/src/models/video_item.dart';

VideoItem _video({
  required String videoId,
  required String title,
  required DateTime addedAt,
}) {
  return VideoItem(
    videoId: videoId,
    path: 'D:\\library\\$title.mp4',
    title: title,
    folder: r'D:\library',
    tags: const <String>{},
    addedAt: addedAt,
  );
}

void main() {
  test('排序 owner 恢复偏好并发布稳定 fingerprint', () {
    final controller = LibrarySortController();

    controller.restore(const LibrarySortPreferences(
      mode: SortMode.name,
      direction: SortDirection.ascending,
      denseResultGrid: true,
    ));

    expect(controller.mode, SortMode.name);
    expect(controller.direction, SortDirection.ascending);
    expect(controller.fingerprint, 'name:ascending');
  });

  test('无变化提交不会制造新排序状态', () {
    final controller = LibrarySortController(
      mode: SortMode.name,
      direction: SortDirection.ascending,
    );

    expect(
      controller.apply(
        mode: SortMode.name,
        direction: SortDirection.ascending,
      ),
      isFalse,
    );
    expect(controller.oppositeDirection, SortDirection.descending);
  });

  test('排序只改变顺序而不改变 stable id 成员', () {
    final older = _video(
      videoId: 'video-older',
      title: 'video10',
      addedAt: DateTime.utc(2025),
    );
    final newer = _video(
      videoId: 'video-newer',
      title: 'video2',
      addedAt: DateTime.utc(2026),
    );
    final controller = LibrarySortController(
      mode: SortMode.name,
      direction: SortDirection.ascending,
    );

    final sorted = controller.sort(<VideoItem>[older, newer]);

    expect(sorted.map((item) => item.videoId), <String>[
      'video-newer',
      'video-older',
    ]);
    expect(sorted.map((item) => item.videoId).toSet(), <String>{
      'video-older',
      'video-newer',
    });
    expect(() => sorted.add(older), throwsUnsupportedError);
  });
}
