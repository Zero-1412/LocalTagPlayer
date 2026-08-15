import 'package:flutter/material.dart';

import '../../services/library/video_similarity_service.dart';
import '../app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 相似视频页摘要只展示报告快照和视觉复核状态，不启动扫描或修改候选。 */
class VideoSimilarityOverview extends StatelessWidget {
  const VideoSimilarityOverview({
    super.key,
    required this.report,
    required this.visualScanning,
    required this.visualError,
    required this.visualScanStale,
    required this.visualProgress,
    required this.visualProgressTotal,
  });

  final VideoSimilarityReport report;
  final bool visualScanning;
  final String? visualError;
  final bool visualScanStale;
  final int visualProgress;
  final int visualProgressTotal;

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
              _VideoSimilarityOverviewPill(
                label: '重复文件',
                value: '${report.duplicateVideoCount}',
              ),
              _VideoSimilarityOverviewPill(
                label: '可复核多余项',
                value: '${report.duplicateExtraCount}',
              ),
              _VideoSimilarityOverviewPill(
                label: '已建立指纹',
                value: '${report.indexedVideoCount}',
              ),
              if (report.unindexedVideoCount > 0)
                _VideoSimilarityOverviewPill(
                  label: '待扫描',
                  value: '${report.unindexedVideoCount}',
                  warning: true,
                ),
              if (report.missingVideoCount > 0)
                _VideoSimilarityOverviewPill(
                  label: '缺失记录已跳过',
                  value: '${report.missingVideoCount}',
                ),
              if (visualScanning)
                _VideoSimilarityOverviewPill(
                  label: '视觉复核',
                  value: visualProgressTotal > 0
                      ? '$visualProgress/$visualProgressTotal'
                      : '准备中',
                  warning: true,
                ),
              if (!visualScanning && visualScanStale)
                const _VideoSimilarityOverviewPill(
                  label: '视觉结果',
                  value: '待重新计算',
                  warning: true,
                ),
              if (!visualScanning && report.visualCandidatePairCount > 0)
                _VideoSimilarityOverviewPill(
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

class _VideoSimilarityOverviewPill extends StatelessWidget {
  const _VideoSimilarityOverviewPill({
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

/** 空状态保留相似候选页的可达反馈，不把“暂无结果”与“仍在扫描”混淆。 */
class VideoSimilarityEmptyState extends StatelessWidget {
  const VideoSimilarityEmptyState({super.key, this.stale = false});

  final bool stale;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 38, color: Color(0xff69d49a)),
            SizedBox(height: 12),
            Text(
              '当前没有重复候选',
              style: const TextStyle(
                color: libraryText,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              stale
                  ? '候选已局部更新；点击右上角“重新计算”继续搜索未复核的重复视频。'
                  : '如果仍有新视频未完成扫描，请先回到媒体库执行“重新扫描”，再点击右上角重新计算。',
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

/** 扫描状态在已有候选继续显示时只作为摘要提示，不替换候选列表。 */
class VideoSimilarityScanningState extends StatelessWidget {
  const VideoSimilarityScanningState({
    super.key,
    this.progress = 0,
    this.total = 0,
  });

  final int progress;
  final int total;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(height: 14),
            Text(
              total > 0 ? '正在按时序画面复核近重复视频（$progress/$total）' : '正在按时序画面复核近重复视频',
              style: TextStyle(
                color: libraryText,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '会优先比较多通道候选，并对未缓存首帧保留有界深度回退；不会为全库视频逐个启动播放器兜底。',
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
