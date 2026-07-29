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
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sell_outlined, size: 34, color: libraryTextMuted),
            SizedBox(height: 12),
            Text(
              '选择一个标签查看和维护详情',
              style: TextStyle(color: libraryTextMuted),
            ),
          ],
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
