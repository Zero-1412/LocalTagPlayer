part of '../app.dart';

/// 媒体库标签计数刷新协调器。
///
/// 标签计数会扫描候选标签和当前视频集合，不能直接绑在标签点击、搜索输入或排序
/// 这类高频交互上同步执行。该协调器把计数刷新收口到一个明确的延后任务入口，
/// 并用 revision 丢弃过期任务，保证可见视频列表先更新，非关键计数稍后更新。
class LibraryCountRefreshCoordinator {
  LibraryCountRefreshCoordinator({
    this.idleDelay = const Duration(milliseconds: 1200),
  });

  /// 高频交互后的空闲等待时间。
  ///
  /// 用户连续点击标签时，等待窗口内的新请求会替换旧请求，避免多次全量计数排队。
  final Duration idleDelay;

  Timer? _timer;
  var _revision = 0;

  /// 当前刷新版本号。
  ///
  /// 页面可以把该值和自身筛选版本一起用于二次校验，避免旧页面状态写回新 UI。
  int get revision => _revision;

  /// 取消所有待执行的计数刷新。
  ///
  /// 标签点击、搜索输入、排序切换等前台交互应调用该方法，让界面优先响应用户输入，
  /// 已经排队但尚未开始的计数刷新会被静默丢弃。
  void cancelPending() {
    _revision += 1;
    _timer?.cancel();
    _timer = null;
  }

  /// 安排一次空闲计数刷新。
  ///
  /// [query] 是本次计数对应的筛选条件；[compute] 只在空闲窗口结束后执行；
  /// [isStillCurrent] 用于让页面确认 store、筛选版本和 widget 生命周期仍然有效；
  /// [onComplete] 只会收到最新且仍有效的计数结果。
  void schedule({
    required FilterQuery query,
    required Map<String, int> Function(FilterQuery query) compute,
    required bool Function(int revision) isStillCurrent,
    required ValueChanged<Map<String, int>> onComplete,
  }) {
    final requestRevision = ++_revision;
    _timer?.cancel();
    _timer = Timer(idleDelay, () {
      _timer = null;
      if (requestRevision != _revision || !isStillCurrent(requestRevision)) {
        return;
      }
      final counts = compute(query);
      if (requestRevision != _revision || !isStillCurrent(requestRevision)) {
        return;
      }
      onComplete(counts);
    });
  }

  /// 释放计时器。
  ///
  /// 页面 dispose 时必须调用，避免已关闭页面继续收到异步计数回调。
  void dispose() {
    cancelPending();
  }
}
