import '../../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/** 侧栏需要的全库布尔统计快照。 */
class LibrarySidebarMetrics {
  const LibrarySidebarMetrics({
    required this.favoriteCount,
    required this.missingCount,
  });

  final int favoriteCount;
  final int missingCount;
}

/**
 * 按媒体库 revision 复用侧栏全库统计。
 *
 * 同一次 revision 只遍历视频集合一遍，普通 rebuild、面板动画和窗口缩放直接复用快照。
 */
class LibrarySidebarMetricsCache {
  int? _revision;
  LibrarySidebarMetrics? _snapshot;
  var _rebuildCount = 0;

  /** 测试与性能门禁读取的实际重建次数。 */
  int get rebuildCount => _rebuildCount;

  LibrarySidebarMetrics resolve({
    required int revision,
    required Iterable<VideoItem> videos,
  }) {
    final cached = _snapshot;
    if (_revision == revision && cached != null) {
      return cached;
    }
    var favoriteCount = 0;
    var missingCount = 0;
    for (final item in videos) {
      if (item.isFavorite) favoriteCount += 1;
      if (item.isMissing) missingCount += 1;
    }
    final next = LibrarySidebarMetrics(
      favoriteCount: favoriteCount,
      missingCount: missingCount,
    );
    _revision = revision;
    _snapshot = next;
    _rebuildCount += 1;
    return next;
  }
}
