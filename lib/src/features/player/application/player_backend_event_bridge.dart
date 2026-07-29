import 'dart:async';

// ignore_for_file: slash_for_doc_comments

/**
 * 页面消费播放器后端事件的单一订阅 owner。
 *
 * bridge 只绑定抽象 Stream 和回调，不依赖 Flutter、`PlayerService`、`PlayerBackend`
 * 或原生资源。页面仍解释 EOF、进度、错误和播放状态，bridge 只保证集中订阅与幂等取消。
 */
class PlayerBackendEventBridge {
  /**
   * 绑定当前播放器会话的四类后端事件。
   *
   * 回调由页面注入，因而不会把 `BuildContext`、Widget 状态或业务命令带入 bridge。
   */
  PlayerBackendEventBridge({
    required Stream<bool> completedChanges,
    required Stream<String> errorChanges,
    required Stream<Duration> positionChanges,
    required Stream<bool> playingChanges,
    required void Function(bool completed) onCompleted,
    required void Function(String code) onError,
    required void Function(Duration position) onPosition,
    required void Function(bool playing) onPlayingChanged,
  }) {
    _subscriptions.addAll(<StreamSubscription<dynamic>>[
      completedChanges.listen(onCompleted),
      errorChanges.listen(onError),
      positionChanges.listen(onPosition),
      playingChanges.listen(onPlayingChanged),
    ]);
  }

  /** 当前会话的全部事件订阅；必须在 backend dispose 前统一取消。 */
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  /** 首次 dispose 的共享 Future，防止并发释放形成第二条取消链。 */
  Future<void>? _disposeFuture;

  /** bridge 是否已经拒绝继续转发事件。 */
  var _disposed = false;

  /** 当前 bridge 是否已经进入释放阶段。 */
  bool get isDisposed => _disposed;

  /**
   * 幂等取消全部订阅。
   *
   * 调用方必须先等待本 Future，再 stop/dispose backend，避免流关闭与页面回调交错。
   */
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    _disposed = true;
    final future = Future.wait<void>(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    _disposeFuture = future;
    return future;
  }
}
