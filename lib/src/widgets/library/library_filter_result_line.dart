import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 筛选工具栏末端的结果数量、扫描进度与任务控制行。 */
class LibraryFilterResultLine extends StatelessWidget {
  const LibraryFilterResultLine({
    super.key,
    required this.resultCount,
    this.resultCountLabel,
    required this.refreshing,
    required this.progressLabel,
    required this.progressValue,
    required this.progressPaused,
    required this.onToggleProgressPaused,
    required this.onCancelProgress,
  });

  final int resultCount;

  /** 自定义结果统计；为空时沿用“视频”语义。 */
  final String? resultCountLabel;

  final bool refreshing;

  final String? progressLabel;

  final double? progressValue;

  final bool progressPaused;

  final VoidCallback? onToggleProgressPaused;

  /** 当前扫描的取消入口；为空时不占用进度行空间。 */
  final VoidCallback? onCancelProgress;

  @override
  Widget build(BuildContext context) {
    final operationInProgress = progressLabel != null;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (!operationInProgress) ...[
        const Icon(Icons.circle, size: 7, color: appAccentViolet),
        const SizedBox(width: AppSpacing.xs),
      ],
      Flexible(
        child: Text(
          progressLabel ?? resultCountLabel ?? '$resultCount 个视频',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: libraryText,
            fontSize: 13,
            fontWeight: AppTypography.strong,
          ),
        ),
      ),
      if (operationInProgress) ...[
        const SizedBox(width: 8),
        if (progressValue == null)
          const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          SizedBox(
            width: 64,
            child: LinearProgressIndicator(
              value: progressValue!.clamp(0, 1),
              minHeight: 4,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: const Color(0xffe7e4ff),
            ),
          ),
        if (onToggleProgressPaused != null) ...[
          const SizedBox(width: 4),
          SizedBox.square(
            dimension: 28,
            child: IconButton(
              key: ValueKey(progressPaused
                  ? 'qa.media_import.resume'
                  : 'qa.media_import.pause'),
              tooltip: progressPaused ? '继续后台任务' : '暂停后台任务',
              padding: EdgeInsets.zero,
              iconSize: 18,
              color: appAccentViolet,
              onPressed: onToggleProgressPaused,
              icon: Icon(
                progressPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              ),
            ),
          ),
        ],
        if (onCancelProgress != null) ...[
          const SizedBox(width: 2),
          SizedBox.square(
            dimension: 28,
            child: IconButton(
              key: const ValueKey('qa.library_scan.cancel'),
              tooltip: '取消扫描',
              padding: EdgeInsets.zero,
              iconSize: 17,
              color: libraryTextMuted,
              onPressed: onCancelProgress,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ] else if (refreshing) ...[
        const SizedBox(width: 8),
        const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ],
    ]);
  }
}
