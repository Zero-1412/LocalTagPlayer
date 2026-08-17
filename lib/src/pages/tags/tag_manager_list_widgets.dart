import 'package:flutter/material.dart';

import '../../models/platform_models.dart';
import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 标签中心未选择项目时的稳定空详情表面。 */
class TagManagerEmptyDetail extends StatelessWidget {
  const TagManagerEmptyDetail({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: librarySurface,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.panel)),
        border: Border.fromBorderSide(BorderSide(color: libraryBorder)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: librarySurfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: const Border.fromBorderSide(
                  BorderSide(color: libraryBorder),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Icon(Icons.sell_outlined,
                    size: 28, color: libraryTextMuted),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '选择一个标签查看和维护详情',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: libraryText,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '从左侧列表选择标签，开始编辑属性或检查影响范围。',
                textAlign: TextAlign.center,
                style: TextStyle(color: libraryTextMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/** 标签中心的实色结构表面；只负责层级、语义和裁切，不拥有标签状态。 */
class TagManagerWorkspaceSurface extends StatelessWidget {
  const TagManagerWorkspaceSurface({
    super.key,
    required this.surfaceKey,
    required this.label,
    required this.child,
  });

  /** 供页面级挂载和截图检查使用的稳定表面 key。 */
  final Key surfaceKey;

  /** 辅助技术读取的结构区域名称。 */
  final String label;

  /** 左侧导航或右侧 inspector 的内容。 */
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: label,
      child: Material(
        key: surfaceKey,
        color: librarySurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.panel)),
          side: BorderSide(color: libraryBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/** 标签中心右侧 inspector 的统一外壳，保持选中态和空状态共享同一边界。 */
class TagManagerInspectorSurface extends StatelessWidget {
  const TagManagerInspectorSurface({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TagManagerWorkspaceSurface(
      surfaceKey: const ValueKey('tagManager.inspectorSurface'),
      label: '标签 inspector 工作区',
      child: child,
    );
  }
}

/** 左侧标签列表的上下文标题，展示发现范围而不改变筛选语义。 */
class TagManagerListHeader extends StatelessWidget {
  const TagManagerListHeader({
    super.key,
    required this.visibleCount,
  });

  final int visibleCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sell_outlined, size: 18, color: libraryAccent),
              const SizedBox(width: 8),
              Text(
                '标签',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              Text(
                '$visibleCount 个',
                style: const TextStyle(
                  color: libraryTextMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            '按来源和分组维护标签关系',
            style: TextStyle(color: libraryTextMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/** 标签列表单行外壳，保留单击选中回调并强化 selected 的定位线。 */
class TagManagerListItem extends StatelessWidget {
  const TagManagerListItem({
    super.key,
    required this.row,
    required this.groupLabel,
    required this.selected,
    required this.onTap,
  });

  final TagManagerTagRow row;
  final String groupLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tag = row.tag;
    final isFolder = tag.source == TagSource.folder;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: Material(
        color: selected
            ? appAccentViolet.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border(
                left: BorderSide(
                  color: selected ? appAccentViolet : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected
                        ? appAccentViolet.withValues(alpha: 0.18)
                        : librarySurfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Icon(
                      isFolder ? Icons.folder_outlined : Icons.sell_outlined,
                      size: 16,
                      color: selected ? libraryAccent : libraryTextMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.displayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        row.subtitle(groupLabel),
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
                if (tag.isHidden)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.visibility_off_outlined,
                        size: 17, color: libraryTextMuted),
                  )
                else if (tag.isFavorite)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.star_rounded,
                        size: 17, color: libraryAccent),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/** 标签中心唯一的稳定搜索输入，键盘输入与 controller 变更共享刷新回调。 */
class TagManagerSearchField extends StatelessWidget {
  const TagManagerSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  /** 持有当前搜索关键词的唯一 controller。 */
  final TextEditingController controller;

  /** 输入或清除后通知页面刷新当前可见标签。 */
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('tagManager.search'),
      controller: controller,
      decoration: InputDecoration(
        hintText: '搜索标签 / 别名',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清除标签搜索',
                onPressed: () {
                  controller.clear();
                  onChanged();
                },
                icon: const Icon(Icons.close_rounded),
              ),
      ),
      onChanged: (_) => onChanged(),
    );
  }
}

/** 标签中心搜索链路的 focused widget 测试宿主。 */
@visibleForTesting
Widget tagManagerSearchSmokeHarness({
  required TextEditingController controller,
  required VoidCallback onChanged,
}) {
  return MaterialApp(
    theme: maintenanceWorkspaceTheme(ThemeData(useMaterial3: true)),
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: TagManagerSearchField(
            controller: controller,
            onChanged: () {
              onChanged();
              setState(() {});
            },
          ),
        ),
      ),
    ),
  );
}

class TagManagerTagRow {
  const TagManagerTagRow({
    required this.tag,
    required this.usage,
    required this.duplicateCount,
    required this.caseVariants,
  });

  final TagItem tag;
  final TagUsageSummary usage;
  final int duplicateCount;
  final List<String> caseVariants;

  factory TagManagerTagRow.fromItems(
    List<TagItem> items,
    Map<String, TagUsageSummary> usageById,
  ) {
    final sorted = [...items]..sort((a, b) {
        final usageA = usageById[a.id]?.total ?? a.usageCount;
        final usageB = usageById[b.id]?.total ?? b.usageCount;
        final byUsage = usageB.compareTo(usageA);
        if (byUsage != 0) {
          return byUsage;
        }
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        if (byOrder != 0) {
          return byOrder;
        }
        return (a.displayName ?? a.name).compareTo(b.displayName ?? b.name);
      });
    final tag = sorted.first;
    final variants = <String>{};
    var total = const TagUsageSummary();
    for (final item in sorted) {
      variants.add(item.displayName ?? item.name);
      final usage = usageById[item.id] ??
          TagUsageSummary(
            total: item.usageCount,
            folder: item.source == TagSource.folder ? item.usageCount : 0,
            manual: item.source == TagSource.manual ? item.usageCount : 0,
            rule: item.source == TagSource.rule ? item.usageCount : 0,
            filename: item.source == TagSource.filename ? item.usageCount : 0,
            imported: item.source == TagSource.import ? item.usageCount : 0,
            auto: item.source == TagSource.auto ? item.usageCount : 0,
          );
      total = TagUsageSummary(
        total: total.total + usage.total,
        folder: total.folder + usage.folder,
        manual: total.manual + usage.manual,
        rule: total.rule + usage.rule,
        filename: total.filename + usage.filename,
        imported: total.imported + usage.imported,
        auto: total.auto + usage.auto,
      );
    }
    return TagManagerTagRow(
      tag: tag,
      usage: total,
      duplicateCount: sorted.length,
      caseVariants: variants.toList()..sort(),
    );
  }

  String get displayLabel {
    final parent = tag.parentId?.trim();
    final label = tag.displayName ?? tag.name;
    if (parent == null || parent.isEmpty || tag.groupId != 'folder.child') {
      return label;
    }
    return '$parent / $label';
  }

  bool matches(String token) {
    if (tag.matchesNameOrAlias(token)) {
      return true;
    }
    return caseVariants.any((value) => value.toLowerCase().contains(token));
  }

  String subtitle(String groupLabel) {
    final parts = <String>[
      groupLabel,
      tag.source.name,
      '使用 ${usage.total}',
    ];
    if (duplicateCount > 1) {
      parts.add('已合并 $duplicateCount 个大小写变体');
    }
    return parts.join(' · ');
  }
}

/** 按来源、分组、父级和大小写归一名称生成展示去重键。 */
String tagManagerDedupeKey(TagItem tag) {
  final source = tag.source.name;
  final group = tag.groupId ?? 'manual';
  final parent = (tag.parentId ?? '').trim().toLowerCase();
  final name = tag.name.trim().toLowerCase();
  return '$source|$group|$parent|$name';
}

/** 测试复用生产去重键，防止 focused fixture 复制标签来源规则。 */
@visibleForTesting
String tagManagerDedupeKeyForTesting(TagItem tag) => tagManagerDedupeKey(tag);

@visibleForTesting
List<String> tagManagerDisplayRowsForTesting({
  required Iterable<TagItem> tags,
  required Map<String, TagUsageSummary> usage,
}) {
  final grouped = <String, List<TagItem>>{};
  for (final tag in tags) {
    (grouped[tagManagerDedupeKey(tag)] ??= <TagItem>[]).add(tag);
  }
  final rows = [
    for (final items in grouped.values)
      TagManagerTagRow.fromItems(items, usage),
  ]..sort((a, b) => a.displayLabel.compareTo(b.displayLabel));
  return [
    for (final row in rows)
      '${row.displayLabel}|${row.usage.total}|${row.duplicateCount}',
  ];
}
