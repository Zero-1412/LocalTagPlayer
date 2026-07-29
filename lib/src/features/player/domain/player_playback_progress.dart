import '../../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 判断播放器打开后的媒体状态是否已经具备可播放证据。
 *
 * 本地视频通常会先得到有效时长；少数容器时长稍晚，但后端已能报告音频或视频编码。
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
