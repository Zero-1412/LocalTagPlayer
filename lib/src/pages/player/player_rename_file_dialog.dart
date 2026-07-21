import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../models/video_item.dart';
import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** Windows 和常见桌面文件系统都不接受的文件名字符。 */
final RegExp _invalidRenameCharacters = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

/** Windows 保留设备名；使用保守交集可避免同一媒体库跨平台后出现不可访问文件。 */
final RegExp _reservedWindowsFileName = RegExp(
  r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
  caseSensitive: false,
);

/**
 * 校验用户输入的文件 basename；返回 null 表示可以提交。
 *
 * 扩展名由对话框只读保留，因此这里禁止路径分隔符、控制字符、尾部点/空格和保留设备名。
 */
String? playerRenameFileNameError(String rawName) {
  final name = rawName.trim();
  if (name.isEmpty) {
    return '请输入文件名';
  }
  if (name == '.' || name == '..') {
    return '文件名不能是 . 或 ..';
  }
  if (_invalidRenameCharacters.hasMatch(name)) {
    return '文件名不能包含 < > : " / \\ | ? *';
  }
  if (rawName.endsWith(' ') || rawName.endsWith('.')) {
    return '文件名不能以空格或句点结尾';
  }
  if (_reservedWindowsFileName.hasMatch(name)) {
    return '该名称由系统保留，请换一个文件名';
  }
  return null;
}

/**
 * 展示当前视频的重命名弹窗，只编辑 basename 并保留原扩展名。
 *
 * 返回 null 表示取消；返回值已经过校验和 trim，但尚未执行任何磁盘或数据库操作。
 */
Future<String?> showPlayerRenameFileDialog(
  BuildContext context, {
  required VideoItem item,
}) =>
    showDialog<String>(
      context: context,
      builder: (dialogContext) => _PlayerRenameFileDialog(item: item),
    );

/** 持有重命名输入生命周期，确保 DialogRoute 退场完成后才释放 controller。 */
class _PlayerRenameFileDialog extends StatefulWidget {
  const _PlayerRenameFileDialog({required this.item});

  /** 当前稳定视频；只读取现有标题和扩展名，不在弹窗内修改实体。 */
  final VideoItem item;

  @override
  State<_PlayerRenameFileDialog> createState() =>
      _PlayerRenameFileDialogState();
}

/** 只维护输入和校验错误；磁盘事务由弹窗外的播放器/媒体库协调。 */
class _PlayerRenameFileDialogState extends State<_PlayerRenameFileDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  /** 原文件扩展名始终只读显示。 */
  String get _extension => p.extension(widget.item.path);

  /** 当前输入是否与原 basename 存在真实变化。 */
  bool get _changed => _controller.text.trim() != widget.item.title.trim();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.item.title);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /** 校验并关闭弹窗；成功结果只返回 basename，不提前执行磁盘操作。 */
  void _submit() {
    final error = playerRenameFileNameError(_controller.text);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    if (!_changed) {
      return;
    }
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      // DialogRoute 位于播放器局部主题之外，显式继承深色维护浮层语义。
      data: maintenanceWorkspaceTheme(Theme.of(context)),
      child: AlertDialog(
        title: const Text('重命名文件'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '只修改文件名，标签请在下方“标签”区域维护。',
                style: TextStyle(color: playerTextMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('player.renameFile.input'),
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(240),
                ],
                decoration: InputDecoration(
                  labelText: '文件名',
                  suffixText: _extension,
                  errorText: _errorText,
                  helperText: _extension.isEmpty ? null : '扩展名保持不变',
                ),
                onChanged: (_) => setState(() => _errorText = null),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('player.renameFile.cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('player.renameFile.confirm'),
            onPressed: _changed ? _submit : null,
            style: FilledButton.styleFrom(
              backgroundColor: appAccentViolet,
              foregroundColor: Colors.white,
            ),
            child: const Text('重命名'),
          ),
        ],
      ),
    );
  }
}
