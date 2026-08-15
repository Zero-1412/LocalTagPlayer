import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/video_item.dart';
import '../../models/video_visual_signature.dart';
import '../../repositories/repository_interfaces.dart';
import '../media/thumbnail_service.dart';
import 'video_similarity_service.dart';

// ignore_for_file: slash_for_doc_comments

// 首帧只复用作廉价预筛；主体签名固定取 30%、50%、70% 三个中段采样点，
// 避免同作者共用片头/片尾模板或首帧水印成为近重复证据，同时不增加取帧数量。
const _visualSampleFractions = <double>[0.3, 0.5, 0.7];
// 签名首位保留首帧；它只能服务 quick hash，主体比较会显式跳过该位置。
const _missingVisualEdgeHash = -1;
/** 视觉结果仅作为人工复核候选，适度偏向召回率而不是自动删除的精确率。 */
const _visualDistanceThreshold = 0.28;
/** 未命中的采样点会增加距离，避免把“最佳帧”误称为整段视频相似度。 */
const _temporalCoveragePenalty = 0.5;
/** 难例召回只进入“待复核”组，不能绕过元数据/标题约束。 */
const _visualReviewDistanceThreshold = 0.56;
const _visualReviewMetadataScore = 0.72;
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
/** 缺少缓存首帧时只允许有限的 FFmpeg 深度回退，禁止首次进入相似页启动全库解码。 */
const _maxUncachedDeepCandidatePairs = 512;
/** 即使首帧已缓存，深度取帧也有全局上限；首帧命中仍需完整时序复核。 */
const _maxDeepVisualCandidatePairs = 2048;

/** 视觉复核的可见阶段，避免快速预筛结束后深度取帧仍只能显示无期限转圈。 */
enum VideoVisualScanPhase {
  buildingCandidates,
  comparingCandidates,
  extractingSignatures,
}

/** 页面使用的阶段进度；不把廉价预筛和 FFmpeg 深度取帧混成一个无意义的百分比。 */
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
 * 为扫描阶段统一记录耗时和吞吐率。
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

/**
 * 内容级近重复检测器。
 *
 * 先按时长/画面规格/文件大小为每个视频选择最相近邻居，再复用已有缩略图做廉价
 * 首帧 dHash 预筛，最后经 [ThumbnailService] 的 FFmpeg 取帧边界生成有序多帧 dHash。
 * 这样可以识别重新编码、容器变化或轻微裁剪后的复制品，同时避免同一时长密集区
 * 垄断全局候选；平台路径、外部进程或解码逻辑仍不进入页面，签名通过 Repository
 * 复用带身份校验的持久化派生缓存，失效时再回退到本轮取帧。
 */
class VideoContentSimilarityService {
  const VideoContentSimilarityService(
    this._thumbnailService, {
    VisualSignatureCacheRepository? visualSignatureCache,
  }) : _visualSignatureCache = visualSignatureCache;

  final ThumbnailService _thumbnailService;
  final VisualSignatureCacheRepository? _visualSignatureCache;

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
    // 深度候选按视频 ID 合并任务，避免同一视频同时出现在多个邻居对中时重复
    // 启动 FFmpeg；后面会以唯一视频为单位持续补充 worker，避免慢候选对拖住整批。
    final signatureTasks = <String, Future<List<int>?>>{};
    final persistedSignatures = <String, VideoVisualSignatureCacheEntry>{};
    final visualSignatureRepository = _visualSignatureCache;
    if (visualSignatureRepository != null) {
      final videoIds = <String>{
        for (final candidate in candidates) ...<String>{
          videos[candidate.left].videoId,
          videos[candidate.right].videoId,
        },
      };
      try {
        // 元数据表批量预热只做一次（内部按参数上限分块），避免每个候选视频
        // 启动一条独立查询；不存在或损坏的条目仍由本轮取帧回退重建。
        persistedSignatures.addAll(
          await visualSignatureRepository.loadVisualSignatures(videoIds),
        );
      } on Object {
        // 派生缓存读取失败只影响命中率，不能阻断相似候选搜索。
        persistedSignatures.clear();
      }
    }
    final quickHashes = <String, int?>{};
    final parent = List<int>.generate(videos.length, (index) => index);
    final matchedScores = <int, double>{};
    final reviewMatches = <int, bool>{};
    var uncachedDeepCandidates = 0;
    var deepComparedCandidates = 0;
    var compared = 0;
    var processed = 0;
    final deepCandidates = <_VisualCandidate>[];
    var pendingSignatureWrites = Future<void>.value();

