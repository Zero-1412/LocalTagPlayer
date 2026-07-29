import '../../../models/platform_models.dart';
import '../../../services/library/library_count_refresh_coordinator.dart';
import '../domain/library_query_snapshot.dart';

// ignore_for_file: slash_for_doc_comments

/** 某个计数 epoch 已被 controller 接受后的页面通知。 */
typedef LibraryFacetCountsAccepted = void Function(
  LibraryCountEpoch epoch,
  Map<String, int> counts,
);

/**
 * 媒体库可见候选计数与全库稳定计数的唯一 application owner。
 *
 * 两类计数共享既有空闲窗口和 latest-only 协调器，但保存在独立只读快照中。该 owner
 * 不读取查询结果 controller，也不持有 Widget、Store、Route 或平台资源；页面负责提供
 * `resultCounts` 计算函数并在发布回调中触发局部重建。
 */
class LibraryFacetCountController {
  LibraryFacetCountController({
    LibraryCountRefreshCoordinator? coordinator,
  }) : _coordinator = coordinator ?? LibraryCountRefreshCoordinator();

  /** 延后执行、取消和 epoch 二次校验的低层协调器。 */
  final LibraryCountRefreshCoordinator _coordinator;
  /** 当前筛选上下文中的候选计数快照。 */
  Map<String, int> _visibleCounts = const <String, int>{};
  /** 不随当前筛选收缩的全库稳定计数快照。 */
  Map<String, int> _stableCounts = const <String, int>{};
  /** dispose 后阻止同步和异步快照发布。 */
  var _disposed = false;

  /** 当前筛选上下文中的只读候选计数。 */
  Map<String, int> get visibleCounts => _visibleCounts;

  /** 全库稳定标签计数；空集合表示页面应使用持久化 usageCount 回退。 */
  Map<String, int> get stableCounts => _stableCounts;

  /** 是否已经释放。 */
  bool get isDisposed => _disposed;

  /** 用首屏持久化计数建立可见候选快照。 */
  void seedVisible(Map<String, int> counts) {
    if (_disposed) {
      return;
    }
    _visibleCounts = _freeze(counts);
  }

  /** 从 Repository 已水合的 usageCount 构造无需全量扫描的回退计数。 */
  Map<String, int> fallbackCounts(Iterable<TagItem> tags) {
    return Map<String, int>.unmodifiable(<String, int>{
      for (final tag in tags) tag.id: tag.usageCount,
    });
  }

  /** 清空稳定计数，让页面暂时回退到持久化 usageCount。 */
  void clearStable() {
    if (_disposed) {
      return;
    }
    _stableCounts = const <String, int>{};
  }

  /** 同步计算并发布全库稳定计数，供低频标签维护完成路径使用。 */
  void refreshStableNow({
    required FilterQuery query,
    required Map<String, int> Function(FilterQuery query) compute,
  }) {
    if (_disposed) {
      return;
    }
    _stableCounts = _freeze(compute(query));
  }

  /** 安排当前筛选上下文的候选计数刷新。 */
  void scheduleVisible({
    required LibraryCountEpoch epoch,
    required FilterQuery query,
    required Map<String, int> Function(FilterQuery query) compute,
    required bool Function(LibraryCountEpoch epoch) isStillCurrent,
    required LibraryFacetCountsAccepted onAccepted,
  }) {
    _schedule(
      target: _LibraryFacetCountTarget.visible,
      epoch: epoch,
      query: query,
      compute: compute,
      isStillCurrent: isStillCurrent,
      onAccepted: onAccepted,
    );
  }

  /** 安排不随当前筛选收缩的全库稳定计数刷新。 */
  void scheduleStable({
    required LibraryCountEpoch epoch,
    required FilterQuery query,
    required Map<String, int> Function(FilterQuery query) compute,
    required bool Function(LibraryCountEpoch epoch) isStillCurrent,
    required LibraryFacetCountsAccepted onAccepted,
  }) {
    _schedule(
      target: _LibraryFacetCountTarget.stable,
      epoch: epoch,
      query: query,
      compute: compute,
      isStillCurrent: isStillCurrent,
      onAccepted: onAccepted,
    );
  }

  /** 取消尚未开始或尚未发布的计数任务。 */
  void cancelPending() {
    _coordinator.cancelPending();
  }

  /** 释放计时器并永久阻止计数快照发布。 */
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _coordinator.dispose();
  }

  /** 把统一协调器的结果发布到指定只读快照。 */
  void _schedule({
    required _LibraryFacetCountTarget target,
    required LibraryCountEpoch epoch,
    required FilterQuery query,
    required Map<String, int> Function(FilterQuery query) compute,
    required bool Function(LibraryCountEpoch epoch) isStillCurrent,
    required LibraryFacetCountsAccepted onAccepted,
  }) {
    if (_disposed) {
      return;
    }
    _coordinator.schedule(
      epoch: epoch,
      query: query,
      compute: compute,
      isStillCurrent: (candidate) => !_disposed && isStillCurrent(candidate),
      onComplete: (candidate, counts) {
        if (_disposed) {
          return;
        }
        final snapshot = _freeze(counts);
        switch (target) {
          case _LibraryFacetCountTarget.visible:
            _visibleCounts = snapshot;
            break;
          case _LibraryFacetCountTarget.stable:
            _stableCounts = snapshot;
            break;
        }
        onAccepted(candidate, snapshot);
      },
    );
  }

  /** 复制外部 Map，防止 Repository 或页面在发布后继续修改快照。 */
  Map<String, int> _freeze(Map<String, int> counts) =>
      Map<String, int>.unmodifiable(Map<String, int>.of(counts));
}

/** 两个互不覆盖的计数发布目标。 */
enum _LibraryFacetCountTarget {
  visible,
  stable,
}
