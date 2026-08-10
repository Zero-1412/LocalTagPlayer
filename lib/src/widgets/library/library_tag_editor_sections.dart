import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 明确同名标签的来源边界，避免用户把可编辑 manual 误认为目录项。 */
class TagEditorSameNameSourceNotice extends StatelessWidget {
  const TagEditorSameNameSourceNotice({super.key, required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final names = tags.map((tag) => '“$tag”').join('、');
    return Semantics(
      container: true,
      child: DecoratedBox(
        key: const ValueKey('tagEditor.sameNameSourceNotice'),
        decoration: BoxDecoration(
          color: libraryAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: libraryAccent.withValues(alpha: 0.32)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 17,
                color: libraryAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$names 同时存在目录和自定义两种来源。移除不带锁图标的同名标签，只会移除自定义标签，不会影响目录标签。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: libraryTextMuted,
                        height: 1.4,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/** 标签编辑器内部统一的维护页面分区，不再借用播放器弹窗材质。 */
class TagEditorSectionCard extends StatelessWidget {
  const TagEditorSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    this.expandChild = false,
  });

  /** 分区标题。 */
  final String title;

  /** 分区语义图标。 */
  final IconData icon;

  /** 分区主体。 */
  final Widget child;

  /** 标题右侧的数量或状态。 */
  final Widget? trailing;

  /** 分区内边距。 */
  final EdgeInsetsGeometry padding;

  /** 是否让主体占满分区剩余高度。 */
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: librarySurfaceAlt.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: libraryBorder),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: libraryAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: libraryText,
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

/** manual 标签编辑器中的轻量候选分区。 */
class TagSuggestionSection extends StatelessWidget {
  const TagSuggestionSection({
    super.key,
    required this.title,
    required this.tags,
    required this.icon,
    required this.onSelected,
  });

  final String title;
  final List<String> tags;
  final IconData icon;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: libraryAccent),
              const SizedBox(width: 6),
              Text(title, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in tags)
                ActionChip(
                  label: Text(tag),
                  onPressed: () => onSelected(tag),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
