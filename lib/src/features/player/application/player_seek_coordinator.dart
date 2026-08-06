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

/** 读取用户保留的音量值；临时静音不得更改这个值。 */
typedef PlayerSeekVolumeReader = double Function();

/** 仅向后端下发瞬时音量，不更改 UI 或持久化设置。 */
typedef PlayerSeekVolumeCommand = Future<void> Function(double volume);

/** 读取 mpv 视频链路已交付的帧号。 */
typedef PlayerSeekFrameReader = Future<int?> Function();

/** 等待精确 seek 后有新视频帧交付的证据。 */
typedef PlayerSeekFrameWaiter = Future<bool> Function(
  int? previousFrame,
  Duration timeout,
);

/** 返回当前帧门禁使用的证据来源，供录屏回归排除估算帧号假阳性。 */
typedef PlayerSeekFrameEvidenceReader = String Function();

/**
 * 将一次 seek 会话的关键节点写成可与录屏对齐的短 trace。
 *
 * `mono_us` 只用于比较会话内的真实间隔，避免系统时间校正污染结论；`wall_utc_ms`
 * 仅作为录屏启动日志的跨进程锚点，不能参与延迟计算。输出端由页面注入，业务层不依赖
 * Flutter 的 `debugPrint`。
 */
typedef PlayerSeekTraceOutput = void Function(String line);

class PlayerSeekTraceLogger {
  PlayerSeekTraceLogger({
    PlayerSeekTraceOutput? output,
    Stopwatch? monotonicClock,
    DateTime Function()? wallClock,
  })  : _output = output,
        _monotonicClock = monotonicClock ?? (Stopwatch()..start()),
        _wallClock = wallClock ?? DateTime.now;

  final PlayerSeekTraceOutput? _output;
  final Stopwatch _monotonicClock;
  final DateTime Function() _wallClock;
  var _nextTraceId = 0;

  int begin() => ++_nextTraceId;

  void mark(
    int? traceId,
    String stage, {
    Duration? target,
    int? previousFrame,
    int? waitMilliseconds,
    bool? framePresented,
    String? frameEvidence,
  }) {
    final output = _output;
    if (traceId == null || output == null) return;
    final fields = <String>[
      'PLAYER_SEEK_TRACE',
      'trace=$traceId',
      'mono_us=${_monotonicClock.elapsedMicroseconds}',
      'wall_utc_ms=${_wallClock().toUtc().millisecondsSinceEpoch}',
      'stage=$stage',
      if (target != null) 'target_ms=${target.inMilliseconds}',
      if (previousFrame != null) 'previous_frame=$previousFrame',
      if (waitMilliseconds != null) 'wait_ms=$waitMilliseconds',
      if (framePresented != null) 'frame_presented=$framePresented',
      if (frameEvidence != null) 'frame_evidence=$frameEvidence',
    ];
    output(fields.join(' '));
  }
}

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
 * 长 GOP 不能在 UI 路径额外扫描文件；以当前会话关键帧 seek 的实际成本作代理。
 *
 * 12-case 门禁以长 GOP p95 校准三档阈值。快速样本保持约 15fps 预览；只有已经
 * 显示出解码压力的会话才降低到约 10fps 或 8fps，并相应延长最终新帧等待阈值。
 */
class PlayerSeekGopAdaptiveThrottle {
  static const _normalInterval = Duration(milliseconds: 64);
  static const _moderateInterval = Duration(milliseconds: 96);
  static const _longGopInterval = Duration(milliseconds: 125);
  static const _normalPresentationTimeout = Duration(milliseconds: 750);
  static const _moderatePresentationTimeout = Duration(milliseconds: 1200);
  static const _longGopPresentationTimeout = Duration(milliseconds: 1800);

  Duration _minimumDispatchInterval = _normalInterval;
  Duration _finalPresentationTimeout = _normalPresentationTimeout;

  Duration get minimumDispatchInterval => _minimumDispatchInterval;
  Duration get finalPresentationTimeout => _finalPresentationTimeout;

  /** 只为当前会话降速，低成本 seek 会立即回到默认预览频率。 */
  void recordPreviewLatency(int milliseconds) {
    if (milliseconds >= 350) {
      _minimumDispatchInterval = _longGopInterval;
      _finalPresentationTimeout = _longGopPresentationTimeout;
    } else if (milliseconds >= 160) {
      _minimumDispatchInterval = _moderateInterval;
      _finalPresentationTimeout = _moderatePresentationTimeout;
    } else if (milliseconds <= 80) {
      _minimumDispatchInterval = _normalInterval;
      _finalPresentationTimeout = _normalPresentationTimeout;
    }
  }
}

