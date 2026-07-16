import 'dart:async';
import 'dart:collection';

import '../../models/media_details.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../platform/platform_interfaces.dart';

// ignore_for_file: slash_for_doc_comments

/** 媒体探测完成后交给 Repository 持久化的单条不可变更新。 */
class MediaDetailsUpdate {
  const MediaDetailsUpdate({
    required this.item,
    required this.details,
    required this.fingerprint,
  });

  /** 当前媒体库中的稳定视频对象。 */
  final VideoItem item;

  /** 本次探测得到的轻量媒体详情；失败时为空详情。 */
  final MediaDetails details;

  /** 入队时的视频指纹，用于阻止旧任务覆盖已变化文件。 */
  final String? fingerprint;
}

/** 媒体详情后台队列进度快照，供媒体库显示可理解的导入阶段。 */
class MediaDetailsProgress {
  const MediaDetailsProgress({
    required this.total,
    required this.completed,
    required this.failed,
    required this.queued,
    required this.active,
    this.itemsPerSecond,
    this.estimatedRemaining,
    this.isPaused = false,
  });

  /** 本轮实际需要探测的总文件数，不包含已缓存详情。 */
  final int total;

  /** 本轮成功探测并完成 Repository 回写的文件数。 */
  final int completed;

  /** 本轮探测或回写失败的文件数；失败也计入已处理进度。 */
  final int failed;

  /** 尚未交给原生批次执行的文件数。 */
  final int queued;

  /** 当前原生批次正在处理的文件数。 */
  final int active;

  /** 按最近批次平滑后的处理速度；首批完成前为空。 */
  final double? itemsPerSecond;

  /** 按平滑速度估算的剩余时间；样本不足或已经完成时为空。 */
  final Duration? estimatedRemaining;

  /** 是否已阻止后续后台批次启动；活动小批次允许自然收尾。 */
  final bool isPaused;

  /** 已处理文件数，包含失败项，避免进度因异常文件永久停滞。 */
  int get processed => completed + failed;

  /** 供确定型进度条使用的安全比例。 */
  double get fraction => total <= 0 ? 0 : (processed / total).clamp(0, 1);

  /** 本轮全部条目均已得到成功或失败结论。 */
  bool get isComplete => total > 0 && processed >= total;
}

/**
 * 单条媒体详情任务。
 *
 * 服务仍然只允许一个原生探测任务执行；优先级只决定尚未开始任务的顺序，避免可视项
 * 被数千条扫描后台任务长期阻塞。
 */
class _MediaDetailsJob {
  _MediaDetailsJob({
    required this.item,
    required this.cached,
    required this.generation,
    required this.completer,
    required this.priority,
  });

  /** 需要读取详情的视频对象。 */
  final VideoItem item;

  /** 入队时可复用的不完整缓存；任务取消时作为安全回退。 */
  final MediaDetails? cached;

  /** 创建任务时的服务代次，旧代结果不得回写。 */
  final int generation;

  /** 让同一路径的多个调用方共享同一个完成信号。 */
  final Completer<MediaDetails> completer;

  /** true 表示媒体库或播放器当前可视区域请求。 */
  bool priority;
}

/**
 * 串行协调媒体详情缓存、原生探测与 Repository 回写。
 *
 * 服务把可视请求与扫描后台请求分队列排序，但任意时刻只运行一个平台探测，避免
 * FFprobe 与播放器或缩略图任务并发争抢本地磁盘。
 */
class MediaDetailsService {
  MediaDetailsService({
    this.onUpdated,
    this.onBatchUpdated,
    this.onProgress,
    required MediaProbeBackend probeBackend,
  })  : _probeBackend = probeBackend,
        _generation = _nextGeneration++;

  /**
   * 单个后台原生批次的最大文件数。
   *
   * 小批次减少平台通道和 SQLite 往返，同时限制可见项等待当前后台批次的最长时间。
   */
  static const int _maxBackgroundBatchSize = 8;

  /** 进程内递增代号，避免多个播放器页面取消同一个原生 generation。 */
  static int _nextGeneration = 1;

