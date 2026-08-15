import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/video_item.dart';
import '../media/thumbnail_service.dart';
import 'video_similarity_service.dart';

// ignore_for_file: slash_for_doc_comments

// 首帧复用媒体库缩略图，另外取四分之一、二分之一和四分之三处的帧；避免只因
// 片头/片尾或首帧水印变化就漏掉同一内容，同时仍把取帧数量限制在有界候选内。
const _visualSampleFractions = <double>[0.25, 0.5, 0.75];
/** 视觉结果仅作为人工复核候选，适度偏向召回率而不是自动删除的精确率。 */
const _visualDistanceThreshold = 0.28;
/**
 * 候选上限只作为异常大库的保护；候选选择本身按每个视频分摊，不能再取全局
 * 时长排序的前 N 对，否则同一时长密集区会饿死其它视频。
 */
const _maxVisualCandidatePairs = 131072;
/** 每个视频保留多条候选通道；全局上限只保护异常大库，不再只覆盖前几条邻居。 */
const _maxVisualNeighborsPerVideo = 32;
/** 密集时长区只保留有限的本地评分池，避免 1 万级媒体库构造数千万临时对象。 */
const _maxLocalCandidatePool = 256;
/** 对最近时长邻居保留少量画幅变化通道，覆盖裁切/加黑边而不放大为全量笛卡尔积。 */
const _maxRelaxedShapeNeighbors = 48;
/** 重新编码/剪辑后仍允许一定时长漂移；最终结果还要通过多帧视觉复核。 */
const _visualDurationTolerance = 0.2;
const _visualMinDurationToleranceMs = 3000;
/** 允许裁切、加黑边或横竖画幅变化进入人工复核候选。 */
const _visualShapeTolerance = 0.25;
/** 首帧只做廉价预筛；接近元数据的候选即使首帧变化也必须深度复核。 */
const _quickVisualDistanceThreshold = 0.45;
const _quickRejectMetadataScore = 0.75;
/** 首帧已经高度相似时可直接进入人工复核组，不再为每对视频重复取四个 FFmpeg 帧。 */
const _quickMatchDistanceThreshold = 0.16;
/** 缺少缓存首帧时只允许有限的 FFmpeg 深度回退，禁止首次进入相似页启动全库解码。 */
const _maxUncachedDeepCandidatePairs = 512;
/** 即使首帧已缓存，深度取帧也有全局上限；强匹配仍走廉价首帧路径。 */
const _maxDeepVisualCandidatePairs = 2048;

/** 视觉复核的两个可见阶段，避免候选构建期间只能显示无期限转圈。 */
enum VideoVisualScanPhase {
  buildingCandidates,
  comparingCandidates,
}

/** 页面使用的阶段进度；不把候选构建和 FFmpeg 取帧混成一个无意义的百分比。 */
class VideoVisualScanProgress {
  const VideoVisualScanProgress({
    required this.phase,
    required this.processed,
    required this.total,
    this.elapsed = Duration.zero,
    this.estimatedRemaining,
    this.itemsPerSecond,
  });

  final VideoVisualScanPhase phase;
  final int processed;
  final int total;

  /** 扫描启动后的累计耗时；用于把“转圈”变成可判断的运行状态。 */
  final Duration elapsed;

  /** 依据当前阶段吞吐率推测的剩余时间；预热不足时为空。 */
  final Duration? estimatedRemaining;

  /** 当前阶段的平滑处理速度，单位为候选项/秒。 */
  final double? itemsPerSecond;
}

/**
 * 为两个扫描阶段统一记录耗时和吞吐率。
 *
 * 候选构建和视觉比较的工作量不同，不能把它们拼成一个百分比再套固定总时长。
 * 阶段切换时重置速率窗口，前几项先显示“正在估算”，避免首个慢取帧把 ETA 放大。
 */
class _VisualScanProgressReporter {
  _VisualScanProgressReporter(this._onProgress)
      : _overall = Stopwatch()..start(),
        _phaseClock = Stopwatch()..start();

