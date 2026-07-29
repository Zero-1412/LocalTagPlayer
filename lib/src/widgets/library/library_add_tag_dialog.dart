import 'package:flutter/material.dart';

import '../../models/platform_models.dart';
import 'library_desktop_scroll_behavior.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 展示“添加到我的标签库”对话框，并返回用户选择或输入的标签名快照。
 *
 * 对话框只管理输入框和候选过滤等瞬时展示状态，不创建标签、不修改收藏，
 * 也不持有媒体库 controller；业务 owner 仍由调用页面在返回后执行命令。
 */
Future<String?> showLibraryAddTagDialog(
  BuildContext context, {
  required List<TagItem> tags,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _LibraryAddTagDialog(tags: tags),
  );
}

/** 管理对话框输入框与候选过滤的短生命周期展示状态。 */
class _LibraryAddTagDialog extends StatefulWidget {
  const _LibraryAddTagDialog({required this.tags});

  /** 打开对话框时传入的只读标签快照。 */
  final List<TagItem> tags;

  @override
  State<_LibraryAddTagDialog> createState() => _LibraryAddTagDialogState();
}

/** 在路由彻底卸载后释放输入 controller，避免退出动画继续读取已释放对象。 */
class _LibraryAddTagDialogState extends State<_LibraryAddTagDialog> {
  final TextEditingController _controller = TextEditingController();
  late final List<TagItem> _sortedTags = List<TagItem>.of(widget.tags)
    ..sort((a, b) => _tagLabel(a).compareTo(_tagLabel(b)));
  String _keyword = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 过滤只改变候选展示，不写回真实标签数据。
    final normalizedKeyword = _keyword.trim().toLowerCase();
    final visibleTags = _sortedTags
        .where((tag) {
          final label = _tagLabel(tag);
          return normalizedKeyword.isEmpty ||
              label.toLowerCase().contains(normalizedKeyword) ||
              tag.name.toLowerCase().contains(normalizedKeyword);
        })
        .take(80)
        .toList(growable: false);
    return AlertDialog(
      title: const Text('添加到我的标签库'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '搜索或新建标签',
                hintText: '输入标签名，下方会即时过滤',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (value) => setState(() => _keyword = value),
              onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: visibleTags.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text('没有匹配的已有标签'),
                      ),
                    )
                  : ScrollConfiguration(
                      behavior: const DesktopDragScrollBehavior(),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in visibleTags)
                              ActionChip(
                                label: Text(_tagLabel(tag)),
                                onPressed: () =>
                                    Navigator.of(context).pop(_tagLabel(tag)),
                              ),
                          ],
                        ),
                      ),
                    ),
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
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('添加'),
        ),
      ],
    );
  }
}

/** 返回候选标签对用户可见的名称。 */
String _tagLabel(TagItem tag) => tag.displayName ?? tag.name;
