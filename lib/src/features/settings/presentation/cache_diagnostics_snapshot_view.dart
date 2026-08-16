import 'package:flutter/material.dart';

import '../application/cache_diagnostics_maintenance_controller.dart';
import '../../../services/media/thumbnail_service.dart';
import '../../../widgets/app_theme_tokens.dart';
import 'cache_diagnostics_header.dart';
import 'cache_diagnostics_snapshot_sections.dart';

export 'cache_diagnostics_snapshot_sections.dart';

// ignore_for_file: slash_for_doc_comments

/** 格式化失败项重试结果，不改变队列或持久化状态。 */
String cacheRetryOutcomeLabel(CacheRetryOutcome outcome) =>
    outcome.retried == outcome.requested
        ? '已重新排队 ${outcome.retried} 个失败缩略图'
        : '已重新排队 ${outcome.retried} 个；'
            '另有 ${outcome.requested - outcome.retried} 个仍待处理';

/** 格式化失败标记清除结果，明确不会删除视频或缓存文件。 */
String cacheClearOutcomeLabel(CacheClearOutcome outcome) =>
    '已清除 ${outcome.cleared} 条失败标记；视频和缓存文件未删除';

/**
 * 缓存统计读取期间的只读结构占位。
 *
 * 该组件不持有 Future，也不触发读取；调用方负责 latest-only 加载和生命周期。
 */
class CacheDiagnosticsLoading extends StatelessWidget {
  const CacheDiagnosticsLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '正在读取缩略图缓存统计',
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CacheDiagnosticsHeader(
            statusLabel: '读取统计中',
            statusColor: appAccentViolet,
          ),
          SizedBox(height: 18),
          Text(
            '正在校验有效 JPEG 与后台任务状态…',
            style: TextStyle(color: libraryTextMuted),
          ),
          SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
            child: LinearProgressIndicator(minHeight: 4),
          ),
        ],
      ),
    );
  }
}

/**
 * 缓存统计读取失败时的安全恢复入口。
 *
 * 展示层不接收原始异常，避免文件系统错误把本机路径带入 UI；[onRetry] 只重新请求只读
 * 快照，不执行失败项重试、清理或缓存删除。
 */
class CacheDiagnosticsLoadError extends StatelessWidget {
  const CacheDiagnosticsLoadError({
    super.key,
    required this.onRetry,
  });

  /** 重新读取缓存统计的只读命令。 */
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '缩略图缓存统计读取失败',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CacheDiagnosticsHeader(
            statusLabel: '读取失败',
            statusColor: Colors.orangeAccent,
          ),
          const SizedBox(height: 18),
          const Text(
            '暂时无法读取缓存统计。缓存文件和后台任务未被修改，可以稍后重试。',
            style: TextStyle(color: libraryTextMuted, height: 1.4),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('settings.cache.loadError.retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新读取'),
            ),
          ),
        ],
      ),
    );
  }
}

/** 由页面命令 owner 为当前缓存快照构建失败动作区。 */
typedef CacheFailureActionsBuilder = Widget Function(
  CacheStats stats,
  bool cacheBusy,
);

/**
 * 缓存诊断只读加载状态的展示分派。
 *
 * 该组件只解释 controller 已发布的 loading/error/data 快照；缓存动作仍由
 * [failureActionsBuilder] 回传给页面 owner 构造，不在 presentation 发起服务调用。
 */
class CacheDiagnosticsLoadStateView extends StatelessWidget {
  const CacheDiagnosticsLoadStateView({
    super.key,
    required this.loading,
    required this.hasError,
    required this.stats,
    required this.cacheActionRunning,
    required this.onRetry,
    required this.failureActionsBuilder,
  });

  /** 最新只读请求是否仍在加载。 */
  final bool loading;

  /** 最新读取是否失败；原始异常不会进入展示层。 */
  final bool hasError;

  /** 最新成功读取的缓存快照。 */
  final CacheStats? stats;

  /** 页面命令 owner 是否正在执行重试或清理。 */
  final bool cacheActionRunning;

  /** 只重新读取统计的恢复入口。 */
  final VoidCallback onRetry;

  /** 为成功快照构建仍由页面拥有的失败动作区。 */
  final CacheFailureActionsBuilder failureActionsBuilder;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const CacheDiagnosticsLoading();
    }
    if (hasError) {
      return CacheDiagnosticsLoadError(onRetry: onRetry);
    }
    final stats = this.stats;
    if (stats == null) {
      return const CacheDiagnosticsLoading();
    }
    final cacheBusy = cacheActionRunning ||
        stats.active > 0 ||
        stats.queued > 0 ||
        stats.pendingBackgroundRequests > 0 ||
        stats.backgroundGenerationActive;
    return CacheDiagnosticsSnapshotView(
      stats: stats,
      cacheBusy: cacheBusy,
      failureActions: failureActionsBuilder(stats, cacheBusy),
    );
  }
}
