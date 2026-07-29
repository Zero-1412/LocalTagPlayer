import 'dart:async';

import 'package:flutter/foundation.dart';

// ignore_for_file: slash_for_doc_comments

/** 持久化一份完整设置快照的应用层命令。 */
typedef SaveSettings<T> = Future<void> Function(T settings);

/**
 * 单一设置快照的串行乐观一致性 owner。
 *
 * controller 立即发布用户选择，并按调用顺序持久化；只有最新请求失败时才回滚到最后
 * 成功快照。它不持有 `BuildContext`、Route、Widget、文件系统或平台资源。
 */
class SerialSettingsController<T> extends ChangeNotifier {
  SerialSettingsController({
    required T initialValue,
    required SaveSettings<T> save,
  })  : _value = initialValue,
        _persistedValue = initialValue,
        _save = save;

  /** 当前已接受并发布给 UI 的设置快照。 */
  T _value;

  /** 最近一次成功持久化的回滚基线。 */
  T _persistedValue;

  /** 由组合方注入的完整快照保存命令。 */
  final SaveSettings<T> _save;

  /** 保证磁盘写入与用户操作顺序一致的队列尾。 */
  Future<void> _writeTail = Future<void>.value();

  /** 当前设置请求版本，供调用方抑制过期局部错误。 */
  var _revision = 0;

  /** 页面释放后阻止异步完成通知。 */
  var _disposed = false;

  /** 当前已接受的设置快照。 */
  T get value => _value;

  /** 当前设置请求版本。 */
  int get revision => _revision;

  /** 乐观发布并串行持久化新的完整设置。 */
  Future<void> update(T next) {
    final requestRevision = ++_revision;
    _value = next;
    _notifyIfActive();

    final operation = _writeTail.then((_) async {
      await _save(next);
      // 只有真实保存成功的快照才能成为后续失败的回滚目标。
      _persistedValue = next;
    });
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        // 旧失败不得覆盖用户随后提交的新设置。
        if (requestRevision == _revision && identical(_value, next)) {
          _value = _persistedValue;
          _notifyIfActive();
        }
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  /** 仅在 controller 尚未释放时发布快照。 */
  void _notifyIfActive() {
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