  final Future<void> Function(
      VideoItem item, MediaDetails details, String? fingerprint)? onUpdated;

  /** 批量 Repository 回写入口；存在时优先于逐条 [onUpdated]，避免大目录逐条提交。 */
  final Future<void> Function(List<MediaDetailsUpdate> updates)? onBatchUpdated;

  /** 队列总量或批次完成时报告轻量进度；不得在回调中启动新的媒体探测。 */
  final void Function(MediaDetailsProgress progress)? onProgress;

  /** 批量媒体探测平台边界；SQLite 写回仍由回调所在 Repository 完成。 */
  final MediaProbeBackend _probeBackend;
  final Map<String, Future<MediaDetails>> _inFlight = {};
  final Map<String, MediaDetails> _cache = {};
  final Set<String> _queuedPaths = {};

  /** 等待执行的可视区域任务，最新可视项优先。 */
  final Queue<_MediaDetailsJob> _priorityJobs = Queue<_MediaDetailsJob>();

  /** 扫描产生的后台任务，按原入队顺序执行。 */
  final Queue<_MediaDetailsJob> _backgroundJobs = Queue<_MediaDetailsJob>();

  /** 按路径索引尚未执行的任务，供可视请求原地提升而不重复探测。 */
  final Map<String, _MediaDetailsJob> _queuedJobs =
      <String, _MediaDetailsJob>{};

  /** 当前唯一运行的原生探测批次；批次内部仍由平台单工作线程串行读取。 */
  List<_MediaDetailsJob> _activeJobs = const <_MediaDetailsJob>[];
  var _activeReads = 0;
  var _scheduledThisRun = 0;
  var _completedThisRun = 0;
  var _failedThisRun = 0;
  /** 只累计实际运行时间，用户暂停期间不进入速度与 ETA 估算。 */
  final Stopwatch _activeElapsed = Stopwatch();
  Duration _lastRateElapsed = Duration.zero;
  var _lastRateProcessed = 0;
  double? _smoothedItemsPerSecond;
  var _paused = false;
  int _generation;
  var _disposed = false;

  int get queuedReads => _queuedPaths.length;
  int get activeReads => _activeReads;
  int get completedThisRun => _completedThisRun;
  int get failedThisRun => _failedThisRun;

  /** 当前后台媒体解析是否暂停。 */
  bool get isPaused => _paused;

  /** 当前服务是否已经退出播放器生命周期。 */
  bool get isDisposed => _disposed;

  /**
   * 仅读取内存或视频模型中已经持久化的详情，不启动 FFprobe 或 media_kit。
   */
  MediaDetails? cachedDetailsFor(VideoItem item) {
    return _cache[item.path] ?? item.mediaDetails;
  }

  /**
   * 返回媒体详情；[refreshIncomplete] 供播放前安全预检或可见卡片补齐总时长，
   * [priority] 表示请求来自当前可视区域，可以越过尚未开始的后台任务。
   *
   * 普通列表和播放器队列保持缓存优先，不能因缺少单个字段自动启动探测；显式刷新会
   * 补齐编码、分辨率或总时长，防止旧版半成品缓存永久缺少卡片时长或绕过硬解矩阵。
   */
  Future<MediaDetails> detailsFor(
    VideoItem item, {
    bool refreshIncomplete = false,
    bool priority = false,
  }) {
    final cached = cachedDetailsFor(item);
    final cachedIsComplete = cached?.videoCodec != null &&
        cached?.width != null &&
        cached?.height != null &&
        (item.playbackDuration > Duration.zero ||
            (cached?.duration != null && cached!.duration! > Duration.zero));
    if (cached != null && (!refreshIncomplete || cachedIsComplete)) {
      _cache[item.path] = cached;
      return Future.value(cached);
    }
    if (_disposed) {
      return Future.value(const MediaDetails());
    }

    final existing = _inFlight[item.path];
    if (existing != null) {
      if (priority) {
        _promoteQueuedJob(item.path);
      }
      return existing;
    }

    final job = _enqueue(item, cached: cached, priority: priority);
    _emitProgress();
    _drainQueue();
    return job.completer.future;
  }

