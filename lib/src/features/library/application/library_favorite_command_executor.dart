import '../../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 收藏切换的补偿式命令。
 *
 * 内存对象先提供即时反馈；Repository 写入失败时恢复精确旧值并重新抛出，让页面显示错误。
 */
class LibraryFavoriteCommandExecutor {
  const LibraryFavoriteCommandExecutor();

  /** 切换收藏并提交同一 stable videoId，失败时不留下未持久化状态。 */
  Future<void> toggle(
    VideoItem item, {
    required Future<void> Function(VideoItem item) commit,
  }) async {
    final previous = item.isFavorite;
    item.isFavorite = !previous;
    try {
      await commit(item);
    } catch (_) {
      item.isFavorite = previous;
      rethrow;
    }
  }
}