    void enqueueSignatureWrite(VideoItem item, List<int> hashes) {
      pendingSignatureWrites = pendingSignatureWrites.then<void>(
        (_) => _savePersistedSignature(item, hashes),
      );
    }

    Future<VideoVisualSignatureCacheEntry?> persistedFor(VideoItem item) async {
      final cached = persistedSignatures[item.videoId];
      return cached != null && cached.matches(item) ? cached : null;
    }

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
      final task = _signatureFor(
        item,
        signatures,
        loadPersisted: persistedFor,
        onSignatureReady: enqueueSignatureWrite,
      );
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
          _quickHashFor(left, quickHashes, loadPersisted: persistedFor),
          _quickHashFor(right, quickHashes, loadPersisted: persistedFor),
        ],
      );
      final leftQuickHash = quickPair[0];
      final rightQuickHash = quickPair[1];
      final leftPersisted = persistedSignatures[left.videoId];
      final rightPersisted = persistedSignatures[right.videoId];
      final leftPersistedValid = leftPersisted != null &&
          leftPersisted.matches(left) &&
          leftPersisted.hashes.length >= 2;
      final rightPersistedValid = rightPersisted != null &&
          rightPersisted.matches(right) &&
          rightPersisted.hashes.length >= 2;
      // 持久化签名是完整时序证据；命中后直接比较内存中的签名，避免首帧预筛
      // 把单个巧合画面升格为 100% 结果，也避免每次重新启动 FFmpeg。
      if (leftPersistedValid && rightPersistedValid) {
        compared++;
        final match = _sequenceMatch(
          leftPersisted.hashes,
          rightPersisted.hashes,
        );
        if (match != null && _acceptVisualMatch(candidate, match)) {
          _union(parent, candidate.left, candidate.right);
          _recordMinimumScore(matchedScores, candidate.left, match.distance);
          _recordMinimumScore(matchedScores, candidate.right, match.distance);
          if (match.distance > _visualDistanceThreshold) {
            reviewMatches[candidate.left] = true;
            reviewMatches[candidate.right] = true;
          }
        }
        reportProcessed();
        continue;
      }
      if (leftQuickHash != null && rightQuickHash != null) {
        final quickDistance = _hamming(leftQuickHash ^ rightQuickHash) / 64;
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

    // 快速首帧预筛和深度取帧的成本量级不同；深度阶段按“唯一视频”计数，避免
    // 一个视频参与多个候选对时被重复估算。唯一任务池也让慢文件不会阻塞整批补充。
    final deepVideos = <String, VideoItem>{};
    for (final candidate in deepCandidates) {
      final left = videos[candidate.left];
      final right = videos[candidate.right];
      deepVideos[left.videoId] = left;
      deepVideos[right.videoId] = right;
    }
    final deepVideoList = deepVideos.values.toList(growable: false);
    final scheduledDeepVideos = List<VideoItem>.of(deepVideoList)
      // Longest-processing-time first reduces the tail when duration/size vary;
      // workers still pull continuously, so this only changes scheduling order.
      ..sort(_compareDeepWorkEstimate);

    var deepProcessed = 0;
    if (scheduledDeepVideos.isNotEmpty) {
      progress.report(
        VideoVisualScanPhase.extractingSignatures,
        0,
        scheduledDeepVideos.length,
      );
    }
    final workerCount = _visualComparisonWorkerCount();
    var nextDeepVideo = 0;
    Future<void> extractWorker() async {
      while (true) {
        if (cancelled()) {
          return;
        }
        final index = nextDeepVideo++;
        if (index >= scheduledDeepVideos.length) {
          return;
        }
        await _waitForScheduler(cancelled, shouldYield);
        if (cancelled()) {
          return;
        }
        await signatureFor(scheduledDeepVideos[index]);
        deepProcessed++;
        progress.report(
          VideoVisualScanPhase.extractingSignatures,
          deepProcessed,
          scheduledDeepVideos.length,
        );
      }
    }

    if (scheduledDeepVideos.isNotEmpty) {
      await Future.wait<void>(
        <Future<void>>[
          for (var index = 0;
              index < math.min(workerCount, scheduledDeepVideos.length);
              index++)
            extractWorker(),
        ],
      );
      if (cancelled()) {
        return const VideoVisualScanResult.cancelled();
      }
    }

    // 取帧完成后只比较内存中的 dHash 序列；比较本身不再被某个慢 FFmpeg 对拖住。
    for (final candidate in deepCandidates) {
      if (cancelled()) {
        return const VideoVisualScanResult.cancelled();
      }
      final left = videos[candidate.left];
      final right = videos[candidate.right];
      final leftSignature = signatures[left.videoId];
      final rightSignature = signatures[right.videoId];
      if (leftSignature != null && rightSignature != null) {
        compared++;
        final match = _sequenceMatch(leftSignature, rightSignature);
        if (match != null && _acceptVisualMatch(candidate, match)) {
          _union(parent, candidate.left, candidate.right);
          _recordMinimumScore(matchedScores, candidate.left, match.distance);
          _recordMinimumScore(matchedScores, candidate.right, match.distance);
          if (match.distance > _visualDistanceThreshold) {
            reviewMatches[candidate.left] = true;
            reviewMatches[candidate.right] = true;
          }
        }
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
      // 组分数取最弱成员边，而不是某一对最佳边；视觉百分比因此代表该组
      // 的保守匹配度，不再把传递合并或单帧巧合显示成 100%。
      final score = entry.value
          .map((index) => matchedScores[index])
          .whereType<double>()
          .fold<double?>(
              null,
              (worst, value) =>
                  worst == null ? value : math.max(worst, value).toDouble());
      final confidence =
          entry.value.any((index) => reviewMatches[index] == true)
              ? VideoVisualMatchConfidence.review
              : VideoVisualMatchConfidence.high;
      groups.add(
        VideoSimilarityGroup(
          // 分组结果不持久化；该值仅用于调试区分算法版本，缓存条目另走 Repository。
          fingerprint: videoVisualSignatureAlgorithm,
          kind: VideoSimilarityKind.visualNearDuplicate,
          visualScore: score,
          visualConfidence: confidence,
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

  /** 按预计解码成本从高到低排队，避免长视频集中落在深度扫描尾部。 */
  int _compareDeepWorkEstimate(VideoItem left, VideoItem right) {
    final leftDuration = _durationFor(left)?.inMilliseconds ?? 0;
    final rightDuration = _durationFor(right)?.inMilliseconds ?? 0;
    final duration = rightDuration.compareTo(leftDuration);
    if (duration != 0) {
      return duration;
    }
    final leftSize = left.fileSize ?? 0;
    final rightSize = right.fileSize ?? 0;
    final size = rightSize.compareTo(leftSize);
    if (size != 0) {
      return size;
    }
    return left.videoId.compareTo(right.videoId);
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

  Future<void> _savePersistedSignature(
    VideoItem item,
    List<int> hashes,
  ) async {
    final repository = _visualSignatureCache;
    if (repository == null ||
        hashes.length < 3 ||
        (item.mediaFingerprint == null &&
            item.fileSize == null &&
            item.modifiedMs == null)) {
      return;
    }
    try {
      await repository.saveVisualSignature(
        VideoVisualSignatureCacheEntry(
          videoId: item.videoId,
          algorithm: videoVisualSignatureAlgorithm,
          hashes: List<int>.unmodifiable(hashes),
          mediaFingerprint: item.mediaFingerprint,
          fileSize: item.fileSize,
          modifiedMs: item.modifiedMs,
        ),
      );
    } on Object {
      // 派生缓存写入失败不影响本轮已得到的视觉结果，下一轮可重试。
    }
  }

  Future<List<int>?> _signatureFor(
    VideoItem item,
    Map<String, List<int>?> cache, {
    Future<VideoVisualSignatureCacheEntry?> Function(VideoItem)? loadPersisted,
    void Function(VideoItem item, List<int> hashes)? onSignatureReady,
  }) async {
    if (cache.containsKey(item.videoId)) {
      return cache[item.videoId];
    }
    final persisted = await loadPersisted?.call(item);
    if (persisted != null) {
      cache[item.videoId] = persisted.hashes;
      return persisted.hashes;
    }
    final duration = _durationFor(item);
    final hashes = <int>[_missingVisualEdgeHash];
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
    final frames = await Future.wait<Uint8List?>(
      <Future<Uint8List?>>[
        for (final position in positions)
          _thumbnailService.similarityPreviewBytesFor(item, position),
      ],
    );
    for (final frame in frames) {
      if (frame == null) {
        continue;
      }
      final hash = await _dHashForBytes(frame);
      if (hash != null) {
        hashes.add(hash);
      }
    }
    // 单个时间点取帧失败不应吞掉整个候选；至少两个主体采样点仍能提供时序方向，最终只作为
    // 人工复核候选展示，不触发自动删除。
    final result = hashes.length < 3 ? null : hashes;
    cache[item.videoId] = result;
    if (result != null) {
      if (onSignatureReady != null) {
        onSignatureReady(item, result);
      } else {
        await _savePersistedSignature(item, result);
      }
    }
    return result;
  }

  Future<int?> _quickHashFor(
    VideoItem item,
    Map<String, int?> cache, {
    Future<VideoVisualSignatureCacheEntry?> Function(VideoItem)? loadPersisted,
  }) async {
    if (cache.containsKey(item.videoId)) {
      return cache[item.videoId];
    }
    final persisted = await loadPersisted?.call(item);
    if (persisted != null) {
      final hash = persisted.hashes.first;
      final quickHash = hash == _missingVisualEdgeHash ? null : hash;
      cache[item.videoId] = quickHash;
      return quickHash;
    }
    // 只读取已存在的有效 JPEG，不在候选预筛阶段触发 FFmpeg 生成任务。
    final frame = await _thumbnailService.thumbnailFor(item);
    final hash = frame == null ? null : await _dHashFor(frame);
    cache[item.videoId] = hash;
    return hash;
  }

  Future<int?> _dHashFor(File file) async {
    try {
      return _dHashForBytes(await file.readAsBytes());
    } on Object {
      // 缓存文件可能在校验和读取之间被清理；该帧失败不应中断整轮扫描。
      return null;
    }
  }

  Future<int?> _dHashForBytes(Uint8List bytes) async {
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

  _VisualSequenceMatch? _sequenceMatch(List<int> left, List<int> right) {
    // v5 签名首位是首帧预筛值；主体相似度只比较中段采样，隔离公共片头/片尾。
    final leftContent = left.length > 1 ? left.sublist(1) : const <int>[];
    final rightContent = right.length > 1 ? right.sublist(1) : const <int>[];
    if (leftContent.isEmpty || rightContent.isEmpty) {
      return null;
    }
    _VisualSequenceMatch? best;
    for (final offset in <int>[-1, 0, 1]) {
      final distances = <int>[];
      for (var index = 0; index < leftContent.length; index++) {
        final other = index + offset;
        if (other < 0 || other >= rightContent.length) {
          continue;
        }
        distances.add(_hamming(leftContent[index] ^ rightContent[other]));
      }
      final distance = _summarizeTemporalDistances(
        distances,
        expectedCount: math.max(leftContent.length, rightContent.length),
      );
      if (distance != null &&
          (best == null || distance.distance < best.distance)) {
        best = distance;
      }
    }
    // 不使用无序 nearest-neighbor：重复片头、黑场或水印可能让所有采样点
    // 找到同一个画面，从而制造虚假的满分；固定小 offset 更符合时序证据。
    return best;
  }

  bool _acceptVisualMatch(
    _VisualCandidate candidate,
    _VisualSequenceMatch match,
  ) {
    if (match.distance <= _visualDistanceThreshold) {
      return true;
    }
    return match.distance <= _visualReviewDistanceThreshold &&
        (candidate.titleMatch || candidate.score <= _visualReviewMetadataScore);
  }

  /**
   * 将采样点距离压成带覆盖约束的距离。
   *
   * 单纯平均值会让一个相同片段掩盖其余不相似画面；这里保留命中覆盖率并为
   * 未命中点增加惩罚，严格组与 review 组再使用不同距离门槛，使结果仍是人工候选而非概率。
   */
  _VisualSequenceMatch? _summarizeTemporalDistances(
    List<int> distances, {
    required int expectedCount,
  }) {
    if (distances.isEmpty) {
      return null;
    }
    final normalized =
        distances.map((distance) => distance / 64).toList(growable: false);
    final hits = normalized
        .where((distance) => distance <= _visualDistanceThreshold)
        .length;
    final missing = math.max(0, expectedCount - normalized.length);
    final coverage = hits / expectedCount;
    final mean =
        (normalized.fold<double>(0, (sum, value) => sum + value) + missing) /
            expectedCount;
    return _VisualSequenceMatch(
      distance: mean + (1 - coverage) * _temporalCoveragePenalty,
      coverage: coverage,
    );
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

/** 时序签名的保守距离和命中覆盖率；review 组使用同一距离轴但单独标记证据等级。 */
class _VisualSequenceMatch {
  const _VisualSequenceMatch({required this.distance, required this.coverage});

  final double distance;
  final double coverage;
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
