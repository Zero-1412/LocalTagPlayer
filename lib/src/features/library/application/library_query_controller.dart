import 'dart:async';

import '../../../models/platform_models.dart';
import '../../../models/video_item.dart';
import '../../../services/tags/tag_query_service.dart';
import '../domain/library_query_snapshot.dart';

// ignore_for_file: slash_for_doc_comments

/** 已接受筛选结果发布后的回调。 */
typedef LibraryQueryAccepted = void Function(FilterState state);

/** 查询计算耗时回调，仅用于观测扫描差量路径，不参与发布决策。 */
typedef LibraryQueryMeasured = void Function(Duration elapsed);

/**
 * 媒体库筛选、搜索和结果发布的唯一 application owner。
 *
 * controller 复用 `FilterStateSource` 的缓存与扫描差量算法，并以自增 revision 拒绝旧请求。
 * 它不持有 Widget、`BuildContext`、Route、Repository、计数 controller 或播放队列；页面
 * 只负责提供当前数据快照、排序函数和发布后的局部重建。
 */
class LibraryQueryController {
  LibraryQueryController({
    FilterStateSource? source,
  }) : _source = source ?? FilterStateSource();

  /** 纯查询计算与缓存实现；不负责 Widget 生命周期。 */
  final FilterStateSource _source;
  /** 最近一次通过 epoch 与 latest-only 校验的结果。 */
  FilterState? _state;
  /** 最近一次由页面提交的筛选/搜索输入，可能早于对应结果发布。 */
  FilterQuery? _requestedQuery;
  /** 每次新请求、同步发布或取消都会提升，用于淘汰旧异步任务。 */
  var _revision = 0;
  /** dispose 后永久阻止结果发布。 */
  var _disposed = false;

  /** 当前已接受结果；页面首次水合前可以为空。 */
  FilterState? get state => _state;

  /** 当前待发布或已接受的筛选/搜索输入。 */
  FilterQuery? get requestedQuery => _requestedQuery;

  /** 当前 latest-only 代次，供测试和诊断确认旧请求已失效。 */
  int get revision => _revision;

  /** 是否已经释放，释放后不得再接受结果。 */
  bool get isDisposed => _disposed;

  /**
   * 配置下一次查询使用的数据和排序快照。
   *
   * [engine] 只读取调用方提供的当前视频与标签上下文；[dataRevision] 和
   * [sortFingerprint] 会共同进入结果 epoch，避免旧数据或旧排序写回。
   */
  void configure({
    required TagQueryService engine,
    required int totalCount,
    required int dataRevision,
    required String sortFingerprint,
    VideoItemComparator? compare,
    VideoItemSorter? sortVideos,
  }) {
    if (_disposed) {
      return;
    }
    _source.configure(
      engine: engine,
      totalCount: totalCount,
      dataRevision: dataRevision,
      sortFingerprint: sortFingerprint,
      compare: compare,
      sortVideos: sortVideos,
    );
  }

  /**
   * 用首屏同步快照建立结果 owner，并使此前排队的请求失效。
   *
   * [state] 必须已经包含调用方当前的完整 `LibraryResultEpoch`。
   */
  void seed(FilterState state) {
    if (_disposed) {
      return;
    }
    _revision += 1;
    _requestedQuery = state.query;
    _state = state;
  }

  /**
   * 使用最近一次 [configure] 的快照同步计算候选结果，但不直接发布。
   *
   * [changedVideos] 或 [removedVideoIds] 非空时复用 stable `videoId` 差量路径；最终
   * 是否接受仍必须经 [publish] 或 [schedule] 的 epoch 校验。
   */
  FilterState compute(
    FilterQuery query, {
    Iterable<VideoItem>? changedVideos,
    Iterable<String>? removedVideoIds,
  }) {
    return changedVideos == null && removedVideoIds == null
        ? _source.update(query)
        : _source.applyVideoDelta(
            query,
            changedVideos ?? const <VideoItem>[],
            removedVideoIds: removedVideoIds ?? const <String>[],
          );
  }

  /**
   * 同步发布排序等不改变成员集合的结果。
   *
   * 只有 [state] 与 [expectedEpoch] 完全一致时才接受；成功发布也会淘汰旧筛选任务。
   */
  bool publish(
    FilterState state, {
    required LibraryResultEpoch expectedEpoch,
  }) {
    if (_disposed || state.epoch != expectedEpoch) {
      return false;
    }
    _revision += 1;
    _requestedQuery = state.query;
    _state = state;
    return true;
  }

  /**
   * 在下一事件循环计算并发布最新筛选请求。
   *
   * [query] 是当前搜索与标签输入；[expectedEpoch] 是调用时的完整版本身份；
   * [changedVideos] 或 [removedVideoIds] 非空时只重新评估列表差量；[isStillCurrent] 由
   * 页面核对当前 store 和输入身份；[onAccepted] 只在 controller 已保存候选结果后调用。
   */
  void schedule({
    required FilterQuery query,
    required LibraryResultEpoch expectedEpoch,
    Iterable<VideoItem>? changedVideos,
    Iterable<String>? removedVideoIds,
    required bool Function(LibraryResultEpoch epoch) isStillCurrent,
    required LibraryQueryAccepted onAccepted,
    LibraryQueryMeasured? onMeasured,
  }) {
    if (_disposed) {
      return;
    }
    final requestRevision = ++_revision;
    _requestedQuery = query;
    final changedSnapshot = changedVideos?.toList(growable: false);
    final removedSnapshot = removedVideoIds?.toList(growable: false);
    Future<void>.delayed(Duration.zero, () {
      if (_disposed ||
          requestRevision != _revision ||
          !isStillCurrent(expectedEpoch)) {
        return;
      }
      final watch = Stopwatch()..start();
      final candidate = compute(
        query,
        changedVideos: changedSnapshot,
        removedVideoIds: removedSnapshot,
      );
      watch.stop();
      onMeasured?.call(watch.elapsed);
      if (_disposed ||
          requestRevision != _revision ||
          candidate.epoch != expectedEpoch ||
          !isStillCurrent(expectedEpoch)) {
        return;
      }
      _state = candidate;
      onAccepted(candidate);
    });
  }

  /** 取消尚未发布的请求，但保留最后一个已接受结果。 */
  void cancelPending() {
    _revision += 1;
  }

  /** 永久失效排队请求并释放结果引用。 */
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _revision += 1;
    _requestedQuery = null;
    _state = null;
  }
}
