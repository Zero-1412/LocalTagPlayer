import 'dart:async';

// ignore_for_file: slash_for_doc_comments

/** 执行一次桌面窗口命令；具体 window manager 只允许由 presentation 注入。 */
typedef PlayerWindowCommand = Future<void> Function();

/** 查询桌面窗口当前是否处于系统全屏。 */
typedef PlayerWindowFullscreenQuery = Future<bool> Function();

/** 记录不应阻断播放器退出的窗口边界错误。 */
typedef PlayerWindowLifecycleErrorReporter = void Function(
  String code,
  Object error,
);

/**
 * 记录跨播放器 Route 保留的全屏会话偏好。
 *
 * 普通最大化不能创建全屏偏好；只有播放器实际处于全屏时退出，下一次进入才恢复。
 */
class PlayerFullscreenSessionController {
  bool _shouldOpenFullscreen = false;

  /** 新播放器 Route 是否需要恢复上一次播放器全屏状态。 */
  bool get shouldOpenFullscreen => _shouldOpenFullscreen;

  /** 记录用户在播放器内完成的全屏切换。 */
  void recordPlayerFullscreen(bool fullscreen) {
    _shouldOpenFullscreen = fullscreen;
  }

  /**
   * 判断返回前是否需要把系统窗口恢复为最大化。
   *
   * 从全屏返回时保留播放器偏好，非全屏返回则不改变窗口，也不凭空创建全屏偏好。
   */
  bool prepareForPlayerExit({required bool currentlyFullscreen}) {
    if (currentlyFullscreen) {
      _shouldOpenFullscreen = true;
    }
    return currentlyFullscreen;
  }
}

/**
 * 播放器 Route 内桌面全屏状态与窗口命令顺序的唯一 owner。
 *
 * controller 不持有 `BuildContext`、Route、Widget、window handle 或 PlayerBackend。
 * presentation 注入窗口命令和 `endOfFrame` 门禁，使 child HWND 在原生全屏前先看到
 * 顶栏卸载后的 Flutter 帧，同时保持状态机可独立测试。
 */
class PlayerFullscreenLifecycleController {
  /**
   * 创建当前播放器 Route 的全屏生命周期。
   *
   * [session] 跨 Route 保留用户全屏偏好；[onChanged] 只通知页面重绘，不执行窗口命令。
   */
  PlayerFullscreenLifecycleController({
    required PlayerFullscreenSessionController session,
    required void Function() onChanged,
  })  : _session = session,
        _onChanged = onChanged,
        _isFullscreen = session.shouldOpenFullscreen;

  /** 跨 Route 的全屏会话偏好。 */
  final PlayerFullscreenSessionController _session;

  /** 无上下文的 presentation 刷新回调。 */
  final void Function() _onChanged;

  /** 页面认为当前系统窗口是否处于全屏。 */
  bool _isFullscreen;

  /** 原生窗口命令执行前后用于卸载旧顶栏的短暂过渡状态。 */
  bool _transitionInProgress = false;

  /** 首帧后的会话恢复只允许启动一次。 */
  Future<void>? _restoreFuture;

  /** 当前页面全屏状态。 */
  bool get isFullscreen => _isFullscreen;

  /** 是否正在跨 Flutter/native 边界切换全屏。 */
  bool get transitionInProgress => _transitionInProgress;

  /**
   * 首帧后幂等恢复会话全屏。
   *
   * 恢复失败会清除跨 Route 偏好，并把当前页面回退为普通窗口；错误只用于诊断，
   * 不能阻断播放器继续使用。
   */
  Future<void> restoreSession({
    required PlayerWindowCommand enterFullscreen,
    required PlayerWindowLifecycleErrorReporter reportError,
  }) {
    final existing = _restoreFuture;
    if (existing != null) {
      return existing;
    }
    if (!_isFullscreen) {
      return _restoreFuture = Future<void>.value();
    }
    return _restoreFuture = _restoreSession(
      enterFullscreen: enterFullscreen,
      reportError: reportError,
    );
  }

  Future<void> _restoreSession({
    required PlayerWindowCommand enterFullscreen,
    required PlayerWindowLifecycleErrorReporter reportError,
  }) async {
    try {
      await enterFullscreen();
    } catch (error) {
      _session.recordPlayerFullscreen(false);
      _isFullscreen = false;
      _onChanged();
      reportError('restore_failed', error);
    }
  }

  /**
   * 串行切换桌面窗口全屏。
   *
   * [beforeWindowCommand] 由页面注入 `endOfFrame`，确保顶栏先卸载；原生命令失败时
   * 保留旧全屏状态并结束过渡，不产生错误的会话偏好。[canExecuteWindowCommand]
   * 在帧边界后重新检查 Route 是否仍挂载，拒绝迟到的原生窗口命令。
   */
  Future<void> toggle({
    required PlayerWindowCommand beforeWindowCommand,
    required bool Function() canExecuteWindowCommand,
    required Future<void> Function(bool fullscreen) setFullscreen,
  }) async {
    if (_transitionInProgress) {
      return;
    }
    final target = !_isFullscreen;
    _transitionInProgress = true;
    _onChanged();
    try {
      await beforeWindowCommand();
    } catch (_) {
      _transitionInProgress = false;
      _onChanged();
      rethrow;
    }
    if (!canExecuteWindowCommand()) {
      // Route 已卸载时只结束过渡，不执行迟到窗口命令或污染跨 Route 全屏偏好。
      _transitionInProgress = false;
      _onChanged();
      return;
    }
    try {
      await setFullscreen(target);
    } catch (_) {
      _transitionInProgress = false;
      _onChanged();
      rethrow;
    }
    _isFullscreen = target;
    _transitionInProgress = false;
    _session.recordPlayerFullscreen(target);
    _onChanged();
  }

  /**
   * 返回 Route 前等待恢复命令，并按插件实际状态决定是否退出全屏和最大化。
   *
   * `setWindowed` 或 `maximize` 失败只记录安全错误；资源释放和 Route 返回仍继续。
   */
  Future<void> prepareForExit({
    required PlayerWindowFullscreenQuery queryFullscreen,
    required PlayerWindowCommand setWindowed,
    required PlayerWindowCommand maximize,
    required PlayerWindowLifecycleErrorReporter reportError,
  }) async {
    await (_restoreFuture ?? Future<void>.value());
    var actuallyFullscreen = _isFullscreen;
    if (!actuallyFullscreen) {
      try {
        actuallyFullscreen = await queryFullscreen();
      } catch (_) {
        actuallyFullscreen = false;
      }
    }
    if (!_session.prepareForPlayerExit(
      currentlyFullscreen: actuallyFullscreen,
    )) {
      return;
    }
    try {
      await setWindowed();
    } catch (error) {
      reportError('exit_failed', error);
    }
    try {
      await maximize();
    } catch (error) {
      reportError('exit_maximize_failed', error);
    }
    _isFullscreen = false;
    _transitionInProgress = false;
    _onChanged();
  }
}
