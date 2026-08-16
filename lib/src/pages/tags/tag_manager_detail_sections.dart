import 'package:flutter/material.dart';

import '../../models/platform_models.dart';
import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 标签详情中的单个维护分组，统一标题、说明与内容表面。 */
class TagManagerSection extends StatelessWidget {
  const TagManagerSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.danger = false,
  });

  /** 分组标题。 */
  final String title;

  /** 可选的影响范围或当前状态说明。 */
  final String? subtitle;

  /** 分组的真实输入、状态或动作内容。 */
  final Widget child;

  /** 是否为需要清晰风险边界的操作分组。 */
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final dangerColor = Theme.of(context).colorScheme.error;
    // 使用真实 Material 承载内部 SwitchListTile 的 focus/hover/ink，避免表面色遮住反馈。
    return Material(
      color: danger ? dangerColor.withValues(alpha: 0.06) : librarySurfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: danger ? dangerColor.withValues(alpha: 0.55) : libraryBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: danger ? dangerColor : libraryText,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(subtitle!, style: const TextStyle(color: libraryTextMuted)),
            ],
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/** 右侧 inspector 的标签身份头部，先回答“正在维护什么”再展示编辑表单。 */
class TagManagerInspectorHeader extends StatelessWidget {
  const TagManagerInspectorHeader({
    super.key,
    required this.tag,
    required this.groupLabel,
    required this.usageCount,
  });

  final TagItem tag;
  final String groupLabel;
  final int usageCount;

  @override
  Widget build(BuildContext context) {
    final isFolder = tag.source == TagSource.folder;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: const Border.fromBorderSide(BorderSide(color: libraryBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: appAccentViolet.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  isFolder ? Icons.folder_outlined : Icons.sell_outlined,
                  color: libraryAccent,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '标签 inspector',
                    style: TextStyle(
                      color: libraryTextMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tag.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TagManagerMetaPill(label: tag.source.name),
                      TagManagerMetaPill(label: groupLabel),
                      TagManagerMetaPill(label: '使用 $usageCount'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ID: ${tag.id}',
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
          ],
        ),
      ),
    );
  }
}

/** inspector 头部使用的低强调元数据胶囊，区别于可操作的分组 ChoiceChip。 */
class TagManagerMetaPill extends StatelessWidget {
  const TagManagerMetaPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: librarySurface,
        borderRadius: BorderRadius.circular(7),
        border: const Border.fromBorderSide(BorderSide(color: libraryBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: const TextStyle(
            color: libraryTextMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class TagGroupSummary extends StatelessWidget {
  const TagGroupSummary({
    super.key,
    required this.groups,
    required this.selectedGroupId,
    required this.onSelected,
  });

  final List<TagGroup> groups;

  /** 当前用于过滤左侧标签列表的分组；null 表示全部。 */
  final String? selectedGroupId;

  /** 选择或取消分组过滤；只影响 Tag Manager 当前列表。 */
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Text('暂无标签组', style: TextStyle(color: libraryTextMuted)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '标签组',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('tagManager.group.all'),
                label: const Text('全部'),
                selected: selectedGroupId == null,
                showCheckmark: false,
                avatar: selectedGroupId == null
                    ? const Icon(Icons.check_rounded, size: 16)
                    : null,
                onSelected: (_) => onSelected(null),
              ),
              for (final group in groups)
                Tooltip(
                  message: '${group.id} · sort ${group.sortOrder}',
                  child: ChoiceChip(
                    key: ValueKey('tagManager.group.${group.id}'),
                    label: Text(group.displayName ?? group.name),
                    selected: selectedGroupId == group.id,
                    showCheckmark: false,
                    avatar: selectedGroupId == group.id
                        ? const Icon(Icons.check_rounded, size: 16)
                        : null,
                    onSelected: (selected) =>
                        onSelected(selected ? group.id : null),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/** 标签分组选择反馈的 focused widget 测试宿主。 */
@visibleForTesting
Widget tagManagerGroupSummarySmokeHarness(List<TagGroup> groups) {
  String? selectedGroupId;
  return MaterialApp(
    theme: maintenanceWorkspaceTheme(ThemeData(useMaterial3: true)),
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => TagGroupSummary(
          groups: groups,
          selectedGroupId: selectedGroupId,
          onSelected: (value) => setState(() => selectedGroupId = value),
        ),
      ),
    ),
  );
}

class UsagePill extends StatelessWidget {
  const UsagePill({super.key, required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label $value'),
      backgroundColor: librarySurfaceAlt,
      side: const BorderSide(color: libraryBorder),
    );
  }
}
