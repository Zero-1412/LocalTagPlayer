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

/** 读取当前媒体是否处于用户主动播放态。*/
typedef PlayerPlaybackIntentReader = bool Function();

/** 在不改变用户播放意图的前提下执行一次传输命令。*/
typedef PlayerPlaybackCommand = Future<void> Function();

/** 等待节流或位置确认轮询；测试可注入即时等待以保持确定性。 */
typedef PlayerSeekDelay = Future<void> Function(Duration duration);

/**
 * 把配置步长映射为长按重复阶段的小步长。
 *
 * 短按继续使用完整配置值；长按最多推进 5 秒，避免一个 64ms 预览窗口合并多个
 * KeyRepeat 后形成十几秒的画面硬跳。
 */
int playerKeyboardSeekRepeatStepSeconds(int configuredSeconds) {
  final softened = (configuredSeconds * 0.4).round();
  if (softened < 1) return 1;
  if (softened > 5) return 5;
  return softened;
}

/**
 * 协调播放器页面的连续 seek，保证首次立即提交且后续只追踪最新目标。
 *
 * 相对快进/快退会基于尚未确认的最新目标继续累计。工作器始终串行调用后端，
 * 连续输入只按 [minimumDispatchInterval] 刷新最新目标，避免并发 seek 压垮解码器；
 * 用户停止输入后，最后一个精确目标仍会被提交。
 */
class PlayerSeekCoordinator {
  /** 连续预览约 15fps；高于旧 80ms 节奏但仍给解码器保留合并窗口。 */
  static const defaultMinimumDispatchInterval = Duration(milliseconds: 64);

