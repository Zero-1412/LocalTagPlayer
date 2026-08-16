import 'package:flutter/material.dart';

import '../../core/layout_size.dart';
import '../../core/tag_rules.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../services/library/library_application_facade.dart';
import '../../widgets/app_theme_tokens.dart';
import '../../widgets/maintenance_feedback.dart';

import 'tag_manager_blocked_dialog.dart';
import 'tag_manager_create_dialog.dart';
import 'tag_manager_detail.dart';
import 'tag_manager_detail_sections.dart';
import 'tag_manager_list_widgets.dart';
import 'tag_manager_workspace_app_bar.dart';

export 'tag_manager_blocked_dialog.dart'
    show tagManagerBlockedOperationSmokeHarness;
export 'tag_manager_create_dialog.dart'
    show createTagDialogSmokeHarness, manualTagNameValidationError;
export 'tag_manager_detail.dart' show tagManagerDetailSmokeHarness;
export 'tag_manager_detail_sections.dart'
    show tagManagerGroupSummarySmokeHarness;
export 'tag_manager_list_widgets.dart'
    show
        tagManagerDedupeKeyForTesting,
        tagManagerDisplayRowsForTesting,
        tagManagerSearchSmokeHarness;
export 'tag_manager_workspace_app_bar.dart';

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
  /** 左侧列表当前选中的标签组；null 表示显示全部分组。 */
  String? _selectedGroupId;
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

  List<TagManagerTagRow> _filteredTagRows(
    Map<String, TagUsageSummary> usage,
  ) {
    final token = _searchController.text.trim().toLowerCase();
    final grouped = <String, List<TagItem>>{};
    for (final tag in widget.store.allTagItems) {
      (grouped[tagManagerDedupeKey(tag)] ??= <TagItem>[]).add(tag);
    }
    final rows = [
      for (final items in grouped.values)
        TagManagerTagRow.fromItems(items, usage),
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
    return rows.where((row) {
      // 分组 chip 是显示层过滤器，不修改 TagItem、FilterQuery 或媒体库当前筛选。
      if (_selectedGroupId != null && row.tag.groupId != _selectedGroupId) {
        return false;
      }
      return token.isEmpty || row.matches(token);
    }).toList();
  }

  TagManagerTagRow _rowFor(TagItem tag, Map<String, TagUsageSummary> usage) {
    return TagManagerTagRow.fromItems(
      [
        for (final item in widget.store.allTagItems)
          if (tagManagerDedupeKey(item) == tagManagerDedupeKey(tag)) item,
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
    final result = await showMaintenanceDialog<CreateTagResult>(
      context: context,
      builder: (context) => CreateTagDialog(groups: widget.store.tagGroups),
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
        showMaintenanceSnackBar(
          context,
          message: '创建标签失败：$error',
        );
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
    showMaintenanceSnackBar(context, message: '标签已保存');
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
    showMaintenanceSnackBar(context, message: '已添加到 $count 个视频');
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
    showMaintenanceSnackBar(
      context,
      message: '已从 $count 个视频移除 manual 标签',
    );
  }

  Future<bool?> _confirmBatch({
    required String title,
    required String message,
    required String action,
  }) {
    return showMaintenanceDialog<bool>(
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
    showMaintenanceSnackBar(
      context,
      message: '$action 只支持 manual 标签。folder 来源标签由路径派生，不能作为普通 manual 批量操作对象。',
    );
  }

  Future<void> _showDeleteBlocked(TagItem tag) async {
    final refs = await widget.store.countTagReferences(tag);
    if (!mounted) {
      return;
    }
    final isFolder = tag.source == TagSource.folder;
    await _showBlockedTagOperation(
      icon: Icons.delete_outline_rounded,
      title: '暂不能删除此标签',
      message: isFolder
          ? '“${_tagLabel(tag)}” 是路径派生 folder 标签，当前有 $refs 条 video_tags 引用。folder 标签只能由目录结构维护，本次未执行删除。'
          : '“${_tagLabel(tag)}” 当前有 $refs 条 video_tags 引用。当前版本只检查影响范围，本次未删除标签或任何视频关联。',
    );
  }

  Future<void> _showMergeBlocked(TagItem tag) async {
    final refs = await widget.store.countTagReferences(tag);
    if (!mounted) {
      return;
    }
    await _showBlockedTagOperation(
      icon: Icons.call_merge_rounded,
      title: '暂不能合并此标签',
      message:
          '“${_tagLabel(tag)}” 当前有 $refs 条 video_tags 引用。合并需要迁移引用并处理 folder/manual 来源边界，本次未修改标签或视频关联。',
    );
  }

  /**
   * 展示只读的高风险影响说明。
   *
   * 当前阶段不会执行合并或删除，因此默认焦点落在安全返回动作；大文字下内容可滚动，
   * 避免用户把“检查影响”误解为已经提交不可逆操作。
   */
  Future<void> _showBlockedTagOperation({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return showMaintenanceDialog<void>(
      context: context,
      builder: (dialogContext) => BlockedTagOperationDialog(
        icon: icon,
        title: title,
        message: message,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layoutSize =
        LayoutBreakpoints.fromWidth(MediaQuery.sizeOf(context).width);
    final compact = layoutSize == LayoutSize.compact;
    return Theme(
      data: maintenanceWorkspaceTheme(Theme.of(context)),
      child: _buildWorkspace(layoutSize: layoutSize, compact: compact),
    );
  }

  /** 构建标签维护工作区；主题包装与页面内容分离，保持布局 diff 集中可审查。 */
  Widget _buildWorkspace({
    required LayoutSize layoutSize,
    required bool compact,
  }) {
    return Scaffold(
      backgroundColor: libraryBackground,
      appBar: TagManagerWorkspaceAppBar(
        compact: compact,
        onRefresh: _refreshUsage,
        onCreate: _createTag,
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 20,
          compact ? 10 : 16,
          compact ? 12 : 20,
          compact ? 12 : 20,
        ),
        child: FutureBuilder<Map<String, TagUsageSummary>>(
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
                  height: compact ? 304 : null,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: librarySurface,
                      borderRadius:
                          BorderRadius.all(Radius.circular(AppRadius.panel)),
                      border: Border.fromBorderSide(
                        BorderSide(color: libraryBorder),
                      ),
                    ),
                    child: Column(
                      children: [
                        TagManagerListHeader(visibleCount: rows.length),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                          child: TagManagerSearchField(
                            controller: _searchController,
                            onChanged: () => setState(() {}),
                          ),
                        ),
                        TagGroupSummary(
                          groups: widget.store.tagGroups,
                          selectedGroupId: _selectedGroupId,
                          onSelected: (groupId) {
                            setState(() {
                              _selectedGroupId = groupId;
                              // 当前详情可能已不在左侧结果中，清空可避免“筛选 A、编辑 B”的错觉。
                              if (groupId != null &&
                                  _selectedTag?.groupId != groupId) {
                                _selectedTagId = null;
                              }
                            });
                          },
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(top: 6, bottom: 8),
                            itemCount: rows.length,
                            itemBuilder: (context, index) {
                              final row = rows[index];
                              final tag = row.tag;
                              return TagManagerListItem(
                                row: row,
                                groupLabel: _groupLabel(tag.groupId),
                                selected: tag.id == _selectedTagId,
                                onTap: () => _selectTag(tag),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: compact ? 0 : 16, height: compact ? 16 : 0),
                Expanded(
                  child: _selectedTag == null
                      ? const TagManagerEmptyDetail()
                      : TagManagerInspectorSurface(
                          child: TagManagerDetail(
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
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
