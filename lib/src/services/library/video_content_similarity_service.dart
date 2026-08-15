import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/video_item.dart';
import '../media/thumbnail_service.dart';
import 'video_similarity_service.dart';

// ignore_for_file: slash_for_doc_comments

// 首帧复用媒体库缩略图，另外取中段/后段两个时间点；避免页面首次打开为每个候选
// 启动六次 FFmpeg，同时仍保留有序时序特征而不是只比较一个画面。
const _visualSampleFractions = <double>[0.35, 0.65];
const _visualDistanceThreshold = 0.22;
/**
 * 候选上限只作为异常大库的保护；候选选择本身按每个视频分摊，不能再取全局
 * 时长排序的前 N 对，否则同一时长密集区会饿死其它视频。
 */
const _maxVisualCandidatePairs = 65536;
const _maxVisualNeighborsPerVideo = 8;
/** 首帧只做廉价预筛，低于完整时序阈值的候选才启动中段/后段取帧。 */
const _quickVisualDistanceThreshold = 0.32;
/** 缩略图尚未缓存时只保留少量深度回退，避免首次打开页面启动全库 FFmpeg 风暴。 */
const _maxUncachedDeepCandidatePairs = 256;

/**
 * 内容级近重复检测器。
 *
 * 先按时长/画面规格/文件大小为每个视频选择最相近邻居，再复用已有缩略图做廉价
 * 首帧 dHash 预筛，最后经 [ThumbnailService] 的 FFmpeg 取帧边界生成有序多帧 dHash。
 * 这样可以识别重新编码、容器变化或轻微裁剪后的复制品，同时避免同一时长密集区
 * 垄断全局候选；平台路径、外部进程或解码逻辑仍不进入页面，签名只在当前扫描内存中存在。
 */
class VideoContentSimilarityService {
  const VideoContentSimilarityService(this._thumbnailService);

  final ThumbnailService _thumbnailService;

  Future<VideoVisualScanResult> findNearDuplicateGroups(
    Iterable<VideoItem> source, {
    Iterable<String> excludedVideoIds = const <String>[],
    int maxCandidatePairs = _maxVisualCandidatePairs,
  }) async {
    if (maxCandidatePairs <= 0) {
      return const VideoVisualScanResult.empty();
    }
    final excluded = excludedVideoIds.toSet();
    final videos = source
        .where((item) => !item.isMissing && !excluded.contains(item.videoId))
        .where((item) => _durationFor(item) != null)
        .toList(growable: false);
    final candidates = _buildCandidates(videos, maxCandidatePairs);
    if (candidates.isEmpty) {
      return const VideoVisualScanResult.empty();
    }

    final signatures = <String, List<int>?>{};
    final quickHashes = <String, int?>{};
    final parent = List<int>.generate(videos.length, (index) => index);
    final matchedScores = <int, double>{};
    var uncachedDeepCandidates = 0;
    var compared = 0;
    for (final candidate in candidates) {
      final left = videos[candidate.left];
      final right = videos[candidate.right];
      // 已有文件级指纹命中的组不再重复触发取帧；页面会单独展示它们。
      if (_sameFingerprint(left, right)) {
        continue;
      }
      final leftQuickHash = await _quickHashFor(left, quickHashes);
      final rightQuickHash = await _quickHashFor(right, quickHashes);
      if (leftQuickHash != null && rightQuickHash != null) {
        final quickDistance = _hamming(leftQuickHash ^ rightQuickHash) / 64;
        if (quickDistance > _quickVisualDistanceThreshold) {
          continue;
        }
      } else {
        // 未缓存首帧的候选仍允许少量深度回退，但不能让首次打开页面为全库
        // 生成数千个 JPEG；后续缩略图预取或再次扫描会逐步扩大覆盖。
        if (uncachedDeepCandidates >= _maxUncachedDeepCandidatePairs) {
          continue;
        }
        uncachedDeepCandidates++;
      }
      final leftSignature = await _signatureFor(left, signatures);
      final rightSignature = await _signatureFor(right, signatures);
      if (leftSignature == null || rightSignature == null) {
        continue;
      }
      compared++;
      final distance = _sequenceDistance(leftSignature, rightSignature);
      if (distance > _visualDistanceThreshold) {
        continue;
      }
      _union(parent, candidate.left, candidate.right);
      _recordMinimumScore(matchedScores, candidate.left, distance);
      _recordMinimumScore(matchedScores, candidate.right, distance);
    }

    final components = <int, List<int>>{};
    for (var index = 0; index < videos.length; index++) {
      final root = _find(parent, index);
      (components[root] ??= <int>[]).add(index);
    }
    final groups = <VideoSimilarityGroup>[];
    for (final entry in components.entries) {
      if (entry.value.length < 2) {
        continue;
      }
      final members = entry.value.map((index) => videos[index]).toList()
        ..sort(_compareVideos);
      final score = entry.value
          .map((index) => matchedScores[index])
          .whereType<double>()
          .fold<double?>(
              null,
              (best, value) =>
                  best == null ? value : math.min(best, value).toDouble());
      groups.add(
        VideoSimilarityGroup(
          // 视觉签名不持久化；该值仅用于调试区分算法版本。
          fingerprint: 'visual-dhash-v2',
          kind: VideoSimilarityKind.visualNearDuplicate,
          visualScore: score,
          videos: List<VideoItem>.unmodifiable(members),
        ),
      );
    }
    groups.sort((a, b) => _compareVideos(a.videos.first, b.videos.first));
    return VideoVisualScanResult(
      groups: List<VideoSimilarityGroup>.unmodifiable(groups),
      candidatePairCount: candidates.length,
      comparedPairCount: compared,
    );
  }

