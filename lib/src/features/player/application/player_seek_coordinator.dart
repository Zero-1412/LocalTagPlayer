import 'dart:async';

// ignore_for_file: slash_for_doc_comments

/** 向当前播放器提交绝对 seek 目标。 */
typedef PlayerSeekSubmit = Future<void> Function(Duration target);

/** 读取当前播放器位置或时长。 */
typedef PlayerSeekDurationReader = Duration Function();

/** 判断播放器页面是否已经进入退出流程。 */
typedef PlayerSeekExitReader = bool Function();

/** 发布一次已完成 seek 的端到端耗时。 */
typedef PlayerSeekLatencyListener = void Function(int milliseconds);

/** 等待节流或位置确认轮询；测试可注入即时等待以保持确定性。 */
typedef PlayerSeekDelay = Future<void> Function(Duration duration);

/**
 * 协调播放器页面的连续 seek，保证首次立即提交且后续只追踪最新目标。
 *
 * 相对快进/快退会基于尚未确认的最新目标继续累计。工作器始终串行调用后端，
 * 连续输入只按 [minimumDispatchInterval] 刷新最新目标，避免并发 seek 压垮解码器；
 * 用户停止输入后，最后一个精确目标仍会被提交。
 */
class PlayerSeekCoordinator {
  PlayerSeekCoordinator({
    required PlayerSeekSubmit submit,
    required PlayerSeekDurationReader readPosition,
    required PlayerSeekDurationReader readDuration,
    required PlayerSeekExitReader isExiting,
    required PlayerSeekLatencyListener onLatency,
    this.minimumDispatchInterval = const Duration(milliseconds: 80),
    this.confirmationPollInterval = const Duration(milliseconds: 25),
    this.confirmationTimeout = const Duration(seconds: 2),
    this.confirmationTolerance = const Duration(milliseconds: 750),
    PlayerSeekDelay? delay,
  })  : _submit = submit,
        _readPosition = readPosition,
        _readDuration = readDuration,
        _isExiting = isExiting,
        _onLatency = onLatency,
        _delay = delay ?? Future<void>.delayed;

  /** 两次后端命令的最短间隔；限制连续按键产生的解码压力。 */
  final Duration minimumDispatchInterval;

  /** 后端位置尚未接近目标时的轮询间隔。 */
  final Duration confirmationPollInterval;

  /** 单次 seek 等待后端位置反馈的最长时间。 */
  final Duration confirmationTimeout;

  /** 后端位置落在该范围内即视为目标已经响应。 */
  final Duration confirmationTolerance;

  final PlayerSeekSubmit _submit;
  final PlayerSeekDurationReader _readPosition;
  final PlayerSeekDurationReader _readDuration;
  final PlayerSeekExitReader _isExiting;
  final PlayerSeekLatencyListener _onLatency;
  final PlayerSeekDelay _delay;

  Duration? _pendingTarget;
  Duration? _latestRequestedTarget;
  Future<void>? _worker;
  var _running = false;

  /** 连续输入尚未落稳时的最新累计目标。 */
  Duration? get latestRequestedTarget => _latestRequestedTarget;

  /** 当前是否已有串行 seek 工作器。 */
  bool get isRunning => _running;

  /**
   * 请求绝对跳转到 [target]。
   *
   * 第一项请求在当前调用轮次立即送入后端；工作器繁忙时只替换待提交目标，
   * 调用方等待返回的 Future 即可确认这一轮最终目标已经处理完毕。
   */
  Future<void> request(Duration target) {
    if (_isExiting()) {
      return Future<void>.value();
    }
    final normalized = _clamp(target);
    _latestRequestedTarget = normalized;
    _pendingTarget = normalized;
    if (_running) {
      return _worker!;
    }
    _running = true;
    return _worker = _run();
  }

  /**
   * 在后端位置可能滞后时累计相对 [delta]，并返回同一串行工作器。
   */
  Future<void> requestRelative(Duration delta) {
    final base = _latestRequestedTarget ?? _readPosition();
    return request(base + delta);
  }

  /** 退出或切换生命周期开始时取消尚未提交的 seek，不中断正在执行的后端命令。 */
  void cancelPending() {
    _pendingTarget = null;
    _latestRequestedTarget = null;
  }

  Future<void> _run() async {
    Stopwatch? sinceLastDispatch;
    try {
      while (!_isExiting() && _pendingTarget != null) {
        final elapsed = sinceLastDispatch?.elapsed;
        if (elapsed != null && elapsed < minimumDispatchInterval) {
          // 等待期间新输入继续覆盖 _pendingTarget；到点后读取的始终是最新累计位置。
          await _delay(minimumDispatchInterval - elapsed);
        }
        if (_isExiting()) {
          break;
        }
        final requested = _pendingTarget;
        if (requested == null) {
          continue;
        }
        _pendingTarget = null;
        final latency = Stopwatch()..start();
        await _submit(requested);
        sinceLastDispatch = Stopwatch()..start();

        final confirmation = Stopwatch()..start();
        while (!_isExiting() && confirmation.elapsed < confirmationTimeout) {
          // 新目标不等待旧画面落稳，下一轮按节流间隔直接推进到最新目标。
          if (_pendingTarget != null) {
            break;
          }
          if ((_readPosition() - requested).abs() <= confirmationTolerance) {
            break;
          }
          await _delay(confirmationPollInterval);
        }
        latency.stop();
        _onLatency(latency.elapsedMilliseconds);
      }
    } finally {
      _running = false;
      _latestRequestedTarget = null;
    }
  }

  Duration _clamp(Duration target) {
    if (target < Duration.zero) {
      return Duration.zero;
    }
    final duration = _readDuration();
    if (duration > Duration.zero && target > duration) {
      return duration;
    }
    return target;
  }
}
