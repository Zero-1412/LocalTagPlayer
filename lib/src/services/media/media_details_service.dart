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
  int _generation;
  var _disposed = false;

  int get queuedReads => _queuedPaths.length;
  int get activeReads => _activeReads;
  int get completedThisRun => _completedThisRun;
  int get failedThisRun => _failedThisRun;

  /** 当前服务是否已经退出播放器生命周期。 */
  bool get isDisposed => _disposed;

  /**
   * 仅读取内存或视频模型中已经持久化的详情，不启动 FFprobe 或 media_kit。
   */
  MediaDetails? cachedDetailsFor(VideoItem item) {
    return _cache[item.path] ?? item.mediaDetails;
  }

  /**
   * 返回媒体详情；[refreshIncomplete] 仅供用户点击后的播放前安全预检使用，
   * [priority] 表示请求来自当前可视区域，可以越过尚未开始的后台任务。
   *
   * 普通列表和播放器队列保持缓存优先，不能因缺少单个字段自动启动探测；播放前预检
   * 可刷新缺少编码或分辨率的旧记录，防止半成品缓存永久绕过硬解兼容矩阵。
   */
  Future<MediaDetails> detailsFor(
    VideoItem item, {
    bool refreshIncomplete = false,
    bool priority = false,
  }) {
    final cached = cachedDetailsFor(item);
    final cachedIsComplete = cached?.videoCodec != null &&
        cached?.width != null &&
        cached?.height != null;
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
      if (cachedDetailsFor(item) != null || _inFlight.containsKey(item.path)) {
        continue;
      }
      _enqueue(item, cached: null, priority: false);
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
    if (_disposed || _activeJobs.isNotEmpty) {
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
    onProgress!(MediaDetailsProgress(
      total: _scheduledThisRun,
      completed: _completedThisRun,
      failed: _failedThisRun,
      queued: _queuedPaths.length,
      active: _activeJobs.length,
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
