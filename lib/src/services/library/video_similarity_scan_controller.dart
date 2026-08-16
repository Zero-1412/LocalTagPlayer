import 'dart:async';

import 'package:flutter/foundation.dart';

import 'library_application_facade.dart';
import '../media/thumbnail_service.dart';
import 'video_content_similarity_service.dart';
import 'video_similarity_service.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库 Route 级相似视频扫描 owner。
 *
 * 扫描不是相似视频页面的短暂生命周期任务：页面退出时只撤销前台并发，不能取消
 * 已经启动的扫描，否则下一次进入会重复遍历全库。该 controller 与媒体库 Route
 * 同寿命，保存进行中 Future、进度和最近一次结果；只有显式刷新或数据删除才会
 * 让当前结果失效。
 */
class VideoSimilarityScanController extends ChangeNotifier {
  VideoSimilarityScanController({
    required LibraryApplicationFacade store,
    required ThumbnailService thumbnailService,
  })  : _store = store,
        _thumbnailService = thumbnailService;

  final LibraryApplicationFacade _store;
  final ThumbnailService _thumbnailService;

  Future<void>? _activeTask;
  VideoVisualScanResult? _result;
  VideoVisualScanProgress? _progress;
  String? _error;
  var _isScanning = false;
  var _hasRun = false;
  var _pageForeground = false;
  var _playbackActive = false;
  var _generation = 0;

  bool get isScanning => _isScanning;
  bool get hasRun => _hasRun;
  VideoVisualScanResult? get result => _result;
  VideoVisualScanProgress? get progress => _progress;
  String? get error => _error;

  /** 相似视频页在前台时提高视觉取帧并发，离开后保留任务但降为后台速率。 */
  void setPageForeground(bool foreground) {
    if (_pageForeground == foreground) {
      return;
    }
    _pageForeground = foreground;
    _syncThumbnailPriority();
    notifyListeners();
  }

  /** 播放器打开时让相似扫描进入后台速率；播放器关闭后恢复当前页面优先级。 */
  void setPlaybackActive(bool active) {
    if (_playbackActive == active) {
      return;
    }
    _playbackActive = active;
    _syncThumbnailPriority();
    notifyListeners();
  }

  /** 首次进入自动执行；若已有任务或结果，后续进入只复用共享状态。 */
  Future<void> startIfNeeded() {
    if (_activeTask != null) {
      return _activeTask!;
    }
    if (_hasRun) {
      return Future<void>.value();
    }
    return _start();
  }

  /** 只有用户明确点击“重新计算”时才重跑视觉复核。 */
  Future<void> refresh() async {
    // 删除刚使旧代次失效时，活动 FFmpeg 仍可能自然收尾；显式刷新排在它之后，
    // 避免新旧两轮同时占用取帧队列，也避免一次点击只等待已取消的旧 Future。
    final active = _activeTask;
    if (active != null) {
      await active;
    }
    if (_activeTask != null) {
      await _activeTask!;
    }
    await _start();
  }

  /** 数据删除会使旧候选失效，但不自动启动下一轮全库扫描。 */
  void invalidateForDataChange() {
    _generation++;
    _thumbnailService.cancelSimilarityScan();
    _result = null;
    _progress = null;
    _error = null;
    _isScanning = false;
    // 让删除后的重新进入复用“待手动刷新”状态，而不是再次自动遍历大库。
    _hasRun = true;
    notifyListeners();
  }

  void _syncThumbnailPriority() {
    _thumbnailService.setSimilarityScanForeground(
      _pageForeground && !_playbackActive,
    );
  }

  Future<void> _start() {
    final generation = ++_generation;
    _hasRun = true;
    _isScanning = true;
    _result = null;
    _progress = null;
    _error = null;
    notifyListeners();

    // 先发布“正在扫描”状态并登记共享 Future，再把候选基础报告放到微任务，避免
    // 首次进入的 post-frame 回调同步遍历万级视频而阻塞首帧绘制。
    final task = Future<void>.microtask(() => _scan(generation));
    _activeTask = task;
    return task.whenComplete(() {
      if (identical(_activeTask, task)) {
        _activeTask = null;
      }
    });
  }

  Future<void> _scan(int generation) async {
    final exactVideoIds = VideoSimilarityReport.fromVideos(
      _store.videos.values,
    )
        .groups
        .expand((group) => group.videos)
        .map((item) => item.videoId)
        .toSet();
    try {
      final result = await VideoContentSimilarityService(
        _thumbnailService,
        visualSignatureCache: _store,
      ).findNearDuplicateGroups(
        _store.videos.values,
        excludedVideoIds: exactVideoIds,
        isCancelled: () => generation != _generation,
        shouldYield: () => _playbackActive,
        onProgress: (progress) {
          if (generation != _generation) {
            return;
          }
          _progress = progress;
          notifyListeners();
        },
      );
      if (generation != _generation || result.cancelled) {
        return;
      }
      _result = result;
      _isScanning = false;
      _error = null;
      _progress = _finalProgress(result);
      notifyListeners();
    } catch (error) {
      if (generation != _generation) {
        return;
      }
      _isScanning = false;
      _error = '视觉复核失败：$error';
      notifyListeners();
    }
  }

  VideoVisualScanProgress? _finalProgress(VideoVisualScanResult result) {
    final progress = _progress;
    if (progress == null) {
      return null;
    }
    return VideoVisualScanProgress(
      phase: VideoVisualScanPhase.comparingCandidates,
      processed: result.candidatePairCount,
      total: result.candidatePairCount,
      elapsed: progress.elapsed,
      itemsPerSecond: progress.itemsPerSecond,
    );
  }

  @override
  void dispose() {
    _generation++;
    _thumbnailService.cancelSimilarityScan();
    super.dispose();
  }
}
