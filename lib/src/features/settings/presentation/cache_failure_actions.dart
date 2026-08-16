import 'package:flutter/material.dart';

import '../../../services/media/thumbnail_service.dart';
import '../../../widgets/app_theme_tokens.dart';
import 'cache_diagnostics_snapshot_view.dart';
import 'settings_workspace_theme.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 构建缓存诊断面板的 focused widget test 容器。
 *
 * 测试只注入不可变统计快照和动作回调，不创建真实缓存队列或后台任务。
 */
@visibleForTesting
Widget cacheDiagnosticsSmokeHarness({
  required CacheStats stats,
  bool cacheBusy = false,
  VoidCallback? onRetry,
  VoidCallback? onClear,
  VoidCallback? onGenerateMissing,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    theme: settingsWorkspaceTheme(ThemeData(useMaterial3: true)),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(1000, 900),
        textScaler: textScaler,
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: CacheDiagnosticsSnapshotView(
            stats: stats,
            cacheBusy: cacheBusy,
            failureActions: CacheFailureActions(
              hasFailures: stats.failures.isNotEmpty,
              missingCount: stats.missing,
              cacheBusy: cacheBusy,
              onRetry: onRetry ?? () {},
              onClear: onClear ?? () {},
              onGenerateMissing: onGenerateMissing,
            ),
          ),
        ),
      ),
    ),
  );
}

/** 失败处理区保留既有动作，并在没有失败时给出明确完成反馈。 */
class CacheFailureActions extends StatelessWidget {
  const CacheFailureActions({
    super.key,
    required this.hasFailures,
    required this.missingCount,
    required this.cacheBusy,
    required this.onRetry,
    required this.onClear,
    required this.onGenerateMissing,
  });

  /** 当前是否存在可定向处理的失败条目。 */
  final bool hasFailures;

  /** 当前没有有效 JPEG 的条目数量；普通缺失也可由用户显式启动补全。 */
  final int missingCount;

  /** 既有队列忙碌时禁止重复提交。 */
  final bool cacheBusy;

  /** 重试回调。 */
  final VoidCallback onRetry;

  /** 清除失败标记回调。 */
  final VoidCallback onClear;

  /** 用户显式启动缺失缓存补全；空值表示测试宿主未注入动作。 */
  final VoidCallback? onGenerateMissing;

  @override
  Widget build(BuildContext context) {
    final actionsEnabled = hasFailures && !cacheBusy;
    final generationEnabled =
        missingCount > 0 && !cacheBusy && onGenerateMissing != null;
    final status = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          hasFailures
              ? Icons.build_circle_outlined
              : Icons.check_circle_outline_rounded,
          color: hasFailures ? Colors.orangeAccent : const Color(0xff42d3a6),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasFailures ? '失败处理' : '当前没有失败项',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                hasFailures
                    ? cacheBusy
                        ? '后台任务结束后可重试或清除诊断标记。'
                        : '重试复用现有优先队列；清除标记不会删除视频或有效缓存。'
                    : cacheBusy
                        ? '后台任务正在按限流窗口推进；当前缺失项会继续处理。'
                        : missingCount > 0
                            ? '普通缺失不会自动生成；可手动启动有界补全。'
                            : '当前没有缺失缓存，无需启动补全。',
                style: const TextStyle(color: libraryTextMuted, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          key: const ValueKey('settings.cache.generateMissing'),
          onPressed: generationEnabled ? onGenerateMissing : null,
          icon: const Icon(Icons.image_search_rounded),
          label: const Text('生成缺失缓存'),
        ),
        FilledButton.icon(
          key: const ValueKey('settings.cache.retryFailures'),
          onPressed: actionsEnabled ? onRetry : null,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重试失败项'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('settings.cache.clearFailures'),
          onPressed: actionsEnabled ? onClear : null,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('清除失败标记'),
        ),
      ],
    );
    return DecoratedBox(
      key: const ValueKey('settings.cache.failureActions'),
      decoration: BoxDecoration(
        color: librarySurfaceAlt.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: libraryBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 动作区优先保证说明可读，窄窗时按钮自然换到下一行。
            if (constraints.maxWidth < 780) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  status,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: status),
                const SizedBox(width: 14),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}
