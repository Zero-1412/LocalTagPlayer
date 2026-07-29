import 'package:flutter/material.dart';

import '../../core/layout_size.dart';
import '../../models/platform_models.dart';
import '../../widgets/app_theme_tokens.dart';
import 'tag_manager_detail_sections.dart';

// ignore_for_file: slash_for_doc_comments

class TagManagerDetail extends StatelessWidget {
  const TagManagerDetail({
    super.key,
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
            DropdownMenuItem(
              key: ValueKey('tagManager.detail.group.manual'),
              value: 'manual',
              child: Text('手动标签'),
            )
          ]
        : <DropdownMenuItem<String>>[
            for (final group in groups)
              DropdownMenuItem(
                key: ValueKey('tagManager.detail.group.${group.id}'),
                value: group.id,
                child: Text(group.displayName ?? group.name),
              ),
          ];
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          compact ? 14 : 24,
          20,
          compact ? 14 : 24,
          28,
        ),
        children: [
          Text(tag.name,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('ID: ${tag.id}',
              style: const TextStyle(color: libraryTextMuted)),
          const SizedBox(height: 18),
          TagManagerSection(
            title: '使用情况',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                UsagePill(label: '总使用', value: usage.total),
                UsagePill(label: 'folder', value: usage.folder),
                UsagePill(label: 'manual', value: usage.manual),
                UsagePill(label: 'rule', value: usage.rule),
                UsagePill(label: 'filename', value: usage.filename),
                UsagePill(label: 'import', value: usage.imported),
                UsagePill(label: 'auto', value: usage.auto),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TagManagerSection(
            title: '标签属性',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: TextField(
                    key: const ValueKey('tagManager.detail.displayName'),
                    controller: displayNameController,
                    decoration: const InputDecoration(labelText: '显示名称'),
                  ),
                ),
                const SizedBox(height: 12),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: TextField(
                    key: const ValueKey('tagManager.detail.aliases'),
                    controller: aliasesController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '别名',
                      hintText: '用逗号或换行分隔',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(3),
                  child: Builder(
                    builder: (fieldContext) => DropdownButtonFormField<String>(
                      key: const ValueKey('tagManager.detail.group'),
                      initialValue: groupId,
                      isExpanded: true,
                      menuMaxHeight: 320,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      items: groupItems,
                      decoration: const InputDecoration(labelText: '标签组'),
                      // 大文字下字段可能贴近窗口底边；在下拉路由布局前把锚点移入
                      // 可视区中段，避免最后一个选项落到主窗口捕获边界之外。
                      onTap: () => Scrollable.ensureVisible(
                        fieldContext,
                        alignment: 0.46,
                        duration: Duration.zero,
                      ),
                      onChanged: onGroupChanged,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(4),
                  child: TextField(
                    key: const ValueKey('tagManager.detail.sortOrder'),
                    controller: sortOrderController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '排序值'),
                  ),
                ),
                const SizedBox(height: 8),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(5),
                  child: SwitchListTile(
                    key: const ValueKey('tagManager.detail.favorite'),
                    value: isFavorite,
                    onChanged: onFavoriteChanged,
                    title: const Text('收藏标签'),
                    subtitle: const Text('在标签发现入口优先展示'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(6),
                  child: SwitchListTile(
                    key: const ValueKey('tagManager.detail.hidden'),
                    value: isHidden,
                    onChanged: onHiddenChanged,
                    title: const Text('隐藏标签'),
                    subtitle: const Text('从常规发现列表隐藏，不删除数据'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(7),
                    child: FilledButton.icon(
                      key: const ValueKey('tagManager.detail.save'),
                      onPressed: onSave,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('保存标签'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TagManagerSection(
            title: '批量打标签',
            subtitle: '当前筛选结果：$currentResultCount 个视频',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(8),
                      child: FilledButton.icon(
                        key: const ValueKey('tagManager.detail.batchAdd'),
                        onPressed: currentResultCount == 0 || !canBatchEdit
                            ? null
                            : onBatchAdd,
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('批量添加 manual'),
                      ),
                    ),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(9),
                      child: OutlinedButton.icon(
                        key: const ValueKey('tagManager.detail.batchRemove'),
                        onPressed: currentResultCount == 0 || !canBatchEdit
                            ? null
                            : onBatchRemove,
                        icon: const Icon(Icons.playlist_remove),
                        label: const Text('批量移除 manual'),
                      ),
                    ),
                  ],
                ),
                if (!canBatchEdit) ...[
                  const SizedBox(height: 10),
                  const Text(
                    '当前标签不是 manual 来源。批量添加/移除只对 manual 标签开放，folder 标签由路径派生维护。',
                    style: TextStyle(color: libraryTextMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          TagManagerSection(
            title: '高风险操作',
            subtitle: '入口只检查引用并说明影响；当前版本不会执行合并或删除。',
            danger: true,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FocusTraversalOrder(
                  order: const NumericFocusOrder(10),
                  child: OutlinedButton.icon(
                    key: const ValueKey('tagManager.detail.merge'),
                    onPressed: onMerge,
                    icon: const Icon(Icons.call_merge),
                    label: const Text('检查合并影响'),
                  ),
                ),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(11),
                  child: OutlinedButton.icon(
                    key: const ValueKey('tagManager.detail.delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('检查删除影响'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/**
 * 构建标签详情的 focused test 容器。
 *
 * 容器只承载本地控制器、缩放和焦点，不连接 Store，也不会保存、批量打标、合并或删除。
 */
@visibleForTesting
Widget tagManagerDetailSmokeHarness({
  TextScaler textScaler = TextScaler.noScaling,
  VoidCallback? onDelete,
}) {
  return TagManagerDetailSmokeHarness(
    textScaler: textScaler,
    onDelete: onDelete,
  );
}

/** 标签详情测试宿主，负责释放真实输入控制器。 */
class TagManagerDetailSmokeHarness extends StatefulWidget {
  const TagManagerDetailSmokeHarness({
    super.key,
    required this.textScaler,
    this.onDelete,
  });

  /** 待验证的系统文字缩放。 */
  final TextScaler textScaler;

  /** 只记录危险入口是否命中，不执行标签操作。 */
  final VoidCallback? onDelete;

  @override
  State<TagManagerDetailSmokeHarness> createState() =>
      TagManagerDetailSmokeHarnessState();
}

class TagManagerDetailSmokeHarnessState
    extends State<TagManagerDetailSmokeHarness> {
  final _displayNameController = TextEditingController(text: '示例标签');
  final _aliasesController = TextEditingController(text: '别名一, 别名二');
  final _sortOrderController = TextEditingController(text: '10');
  String _groupId = 'favorite';
  bool _hidden = false;
  bool _favorite = true;

  @override
  void dispose() {
    _displayNameController.dispose();
    _aliasesController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const tag = TagItem(
      id: 'manual:example',
      name: '示例标签',
      source: TagSource.manual,
      groupId: 'manual',
    );
    const groups = <TagGroup>[
      TagGroup(
        id: 'manual',
        name: 'manual',
        displayName: '手动标签',
        items: <TagItem>[],
      ),
      TagGroup(
        id: 'favorite',
        name: 'favorite',
        displayName: '收藏分组',
        items: <TagItem>[],
      ),
      TagGroup(
        id: 'archive',
        name: 'archive',
        displayName: '归档分组',
        items: <TagItem>[],
      ),
    ];
    return MaterialApp(
      theme: maintenanceWorkspaceTheme(ThemeData(useMaterial3: true)),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(960, 720),
          textScaler: widget.textScaler,
        ),
        child: Scaffold(
          body: TagManagerDetail(
            tag: tag,
            usage: const TagUsageSummary(total: 12, manual: 12),
            groups: groups,
            currentResultCount: 24,
            displayNameController: _displayNameController,
            aliasesController: _aliasesController,
            sortOrderController: _sortOrderController,
            groupId: _groupId,
            isHidden: _hidden,
            isFavorite: _favorite,
            onGroupChanged: (value) {
              if (value != null) {
                setState(() => _groupId = value);
              }
            },
            onHiddenChanged: (value) => setState(() => _hidden = value),
            onFavoriteChanged: (value) => setState(() => _favorite = value),
            onSave: () {},
            onBatchAdd: () {},
            onBatchRemove: () {},
            onDelete: widget.onDelete ?? () {},
            onMerge: () {},
          ),
        ),
      ),
    );
  }
}
