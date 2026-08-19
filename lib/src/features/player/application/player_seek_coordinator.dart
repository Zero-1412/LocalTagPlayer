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

/** 报告 native seek 失败或超时；协调器不会把异常泄漏到 unawaited worker。 */
typedef PlayerSeekFailureListener = void Function(Object error);

/** 等待节流或位置确认轮询；测试可注入即时等待以保持确定性。 */
typedef PlayerSeekDelay = Future<void> Function(Duration duration);

/** 读取用户保留的音量值；临时静音不得更改这个值。 */
typedef PlayerSeekVolumeReader = double Function();

/** 仅向后端下发瞬时音量，不更改 UI 或持久化设置。 */
typedef PlayerSeekVolumeCommand = Future<void> Function(double volume);

/** 读取用户当前选择的常规播放速度，临时快进结束后必须原样恢复。 */
typedef PlayerSeekPlaybackRateReader = double Function();

/** 仅作用于当前播放内核的临时速度命令，不写入用户播放设置。 */
typedef PlayerSeekPlaybackRateCommand = Future<void> Function(double rate);

/** 开启临时高速扫描呈现档位；实现必须自行保存原有属性。 */
typedef PlayerFastForwardScanStart = Future<void> Function(double rate);

/** 结束临时高速扫描呈现档位；实现必须恢复开始前的属性与真实倍速。 */
typedef PlayerFastForwardScanStop = Future<void> Function();

/** 读取 mpv 视频链路已交付的帧号。 */
typedef PlayerSeekFrameReader = Future<int?> Function();

/** 等待精确 seek 后有新视频帧交付的证据。 */
typedef PlayerSeekFrameWaiter = Future<bool> Function(
  int? previousFrame,
  Duration timeout,
);

/** 返回当前帧门禁使用的证据来源，供录屏回归排除估算帧号假阳性。 */
typedef PlayerSeekFrameEvidenceReader = String Function();

/** 返回当前输入会话已经分配的 trace id；没有会话时返回 null。 */
typedef PlayerSeekTraceIdReader = int? Function();

/**
 * 读取连续扫描阶段的匿名运行态快照。
 *
 * 只允许返回固定的 cache/decoder/VO/Texture 字段；实现不得放入路径、媒体标题、
 * 帧内容或用户设置。读取失败由调用方写成 unavailable，不能阻塞播放命令。
 */
typedef PlayerSeekTraceRuntimeSnapshotReader = FutureOr<Map<String, String>>
    Function();

