import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/playback_settings.dart';

// ignore_for_file: slash_for_doc_comments

/** 播放设置持久化命令。 */
typedef SavePlaybackSettings = Future<void> Function(
  PlaybackSettings settings,
);

/**
 * 普通播放设置的一致性 owner。
 *
 * controller 只拥有 [PlaybackSettings] 与串行持久化顺序，不持有 `BuildContext`、Route、
 * 备份状态、缓存任务或平台资源。每次更新会立即发布给 UI；写入失败时，只有该更新仍是
 * 最新可见版本才回滚，防止旧请求覆盖用户随后完成的新修改。
 */
class PlaybackSettingsController extends ChangeNotifier {
  PlaybackSettingsController({
    required PlaybackSettings initialSettings,
    required SavePlaybackSettings save,
  })  : _settings = initialSettings,
        _persistedSettings = initialSettings,
        _save = save;

  PlaybackSettings _settings;
  PlaybackSettings _persistedSettings;
  final SavePlaybackSettings _save;
  Future<void> _writeTail = Future<void>.value();
  var _revision = 0;
  var _disposed = false;

  /** 当前已接受的播放设置快照。 */
  PlaybackSettings get settings => _settings;

  /** 当前设置请求版本，供调用方抑制已经过期的局部错误提示。 */
  int get revision => _revision;

  /**
   * 乐观发布并按调用顺序持久化新的完整设置。
   *
   * 返回的 Future 只代表本次写入；调用方可据此展示具体错误。串行队列会吞掉前一项错误后
   * 继续后续写入，避免一次磁盘失败永久阻断设置保存。
   */
  Future<void> update(PlaybackSettings next) {
    final requestRevision = ++_revision;
    _settings = next;
    _notifyIfActive();

    final operation = _writeTail.then((_) async {
      await _save(next);
      // 串行写入成功后才推进可回滚基线，不能使用尚未落盘的乐观快照。
      _persistedSettings = next;
    });
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        // 旧写入失败不能回滚更晚的用户修改。
        if (requestRevision == _revision && identical(_settings, next)) {
          _settings = _persistedSettings;
          _notifyIfActive();
        }
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

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
