import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/tag_rules.dart';
import '../app_theme_tokens.dart';
import 'library_tag_editor_sections.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

/**
 * 手动标签编辑弹窗。
 *
 * folder 等锁定来源仅供查看；保存结果只表达当前作用域内可维护的 manual 标签。
 */
class TagEditorDialog extends StatefulWidget {
  const TagEditorDialog({
    super.key,
    required this.title,
    required this.initialManualTags,
    required this.existingTags,
    this.lockedTags = const <String>{},
    this.helperText,
    this.recentTags = const <String>[],
    this.favoriteTags = const <String>{},
    this.mostUsedTags = const <String>[],
  });

  final String title;
  /** 仅包含当前视频已关联的 manual 标签；不得混入 folder 兼容字段。 */
  final Set<String> initialManualTags;
  final Set<String> existingTags;

  /** 由 folder 等外部来源维护、在当前弹窗中只能查看不能删除的标签。 */
  final Set<String> lockedTags;

  /** 当前编辑范围和来源边界说明。 */
  final String? helperText;

  /** 当前会话最近使用的 manual 标签，顺序由调用方维护。 */
  final List<String> recentTags;

  /** 用户在标签中心标记为收藏的 manual 标签。 */
  final Set<String> favoriteTags;

  /** 按当前媒体库实际关联次数降序排列的 manual 标签名称。 */
  final List<String> mostUsedTags;