  final void Function(VideoVisualScanProgress progress)? _onProgress;
  final Stopwatch _overall;
  Stopwatch _phaseClock;
  VideoVisualScanPhase? _phase;
  double? _smoothedRate;

  void report(VideoVisualScanPhase phase, int processed, int total) {
    if (_onProgress == null) {
      return;
    }
    if (_phase != phase) {
      _phase = phase;
      _phaseClock = Stopwatch()..start();
      _smoothedRate = null;
    }
    final safeTotal = math.max(total, 1);
    final safeProcessed = processed.clamp(0, safeTotal);
    final elapsedMicros = _phaseClock.elapsed.inMicroseconds;
    final phaseSeconds = elapsedMicros / Duration.microsecondsPerSecond;
    double? rate;
    if (safeProcessed >= 4 && phaseSeconds >= 0.25) {
      final instantRate = safeProcessed / phaseSeconds;
      _smoothedRate = _smoothedRate == null
          ? instantRate
          : (_smoothedRate! * 0.7) + (instantRate * 0.3);
      rate = _smoothedRate;
    }
    Duration? remaining;
    if (rate != null && safeProcessed < safeTotal && rate > 0) {
      remaining = Duration(
        microseconds: ((safeTotal - safeProcessed) /
                rate *
                Duration.microsecondsPerSecond)
            .round(),
      );
    }
    _onProgress(
      VideoVisualScanProgress(
        phase: phase,
        processed: safeProcessed,
        total: safeTotal,
        elapsed: _overall.elapsed,
        estimatedRemaining: remaining,
        itemsPerSecond: rate,
      ),
    );
  }
}

/** 深度复核任务只携带结果，合并候选组仍在主扫描顺序中完成，保证结果稳定。 */
class _VisualSignaturePair {
  const _VisualSignaturePair(this.left, this.right);

