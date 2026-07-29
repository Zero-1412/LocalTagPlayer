// ignore_for_file: slash_for_doc_comments

/**
 * 迁移期兼容导出。
 *
 * latest-only 请求 owner 已迁入 feature application，播放进度纯函数已迁入 domain。
 * 保留该路径仅避免旧测试或下游导入立即失效，不允许 presentation 重新持有请求状态。
 */
library;

export '../../features/player/application/player_open_request_controller.dart';
export '../../features/player/domain/player_playback_progress.dart';
