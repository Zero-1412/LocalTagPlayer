import 'dart:async';

import '../../models/player_backend_telemetry.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 单个播放器后端实例的结构化遥测状态机。
 *
 * 该状态机只处理代次、去重和耗时计算，不访问 Player、NativePlayer 或本地路径，
 * 因而可以独立验证快速切换、错误统计和资源释放语义。
 */
class PlayerBackendTelemetryTracker {
  PlayerBackendTelemetryTracker({required String backendName})
      : _snapshot = PlayerBackendTelemetrySnapshot(
          backendName: backendName,
          supported: true,
          openGeneration: 0,
          openStartedAt: null,
          firstFrameAt: null,
          firstFrameLatency: null,
          firstFrameEvidence: null,
          hwdecCurrent: null,
          videoCodec: null,
          decoderCapturedAt: null,
          errorEventCount: 0,
          failedOpenCount: 0,
          lastFailedOpenGeneration: null,
          lastErrorCode: null,
          lastErrorAt: null,
          releasePhase: PlayerBackendReleasePhase.active,
          releaseStartedAt: null,
          releaseCompletedAt: null,
          playerDisposeDuration: null,
          nativeReleaseWait: null,
          totalReleaseDuration: null,
        );

  /** 当前不可变遥测快照。 */
  PlayerBackendTelemetrySnapshot _snapshot;

  /** 只向诊断与压测工具广播不含路径的结构化事件。 */
  final StreamController<PlayerBackendTelemetryEvent> _events =
      StreamController<PlayerBackendTelemetryEvent>.broadcast(sync: true);

  /** 当前不可变遥测快照。 */
  PlayerBackendTelemetrySnapshot get snapshot => _snapshot;

  /** 后端遥测事件流。 */
  Stream<PlayerBackendTelemetryEvent> get events => _events.stream;

  /**
   * 开始一个新的媒体打开代次并清空上一媒体的首帧与解码器字段。
   *
   * [at] 允许确定性测试注入时钟；生产调用省略时使用本地当前时间。
   */
  int beginOpen({DateTime? at}) {
    final occurredAt = at ?? DateTime.now();
    final generation = _snapshot.openGeneration + 1;
    _snapshot = _snapshot.copyWith(
      openGeneration: generation,
      openStartedAt: occurredAt,
      clearFirstFrameAt: true,
      clearFirstFrameLatency: true,
      clearFirstFrameEvidence: true,
      clearHwdecCurrent: true,
      clearVideoCodec: true,
      clearDecoderCapturedAt: true,
    );
    _emit(PlayerBackendTelemetryEventKind.openStarted, occurredAt);
    return generation;
  }

  /**
   * 记录当前打开代次的第一份视频帧证据。
   *
   * 过时代次和同代重复证据会被拒绝，防止快速切换时旧异步回调污染最新样本。
   */
  bool recordFirstFrame({
    required int generation,
    required String evidence,
    DateTime? at,
  }) {
    if (generation != _snapshot.openGeneration ||
        _snapshot.firstFrameAt != null ||
        _snapshot.openStartedAt == null) {
      return false;
    }
    final occurredAt = at ?? DateTime.now();
    final latency = occurredAt.difference(_snapshot.openStartedAt!);
    _snapshot = _snapshot.copyWith(
      firstFrameAt: occurredAt,
      firstFrameLatency: latency.isNegative ? Duration.zero : latency,
      firstFrameEvidence: evidence,
    );
    _emit(PlayerBackendTelemetryEventKind.firstFrame, occurredAt);
    return true;
  }

  /**
   * 记录当前媒体实际解码器。
   *
   * 空值保持未知；软件解码由后端归一化为 `no`，不能用用户请求值冒充实际结果。
   */
  bool recordDecoder({
    required int generation,
    String? hwdecCurrent,
    String? videoCodec,
    DateTime? at,
  }) {
    if (generation != _snapshot.openGeneration) {
      return false;
    }
    final occurredAt = at ?? DateTime.now();
    _snapshot = _snapshot.copyWith(
      hwdecCurrent: hwdecCurrent,
      clearHwdecCurrent: hwdecCurrent == null,
      videoCodec: videoCodec,
      clearVideoCodec: videoCodec == null,
      decoderCapturedAt: occurredAt,
    );
    _emit(PlayerBackendTelemetryEventKind.decoderResolved, occurredAt);
    return true;
  }

