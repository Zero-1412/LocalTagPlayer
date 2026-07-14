import 'dart:convert';
import 'dart:typed_data';

import '../../models/library_scan_models.dart';
import '../../platform/file_system_adapter.dart';
import 'library_load_diagnostics.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 由组合根解析的 debug 压测与诊断配置。
 *
 * 页面只消费已经解析的值，不读取进程环境，也不直接创建诊断文件。
 */
class LibraryDebugOptions {
  const LibraryDebugOptions({
    this.stressRoot,
    this.startupDiagnosticsPath,
  });

  /** 专项压测唯一允许操作的媒体 root。 */
  final String? stressRoot;

  /** 不包含用户路径或标签内容的启动诊断输出文件。 */
  final String? startupDiagnosticsPath;

  /** 通过文件系统边界写入安全启动诊断摘要。 */
  Future<void> writeStartupDiagnostics({
    required FileSystemAdapter fileSystem,
    required LibraryLoadDiagnostics diagnostics,
    required Duration totalElapsed,
    required String marker,
  }) async {
    final outputPath = startupDiagnosticsPath;
    if (outputPath == null) return;
    try {
      await fileSystem.writeBytes(
        outputPath,
        Uint8List.fromList(utf8.encode(jsonEncode(<String, Object?>{
          'marker': marker,
          'totalMs': double.parse(
            (totalElapsed.inMicroseconds / 1000).toStringAsFixed(3),
          ),
          ...diagnostics.toJson(),
        }))),
      );
    } catch (_) {
      // debug 诊断失败不能阻塞媒体库首帧。
    }
  }
}

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
  static Future<void> Function()? _waitForPlayerRelease;
  static LibraryStressSnapshot Function()? _snapshot;

  /** 页面是否已完成 hydration 并注册压测控制。 */
  static bool get isAvailable =>
      _owner != null &&
      _addRoot != null &&
      _removeRoot != null &&
      _waitForPlayerRelease != null &&
      _snapshot != null;

  /** 注册当前媒体库页面；重复页面会替换旧页面，避免回调指向已 dispose 状态。 */
  static void register({
    required Object owner,
    required Future<LibraryScanCommitResult> Function() addRoot,
    required Future<int> Function() removeRoot,
    required Future<void> Function() waitForPlayerRelease,
    required LibraryStressSnapshot Function() snapshot,
  }) {
    assert(() {
      _owner = owner;
      _addRoot = addRoot;
      _removeRoot = removeRoot;
      _waitForPlayerRelease = waitForPlayerRelease;
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
        _waitForPlayerRelease = null;
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

  /** 等待最近一次播放器完成真实原生销毁，避免压测把纹理解绑误当成资源已释放。 */
  static Future<void> waitForPlayerRelease() {
    final action = _waitForPlayerRelease;
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