/**
 * 协调播放器页面的连续 seek：首次立即提交，后续 latest-only 合并且串行下发。
 *
 * 相对快进/快退以尚未确认的最新目标继续累计。长按期间按最小派发间隔刷新最近目标，
 * 避免并发 seek 压垮解码器；停止输入后仍会提交最终精确目标。
 */
class PlayerSeekCoordinator {
  /** 连续预览默认约 15fps，给解码器保留合并窗口。 */
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
    this.adaptiveThrottle,
    PlayerSeekDelay? delay,
  })  : _submit = submit,
        _readPosition = readPosition,
        _readDuration = readDuration,
        _isExiting = isExiting,
        _onLatency = onLatency,
        _delay = delay ?? Future<void>.delayed;

  final Duration minimumDispatchInterval;
  final Duration confirmationPollInterval;
  final Duration confirmationTimeout;
  final Duration confirmationTolerance;
  final PlayerSeekGopAdaptiveThrottle? adaptiveThrottle;
  final PlayerSeekSubmit _submit;
  final PlayerSeekDurationReader _readPosition;
  final PlayerSeekDurationReader _readDuration;
  final PlayerSeekExitReader _isExiting;
  final PlayerSeekLatencyListener _onLatency;
  final PlayerSeekDelay _delay;

  Duration? _pendingTarget;
  Duration? _latestRequestedTarget;
  Future<void>? _worker;
  Stopwatch? _sinceLastDispatch;
  var _running = false;

  Duration? get latestRequestedTarget => _latestRequestedTarget;
  bool get isRunning => _running;

  Future<void> request(Duration target) {
    if (_isExiting()) return Future<void>.value();
    final normalized = _clamp(target);
    _latestRequestedTarget = normalized;
    _pendingTarget = normalized;
    if (_running) return _worker!;
    _running = true;
    return _worker = _run();
  }

  Future<void> requestRelative(Duration delta) {
    final base = _latestRequestedTarget ?? _readPosition();
    return request(base + delta);
  }

  /** 只取消尚未派发的目标；不强行中断正在执行的后端命令。 */
  void cancelPending() {
    _pendingTarget = null;
    _latestRequestedTarget = null;
  }

  Future<void> _run() async {
    try {
      while (!_isExiting() && _pendingTarget != null) {
        final dispatchInterval = adaptiveThrottle?.minimumDispatchInterval ??
            minimumDispatchInterval;
        final elapsed = _sinceLastDispatch?.elapsed;
        if (elapsed != null && elapsed < dispatchInterval) {
          // 等待时的新输入只替换 pending 目标；到点读取的始终是最新累计位置。
          await _delay(dispatchInterval - elapsed);
        }
        if (_isExiting()) break;
        final requested = _pendingTarget;
        if (requested == null) continue;
        _pendingTarget = null;
        final latency = Stopwatch()..start();
        // 节流窗口从命令派发开始计算；后端已耗时超过窗口时，下一次最新目标
        // 应在命令返回后立即接续，不能把同一个窗口重复加在命令完成之后。
        _sinceLastDispatch = Stopwatch()..start();
        await _submit(requested);

        final confirmation = Stopwatch()..start();
        while (!_isExiting() && confirmation.elapsed < confirmationTimeout) {
          // 新目标不等待旧画面落稳；下一轮按最新目标继续预览。
          if (_pendingTarget != null) break;
          if ((_readPosition() - requested).abs() <= confirmationTolerance) {
            break;
          }
          await _delay(confirmationPollInterval);
        }
        latency.stop();
        adaptiveThrottle?.recordPreviewLatency(latency.elapsedMilliseconds);
        _onLatency(latency.elapsedMilliseconds);
      }
    } finally {
      _running = false;
      _latestRequestedTarget = null;
    }
  }

  Duration _clamp(Duration target) {
    if (target < Duration.zero) return Duration.zero;
    final duration = _readDuration();
    if (duration > Duration.zero && target > duration) return duration;
    return target;
  }
}

/**
 * 临时静音 seek 会话：不 pause/play，因此视频时钟与关键帧预览持续前进。
 *
 * 精确落点被确认后，必须获得 `estimated-frame-number` 变化的证据才恢复原音量。
 * 会话代号阻止已经取消的旧会话在新长按期间错误解除静音。
 */
