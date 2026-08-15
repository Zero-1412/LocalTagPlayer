import 'package:flutter/material.dart';

import '../../models/media_details.dart';
import '../../models/video_item.dart';
import '../../services/library/library_application_facade.dart';
import '../../services/library/video_similarity_service.dart';
import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 重复下载候选页。
 *
 * 页面只读取当前 facade 的视频快照并展示候选，不自动删除、移动或修改任何条目；用户
 * 可逐条定位文件后自行确认。重复判断复用扫描阶段已经持久化的轻量 mediaFingerprint。
 */
class VideoSimilarityPage extends StatefulWidget {
  const VideoSimilarityPage({
    super.key,
    required this.store,
    required this.onRevealLocation,
  });

  /** 只读读取视频索引；页面不穿透 facade 访问 SQLite。 */
  final LibraryApplicationFacade store;

  /** 复用媒体库已有的平台文件定位边界。 */
  final Future<void> Function(VideoItem item) onRevealLocation;

  @override
  State<VideoSimilarityPage> createState() => _VideoSimilarityPageState();
}

class _VideoSimilarityPageState extends State<VideoSimilarityPage> {
  late VideoSimilarityReport _report;
  final Set<String> _revealingVideoIds = <String>{};

  @override
  void initState() {
    super.initState();
    _report = _buildReport();
  }

  VideoSimilarityReport _buildReport() {
    return VideoSimilarityReport.fromVideos(widget.store.videos.values);
  }

  void _refresh() {
    setState(() => _report = _buildReport());
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
              onPressed: _refresh,
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
                  _SimilarityOverview(report: _report),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _report.hasMatches
                        ? ListView.separated(
                            key: const ValueKey('videoSimilarity.groups'),
                            itemCount: _report.groups.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final group = _report.groups[index];
                              return _SimilarityGroupCard(
                                index: index,
                                group: group,
                                revealingVideoIds: _revealingVideoIds,
                                onReveal: _reveal,
                              );
                            },
                          )
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
  const _SimilarityOverview({required this.report});

  final VideoSimilarityReport report;

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
            '使用扫描阶段已有的轻量内容指纹（文件大小 + 首尾采样）分组。这里只提供候选和文件定位，不会自动删除；请人工确认后再处理。',
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
            ],
          ),
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
    required this.index,
    required this.group,
    required this.revealingVideoIds,
    required this.onReveal,
  });

  final int index;
  final VideoSimilarityGroup group;
  final Set<String> revealingVideoIds;
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
                    '重复候选组 · ${group.videos.length} 个视频',
                    style: const TextStyle(
                      color: libraryText,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '建议保留 1 个',
                  style: const TextStyle(
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
              item: group.videos[i],
              ordinal: i + 1,
              revealing: revealingVideoIds.contains(group.videos[i].videoId),
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
    required this.item,
    required this.ordinal,
    required this.revealing,
    required this.onReveal,
  });

  final VideoItem item;
  final int ordinal;
  final bool revealing;
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
