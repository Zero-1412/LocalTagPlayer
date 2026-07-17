import 'package:flutter/material.dart';

import '../../core/layout_size.dart';
import '../../core/tag_rules.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../services/library/library_application_facade.dart';
import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

class TagManagerPage extends StatefulWidget {
  const TagManagerPage({
    super.key,
    required this.store,
    required this.currentResults,
  });

  final LibraryApplicationFacade store;
  final List<VideoItem> currentResults;

  @override
  State<TagManagerPage> createState() => _TagManagerPageState();
}

class _TagManagerPageState extends State<TagManagerPage> {
  final _searchController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _aliasesController = TextEditingController();
  final _sortOrderController = TextEditingController();
  late Future<Map<String, TagUsageSummary>> _usageFuture;
  String? _selectedTagId;
  String? _editingGroupId;
  bool _editingHidden = false;
  bool _editingFavorite = false;

  @override
  void initState() {
    super.initState();
    _usageFuture = widget.store.tagUsageSummaries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _displayNameController.dispose();
    _aliasesController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  List<_TagManagerTagRow> _filteredTagRows(
    Map<String, TagUsageSummary> usage,
  ) {
    final token = _searchController.text.trim().toLowerCase();
    final grouped = <String, List<TagItem>>{};
    for (final tag in widget.store.allTagItems) {
      (grouped[_tagDedupeKey(tag)] ??= <TagItem>[]).add(tag);
    }
    final rows = [
      for (final items in grouped.values)
        _TagManagerTagRow.fromItems(items, usage),
    ];
    rows.sort((a, b) {
      final group = (a.tag.groupId ?? '').compareTo(b.tag.groupId ?? '');
      if (group != 0) {
        return group;
      }
      final parent = (a.tag.parentId ?? '').compareTo(b.tag.parentId ?? '');
      if (parent != 0) {
        return parent;
      }
      final order = a.tag.sortOrder.compareTo(b.tag.sortOrder);
      if (order != 0) {
        return order;
      }
      return _tagLabel(a.tag).compareTo(_tagLabel(b.tag));
    });
    if (token.isEmpty) {
      return rows;
    }
    return rows.where((row) => row.matches(token)).toList();
  }

  String _tagDedupeKey(TagItem tag) {
    return tagManagerDedupeKeyForTesting(tag);
  }

  _TagManagerTagRow _rowFor(TagItem tag, Map<String, TagUsageSummary> usage) {
    return _TagManagerTagRow.fromItems(
      [
        for (final item in widget.store.allTagItems)
          if (_tagDedupeKey(item) == _tagDedupeKey(tag)) item,
      ],
      usage,
    );
  }

  TagItem? get _selectedTag {
    final id = _selectedTagId;
    if (id == null) {
      return null;
    }
    return widget.store.tagsById[id];
  }

  String _tagLabel(TagItem tag) => tag.displayName ?? tag.name;

  String _groupLabel(String? groupId) {
    TagGroup? group;
    for (final candidate in widget.store.tagGroups) {
      if (candidate.id == groupId) {
        group = candidate;
        break;
      }
    }
    return group?.displayName ?? group?.name ?? groupId ?? '未分组';
  }

  void _selectTag(TagItem tag) {
    setState(() {
      _selectedTagId = tag.id;
      _editingGroupId = tag.groupId ?? 'manual';
      _editingHidden = tag.isHidden;
      _editingFavorite = tag.isFavorite;
      _displayNameController.text = tag.displayName ?? tag.name;
      _aliasesController.text = tag.aliases.join(', ');
      _sortOrderController.text = tag.sortOrder.toString();
    });
  }

  Future<void> _refreshUsage() async {
    setState(() => _usageFuture = widget.store.tagUsageSummaries());
  }

  Future<void> _createTag() async {
    final result = await showDialog<_CreateTagResult>(
      context: context,
      builder: (context) => _CreateTagDialog(groups: widget.store.tagGroups),
    );
    if (result == null) {
      return;
    }
    try {
      final tag = await widget.store.createManualTag(
        name: result.name,
        groupId: result.groupId,
        displayName: result.displayName,
      );
      if (!mounted) {
        return;
      }
      _selectTag(tag);
      await _refreshUsage();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建标签失败：$error')));
      }
    }
  }

