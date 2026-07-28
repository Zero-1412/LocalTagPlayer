// ignore_for_file: slash_for_doc_comments

/**
 * 播放器后端释放阶段。
 *
 * 该枚举只描述当前 Route 独占后端的生命周期，不代表进程级媒体库或缓存服务状态。
 */
enum PlayerBackendReleasePhase {
  active,
  releasing,
  released,
}

/**
 * 播放器后端遥测事件类型。
 *
 * 事件不携带媒体路径；调用方应通过打开代次关联同一 filtered queue 中的切换样本。
 */
enum PlayerBackendTelemetryEventKind {
  openStarted,
  firstFrame,
  decoderResolved,
  error,
  releaseStarted,
  releaseCompleted,
}

/**
 * 单个播放器后端实例的只读遥测快照。
 *
 * 快照以打开代次而不是本地路径标识媒体，既支持同实例连续切换，也避免诊断日志泄漏
 * 用户目录。首帧证据必须显式说明来源，不能把 `open` Future 返回当作渲染完成。
 */
class PlayerBackendTelemetrySnapshot {
  const PlayerBackendTelemetrySnapshot({
    required this.backendName,
    required this.supported,
    required this.openGeneration,
    required this.openStartedAt,
    required this.firstFrameAt,
    required this.firstFrameLatency,
    required this.firstFrameEvidence,
    required this.hwdecCurrent,
    required this.videoCodec,
    required this.decoderCapturedAt,
    required this.errorEventCount,
    required this.failedOpenCount,
    required this.lastFailedOpenGeneration,
    required this.lastErrorCode,
    required this.lastErrorAt,
    required this.releasePhase,
    required this.releaseStartedAt,
    required this.releaseCompletedAt,
    required this.playerDisposeDuration,
    required this.nativeReleaseWait,
    required this.totalReleaseDuration,
  });

  /** 后端不能提供结构化遥测时使用的显式占位快照。 */
  const PlayerBackendTelemetrySnapshot.unsupported()
      : backendName = 'unsupported',
        supported = false,
        openGeneration = 0,
        openStartedAt = null,
        firstFrameAt = null,
        firstFrameLatency = null,
        firstFrameEvidence = null,
        hwdecCurrent = null,
        videoCodec = null,
        decoderCapturedAt = null,
        errorEventCount = 0,
        failedOpenCount = 0,
        lastFailedOpenGeneration = null,
        lastErrorCode = null,
        lastErrorAt = null,
        releasePhase = PlayerBackendReleasePhase.active,
        releaseStartedAt = null,
        releaseCompletedAt = null,
        playerDisposeDuration = null,
        nativeReleaseWait = null,
        totalReleaseDuration = null;

  /** 不包含版本号和路径的稳定后端标识。 */
  final String backendName;

  /** 当前后端是否实现结构化遥测。 */
  final bool supported;

  /** 当前后端实例累计发起的媒体打开次数。 */
  final int openGeneration;

  /** 当前打开代次开始时间。 */
  final DateTime? openStartedAt;

  /** 当前打开代次首次获得视频帧证据的时间。 */
  final DateTime? firstFrameAt;

  /** 从当前打开请求到首帧证据的耗时。 */
  final Duration? firstFrameLatency;

  /** 首帧证据来源，例如 Texture rendered 或 mpv frame number。 */
  final String? firstFrameEvidence;

  /** 当前媒体实际使用的硬件解码器；`no` 表示软件解码。 */
  final String? hwdecCurrent;

  /** 当前媒体由 libmpv 报告的视频编码。 */
  final String? videoCodec;

  /** 当前媒体解码器信息完成采样的时间。 */
  final DateTime? decoderCapturedAt;

  /** 后端原始错误事件数量；同一次打开可能产生多个底层错误事件。 */
  final int errorEventCount;

  /** 至少产生过一次错误的打开代次数量，用于计算切换失败率。 */
  final int failedOpenCount;

  /** 最近一次产生错误的打开代次，用于同代错误去重。 */
  final int? lastFailedOpenGeneration;

  /** 最近错误的稳定分类码，不包含异常正文或本地路径。 */
  final String? lastErrorCode;

  /** 最近错误发生时间。 */
  final DateTime? lastErrorAt;

  /** 当前后端资源释放阶段。 */
  final PlayerBackendReleasePhase releasePhase;

  /** 后端开始释放的时间。 */
  final DateTime? releaseStartedAt;

