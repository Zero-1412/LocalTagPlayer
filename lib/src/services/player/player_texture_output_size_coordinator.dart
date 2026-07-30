import 'dart:async';

import 'package:flutter/widgets.dart';

// ignore_for_file: slash_for_doc_comments

/** 向原生 VideoController 请求一个稳定 Texture 输出尺寸。 */
typedef PlayerTextureSizeRequest = Future<void> Function(Size size);

/**
 * 原生 Texture 输出尺寸协调器的只读状态。
 *
 * 状态不包含 Texture ID、窗口句柄或媒体路径，只用于诊断与性能门禁。
 */
class PlayerTextureOutputSizeSnapshot {
  const PlayerTextureOutputSizeSnapshot({
    required this.enabled,
    required this.state,
    required this.desiredSize,
    required this.requestedSize,
    required this.requestCount,
    required this.failureCount,
  });

  /** 当前会话是否允许动态调整原生 Texture。 */
  final bool enabled;

  /** 当前协调阶段。 */
  final String state;

  /** 最新布局经过稳定档位与滞回处理后的目标尺寸。 */
  final Size? desiredSize;

  /** 最近一次实际下发给原生插件的尺寸。 */
  final Size? requestedSize;

  /** 本会话向原生插件下发的尺寸请求数。 */
  final int requestCount;

  /** 请求异常或等待 Texture 回报超时的次数。 */
  final int failureCount;
}

/**
 * 把高频 Widget/DPI 变化收敛为少量稳定的原生 Texture 尺寸请求。
 *
 * `media_kit_video` 的 `setSize` 会注销旧 Texture、重建 D3D11/EGL 表面并注册新
 * Texture；因此本协调器使用固定档位、尾随去抖、最小请求间隔和实际尺寸确认，
 * 禁止把每个布局帧直接转成原生重建。
 */
class PlayerTextureOutputSizeCoordinator {
  PlayerTextureOutputSizeCoordinator({
    required this.enabled,
    required PlayerTextureSizeRequest requestSize,
    this.debounce = const Duration(milliseconds: 420),
    this.minimumRequestInterval = const Duration(milliseconds: 1100),
    this.confirmationTimeout = const Duration(milliseconds: 3000),
    DateTime Function()? now,
    void Function(PlayerTextureOutputSizeSnapshot snapshot)? onStateChanged,
  })  : _requestSize = requestSize,
        _now = now ?? DateTime.now,
        _onStateChanged = onStateChanged;

  /** 是否允许本会话调整原生 Texture；关闭时仅保留尺寸观测。 */
  final bool enabled;

  /** 用户停止缩放后等待多久再选择稳定档位。 */
  final Duration debounce;

  /** 两次原生 Texture 重建请求之间的最短间隔。 */
  final Duration minimumRequestInterval;

  /** 等待原生插件通过 `rect` 回报新 Texture 尺寸的最长时间。 */
  final Duration confirmationTimeout;

  /** 原生尺寸请求边界。 */
  final PlayerTextureSizeRequest _requestSize;

  /** 可注入时钟，便于确定性验证请求间隔。 */
  final DateTime Function() _now;

  /** 状态变化旁路，只允许更新匿名诊断。 */
  final void Function(PlayerTextureOutputSizeSnapshot snapshot)?
      _onStateChanged;

  /** 固定 16:9 档位保持现有 1920×1080 输出比例，不引入新的拉伸语义。 */
  static const List<Size> stableOutputSizes = <Size>[
    Size(640, 360),
    Size(960, 540),
    Size(1280, 720),
    Size(1600, 900),
    Size(1920, 1080),
  ];

  Timer? _timer;
  Size? _actualSize;
  Size? _desiredSize;
  Size? _lastRequestedSize;
  Size? _waitingForSize;
  DateTime? _lastRequestAt;
  DateTime? _waitingSince;
  var _requestCount = 0;
  var _failureCount = 0;
  var _requestInFlight = false;
  var _disposed = false;
  var _state = 'idle';

  /** 当前匿名协调状态。 */
  PlayerTextureOutputSizeSnapshot get snapshot =>
      PlayerTextureOutputSizeSnapshot(
        enabled: enabled,
        state: enabled ? _state : 'disabled',
        desiredSize: _desiredSize,
        requestedSize: _lastRequestedSize,
        requestCount: _requestCount,
        failureCount: _failureCount,
      );

  /**
   * 根据 BoxFit 后物理目标选择最小稳定档位。
   *
   * 候选预留约 8% 采样余量；向下切换还要求目标不超过候选的 90%，形成小范围滞回，
   * 避免窗口停在阈值附近时反复重建。放大请求立即选择能覆盖目标的更高档位。
   */
  static Size selectStableOutputSize({
    required Size fittedPhysicalTarget,
    Size? currentSize,
  }) {
    if (fittedPhysicalTarget.isEmpty ||
        !fittedPhysicalTarget.width.isFinite ||
        !fittedPhysicalTarget.height.isFinite) {
      return currentSize ?? stableOutputSizes.last;
    }
    final candidate = stableOutputSizes.firstWhere(
      (size) =>
          fittedPhysicalTarget.width * 1.08 <= size.width &&
          fittedPhysicalTarget.height * 1.08 <= size.height,
      orElse: () => stableOutputSizes.last,
    );
    if (currentSize != null &&
        candidate.width < currentSize.width &&
        (fittedPhysicalTarget.width > candidate.width * 0.90 ||
            fittedPhysicalTarget.height > candidate.height * 0.90)) {
      return currentSize;
    }
    return candidate;
  }

