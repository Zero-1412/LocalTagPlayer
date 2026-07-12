part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放器弹窗内部统一使用的信息卡片。
 *
 * 该组件只约束标题、边框、内边距和内容节奏，不承载业务状态，避免标签、
 * 视频信息与诊断弹窗各自维护一套视觉规则。
 */
class _PlayerDialogSectionCard extends StatelessWidget {
  const _PlayerDialogSectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    this.expandChild = false,
  });

  /** 卡片分组标题。 */
  final String title;

  /** 用于快速辨识信息类别的图标。 */
  final IconData icon;

  /** 标题右侧的可选状态或计数。 */
  final Widget? trailing;

  /** 卡片主体内容。 */
  final Widget child;

  /** 主体与卡片边缘的留白。 */
  final EdgeInsetsGeometry padding;

  /** 是否让主体占满卡片剩余高度，供内部滚动区域使用。 */
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            if (expandChild) Expanded(child: child) else child,
          ],
        ),
      ),
    );
  }
}

/** 播放器信息弹窗中统一的“标签－值”信息行。 */
class _PlayerDialogInfoRow extends StatelessWidget {
  const _PlayerDialogInfoRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  /** 左侧字段名称。 */
  final String label;

  /** 右侧字段值。 */
  final String value;

  /** 是否强调当前值。 */
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
