import 'package:flutter/foundation.dart';

// ignore_for_file: slash_for_doc_comments

/** 读取一份不可变缓存统计快照的应用层命令。 */
typedef LoadCacheDiagnostics<T> = Future<T> Function();

/**
 * 缓存诊断只读生命周期的唯一 owner。
 *
 * controller 只管理读取代次、加载状态、结果与错误，不持有 `ThumbnailService`、
 * Repository、`BuildContext`、Route 或重试/清理命令。刷新采用 latest-only 发布，
 * dispose 会使所有在途结果失效，避免离开设置页后继续通知 Widget。
 */
class CacheDiagnosticsController<T> extends ChangeNotifier {
  CacheDiagnosticsController({required LoadCacheDiagnostics<T> load})
      : _load = load;

  /** 由页面组合具体缓存服务与当前媒体集合的只读加载命令。 */
  final LoadCacheDiagnostics<T> _load;

  /** 最近一次成功且仍可发布的结果。 */
  T? _stats;

  /** 最新读取失败的原始对象，仅供状态判断和测试，不应直接展示。 */
  Object? _error;

  /** 当前最新读取是否尚未结束。 */
  var _loading = false;

  /** 单调递增的读取代次，用于拒绝旧 Future。 */
  var _generation = 0;

  /** 页面释放后永久阻止异步结果发布。 */
  var _disposed = false;

  /** 最近一次成功且仍属最新代次的统计快照。 */
  T? get stats => _stats;

  /** 最新读取是否仍在执行。 */
  bool get loading => _loading;

  /** 最新读取失败时保存的错误；展示层不得直接暴露可能包含本机路径的文本。 */
  Object? get error => _error;

  /** 丢弃旧快照并启动新一代统计读取。 */
  Future<void> refresh() async {
    if (_disposed) {
      return;
    }
    final generation = ++_generation;
    _stats = null;
    _error = null;
    _loading = true;
    notifyListeners();

    try {
      final stats = await _load();
      if (_canPublish(generation)) {
        _stats = stats;
      }
    } catch (error) {
      if (_canPublish(generation)) {
        _error = error;
      }
    }
    if (!_canPublish(generation)) {
      return;
    }
    _loading = false;
    notifyListeners();
  }

  /** 只有当前最新且尚未释放的读取代次可以改变可见状态。 */
  bool _canPublish(int generation) => !_disposed && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}
