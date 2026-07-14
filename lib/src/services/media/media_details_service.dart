import 'dart:async';
import 'dart:collection';

import '../../models/media_details.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../platform/platform_interfaces.dart';

// ignore_for_file: slash_for_doc_comments

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
    required MediaProbeBackend probeBackend,
  })  : _probeBackend = probeBackend,
        _generation = _nextGeneration++;

  /** 进程内递增代号，避免多个播放器页面取消同一个原生 generation。 */
  static int _nextGeneration = 1;

  final Future<void> Function(
      VideoItem item, MediaDetails details, String? fingerprint)? onUpdated;
  /** 批量媒体探测平台边界；SQLite 写回仍由 [onUpdated] 所在 Repository 完成。 */
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

  /** 当前唯一运行的原生探测任务。 */
  _MediaDetailsJob? _activeJob;
  var _activeReads = 0;
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

    final completer = Completer<MediaDetails>();
    final job = _MediaDetailsJob(
      item: item,
      cached: cached,
      generation: _generation,
      completer: completer,
      priority: priority,
    );
    _inFlight[item.path] = completer.future;
    _queuedJobs[item.path] = job;
    _queuedPaths.add(item.path);
    if (priority) {
      // 最新进入视口的项目放到优先队首，快速滚动停稳后不等待旧离屏任务。
      _priorityJobs.addFirst(job);
    } else {
      _backgroundJobs.addLast(job);
    }
    _drainQueue();
    return completer.future;
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

  /** 串行启动下一条任务；可视队列始终优先于扫描后台队列。 */
  void _drainQueue() {
    if (_disposed || _activeJob != null) {
      return;
    }
    final job = _priorityJobs.isNotEmpty
        ? _priorityJobs.removeFirst()
        : _backgroundJobs.isNotEmpty
            ? _backgroundJobs.removeFirst()
            : null;
    if (job == null) {
      return;
    }
    _queuedJobs.remove(job.item.path);
    _queuedPaths.remove(job.item.path);
    _activeJob = job;
    _activeReads++;
    unawaited(_runJob(job));
  }

  /** 执行单条原生探测并完成共享 Future，结束后继续推进串行队列。 */
  Future<void> _runJob(_MediaDetailsJob job) async {
    var details = job.cached ?? const MediaDetails();
    try {
      if (!_disposed && job.generation == _generation) {
        details = await _read(job.item, job.generation);
        if (!_disposed && job.generation == _generation) {
          if (job.item.mediaDetailsError == null) {
            _completedThisRun++;
          } else {
            _failedThisRun++;
          }
        }
      }
    } catch (_) {
      // Repository 回调失败不能卡死整个串行队列；错误状态由调用方后续重试恢复。
      job.item.mediaDetailsError ??= 'media details callback failed';
      _failedThisRun++;
    } finally {
      _activeReads--;
      _activeJob = null;
      _inFlight.remove(job.item.path);
      if (!job.completer.isCompleted) {
        job.completer.complete(details);
      }
      _drainQueue();
    }
  }

  /**
   * 读取单条媒体详情；[generation] 用于阻止旧播放器任务回写新页面状态。
   */
  Future<MediaDetails> _read(VideoItem item, int generation) async {
    final path = item.path;
    // 扫描阶段已经保存 fingerprint、大小和修改时间，播放器详情不得再次 stat 或读取首尾样本。
    final fingerprint = item.mediaFingerprint;
    try {
      final results = await _probeBackend.probeBatch(
        generationId: generation,
        requests: <MediaProbeRequest>[
          MediaProbeRequest(
            videoId: item.videoId,
            path: path,
            knownSize: item.fileSize,
            knownModifiedAt: item.modifiedMs,
          ),
        ],
      );
      final result = results.firstOrNull;
      if (result?.cancelled == true || _disposed || generation != _generation) {
        return const MediaDetails();
      }
      final details = result?.details;
      if (details != null && result?.error == null) {
        item.mediaDetailsError = null;
        _cache[path] = details;
        await _notifyUpdated(item, details, fingerprint, generation);
        return details;
      }
      item.mediaDetailsError = result?.error ?? 'media probe unavailable';
    } catch (error) {
      item.mediaDetailsError = 'media probe: ${error.runtimeType}';
    }
    const details = MediaDetails();
    _cache[path] = details;
    await _notifyUpdated(item, details, fingerprint, generation);
    return details;
  }

  /** 仅允许当前播放器代际把详情写回媒体库。 */
  Future<void> _notifyUpdated(
    VideoItem item,
    MediaDetails details,
    String? fingerprint,
    int generation,
  ) async {
    if (_disposed || generation != _generation) {
      return;
    }
    await onUpdated?.call(item, details, fingerprint);
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
    _inFlight.removeWhere((path, _) => path != _activeJob?.item.path);
    _cache.clear();
  }
}
