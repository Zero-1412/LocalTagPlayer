part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/** 媒体库专项压测读取的不可变运行快照。 */
class LibraryStressSnapshot {
  const LibraryStressSnapshot({
    required this.videoCount,
    required this.visibleCount,
    required this.roots,
    required this.thumbnailQueued,
    required this.thumbnailActive,
    required this.probeQueued,
    required this.probeActive,
    required this.probeCompleted,
    required this.probeFailed,
  });

  /** SQLite hydration 后当前内存索引的视频总数。 */
  final int videoCount;

  /** 当前筛选条件下交给媒体库视图的结果数。 */
  final int visibleCount;

  /** 当前隔离 profile 配置的媒体库根目录。 */
  final List<String> roots;

  /** 等待生成或读取的缩略图任务数。 */
  final int thumbnailQueued;

  /** 当前活动缩略图任务数。 */
  final int thumbnailActive;

  /** 当前代次等待媒体详情解析的任务数。 */
  final int probeQueued;

  /** 当前活动媒体详情解析数。 */
  final int probeActive;

  /** 当前代次已经完成的媒体详情解析数。 */
  final int probeCompleted;

  /** 当前代次失败的媒体详情解析数。 */
  final int probeFailed;
}

/**
 * 真实窗口专项压测与媒体库页面之间的 debug-only 控制边界。
 *
 * 生产构建不会注册回调；集成测试只能操作环境变量明确指定的单个 root，并且
 * 仍复用页面 `_scan`、SQLite Repository、差量刷新与缓存调度链路。该边界不提供
 * 删除本地文件能力，也不关闭 Flutter 语义树。
 */
class LibraryStressControl {
  const LibraryStressControl._();

  static Object? _owner;
  static Future<LibraryScanCommitResult> Function()? _addRoot;
  static Future<int> Function()? _removeRoot;
  static LibraryStressSnapshot Function()? _snapshot;

  /** 页面是否已完成 hydration 并注册压测控制。 */
  static bool get isAvailable =>
      _owner != null &&
      _addRoot != null &&
      _removeRoot != null &&
      _snapshot != null;

  /** 注册当前媒体库页面；重复页面会替换旧页面，避免回调指向已 dispose 状态。 */
  static void register({
    required Object owner,
    required Future<LibraryScanCommitResult> Function() addRoot,
    required Future<int> Function() removeRoot,
    required LibraryStressSnapshot Function() snapshot,
  }) {
    assert(() {
      _owner = owner;
      _addRoot = addRoot;
      _removeRoot = removeRoot;
      _snapshot = snapshot;
      return true;
    }());
  }

  /** 清除指定页面拥有的回调，禁止测试在页面退出后继续写数据库。 */
  static void unregister(Object owner) {
    assert(() {
      if (identical(_owner, owner)) {
        _owner = null;
        _addRoot = null;
        _removeRoot = null;
        _snapshot = null;
      }
      return true;
    }());
  }

  /** 通过页面应用链路添加环境变量指定的 root。 */
  static Future<LibraryScanCommitResult> addConfiguredRoot() {
    final action = _addRoot;
    if (action == null) {
      throw StateError('媒体库专项压测控制尚未注册');
    }
    return action();
  }

  /** 通过页面应用链路移除环境变量指定的 root，但绝不删除本地文件。 */
  static Future<int> removeConfiguredRoot() {
    final action = _removeRoot;
    if (action == null) {
      throw StateError('媒体库专项压测控制尚未注册');
    }
    return action();
  }

  /** 读取当前页面、缩略图和媒体探测队列状态。 */
  static LibraryStressSnapshot snapshot() {
    final read = _snapshot;
    if (read == null) {
      throw StateError('媒体库专项压测控制尚未注册');
    }
    return read();
  }
}
