part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放器跨 Flutter、media_kit 与原生纹理边界的轻量内存阶段记录器。
 *
 * 记录内容不包含媒体路径；外部压力脚本可用时间戳把阶段与 Windows GPU Process Memory
 * 计数器对齐，从而区分 Flutter 图片缓存、libmpv 缓存和 D3D 纹理驻留。
 */
class PlayerMemoryDiagnostics {
  const PlayerMemoryDiagnostics._();

  /** 记录一个阶段；播放器已经释放时应省略 [player] 与 [controller]。 */
  static Future<void> logStage(
    String stage, {
    PlayerBackend? backend,
  }) async {
    final imageCache = PaintingBinding.instance.imageCache;
    var demuxSeconds = 'unavailable';
    var demuxState = 'unavailable';
    if (backend != null) {
      try {
        demuxSeconds = await backend.getProperty('demuxer-cache-duration');
      } catch (_) {
        // 文件尚未打开或 Player 正在释放时，mpv 属性允许暂时不可用。
      }
      try {
        demuxState = await backend.getProperty('demuxer-cache-state');
      } catch (_) {
        // 复杂 node 属性在部分构建中不可转换为字符串，保留 unavailable。
      }
    }
    debugPrint(
      'PLAYER_MEMORY_STAGE timestamp=${DateTime.now().toIso8601String()} '
      'stage=$stage rss_bytes=${ProcessInfo.currentRss} '
      'image_cache_bytes=${imageCache.currentSizeBytes} '
      'image_cache_count=${imageCache.currentSize} '
      'image_cache_live=${imageCache.liveImageCount} '
      'image_cache_pending=${imageCache.pendingImageCount} '
      'texture_id=${backend?.textureId.value ?? -1} '
      'demux_seconds=$demuxSeconds demux_state=$demuxState',
    );
  }
}