  List<_VisualCandidate> _buildCandidates(
    List<VideoItem> videos,
    int maxCandidatePairs,
  ) {
    final indexed = <_TimedVideo>[];
    for (var index = 0; index < videos.length; index++) {
      final duration = _durationFor(videos[index]);
      if (duration == null || duration <= Duration.zero) {
        continue;
      }
      indexed.add(_TimedVideo(index: index, duration: duration));
    }
    indexed.sort((a, b) => a.duration.compareTo(b.duration));
    final rankedByVideo = <List<_VisualCandidate>>[
      for (var index = 0; index < indexed.length; index++) <_VisualCandidate>[],
    ];
    final seen = <String, _VisualCandidate>{};
    for (var i = 0; i < indexed.length; i++) {
      final left = indexed[i];
      final tolerance = Duration(
        milliseconds: math.max(
          2500,
          (left.duration.inMilliseconds * 0.06).round(),
        ),
      );
      final local = <_VisualCandidate>[];
      for (var j = i + 1; j < indexed.length; j++) {
        final right = indexed[j];
        if (right.duration - left.duration > tolerance) {
          break;
        }
        if (!_compatibleVideoShape(videos[left.index], videos[right.index])) {
          continue;
        }
        local.add(
          _VisualCandidate(
            left: left.index,
            right: right.index,
            score: _candidateScore(videos[left.index], videos[right.index]),
          ),
        );
      }
      local.sort((a, b) {
        final score = a.score.compareTo(b.score);
        if (score != 0) return score;
        final left = a.left.compareTo(b.left);
        return left != 0 ? left : a.right.compareTo(b.right);
      });
      rankedByVideo[i].addAll(
        local.take(_maxVisualNeighborsPerVideo),
      );
    }

    // 按邻居轮次交错不同 duration 区间，保证候选上限也不会只覆盖排序最前端。
    final candidates = <_VisualCandidate>[];
    for (var round = 0; round < _maxVisualNeighborsPerVideo; round++) {
      for (final ranked in rankedByVideo) {
        if (round >= ranked.length) continue;
        final candidate = ranked[round];
        final key = candidate.left < candidate.right
            ? '${candidate.left}:${candidate.right}'
            : '${candidate.right}:${candidate.left}';
        if (seen.containsKey(key)) continue;
        seen[key] = candidate;
        candidates.add(candidate);
        if (candidates.length >= maxCandidatePairs) {
          return candidates;
        }
      }
    }
    return candidates;
  }

