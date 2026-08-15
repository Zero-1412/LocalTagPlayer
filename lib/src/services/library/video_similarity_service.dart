import '../../models/video_item.dart';

enum VideoSimilarityKind {
  /** 扫描阶段持久化的文件级快速指纹一致。 */
  exactFingerprint,

  /** 重新编码或容器变化后仍保持时序视觉内容一致的高置信候选。 */
  visualNearDuplicate,
}

// ignore_for_file: slash_for_doc_comments

/**
 * 一组使用相同轻量媒体指纹的视频。
 *
 * 指纹来自扫描链路的文件大小与首尾采样；这里仅做内存分组，不重新读取文件，也不
 * 把“相似”误判为可以自动删除。最终处理仍由用户逐条确认。
 */
class VideoSimilarityGroup {
  const VideoSimilarityGroup({
    required this.fingerprint,
    required this.videos,
    this.kind = VideoSimilarityKind.exactFingerprint,
    this.visualScore,
  });

  /** 仅供测试和后续诊断使用，界面不展示内部指纹值。 */
  final String fingerprint;

  /** 仅影响候选解释，不改变用户数据或删除语义。 */
  final VideoSimilarityKind kind;

  /** 视觉候选的时序 dHash 相似度；越低越相似。 */
  final double? visualScore;

  /** 同组视频按标题和路径稳定排序。 */
  final List<VideoItem> videos;

  int get duplicateCount => videos.length - 1;
}

/**
 * 当前媒体库的重复候选快照。
 *
 * 只把有明确指纹且当前路径有效的视频纳入候选；missing 记录仍保留在库中，但不参与
 * 物理文件重复判断。缺少指纹的条目单独计数，提示用户先完成一次扫描。
 */
class VideoSimilarityReport {
  const VideoSimilarityReport({
    required this.groups,
    required this.indexedVideoCount,
    required this.unindexedVideoCount,
    required this.missingVideoCount,
    this.visualGroups = const <VideoSimilarityGroup>[],
    this.visualCandidatePairCount = 0,
    this.visualComparedPairCount = 0,
  });

  factory VideoSimilarityReport.fromVideos(Iterable<VideoItem> videos) {
    final byFingerprint = <String, List<VideoItem>>{};
    var indexed = 0;
    var unindexed = 0;
    var missing = 0;
    for (final item in videos) {
      if (item.isMissing) {
        missing++;
        continue;
      }
      final fingerprint = item.mediaFingerprint?.trim();
      if (fingerprint == null || fingerprint.isEmpty) {
        unindexed++;
        continue;
      }
      indexed++;
      (byFingerprint[fingerprint] ??= <VideoItem>[]).add(item);
    }

    final groups = <VideoSimilarityGroup>[];
    for (final entry in byFingerprint.entries) {
      if (entry.value.length < 2) {
        continue;
      }
      final sortedVideos = List<VideoItem>.of(entry.value)
        ..sort(_compareVideos);
      groups.add(VideoSimilarityGroup(
        fingerprint: entry.key,
        videos: List<VideoItem>.unmodifiable(sortedVideos),
      ));
    }
    groups.sort((a, b) => _compareVideos(a.videos.first, b.videos.first));
    return VideoSimilarityReport(
      groups: List<VideoSimilarityGroup>.unmodifiable(groups),
      indexedVideoCount: indexed,
      unindexedVideoCount: unindexed,
      missingVideoCount: missing,
    );
  }

  /**
   * 在保留快速指纹统计的前提下附加本次按需视觉复核结果。
   *
   * 视觉签名只驻留在当前页面快照中，不写入 schema，避免把算法版本或临时失败状态
   * 绑定到稳定 videoId。
   */
  VideoSimilarityReport withVisualGroups({
    required Iterable<VideoSimilarityGroup> groups,
    required int candidatePairCount,
    required int comparedPairCount,
  }) {
    return VideoSimilarityReport(
      groups: this.groups,
      indexedVideoCount: indexedVideoCount,
      unindexedVideoCount: unindexedVideoCount,
      missingVideoCount: missingVideoCount,
      visualGroups: List<VideoSimilarityGroup>.unmodifiable(groups),
      visualCandidatePairCount: candidatePairCount,
      visualComparedPairCount: comparedPairCount,
    );
  }

  /** 按首个稳定排序视频排列的重复候选组。 */
  final List<VideoSimilarityGroup> groups;

  /** 已有可用于比较的 mediaFingerprint 的有效视频数量。 */
  final int indexedVideoCount;

  /** 尚未完成 fingerprint 的有效视频数量。 */
  final int unindexedVideoCount;

  /** 被保留但当前路径失效、因此跳过比较的条目数量。 */
  final int missingVideoCount;

  /** 本次按需视觉扫描生成的近重复组。 */
  final List<VideoSimilarityGroup> visualGroups;

  /** 由时长/分辨率预筛留下的候选对数量。 */
  final int visualCandidatePairCount;

  /** 实际完成取帧比较的候选对数量。 */
  final int visualComparedPairCount;

  Iterable<VideoSimilarityGroup> get allGroups sync* {
    yield* groups;
    yield* visualGroups;
  }

  int get duplicateGroupCount => groups.length + visualGroups.length;

  /** 参与重复组的文件总数；同组第一条也计入，便于展示实际影响范围。 */
  int get duplicateVideoCount =>
      allGroups.fold<int>(0, (total, group) => total + group.videos.length);

  /** 每组扣除一条保留项后的可清理候选数，仅作为统计，不触发删除。 */
  int get duplicateExtraCount =>
      allGroups.fold<int>(0, (total, group) => total + group.duplicateCount);

  bool get hasMatches => groups.isNotEmpty || visualGroups.isNotEmpty;
}

int _compareVideos(VideoItem a, VideoItem b) {
  final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  if (title != 0) {
    return title;
  }
  final path = a.path.toLowerCase().compareTo(b.path.toLowerCase());
  if (path != 0) {
    return path;
  }
  return a.videoId.compareTo(b.videoId);
}
