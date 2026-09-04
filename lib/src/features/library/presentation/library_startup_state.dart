import 'package:flutter/material.dart';

// ignore_for_file: slash_for_doc_comments

/** 首屏依赖尚未恢复时的稳定加载状态。 */
class LibraryStartupLoadingView extends StatelessWidget {
  const LibraryStartupLoadingView({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        key: ValueKey('library.startup.loading'),
        body: Center(child: CircularProgressIndicator()),
      );
}

/**
 * 媒体库首屏失败后的稳定恢复界面。
 *
 * 页面不展示可能包含本机路径的原始异常，只提供可执行重试；详细错误继续进入诊断日志。
 */
class LibraryStartupFailureView extends StatelessWidget {
  const LibraryStartupFailureView({super.key, required this.onRetry});

  /** 再次调用同一个应用加载边界。 */
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('library.startup.failed'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 42),
                const SizedBox(height: 16),
                Text(
                  '媒体库暂时无法加载',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  '数据库或设置读取失败。你的媒体文件不会被修改，可以安全重试。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey('library.startup.retry'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新加载'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
