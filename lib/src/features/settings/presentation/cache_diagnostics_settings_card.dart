import 'package:flutter/material.dart';

import '../../../services/media/thumbnail_service.dart';
import 'cache_diagnostics_snapshot_view.dart';
import 'cache_failure_actions.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 缓存诊断二级页的只读状态卡。
 *
 * 组件只组合 controller 已发布的快照和页面注入的动作回调；缓存读取、重试、清理、
 * Repository 写入和互斥状态仍由 `CacheSettingsPage` 的既有 owner 管理。
 */
class CacheDiagnosticsSettingsCard extends StatelessWidget {
  const CacheDiagnosticsSettingsCard({
    super.key,
    required this.loading,
    required this.hasError,
    required this.stats,
    required this.cacheActionRunning,
    required this.onRetry,
    required this.onRetryFailures,
    required this.onClearFailures,
  });

  /** 最新统计请求是否仍在加载。 */
  final bool loading;

  /** 最新统计请求是否失败。 */
  final bool hasError;

  /** 最近一次成功读取的只读统计快照。 */
  final CacheStats? stats;

  /** 页面缓存维护 owner 是否正在执行动作。 */
  final bool cacheActionRunning;

  /** 重新读取统计快照的意图回调。 */
  final VoidCallback onRetry;

  /** 定向重试当前失败快照的意图回调。 */
  final ValueChanged<CacheStats> onRetryFailures;

  /** 清除当前失败标记的意图回调。 */
  final ValueChanged<CacheStats> onClearFailures;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: CacheDiagnosticsLoadStateView(
          loading: loading,
          hasError: hasError,
          stats: stats,
          cacheActionRunning: cacheActionRunning,
          onRetry: onRetry,
          failureActionsBuilder: (stats, cacheBusy) => CacheFailureActions(
            hasFailures: stats.failures.isNotEmpty,
            cacheBusy: cacheBusy,
            onRetry: () => onRetryFailures(stats),
            onClear: () => onClearFailures(stats),
          ),
        ),
      ),
    );
  }
}