/**
 * 将一次 seek 会话的关键节点写成可与录屏对齐的短 trace。
 *
 * `mono_us` 只用于比较会话内的真实间隔，避免系统时间校正污染结论；`wall_utc_us` /
 * `wall_utc_ms` 仅作为录屏启动日志的跨进程锚点，不能参与 QPC 延迟计算。保留毫秒字段
 * 兼容已有日志，新的桌面关联优先使用微秒字段。输出端由页面注入，业务层不依赖 Flutter
 * 的 `debugPrint`。
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

  /** 当前进程内的单调微秒，供 seek 与原生帧观测共用同一时间基准。 */
  int get monotonicMicroseconds => _monotonicClock.elapsedMicroseconds;

  int begin() => ++_nextTraceId;

  void mark(
    int? traceId,
    String stage, {
    Duration? target,
    int? previousFrame,
    int? frameNumber,
    int? waitMilliseconds,
    int? seekToFrameMicroseconds,
    bool? framePresented,
    String? frameEvidence,
    Map<String, String>? runtimeSnapshot,
  }) {
    final output = _output;
    if (traceId == null || output == null) return;
    final wallUtc = _wallClock().toUtc();
    final fields = <String>[
      'PLAYER_SEEK_TRACE',
      'trace=$traceId',
      'mono_us=${_monotonicClock.elapsedMicroseconds}',
      'wall_utc_us=${wallUtc.microsecondsSinceEpoch}',
      'wall_utc_ms=${wallUtc.millisecondsSinceEpoch}',
      'stage=$stage',
      if (target != null) 'target_ms=${target.inMilliseconds}',
      if (previousFrame != null) 'previous_frame=$previousFrame',
      if (frameNumber != null) 'frame_number=$frameNumber',
      if (waitMilliseconds != null) 'wait_ms=$waitMilliseconds',
      if (seekToFrameMicroseconds != null)
        'seek_to_frame_us=$seekToFrameMicroseconds',
      if (framePresented != null) 'frame_presented=$framePresented',
      if (frameEvidence != null) 'frame_evidence=$frameEvidence',
      if (runtimeSnapshot != null)
        for (final entry in runtimeSnapshot.entries)
          if (_isSafeTraceFieldName(entry.key))
            'snapshot_${entry.key}=${_sanitizeTraceFieldValue(entry.value)}',
    ];
    output(fields.join(' '));
  }

  static bool _isSafeTraceFieldName(String value) =>
      RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value);

  static String _sanitizeTraceFieldValue(String value) => value
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll('=', '_')
      .replaceAll(RegExp(r'[^A-Za-z0-9_.:+/\-]'), '_');
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
    PlayerSeekFailureListener? onFailure,
    this.minimumDispatchInterval = defaultMinimumDispatchInterval,
    this.confirmationPollInterval = const Duration(milliseconds: 25),
    this.confirmationTimeout = const Duration(seconds: 2),
    this.submitTimeout = const Duration(seconds: 10),
    this.confirmationTolerance = const Duration(milliseconds: 750),
    this.adaptiveThrottle,
    this.trace,
    this.readTraceId,
    this.readTraceRuntimeSnapshot,
    this.readPresentedFrame,
    this.readFrameEvidence,
    this.frameObservationTimeout = const Duration(seconds: 2),
    this.frameObservationPollInterval = const Duration(milliseconds: 16),
    PlayerSeekDelay? delay,
  })  : _submit = submit,
        _readPosition = readPosition,
        _readDuration = readDuration,
        _isExiting = isExiting,
        _onLatency = onLatency,
        _onFailure = onFailure,
        _delay = delay ?? Future<void>.delayed;

  final Duration minimumDispatchInterval;
  final Duration confirmationPollInterval;
  final Duration confirmationTimeout;
  /** 保护注入的 native submit；正式 PlayerService 会使用更早的服务级超时。 */
  final Duration submitTimeout;
  final Duration confirmationTolerance;
  final PlayerSeekGopAdaptiveThrottle? adaptiveThrottle;
  final PlayerSeekSubmit _submit;
  final PlayerSeekDurationReader _readPosition;
  final PlayerSeekDurationReader _readDuration;
  final PlayerSeekExitReader _isExiting;
  final PlayerSeekLatencyListener _onLatency;
  final PlayerSeekFailureListener? _onFailure;
  final PlayerSeekDelay _delay;
  final PlayerSeekTraceLogger? trace;
  final PlayerSeekTraceIdReader? readTraceId;
  /** Debug-only seek 分段快照；为空时命令路径完全不读取 mpv 运行态属性。 */
  final PlayerSeekTraceRuntimeSnapshotReader? readTraceRuntimeSnapshot;
  final PlayerSeekFrameReader? readPresentedFrame;
  final PlayerSeekFrameEvidenceReader? readFrameEvidence;
  final Duration frameObservationTimeout;
  final Duration frameObservationPollInterval;

  Duration? _pendingTarget;
  Duration? _latestRequestedTarget;
  Future<void>? _worker;
  Stopwatch? _sinceLastDispatch;
  var _frameObservationGeneration = 0;
  var _running = false;
  /** 串行化诊断属性读取，避免多个 seek 同时争用 NativePlayer。 */
  Future<void> _traceRuntimeSnapshotTail = Future<void>.value();
  final Set<Future<void>> _pendingFrameObservations = <Future<void>>{};

  Duration? get latestRequestedTarget => _latestRequestedTarget;
  bool get isRunning => _running;

  /** QA 用：等待已排队的运行态快照，不能作为播放命令的同步依赖。 */
  Future<void> flushTraceRuntimeSnapshots() async {
    while (_pendingFrameObservations.isNotEmpty) {
      await Future.wait<void>(List<Future<void>>.of(_pendingFrameObservations));
    }
    await _traceRuntimeSnapshotTail;
  }

  Future<void> request(Duration target) {
    if (_isExiting()) return Future<void>.value();
    final normalized = _clamp(target);
    // 新目标会让旧落点失效；后台首帧观测只保留当前最新目标，避免快速点击
    // 产生多个属性轮询器并争用同一条 native 播放链。
    _frameObservationGeneration++;
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
    _frameObservationGeneration++;
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
        final traceId = _traceIdForSeek();
        final seekStartMicroseconds = trace?.monotonicMicroseconds;
        trace?.mark(traceId, 'seek_submit_start', target: requested);
        Future<int?>? frameBeforeSeek;
        final frameReader = readPresentedFrame;
        if (trace != null && frameReader != null) {
          try {
            // 与 native seek 并行读取基线，不把一次属性查询串到命令前面。
            frameBeforeSeek = frameReader();
          } catch (_) {
            frameBeforeSeek = null;
          }
        }
        final latency = Stopwatch()..start();
        // 节流窗口从命令派发开始计算；后端已耗时超过窗口时，下一次最新目标
        // 应在命令返回后立即接续，不能把同一个窗口重复加在命令完成之后。
        _sinceLastDispatch = Stopwatch()..start();
        try {
          await _submit(requested).timeout(submitTimeout);
        } catch (error) {
          trace?.mark(
            traceId,
            'seek_command_failed',
            target: requested,
            waitMilliseconds: latency.elapsedMilliseconds,
          );
          _pendingTarget = null;
          try {
            _onFailure?.call(error);
          } catch (_) {
            // 失败诊断是旁路回调，不能把 native 命令异常重新抛回 worker。
          }
          // 当前命令失败时丢弃同一输入批次的 pending 目标；下一次用户输入
          // 仍可重新建立 worker，避免在服务已封锁后忙循环重放旧目标。
          break;
        }
        trace?.mark(
          traceId,
          'seek_command_complete',
          target: requested,
          waitMilliseconds: latency.elapsedMilliseconds,
        );
        _markTraceRuntimeSnapshot(
          traceId,
          'seek_command_complete',
          target: requested,
        );
        if (traceId != null && frameBeforeSeek != null) {
          final observation = _observePresentedFrame(
            traceId: traceId,
            target: requested,
            seekStartMicroseconds: seekStartMicroseconds,
            previousFrame: frameBeforeSeek,
            observationGeneration: _frameObservationGeneration,
          );
          _pendingFrameObservations.add(observation);
          unawaited(
            observation.then<void>(
              (_) => _pendingFrameObservations.remove(observation),
              onError: (_, __) {
                _pendingFrameObservations.remove(observation);
              },
            ),
          );
        }

        final confirmation = Stopwatch()..start();
        final confirmationEnabled = confirmationTimeout > Duration.zero;
        if (confirmationEnabled) {
          trace?.mark(
            traceId,
            'position_confirmation_start',
            target: requested,
          );
        }
        var confirmationOutcome = 'timeout';
        while (!_isExiting() && confirmation.elapsed < confirmationTimeout) {
          // 新目标不等待旧画面落稳；下一轮按最新目标继续预览。
          if (_pendingTarget != null) {
            confirmationOutcome = 'superseded';
            break;
          }
          if ((_readPosition() - requested).abs() <= confirmationTolerance) {
            confirmationOutcome = 'complete';
            break;
          }
          await _delay(confirmationPollInterval);
        }
        if (confirmationEnabled) {
          final confirmationStage = switch (confirmationOutcome) {
            'complete' => 'position_confirmation_complete',
            'superseded' => 'position_confirmation_superseded',
            _ => 'position_confirmation_timeout',
          };
          trace?.mark(
            traceId,
            confirmationStage,
            target: requested,
            waitMilliseconds: confirmation.elapsedMilliseconds,
          );
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

  int? _traceIdForSeek() {
    final trace = this.trace;
    if (trace == null) return null;
    return readTraceId?.call() ?? trace.begin();
  }

  /**
   * 在命令返回后异步等待首个新帧；它不阻塞 coordinator 的下一次 latest-only 派发。
   * `mono_us` 与 `seek_to_frame_us` 都由同一个 Dart Stopwatch 生成，不能与 wall clock 混算。
   */
  Future<void> _observePresentedFrame({
    required int traceId,
    required Duration target,
    required int? seekStartMicroseconds,
    required Future<int?> previousFrame,
    required int observationGeneration,
  }) async {
    final frameReader = readPresentedFrame;
    final trace = this.trace;
    if (frameReader == null || trace == null) return;
    int? previous;
    try {
      previous = await previousFrame;
    } catch (_) {
      previous = null;
    }
    final watch = Stopwatch()..start();
    while (!_isExiting() &&
        observationGeneration == _frameObservationGeneration &&
        watch.elapsed < frameObservationTimeout) {
      int? current;
      try {
        current = await frameReader();
      } catch (_) {
        current = null;
      }
      if (current != null &&
          (previous == null || current != previous) &&
          observationGeneration == _frameObservationGeneration) {
        final evidence = readFrameEvidence?.call();
        final observedAt = trace.monotonicMicroseconds;
        trace.mark(
          traceId,
          evidence == 'native-rendered-texture'
              ? 'native_rendered_frame'
              : 'presented_frame_fallback',
          target: target,
          frameNumber: current,
          seekToFrameMicroseconds: seekStartMicroseconds == null
              ? null
              : observedAt - seekStartMicroseconds,
          frameEvidence: evidence,
        );
        _markTraceRuntimeSnapshot(
          traceId,
          evidence == 'native-rendered-texture'
              ? 'native_rendered_frame'
              : 'presented_frame_fallback',
          target: target,
        );
        return;
      }
      await _delay(frameObservationPollInterval);
    }
    if (observationGeneration == _frameObservationGeneration && !_isExiting()) {
      trace.mark(
        traceId,
        'native_rendered_frame_timeout',
        target: target,
        previousFrame: previous,
        waitMilliseconds: watch.elapsedMilliseconds,
        frameEvidence: readFrameEvidence?.call(),
      );
      _markTraceRuntimeSnapshot(
        traceId,
        'native_rendered_frame_timeout',
        target: target,
      );
    }
  }

  /**
   * 在后台读取一次固定运行态字段，切开命令完成、实际帧和 timeout 的根因。
   *
   * 这是 Debug-only 诊断旁路：读取失败写成 unavailable，且不等待它完成再派发下一次
   * seek。所有读取经同一尾链串行，避免诊断本身制造 NativePlayer 属性竞争。
   */
  void _markTraceRuntimeSnapshot(
    int? traceId,
    String stage, {
    required Duration target,
  }) {
    final reader = readTraceRuntimeSnapshot;
    final trace = this.trace;
    if (traceId == null || reader == null || trace == null) return;
    _traceRuntimeSnapshotTail = _traceRuntimeSnapshotTail.then<void>((_) async {
      Map<String, String> snapshot;
      try {
        snapshot = await Future<Map<String, String>>.value(reader())
            .timeout(const Duration(milliseconds: 500));
      } catch (_) {
        snapshot = const <String, String>{'status': 'unavailable'};
      }
      trace.mark(
        traceId,
        '${stage}_runtime',
        target: target,
        runtimeSnapshot: snapshot,
      );
    }, onError: (_, __) {});
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

  /**
   * 连续反向预览使用的单帧等待；只观测新帧，不改变静音会话或播放意图。
   *
   * 快退不能使用 mpv 的负向播放时钟，若在上一帧尚未送达时继续 latest-only seek，
   * Texture 往往只在松键后的最后一个目标才出现新画面。把等待暴露给同一音频门，
   * 可以让反向预览按“提交一个目标 → 等一帧 → 合并下一个目标”推进，仍不把音频提前恢复。
   */
  Future<bool> waitForPresentedFrame(
    int? previousFrame,
    Duration timeout,
  ) {
    if (!_active || _isExiting()) return Future<bool>.value(false);
    return _waitForNewFrame(previousFrame, timeout);
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
 * 持有一次物理快进/快退按键的累计目标与 KeyUp 预览收敛。
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
    this.deferInitialPreviewUntilRelease = false,
    this.readPlaybackRate,
    this.setTemporaryPlaybackRate,
    this.beginFastForwardScan,
    this.endFastForwardScan,
    this.readScanTraceSnapshot,
    this.smoothForwardScanMinimumRate = 2,
    this.reversePreviewFrameTimeout = const Duration(milliseconds: 320),
    this.reversePreviewMinimumDwell = const Duration(milliseconds: 120),
  })  : _coordinator = coordinator,
        _readPosition = readPosition,
        _readDuration = readDuration,
        _isExiting = isExiting,
        _onLatency = onLatency,
        assert(smoothForwardScanMinimumRate > 1);

  final PlayerSeekCoordinator _coordinator;
  final PlayerSeekDurationReader _readPosition;
  final PlayerSeekDurationReader _readDuration;
  final PlayerSeekExitReader _isExiting;
  final PlayerSeekLatencyListener _onLatency;
  final PlayerSeekAudioGate? previewAudioGate;
  final PlayerSeekTraceLogger? trace;

  /**
   * 页面级键盘输入会在确认短按前延后首个关键帧 seek。
   *
   * 长按的第一个系统 KeyRepeat 到达前不能知道用户意图；若一开始就随机 seek，后续
   * 再切到连续快进仍会留下可感知的解码停顿。测试和其它调用方可维持旧的立即预览。
   */
  final bool deferInitialPreviewUntilRelease;

  /** 以下两个回调同时存在时，物理长按“前进”使用连续高速播放而非重复随机 seek。 */
  final PlayerSeekPlaybackRateReader? readPlaybackRate;
  final PlayerSeekPlaybackRateCommand? setTemporaryPlaybackRate;

  /** 可选的专用高速扫描档位；负责暂时放松高倍速下的渲染限制并完整恢复。 */
  final PlayerFastForwardScanStart? beginFastForwardScan;
  final PlayerFastForwardScanStop? endFastForwardScan;

  /** Debug-only 连续扫描分段采样；为空时保持生产路径零额外属性读取。 */
  final PlayerSeekTraceRuntimeSnapshotReader? readScanTraceSnapshot;

  /**
   * 反向 latest-only 预览每个目标最多等待一帧的时间。
   *
   * 该等待只作用于连续快退；短按仍沿用原有一次关键帧命令，避免把精确定位的
   * 音频门或普通播放路径变成同步等待。
   */
  final Duration reversePreviewFrameTimeout;

  /**
   * 估算帧变化后仍给 Texture/DWM 留出的最短停留时间。
   *
   * 仅用于连续快退的 Debug/正式预览节奏；若没有该停留，KeyRepeat 的 70ms 节奏会在
   * Texture 合成前连续覆盖目标，导致桌面直到松键才出现新画面。
   */
  final Duration reversePreviewMinimumDwell;

  /**
   * 连续快进至少使用 2×，但不降低用户已经选择的更高常规速度。
   *
   * 2× 使常见 24/30fps 素材仍能在 60Hz 表面保持稳定视觉节奏；再高的速度由用户
   * 已选常规倍速保留，而不是强迫所有硬件在 Flutter Texture 上追逐 4× 解码。
   */
  final double smoothForwardScanMinimumRate;

  Duration? _target;
  Future<void>? _previewTail;
  Future<void>? _reversePreviewTail;
  Duration? _reversePendingTarget;
  var _reversePreviewUsed = false;
  Future<void>? _smoothForwardScanTail;
  Future<void> _smoothForwardScanSnapshotTail = Future<void>.value();
  double? _smoothForwardScanRestoreRate;
  double? _smoothForwardScanRate;
  int? _smoothForwardScanTraceId;
  var _smoothForwardScanActive = false;
  var _smoothForwardScanUsesProfile = false;
  var _generation = 0;

  bool get isActive => _target != null;
  Duration? get target => _target;
  bool get hasInteractivePreview => _previewTail != null;
  bool get isSmoothForwardScan => _smoothForwardScanActive;
  double? get activeSmoothForwardScanRate => _smoothForwardScanRate;

  bool get _canUseSmoothForwardScan {
    final hasProfile =
        beginFastForwardScan != null && endFastForwardScan != null;
    return readPlaybackRate != null &&
        (hasProfile || setTemporaryPlaybackRate != null);
  }

  /**
   * 键盘跳转始终先落到关键帧预览，KeyUp 只等待并收敛当前预览，避免同一次输入
   * 再次发起绝对精确 seek 重置解码链。
   *
   * 短按不静音；仅物理长按进入 KeyRepeat 后才打开临时静音。这样既保留普通方向键
   * 的连贯声音，也不会让长按期间的旧音频与关键帧预览错位。
   */
  Duration requestRelative(
    Duration delta, {
    bool submitPreview = true,
    bool mutePreview = true,
    bool isRepeat = false,
  }) {
    if (_isExiting()) return _readPosition();
    if (_smoothForwardScanActive) {
      // 连续快进期间不再累计虚假的随机目标；反馈读取真实播放时钟即可。
      return _readPosition();
    }
    if (_target == null) {
      _generation++;
      _reversePreviewUsed = false;
      _reversePendingTarget = null;
    }
    final duration = _readDuration();
    var next = (_target ?? _readPosition()) + delta;
    if (next < Duration.zero) {
      next = Duration.zero;
    } else if (duration > Duration.zero && next > duration) {
      next = duration;
    }
    _target = next;

    if (isRepeat && delta > Duration.zero && _canUseSmoothForwardScan) {
      _beginSmoothForwardScan();
      return next;
    }

    if (submitPreview) {
      // 只有页面级物理 KeyDown 允许延后：短按会在 KeyUp 提交一次，长按则在
      // 首个 KeyRepeat 直接进入连续播放，避免先随机 seek 再切倍速的双重抖动。
      if (!deferInitialPreviewUntilRelease || isRepeat) {
        if (isRepeat && delta < Duration.zero) {
          // 反向播放时不能依赖负向 mpv 时钟；每个目标等到上一帧有机会进入
          // Texture 后再继续，避免一串随机 seek 把所有中间画面吞掉。
          _submitReversePreview(next);
        } else {
          _submitPreview(next, mutePreview: mutePreview);
        }
      }
    }
    return next;
  }

  /** 提交当前 latest-only 关键帧目标；该分支只服务短按与快退长按。 */
  void _submitPreview(Duration target, {required bool mutePreview}) {
    final generation = _generation;
    final prepared = mutePreview
        ? previewAudioGate?.begin() ?? Future<void>.value()
        : Future<void>.value();
    _previewTail = prepared.then<void>((_) async {
      if (_isExiting() || generation != _generation) return;
      await _coordinator.request(target);
    });
    unawaited(_previewTail);
  }

  /**
   * 以最新目标合并、按帧让渡的连续反向预览。
   *
   * 该路径仍使用同一个 [PlayerSeekCoordinator] 和 [PlayerSeekAudioGate]，不创建第二
   * 个播放器或队列。新的 KeyRepeat 只替换尚未派发的目标；当前目标完成一次帧等待后
   * 才读取最新值，避免长 GOP 上的命令洪水让 DWM 直到 KeyUp 才看到画面。
   */
  void _submitReversePreview(Duration target) {
    _reversePreviewUsed = true;
    _reversePendingTarget = target;
    if (_reversePreviewTail != null) return;
    final generation = _generation;
    final run = _runReversePreview(generation);
    _reversePreviewTail = run;
    unawaited(run);
  }

  Future<void> _runReversePreview(int generation) async {
    try {
      final gate = previewAudioGate;
      await gate?.begin();
      while (!_isExiting() && generation == _generation) {
        final target = _reversePendingTarget;
        if (target == null) break;
        _reversePendingTarget = null;
        final previousFrame = await gate?.captureFinalFrame();
        final dwell = Stopwatch()..start();
        await _coordinator.request(target);
        if (gate != null &&
            !_isExiting() &&
            generation == _generation &&
            previousFrame != null) {
          final traceId = gate.activeTraceId ?? trace?.begin();
          trace?.mark(
            traceId,
            'reverse_preview_frame_wait_start',
            target: target,
            previousFrame: previousFrame,
          );
          final wait = Stopwatch()..start();
          final framePresented = await gate.waitForPresentedFrame(
            previousFrame,
            reversePreviewFrameTimeout,
          );
          wait.stop();
          trace?.mark(
            traceId,
            'reverse_preview_frame_wait_complete',
            target: target,
            waitMilliseconds: wait.elapsedMilliseconds,
            framePresented: framePresented,
          );
        }
        final remainingDwell = reversePreviewMinimumDwell - dwell.elapsed;
        if (remainingDwell > Duration.zero &&
            !_isExiting() &&
            generation == _generation) {
          await Future<void>.delayed(remainingDwell);
        }
      }
    } finally {
      _reversePreviewTail = null;
      // 输入事件可能恰好在 worker 读取 null 后到达；不要丢掉这一个最新目标。
      if (_reversePendingTarget != null &&
          generation == _generation &&
          !_isExiting()) {
        _submitReversePreview(_reversePendingTarget!);
      }
    }
  }

  /**
   * 首个 KeyRepeat 进入连续快进。
   *
   * mpv 的精确 seek 需要从前一关键帧解码，而连续播放可以保留解码器和 Texture
   * 时钟；这里不持久化倍速，也不改变短按/快退的既有随机跳转语义。
   */
  void _beginSmoothForwardScan() {
    if (_smoothForwardScanActive || _isExiting()) return;
    final readRate = readPlaybackRate;
    final setRate = setTemporaryPlaybackRate;
    final hasProfile =
        beginFastForwardScan != null && endFastForwardScan != null;
    if (readRate == null || (!hasProfile && setRate == null)) return;

    final generation = _generation;
    final restoreRate = readRate();
    final scanRate = restoreRate < smoothForwardScanMinimumRate
        ? smoothForwardScanMinimumRate
        : restoreRate;
    _smoothForwardScanActive = true;
    _smoothForwardScanUsesProfile =
        beginFastForwardScan != null && endFastForwardScan != null;
    _smoothForwardScanRestoreRate = restoreRate;
    _smoothForwardScanRate = scanRate;
    _target = null;
    _previewTail = null;
    // 只取消尚未派发的旧预览。已经进入 native 的命令仍由 PlayerService 串行收尾。
    _coordinator.cancelPending();
    // 连续扫描不是随机 seek；仍记录独立阶段，便于把实体键盘到桌面首帧的长尾拆成
    // 音频门、扫描档位下发和后续解码/VO/Texture 合成，而不是只看 KeyUp。
    final fallbackTraceId = previewAudioGate == null ? trace?.begin() : null;
    _smoothForwardScanTraceId = fallbackTraceId;
    _smoothForwardScanTail = () async {
      try {
        await (previewAudioGate?.begin() ?? Future<void>.value());
        final traceId = previewAudioGate?.activeTraceId ?? fallbackTraceId;
        _smoothForwardScanTraceId = traceId;
        _markSmoothScanStage(traceId, 'smooth_scan_start');
        if (_isExiting() ||
            generation != _generation ||
            !_smoothForwardScanActive) {
          return;
        }
        _markSmoothScanStage(traceId, 'smooth_scan_command_start');
        if (_smoothForwardScanUsesProfile) {
          await beginFastForwardScan!(scanRate);
        } else {
          await setRate!(scanRate);
        }
        _markSmoothScanStage(traceId, 'smooth_scan_command_complete');
      } catch (_) {
        final traceId = previewAudioGate?.activeTraceId ?? fallbackTraceId;
        _markSmoothScanStage(traceId, 'smooth_scan_command_failed');
        // 专用后端拒绝临时呈现档位时仍可安全退回普通倍速；不能重新回到连续随机 seek。
        if (_smoothForwardScanUsesProfile && setRate != null) {
          _smoothForwardScanUsesProfile = false;
          try {
            await setRate(scanRate);
            _markSmoothScanStage(traceId, 'smooth_scan_fallback_rate_complete');
          } catch (_) {
            // 临时快进失败时不影响用户原本的播放速度、队列或后续短按 seek。
          }
        }
      }
    }();
    unawaited(_smoothForwardScanTail!);
  }

  /**
   * KeyUp 结束当前输入会话，只收敛到已经提交的最新关键帧预览。
   *
   * 精确 seek 保留给进度条和继续观看等明确需要精确落点的入口；键盘快进/快退不在
   * 同一次输入中追加第二次绝对 seek。长按的音频只在预览帧推进后恢复。
   */
  Future<void> settlePreview() async {
    if (_smoothForwardScanActive) {
      await _finishSmoothForwardScan();
      return;
    }
    final finalTarget = _target;
    if (finalTarget == null || _isExiting()) return;
    final generation = _generation;
    final previewTail = _previewTail ?? _reversePreviewTail;
    final shouldFinishPreview = previewAudioGate?.isActive ?? false;
    final traceId = previewAudioGate?.activeTraceId ?? trace?.begin();
    trace?.mark(traceId, 'key_up', target: finalTarget);
    _target = null;
    _previewTail = null;
    var previewSubmitted = false;
    int? frameAfterPreview;
    try {
      final latency = Stopwatch()..start();
      // 物理短按在 KeyUp 才提交唯一的关键帧 seek；没有“预览后再精确”的第二跳。
      if (previewTail == null && !_reversePreviewUsed) {
        _submitPreview(finalTarget, mutePreview: false);
      }
      await (_previewTail ?? _reversePreviewTail ?? previewTail);
      latency.stop();
      if (_isExiting() || generation != _generation || _target != null) return;
      previewSubmitted = previewTail != null || _previewTail != null;
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
    final wasSmoothForwardScan = _smoothForwardScanActive;
    _generation++;
    _target = null;
    _previewTail = null;
    _reversePendingTarget = null;
    _reversePreviewUsed = false;
    _coordinator.cancelPending();
    if (wasSmoothForwardScan) {
      unawaited(_finishSmoothForwardScan().catchError((_) {}));
      return;
    }
    if (previewAudioGate?.isActive ?? false) {
      unawaited(
          previewAudioGate!.finish(waitForNewFrame: false).catchError((_) {}));
    }
  }

  /** 松键或取消时恢复用户速度与音量；不等待额外随机 seek 或帧确认。 */
  Future<void> _finishSmoothForwardScan() async {
    final restoreRate = _smoothForwardScanRestoreRate;
    final usesProfile = _smoothForwardScanUsesProfile;
    _smoothForwardScanActive = false;
    _smoothForwardScanUsesProfile = false;
    _smoothForwardScanRestoreRate = null;
    _smoothForwardScanRate = null;
    _target = null;
    _previewTail = null;
    final tail = _smoothForwardScanTail;
    _smoothForwardScanTail = null;
    final traceId =
        previewAudioGate?.activeTraceId ?? _smoothForwardScanTraceId;
    _smoothForwardScanTraceId = null;
    _markSmoothScanStage(traceId, 'smooth_scan_stop_start');
    try {
      if (tail != null) await tail;
      await _smoothForwardScanSnapshotTail;
      if (!_isExiting()) {
        if (usesProfile) {
          await endFastForwardScan!();
        } else {
          final setRate = setTemporaryPlaybackRate;
          if (restoreRate != null && setRate != null) {
            await setRate(restoreRate);
          }
        }
      }
      _markSmoothScanStage(traceId, 'smooth_scan_stop_complete');
      await _smoothForwardScanSnapshotTail;
    } finally {
      if (previewAudioGate?.isActive ?? false) {
        await previewAudioGate!.finish(waitForNewFrame: false);
      }
    }
  }

  /**
   * 将阶段标记与同一会话的运行态快照排队写出。
   *
   * 属性读取在独立尾链中串行执行，避免多个 `getProperty` Future 互相覆盖；播放命令
   * 不等待开始/完成快照，只有松键收尾时最多等待这条 Debug-only 尾链完成。
   */
  void _markSmoothScanStage(int? traceId, String stage) {
    trace?.mark(traceId, stage);
    final reader = readScanTraceSnapshot;
    if (traceId == null || trace == null || reader == null) return;
    _smoothForwardScanSnapshotTail =
        _smoothForwardScanSnapshotTail.then<void>((_) async {
      Map<String, String> snapshot;
      try {
        snapshot = await Future<Map<String, String>>.value(reader())
            .timeout(const Duration(milliseconds: 500));
      } catch (_) {
        snapshot = const <String, String>{'status': 'unavailable'};
      }
      trace?.mark(
        traceId,
        '${stage}_runtime',
        runtimeSnapshot: snapshot,
      );
    }, onError: (_, __) {});
  }
}
