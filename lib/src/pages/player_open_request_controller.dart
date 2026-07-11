part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 判断播放器打开后的媒体状态是否已经具备可播放证据。
 *
 * 本地视频通常会先得到有效时长；少数容器时长稍晚，但 mpv 已能报告音频或视频编码。
 * 两类证据都缺失时不能把 `Player.open` 的成功返回直接当成可播放成功。
 */
bool playerMediaStateIsPlayable({
  required Duration duration,
  required String videoCodec,
  required String audioCodec,
}) {
  if (duration > Duration.zero) {
    return true;
  }
  bool hasCodec(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isNotEmpty &&
        normalized != 'empty' &&
        normalized != 'unavailable' &&
        normalized != 'null';
  }

  return hasCodec(videoCodec) || hasCodec(audioCodec);
}

/**
 * 按视频长度返回动态完成阈值。
 *
 * 短视频只保留 1-2 秒尾部容差，长视频使用约 5% 且封顶 30 秒，避免最后几秒反复恢复。
 */
Duration playerCompletionThreshold(Duration duration) {
  if (duration <= const Duration(seconds: 15)) {
    return const Duration(seconds: 1);
  }
  if (duration <= const Duration(minutes: 1)) {
    return const Duration(seconds: 2);
  }
  final milliseconds = (duration.inMilliseconds * 0.05).round();
  return Duration(
    milliseconds: milliseconds.clamp(5000, 30000),
  );
}

/** 判断当前位置是否已进入完成区间；无有效时长时保持保守未完成。 */
bool playerPlaybackIsNearCompletion({
  required Duration position,
  required Duration duration,
}) {
  if (duration <= Duration.zero || position <= Duration.zero) {
    return false;
  }
  return position >= duration - playerCompletionThreshold(duration);
}

/** 真正需要出现在“继续观看”中的稳定视频记录。 */
bool videoIsContinueWatching(VideoItem item) {
  return item.lastPlayedAt != null &&
      !item.playbackCompleted &&
      item.playbackPosition >= const Duration(seconds: 3) &&
      item.playbackDuration > Duration.zero &&
      !playerPlaybackIsNearCompletion(
        position: item.playbackPosition,
        duration: item.playbackDuration,
      );
}

/** 返回继续观看卡片使用的稳定进度比例。 */
double videoPlaybackProgressFraction(VideoItem item) {
  if (item.playbackDuration <= Duration.zero) {
    return 0;
  }
  return (item.playbackPosition.inMilliseconds /
          item.playbackDuration.inMilliseconds)
      .clamp(0.0, 1.0);
}

/** 返回安全可恢复的播放位置；接近结尾时从头播放，避免一打开就触发 EOF。 */
Duration? playerResumePosition({
  required Duration saved,
  required Duration duration,
  bool completed = false,
}) {
  if (completed ||
      saved < const Duration(seconds: 3) ||
      duration <= Duration.zero ||
      playerPlaybackIsNearCompletion(position: saved, duration: duration)) {
    return null;
  }
  return saved;
}

/**
 * 播放页 open 请求队列协调器。
 *
 * 该 controller 只维护“最新待打开路径、是否有 drain worker、是否展示打开中遮罩”，不直接调用
 * `Player.open`，因此不会改变 PlayerBackend/mpv 行为。
 */
class PlayerOpenRequestController {
  /** 最新一次请求打开的视频路径。 */
  String? _pendingOpenPath;

  /** 是否已有 worker 正在串行处理 open 请求。 */
  var _workerRunning = false;

  /** 页面是否应展示打开中遮罩。 */
  var isOpening = false;

  /** 最近一次最终未能打开的视频路径，仅在播放器页生命周期内保留。 */
  String? failedPath;

  /** 不包含本地路径的安全错误类型，用于稳定错误面板和诊断摘要。 */
  String? failureCode;

  /** 当前是否还有待处理路径。 */
  bool get hasPending => _pendingOpenPath != null;

  /** 当前是否有需要用户重试或跳过的稳定打开错误。 */
  bool get hasFailure => failedPath != null;

  /**
   * 记录一次打开请求。
   *
   * 返回 `true` 表示调用方需要启动 drain worker；返回 `false` 表示已有 worker 会消费最新路径。
   */
  bool request(String path) {
    clearFailure();
    _pendingOpenPath = path;
    if (_workerRunning) {
      return false;
    }
    return true;
  }

  /** 记录最终打开失败状态，错误详情只保留安全类型，不保存异常文本。 */
  void markFailure(String path, {required String code}) {
    failedPath = path;
    failureCode = code;
  }

  /** 成功打开视频后清理旧错误，避免失败遮罩覆盖已经切换成功的视频。 */
  void markSuccess() {
    clearFailure();
  }

  /** 清理当前打开错误。 */
  void clearFailure() {
    failedPath = null;
    failureCode = null;
  }

  /** 重新排队最近失败的视频，并复用原有 latest-request worker 语义。 */
  bool retryFailure() {
    final path = failedPath;
    if (path == null) {
      return false;
    }
    return request(path);
  }

  /**
   * 标记 drain worker 开始运行。
   */
  void beginDrain() {
    _workerRunning = true;
    isOpening = true;
  }

  /**
   * 取出并清空当前待打开路径。
   *
   * open 请求只保留最新路径，快速跳转时旧路径会被覆盖，避免排队打开过时视频。
   */
  String? takePendingPath() {
    final path = _pendingOpenPath;
    _pendingOpenPath = null;
    return path;
  }

  /**
   * 标记 drain worker 完成。
   *
   * [keepOpening] 为 true 时说明 finally 阶段已经发现新请求，遮罩保持打开直到下一轮 drain。
   */
  void finishDrain({required bool keepOpening}) {
    _workerRunning = false;
    isOpening = keepOpening;
  }

  /**
   * 页面销毁时取消尚未处理的 open 请求。
   */
  void cancel() {
    _pendingOpenPath = null;
    _workerRunning = false;
    isOpening = false;
    clearFailure();
  }
}
