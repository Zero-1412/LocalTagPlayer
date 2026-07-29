// ignore_for_file: slash_for_doc_comments

/**
 * 迁移期兼容导出。
 *
 * 生产页面已经改用 feature application 下的 `PlayerSessionController`；保留该路径只为
 * 避免旧测试或下游导入立即失效，不允许在 presentation 目录重新建立可写队列 owner。
 */
library;

export '../../features/player/application/player_session_controller.dart';