  /**
   * 一次性登记扫描新增项，再启动有限批次后台探测。
   *
   * 与逐条调用 [detailsFor] 相比，该入口只报告一次初始总量，并让第一个原生调用直接
   * 获得完整小批次，避免数千次启动调度和平台通道往返。
   */
  void prefetchAll(Iterable<VideoItem> items) {
    if (_disposed) {
      return;
    }
    for (final item in items) {
      final cached = cachedDetailsFor(item);
      // 旧版详情缓存没有总时长。已有可靠总时长时仍复用缓存；只有详情存在但
      // 时长缺失的旧记录才进入一次受限后台补齐，不能在卡片 build 中探测文件。
      if ((cached != null && item.playbackDuration > Duration.zero) ||
          _inFlight.containsKey(item.path)) {
        continue;
      }
      _enqueue(item, cached: cached, priority: false);
    }
    _emitProgress();
    _drainQueue();
  }

  /**
   * 暂停启动后续媒体详情批次。
   *
   * 已进入原生边界的最多 8 条任务允许自然完成，避免取消后重复读取同一文件；完成后
   * 停止计时并保持队列，筛选、滚动和播放不受影响。
   */
  void pause() {
    if (_disposed || _paused) {
      return;
    }
    _paused = true;
    if (_activeJobs.isEmpty) {
      _activeElapsed.stop();
    }
    _emitProgress();
  }

  /** 继续执行暂停保留的后台任务，并从暂停点恢复有效运行时间统计。 */
  void resume() {
    if (_disposed || !_paused) {
      return;
    }
    _paused = false;
    if (_queuedPaths.isNotEmpty && !_activeElapsed.isRunning) {
      _activeElapsed.start();
      // 暂停后的首个批次从新基线计算瞬时速度，避免把暂停时间混入 ETA。
      _lastRateElapsed = _activeElapsed.elapsed;
      _lastRateProcessed = _completedThisRun + _failedThisRun;
    }
    _emitProgress();
    _drainQueue();
  }

  /** 创建共享任务并加入对应优先级队列；调用方负责统一启动 drain。 */
  _MediaDetailsJob _enqueue(
    VideoItem item, {
    required MediaDetails? cached,
    required bool priority,
  }) {
    final completer = Completer<MediaDetails>();
    final job = _MediaDetailsJob(
      item: item,
      cached: cached,
      generation: _generation,
      completer: completer,
      priority: priority,
    );
    if (_scheduledThisRun == 0 && !_paused) {
      _activeElapsed.start();
    }
    _scheduledThisRun++;
    _inFlight[item.path] = completer.future;
    _queuedJobs[item.path] = job;
    _queuedPaths.add(item.path);
    if (priority) {
      // 最新进入视口的项目放到优先队首，快速滚动停稳后不等待旧离屏任务。
      _priorityJobs.addFirst(job);
    } else {
      _backgroundJobs.addLast(job);
    }
    return job;
  }

  /** 把尚未执行的后台任务提升到可视队首，不重复创建原生探测。 */
  void _promoteQueuedJob(String path) {
    final job = _queuedJobs[path];
    if (job == null || job.priority) {
      return;
    }
    _backgroundJobs.removeWhere((candidate) => identical(candidate, job));
    job.priority = true;
    _priorityJobs.addFirst(job);
  }

  /** 串行启动下一批任务；可见队列始终优先且单独成批，避免被后台条目拖延。 */
  void _drainQueue() {
    if (_disposed || _paused || _activeJobs.isNotEmpty) {
      return;
    }
    final jobs = <_MediaDetailsJob>[];
    if (_priorityJobs.isNotEmpty) {
      // 可见项独立执行，完成后可以立即刷新卡片，不等待后台批次其余条目。
      jobs.add(_priorityJobs.removeFirst());
    } else {
      while (
          _backgroundJobs.isNotEmpty && jobs.length < _maxBackgroundBatchSize) {
        jobs.add(_backgroundJobs.removeFirst());
      }
    }
    if (jobs.isEmpty) {
      return;
    }
    for (final job in jobs) {
      _queuedJobs.remove(job.item.path);
      _queuedPaths.remove(job.item.path);
    }
    _activeJobs = List<_MediaDetailsJob>.unmodifiable(jobs);
    _activeReads = 1;
    _emitProgress();
    unawaited(_runBatch(jobs));
  }

