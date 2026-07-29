// ignore_for_file: slash_for_doc_comments

/**
 * 一次播放器诊断采样的不可变领域快照。
 *
 * 快照只保存匿名运行指标和面向用户的安全文本，不持有 PlayerService、PlayerBackend、
 * Widget、Route 或本地目录。连续样本比较由诊断 presentation 在自身生命周期内完成。
 */
class PlaybackDiagnosticsSnapshot {
  const PlaybackDiagnosticsSnapshot({
    required this.lines,
    required this.sampledAt,
    required this.wasPlaying,
    required this.wasBuffering,
    required this.progressMs,
    required this.expectedMs,
    required this.smooth,
    required this.avSync,
    required this.mistimedFrames,
    required this.voDelayedFrames,
    required this.voDroppedFrames,
    required this.decoderDroppedFrames,
    required this.totalDroppedFrames,
    required this.cacheDuration,
    required this.cacheBufferingState,
    required this.hwdecCurrent,
    required this.videoCodec,
    required this.videoWidth,
    required this.videoHeight,
    required this.seekLatencyMs,
    required this.detailsQueued,
    required this.frameDurationMs,
    required this.videoStalled,
    required this.audioStalled,
  });

  /** 展示给用户的诊断文本行。 */
  final List<String> lines;

  /** 本次采样完成时间。 */
  final DateTime sampledAt;

  /** 采样开始时播放器是否处于播放状态。 */
  final bool wasPlaying;

  /** 采样开始时播放器是否处于缓冲状态。 */
  final bool wasBuffering;

  /** 采样窗口内播放位置推进毫秒数。 */
  final int progressMs;

  /** 当前状态下期望推进的毫秒数。 */
  final int expectedMs;

  /** 根据推进量推断播放是否流畅。 */
  final bool smooth;

  /** mpv 报告的 AV 同步偏移。 */
  final double? avSync;

  /** mpv 报告的时序异常帧计数。 */
  final int? mistimedFrames;

  /** mpv 报告的视频输出延迟帧计数。 */
  final int? voDelayedFrames;

  /** mpv 报告的视频输出丢帧计数。 */
  final int? voDroppedFrames;

  /** mpv 报告的解码丢帧计数。 */
  final int? decoderDroppedFrames;

  /** mpv 报告的总丢帧计数。 */
  final int? totalDroppedFrames;

  /** mpv demuxer 缓存时长。 */
  final double? cacheDuration;

  /** mpv 缓存填充状态。 */
  final double? cacheBufferingState;

  /** mpv 当前真正启用的硬件解码后端。 */
  final String? hwdecCurrent;

  /** 当前视频编码与分辨率，用于解释硬解后端拒绝高规格样本的原因。 */
  final String? videoCodec;
  final int? videoWidth;
  final int? videoHeight;

  /** 最近一次 seek 从请求到播放器返回的耗时。 */
  final int? seekLatencyMs;

  /** 当前媒体详情服务尚未执行的任务数量。 */
  final int detailsQueued;

  /** 根据 mpv 估算视频 FPS 换算的单帧预算。 */
  final double? frameDurationMs;

  /** 持续采样是否确认视频帧超过阈值未推进。 */
  final bool videoStalled;

  /** 持续采样是否确认音频播放头超过阈值未推进。 */
  final bool audioStalled;
}
