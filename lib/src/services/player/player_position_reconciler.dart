// ignore_for_file: slash_for_doc_comments

/**
 * 在 seek 命令与后端位置事件之间维护一个短暂的目标栅栏。
 *
 * libmpv/media_kit 可能先返回 seek 命令，再把命令前已经排队的 `time-pos` 事件
 * 送到 Dart。若直接把这个旧位置当成当前状态，进度条和下一次相对 seek 都会回到
 * 旧落点。该类只处理播放器服务内的显示/读取一致性，不改变底层解码器的位置。
 */
class PlayerPositionReconciler {
  PlayerPositionReconciler({
    this.confirmationTolerance = const Duration(milliseconds: 750),
    this.confirmationTimeout = const Duration(seconds: 2),
    this.staleEventGrace = const Duration(milliseconds: 350),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration confirmationTolerance;
  final Duration confirmationTimeout;
  final Duration staleEventGrace;
  final DateTime Function() _now;

  Duration? _target;
  DateTime? _startedAt;
  DateTime? _confirmedAt;
  int _direction = 0;

  /** 当前是否仍在等待 seek 目标附近的位置事件。 */
  bool get isPending => _target != null;

  /** 当前 seek 目标；仅用于诊断和测试，不作为新的命令来源。 */
  Duration? get target => _target;

  /** 开始新一代 seek，并让此前尚未交付的旧位置事件失效。 */
  void beginSeek({required Duration target, required Duration current}) {
    final delta = target - current;
    _target = target;
    _startedAt = _now();
    _confirmedAt = null;
    _direction = delta == Duration.zero
        ? 0
        : delta > Duration.zero
            ? 1
            : -1;
  }

  /** 媒体切换或服务释放时清掉上一媒体的目标栅栏。 */
  void reset() {
    _target = null;
    _startedAt = null;
    _confirmedAt = null;
    _direction = 0;
  }

  /**
   * 把后端位置转换为页面可见/可读取的位置。
   *
   * 目标附近的首个事件不会立即解除栅栏；短暂 grace 窗口用于吞掉同一 seek 前已
   * 排队的旧事件。超过确认超时仍未收到目标附近位置时才回退到后端实际值，避免
   * 播放器故障时永久卡在乐观目标。
   */
  Duration reconcile(Duration backendPosition) {
    final target = _target;
    final startedAt = _startedAt;
    if (target == null || startedAt == null) {
      return backendPosition;
    }

    final now = _now();
    final elapsed = now.difference(startedAt);
    final delta = backendPosition - target;
    final nearTarget = delta.abs() <= confirmationTolerance;
    final crossedTarget = _direction > 0
        ? backendPosition >= target
        : _direction < 0
            ? backendPosition <= target
            : nearTarget;

    final confirmedAt = _confirmedAt;
    if (confirmedAt != null) {
      final staleOpposite = _direction > 0
          ? backendPosition < target - confirmationTolerance
          : _direction < 0
              ? backendPosition > target + confirmationTolerance
              : !nearTarget;
      // 即使旧事件晚于 grace 窗口到达，只要仍处在 seek 目标的反方向，
      // 就继续屏蔽到本次确认超时；正常播放越过目标后可立即解除栅栏。
      if (staleOpposite && elapsed < confirmationTimeout) {
        return target;
      }
      if (now.difference(confirmedAt) < staleEventGrace) {
        return target;
      }
      reset();
      return backendPosition;
    }

    if (nearTarget || crossedTarget) {
      _confirmedAt = now;
      return target;
    }

    if (elapsed >= confirmationTimeout) {
      reset();
      return backendPosition;
    }

    // 在确认前保持用户刚提交的目标，避免旧位置把 UI 和下一次相对 seek 拉回去。
    return target;
  }
}