  /** 执行一个有限原生批次并完成各条共享 Future；结束后继续推进串行队列。 */
  Future<void> _runBatch(List<_MediaDetailsJob> jobs) async {
    var detailsByPath = <String, MediaDetails>{
      for (final job in jobs) job.item.path: job.cached ?? const MediaDetails(),
    };
    try {
      if (!_disposed && jobs.every((job) => job.generation == _generation)) {
        detailsByPath = await _readBatch(jobs, _generation);
        if (!_disposed && jobs.every((job) => job.generation == _generation)) {
          for (final job in jobs) {
            if (job.item.mediaDetailsError == null) {
              _completedThisRun++;
            } else {
              _failedThisRun++;
            }
          }
          _updateRateEstimate();
        }
      }
    } catch (_) {
      // Repository 批量回写失败不能卡死队列；本批条目标记失败并允许诊断页后续重试。
      for (final job in jobs) {
        job.item.mediaDetailsError ??= 'media details callback failed';
        _failedThisRun++;
      }
    } finally {
      _activeReads = 0;
      _activeJobs = const <_MediaDetailsJob>[];
      if (_paused) {
        _activeElapsed.stop();
      }
      for (final job in jobs) {
        _inFlight.remove(job.item.path);
        if (!job.completer.isCompleted) {
          job.completer.complete(
            detailsByPath[job.item.path] ?? const MediaDetails(),
          );
        }
      }
      _emitProgress();
      _drainQueue();
    }
  }

  /** 使用批次增量的指数平滑速度估算剩余时间，避免单个异常文件让文案剧烈跳动。 */
  void _updateRateEstimate() {
    final processed = _completedThisRun + _failedThisRun;
    final elapsed = _activeElapsed.elapsed;
    final deltaItems = processed - _lastRateProcessed;
    final deltaMicros =
        elapsed.inMicroseconds - _lastRateElapsed.inMicroseconds;
    if (deltaItems <= 0 || deltaMicros <= 0) {
      return;
    }
    final instantaneous = deltaItems / (deltaMicros / 1000000);
    final previous = _smoothedItemsPerSecond;
    _smoothedItemsPerSecond =
        previous == null ? instantaneous : previous * 0.7 + instantaneous * 0.3;
    _lastRateProcessed = processed;
    _lastRateElapsed = elapsed;
  }