  /** 接收最新 BoxFit 物理目标；高频变化只保留最后一个稳定档位。 */
  void observeFittedPhysicalTarget(Size target) {
    if (_disposed) {
      return;
    }
    final selected = selectStableOutputSize(
      fittedPhysicalTarget: target,
      currentSize: _waitingForSize ?? _actualSize,
    );
    if (_desiredSize == selected) {
      return;
    }
    _desiredSize = selected;
    if (!enabled || _sameSize(_actualSize, selected)) {
      _state = 'idle';
      _notify();
      return;
    }
    _state = 'debouncing';
    _schedule(restartDebounce: true);
  }

  /**
   * 接收原生插件实际回报的 Texture 尺寸。
   *
   * 只有实际尺寸到达请求值后才解除等待，防止 MethodChannel 已返回但原生线程仍在
   * 注销旧 Texture 时继续排队下一次重建。
   */
  void recordActualTextureSize(Size size) {
    if (_disposed || size.isEmpty) {
      return;
    }
    _actualSize = size;
    if (_sameSize(_waitingForSize, size)) {
      _waitingForSize = null;
      _waitingSince = null;
      _state = 'idle';
    }
    _notify();
    if (enabled &&
        _desiredSize != null &&
        !_sameSize(_desiredSize, _actualSize) &&
        _waitingForSize == null) {
      _state = 'debouncing';
      _schedule(restartDebounce: false);
    }
  }

  /** 计算去抖、请求间隔与确认等待共同要求的下一次唤醒时间。 */
  void _schedule({required bool restartDebounce}) {
    if (_disposed || !enabled) {
      return;
    }
    _timer?.cancel();
    var delay = restartDebounce ? debounce : Duration.zero;
    final lastRequestAt = _lastRequestAt;
    if (lastRequestAt != null) {
      final remaining =
          minimumRequestInterval - _now().difference(lastRequestAt);
      if (remaining > delay) {
        delay = remaining;
      }
    }
    final waitingSince = _waitingSince;
    if (_waitingForSize != null && waitingSince != null) {
      final remaining = confirmationTimeout - _now().difference(waitingSince);
      if (remaining > delay) {
        delay = remaining;
      }
    }
    if (delay.isNegative) {
      delay = Duration.zero;
    }
    _timer = Timer(delay, () => unawaited(_flush()));
    _notify();
  }

  /** 下发最后一个稳定目标，并等待 `recordActualTextureSize` 确认完成。 */
  Future<void> _flush() async {
    _timer = null;
    if (_disposed || !enabled || _requestInFlight) {
      return;
    }
    final desired = _desiredSize;
    if (desired == null || _sameSize(desired, _actualSize)) {
      _state = 'idle';
      _notify();
      return;
    }
    final waitingSince = _waitingSince;
    if (_waitingForSize != null && waitingSince != null) {
      if (_now().difference(waitingSince) < confirmationTimeout) {
        _state = 'waiting-texture';
        _schedule(restartDebounce: false);
        return;
      }
      // 超时后不重试同一尺寸，防止插件异常时形成永久重建循环。
      _failureCount += 1;
      final timedOutSize = _waitingForSize;
      _waitingForSize = null;
      _waitingSince = null;
      _state = 'confirmation-timeout';
      _notify();
      if (_sameSize(timedOutSize, desired)) {
        return;
      }
    }

    _requestInFlight = true;
    _lastRequestedSize = desired;
    _waitingForSize = desired;
    _lastRequestAt = _now();
    _waitingSince = _lastRequestAt;
    _requestCount += 1;
    _state = 'requesting';
    _notify();
    try {
      await _requestSize(desired);
      if (_sameSize(_waitingForSize, desired)) {
        _state = 'waiting-texture';
      }
    } catch (_) {
      _failureCount += 1;
      if (_sameSize(_waitingForSize, desired)) {
        _waitingForSize = null;
        _waitingSince = null;
      }
      _state = 'request-failed';
    } finally {
      _requestInFlight = false;
      _notify();
    }
    if (_desiredSize != null &&
        !_sameSize(_desiredSize, _actualSize) &&
        _waitingForSize == null &&
        _state != 'request-failed') {
      _state = 'debouncing';
      _schedule(restartDebounce: false);
    }
  }

  /** 使用整数像素口径比较档位，忽略布局计算产生的亚像素差异。 */
  static bool _sameSize(Size? first, Size? second) =>
      first != null &&
      second != null &&
      first.width.round() == second.width.round() &&
      first.height.round() == second.height.round();

  /** 发布不含路径和原生句柄的状态。 */
  void _notify() => _onStateChanged?.call(snapshot);

  /** 取消尚未下发的去抖任务；原生资源仍由 PlayerBackend 按既有顺序释放。 */
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _state = 'disposed';
    _notify();
  }
}
