import 'package:flutter/material.dart';

import '../../services/relink/bulk_path_relink_service.dart';
import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 批量预览摘要角标。 */
class BulkRelinkSummaryBadge extends StatelessWidget {
  const BulkRelinkSummaryBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.capsule),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/** 生成只读预览期间的稳定加载状态，不使用大面积 shimmer。 */
class BulkRelinkLoadingState extends StatelessWidget {
  const BulkRelinkLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('正在校验路径与 fingerprint…'),
        ],
      ),
    );
  }
}

/** 预览尚未生成或搜索无结果时的解释性空状态。 */
class BulkRelinkEmptyPreview extends StatelessWidget {
  const BulkRelinkEmptyPreview({super.key, required this.hasPreview});

  final bool hasPreview;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasPreview ? Icons.search_off_rounded : Icons.preview_outlined,
            size: 32,
            color: libraryTextMuted,
          ),
          const SizedBox(height: 10),
          Text(
            hasPreview ? '没有匹配的预览项' : '输入路径映射后生成只读预览',
            style: const TextStyle(
              color: libraryTextMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/** 单个批量 Relink 预览条目，状态由图标、文字和色彩共同表达。 */
class BulkRelinkPreviewRow extends StatelessWidget {
  const BulkRelinkPreviewRow({super.key, required this.preview});

  final BulkPathRelinkPreview preview;

  @override
  Widget build(BuildContext context) {
    final color = bulkRelinkStatusColor(preview.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: libraryBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              bulkRelinkStatusIcon(preview.status),
              color: color,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Tooltip(
              message: '${preview.item.path}\n→ ${preview.newPath}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview.item.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: libraryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '→ ${preview.newPath}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: libraryTextMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          BulkRelinkSummaryBadge(
            icon: bulkRelinkStatusIcon(preview.status),
            label: bulkRelinkStatusLabel(preview.status),
            color: color,
          ),
        ],
      ),
    );
  }
}

String bulkRelinkStatusLabel(BulkRelinkStatus status) => switch (status) {
      BulkRelinkStatus.ready => '可更新',
      BulkRelinkStatus.targetMissing => '目标不存在',
      BulkRelinkStatus.pathConflict => '路径冲突',
      BulkRelinkStatus.fingerprintMismatch => '指纹不一致',
      BulkRelinkStatus.executionFailed => '执行失败，可重试',
    };

IconData bulkRelinkStatusIcon(BulkRelinkStatus status) => switch (status) {
      BulkRelinkStatus.ready => Icons.check_circle_outline_rounded,
      BulkRelinkStatus.targetMissing => Icons.help_outline_rounded,
      BulkRelinkStatus.pathConflict => Icons.warning_amber_rounded,
      BulkRelinkStatus.fingerprintMismatch => Icons.fingerprint_rounded,
      BulkRelinkStatus.executionFailed => Icons.refresh_rounded,
    };

/** 批量预览状态的语义色；图标和文字仍保留，颜色不是唯一编码。 */
Color bulkRelinkStatusColor(BulkRelinkStatus status) => switch (status) {
      BulkRelinkStatus.ready => const Color(0xff61d49a),
      BulkRelinkStatus.targetMissing => const Color(0xffe4aa58),
      BulkRelinkStatus.pathConflict => const Color(0xffe07280),
      BulkRelinkStatus.fingerprintMismatch => const Color(0xffc18cff),
      BulkRelinkStatus.executionFailed => const Color(0xffe07280),
    };
