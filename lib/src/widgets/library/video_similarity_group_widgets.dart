import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/media_details.dart';
import '../../models/video_item.dart';
import '../../services/library/video_similarity_service.dart';
import '../../services/media/thumbnail_service.dart';
import '../app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 相似视频候选组卡片，只接收稳定快照和页面回调，不拥有队列或删除命令。 */
class VideoSimilarityGroupCard extends StatelessWidget {
  const VideoSimilarityGroupCard({
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
            VideoSimilarityVideoRow(
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

/** 候选视频行只派发播放、删除和定位意图，视觉复核期间仍保留已有行的按钮。 */
class VideoSimilarityVideoRow extends StatelessWidget {
  const VideoSimilarityVideoRow({
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
          VideoSimilarityThumbnail(
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
class VideoSimilarityThumbnail extends StatefulWidget {
  const VideoSimilarityThumbnail({
    super.key,
    required this.item,
    required this.thumbnailService,
  });

  final VideoItem item;
  final ThumbnailService thumbnailService;

  @override
  State<VideoSimilarityThumbnail> createState() =>
      _VideoSimilarityThumbnailState();
}

class _VideoSimilarityThumbnailState extends State<VideoSimilarityThumbnail> {
  late Future<File?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.thumbnailService.ensureThumbnailFor(widget.item);
  }

  @override
  void didUpdateWidget(covariant VideoSimilarityThumbnail oldWidget) {
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
