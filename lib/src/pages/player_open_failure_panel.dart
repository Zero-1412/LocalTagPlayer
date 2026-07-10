part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放器视频打开失败后的稳定恢复面板。
 *
 * 面板只展示不包含本地路径的安全错误类型，并把重试、跳过和诊断动作交还页面协调，
 * 避免一次 SnackBar 消失后用户无法继续消费当前筛选队列。
 */
class _PlayerOpenFailurePanel extends StatelessWidget {
  const _PlayerOpenFailurePanel({
    required this.failureCode,
    required this.canSkip,
    required this.onRetry,
    required this.onSkip,
    required this.onDiagnostics,
  });

  /** 不包含文件路径和异常正文的安全错误类型。 */
  final String failureCode;

  /** 当前失败项之后是否仍有队列项目。 */
  final bool canSkip;

  /** 重新打开当前视频。 */
  final VoidCallback onRetry;

  /** 跳过当前失败项并继续筛选队列。 */
  final VoidCallback onSkip;

  /** 打开播放诊断详情。 */
  final VoidCallback onDiagnostics;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xcc05070a),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xff151c27),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xff49566a)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xffffb4a9),
                  size: 34,
                ),
                const SizedBox(height: 12),
                const Text(
                  '视频打开失败',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '可能是编码不支持、文件损坏或文件暂时不可访问。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xffc4cede)),
                ),
                const SizedBox(height: 6),
                Text(
                  '错误类型：$failureCode',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xff8f9bad),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('player.openFailure.retry'),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('player.openFailure.skip'),
                      onPressed: canSkip ? onSkip : null,
                      icon: const Icon(Icons.skip_next_rounded),
                      label: const Text('跳过此项'),
                    ),
                    TextButton.icon(
                      key: const ValueKey('player.openFailure.diagnostics'),
                      onPressed: onDiagnostics,
                      icon: const Icon(Icons.monitor_heart_outlined),
                      label: const Text('诊断详情'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