  Future<void> _saveSelectedTag() async {
    final tag = _selectedTag;
    if (tag == null) {
      return;
    }
    final sortOrder =
        int.tryParse(_sortOrderController.text.trim()) ?? tag.sortOrder;
    await widget.store.updateTagDetails(
      tag,
      displayName: TagRules.normalizeTag(_displayNameController.text),
      aliases: _aliasesController.text.split(RegExp(r'[,，\n]')),
      groupId: _editingGroupId,
      isHidden: _editingHidden,
      isFavorite: _editingFavorite,
      sortOrder: sortOrder,
    );
    if (!mounted) {
      return;
    }
    setState(() {});
    await _refreshUsage();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('标签已保存')));
  }

  Future<void> _batchAdd(TagItem tag) async {
    if (tag.source != TagSource.manual) {
      _showManualOnlyNotice('批量添加');
      return;
    }
    final confirmed = await _confirmBatch(
      title: '批量添加标签',
      message:
          '将给当前筛选结果中的 ${widget.currentResults.length} 个视频添加 manual 标签“${_tagLabel(tag)}”。',
      action: '添加',
    );
    if (confirmed != true) {
      return;
    }
    final count =
        await widget.store.batchAddManualTag(tag, widget.currentResults);
    if (!mounted) {
      return;
    }
    await _refreshUsage();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已添加到 $count 个视频')));
  }

  Future<void> _batchRemove(TagItem tag) async {
    if (tag.source != TagSource.manual) {
      _showManualOnlyNotice('批量移除');
      return;
    }
    final confirmed = await _confirmBatch(
      title: '批量移除标签',
      message:
          '将只从当前筛选结果中的 ${widget.currentResults.length} 个视频移除 manual 标签“${_tagLabel(tag)}”。folder 来源关系不会被移除。',
      action: '移除',
    );
    if (confirmed != true) {
      return;
    }
    final count =
        await widget.store.batchRemoveManualTag(tag, widget.currentResults);
    if (!mounted) {
      return;
    }
    await _refreshUsage();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已从 $count 个视频移除 manual 标签')));
  }

  Future<bool?> _confirmBatch({
    required String title,
    required String message,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: widget.currentResults.isEmpty
                ? null
                : () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  void _showManualOnlyNotice(String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              '$action 只支持 manual 标签。folder 来源标签由路径派生，不能作为普通 manual 批量操作对象。')),
    );
  }

  Future<void> _showDeleteBlocked(TagItem tag) async {
    final refs = await widget.store.countTagReferences(tag);
    if (!mounted) {
      return;
    }
    final isFolder = tag.source == TagSource.folder;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除标签尚未启用'),
        content: Text(
          isFolder
              ? '“${_tagLabel(tag)}” 是路径派生 folder 标签，当前有 $refs 条 video_tags 引用。第一阶段不允许硬删除 folder 来源标签。'
              : '“${_tagLabel(tag)}” 当前有 $refs 条 video_tags 引用。第一阶段只做引用检查和确认入口，暂不执行删除。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMergeBlocked(TagItem tag) async {
    final refs = await widget.store.countTagReferences(tag);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('合并标签尚未启用'),
        content: Text(
            '“${_tagLabel(tag)}” 当前有 $refs 条 video_tags 引用。合并需要迁移引用并处理 folder/manual 来源边界，第一阶段先保留入口。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layoutSize =
        LayoutBreakpoints.fromWidth(MediaQuery.sizeOf(context).width);
    final compact = layoutSize == LayoutSize.compact;
    return Scaffold(
      backgroundColor: appBackground,
      appBar: AppBar(
        title: const Text('标签管理'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refreshUsage,
            icon: const Icon(Icons.refresh),
          ),
          if (compact)
            IconButton(
              tooltip: '新建标签',
              onPressed: _createTag,
              icon: const Icon(Icons.add),
            )
          else
            FilledButton.icon(
              onPressed: _createTag,
              icon: const Icon(Icons.add),
              label: const Text('新建标签'),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: FutureBuilder<Map<String, TagUsageSummary>>(
        future: _usageFuture,
        builder: (context, snapshot) {
          final usage = snapshot.data ?? const <String, TagUsageSummary>{};
          final rows = _filteredTagRows(usage);
          return Flex(
            direction: compact ? Axis.vertical : Axis.horizontal,
            children: [
              SizedBox(
                width: compact
                    ? double.infinity
                    : (layoutSize == LayoutSize.medium ? 316 : 360),
                height: compact ? 320 : null,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: appSurface,
                    border: Border(right: BorderSide(color: appBorder)),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SearchBar(
                          controller: _searchController,
                          leading: const Icon(Icons.search),
                          hintText: '搜索标签 / 别名',
                          onChanged: (_) => setState(() {}),
                          elevation: const WidgetStatePropertyAll(0),
                        ),
                      ),
                      _TagGroupSummary(groups: widget.store.tagGroups),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final row = rows[index];
                            final tag = row.tag;
                            return ListTile(
                              selected: tag.id == _selectedTagId,
                              leading: Icon(tag.source == TagSource.folder
                                  ? Icons.folder_outlined
                                  : Icons.sell_outlined),
                              title: Text(row.displayLabel,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle:
                                  Text(row.subtitle(_groupLabel(tag.groupId))),
                              trailing: tag.isHidden
                                  ? const Icon(Icons.visibility_off_outlined,
                                      size: 18)
                                  : tag.isFavorite
                                      ? const Icon(Icons.star, size: 18)
                                      : null,
                              onTap: () => _selectTag(tag),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _selectedTag == null
                    ? const Center(child: Text('选择一个标签查看和维护详情'))
                    : _TagManagerDetail(
                        tag: _selectedTag!,
                        usage: _rowFor(_selectedTag!, usage).usage,
                        groups: widget.store.tagGroups,
                        currentResultCount: widget.currentResults.length,
                        displayNameController: _displayNameController,
                        aliasesController: _aliasesController,
                        sortOrderController: _sortOrderController,
                        groupId: _editingGroupId,
                        isHidden: _editingHidden,
                        isFavorite: _editingFavorite,
                        onGroupChanged: (value) =>
                            setState(() => _editingGroupId = value),
                        onHiddenChanged: (value) =>
                            setState(() => _editingHidden = value),
                        onFavoriteChanged: (value) =>
                            setState(() => _editingFavorite = value),
                        onSave: _saveSelectedTag,
                        onBatchAdd: () => _batchAdd(_selectedTag!),
                        onBatchRemove: () => _batchRemove(_selectedTag!),
                        onDelete: () => _showDeleteBlocked(_selectedTag!),
                        onMerge: () => _showMergeBlocked(_selectedTag!),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TagManagerTagRow {
  const _TagManagerTagRow({
    required this.tag,
    required this.usage,
    required this.duplicateCount,
    required this.caseVariants,
  });

  final TagItem tag;
  final TagUsageSummary usage;
  final int duplicateCount;
  final List<String> caseVariants;

  factory _TagManagerTagRow.fromItems(
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
    return _TagManagerTagRow(
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

@visibleForTesting
String tagManagerDedupeKeyForTesting(TagItem tag) {
  final source = tag.source.name;
  final group = tag.groupId ?? 'manual';
  final parent = (tag.parentId ?? '').trim().toLowerCase();
  final name = tag.name.trim().toLowerCase();
  return '$source|$group|$parent|$name';
}

@visibleForTesting
List<String> tagManagerDisplayRowsForTesting({
  required Iterable<TagItem> tags,
  required Map<String, TagUsageSummary> usage,
}) {
  final grouped = <String, List<TagItem>>{};
  for (final tag in tags) {
    (grouped[tagManagerDedupeKeyForTesting(tag)] ??= <TagItem>[]).add(tag);
  }
  final rows = [
    for (final items in grouped.values)
      _TagManagerTagRow.fromItems(items, usage),
  ]..sort((a, b) => a.displayLabel.compareTo(b.displayLabel));
  return [
    for (final row in rows)
      '${row.displayLabel}|${row.usage.total}|${row.duplicateCount}',
  ];
}

class _TagManagerDetail extends StatelessWidget {
  const _TagManagerDetail({
    required this.tag,
    required this.usage,
    required this.groups,
    required this.currentResultCount,
    required this.displayNameController,
    required this.aliasesController,
    required this.sortOrderController,
    required this.groupId,
    required this.isHidden,
    required this.isFavorite,
    required this.onGroupChanged,
    required this.onHiddenChanged,
    required this.onFavoriteChanged,
    required this.onSave,
    required this.onBatchAdd,
    required this.onBatchRemove,
    required this.onDelete,
    required this.onMerge,
  });

  final TagItem tag;
  final TagUsageSummary usage;
  final List<TagGroup> groups;
  final int currentResultCount;
  final TextEditingController displayNameController;
  final TextEditingController aliasesController;
  final TextEditingController sortOrderController;
  final String? groupId;
  final bool isHidden;
  final bool isFavorite;
  final ValueChanged<String?> onGroupChanged;
  final ValueChanged<bool> onHiddenChanged;
  final ValueChanged<bool> onFavoriteChanged;
  final VoidCallback onSave;
  final VoidCallback onBatchAdd;
  final VoidCallback onBatchRemove;
  final VoidCallback onDelete;
  final VoidCallback onMerge;

  @override
  Widget build(BuildContext context) {
    final canBatchEdit = tag.source == TagSource.manual;
    final compact =
        LayoutBreakpoints.fromWidth(MediaQuery.sizeOf(context).width) ==
            LayoutSize.compact;
    final groupItems = groups.isEmpty
        ? const <DropdownMenuItem<String>>[
            DropdownMenuItem(value: 'manual', child: Text('手动标签'))
          ]
        : <DropdownMenuItem<String>>[
            for (final group in groups)
              DropdownMenuItem(
                value: group.id,
                child: Text(group.displayName ?? group.name),
              ),
          ];
    return ListView(
      padding:
          EdgeInsets.fromLTRB(compact ? 14 : 24, 20, compact ? 14 : 24, 28),
      children: [
        Text(tag.name,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('ID: ${tag.id}', style: const TextStyle(color: appTextMuted)),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _UsagePill(label: '总使用', value: usage.total),
            _UsagePill(label: 'folder', value: usage.folder),
            _UsagePill(label: 'manual', value: usage.manual),
            _UsagePill(label: 'rule', value: usage.rule),
            _UsagePill(label: 'filename', value: usage.filename),
            _UsagePill(label: 'import', value: usage.imported),
            _UsagePill(label: 'auto', value: usage.auto),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: displayNameController,
          decoration: const InputDecoration(labelText: '显示名称'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: aliasesController,
          minLines: 2,
          maxLines: 4,
          decoration:
              const InputDecoration(labelText: '别名', hintText: '用逗号或换行分隔'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: groupId,
          items: groupItems,
          decoration: const InputDecoration(labelText: '标签组'),
          onChanged: onGroupChanged,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: sortOrderController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '排序值'),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: isFavorite,
          onChanged: onFavoriteChanged,
          title: const Text('收藏标签'),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: isHidden,
          onChanged: onHiddenChanged,
          title: const Text('隐藏标签'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onSave,
          icon: const Icon(Icons.save_outlined),
          label: const Text('保存标签'),
        ),
        const SizedBox(height: 24),
        Text('批量打标签',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('当前筛选结果：$currentResultCount 个视频',
            style: const TextStyle(color: appTextMuted)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed:
                  currentResultCount == 0 || !canBatchEdit ? null : onBatchAdd,
              icon: const Icon(Icons.playlist_add),
              label: const Text('批量添加 manual'),
            ),
            OutlinedButton.icon(
              onPressed: currentResultCount == 0 || !canBatchEdit
                  ? null
                  : onBatchRemove,
              icon: const Icon(Icons.playlist_remove),
              label: const Text('批量移除 manual'),
            ),
          ],
        ),
        if (!canBatchEdit) ...[
          const SizedBox(height: 8),
          const Text(
            '当前标签不是 manual 来源。批量添加/移除只对 manual 标签开放，folder 标签由路径派生维护。',
            style: TextStyle(color: appTextMuted),
          ),
        ],
        const SizedBox(height: 24),
        Text('高风险操作',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: onMerge,
              icon: const Icon(Icons.call_merge),
              label: const Text('合并'),
            ),
            OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除'),
            ),
          ],
        ),
      ],
    );
  }
}

class _TagGroupSummary extends StatelessWidget {
  const _TagGroupSummary({required this.groups});

  final List<TagGroup> groups;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text('暂无标签组', style: TextStyle(color: appTextMuted)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
              for (final group in groups)
                Tooltip(
                  message: '${group.id} · sort ${group.sortOrder}',
                  child: Chip(
                    label: Text(group.displayName ?? group.name),
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

class _UsagePill extends StatelessWidget {
  const _UsagePill({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label $value'),
      backgroundColor: const Color(0xffeef4f3),
      side: const BorderSide(color: appBorder),
    );
  }
}

/** 新建 manual 标签的本地输入校验；空白名称必须留在弹窗内提示。 */
@visibleForTesting
String? manualTagNameValidationError(String value) =>
    TagRules.normalizeTag(value).isEmpty ? '请输入标签名' : null;

/**
 * 新建标签弹窗的 focused widget 测试宿主。
 *
 * 宿主复用真实弹窗，确保空名称不会关闭对话框或泄露 Store 的英文参数异常。
 */
@visibleForTesting
Widget createTagDialogSmokeHarness() {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => FilledButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const _CreateTagDialog(groups: <TagGroup>[]),
          ),
          child: const Text('打开新建标签'),
        ),
      ),
    ),
  );
}

class _CreateTagDialog extends StatefulWidget {
  const _CreateTagDialog({required this.groups});

  final List<TagGroup> groups;

  @override
  State<_CreateTagDialog> createState() => _CreateTagDialogState();
}

class _CreateTagDialogState extends State<_CreateTagDialog> {
  final _nameController = TextEditingController();
  final _displayNameController = TextEditingController();
  String? _nameError;
  late String _groupId = widget.groups.any((group) => group.id == 'manual')
      ? 'manual'
      : (widget.groups.isEmpty ? 'manual' : widget.groups.first.id);

  @override
  void dispose() {
    _nameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  /** 校验后提交；无效输入只显示中文字段错误，不关闭弹窗或触发 Store 异常。 */
  void _submit() {
    final error = manualTagNameValidationError(_nameController.text);
    if (error != null) {
      setState(() => _nameError = error);
      return;
    }
    Navigator.of(context).pop(
      _CreateTagResult(
        name: TagRules.normalizeTag(_nameController.text),
        displayName: TagRules.normalizeTag(_displayNameController.text),
        groupId: _groupId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建标签'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_nameError != null) {
                  setState(() => _nameError = null);
                }
              },
              decoration: InputDecoration(
                labelText: '标签名',
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _displayNameController,
              decoration: const InputDecoration(labelText: '显示名称（可选）'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _groupId,
              items: [
                for (final group in widget.groups)
                  DropdownMenuItem(
                    value: group.id,
                    child: Text(group.displayName ?? group.name),
                  ),
                if (widget.groups.isEmpty)
                  const DropdownMenuItem(value: 'manual', child: Text('手动标签')),
              ],
              decoration: const InputDecoration(labelText: '标签组'),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _groupId = value);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('创建'),
        ),
      ],
    );
  }
}

class _CreateTagResult {
  const _CreateTagResult({
    required this.name,
    required this.displayName,
    required this.groupId,
  });

  final String name;
  final String displayName;
  final String groupId;
}
