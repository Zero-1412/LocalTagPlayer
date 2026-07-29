import 'dart:async';

import '../../../models/library_scan_models.dart';

// ignore_for_file: slash_for_doc_comments

/** 扫描动作；Repository 仍拥有实际枚举、generation cancellation 与事务提交。 */
typedef LibraryScanAction = Future<LibraryScanCommitResult> Function(
  LibraryScanProgressCallback onProgress,
);

/** 当前扫描结果通过代次校验后的应用层处理。 */
typedef LibraryScanResultAccepted = FutureOr<void> Function(
  LibraryScanCommitResult result,
);

/** 当前扫描失败后的应用层反馈；controller 不持有本机路径或 UI。 */
typedef LibraryScanFailure = FutureOr<void> Function(
  Object error,
  StackTrace stackTrace,
);

/** 生命周期快照改变后的页面通知。 */
typedef LibraryScanLifecycleChanged<TMediaProgress> = void Function(
  LibraryScanLifecycleState<TMediaProgress> state,
);

/**
 * 媒体库扫描与扫描后媒体解析的只读生命周期快照。
 *
 * 扫描进度和取消状态属于同一操作代次；媒体解析进度属于独立 generation，避免旧服务
 * 在新扫描或新探测会话开始后覆盖当前 UI。
 */
class LibraryScanLifecycleState<TMediaProgress> {
  const LibraryScanLifecycleState({
    this.isScanning = false,
    this.isCancelling = false,
    this.scanProgress,
    this.mediaImportProgress,
  });

  /** 是否存在仍未完成结果处理的扫描操作。 */
  final bool isScanning;

  /** 用户已请求取消，但 Repository 的扫描 Future 仍在退出。 */
  final bool isCancelling;

  /** 当前后端 generation 的最新扫描进度。 */
  final LibraryScanProgress? scanProgress;

  /** 当前扫描后媒体解析 generation 的最新进度。 */
  final TMediaProgress? mediaImportProgress;
}

/**
 * 媒体库扫描、路径导入检查和扫描后解析的 application 生命周期 owner。
 *
 * 本类只负责 latest-only、互斥、generation 校验和不可变状态发布。它不读取 Store，
 * 不执行文件系统检查、不提交 SQLite、不创建媒体服务，也不持有 Widget、BuildContext、
 * Route 或平台资源。实际扫描、限流和取消由调用方注入的既有边界继续负责。
 */
class LibraryScanLifecycleController<TMediaProgress> {
  /** 当前不可变状态。 */
  LibraryScanLifecycleState<TMediaProgress> _state =
      const LibraryScanLifecycleState();

  /** 每轮扫描开始时递增，用于拒绝旧 Future、旧进度与旧错误。 */
  var _scanOperationRevision = 0;

  /** 当前扫描首次接受的 Repository generation。 */
  int? _activeScanGeneration;

  /** 每次路径导入检查递增；只有最后一次异步检查可继续启动扫描。 */
  var _pathImportRevision = 0;

  /** 每次媒体解析服务重建递增，旧服务回调不得发布。 */
  var _mediaImportGeneration = 0;

  /** dispose 后永久拒绝所有发布。 */
  var _disposed = false;

  /** 当前只读生命周期状态。 */
  LibraryScanLifecycleState<TMediaProgress> get state => _state;

  /** 当前扫描操作代次，供测试与诊断确认旧回调已失效。 */
  int get scanOperationRevision => _scanOperationRevision;

  /** 是否已经释放。 */
  bool get isDisposed => _disposed;

  /**
   * 开始一轮路径导入检查并返回 latest-only token。
   *
   * 文件/目录 stat 仍由 FileSystemAdapter 完成；本 token 只阻止较早检查在较晚拖放或选择
   * 之后继续触发扫描。
   */
  int beginPathImportInspection() {
    if (_disposed) {
      return -1;
    }
    return ++_pathImportRevision;
  }