  PlayerSeekCoordinator({
    required PlayerSeekSubmit submit,
    required PlayerSeekDurationReader readPosition,
    required PlayerSeekDurationReader readDuration,
    required PlayerSeekExitReader isExiting,
    required PlayerSeekLatencyListener onLatency,
    this.minimumDispatchInterval = defaultMinimumDispatchInterval,
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
  /** 跨工作器保留最近一次提交间隔，避免长按重复事件在快速确认后绕过节流。 */
  Stopwatch? _sinceLastDispatch;
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
    try {
      while (!_isExiting() && _pendingTarget != null) {
        final elapsed = _sinceLastDispatch?.elapsed;
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
        _sinceLastDispatch = Stopwatch()..start();

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

/**
 * 拥有一次物理快进/快退按键的累计目标与 KeyUp 精确收敛。
 *
 * 连续 KeyRepeat 只经 [coordinator] 提交廉价关键帧预览；目标始终基于本控制器保存的
 * 逻辑位置累加，不读取可能落在前后关键帧的后端位置。新会话或取消会使旧 KeyUp 的
 * 迟到精确 seek 失效。
 */
/**
 * 在交互式或精确 seek 的解码窗口暂停播放，并在位置确认后恢复原本的播放意图。
 *
 * 它不修改用户音量、倍速或全局 mpv 音画同步配置：仅使快进预览期间不输出音频，防止旧关键帧
 * 的声音和最终落点混在一起。命令尾链保证旧会话的恢复与新会话的暂停按顺序下发。
 */
class PlayerSeekPlaybackGate {
  PlayerSeekPlaybackGate({
    required PlayerPlaybackIntentReader readPlaying,
    required PlayerPlaybackCommand pause,
    required PlayerPlaybackCommand play,
    required PlayerSeekExitReader isExiting,
  })  : _readPlaying = readPlaying,
        _pause = pause,
        _play = play,
        _isExiting = isExiting;

  final PlayerPlaybackIntentReader _readPlaying;
  final PlayerPlaybackCommand _pause;
  final PlayerPlaybackCommand _play;
  final PlayerSeekExitReader _isExiting;

  Future<void> _tail = Future<void>.value();
  Future<void>? _prepared;
  var _active = false;
  var _resumeAfterSeek = false;

  /** 是否已经占用一个 seek 的音频暂停窗口。*/
  bool get isActive => _active;

  /** 在第一个预览命令前暂停音频，并返回可供后续 seek 等待的屏障。*/
  Future<void> begin() {
    if (_active) {
      return _prepared ?? _tail;
    }
    _active = true;
    _resumeAfterSeek = !_isExiting() && _readPlaying();
    if (!_resumeAfterSeek) {
      return _prepared = _tail;
    }
    return _prepared = _enqueue(_pause);
  }

  /** 对单次精确 seek 保证“暂停 -> 落点确认 -> 恢复”的顺序。*/
  Future<T> run<T>(Future<T> Function() operation) async {
    try {
      await begin();
      return await operation();
    } finally {
      await finish();
    }
  }

  /** 只在进入窗口前本来处于播放态时恢复；用户原本暂停的媒体保持暂停。*/
  Future<void> finish() {
    if (!_active) {
      return _tail;
    }
    _active = false;
    final shouldResume = _resumeAfterSeek;
    _resumeAfterSeek = false;
    _prepared = null;
    if (!shouldResume || _isExiting()) {
      return _tail;
    }
    return _enqueue(_play);
  }

  /** 以可恢复的串行尾链下发后端命令，单次失败不会永久堵塞之后的用户交互。*/
  Future<void> _enqueue(PlayerPlaybackCommand command) {
    _tail = _tail.catchError((_) {}).then((_) => command());
    return _tail;
  }
}

class PlayerKeyboardSeekController {
  PlayerKeyboardSeekController({
    required PlayerSeekCoordinator coordinator,
    required PlayerSeekSubmit settle,
    required PlayerSeekDurationReader readPosition,
    required PlayerSeekDurationReader readDuration,
    required PlayerSeekExitReader isExiting,
    required PlayerSeekLatencyListener onLatency,
    this.previewPlaybackGate,
  })  : _coordinator = coordinator,
        _settle = settle,
        _readPosition = readPosition,
        _readDuration = readDuration,
        _isExiting = isExiting,
        _onLatency = onLatency;

  final PlayerSeekCoordinator _coordinator;
  final PlayerSeekSubmit _settle;
  final PlayerSeekDurationReader _readPosition;
  final PlayerSeekDurationReader _readDuration;
  final PlayerSeekExitReader _isExiting;
  final PlayerSeekLatencyListener _onLatency;
  /** 仅长按进入关键帧预览时占用，短按不会触发。*/
  final PlayerSeekPlaybackGate? previewPlaybackGate;

  Duration? _target;
  Future<void>? _previewTail;
  var _generation = 0;

  /** 当前物理按键会话是否尚未收到 KeyUp。 */
  bool get isActive => _target != null;

  /** 当前会话累计后的最终逻辑目标。 */
  Duration? get target => _target;

  /** 是否已经进入长按的关键帧预览路径。*/
  bool get hasInteractivePreview => _previewTail != null;

  /**
   * 基于当前会话目标累计 [delta]，并按需异步提交最新关键帧预览。
   *
   * 首个物理 KeyDown 传入 `submitPreview: false`，使短按只在 KeyUp 精确落点；
   * 只有系统产生 KeyRepeat，才表示进入长按并允许交互式预览占用解码器。
   */
  Duration requestRelative(
    Duration delta, {
    bool submitPreview = true,
  }) {
    if (_isExiting()) {
      return _readPosition();
    }
    if (_target == null) {
      _generation++;
    }
    final duration = _readDuration();
    var next = (_target ?? _readPosition()) + delta;
    if (next < Duration.zero) {
      next = Duration.zero;
    } else if (duration > Duration.zero && next > duration) {
      next = duration;
    }
    _target = next;
    if (submitPreview) {
      final generation = _generation;
      final prepared = previewPlaybackGate?.begin() ?? Future<void>.value();
      _previewTail = prepared.then<void>((_) async {
        // 暂停确认后才允许关键帧预览；被取消的旧会话不得越过此屏障发送滞后 seek。
        if (_isExiting() || generation != _generation) {
          return;
        }
        await _coordinator.request(next);
      });
      unawaited(_previewTail);
    }
    return next;
  }

  /** 等待最终预览命令返回，并只对仍有效的本轮目标执行一次精确 seek。 */
  Future<void> settle() async {
    final finalTarget = _target;
    if (finalTarget == null || _isExiting()) {
      return;
    }
    final generation = _generation;
    final previewTail = _previewTail;
    final shouldFinishPreview = previewPlaybackGate?.isActive ?? false;
    _target = null;
    _previewTail = null;
    try {
      if (previewTail != null) {
        await previewTail;
      }
      if (_isExiting() || generation != _generation || _target != null) {
        return;
      }
      final latency = Stopwatch()..start();
      await _settle(finalTarget);
      latency.stop();
      _onLatency(latency.elapsedMilliseconds);
    } finally {
      // 精确落点已确认或会话已取消后，才按原播放意图恢复音频。
      if (shouldFinishPreview) {
        await previewPlaybackGate?.finish();
      }
    }
  }

  /** 取消当前目标与待提交预览，并使上一轮迟到的精确收敛失效。 */
  void cancel() {
    _generation++;
    _target = null;
    _previewTail = null;
    _coordinator.cancelPending();
    if (previewPlaybackGate?.isActive ?? false) {
      // cancel 不会中断正在后端执行的寻帧，但仍要在其后恢复这一轮自动暂停。
      unawaited(previewPlaybackGate!.finish().catchError((_) {}));
    }
  }
}