  Duration? _durationFor(VideoItem item) {
    final mediaDuration = item.mediaDetails?.duration;
    if (mediaDuration != null && mediaDuration > Duration.zero) {
      return mediaDuration;
    }
    final playbackDuration = item.playbackDuration;
    return playbackDuration > Duration.zero ? playbackDuration : null;
  }

  double _candidateScore(VideoItem left, VideoItem right) {
    final leftDuration = _durationFor(left)!;
    final rightDuration = _durationFor(right)!;
    final tolerance = math.max(
      2500,
      (leftDuration.inMilliseconds * 0.06).round(),
    );
    final durationDistance =
        (leftDuration - rightDuration).inMilliseconds.abs() / tolerance;
    final leftDetails = left.mediaDetails;
    final rightDetails = right.mediaDetails;
    final leftWidth = leftDetails?.width;
    final leftHeight = leftDetails?.height;
    final rightWidth = rightDetails?.width;
    final rightHeight = rightDetails?.height;
    final shapeDistance = leftWidth == null ||
            leftHeight == null ||
            rightWidth == null ||
            rightHeight == null
        ? 0.0
        : ((leftWidth / leftHeight) - (rightWidth / rightHeight)).abs() / 0.08;
    final leftSize = left.fileSize;
    final rightSize = right.fileSize;
    final sizeDistance =
        leftSize == null || rightSize == null || leftSize <= 0 || rightSize <= 0
            ? 0.0
            : (math.log(leftSize / rightSize).abs() / math.log(4)).clamp(0, 4);
    return durationDistance * 0.7 + shapeDistance * 0.7 + sizeDistance * 0.35;
  }

  bool _compatibleVideoShape(VideoItem left, VideoItem right) {
    final leftDetails = left.mediaDetails;
    final rightDetails = right.mediaDetails;
    final leftWidth = leftDetails?.width;
    final leftHeight = leftDetails?.height;
    final rightWidth = rightDetails?.width;
    final rightHeight = rightDetails?.height;
    if (leftWidth == null ||
        leftHeight == null ||
        rightWidth == null ||
        rightHeight == null) {
      return true;
    }
    final leftRatio = leftWidth / leftHeight;
    final rightRatio = rightWidth / rightHeight;
    return (leftRatio - rightRatio).abs() <= 0.08;
  }

  bool _sameFingerprint(VideoItem left, VideoItem right) {
    final leftFingerprint = left.mediaFingerprint?.trim();
    final rightFingerprint = right.mediaFingerprint?.trim();
    return leftFingerprint != null &&
        leftFingerprint.isNotEmpty &&
        leftFingerprint == rightFingerprint;
  }

  Future<List<int>?> _signatureFor(
    VideoItem item,
    Map<String, List<int>?> cache,
  ) async {
    if (cache.containsKey(item.videoId)) {
      return cache[item.videoId];
    }
    final duration = _durationFor(item);
    if (duration == null || duration <= Duration.zero) {
      cache[item.videoId] = null;
      return null;
    }
    final hashes = <int>[];
    final cachedFrame = await _thumbnailService.ensureThumbnailFor(item);
    if (cachedFrame != null) {
      final hash = await _dHashFor(cachedFrame);
      if (hash != null) {
        hashes.add(hash);
      }
    }
    for (final fraction in _visualSampleFractions) {
      final position = Duration(
        microseconds: (duration.inMicroseconds * fraction).round(),
      );
      final frame = await _thumbnailService.previewFrameFor(item, position);
      if (frame == null) {
        continue;
      }
      final hash = await _dHashFor(frame);
      if (hash != null) {
        hashes.add(hash);
      }
    }
    final result = hashes.length < 3 ? null : hashes;
    cache[item.videoId] = result;
    return result;
  }

