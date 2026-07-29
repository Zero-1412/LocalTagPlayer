import 'package:flutter/material.dart';

import '../../core/tag_rules.dart';
import '../../models/platform_models.dart';

// ignore_for_file: slash_for_doc_comments

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
            builder: (_) => const CreateTagDialog(groups: <TagGroup>[]),
          ),
          child: const Text('打开新建标签'),
        ),
      ),
    ),
  );
}

class CreateTagDialog extends StatefulWidget {
  const CreateTagDialog({super.key, required this.groups});

  final List<TagGroup> groups;

  @override
  State<CreateTagDialog> createState() => CreateTagDialogState();
}

class CreateTagDialogState extends State<CreateTagDialog> {
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
      CreateTagResult(
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

class CreateTagResult {
  const CreateTagResult({
    required this.name,
    required this.displayName,
    required this.groupId,
  });

  final String name;
  final String displayName;
  final String groupId;
}
