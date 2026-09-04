import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_sidebar_metrics_cache.dart';
import 'package:local_tag_player/src/models/video_item.dart';

void main() {
  test('11000 项侧栏统计按 revision 单次遍历并复用快照', () {
    final videos = List<VideoItem>.generate(
      11000,
      (index) => VideoItem(
        videoId: 'video-$index',
        path: 'D:/library/video-$index.mp4',
        title: 'video-$index',
        folder: 'D:/library',
        tags: const <String>{},
        addedAt: DateTime.utc(2026, 9, 4),
        isFavorite: index.isEven,
        isMissing: index % 11 == 0,
      ),
      growable: false,
    );
    final cache = LibrarySidebarMetricsCache();
    final watch = Stopwatch()..start();
    final first = cache.resolve(revision: 7, videos: videos);
    final second = cache.resolve(revision: 7, videos: videos);
    watch.stop();

    expect(first.favoriteCount, 5500);
    expect(first.missingCount, 1000);
    expect(identical(first, second), isTrue);
    expect(cache.rebuildCount, 1);
    expect(watch.elapsedMilliseconds, lessThan(250));
    // 保留一行可检索基准，不输出媒体路径或用户数据。
    // ignore: avoid_print
    print('LIBRARY_SIDEBAR_BENCHMARK items=11000 '
        'elapsed_us=${watch.elapsedMicroseconds} rebuilds=${cache.rebuildCount}');
  });

  test('revision 前进后只重建一次新统计', () {
    final item = VideoItem(
      videoId: 'stable',
      path: 'D:/library/video.mp4',
      title: 'video',
      folder: 'D:/library',
      tags: const <String>{},
      addedAt: DateTime.utc(2026, 9, 4),
    );
    final cache = LibrarySidebarMetricsCache();
    cache.resolve(revision: 1, videos: [item]);
    item.isFavorite = true;
    final next = cache.resolve(revision: 2, videos: [item]);

    expect(next.favoriteCount, 1);
    expect(cache.rebuildCount, 2);
  });
}