class PlayerSeekAudioGate {
  PlayerSeekAudioGate({
    required PlayerSeekVolumeReader readDesiredVolume,
    required PlayerSeekVolumeCommand setVolume,
    required PlayerSeekFrameReader readPresentedFrame,
    required PlayerSeekFrameWaiter waitForNewFrame,
    required PlayerSeekDurationReader framePresentationTimeout,
    required PlayerSeekExitReader isExiting,
    this.readFrameEvidence,
    this.trace,
  })  : _readDesiredVolume = readDesiredVolume,
        _setVolume = setVolume,
        _readPresentedFrame = readPresentedFrame,
        _waitForNewFrame = waitForNewFrame,
        _framePresentationTimeout = framePresentationTimeout,
        _isExiting = isExiting;

  final PlayerSeekVolumeReader _readDesiredVolume;
  final PlayerSeekVolumeCommand _setVolume;
  final PlayerSeekFrameReader _readPresentedFrame;
  final PlayerSeekFrameWaiter _waitForNewFrame;
  final PlayerSeekDurationReader _framePresentationTimeout;
  final PlayerSeekExitReader _isExiting;
  final PlayerSeekFrameEvidenceReader? readFrameEvidence;
  final PlayerSeekTraceLogger? trace;

  Future<void> _tail = Future<void>.value();
  Future<void>? _prepared;
  var _active = false;
  var _restoreAudio = false;
  var _session = 0;
  int? _traceId;

  bool get isActive => _active;
  int? get activeTraceId => _active ? _traceId : null;

  /** 第一个预览命令前只下发音量 0；绝不暂停视频时钟。 */
  Future<void> begin() {
    if (_active) return _prepared ?? _tail;
    _active = true;
    _session++;
    _traceId = trace?.begin();
    _restoreAudio = !_isExiting() && _readDesiredVolume() > 0;
    if (!_restoreAudio) return _prepared = _tail;
    return _prepared = _enqueue(() => _setVolume(0));
  }

  /** 精确 seek 命令已完成后读取帧号，后续必须观察到不同帧号才允许解除静音。 */
  Future<int?> captureFinalFrame() async {
    await (_prepared ?? _tail);
    if (!_active || _isExiting()) return null;
    try {
      return await _readPresentedFrame();
    } catch (_) {
      return null;
    }
  }

  /** 单次精确 seek 的完整音频门顺序。 */
  Future<T> run<T>(Future<T> Function() operation) async {
    var completed = false;
    int? frameBeforeExact;
    try {
      await begin();
      final result = await operation();
      completed = true;
      // 基线必须在精确命令完成后取得，不能把命令执行期间仍在播放的预览帧当作最终落点。
      if (_restoreAudio) {
        frameBeforeExact = await captureFinalFrame();
      }
      return result;
    } finally {
      await finish(
        frameBeforeExact: frameBeforeExact,
        waitForNewFrame: completed,
      );
    }
  }

  /** cancel 可跳过已废弃落点的帧等待；正常 KeyUp 不可跳过。 */
  Future<void> finish({
    int? frameBeforeExact,
    bool waitForNewFrame = true,
  }) async {
    if (!_active) {
      await _tail;
      return;
    }
    _active = false;
    final session = _session;
    final traceId = _traceId;
    final shouldRestore = _restoreAudio;
    _restoreAudio = false;
    _prepared = null;
    _traceId = null;
    if (!shouldRestore || _isExiting()) {
      await _tail;
      return;
    }
    var framePresented = true;
    if (waitForNewFrame) {
      final frameWait = Stopwatch()..start();
      try {
        framePresented = await _waitForNewFrame(
          frameBeforeExact,
          _framePresentationTimeout(),
        );
      } catch (_) {
        framePresented = false;
      }
      frameWait.stop();
      trace?.mark(
        traceId,
        framePresented ? 'new_video_frame' : 'new_video_frame_timeout',
        previousFrame: frameBeforeExact,
        waitMilliseconds: frameWait.elapsedMilliseconds,
        framePresented: framePresented,
        frameEvidence: readFrameEvidence?.call(),
      );
    }
    // 没有新帧证据时不得播放旧落点的声音；下一次 seek 会重新建立一个安全会话。
    if (!framePresented) return;
    if (_isExiting() || _session != session || _active) return;
    trace?.mark(traceId, 'audio_restore_start');
    await _enqueue(() => _setVolume(_readDesiredVolume()));
    trace?.mark(traceId, 'audio_restore_complete');
  }

  Future<void> _enqueue(Future<void> Function() command) {
    _tail = _tail.catchError((_) {}).then((_) => command());
    return _tail;
  }
}

