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
    this.onCompletedWithGeneration,
    this.onErrorWithGeneration,
    this.onPositionWithGeneration,
  }) {
    _completedChanges = completedChanges;
    _errorChanges = errorChanges;
    _positionChanges = positionChanges;
    _playingChanges = playingChanges;
    _onCompleted = onCompleted;
    _onError = onError;
    _onPosition = onPosition;
    _onPlayingChanged = onPlayingChanged;
    _bind(
      completedChanges: completedChanges,
      errorChanges: errorChanges,
      positionChanges: positionChanges,
      playingChanges: playingChanges,
      onCompleted: onCompleted,
      onError: onError,
      onPosition: onPosition,
      onPlayingChanged: onPlayingChanged,
    );
  }

  /** 重新绑定一个媒体代次，并让回调携带不可变的打开 generation。 */
  final void Function(bool completed, int generation)?
      onCompletedWithGeneration;
  final void Function(String code, int generation)? onErrorWithGeneration;
  final void Function(Duration position, int generation)?
      onPositionWithGeneration;

  late final Stream<bool> _completedChanges;
  late final Stream<String> _errorChanges;
  late final Stream<Duration> _positionChanges;
  late final Stream<bool> _playingChanges;
  late final void Function(bool completed) _onCompleted;
  late final void Function(String code) _onError;
  late final void Function(Duration position) _onPosition;
  late final void Function(bool playing) _onPlayingChanged;

  /** 当前会话的全部事件订阅；必须在 backend dispose 前统一取消。 */
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  /** 重绑与释放共用一条尾链，避免旧订阅取消和新订阅建立交错。 */
  Future<void> _bindingTail = Future<void>.value();

  /** 首次 dispose 的共享 Future，防止并发释放形成第二条取消链。 */
  Future<void>? _disposeFuture;

  /** bridge 是否已经拒绝继续转发事件。 */
  var _disposed = false;

  /** 当前 bridge 是否已经进入释放阶段。 */
  bool get isDisposed => _disposed;

  void _bind({
    required Stream<bool> completedChanges,
    required Stream<String> errorChanges,
    required Stream<Duration> positionChanges,
    required Stream<bool> playingChanges,
    required void Function(bool completed) onCompleted,
    required void Function(String code) onError,
    required void Function(Duration position) onPosition,
    required void Function(bool playing) onPlayingChanged,
    int? generation,
  }) {
    _subscriptions.addAll(<StreamSubscription<dynamic>>[
      completedChanges.listen((completed) {
        if (generation == null) {
          onCompleted(completed);
        } else {
          onCompletedWithGeneration?.call(completed, generation);
        }
      }),
      errorChanges.listen((code) {
        if (generation == null) {
          onError(code);
        } else {
          onErrorWithGeneration?.call(code, generation);
        }
      }),
      positionChanges.listen((position) {
        if (generation == null) {
          onPosition(position);
        } else {
          onPositionWithGeneration?.call(position, generation);
        }
      }),
      playingChanges.listen(onPlayingChanged),
    ]);
  }

  Future<void> _cancelSubscriptions() async {
    final subscriptions = List<StreamSubscription<dynamic>>.from(
      _subscriptions,
    );
    _subscriptions.clear();
    await Future.wait<void>(
      subscriptions.map((subscription) => subscription.cancel()),
    );
  }

  /**
   * 在新媒体成功可播放前切断旧媒体事件；新订阅只会把事件送入指定 generation。
   *
   * 打开期间页面不消费事件，成功后才发布稳定 videoId + generation，避免旧 EOF、
   * 位置或错误在媒体切换窗口里污染新队列项。
   */
  Future<void> rebind({required int generation}) {
    final operation = _bindingTail.then<void>((_) async {
      if (_disposed) return;
      await _cancelSubscriptions();
      if (_disposed) return;
      final onCompleted = onCompletedWithGeneration;
      final onError = onErrorWithGeneration;
      final onPosition = onPositionWithGeneration;
      if (onCompleted == null || onError == null || onPosition == null) {
        return;
      }
      _bind(
        completedChanges: _completedChanges,
        errorChanges: _errorChanges,
        positionChanges: _positionChanges,
        playingChanges: _playingChanges,
        onCompleted: _onCompleted,
        onError: _onError,
        onPosition: _onPosition,
        onPlayingChanged: _onPlayingChanged,
        generation: generation,
      );
    });
    _bindingTail = operation.then<void>(
      (_) {},
      onError: (_) {},
    );
    return operation;
  }

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
    final future = _bindingTail.then<void>((_) => _cancelSubscriptions());
    _disposeFuture = future;
    return future;
  }
}