  /** 判断路径导入检查是否仍是最后一次请求。 */
  bool isCurrentPathImport(int revision) =>
      !_disposed && revision == _pathImportRevision;

  /** 使尚未完成的路径导入检查失效。 */
  void cancelPathImportInspections() {
    _pathImportRevision += 1;
  }

  /**
   * 互斥执行一轮扫描，并只把当前操作与当前后端 generation 的结果交给调用方。
   *
   * [onAccepted] 在扫描状态仍为 active 时执行，保持既有“扫描完成反馈与差量应用结束后
   * 再退出进度态”的顺序。[action] 返回 cancelled 时不发布结果，也不调用失败回调。
   */
  Future<bool> run({
    required LibraryScanAction action,
    required LibraryScanResultAccepted onAccepted,
    required LibraryScanFailure onFailure,
    required LibraryScanLifecycleChanged<TMediaProgress> onChanged,
  }) async {
    if (_disposed || _state.isScanning) {
      return false;
    }
    cancelPathImportInspections();
    _mediaImportGeneration += 1;
    final operationRevision = ++_scanOperationRevision;
    _activeScanGeneration = null;
    _emit(
      LibraryScanLifecycleState<TMediaProgress>(
        isScanning: true,
        mediaImportProgress: null,
      ),
      onChanged,
    );
    try {
      final result = await action((progress) {
        if (!_isCurrentScan(operationRevision)) {
          return;
        }
        final generation = _activeScanGeneration;
        if (generation != null && generation != progress.generationId) {
          return;
        }
        _activeScanGeneration ??= progress.generationId;
        _emit(
          LibraryScanLifecycleState<TMediaProgress>(
            isScanning: true,
            isCancelling: _state.isCancelling,
            scanProgress: progress,
            mediaImportProgress: _state.mediaImportProgress,
          ),
          onChanged,
        );
      });
      if (!_isCurrentScan(operationRevision) || result.cancelled) {
        return true;
      }
      final generation = _activeScanGeneration;
      if (generation != null && generation != result.generationId) {
        return true;
      }
      _activeScanGeneration ??= result.generationId;
      await onAccepted(result);
    } catch (error, stackTrace) {
      if (_isCurrentScan(operationRevision)) {
        await onFailure(error, stackTrace);
      }
    } finally {
      if (_isCurrentScan(operationRevision)) {
        _activeScanGeneration = null;
        _emit(
          LibraryScanLifecycleState<TMediaProgress>(
            mediaImportProgress: _state.mediaImportProgress,
          ),
          onChanged,
        );
      }
    }
    return true;
  }

  /**
   * 乐观切换当前扫描暂停状态，并把真实暂停命令委托给 Repository。
   *
   * 命令失败时只在同一操作和 generation 仍有效时恢复旧快照，避免晚到失败覆盖新扫描。
   */
  Future<bool> toggleScanPaused({
    required Future<void> Function(bool paused) setPaused,
    required LibraryScanLifecycleChanged<TMediaProgress> onChanged,
  }) async {
    final progress = _state.scanProgress;
    if (_disposed || !_state.isScanning || progress == null) {
      return false;
    }
    final operationRevision = _scanOperationRevision;
    final paused = !progress.isPaused;
    _publishScanPaused(paused, onChanged);
    try {
      await setPaused(paused);
    } catch (_) {
      if (_isCurrentScan(operationRevision) &&
          _state.scanProgress?.generationId == progress.generationId) {
        _publishScanPaused(progress.isPaused, onChanged);
      }
      rethrow;
    }
    return true;
  }

