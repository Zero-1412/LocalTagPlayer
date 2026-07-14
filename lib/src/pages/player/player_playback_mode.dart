part of '../../app.dart';

// ignore_for_file: slash_for_doc_comments

/** 播放完成后的轻量队列策略，不改变 filtered queue 本身的顺序与来源。 */
enum PlayerPlaybackMode {
  sequential,
  shuffle,
  repeatOne,
  repeatAll,
}

extension PlayerPlaybackModePresentation on PlayerPlaybackMode {
  /** 面向播放器菜单的简短中文名称。 */
  String get label => switch (this) {
        PlayerPlaybackMode.sequential => '顺序播放',
        PlayerPlaybackMode.shuffle => '随机播放',
        PlayerPlaybackMode.repeatOne => '单曲循环',
        PlayerPlaybackMode.repeatAll => '列表循环',
      };

  /** 播放器顶部用于辨认当前策略的图标。 */
  IconData get icon => switch (this) {
        PlayerPlaybackMode.sequential => Icons.format_list_numbered_rounded,
        PlayerPlaybackMode.shuffle => Icons.shuffle_rounded,
        PlayerPlaybackMode.repeatOne => Icons.repeat_one_rounded,
        PlayerPlaybackMode.repeatAll => Icons.repeat_rounded,
      };
}

/**
 * 计算 EOF 后应打开的队列索引。
 *
 * [randomValue] 仅用于随机模式，范围会被夹紧，便于测试并避免随机数影响其它模式。
 * 返回 `null` 表示保持默认队尾停止语义。
 */
int? playerCompletionTargetIndex({
  required PlayerPlaybackMode mode,
  required int currentIndex,
  required int queueLength,
  double randomValue = 0,
}) {
  if (queueLength <= 0 || currentIndex < 0 || currentIndex >= queueLength) {
    return null;
  }
  switch (mode) {
    case PlayerPlaybackMode.sequential:
      return currentIndex + 1 < queueLength ? currentIndex + 1 : null;
    case PlayerPlaybackMode.repeatOne:
      return currentIndex;
    case PlayerPlaybackMode.repeatAll:
      return currentIndex + 1 < queueLength ? currentIndex + 1 : 0;
    case PlayerPlaybackMode.shuffle:
      if (queueLength == 1) {
        return 0;
      }
      // 从排除当前项后的 N-1 个槽位中选择，避免连续随机到同一视频。
      final slot = (randomValue.clamp(0, 0.999999) * (queueLength - 1)).floor();
      return slot >= currentIndex ? slot + 1 : slot;
  }
}
