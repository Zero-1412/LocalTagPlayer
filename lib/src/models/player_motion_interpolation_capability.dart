// ignore_for_file: slash_for_doc_comments

/**
 * 本机运动补偿插帧链的可用状态。
 *
 * `ready` 只表示外部 VapourSynth 运行时和脚本通过静态门禁；
 * `requested/active` 才表示当前 libmpv 会话已经请求或实际运行滤镜。
 */
enum PlayerMotionInterpolationStatus {
  unsupported,
  notConfigured,
  unavailable,
  ready,
  requested,
  active,
  fallback,
}

/**
 * Windows libmpv 插帧边界返回的不可变能力快照。
 *
 * 快照只暴露稳定状态码，不携带本机 DLL、Python、脚本或媒体路径。
 */
class PlayerMotionInterpolationCapability {
  const PlayerMotionInterpolationCapability({
    required this.status,
    required this.backend,
    required this.runtimeState,
    this.errorCode = '',
    this.enabled = false,
    this.fallbackCount = 0,
  });

  /** 非 Windows 原生后端使用的确定性回退。 */
  const PlayerMotionInterpolationCapability.unsupported()
      : status = PlayerMotionInterpolationStatus.unsupported,
        backend = 'unsupported',
        runtimeState = 'unsupported',
        errorCode = 'backend-capability-unsupported',
        enabled = false,
        fallbackCount = 0;

  final PlayerMotionInterpolationStatus status;

  /** 能力所有者；正式路径必须为 `windows-native-libmpv`。 */
  final String backend;

  /** 原生宿主返回的稳定状态，不包含路径或第三方日志。 */
  final String runtimeState;

  /** 失败时的稳定错误码。 */
  final String errorCode;

  /** 当前会话是否仍持有插帧请求。 */
  final bool enabled;

  /** 本会话发生过的确定性滤镜回退次数。 */
  final int fallbackCount;

  /** 只有运行时和脚本通过门禁后才允许发送启用命令。 */
  bool get canEnable =>
      status == PlayerMotionInterpolationStatus.ready ||
      status == PlayerMotionInterpolationStatus.requested ||
      status == PlayerMotionInterpolationStatus.active;

  String get helperText => switch (status) {
        PlayerMotionInterpolationStatus.unsupported => '当前播放器后端不支持本机运动补偿插帧',
        PlayerMotionInterpolationStatus.notConfigured =>
          '未配置本机 VapourSynth 运行时与插帧脚本',
        PlayerMotionInterpolationStatus.unavailable => '本机插帧运行时不可用：$errorCode',
        PlayerMotionInterpolationStatus.ready => '本机运行时已验证，尚未启用插帧',
        PlayerMotionInterpolationStatus.requested =>
          'libmpv 已请求本机插帧滤镜，等待实际送帧确认',
        PlayerMotionInterpolationStatus.active => '本机运动补偿插帧正在运行',
        PlayerMotionInterpolationStatus.fallback => '插帧失败并已回退原视频帧：$errorCode',
      };
}

/**
 * 启用或关闭插帧后的读回结果。
 *
 * [applied] 只在原生状态与请求一致时为 true，UI 不得按写入成功自行推断。
 */
class PlayerMotionInterpolationApplyResult {
  const PlayerMotionInterpolationApplyResult({
    required this.applied,
    required this.capability,
  });

  final bool applied;
  final PlayerMotionInterpolationCapability capability;
}