  final List<int>? left;
  final List<int>? right;
}

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
    bool Function()? isCancelled,
    bool Function()? shouldYield,
    void Function(VideoVisualScanProgress progress)? onProgress,
  }) async {
    if (maxCandidatePairs <= 0) {
      return const VideoVisualScanResult.empty();
    }
    final excluded = excludedVideoIds.toSet();
    final cancelled = isCancelled ?? () => false;
    final videos = source
        .where((item) => !item.isMissing && !excluded.contains(item.videoId))
        .toList(growable: false);
    final progress = _VisualScanProgressReporter(onProgress);
    // 让页面首帧和已有缩略图任务先运行；候选构建虽有界，仍可能在密集时长区
    // 触发大量比较与排序，不能在调用方首个事件循环里同步占满 UI 线程。
    final candidates = await _buildCandidates(
      videos,
      maxCandidatePairs,
      isCancelled: cancelled,
      shouldYield: shouldYield,
      onProgress: (item) => progress.report(
        item.phase,
        item.processed,
        item.total,
      ),
    );
    if (candidates == null || cancelled()) {
      return const VideoVisualScanResult.cancelled();
    }
    if (candidates.isEmpty) {
      return const VideoVisualScanResult.empty();
    }
    await _waitForScheduler(cancelled, shouldYield);
    if (cancelled()) {
      return const VideoVisualScanResult.cancelled();
    }
    progress.report(
      VideoVisualScanPhase.comparingCandidates,
      0,
      candidates.length,
    );

    final signatures = <String, List<int>?>{};
    // 深度候选按视频 ID 合并 in-flight 任务，避免同一视频同时出现在多个邻居
    // 对中时重复启动 FFmpeg；批次大小再按 CPU 档位有界放大，保持可取消和可让渡。
    final signatureTasks = <String, Future<List<int>?>>{};
    final quickHashes = <String, int?>{};
    final parent = List<int>.generate(videos.length, (index) => index);
    final matchedScores = <int, double>{};
    var uncachedDeepCandidates = 0;
    var deepComparedCandidates = 0;
    var compared = 0;
    var processed = 0;
    final deepCandidates = <_VisualCandidate>[];

    void reportProcessed() {
      processed++;
      progress.report(
        VideoVisualScanPhase.comparingCandidates,
        processed,
        candidates.length,
      );
    }

    Future<List<int>?> signatureFor(VideoItem item) {
      final cached = signatureTasks[item.videoId];
      if (cached != null) {
        return cached;
      }
      final task = _signatureFor(item, signatures);
      signatureTasks[item.videoId] = task;
      return task;
    }

    for (var candidateIndex = 0;
        candidateIndex < candidates.length;
        candidateIndex++) {
      if (cancelled()) {
        return const VideoVisualScanResult.cancelled();
      }
      await _waitForScheduler(cancelled, shouldYield);
      if (cancelled()) {
        return const VideoVisualScanResult.cancelled();
      }
      final candidate = candidates[candidateIndex];
      final left = videos[candidate.left];
      final right = videos[candidate.right];
      // 已有文件级指纹命中的组不再重复触发取帧；页面会单独展示它们。
      if (_sameFingerprint(left, right)) {
        reportProcessed();
        continue;
      }
      // 两端首帧都只经过缓存边界，允许同时排队；在低端机器上仍由
      // ThumbnailService 的 regular queue 限制实际解码并发。
      final quickPair = await Future.wait<int?>(
        <Future<int?>>[
          _quickHashFor(left, quickHashes),
          _quickHashFor(right, quickHashes),
        ],
      );
      final leftQuickHash = quickPair[0];
      final rightQuickHash = quickPair[1];
      if (leftQuickHash != null && rightQuickHash != null) {
        final quickDistance = _hamming(leftQuickHash ^ rightQuickHash) / 64;
        if (quickDistance <= _quickMatchDistanceThreshold) {
          _union(parent, candidate.left, candidate.right);
          _recordMinimumScore(matchedScores, candidate.left, quickDistance);
          _recordMinimumScore(matchedScores, candidate.right, quickDistance);
          compared++;
          reportProcessed();
          continue;
        }
        if (quickDistance > _quickVisualDistanceThreshold &&
            candidate.score > _quickRejectMetadataScore &&
            !candidate.titleMatch) {
          reportProcessed();
          continue;
        }
      }
      if (leftQuickHash == null || rightQuickHash == null) {
        // 单侧或双侧缺缓存都计入回退配额，避免 ensureThumbnailFor 的播放器兜底
        // 在大库中为每个候选逐个启动解码。
        if (uncachedDeepCandidates >= _maxUncachedDeepCandidatePairs) {
          reportProcessed();
          continue;
        }
        uncachedDeepCandidates++;
      }
      if (deepComparedCandidates >= _maxDeepVisualCandidatePairs) {
        reportProcessed();
        continue;
      }
      deepComparedCandidates++;
      deepCandidates.add(candidate);
    }

    final workerCount = _visualComparisonWorkerCount();
    for (var offset = 0;
        offset < deepCandidates.length;
        offset += workerCount) {
      if (cancelled()) {
        return const VideoVisualScanResult.cancelled();
      }
      await _waitForScheduler(cancelled, shouldYield);
      if (cancelled()) {
        return const VideoVisualScanResult.cancelled();
      }
      final batch = deepCandidates.skip(offset).take(workerCount).toList();
      final results = await Future.wait<_VisualSignaturePair>(
        batch.map((candidate) async {
          final left = videos[candidate.left];
          final right = videos[candidate.right];
          final pairSignatures = await Future.wait<List<int>?>(
            <Future<List<int>?>>[
              signatureFor(left),
              signatureFor(right),
            ],
          );
          return _VisualSignaturePair(pairSignatures[0], pairSignatures[1]);
        }),
      );
      for (var index = 0; index < batch.length; index++) {
        if (cancelled()) {
          return const VideoVisualScanResult.cancelled();
        }
        final candidate = batch[index];
        final result = results[index];
        final leftSignature = result.left;
        final rightSignature = result.right;
        if (leftSignature != null && rightSignature != null) {
          compared++;
          final distance = _sequenceDistance(leftSignature, rightSignature);
          if (distance <= _visualDistanceThreshold) {
            _union(parent, candidate.left, candidate.right);
            _recordMinimumScore(matchedScores, candidate.left, distance);
            _recordMinimumScore(matchedScores, candidate.right, distance);
          }
        }
        reportProcessed();
      }
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
          fingerprint: 'visual-dhash-v3',
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

  Future<List<_VisualCandidate>?> _buildCandidates(
    List<VideoItem> videos,
    int maxCandidatePairs, {
    required bool Function() isCancelled,
    bool Function()? shouldYield,
    void Function(VideoVisualScanProgress progress)? onProgress,
  }) async {
    await Future<void>.delayed(Duration.zero);
    if (isCancelled()) {
      return null;
    }
    final indexed = <_TimedVideo>[];
    for (var index = 0; index < videos.length; index++) {
      final duration = _durationFor(videos[index]);
      if (duration == null || duration <= Duration.zero) {
        continue;
      }
      indexed.add(_TimedVideo(index: index, duration: duration));
      if (index % 64 == 0) {
        await Future<void>.delayed(Duration.zero);
        await _waitForScheduler(isCancelled, shouldYield);
      }
    }
    indexed.sort((a, b) => a.duration.compareTo(b.duration));
    // 候选构建阶段按实际进入时长邻居筛选的视频计数，避免把内部两轮循环
    // 暴露为用户难以理解的两倍总量；无时长但命中文名通道的极小库会显示 1/1。
    final candidateBuildTotal = math.max(indexed.length, 1);
    _reportCandidateProgress(
      onProgress,
      0,
      candidateBuildTotal,
    );
    final rankedByVideo = <List<_VisualCandidate>>[
      for (var index = 0; index < videos.length; index++) <_VisualCandidate>[],
    ];
    void addCandidate(_VisualCandidate candidate) {
      if (candidate.titleMatch) {
        rankedByVideo[candidate.left].insert(0, candidate);
        rankedByVideo[candidate.right].insert(0, candidate);
      } else {
        rankedByVideo[candidate.left].add(candidate);
        rankedByVideo[candidate.right].add(candidate);
      }
    }

    final seen = <String, _VisualCandidate>{};
    for (var i = 0; i < indexed.length; i++) {
      if (isCancelled()) {
        return null;
      }
      await _waitForScheduler(isCancelled, shouldYield);
      if (isCancelled()) {
        return null;
      }
      if (i % 8 == 0) {
        // 大库中同一时长可能有数千条记录；批次间让出事件循环，保证滚动和返回
        // 操作仍可响应，候选覆盖规则本身不变。
        await Future<void>.delayed(Duration.zero);
      }
      _reportCandidateProgress(
        onProgress,
        i + 1,
        candidateBuildTotal,
      );
      final left = indexed[i];
      final local = <_VisualCandidate>[];
      final toleranceMs = math.max(
        _visualMinDurationToleranceMs,
        (left.duration.inMilliseconds * _visualDurationTolerance).round(),
      );
      void addLocalCandidate(_VisualCandidate candidate) {
        if (local.length < _maxLocalCandidatePool) {
          local.add(candidate);
          return;
        }
        var worstIndex = 0;
        for (var index = 1; index < local.length; index++) {
          if (local[index].score > local[worstIndex].score) {
            worstIndex = index;
          }
        }
        if ((candidate.relaxedShape && !local[worstIndex].relaxedShape) ||
            candidate.score < local[worstIndex].score) {
          local[worstIndex] = candidate;
        }
      }

      for (var j = i + 1; j < indexed.length; j++) {
        final right = indexed[j];
        final durationDeltaMs =
            right.duration.inMilliseconds - left.duration.inMilliseconds;
        final rightToleranceMs = math.max(
          _visualMinDurationToleranceMs,
          (right.duration.inMilliseconds * _visualDurationTolerance).round(),
        );
        if (durationDeltaMs > math.max(toleranceMs, rightToleranceMs)) {
          break;
        }
        if (!_compatibleVideoShape(videos[left.index], videos[right.index])) {
          continue;
        }
        addLocalCandidate(_VisualCandidate(
          left: left.index,
          right: right.index,
          score: _candidateScore(videos[left.index], videos[right.index]),
        ));
      }
      final relaxedEnd = math.min(
        indexed.length,
        i + 1 + _maxRelaxedShapeNeighbors,
      );
      for (var j = i + 1; j < relaxedEnd; j++) {
        final right = indexed[j];
        final durationDeltaMs =
            right.duration.inMilliseconds - left.duration.inMilliseconds;
        final rightToleranceMs = math.max(
          _visualMinDurationToleranceMs,
          (right.duration.inMilliseconds * _visualDurationTolerance).round(),
        );
        if (durationDeltaMs > math.max(toleranceMs, rightToleranceMs)) {
          break;
        }
        if (_compatibleVideoShape(videos[left.index], videos[right.index]) ||
            _sizeDistanceFor(videos[left.index], videos[right.index]) >
                math.log(16)) {
          continue;
        }
        addLocalCandidate(
          _VisualCandidate(
            left: left.index,
            right: right.index,
            score: _candidateScore(videos[left.index], videos[right.index]),
            relaxedShape: true,
          ),
        );
      }
      local.sort((a, b) {
        final score = a.score.compareTo(b.score);
        if (score != 0) return score;
        final left = a.left.compareTo(b.left);
        return left != 0 ? left : a.right.compareTo(b.right);
      });
      // 综合分优先覆盖常见副本；再单独补入时长/大小近邻，避免“大小差异大”或
      // “片头剪辑导致时长差异”把真实副本排到默认邻居之外。
      final selected = <String, _VisualCandidate>{};
      void addLane(Iterable<_VisualCandidate> lane, int limit) {
        var added = 0;
        for (final candidate in lane) {
          final key = _candidateKey(candidate);
          if (selected.containsKey(key)) continue;
          selected[key] = candidate;
          added++;
          if (added >= limit) break;
        }
      }

      addLane(local.where((candidate) => candidate.relaxedShape), 8);
      addLane(local, 16);
      final byDuration = List<_VisualCandidate>.of(local)
        ..sort((a, b) => _durationDeltaFor(
              videos[a.left],
              videos[a.right],
            ).compareTo(_durationDeltaFor(videos[b.left], videos[b.right])));
      addLane(byDuration, 4);
      final bySize = List<_VisualCandidate>.of(local)
        ..sort((a, b) => _sizeDistanceFor(videos[a.left], videos[a.right])
            .compareTo(_sizeDistanceFor(videos[b.left], videos[b.right])));
      addLane(bySize, 4);
      for (final candidate
          in selected.values.take(_maxVisualNeighborsPerVideo)) {
        addCandidate(candidate);
      }
    }

    // 文件名相同或只多了 Source/1080p/副本后缀的重下载，不能因为时长探测漂移或
    // 画幅变化而完全错过；标题只负责扩大人工复核召回，最终仍必须通过视觉比较。
    final titleBuckets = <String, List<int>>{};
    for (var index = 0; index < videos.length; index++) {
      final key = _normalizedTitleKey(videos[index].title);
      if (key != null) {
        (titleBuckets[key] ??= <int>[]).add(index);
      }
    }
    for (final bucket in titleBuckets.values) {
      if (isCancelled()) {
        return null;
      }
      if (bucket.length < 2 || bucket.length > 64) {
        continue;
      }
      for (var leftIndex = 0; leftIndex < bucket.length; leftIndex++) {
        for (var rightIndex = leftIndex + 1;
            rightIndex < bucket.length;
            rightIndex++) {
          final leftIndexValue = bucket[leftIndex];
          final rightIndexValue = bucket[rightIndex];
          addCandidate(
            _VisualCandidate(
              left: leftIndexValue,
              right: rightIndexValue,
              score: _candidateScore(
                videos[leftIndexValue],
                videos[rightIndexValue],
              ),
              titleMatch: true,
            ),
          );
        }
      }
    }

    _reportCandidateProgress(
      onProgress,
      candidateBuildTotal,
      candidateBuildTotal,
    );

    // 按邻居轮次交错不同 duration 区间，保证候选上限也不会只覆盖排序最前端。
    final candidates = <_VisualCandidate>[];
    for (var round = 0; round < _maxVisualNeighborsPerVideo; round++) {
      for (final ranked in rankedByVideo) {
        if (round >= ranked.length) continue;
        final candidate = ranked[round];
        final key = _candidateKey(candidate);
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

  void _reportCandidateProgress(
    void Function(VideoVisualScanProgress progress)? onProgress,
    int processed,
    int total,
  ) {
    if (onProgress == null) {
      return;
    }
    final safeTotal = math.max(total, 1);
    final safeProcessed = processed.clamp(0, safeTotal);
    if (safeProcessed == safeTotal || safeProcessed % 64 == 0) {
      onProgress(
        VideoVisualScanProgress(
          phase: VideoVisualScanPhase.buildingCandidates,
          processed: safeProcessed,
          total: safeTotal,
        ),
      );
    }
  }

  Future<void> _waitForScheduler(
    bool Function() isCancelled,
    bool Function()? shouldYield,
  ) async {
    while (shouldYield?.call() == true && !isCancelled()) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /**
   * 深度签名任务按机器档位有界并发；实际 FFmpeg 数量仍由 ThumbnailService
   * 的相似度队列控制，避免把“加并发”变成进程风暴。
   */
  int _visualComparisonWorkerCount() {
    final processors = Platform.numberOfProcessors;
    if (processors >= 12) return 4;
    if (processors >= 8) return 3;
    return 2;
  }

  Duration? _durationFor(VideoItem item) {
    final mediaDuration = item.mediaDetails?.duration;
    if (mediaDuration != null && mediaDuration > Duration.zero) {
      return mediaDuration;
    }
    final playbackDuration = item.playbackDuration;
    return playbackDuration > Duration.zero ? playbackDuration : null;
  }

  int _durationDeltaFor(VideoItem left, VideoItem right) {
    final leftDuration = _durationFor(left);
    final rightDuration = _durationFor(right);
    if (leftDuration == null || rightDuration == null) {
      return 1 << 62;
    }
    return (leftDuration - rightDuration).inMilliseconds.abs();
  }

  double _sizeDistanceFor(VideoItem left, VideoItem right) {
    final leftSize = left.fileSize;
    final rightSize = right.fileSize;
    if (leftSize == null ||
        rightSize == null ||
        leftSize <= 0 ||
        rightSize <= 0) {
      return 0;
    }
    return math.log(leftSize / rightSize).abs();
  }

  String _candidateKey(_VisualCandidate candidate) {
    final left = math.min(candidate.left, candidate.right);
    final right = math.max(candidate.left, candidate.right);
    return '$left:$right';
  }

  double _candidateScore(VideoItem left, VideoItem right) {
    final leftDuration = _durationFor(left);
    final rightDuration = _durationFor(right);
    final durationDistance = leftDuration == null || rightDuration == null
        ? 0.75
        : (leftDuration - rightDuration).inMilliseconds.abs() /
            math.max(
              _visualMinDurationToleranceMs,
              (math.max(leftDuration.inMilliseconds,
                          rightDuration.inMilliseconds) *
                      _visualDurationTolerance)
                  .round(),
            );
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
        : ((leftWidth / leftHeight) - (rightWidth / rightHeight)).abs() /
            _visualShapeTolerance;
    final leftSize = left.fileSize;
    final rightSize = right.fileSize;
    final sizeDistance =
        leftSize == null || rightSize == null || leftSize <= 0 || rightSize <= 0
            ? 0.0
            : (math.log(leftSize / rightSize).abs() / math.log(4)).clamp(0, 4);
    return durationDistance * 0.7 + shapeDistance * 0.7 + sizeDistance * 0.35;
  }

  /** 归一化文件名中的质量/副本后缀，作为额外人工复核召回通道。 */
  String? _normalizedTitleKey(String title) {
    final rawTokens = title
        .toLowerCase()
        // 保留中日韩统一表意文字、日文假名和韩文音节；其它符号通常是
        // 分辨率、来源或站点后缀的分隔符，统一折叠为空格。
        .replaceAll(
          RegExp(r'[^a-z0-9\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]+'),
          ' ',
        )
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    const ignored = <String>{
      'source',
      'copy',
      'duplicate',
      'dup',
      'final',
      'new',
      '1080p',
      '1440p',
      '2160p',
      '4k',
      '720p',
      '480p',
    };
    final tokens =
        rawTokens.where((token) => !ignored.contains(token)).toList();
    if (tokens.isEmpty) {
      return null;
    }
    final key = tokens.join(' ');
    // 过短的泛化名称会制造大量无意义候选；数字 ID/中日韩标题允许单 token。
    if (key.length < 5 &&
        !RegExp(r'[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]').hasMatch(key)) {
      return null;
    }
    return key.length > 96 ? key.substring(0, 96) : key;
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
    return (leftRatio - rightRatio).abs() <= _visualShapeTolerance;
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
    final hashes = <int>[];
    // 视觉复核不能把不可见的全库视频提升为播放器兜底任务；只读取已有首帧，
    // 需要深度复核时再通过 ThumbnailService 的批量取帧边界走有界预算。
    final cachedFrame = await _thumbnailService.thumbnailFor(item);
    if (cachedFrame != null) {
      final hash = await _dHashFor(cachedFrame);
      if (hash != null) {
        hashes.add(hash);
      }
    }
    final positions = duration == null || duration <= Duration.zero
        ? const <Duration>[
            Duration(seconds: 10),
            Duration(seconds: 60),
            Duration(seconds: 180),
          ]
        : <Duration>[
            for (final fraction in _visualSampleFractions)
              Duration(
                microseconds: (duration.inMicroseconds * fraction).round(),
              ),
          ];
    final frames = await Future.wait<File?>(
      <Future<File?>>[
        for (final position in positions)
          _thumbnailService.similarityPreviewFrameFor(item, position),
      ],
    );
    for (final frame in frames) {
      if (frame == null) {
        continue;
      }
      final hash = await _dHashFor(frame);
      if (hash != null) {
        hashes.add(hash);
      }
    }
    // 单个时间点取帧失败不应吞掉整个候选；至少两帧仍能提供时序方向，最终只作为
    // 人工复核候选展示，不触发自动删除。
    final result = hashes.length < 2 ? null : hashes;
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
    // 分数轴被片头/片尾剪辑后，固定 offset 仍可能错位；对每帧取另一侧最近邻
    // 再做双向平均，补足轻微时间轴变化，同时保留 offset 结果的严格下界。
    double nearestAverage(List<int> source, List<int> target) {
      if (source.isEmpty || target.isEmpty) {
        return double.infinity;
      }
      var total = 0;
      for (final hash in source) {
        var nearest = 64;
        for (final candidate in target) {
          nearest = math.min(nearest, _hamming(hash ^ candidate));
        }
        total += nearest;
      }
      return total / (source.length * 64);
    }

    final nearest =
        (nearestAverage(left, right) + nearestAverage(right, left)) / 2;
    return math.min(best, nearest);
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
    this.cancelled = false,
  });

  const VideoVisualScanResult.empty()
      : groups = const <VideoSimilarityGroup>[],
        candidatePairCount = 0,
        comparedPairCount = 0,
        cancelled = false;

  const VideoVisualScanResult.cancelled()
      : groups = const <VideoSimilarityGroup>[],
        candidatePairCount = 0,
        comparedPairCount = 0,
        cancelled = true;

  final List<VideoSimilarityGroup> groups;
  final int candidatePairCount;
  final int comparedPairCount;
  /** 刷新、删除或离开时取消的旧任务不能覆盖当前候选快照。 */
  final bool cancelled;
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
    this.titleMatch = false,
    this.relaxedShape = false,
  });

  final int left;
  final int right;
  final double score;
  final bool titleMatch;
  final bool relaxedShape;
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
