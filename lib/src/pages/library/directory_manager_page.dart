import 'package:flutter/material.dart';

import '../../services/library/library_application_facade.dart';
import '../../widgets/app_theme_tokens.dart';
import 'directory_manager_sections.dart';

export 'directory_manager_sections.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 本地媒体目录维护页。
 *
 * 页面只编排已有的添加、扫描和解除管理回调，不直接访问磁盘、SQLite 或扫描后端；
 * root、detached 与用户数据保留语义继续由媒体库应用层拥有。
 */
class DirectoryManagerPage extends StatefulWidget {
  const DirectoryManagerPage({
    super.key,
    required this.store,
    required this.scanning,
    required this.onAddDirectory,
    required this.onRescan,
    required this.onRemoveRoot,
  });

  /** 提供当前受管理 root 的应用门面；页面只读取 roots 快照。 */
  final LibraryApplicationFacade store;

  /** 打开页面时扫描是否已经占用目录维护入口。 */
  final bool scanning;

  /** 通过既有文件选择与扫描链路添加目录。 */
  final Future<void> Function() onAddDirectory;

  /** 通过既有扫描协调器重新扫描全部 root。 */
  final Future<void> Function() onRescan;

  /** 解除一个 root 的媒体库管理，不删除本地文件或稳定身份数据。 */
  final Future<void> Function(String root) onRemoveRoot;

  @override
  State<DirectoryManagerPage> createState() => _DirectoryManagerPageState();
}

/** 维护页面级忙碌态，避免添加、扫描和解除管理被重复提交。 */
class _DirectoryManagerPageState extends State<DirectoryManagerPage> {
  var _busy = false;

  /** 执行添加目录并刷新当前页读取的 root 快照。 */
  Future<void> _addDirectory() async {
    if (_busy || widget.scanning) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onAddDirectory();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /** 执行重新扫描；扫描状态仍由原媒体库协调器负责。 */
  Future<void> _rescan() async {
    if (_busy || widget.scanning || widget.store.roots.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onRescan();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /**
   * 明确展示 detached 数据保留语义后解除 root 管理。
   *
   * 确认只授权现有 [widget.onRemoveRoot]，不在 UI 中复制删除或迁移逻辑。
   */
  Future<void> _removeRoot(String root) async {
    if (_busy || widget.scanning) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => maintenanceDialogSurface(
        context: context,
        child: AlertDialog(
          icon: const Icon(Icons.folder_off_outlined, color: appAccentViolet),
          title: const Text('解除目录管理'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '目录中的视频会从当前媒体库与播放队列隐藏，但不会删除本地文件。',
                  style: TextStyle(color: libraryText, height: 1.45),
                ),
                const SizedBox(height: 12),
                const DirectoryDataPolicy(),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: librarySurfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(color: libraryBorder),
                  ),
                  child: Text(
                    root,
                    style: const TextStyle(
                      color: libraryTextMuted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('directoryManager.confirmRemove'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffb84d5f),
              ),
              child: const Text('解除管理'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onRemoveRoot(root);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: maintenanceWorkspaceTheme(Theme.of(context)),
      child: Scaffold(
        key: const ValueKey('directoryManager.page'),
        backgroundColor: libraryBackground,
        appBar: AppBar(
          leading: IconButton(
            tooltip: '返回媒体库',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('目录管理'),
          actions: [
            OutlinedButton.icon(
              key: const ValueKey('directoryManager.add'),
              onPressed: _busy || widget.scanning ? null : _addDirectory,
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加目录'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('directoryManager.rescan'),
              onPressed: _busy || widget.scanning || widget.store.roots.isEmpty
                  ? null
                  : _rescan,
              icon: _busy || widget.scanning
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(widget.scanning ? '扫描中' : '重新扫描'),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final pagePadding = constraints.maxWidth < 700 ? 16.0 : 24.0;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                pagePadding,
                8,
                pagePadding,
                pagePadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DirectoryOverview(
                    rootCount: widget.store.roots.length,
                    scanning: widget.scanning || _busy,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: DirectoryRootList(
                      roots: widget.store.roots,
                      busy: _busy || widget.scanning,
                      onRemove: _removeRoot,
                      onAdd: _addDirectory,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
