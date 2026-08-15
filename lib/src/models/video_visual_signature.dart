import 'video_item.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 视觉签名算法版本；算法、采样点或距离语义改变时必须递增/改名，旧缓存自然失效。
 */
const videoVisualSignatureAlgorithm = 'visual-dhash-v4';

/**
 * 可持久化的内容级视觉签名。
 *
 * 签名以 stable [videoId] 存储，但同时记录媒体身份快照；path 只是可变位置，不能成为
 * 缓存身份。文件被重新编码、替换或 stat 快照改变时，读取方必须拒绝旧签名并重算。
 */
class VideoVisualSignatureCacheEntry {
  const VideoVisualSignatureCacheEntry({
    required this.videoId,
    required this.algorithm,
    required this.hashes,
    this.mediaFingerprint,
    this.fileSize,
    this.modifiedMs,
  });

  final String videoId;
  final String algorithm;
  final List<int> hashes;
  final String? mediaFingerprint;
  final int? fileSize;
  final int? modifiedMs;

  /** 只有同一算法和同一媒体快照才允许命中，避免重用过期画面。 */
  bool matches(VideoItem item) {
    if (videoId != item.videoId ||
        algorithm != videoVisualSignatureAlgorithm ||
        hashes.length < 2 ||
        mediaFingerprint != item.mediaFingerprint ||
        fileSize != item.fileSize ||
        modifiedMs != item.modifiedMs) {
      return false;
    }
    // 没有任何可用于失效的媒体快照时，不能把结果永久视为有效。
    return mediaFingerprint != null || fileSize != null || modifiedMs != null;
  }

  Map<String, Object?> toJson() => {
        'videoId': videoId,
        'algorithm': algorithm,
        'hashes': hashes,
        'mediaFingerprint': mediaFingerprint,
        'fileSize': fileSize,
        'modifiedMs': modifiedMs,
      };

  static VideoVisualSignatureCacheEntry? fromJson(
    String videoId,
    Object? value,
  ) {
    if (value is! Map) {
      return null;
    }
    try {
      final storedVideoId = value['videoId'] as String?;
      if (storedVideoId != null && storedVideoId != videoId) {
        return null;
      }
      final hashes = (value['hashes'] as List?)
          ?.whereType<num>()
          .map((hash) => hash.toInt())
          .toList(growable: false);
      if (hashes == null || hashes.length < 2) {
        return null;
      }
      return VideoVisualSignatureCacheEntry(
        videoId: videoId,
        algorithm: value['algorithm'] as String? ?? '',
        hashes: List<int>.unmodifiable(hashes),
        mediaFingerprint: value['mediaFingerprint'] as String?,
        fileSize: (value['fileSize'] as num?)?.toInt(),
        modifiedMs: (value['modifiedMs'] as num?)?.toInt(),
      );
    } on Object {
      return null;
    }
  }
}