/**
 * 持有一次物理快进/快退按键的累计目标与 KeyUp 精确收敛。
 *
 * 连续 KeyRepeat 只经 coordinator 提交关键帧预览；目标始终基于本控制器累计位置，
 * 不读取可能落在前后关键帧的后端位置。新会话或取消会使旧 KeyUp 失效。
 */
class PlayerKeyboardSeekController {
  PlayerKeyboardSeekController({
    required PlayerSeekCoordinator coordinator,
    required PlayerSeekDurationReader readPosition,
    required PlayerSeekDurationReader readDuration,
    required PlayerSeekExitReader isExiting,
    required PlayerSeekLatencyListener onLatency,
    this.previewAudioGate,
    this.trace,
  })  : _coordinator = coordinator,
        _readPosition = readPosition,
        _readDuration = readDuration,
        _isExiting = isExiting,
        _onLatency = onLatency;

  final PlayerSeekCoordinator _coordinator;
  final PlayerSeekDurationReader _readPosition;
  final PlayerSeekDurationReader _readDuration;
  final PlayerSeekExitReader _isExiting;
  final PlayerSeekLatencyListener _onLatency;
  final PlayerSeekAudioGate? previewAudioGate;
  final PlayerSeekTraceLogger? trace;

  Duration? _target;
  Future<void>? _previewTail;
  var _generation = 0;

  bool get isActive => _target != null;
  Duration? get target => _target;
  bool get hasInteractivePreview => _previewTail != null;

  /**
   * 键盘跳转始终先落到关键帧预览，避免 KeyUp 再次绝对精确 seek 重置解码链。
   *
   * 短按不静音；仅物理长按进入 KeyRepeat 后才打开临时静音。这样既保留普通方向键
   * 的连贯声音，也不会让长按期间的旧音频与关键帧预览错位。
   */
  Duration requestRelative(
    Duration delta, {
    bool submitPreview = true,
    bool mutePreview = true,
  }) {
    if (_isExiting()) return _readPosition();
    if (_target == null) _generation++;
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
      final prepared = mutePreview
          ? previewAudioGate?.begin() ?? Future<void>.value()
          : Future<void>.value();
      _previewTail = prepared.then<void>((_) async {
        if (_isExiting() || generation != _generation) return;
        await _coordinator.request(next);
      });
      unawaited(_previewTail);
    }
    return next;
  }

  /**
   * KeyUp 只收敛到已经提交的最新关键帧，不补发 absolute 精确 seek。
   *
   * 最终精确定位保留给进度条提交路径；键盘快进/快退优先保证恢复连续播放。长按的
   * 音频只在该关键帧预览已经提交、并观察到后续帧推进后恢复，避免把预览帧当成稳定播放。
   */
  Future<void> settlePreview() async {
    final finalTarget = _target;
    if (finalTarget == null || _isExiting()) return;
    final generation = _generation;
    final previewTail = _previewTail;
    final shouldFinishPreview = previewAudioGate?.isActive ?? false;
    final traceId = previewAudioGate?.activeTraceId ?? trace?.begin();
    trace?.mark(traceId, 'key_up', target: finalTarget);
    _target = null;
    _previewTail = null;
    var previewSubmitted = false;
    int? frameAfterPreview;
    try {
      final latency = Stopwatch()..start();
      if (previewTail != null) await previewTail;
      latency.stop();
      if (_isExiting() || generation != _generation || _target != null) return;
      previewSubmitted = previewTail != null;
      trace?.mark(
        traceId,
        'keyframe_seek_complete',
        target: finalTarget,
        waitMilliseconds: latency.elapsedMilliseconds,
      );
      // 基线在最后一次关键帧命令完成后取得，确保等待的是恢复播放后的后续帧推进。
      frameAfterPreview = await previewAudioGate?.captureFinalFrame();
      _onLatency(latency.elapsedMilliseconds);
    } finally {
      if (shouldFinishPreview) {
        await previewAudioGate?.finish(
          frameBeforeExact: frameAfterPreview,
          waitForNewFrame: previewSubmitted,
        );
      }
    }
  }

  /** 取消尚未派发的预览，并立刻归还临时静音，不等待废弃目标的新帧。 */
  void cancel() {
    _generation++;
    _target = null;
    _previewTail = null;
    _coordinator.cancelPending();
    if (previewAudioGate?.isActive ?? false) {
      unawaited(
          previewAudioGate!.finish(waitForNewFrame: false).catchError((_) {}));
    }
  }
}