  /** 后端确认原生资源释放完成的时间。 */
  final DateTime? releaseCompletedAt;

  /** media_kit `Player.dispose` Future 自身耗时。 */
  final Duration? playerDisposeDuration;

  /** 为底层延迟销毁额外等待的时间。 */
  final Duration? nativeReleaseWait;

  /** 从释放开始到确认结束的总耗时。 */
  final Duration? totalReleaseDuration;

  /** 以“至少一次错误的打开代次 / 总打开代次”计算切换失败率。 */
  double get openFailureRate =>
      openGeneration == 0 ? 0 : failedOpenCount / openGeneration;

  /**
   * 返回替换指定字段后的新快照。
   *
   * 可空字段使用显式 `clear*` 开关，避免新媒体打开时沿用上一条媒体的首帧或解码器。
   */
  PlayerBackendTelemetrySnapshot copyWith({
    int? openGeneration,
    DateTime? openStartedAt,
    bool clearOpenStartedAt = false,
    DateTime? firstFrameAt,
    bool clearFirstFrameAt = false,
    Duration? firstFrameLatency,
    bool clearFirstFrameLatency = false,
    String? firstFrameEvidence,
    bool clearFirstFrameEvidence = false,
    String? hwdecCurrent,
    bool clearHwdecCurrent = false,
    String? videoCodec,
    bool clearVideoCodec = false,
    DateTime? decoderCapturedAt,
    bool clearDecoderCapturedAt = false,
    int? errorEventCount,
    int? failedOpenCount,
    int? lastFailedOpenGeneration,
    String? lastErrorCode,
    DateTime? lastErrorAt,
    PlayerBackendReleasePhase? releasePhase,
    DateTime? releaseStartedAt,
    DateTime? releaseCompletedAt,
    Duration? playerDisposeDuration,
    Duration? nativeReleaseWait,
    Duration? totalReleaseDuration,
  }) =>
      PlayerBackendTelemetrySnapshot(
        backendName: backendName,
        supported: supported,
        openGeneration: openGeneration ?? this.openGeneration,
        openStartedAt:
            clearOpenStartedAt ? null : openStartedAt ?? this.openStartedAt,
        firstFrameAt:
            clearFirstFrameAt ? null : firstFrameAt ?? this.firstFrameAt,
        firstFrameLatency: clearFirstFrameLatency
            ? null
            : firstFrameLatency ?? this.firstFrameLatency,
        firstFrameEvidence: clearFirstFrameEvidence
            ? null
            : firstFrameEvidence ?? this.firstFrameEvidence,
        hwdecCurrent:
            clearHwdecCurrent ? null : hwdecCurrent ?? this.hwdecCurrent,
        videoCodec: clearVideoCodec ? null : videoCodec ?? this.videoCodec,
        decoderCapturedAt: clearDecoderCapturedAt
            ? null
            : decoderCapturedAt ?? this.decoderCapturedAt,
        errorEventCount: errorEventCount ?? this.errorEventCount,
        failedOpenCount: failedOpenCount ?? this.failedOpenCount,
        lastFailedOpenGeneration:
            lastFailedOpenGeneration ?? this.lastFailedOpenGeneration,
        lastErrorCode: lastErrorCode ?? this.lastErrorCode,
        lastErrorAt: lastErrorAt ?? this.lastErrorAt,
        releasePhase: releasePhase ?? this.releasePhase,
        releaseStartedAt: releaseStartedAt ?? this.releaseStartedAt,
        releaseCompletedAt: releaseCompletedAt ?? this.releaseCompletedAt,
        playerDisposeDuration:
            playerDisposeDuration ?? this.playerDisposeDuration,
        nativeReleaseWait: nativeReleaseWait ?? this.nativeReleaseWait,
        totalReleaseDuration: totalReleaseDuration ?? this.totalReleaseDuration,
      );
}

/**
 * 一次后端遥测变化。
 *
 * [snapshot] 是事件发生后的完整快照，便于压力工具无状态采集。
 */
class PlayerBackendTelemetryEvent {
  const PlayerBackendTelemetryEvent({
    required this.kind,
    required this.occurredAt,
    required this.snapshot,
  });

  /** 本次变化类型。 */
  final PlayerBackendTelemetryEventKind kind;

  /** 本次变化发生时间。 */
  final DateTime occurredAt;

  /** 变化完成后的完整遥测快照。 */
  final PlayerBackendTelemetrySnapshot snapshot;
}