  /**
   * 标记取消中并调用 Repository cancellation。
   *
   * 取消失败会恢复按钮状态；成功后保持“正在取消”，直到 [run] 的 Future 真正退出。
   */
  Future<bool> cancelScan({
    required Future<void> Function() cancel,
    required LibraryScanLifecycleChanged<TMediaProgress> onChanged,
  }) async {
    if (_disposed || !_state.isScanning || _state.isCancelling) {
      return false;
    }
    final operationRevision = _scanOperationRevision;
    _emit(
      LibraryScanLifecycleState<TMediaProgress>(
        isScanning: true,
        isCancelling: true,
        scanProgress: _state.scanProgress,
        mediaImportProgress: _state.mediaImportProgress,
      ),
      onChanged,
    );
    try {
      await cancel();
    } catch (_) {
      if (_isCurrentScan(operationRevision)) {
        _emit(
          LibraryScanLifecycleState<TMediaProgress>(
            isScanning: true,
            scanProgress: _state.scanProgress,
            mediaImportProgress: _state.mediaImportProgress,
          ),
          onChanged,
        );
      }
      rethrow;
    }
    return true;
  }

  /** 播放器让盘时同步镜像当前扫描暂停态，不重复发出 Repository 命令。 */
  void publishPlaybackPause({
    required bool paused,
    required LibraryScanLifecycleChanged<TMediaProgress> onChanged,
  }) {
    if (_disposed || !_state.isScanning || _state.scanProgress == null) {
      return;
    }
    _publishScanPaused(paused, onChanged);
  }

  /** 开始新的扫描后媒体解析 generation，并清空旧进度。 */
  int beginMediaImport({
    required LibraryScanLifecycleChanged<TMediaProgress> onChanged,
  }) {
    if (_disposed) {
      return -1;
    }
    final generation = ++_mediaImportGeneration;
    _emit(
      LibraryScanLifecycleState<TMediaProgress>(
        isScanning: _state.isScanning,
        isCancelling: _state.isCancelling,
        scanProgress: _state.scanProgress,
      ),
      onChanged,
    );
    return generation;
  }

  /** 只发布当前媒体解析 generation 的进度；完成后自动清空状态。 */
  void publishMediaImportProgress({
    required int generation,
    required TMediaProgress progress,
    required bool isComplete,
    required LibraryScanLifecycleChanged<TMediaProgress> onChanged,
  }) {
    if (_disposed || generation != _mediaImportGeneration) {
      return;
    }
    _emit(
      LibraryScanLifecycleState<TMediaProgress>(
        isScanning: _state.isScanning,
        isCancelling: _state.isCancelling,
        scanProgress: _state.scanProgress,
        mediaImportProgress: isComplete ? null : progress,
      ),
      onChanged,
    );
  }

  /** 释放所有排队发布；Repository 与媒体服务生命周期仍由组合它们的页面负责。 */
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _scanOperationRevision += 1;
    _pathImportRevision += 1;
    _mediaImportGeneration += 1;
    _activeScanGeneration = null;
    _state = const LibraryScanLifecycleState();
  }

  /** 当前操作仍可发布的统一判断。 */
  bool _isCurrentScan(int operationRevision) =>
      !_disposed &&
      _state.isScanning &&
      operationRevision == _scanOperationRevision;

  /** 保留其它生命周期字段并更新扫描暂停位。 */
  void _publishScanPaused(
    bool paused,
    LibraryScanLifecycleChanged<TMediaProgress> onChanged,
  ) {
    final progress = _state.scanProgress;
    if (progress == null) {
      return;
    }
    _emit(
      LibraryScanLifecycleState<TMediaProgress>(
        isScanning: _state.isScanning,
        isCancelling: _state.isCancelling,
        scanProgress: progress.copyWith(isPaused: paused),
        mediaImportProgress: _state.mediaImportProgress,
      ),
      onChanged,
    );
  }

  /** 保存新快照后通知页面；dispose 后不再触发回调。 */
  void _emit(
    LibraryScanLifecycleState<TMediaProgress> state,
    LibraryScanLifecycleChanged<TMediaProgress> onChanged,
  ) {
    if (_disposed) {
      return;
    }
    _state = state;
    onChanged(state);
  }
}
