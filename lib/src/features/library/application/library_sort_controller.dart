import '../../../models/library_sort.dart';
import '../../../models/video_item.dart';
import '../domain/library_sorting.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库排序字段与方向的唯一 owner。
 *
 * controller 只改变当前内存排序身份并调用纯排序函数；不读取 Store、不执行筛选或
 * `resultCounts`、不持久化文件，也不创建播放队列。页面仍负责把新顺序发布到当前已接受
 * 结果，并通过应用服务保存偏好。
 */
class LibrarySortController {
  /** 使用初始 [mode] 与 [direction] 建立唯一排序身份。 */
  LibrarySortController({
    SortMode mode = SortMode.recent,
    SortDirection direction = SortDirection.descending,
  })  : _mode = mode,
        _direction = direction;

  /** 当前排序字段；只允许经 [restore] 或 [apply] 变更。 */
  SortMode _mode;
  /** 当前排序方向；与字段共同构成结果排序指纹。 */
  SortDirection _direction;

  /** 当前排序字段。 */
  SortMode get mode => _mode;

  /** 当前排序方向。 */
  SortDirection get direction => _direction;

  /** 显式且跨运行稳定的结果 epoch 指纹。 */
  String get fingerprint => '${_mode.name}:${_direction.name}';

  /** 当前方向的反向值，供页面确认后提交。 */
  SortDirection get oppositeDirection => _direction == SortDirection.descending
      ? SortDirection.ascending
      : SortDirection.descending;

  /** 从持久化偏好恢复字段与方向；网格密度由独立视图 owner 恢复。 */
  void restore(LibrarySortPreferences preferences) {
    _mode = preferences.mode;
    _direction = preferences.direction;
  }

  /**
   * 应用字段或方向变更；没有真实变化时返回 false。
   *
   * 该方法不发通知，页面可在一次 `setState` 内同时重排已接受结果，避免产生中间顺序。
   */
  bool apply({
    SortMode? mode,
    SortDirection? direction,
  }) {
    final nextMode = mode ?? _mode;
    final nextDirection = direction ?? _direction;
    if (nextMode == _mode && nextDirection == _direction) {
      return false;
    }
    _mode = nextMode;
    _direction = nextDirection;
    return true;
  }

  /** 按当前身份比较两个视频。 */
  int compare(VideoItem a, VideoItem b) => compareLibraryVideosForSort(
        a,
        b,
        sortMode: _mode,
        sortDirection: _direction,
      );

  /** 按当前身份返回不可变的稳定视频顺序。 */
  List<VideoItem> sort(Iterable<VideoItem> videos) => sortedLibraryVideos(
        videos,
        sortMode: _mode,
        sortDirection: _direction,
      );
}
