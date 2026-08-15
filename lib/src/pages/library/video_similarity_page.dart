import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/video_item.dart';
import '../../services/library/library_application_facade.dart';
import '../../services/library/video_content_similarity_service.dart';
import '../../services/library/video_similarity_service.dart';
import '../../services/media/thumbnail_service.dart';
import '../../widgets/app_theme_tokens.dart';
import '../../widgets/library/video_similarity_group_widgets.dart';
import '../../widgets/library/video_similarity_status_widgets.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 重复下载候选页。
 *
 * 页面读取当前 facade 的视频快照并展示候选；播放、定位和删除都委托给媒体库页面已有
 * 的边界，删除必须经过统一确认。重复判断先复用扫描阶段的轻量 mediaFingerprint，再按需
 * 经过共享缩略图/FFmpeg 边界做时序视觉复核。
 */
class VideoSimilarityPage extends StatefulWidget {
  const VideoSimilarityPage({
    super.key,
    required this.store,
    required this.thumbnailService,
    required this.onPlay,
    required this.onDelete,
    required this.onRevealLocation,
  });

  /** 只读读取视频索引；页面不穿透 facade 访问 SQLite。 */
  final LibraryApplicationFacade store;

  /** 复用全局缩略图队列；页面不自行启动 FFmpeg 进程。 */
  final ThumbnailService thumbnailService;

  /** 由媒体库页面创建当前候选组的独立播放队列，并在播放器 Route 返回时通知页面。 */
  final Future<void> Function(
    VideoItem item,
    List<VideoItem> playlist, {
    VoidCallback? onRouteReturned,
  }) onPlay;

  /** 先选择保留目标，再复用媒体库统一确认/合并/删除流程。 */
  final Future<bool> Function(VideoItem item, VideoItem mergeInto) onDelete;

  /** 复用媒体库已有的平台文件定位边界。 */
  final Future<void> Function(VideoItem item) onRevealLocation;

  @override
  State<VideoSimilarityPage> createState() => _VideoSimilarityPageState();
}

class _VideoSimilarityPageState extends State<VideoSimilarityPage> {
  late VideoSimilarityReport _report;
  final Set<String> _revealingVideoIds = <String>{};
  final Set<String> _actingVideoIds = <String>{};
  final Set<String> _deletedVideoIds = <String>{};
  var _visualScanning = false;
  var _visualGeneration = 0;
  var _visualScanStale = false;
  var _visualProgressPhase = VideoVisualScanPhase.buildingCandidates;
  var _visualProgress = 0;
  var _visualProgressTotal = 0;
  VideoVisualScanProgress? _visualTiming;
  var _visualPlaybackActive = false;
  String? _visualError;

  @override
  void initState() {
    super.initState();
    _report = _buildReport();
    widget.thumbnailService.setSimilarityScanForeground(true);
    _scheduleVisualScan();
  }

  @override
  void dispose() {
    _visualPlaybackActive = false;
    widget.thumbnailService.cancelSimilarityScan();
    widget.thumbnailService.setSimilarityScanForeground(false);
    super.dispose();
  }

  VideoSimilarityReport _buildReport() {
    return VideoSimilarityReport.fromVideos(widget.store.videos.values);
  }

  void _refresh() {
    setState(() {
      _report = _buildReport();
      _visualError = null;
      _visualScanStale = false;
    });
    _scheduleVisualScan();
  }

