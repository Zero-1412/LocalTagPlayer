import 'package:flutter/material.dart';

import '../../../services/media/thumbnail_service.dart';
import '../../../widgets/app_theme_tokens.dart';
import 'cache_diagnostics_header.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 缓存诊断只读快照视图。
 *
 * [stats] 由外部 owner 完成读取并发布；[failureActions] 由命令 owner 构造后注入。组件只
 * 解释快照，不访问磁盘、不创建任务，也不改变“失败属于缺失子集”的缓存语义。
 */
class CacheDiagnosticsSnapshotView extends StatelessWidget {
  const CacheDiagnosticsSnapshotView({
    super.key,
    required this.stats,
    required this.cacheBusy,
    required this.failureActions,
  });

  /** 当前缓存统计快照。 */
  final CacheStats stats;

  /** 既有缓存动作或后台队列是否正在运行。 */
  final bool cacheBusy;

  /** 页面命令 owner 提供的失败动作区。 */
  final Widget failureActions;

  @override
  Widget build(BuildContext context) {
    final hasFailures = stats.failures.isNotEmpty;
    final cachedRatio = stats.total == 0 ? 0.0 : stats.cached / stats.total;
    final statusLabel = hasFailures
        ? '${_formatCount(stats.errors)} 个失败项'
        : stats.paused
            ? '后台任务已暂停'
            : cacheBusy
                ? '后台任务运行中'
                : '缓存服务空闲';
    final statusColor = hasFailures
        ? Colors.orangeAccent
        : cacheBusy || stats.paused
            ? appAccentViolet
            : const Color(0xff42d3a6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CacheDiagnosticsHeader(
          statusLabel: statusLabel,
          statusColor: statusColor,
        ),
        const SizedBox(height: 18),
        _CacheCoverageSummary(
          cached: stats.cached,
          total: stats.total,
          ratio: cachedRatio.clamp(0.0, 1.0).toDouble(),
        ),
        const SizedBox(height: 14),
        _CacheMetricGrid(stats: stats),
        const SizedBox(height: 14),
        _CacheTaskSummary(stats: stats),
        const SizedBox(height: 14),
        const _CacheFailureSemanticsNote(),
        if (hasFailures) ...[
          const SizedBox(height: 14),
          _CacheFailureDetails(failures: stats.failures),
        ],
        const SizedBox(height: 14),
        failureActions,
      ],
    );
  }
}

/** 有效 JPEG 覆盖率摘要；进度只来源于当前快照。 */
class _CacheCoverageSummary extends StatelessWidget {
  const _CacheCoverageSummary({
    required this.cached,
    required this.total,
    required this.ratio,
  });

  final int cached;
  final int total;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('settings.cache.coverage'),
      decoration: _surfaceDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '有效缓存覆盖',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${_formatCount(cached)} / ${_formatCount(total)}',
                  style: const TextStyle(
                    color: libraryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius:
                  const BorderRadius.all(Radius.circular(AppRadius.capsule)),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                color: appAccentViolet,
                backgroundColor: libraryBorder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/** 总量、有效缓存、缺失和失败的响应式统计网格。 */
class _CacheMetricGrid extends StatelessWidget {
  const _CacheMetricGrid({required this.stats});

  final CacheStats stats;

  @override
  Widget build(BuildContext context) {
    final metrics = <({
      String keyName,
      String label,
      String value,
      IconData icon,
      Color color
    })>[
      (
        keyName: 'total',
        label: '总数',
        value: _formatCount(stats.total),
        icon: Icons.video_library_outlined,
        color: libraryTextMuted,
      ),
      (
        keyName: 'cached',
        label: '已缓存',
        value: _formatCount(stats.cached),
        icon: Icons.check_circle_outline_rounded,
        color: const Color(0xff42d3a6),
      ),
      (
        keyName: 'missing',
        label: '缺失',
        value: _formatCount(stats.missing),
        icon: Icons.image_not_supported_outlined,
        color: appAccentViolet,
      ),
      (
        keyName: 'errors',
        label: '失败',
        value: _formatCount(stats.errors),
        icon: Icons.error_outline_rounded,
        color: stats.errors == 0 ? libraryTextMuted : Colors.orangeAccent,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 420
                ? 2
                : 1;
        const spacing = 10.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: itemWidth,
                child: _CacheMetricCard(
                  key: ValueKey('settings.cache.metric.${metric.keyName}'),
                  label: metric.label,
                  value: metric.value,
                  icon: metric.icon,
                  color: metric.color,
                ),
              ),
          ],
        );
      },
    );
  }
}

/** 单个缓存指标卡片。 */
class _CacheMetricCard extends StatelessWidget {
  const _CacheMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _surfaceDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: libraryTextMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: libraryText,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/** 后台并发、排队、请求和耗时摘要。 */
class _CacheTaskSummary extends StatelessWidget {
  const _CacheTaskSummary({required this.stats});

  final CacheStats stats;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('settings.cache.taskSummary'),
      decoration: _surfaceDecoration(alpha: 0.62),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('后台任务', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                _taskValue('活动', '${stats.active} / ${stats.maxConcurrent}'),
                _taskValue('排队', _formatCount(stats.queued)),
                _taskValue(
                  '后台请求',
                  _formatCount(stats.pendingBackgroundRequests),
                ),
                _taskValue('平均耗时', '${stats.averageMs} ms'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /** 构建摘要中的单个键值，不持有独立状态。 */
  Widget _taskValue(String label, String value) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label  ',
            style: const TextStyle(
              color: libraryTextMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/** 明确失败与缺失的包含关系，避免用户误解统计口径。 */
class _CacheFailureSemanticsNote extends StatelessWidget {
  const _CacheFailureSemanticsNote();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('settings.cache.failureSemantics'),
      decoration: BoxDecoration(
        color: appAccentViolet.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: appAccentViolet.withValues(alpha: 0.24)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: appAccentViolet, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '失败属于缺失的可诊断子集：失败项当前没有有效 JPEG，因此会同时计入缺失；普通缺失可能只是尚未生成。',
                style: TextStyle(color: libraryTextMuted, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/** 可展开的失败文件与最近原因列表，最多展示前 50 项。 */
class _CacheFailureDetails extends StatelessWidget {
  const _CacheFailureDetails({required this.failures});

  final List<CacheFailureDetail> failures;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _surfaceDecoration(alpha: 0.48),
      child: ExpansionTile(
        key: const ValueKey('settings.cache.failureDetails'),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          '失败详情 · ${failures.length}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text('显示视频标题和最近一次缩略图失败原因'),
        children: [
          for (final failure in failures.take(50))
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.error_outline_rounded,
                color: Colors.orangeAccent,
              ),
              title: Text(
                failure.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                failure.reason,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (failures.length > 50)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '另有 ${failures.length - 50} 条，请处理当前失败项后刷新统计。',
                style: const TextStyle(color: libraryTextMuted),
              ),
            ),
        ],
      ),
    );
  }
}

/** 共享只读诊断卡片表面，避免重复的视觉实现产生漂移。 */
BoxDecoration _surfaceDecoration({double alpha = 1}) => BoxDecoration(
      color: librarySurfaceAlt.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(AppRadius.control),
      border: Border.all(color: libraryBorder),
    );

/** 保持现有缓存统计的千位分隔格式。 */
String _formatCount(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index += 1) {
    final remaining = text.length - index;
    buffer.write(text[index]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}