  /**
   * 用一次平台调用读取有限批次，并把结果合并交给 Repository。
   *
   * 平台返回只按 videoId 映射；路径和 fingerprint 仍留在 Dart 侧验证与持久化。
   */
  Future<Map<String, MediaDetails>> _readBatch(
    List<_MediaDetailsJob> jobs,
    int generation,
  ) async {
    List<MediaProbeResult> results;
    try {
      results = await _probeBackend.probeBatch(
        generationId: generation,
        requests: [
          for (final job in jobs)
            MediaProbeRequest(
              videoId: job.item.videoId,
              path: job.item.path,
              knownSize: job.item.fileSize,
              knownModifiedAt: job.item.modifiedMs,
            ),
        ],
      );
    } catch (error) {
      // 平台批次异常时仍持久化每条失败状态，使诊断页可以看到并重试这批文件。
      final failedUpdates = <MediaDetailsUpdate>[];
      final failedDetails = <String, MediaDetails>{};
      for (final job in jobs) {
        job.item.mediaDetailsError = 'media probe: ${error.runtimeType}';
        const details = MediaDetails();
        _cache[job.item.path] = details;
        failedDetails[job.item.path] = details;
        failedUpdates.add(MediaDetailsUpdate(
          item: job.item,
          details: details,
          fingerprint: job.item.mediaFingerprint,
        ));
      }
      await _notifyUpdatedBatch(failedUpdates, generation);
      return failedDetails;
    }
    if (_disposed || generation != _generation) {
      return const <String, MediaDetails>{};
    }
    final resultsByVideoId = <String, MediaProbeResult>{
      for (final result in results) result.videoId: result,
    };
    final updates = <MediaDetailsUpdate>[];
    final detailsByPath = <String, MediaDetails>{};
    for (final job in jobs) {
      final item = job.item;
      final result = resultsByVideoId[item.videoId];
      if (result?.cancelled == true) {
        continue;
      }
      final details = result?.details ?? const MediaDetails();
      if (result?.details != null && result?.error == null) {
        item.mediaDetailsError = null;
      } else {
        item.mediaDetailsError = result?.error ?? 'media probe unavailable';
      }
      _cache[item.path] = details;
      detailsByPath[item.path] = details;
      updates.add(MediaDetailsUpdate(
        item: item,
        details: details,
        fingerprint: item.mediaFingerprint,
      ));
    }
    await _notifyUpdatedBatch(updates, generation);
    return detailsByPath;
  }

  /** 优先批量回写；兼容旧调用方时才逐条执行单项回调。 */
  Future<void> _notifyUpdatedBatch(
    List<MediaDetailsUpdate> updates,
    int generation,
  ) async {
    if (_disposed || generation != _generation || updates.isEmpty) {
      return;
    }
    if (onBatchUpdated != null) {
      await onBatchUpdated!(List<MediaDetailsUpdate>.unmodifiable(updates));
      return;
    }
    for (final update in updates) {
      if (_disposed || generation != _generation) {
        return;
      }
      await onUpdated?.call(
        update.item,
        update.details,
        update.fingerprint,
      );
    }
  }

  /** 只在队列边界报告快照，避免每个文件入队都触发页面 rebuild。 */
  void _emitProgress() {
    if (_disposed || onProgress == null || _scheduledThisRun == 0) {
      return;
    }
    final processed = _completedThisRun + _failedThisRun;
    final remaining = _scheduledThisRun - processed;
    final speed = _smoothedItemsPerSecond;
    onProgress!(MediaDetailsProgress(
      total: _scheduledThisRun,
      completed: _completedThisRun,
      failed: _failedThisRun,
      queued: _queuedPaths.length,
      active: _activeJobs.length,
      itemsPerSecond: speed,
      estimatedRemaining: speed == null || speed <= 0 || remaining <= 0
          ? null
          : Duration(seconds: (remaining / speed).ceil()),
      isPaused: _paused,
    ));
  }

  /**
   * 立即丢弃尚未开始的读取和所有后续回调。
   *
   * 已经交给外部 FFprobe 的单个进程不能由当前兼容接口强杀，但完成后不会再写回；
   * 队列中其余任务会通过代际检查直接短路。
   */
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _activeElapsed.stop();
    // 纯 Dart/widget test 没有 Windows runner 通道；取消仍应 best-effort，不能在 dispose 后抛出异步异常。
    unawaited(
      _probeBackend.cancelGeneration(_generation).then<void>(
            (_) {},
            onError: (_) {},
          ),
    );
    _generation++;
    for (final job in <_MediaDetailsJob>[
      ..._priorityJobs,
      ..._backgroundJobs,
    ]) {
      if (!job.completer.isCompleted) {
        job.completer.complete(job.cached ?? const MediaDetails());
      }
    }
    _priorityJobs.clear();
    _backgroundJobs.clear();
    _queuedJobs.clear();
    _queuedPaths.clear();
    // 活动任务保留到原生取消完成；其 finally 会完成 Future 并清理映射。
    final activePaths = _activeJobs.map((job) => job.item.path).toSet();
    _inFlight.removeWhere((path, _) => !activePaths.contains(path));
    _cache.clear();
  }
}