  /** 先让相似视频页完成首帧挂载，再启动可能触发候选构建和取帧的后台扫描。 */
  void _scheduleVisualScan() {
    final requestedGeneration = _visualGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && requestedGeneration == _visualGeneration) {
        unawaited(_runVisualScan());
      }
    });
  }

  /** 使删除/刷新触发前一轮复核尽快退出，避免旧任务继续占用 FFmpeg 队列。 */
  void _cancelVisualScan() {
    _visualGeneration++;
    widget.thumbnailService.cancelSimilarityScan();
    if (!_visualScanning || !mounted) {
      return;
    }
    setState(() {
      _visualScanning = false;
      _visualProgressPhase = VideoVisualScanPhase.buildingCandidates;
      _visualProgress = 0;
      _visualProgressTotal = 0;
      _visualTiming = null;
    });
  }

  /** 过滤晚返回的视觉扫描快照，避免删除完成后旧结果把 stable videoId 重新带回页面。 */
  List<VideoSimilarityGroup> _withoutDeletedVideos(
    Iterable<VideoSimilarityGroup> groups,
  ) {
    final visible = <VideoSimilarityGroup>[];
    for (final group in groups) {
      final videos = group.videos
          .where((item) => !_deletedVideoIds.contains(item.videoId))
          .toList(growable: false);
      if (videos.length < 2) {
        continue;
      }
      visible.add(
        VideoSimilarityGroup(
          fingerprint: group.fingerprint,
          kind: group.kind,
          visualScore: group.visualScore,
          visualConfidence: group.visualConfidence,
          videos: List<VideoItem>.unmodifiable(videos),
        ),
      );
    }
    return List<VideoSimilarityGroup>.unmodifiable(visible);
  }

  /** 播放器返回时只对账当前候选快照中的失效 stable ID，不触发整页重建或重新扫描。 */
  void _reconcileAfterPlayerReturn({String? activeVideoId}) {
    final currentVideoIds =
        widget.store.videos.values.map((item) => item.videoId).toSet();
    final removedById = <String, VideoItem>{};
    for (final group in _report.allGroups) {
      for (final item in group.videos) {
        if (!currentVideoIds.contains(item.videoId)) {
          removedById[item.videoId] = item;
        }
      }
    }
    if (!mounted || (activeVideoId == null && removedById.isEmpty)) {
      return;
    }
    setState(() {
      if (activeVideoId != null) {
        _actingVideoIds.remove(activeVideoId);
      }
      if (removedById.isNotEmpty) {
        _deletedVideoIds.addAll(removedById.keys);
        for (final item in removedById.values) {
          _report = _report.withoutVideo(item);
        }
        _visualError = null;
      }
    });
  }

  Future<void> _runVisualScan() async {
    if (_visualScanning) {
      return;
    }
    final generation = ++_visualGeneration;
    if (mounted) {
      setState(() {
        _visualScanning = true;
        _visualProgressPhase = VideoVisualScanPhase.buildingCandidates;
        _visualProgress = 0;
        _visualProgressTotal = 0;
        _visualTiming = null;
      });
    }
    final exactVideoIds = _report.groups
        .expand((group) => group.videos)
        .map((item) => item.videoId)
        .toSet();
    try {
      final result = await VideoContentSimilarityService(
        widget.thumbnailService,
        visualSignatureCache: widget.store,
      ).findNearDuplicateGroups(
        widget.store.videos.values,
        excludedVideoIds: exactVideoIds,
        isCancelled: () => !mounted || generation != _visualGeneration,
        shouldYield: () => _visualPlaybackActive,
        onProgress: (progress) {
          if (!mounted || generation != _visualGeneration) {
            return;
          }
          final phaseChanged = progress.phase != _visualProgressPhase;
          final elapsedChanged =
              progress.elapsed.inSeconds != _visualTiming?.elapsed.inSeconds;
          if (phaseChanged ||
              progress.processed == progress.total ||
              elapsedChanged) {
            setState(() {
              _visualProgressPhase = progress.phase;
              _visualProgress = progress.processed;
              _visualProgressTotal = progress.total;
              _visualTiming = progress;
            });
          }
        },
      );
      if (!mounted || generation != _visualGeneration || result.cancelled) {
        return;
      }
      setState(() {
        _report = _report.withVisualGroups(
          groups: _withoutDeletedVideos(result.groups),
          candidatePairCount: result.candidatePairCount,
          comparedPairCount: result.comparedPairCount,
        );
        _visualScanning = false;
        _visualScanStale = false;
        _visualProgressPhase = VideoVisualScanPhase.comparingCandidates;
        _visualProgress = result.candidatePairCount;
        _visualProgressTotal = result.candidatePairCount;
      });
    } catch (error) {
      if (!mounted || generation != _visualGeneration) {
        return;
      }
      setState(() {
        _visualScanning = false;
        _visualError = '视觉复核失败：$error';
        _visualProgressPhase = VideoVisualScanPhase.buildingCandidates;
        _visualProgress = 0;
        _visualProgressTotal = 0;
      });
    }
  }

  Future<void> _reveal(VideoItem item) async {
    if (_revealingVideoIds.contains(item.videoId)) {
      return;
    }
    setState(() => _revealingVideoIds.add(item.videoId));
    try {
      await widget.onRevealLocation(item);
    } finally {
      if (mounted) {
        setState(() => _revealingVideoIds.remove(item.videoId));
      }
    }
  }

  Future<void> _play(VideoItem item, List<VideoItem> playlist) async {
    if (_actingVideoIds.contains(item.videoId)) {
      return;
    }
    setState(() => _actingVideoIds.add(item.videoId));
    _visualPlaybackActive = true;
    widget.thumbnailService.setSimilarityScanForeground(false);
    try {
      await widget.onPlay(
        item,
        List<VideoItem>.unmodifiable(playlist),
        onRouteReturned: () {
          if (mounted) {
            _reconcileAfterPlayerReturn(activeVideoId: item.videoId);
            // 播放器删除事务先完成，媒体库宿主的差量回调随后发布；下一帧再对账一次，
            // 覆盖宿主延后刷新 Store 内存索引的时序，但仍只移除受影响候选行。
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _reconcileAfterPlayerReturn();
              }
            });
          }
        },
      );
    } finally {
      _visualPlaybackActive = false;
      widget.thumbnailService.setSimilarityScanForeground(true);
      if (mounted) {
        setState(() => _actingVideoIds.remove(item.videoId));
      }
    }
  }

  Future<VideoItem?> _chooseMergeTarget(
    VideoItem item,
    List<VideoItem> playlist,
  ) async {
    final candidates = playlist
        .where((candidate) => candidate.videoId != item.videoId)
        .toList(growable: false);
    if (candidates.length == 1) {
      return candidates.single;
    }
    if (candidates.isEmpty || !mounted) {
      return null;
    }
    return showDialog<VideoItem>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('选择保留视频'),
        content: SizedBox(
          width: 520,
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('源视频的收藏和自定义标签会并入所选视频，目录标签不会复制。'),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: candidates.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final candidate = candidates[index];
                    return ListTile(
                      key: ValueKey(
                        'videoSimilarity.mergeTarget.${candidate.videoId}',
                      ),
                      title: Text(
                        candidate.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        candidate.path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.check_circle_outline_rounded),
                      onTap: () => Navigator.of(dialogContext).pop(candidate),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(VideoItem item, List<VideoItem> playlist) async {
    if (_actingVideoIds.contains(item.videoId)) {
      return;
    }
    final mergeInto = await _chooseMergeTarget(item, playlist);
    if (mergeInto == null || !mounted) {
      return;
    }
    // 删除会改变候选快照；先取消当前复核，成功后只做局部移除，不立即再次启动
    // 1 万级媒体库的全量视觉扫描，用户可通过“重新计算”明确发起下一轮。
    _cancelVisualScan();
    setState(() => _actingVideoIds.add(item.videoId));
    try {
      final deleted = await widget.onDelete(item, mergeInto);
      if (!deleted || !mounted) {
        return;
      }
      _deletedVideoIds.add(item.videoId);
      // 删除已由父页面完成数据库、文件和缩略图清理；这里仅局部移除当前行并标记
      // 视觉结果过期，避免删除一条记录就再次启动 1 万级媒体库的全量取帧。
      setState(() {
        _report = _report.withoutVideo(item);
        _visualError = null;
        _visualScanStale = true;
      });
    } finally {
      if (mounted) {
        setState(() => _actingVideoIds.remove(item.videoId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: maintenanceWorkspaceTheme(Theme.of(context)),
      child: Scaffold(
        key: const ValueKey('videoSimilarity.page'),
        backgroundColor: libraryBackground,
        appBar: AppBar(
          leading: IconButton(
            tooltip: '返回媒体库',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('相似视频'),
          actions: [
            IconButton(
              key: const ValueKey('videoSimilarity.refresh'),
              tooltip: '重新计算',
              onPressed: _visualScanning ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final pagePadding = constraints.maxWidth < 760 ? 16.0 : 28.0;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                pagePadding,
                20,
                pagePadding,
                pagePadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VideoSimilarityOverview(
                    report: _report,
                    visualScanning: _visualScanning,
                    visualError: _visualError,
                    visualScanStale: _visualScanStale,
                    visualProgressPhase: _visualProgressPhase,
                    visualProgress: _visualProgress,
                    visualProgressTotal: _visualProgressTotal,
                    visualTiming: _visualTiming,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _report.hasMatches
                        ? ListView.separated(
                            key: const ValueKey('videoSimilarity.groups'),
                            // Windows 桌面 Scrollbar 默认覆盖 viewport 内容；为卡片预留
                            // 独立右侧安全区，避免滚动条压住行内按钮和建议保留提示。
                            padding:
                                const EdgeInsets.only(right: 18, bottom: 12),
                            itemCount: _report.groups.length +
                                _report.visualGroups.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final group = index < _report.groups.length
                                  ? _report.groups[index]
                                  : _report.visualGroups[
                                      index - _report.groups.length];
                              final groupKey = ValueKey<String>(
                                'videoSimilarity.group.'
                                '${group.kind.name}.'
                                '${group.videos.map((item) => item.videoId).join('|')}',
                              );
                              return VideoSimilarityGroupCard(
                                key: groupKey,
                                index: index,
                                group: group,
                                thumbnailService: widget.thumbnailService,
                                actingVideoIds: _actingVideoIds,
                                revealingVideoIds: _revealingVideoIds,
                                onPlay: _play,
                                onDelete: _delete,
                                onReveal: _reveal,
                              );
                            },
                          )
                        : _visualScanning
                            ? VideoSimilarityScanningState(
                                phase: _visualProgressPhase,
                                progress: _visualProgress,
                                total: _visualProgressTotal,
                                timing: _visualTiming,
                              )
                            : VideoSimilarityEmptyState(
                                stale: _visualScanStale,
                              ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
