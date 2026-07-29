import 'dart:async';

import 'package:flutter/foundation.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 备份服务状态流的唯一订阅 owner。
 *
 * controller 只保存最新状态并负责取消订阅，不读取数据库、不持有 `BuildContext`、Route
 * 或维护命令；dispose 后到达的事件不得通知 Widget。
 */
class DataBackupStatusController<T> extends ChangeNotifier {
  DataBackupStatusController({
    required T initialStatus,
    required Stream<T> statuses,
  }) : _status = initialStatus {
    _subscription = statuses.listen(_accept);
  }

  /** 当前最新备份状态。 */
  T _status;

  /** 由 Repository 暴露的只读状态订阅。 */
  late final StreamSubscription<T> _subscription;

  /** 页面释放后阻止排队事件发布。 */
  var _disposed = false;

  /** 当前最新备份状态。 */
  T get status => _status;

  /** 接受服务状态；dispose 后静默丢弃。 */
  void _accept(T status) {
    if (_disposed) {
      return;
    }
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

/** 启动一轮现有全量备份的应用命令。 */
typedef RunDataBackupNow = Future<void> Function();

/** 执行只读备份完整性检查的应用命令。 */
typedef CheckDataBackupIntegrity<T> = Future<T> Function();

/** 选择目标并导出备份；用户取消时返回 null。 */
typedef ExportDataBackup = Future<String?> Function();

/** 导出命令已实际启动后的结果；[path] 为 null 表示用户取消选择。 */
class DataBackupExportOutcome {
  const DataBackupExportOutcome({required this.path});

  /** 成功导出路径；取消选择时为 null，展示层不得输出该本地路径。 */
  final String? path;
}

/**
 * 备份维护命令的互斥 owner。
 *
 * controller 串行化立即备份、完整性检查和导出入口，但不实现数据库检查、文件选择或
 * 写入；这些能力仍由 Repository、应用服务和平台 adapter 完成。页面继续负责 Dialog
 * 与 SnackBar，不把 `BuildContext` 或 Route 传入 controller。
 */
class DataBackupMaintenanceController<TReport> extends ChangeNotifier {
  DataBackupMaintenanceController({
    required RunDataBackupNow runNow,
    required CheckDataBackupIntegrity<TReport> checkIntegrity,
    required ExportDataBackup export,
  })  : _runNow = runNow,
        _checkIntegrity = checkIntegrity,
        _export = export;

  /** 重置现有全量备份游标的命令。 */
  final RunDataBackupNow _runNow;

  /** 只读检查独立备份的命令。 */
  final CheckDataBackupIntegrity<TReport> _checkIntegrity;

  /** 通过平台 adapter 选择并写出便携备份的命令。 */
  final ExportDataBackup _export;

  /** 三类维护入口共用的互斥状态。 */
  var _busy = false;

  /** 页面释放后阻止新命令和完成通知。 */
  var _disposed = false;

  /** 当前是否已有备份维护命令执行。 */
  bool get busy => _busy;

  /** 启动现有全量备份；互斥或 dispose 时返回 false。 */
  Future<bool> runNow() async {
    if (!_begin()) {
      return false;
    }
    try {
      await _runNow();
      return true;
    } finally {
      _finish();
    }
  }

  /** 执行完整性检查；互斥或 dispose 时返回 null。 */
  Future<TReport?> checkIntegrity() async {
    if (!_begin()) {
      return null;
    }
    try {
      return await _checkIntegrity();
    } finally {
      _finish();
    }
  }

  /** 执行导出；未启动与用户取消通过外层/内层 null 区分。 */
  Future<DataBackupExportOutcome?> export() async {
    if (!_begin()) {
      return null;
    }
    try {
      return DataBackupExportOutcome(path: await _export());
    } finally {
      _finish();
    }
  }

  /** 原子取得互斥门禁并发布 busy。 */
  bool _begin() {
    if (_disposed || _busy) {
      return false;
    }
    _busy = true;
    notifyListeners();
    return true;
  }

  /** 释放互斥门禁；页面销毁后不再通知。 */
  void _finish() {
    _busy = false;
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