  @override
  State<TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<TagEditorDialog> {
  late final Set<String> _tags = _normalizeTags(widget.initialManualTags);
  final _controller = TextEditingController();
  String _query = '';
  bool _hasPendingImeSubmission = false;
  var _imeCompositionEpoch = 0;
  /** 当前选择是否与打开弹窗时不同；只用于提示未保存状态，不提前写入标签数据。 */
  bool _dirty = false;

  /** 统一保存入口，让按钮和 Ctrl+Enter 走同一条结果归一化链路。 */
  void _save() {
    _addTag(_controller.text);
    Navigator.of(context).pop(_tags);
  }

  /** 关闭弹窗但不提交修改；Escape 与取消按钮共用此入口。 */
  void _cancel() => Navigator.of(context).pop();
  @override
  void initState() {
    super.initState();
    _controller.addListener(_trackImeComposition);
  }

  @override
  void dispose() {
    _controller.removeListener(_trackImeComposition);
    _controller.dispose();
    super.dispose();
  }

  void _addTag(String raw) {
    final tag = TagRules.normalizeTag(raw);
    if (tag.isEmpty) {
      return;
    }
    setState(() {
      _dirty = _addNormalizedTag(tag) || _dirty;
      _controller.clear();
      _query = '';
    });
  }

  /** 添加归一化标签并返回当前选择是否真实发生变化。 */
  bool _addNormalizedTag(String tag) {
    if (!_tags.any((existing) => TagRules.sameTag(existing, tag))) {
      _tags.add(tag);
      return true;
    }
    return false;
  }

  /** 清除当前搜索词并恢复完整候选，不影响已经选择的标签。 */
  void _clearQuery() {
    _controller.clear();
    setState(() => _query = '');
  }

  /**
   * 记录输入法组合态刚完成的帧，但不在键盘事件层处理 Enter。
   *
   * Windows 中文输入法用 Enter 选择候选；拦截原始按键会让输入法失去提交机会。
   * 输入法的候选确认可能先结束组合态、再回调 [onSubmitted]，因此一旦观察到组合文本，
   * 就暂时让输入法接管 Enter。若同一帧未收到提交回调，则在下一帧释放普通 Enter。
   */
  void _trackImeComposition() {
    final composing = _controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      _hasPendingImeSubmission = true;
      return;
    }
    if (!_hasPendingImeSubmission) return;

    final epoch = ++_imeCompositionEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _imeCompositionEpoch != epoch) return;
      _hasPendingImeSubmission = false;
    });
  }

  /** 组合候选确认触发的提交只保留文本；下一次普通 Enter 才添加标签。 */
  void _handleSubmitted(String value) {
    if (_hasPendingImeSubmission) {
      _hasPendingImeSubmission = false;
      return;
    }
    _addTag(value);
  }

  Set<String> _normalizeTags(Iterable<String> tags) {
    final normalized = <String>{};
    for (final raw in tags) {
      final tag = TagRules.normalizeTag(raw);
      if (tag.isEmpty ||
          normalized.any((existing) => TagRules.sameTag(existing, tag))) {
        continue;
      }
      normalized.add(tag);
    }
    return normalized;
  }

  /** 找出同时来自目录和用户维护数据的同名标签。 */
  List<String> get _sameNameSourceTags => [
        for (final tag in _tags)
          if (widget.lockedTags
              .any((lockedTag) => TagRules.sameTag(lockedTag, tag)))
            tag,
      ]..sort();

  /** 返回未选中且匹配当前搜索词的候选，保持大小写不敏感。 */
  List<String> _availableTags(
    Iterable<String> source, {
    bool sort = true,
    Iterable<String> prioritizedTags = const <String>[],
  }) {
    final query = _query.trim().toLowerCase();
    final result = _normalizeTags(source.where(
      (tag) =>
          !_tags.any((selected) => TagRules.sameTag(selected, tag)) &&
          (query.isEmpty || tag.toLowerCase().contains(query)),
    )).toList();
    if (sort) {
      final priority = <String, int>{
        for (final (index, tag) in prioritizedTags.indexed)
          TagRules.normalizeTag(tag).toLowerCase(): index,
      };
      result.sort((left, right) {
        final leftPriority = priority[left.toLowerCase()];
        final rightPriority = priority[right.toLowerCase()];
        if (leftPriority != null || rightPriority != null) {
          if (leftPriority == null) return 1;
          if (rightPriority == null) return -1;
          final compared = leftPriority.compareTo(rightPriority);
          if (compared != 0) return compared;
        }
        return left.toLowerCase().compareTo(right.toLowerCase());
      });
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final sameNameSourceTags = _sameNameSourceTags;
    final suggestions = _availableTags(
      widget.existingTags,
      prioritizedTags: widget.mostUsedTags,
    );
    final recent = _availableTags(widget.recentTags, sort: false);
    final favorites = _availableTags(widget.favoriteTags);
    final theme = maintenanceWorkspaceTheme(Theme.of(context));
    return Theme(
      data: theme,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
          const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        },
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: AlertDialog(
            key: const ValueKey('tagEditor.dialog'),
            insetPadding: const EdgeInsets.all(24),
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: appAccentViolet.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: const SizedBox.square(
                    dimension: 40,
                    child: Icon(
                      Icons.sell_outlined,
                      color: libraryAccent,
                      size: 21,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '管理当前视频关联的标签',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: libraryTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: math.min(560, MediaQuery.sizeOf(context).width - 96),
              height: math.min(580, MediaQuery.sizeOf(context).height * 0.72),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.helperText != null) ...[
                    TagEditorSectionCard(
                      title: '编辑范围',
                      icon: Icons.info_outline_rounded,
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        widget.helperText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: libraryTextMuted,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: '搜索或新建独立 manual 标签',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              key: const ValueKey('tagEditor.clearSearch'),
                              tooltip: '清除搜索',
                              onPressed: _clearQuery,
                              icon: const Icon(Icons.close_rounded),
                            ),
                      helperText: 'Tab 浏览候选，Enter 添加，Ctrl+Enter 保存，Esc 取消',
                    ),
                    // 搜索链路继续只使用当前 TextField/controller；清除不创建第二输入状态。
                    onChanged: (value) => setState(() => _query = value),
                    onSubmitted: _handleSubmitted,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TagEditorSectionCard(
                      title: '当前与可用标签',
                      icon: Icons.local_offer_outlined,
                      expandChild: true,
                      trailing: Text(
                        '${_tags.length} 个已选',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: libraryAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final tag
                                    in (widget.lockedTags.toList()..sort()))
                                  Tooltip(
                                    message: '文件夹来源标签，只能通过目录结构修改',
                                    child: InputChip(
                                      avatar: const Icon(
                                        Icons.lock_outline_rounded,
                                        size: 15,
                                      ),
                                      label: Text(tag),
                                      onDeleted: null,
                                      deleteButtonTooltipMessage:
                                          '从当前视频移除 $tag',
                                    ),
                                  ),
                                for (final tag in (_tags.toList()..sort()))
                                  Tooltip(
                                    message: '移除手动标签',
                                    child: InputChip(
                                      label: Text(tag),
                                      onDeleted: () => setState(() {
                                        _dirty = _tags.remove(tag) || _dirty;
                                      }),
                                      deleteButtonTooltipMessage:
                                          '从当前视频移除 $tag',
                                    ),
                                  ),
                              ],
                            ),
                            if (sameNameSourceTags.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              TagEditorSameNameSourceNotice(
                                tags: sameNameSourceTags,
                              ),
                            ],
                            if (_tags.isEmpty)
                              const Text(
                                '尚未选择标签，可从下方候选添加或直接输入新标签。',
                                style: TextStyle(
                                  color: libraryTextMuted,
                                  height: 1.4,
                                ),
                              ),
                            TagSuggestionSection(
                              title: '最近使用',
                              tags: recent.take(8).toList(),
                              icon: Icons.history_rounded,
                              onSelected: (tag) => setState(() {
                                _dirty = _addNormalizedTag(tag) || _dirty;
                              }),
                            ),
                            TagSuggestionSection(
                              title: '收藏标签',
                              tags: favorites.take(8).toList(),
                              icon: Icons.star_rounded,
                              onSelected: (tag) => setState(() {
                                _dirty = _addNormalizedTag(tag) || _dirty;
                              }),
                            ),
                            TagSuggestionSection(
                              title: _query.trim().isEmpty
                                  ? '全部可用自定义标签（常用优先，已选不重复显示）'
                                  : '自定义标签搜索结果',
                              tags: suggestions,
                              icon: Icons.sell_outlined,
                              onSelected: (tag) => setState(() {
                                _dirty = _addNormalizedTag(tag) || _dirty;
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_dirty) ...[
                    const SizedBox(height: 10),
                    Semantics(
                      liveRegion: true,
                      child: const Row(
                        key: ValueKey('tagEditor.unsavedChanges'),
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: libraryAccent,
                            size: 17,
                          ),
                          SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              '修改尚未保存；取消将放弃本次调整。',
                              style: TextStyle(
                                color: libraryTextMuted,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('tagEditor.cancel'),
                onPressed: _cancel,
                child: const Text('\u53d6\u6d88'),
              ),
              FilledButton.icon(
                key: const ValueKey('tagEditor.save'),
                onPressed: _save,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('\u4fdd\u5b58'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
