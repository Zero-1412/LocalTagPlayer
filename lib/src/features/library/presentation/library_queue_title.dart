import '../application/library_playback_queue_controller.dart';
import '../../../models/video_item.dart';
import '../domain/library_query_snapshot.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 为已经接受的结果来源生成播放器队列标题。
 *
 * [libraryTitle] 由页面按当前筛选摘要提供；[localPath] 只在本地目录来源展示。该函数不
 * 读取 Store 或查询状态，确保 Route 切换期间标题与捕获的结果快照保持一致。
 */
String libraryQueueTitle({
  required LibraryResultSource source,
  required int playlistLength,
  required int totalCount,
  required String libraryTitle,
  String? localPath,
}) {
  return switch (source) {
    LibraryResultSource.recent => '最近播放  |  $playlistLength / $totalCount',
    LibraryResultSource.favorites => '本地收藏  |  $playlistLength / $totalCount',
    LibraryResultSource.local =>
      '${localPath ?? '本地媒体库'}  |  $playlistLength / $totalCount',
    LibraryResultSource.library => libraryTitle,
  };
}

/**
 * Widget 树本次实际渲染结果对应的播放绑定。
 *
 * 结果快照和标题在同一 build 输入上生成，Route 切换时不再读取变化后的页面来源状态。
 */
class LibraryDisplayedPlaybackBinding {
  const LibraryDisplayedPlaybackBinding({
    required this.result,
    required this.queueTitle,
  });

  /** 本次实际渲染成员的 stable-ID 结果快照。 */
  final LibraryResultSnapshot result;

  /** 与结果来源同时捕获的队列标题。 */
  final String queueTitle;
}

/**
 * 把页面一次 build 中的来源、成员、epoch 与标题绑定为不可分割的播放输入。
 */
LibraryDisplayedPlaybackBinding bindDisplayedPlaybackResult({
  required LibraryPlaybackQueueController controller,
  required String sourceName,
  required LibraryResultEpoch acceptedLibraryEpoch,
  required Iterable<VideoItem> displayedVideos,
  required int totalCount,
  required int dataRevision,
  required int playbackDataRevision,
  required String sortFingerprint,
  required String libraryTitle,
  String? localPath,
}) {
  final source = LibraryResultSource.fromName(sourceName);
  return LibraryDisplayedPlaybackBinding(
    result: controller.acceptDisplayedResult(
      source: source,
      acceptedLibraryEpoch: acceptedLibraryEpoch,
      displayedVideos: displayedVideos,
      totalCount: totalCount,
      dataRevision: dataRevision,
      playbackDataRevision: playbackDataRevision,
      sortFingerprint: sortFingerprint,
      localPath: localPath,
    ),
    queueTitle: libraryQueueTitle(
      source: source,
      playlistLength: displayedVideos.length,
      totalCount: totalCount,
      localPath: localPath,
      libraryTitle: libraryTitle,
    ),
  );
}
