import 'dart:async';

import 'package:flutter/foundation.dart';

// ignore_for_file: slash_for_doc_comments

/** 播放器原生资源释放阶段的匿名诊断记录器。 */
typedef PlayerResourceStageLogger = Future<void> Function(
  String stage, {
  required bool readEngineProperties,
});

/**
 * Texture listener、backend stop/dispose/released 顺序的唯一协调 owner。
 *
 * coordinator 不取得 Player、NativePlayer、Texture、D3D11 或 HWND 句柄，只接收
 * `PlayerService` 暴露的抽象动作。页面可以继续发送播放命令，但不得再自行解绑纹理
 * listener 或调用 dispose/released，从而保证每个 Route 只有一条幂等释放链。
 */
class PlayerResourceLifecycleCoordinator {
  /**
   * 绑定当前播放器 Route 的资源动作。
   *
   * [cancelBackendEvents] 必须在 stop 前取消全部后端事件订阅；[onReleased] 只发送
   * Route 协调完成信号，不得再次释放资源。
   */
  PlayerResourceLifecycleCoordinator({
    required ValueListenable<int?> textureId,
    required Future<void> Function() cancelBackendEvents,
    required Future<void> Function() stop,
    required Future<void> Function() disposeResource,
    required Future<void> Function() awaitReleased,
    required PlayerResourceStageLogger logStage,
    required VoidCallback onTextureReady,
    required void Function(DateTime releaseStartedAt) onReleased,
    void Function(Object error)? onStopFailed,
  })  : _textureId = textureId,
        _cancelBackendEvents = cancelBackendEvents,
        _stop = stop,
        _disposeResource = disposeResource,
        _awaitReleased = awaitReleased,
        _logStage = logStage,
        _onTextureReady = onTextureReady,
        _onReleased = onReleased,
        _onStopFailed = onStopFailed {
    _textureId.addListener(_handleTextureReady);
    _handleTextureReady();
  }

  /** 只读纹理标识通知源；coordinator 是该诊断 listener 的唯一 owner。 */
  final ValueListenable<int?> _textureId;

  /** 释放前取消全部后端事件订阅。 */
  final Future<void> Function() _cancelBackendEvents;

  /** 停止当前媒体但不直接销毁底层资源。 */
  final Future<void> Function() _stop;

  /** 触发 PlayerService/PlayerBackend 的唯一 dispose 动作。 */
  final Future<void> Function() _disposeResource;

  /** 等待 Texture、D3D11/HWND 与引擎资源全部释放。 */
  final Future<void> Function() _awaitReleased;

  /** 不包含媒体路径的生命周期诊断记录器。 */
  final PlayerResourceStageLogger _logStage;

  /** 首个有效纹理出现时的诊断回调。 */
  final VoidCallback _onTextureReady;

  /** 完整释放后的 Route 协调回调。 */
  final void Function(DateTime releaseStartedAt) _onReleased;

  /** stop 超时或失败的安全诊断回调。 */
  final void Function(Object error)? _onStopFailed;

  /** 首个有效纹理只发布一次。 */
  var _textureReadyPublished = false;

  /** listener 解绑只执行一次。 */
  var _textureListenerDetached = false;

  /** stop 的共享 Future，避免退出兜底和 dispose 形成并发命令。 */
  Future<void>? _stopFuture;

  /** 完整释放的共享 Future，保证 dispose/released 只有一个调用 owner。 */
  Future<void>? _releaseFuture;

  /** 首个有效纹理 ID 到达时发布匿名阶段事件。 */
  void _handleTextureReady() {
    if (_textureReadyPublished || _textureId.value == null) {
      return;
    }
    _textureReadyPublished = true;
    _onTextureReady();
  }

  /** 幂等停止当前媒体，并留下可与 GPU 计数器对齐的阶段标记。 */
  Future<void> stopForExit() {
    final existing = _stopFuture;
    if (existing != null) {
      return existing;
    }
    return _stopFuture = _stopOnce();
  }

  Future<void> _stopOnce() async {
    try {
      await _stop().timeout(const Duration(seconds: 3));
      await _logStageSafely(
        'stop_acknowledged',
        readEngineProperties: true,
      );
    } catch (error) {
      _onStopFailed?.call(error);
    }
  }

  /**
   * 幂等释放当前 Route 的全部播放器资源。
   *
   * 顺序固定为：解绑 Texture listener → 取消事件订阅 → stop → dispose → released。
   * 任一步异常都必须发送最终完成信号，避免媒体库永久禁止下一次进入播放器。
   */
  Future<void> release() {
    final existing = _releaseFuture;
    if (existing != null) {
      return existing;
    }
    return _releaseFuture = _releaseOnce();
  }

  Future<void> _releaseOnce() async {
    final releaseStartedAt = DateTime.now();
    if (!_textureListenerDetached) {
      _textureListenerDetached = true;
      _textureId.removeListener(_handleTextureReady);
    }
    await _logStageSafely(
      'dispose_started',
      readEngineProperties: true,
    );
    try {
      try {
        await _cancelBackendEvents();
      } finally {
        await stopForExit();
        try {
          await _disposeResource();
        } finally {
          // 即使 dispose 抛错，也等待后端自己的 released 信号，避免遗留 HWND/Texture。
          await _awaitReleased();
        }
      }
    } finally {
      try {
        await _logStageSafely(
          'player_disposed',
          readEngineProperties: false,
        );
      } finally {
        _onReleased(releaseStartedAt);
      }
    }
  }

  /** 诊断写入失败不能中断真实资源释放顺序。 */
  Future<void> _logStageSafely(
    String stage, {
    required bool readEngineProperties,
  }) async {
    try {
      await _logStage(
        stage,
        readEngineProperties: readEngineProperties,
      );
    } catch (_) {
      // 生命周期诊断属于旁路观测；资源释放和 Route 完成信号优先。
    }
  }
}