  /**
   * 记录一个安全错误分类码。
   *
   * 同一打开代次可以有多个底层错误事件，但只计为一次打开失败，供连续切换失败率使用。
   */
  void recordError(
    String code, {
    DateTime? at,
    bool affectsCurrentOpen = true,
  }) {
    final occurredAt = at ?? DateTime.now();
    final generation = _snapshot.openGeneration;
    final isNewFailedOpen = affectsCurrentOpen &&
        generation > 0 &&
        _snapshot.lastFailedOpenGeneration != generation;
    _snapshot = _snapshot.copyWith(
      errorEventCount: _snapshot.errorEventCount + 1,
      failedOpenCount: _snapshot.failedOpenCount + (isNewFailedOpen ? 1 : 0),
      lastFailedOpenGeneration:
          isNewFailedOpen ? generation : _snapshot.lastFailedOpenGeneration,
      lastErrorCode: code,
      lastErrorAt: occurredAt,
    );
    _emit(PlayerBackendTelemetryEventKind.error, occurredAt);
  }

  /** 标记开始释放当前后端实例。 */
  void beginRelease({DateTime? at}) {
    if (_snapshot.releasePhase != PlayerBackendReleasePhase.active) {
      return;
    }
    final occurredAt = at ?? DateTime.now();
    _snapshot = _snapshot.copyWith(
      releasePhase: PlayerBackendReleasePhase.releasing,
      releaseStartedAt: occurredAt,
    );
    _emit(PlayerBackendTelemetryEventKind.releaseStarted, occurredAt);
  }

  /**
   * 记录 Player dispose、原生宽限和完整释放耗时。
   *
   * 即使底层 dispose 抛错也应调用本方法，使等待方获得明确终态。
   */
  void completeRelease({
    required Duration playerDisposeDuration,
    required Duration nativeReleaseWait,
    DateTime? at,
  }) {
    if (_snapshot.releasePhase == PlayerBackendReleasePhase.released) {
      return;
    }
    final occurredAt = at ?? DateTime.now();
    final startedAt = _snapshot.releaseStartedAt ?? occurredAt;
    final total = occurredAt.difference(startedAt);
    _snapshot = _snapshot.copyWith(
      releasePhase: PlayerBackendReleasePhase.released,
      releaseStartedAt: startedAt,
      releaseCompletedAt: occurredAt,
      playerDisposeDuration: playerDisposeDuration,
      nativeReleaseWait: nativeReleaseWait,
      totalReleaseDuration: total.isNegative ? Duration.zero : total,
    );
    _emit(PlayerBackendTelemetryEventKind.releaseCompleted, occurredAt);
  }

  /** 关闭事件流；最终快照仍可在后端释放后读取。 */
  Future<void> close() => _events.close();

  /** 广播事件；关闭竞态只影响观察者，不得阻断后端释放。 */
  void _emit(PlayerBackendTelemetryEventKind kind, DateTime occurredAt) {
    if (_events.isClosed) {
      return;
    }
    _events.add(
      PlayerBackendTelemetryEvent(
        kind: kind,
        occurredAt: occurredAt,
        snapshot: _snapshot,
      ),
    );
  }
}

/**
 * 把 media_kit/libmpv 错误正文归一化为不含路径的稳定分类码。
 *
 * 错误正文只在当前调用栈内用于匹配，绝不写入快照、事件流或可复制诊断。
 */
String classifyPlayerBackendError(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('permission denied') ||
      message.contains('access is denied') ||
      message.contains('access denied')) {
    return 'access_denied';
  }
  if (message.contains('not found') ||
      message.contains('no such file') ||
      message.contains('cannot find the file')) {
    return 'missing_file';
  }
  if (message.contains('decoder') ||
      message.contains('decode') ||
      message.contains('codec')) {
    return 'decoder_failure';
  }
  if (message.contains('format') ||
      message.contains('demux') ||
      message.contains('invalid data') ||
      message.contains('unrecognized')) {
    return 'unsupported_or_invalid_media';
  }
  if (message.contains('texture') ||
      message.contains('render') ||
      message.contains('video output')) {
    return 'renderer_failure';
  }
  return 'backend_error';
}
