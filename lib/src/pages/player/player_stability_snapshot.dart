
import '../../features/player/application/player_session_controller.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 双后端稳定性矩阵读取的匿名播放器快照。
 *
 * 快照只暴露稳定 `videoId`、队列索引与生命周期状态，不泄露本地路径，也不允许测试
 * 绕过 [PlayerSessionController] 修改 filtered queue。
 */
class PlayerStabilitySnapshot {
  const PlayerStabilitySnapshot({
    required this.sourceVideoIds,
    required this.queueVideoIds,
    required this.playingIndex,
    required this.selectedIndex,
    required this.currentVideoId,
    required this.openedVideoId,
    required this.opening,
    required this.hasPendingOpen,
    required this.hasOpenFailure,
    required this.windowFullscreen,
  });

  /** 媒体库传入播放器的过滤后来源队列身份。 */
  final List<String> sourceVideoIds;

  /** 当前播放器实际消费的队列身份。 */
  final List<String> queueVideoIds;

  /** 当前播放项在队列中的索引。 */
  final int playingIndex;

  /** 键盘或鼠标当前选中项在队列中的索引。 */
  final int selectedIndex;

  /** 播放器页面当前选择的视频身份。 */
  final String currentVideoId;

  /** 后端最后完成打开的视频身份；打开尚未完成时为 null。 */
  final String? openedVideoId;

  /** 串行 open worker 是否仍在处理请求。 */
  final bool opening;

  /** 是否还有被最新选择覆盖后的待处理 open 请求。 */
  final bool hasPendingOpen;

  /** 最近一次最终 open 是否失败。 */
  final bool hasOpenFailure;

  /** 正式播放器全屏状态机的当前状态。 */
  final bool windowFullscreen;
}
