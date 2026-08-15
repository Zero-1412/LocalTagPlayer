import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/media_details.dart';
import '../../models/video_item.dart';
import '../../services/library/library_application_facade.dart';
import '../../services/library/video_content_similarity_service.dart';
import '../../services/library/video_similarity_service.dart';
import '../../services/media/thumbnail_service.dart';
import '../../widgets/app_theme_tokens.dart';

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
  String? _visualError;

  @override
  void initState() {
    super.initState();
    _report = _buildReport();
    _scheduleVisualScan();
  }

  VideoSimilarityReport _buildReport() {
    return VideoSimilarityReport.fromVideos(widget.store.videos.values);
  }

  void _refresh() {
    setState(() {
      _report = _buildReport();
      _visualError = null;
    });
    _scheduleVisualScan();
  }

  /** 先让相似视频页完成首帧挂载，再启动可能触发候选构建和取帧的后台扫描。 */
  void _scheduleVisualScan() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_runVisualScan());
      }
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
      setState(() => _visualScanning = true);
    }
    final exactVideoIds = _report.groups
        .expand((group) => group.videos)
        .map((item) => item.videoId)
        .toSet();
    try {
      final result = await VideoContentSimilarityService(
        widget.thumbnailService,
      ).findNearDuplicateGroups(
        widget.store.videos.values,
        excludedVideoIds: exactVideoIds,
      );
      if (!mounted || generation != _visualGeneration) {
        return;
      }
      setState(() {
        _report = _report.withVisualGroups(
          groups: _withoutDeletedVideos(result.groups),
          candidatePairCount: result.candidatePairCount,
          comparedPairCount: result.comparedPairCount,
        );
        _visualScanning = false;
      });
    } catch (error) {
      if (!mounted || generation != _visualGeneration) {
        return;
      }
      setState(() {
        _visualScanning = false;
        _visualError = '视觉复核失败：$error';
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
    setState(() => _actingVideoIds.add(item.videoId));
    try {
      final deleted = await widget.onDelete(item, mergeInto);
      if (!deleted || !mounted) {
        return;
      }
      _deletedVideoIds.add(item.videoId);
      // 删除已由父页面完成数据库、文件和缩略图清理；这里重建只读候选快照，
      // 先局部移除当前行，再按最新库内容重新运行一次有界视觉复核。正在运行的旧扫描
      // 即使晚返回，也会按 stable videoId 过滤，不能把已删除行重新带回页面。
      setState(() {
        _report = _report.withoutVideo(item);
        _visualError = null;
      });
      _scheduleVisualScan();
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
                  _SimilarityOverview(
                    report: _report,
                    visualScanning: _visualScanning,
                    visualError: _visualError,
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
                              return _SimilarityGroupCard(
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
                            ? const _SimilarityScanningState()
                            : const _SimilarityEmptyState(),
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

class _SimilarityOverview extends StatelessWidget {
  const _SimilarityOverview({
    required this.report,
    required this.visualScanning,
    required this.visualError,
  });

  final VideoSimilarityReport report;
  final bool visualScanning;
  final String? visualError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: librarySurface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: libraryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_motion_outlined,
                  color: libraryAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  report.hasMatches ? '发现重复下载候选' : '暂未发现重复候选',
                  style: const TextStyle(
                    color: libraryText,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${report.duplicateGroupCount} 组',
                style: const TextStyle(
                  color: libraryAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '先用文件级指纹快速筛选，再按相近时长/画面规格/大小比较缓存首帧，并对通过者抽取多个时间点的时序感知 dHash，识别重新编码后的近重复。删除时会把收藏和自定义标签合并到保留项，再将源视频移入回收站；不会自动删除，请人工确认后再处理。',
            style: const TextStyle(
              color: libraryTextMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OverviewPill(
                label: '重复文件',
                value: '${report.duplicateVideoCount}',
              ),
              _OverviewPill(
                label: '可复核多余项',
                value: '${report.duplicateExtraCount}',
              ),
              _OverviewPill(
                label: '已建立指纹',
                value: '${report.indexedVideoCount}',
              ),
              if (report.unindexedVideoCount > 0)
                _OverviewPill(
                  label: '待扫描',
                  value: '${report.unindexedVideoCount}',
                  warning: true,
                ),
              if (report.missingVideoCount > 0)
                _OverviewPill(
                  label: '缺失记录已跳过',
                  value: '${report.missingVideoCount}',
                ),
              if (visualScanning)
                const _OverviewPill(
                  label: '视觉复核',
                  value: '进行中',
                  warning: true,
                ),
              if (!visualScanning && report.visualCandidatePairCount > 0)
                _OverviewPill(
                  label: '视觉候选/已比较',
                  value:
                      '${report.visualCandidatePairCount}/${report.visualComparedPairCount}',
                ),
            ],
          ),
          if (visualError != null) ...[
            const SizedBox(height: 10),
            Text(
              visualError!,
              style: const TextStyle(
                color: Color(0xffffb06b),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OverviewPill extends StatelessWidget {
  const _OverviewPill({
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: warning ? const Color(0xff5d4828) : librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: warning ? const Color(0xffa77b3c) : libraryBorder,
        ),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: const TextStyle(
                color: libraryTextMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: libraryText,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimilarityGroupCard extends StatelessWidget {
  const _SimilarityGroupCard({
    super.key,
    required this.index,
    required this.group,
    required this.thumbnailService,
    required this.actingVideoIds,
    required this.revealingVideoIds,
    required this.onPlay,
    required this.onDelete,
    required this.onReveal,
  });

  final int index;
  final VideoSimilarityGroup group;
  final ThumbnailService thumbnailService;
  final Set<String> actingVideoIds;
  final Set<String> revealingVideoIds;
  final Future<void> Function(VideoItem item, List<VideoItem> playlist) onPlay;
  final Future<void> Function(VideoItem item, List<VideoItem> playlist)
      onDelete;
  final Future<void> Function(VideoItem item) onReveal;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: librarySurface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: libraryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: appAccentViolet.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: libraryAccent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${group.kind == VideoSimilarityKind.exactFingerprint ? '确定重复' : '内容近重复候选'} · ${group.videos.length} 个视频',
                    style: const TextStyle(
                      color: libraryText,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (group.visualScore != null)
                  Text(
                    '相似度 ${(1 - group.visualScore!).clamp(0, 1) * 100 ~/ 1}%',
                    style: const TextStyle(
                      color: libraryTextMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  const Text(
                    '建议保留 1 个',
                    style: TextStyle(
                      color: libraryTextMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: libraryBorder),
          for (var i = 0; i < group.videos.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: libraryBorder),
            _SimilarityVideoRow(
              key: ValueKey<String>(
                'videoSimilarity.item.${group.videos[i].videoId}',
              ),
              item: group.videos[i],
              ordinal: i + 1,
              thumbnailService: thumbnailService,
              playlist: group.videos,
              acting: actingVideoIds.contains(group.videos[i].videoId),
              revealing: revealingVideoIds.contains(group.videos[i].videoId),
              onPlay: onPlay,
              onDelete: onDelete,
              onReveal: onReveal,
            ),
          ],
        ],
      ),
    );
  }
}

class _SimilarityVideoRow extends StatelessWidget {
  const _SimilarityVideoRow({
    super.key,
    required this.item,
    required this.ordinal,
    required this.thumbnailService,
    required this.playlist,
    required this.acting,
    required this.revealing,
    required this.onPlay,
    required this.onDelete,
    required this.onReveal,
  });

  final VideoItem item;
  final int ordinal;
  final ThumbnailService thumbnailService;
  final List<VideoItem> playlist;
  final bool acting;
  final bool revealing;
  final Future<void> Function(VideoItem item, List<VideoItem> playlist) onPlay;
  final Future<void> Function(VideoItem item, List<VideoItem> playlist)
      onDelete;
  final Future<void> Function(VideoItem item) onReveal;

  @override
  Widget build(BuildContext context) {
    final details = item.mediaDetails;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$ordinal',
              style: const TextStyle(
                color: libraryTextMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _SimilarityThumbnail(
            item: item,
            thumbnailService: thumbnailService,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: libraryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: libraryTextMuted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _mediaSummary(item.fileSize, details),
                  style: const TextStyle(
                    color: libraryTextMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (acting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              key: ValueKey('videoSimilarity.play.${item.videoId}'),
              tooltip: '播放当前候选组',
              // 视觉复核只追加候选组，不改变当前已展示组；播放必须随时复用该组队列。
              // 删除仍在扫描期间锁定，避免复核结果与删除后的快照发生竞态。
              onPressed: () => onPlay(item, playlist),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
            IconButton(
              key: ValueKey('videoSimilarity.delete.${item.videoId}'),
              tooltip: '合并收藏和自定义标签后删除此候选视频',
              onPressed: () => onDelete(item, playlist),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
            IconButton(
              tooltip: '在文件管理器中定位',
              onPressed: revealing ? null : () => onReveal(item),
              icon: revealing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open_outlined),
            ),
          ],
        ],
      ),
    );
  }
}

/** 重复候选行只请求视口内首帧，命中全局缓存时不再重复读盘或启动 FFmpeg。 */
class _SimilarityThumbnail extends StatefulWidget {
  const _SimilarityThumbnail({
    required this.item,
    required this.thumbnailService,
  });

  final VideoItem item;
  final ThumbnailService thumbnailService;

  @override
  State<_SimilarityThumbnail> createState() => _SimilarityThumbnailState();
}

class _SimilarityThumbnailState extends State<_SimilarityThumbnail> {
  late Future<File?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.thumbnailService.ensureThumbnailFor(widget.item);
  }

  @override
  void didUpdateWidget(covariant _SimilarityThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.videoId != widget.item.videoId ||
        oldWidget.thumbnailService != widget.thumbnailService) {
      _future = widget.thumbnailService.ensureThumbnailFor(widget.item);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 118,
      height: 66,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: FutureBuilder<File?>(
          future: _future,
          initialData: widget.thumbnailService.cachedThumbnailFor(widget.item),
          builder: (context, snapshot) {
            final file = snapshot.data;
            if (file != null) {
              return Image.file(
                file,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                cacheWidth: 236,
              );
            }
            final loading = snapshot.connectionState == ConnectionState.waiting;
            return DecoratedBox(
              decoration: const BoxDecoration(color: librarySurfaceAlt),
              child: Center(
                child: Icon(
                  loading ? Icons.hourglass_top_rounded : Icons.movie_outlined,
                  color: libraryTextMuted,
                  size: 22,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SimilarityEmptyState extends StatelessWidget {
  const _SimilarityEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: librarySurface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: libraryBorder),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 38, color: Color(0xff69d49a)),
            SizedBox(height: 12),
            Text(
              '当前没有重复候选',
              style: TextStyle(
                color: libraryText,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '如果仍有新视频未完成扫描，请先回到媒体库执行“重新扫描”，再点击右上角重新计算。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: libraryTextMuted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimilarityScanningState extends StatelessWidget {
  const _SimilarityScanningState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: librarySurface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: libraryBorder),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(height: 14),
            Text(
              '正在按时序画面复核近重复视频',
              style: TextStyle(
                color: libraryText,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '会优先比较时长和画面规格接近的候选，并对未缓存首帧保留有界深度回退；缩略图生成沿用媒体库缓存队列。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: libraryTextMuted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _mediaSummary(int? fileSize, MediaDetails? details) {
  final parts = <String>[_fileSizeLabel(fileSize)];
  if (details?.duration != null) {
    parts.add(_durationLabel(details!.duration!));
  }
  if (details?.width != null && details?.height != null) {
    parts.add('${details!.width}x${details.height}');
  }
  return parts.join(' · ');
}

String _fileSizeLabel(int? bytes) {
  if (bytes == null || bytes < 0) {
    return '大小读取中';
  }
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String _durationLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