  Future<int?> _quickHashFor(
    VideoItem item,
    Map<String, int?> cache,
  ) async {
    if (cache.containsKey(item.videoId)) {
      return cache[item.videoId];
    }
    // 只读取已存在的有效 JPEG，不在候选预筛阶段触发 FFmpeg 生成任务。
    final frame = await _thumbnailService.thumbnailFor(item);
    final hash = frame == null ? null : await _dHashFor(frame);
    cache[item.videoId] = hash;
    return hash;
  }

  Future<int?> _dHashFor(File file) async {
    final bytes = await file.readAsBytes();
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 32,
        targetHeight: 18,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        return null;
      }
      return _dHash(data, image.width, image.height);
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  int _dHash(ByteData data, int width, int height) {
    final rows = 8;
    final columns = 9;
    var hash = 0;
    for (var row = 0; row < rows; row++) {
      final y = ((row + 0.5) * height / rows).floor().clamp(0, height - 1);
      for (var column = 0; column < columns - 1; column++) {
        final x =
            ((column + 0.5) * width / columns).floor().clamp(0, width - 1);
        final nextX =
            ((column + 1.5) * width / columns).floor().clamp(0, width - 1);
        final left = _luma(data, width, x, y);
        final right = _luma(data, width, nextX, y);
        hash <<= 1;
        if (left > right) {
          hash |= 1;
        }
      }
    }
    return hash;
  }

  int _luma(ByteData data, int width, int x, int y) {
    final offset = (y * width + x) * 4;
    final red = data.getUint8(offset);
    final green = data.getUint8(offset + 1);
    final blue = data.getUint8(offset + 2);
    return (red * 299 + green * 587 + blue * 114) ~/ 1000;
  }

  double _sequenceDistance(List<int> left, List<int> right) {
    var best = double.infinity;
    for (final offset in <int>[-1, 0, 1]) {
      var total = 0;
      var count = 0;
      for (var index = 0; index < left.length; index++) {
        final other = index + offset;
        if (other < 0 || other >= right.length) {
          continue;
        }
        total += _hamming(left[index] ^ right[other]);
        count++;
      }
      if (count > 0) {
        best = math.min(best, total / (count * 64));
      }
    }
    return best;
  }

  int _hamming(int value) {
    var bits = value.toUnsigned(64);
    var count = 0;
    while (bits != 0) {
      bits &= bits - 1;
      count++;
    }
    return count;
  }
}

void _recordMinimumScore(Map<int, double> scores, int index, double value) {
  final previous = scores[index];
  scores[index] =
      previous == null ? value : math.min(previous, value).toDouble();
}

/** 视觉扫描只返回本次页面需要的候选，不改变基础快速指纹报告。 */
class VideoVisualScanResult {
  const VideoVisualScanResult({
    required this.groups,
    required this.candidatePairCount,
    required this.comparedPairCount,
  });

  const VideoVisualScanResult.empty()
      : groups = const <VideoSimilarityGroup>[],
        candidatePairCount = 0,
        comparedPairCount = 0;

  final List<VideoSimilarityGroup> groups;
  final int candidatePairCount;
  final int comparedPairCount;
}

class _TimedVideo {
  const _TimedVideo({required this.index, required this.duration});

  final int index;
  final Duration duration;
}

class _VisualCandidate {
  const _VisualCandidate({
    required this.left,
    required this.right,
    required this.score,
  });

  final int left;
  final int right;
  final double score;
}

int _find(List<int> parent, int index) {
  var current = index;
  while (parent[current] != current) {
    parent[current] = parent[parent[current]];
    current = parent[current];
  }
  return current;
}

void _union(List<int> parent, int left, int right) {
  final leftRoot = _find(parent, left);
  final rightRoot = _find(parent, right);
  if (leftRoot != rightRoot) {
    parent[rightRoot] = leftRoot;
  }
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
