import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform/file_system_adapter.dart';
import '../../services/library/library_application_facade.dart';
import '../../services/relink/bulk_path_relink_service.dart';
import '../../widgets/app_theme_tokens.dart';
import 'missing_bulk_relink_preview.dart';

// ignore_for_file: slash_for_doc_comments

/** 批量路径替换的只读预览与二次确认弹窗。 */
class BulkPathRelinkDialog extends StatefulWidget {
  const BulkPathRelinkDialog({
    super.key,
    required this.store,
    required this.fileSystem,
  });

  final LibraryApplicationFacade store;
  final FileSystemAdapter fileSystem;

  @override
  State<BulkPathRelinkDialog> createState() => BulkPathRelinkDialogState();
}

class BulkPathRelinkDialogState extends State<BulkPathRelinkDialog> {
  final _oldPrefixController = TextEditingController();
  final _newPrefixController = TextEditingController();
  final _searchController = TextEditingController();
  final _service = const BulkPathRelinkService();
  List<BulkPathRelinkPreview> _previews = const <BulkPathRelinkPreview>[];
  var _loading = false;
  var _executing = false;
  Set<String> _failedVideoIds = <String>{};
  List<BulkPathRelinkPreview> _auditPreviews = const <BulkPathRelinkPreview>[];
  var _totalSucceeded = 0;
  var _rootUpdateFailed = false;

  @override
  void dispose() {
    _oldPrefixController.dispose();
    _newPrefixController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickNewPrefix() async {
    final paths = await widget.fileSystem.pickDirectories(
      dialogTitle: '选择迁移后的新目录',
      initialDirectory:
          widget.store.roots.isEmpty ? null : widget.store.roots.first,
    );
    final path = paths.isEmpty ? null : paths.first;
    if (path != null && mounted) {
      _newPrefixController.text = path;
    }
  }

  Future<void> _preview() async {
    setState(() => _loading = true);
    final result = await _service.preview(
      store: widget.store,
      oldPrefix: _oldPrefixController.text,
      newPrefix: _newPrefixController.text,
    );
    if (mounted) {
      setState(() {
        _previews = result;
        _auditPreviews = result;
        _failedVideoIds = <String>{};
        _totalSucceeded = 0;
        _rootUpdateFailed = false;
        _loading = false;
      });
    }
  }

  Future<void> _execute() async {
    final ready = _previews
        .where((preview) => preview.status == BulkRelinkStatus.ready)
        .length;
    if (ready == 0) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => maintenanceDialogSurface(
        context: context,
        child: AlertDialog(
          title: const Text('确认批量重新关联'),
          content: Text('将更新 $ready 条视频的 mutable path。文件本身不会被移动或删除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认更新'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _executing = true);
    final result = await _service.execute(
      store: widget.store,
      previews: _previews,
      oldPrefix: _oldPrefixController.text,
      newPrefix: _newPrefixController.text,
    );
    if (mounted) {
      setState(() {
        _totalSucceeded += result.succeededCount;
        _failedVideoIds = result.failedVideoIds;
        _rootUpdateFailed = result.rootUpdateFailed;
        _previews = [
          for (final preview in _previews)
            if (preview.status != BulkRelinkStatus.ready)
              preview
            else if (result.failedVideoIds.contains(preview.item.videoId))
              BulkPathRelinkPreview(
                item: preview.item,
                newPath: preview.newPath,
                status: BulkRelinkStatus.executionFailed,
              ),
        ];
        _executing = false;
      });
    }
  }

  /** 只重新预览并提交上次执行失败的 videoId。 */
  Future<void> _retryFailed() async {
    if (_failedVideoIds.isEmpty) {
      return;
    }
    setState(() => _executing = true);
    final refreshed = await _service.preview(
      store: widget.store,
      oldPrefix: _oldPrefixController.text,
      newPrefix: _newPrefixController.text,
    );
    final retryable = refreshed
        .where((preview) => _failedVideoIds.contains(preview.item.videoId))
        .toList();
    final result = await _service.execute(
      store: widget.store,
      previews: retryable,
      oldPrefix: _oldPrefixController.text,
      newPrefix: _newPrefixController.text,
    );
    if (!mounted) {
      return;
    }
    final stillFailedIds = <String>{
      ...result.failedVideoIds,
      for (final preview in retryable)
        if (preview.status != BulkRelinkStatus.ready) preview.item.videoId,
    };
    setState(() {
      _totalSucceeded += result.succeededCount;
      _failedVideoIds = stillFailedIds;
      _rootUpdateFailed = _rootUpdateFailed || result.rootUpdateFailed;
      _previews = [
        for (final preview in retryable)
          if (stillFailedIds.contains(preview.item.videoId))
            BulkPathRelinkPreview(
              item: preview.item,
              newPath: preview.newPath,
              status: BulkRelinkStatus.executionFailed,
            ),
      ];
      _executing = false;
    });
  }

  /** 复制不包含本地路径和文件标题的审计摘要。 */
  Future<void> _copyAuditSummary() async {
    final result = BulkRelinkExecutionResult(
      succeededCount: _totalSucceeded,
      failedVideoIds: _failedVideoIds,
      rootUpdateFailed: _rootUpdateFailed,
    );
    await Clipboard.setData(ClipboardData(
      text: bulkRelinkAuditSummary(
        _auditPreviews.isEmpty ? _previews : _auditPreviews,
        result: result,
      ),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制不含本地路径的审计摘要')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _previews
        .where((preview) => preview.status == BulkRelinkStatus.ready)
        .length;
    final blocked = _previews.length - ready;
    final visiblePreviews =
        filterBulkRelinkPreviews(_previews, _searchController.text);
    final windowSize = MediaQuery.sizeOf(context);
    final contentHeight = (windowSize.height * 0.66).clamp(380.0, 560.0);
    return AlertDialog(
      insetPadding: const EdgeInsets.all(24),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
      actionsPadding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      actionsOverflowButtonSpacing: 8,
      title: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.drive_file_move_outline, color: appAccentViolet),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('批量路径替换'),
                SizedBox(height: 4),
                Text(
                  '先生成只读预览，再更新可安全匹配的 mutable path；不会移动或删除文件。',
                  style: TextStyle(
                    color: libraryTextMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 820,
        height: contentHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 660;
                final oldField = TextField(
                  key: const ValueKey('missingRelink.oldPrefix'),
                  controller: _oldPrefixController,
                  decoration: const InputDecoration(
                    labelText: '旧路径前缀',
                    hintText: r'X:\test-media',
                    prefixIcon: Icon(Icons.folder_off_outlined),
                  ),
                );
                final newField = TextField(
                  key: const ValueKey('missingRelink.newPrefix'),
                  controller: _newPrefixController,
                  decoration: InputDecoration(
                    labelText: '新路径前缀',
                    hintText: r'E:\video',
                    prefixIcon: const Icon(Icons.folder_copy_outlined),
                    suffixIcon: IconButton(
                      tooltip: '选择新目录',
                      onPressed: _pickNewPrefix,
                      icon: const Icon(Icons.folder_open_rounded),
                    ),
                  ),
                );
                if (compact) {
                  return Column(
                    children: [
                      oldField,
                      const SizedBox(height: 10),
                      newField,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: oldField),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: libraryTextMuted,
                      ),
                    ),
                    Expanded(child: newField),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: librarySurfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: libraryBorder),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _previews.isEmpty ? '等待生成预览' : '预览 ${_previews.length} 项',
                    style: const TextStyle(
                      color: libraryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (_previews.isNotEmpty) ...[
                    BulkRelinkSummaryBadge(
                      icon: Icons.check_circle_outline_rounded,
                      label: '$ready 可更新',
                      color: const Color(0xff61d49a),
                    ),
                    BulkRelinkSummaryBadge(
                      icon: Icons.info_outline_rounded,
                      label: '$blocked 需处理',
                      color: blocked == 0
                          ? libraryTextMuted
                          : const Color(0xffe4aa58),
                    ),
                  ],
                ],
              ),
            ),
            if (_rootUpdateFailed) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0x20e07280),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: const Color(0x66e07280)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Color(0xffe07280), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '视频已更新，但扫描 root 保存失败；请在目录管理中确认新 root。',
                        style: TextStyle(color: Color(0xfff0a0ab)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('missingRelink.previewSearch'),
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded),
                hintText: '在预览中搜索标题、路径或状态',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const BulkRelinkLoadingState()
                  : visiblePreviews.isEmpty
                      ? BulkRelinkEmptyPreview(
                          hasPreview: _previews.isNotEmpty,
                        )
                      : ListView.separated(
                          itemCount: visiblePreviews.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) => BulkRelinkPreviewRow(
                            preview: visiblePreviews[index],
                          ),
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _executing
              ? null
              : () => Navigator.of(context).pop(_totalSucceeded),
          child: const Text('关闭'),
        ),
        TextButton.icon(
          key: const ValueKey('missingRelink.copyAudit'),
          onPressed: _previews.isEmpty && _auditPreviews.isEmpty
              ? null
              : _copyAuditSummary,
          icon: const Icon(Icons.copy_all_rounded),
          label: const Text('复制审计摘要'),
        ),
        if (_failedVideoIds.isNotEmpty)
          OutlinedButton.icon(
            key: const ValueKey('missingRelink.retryFailed'),
            onPressed: _executing ? null : _retryFailed,
            icon: const Icon(Icons.refresh_rounded),
            label: Text('重试失败项 ${_failedVideoIds.length}'),
          ),
        OutlinedButton.icon(
          key: const ValueKey('missingRelink.generatePreview'),
          onPressed: _loading || _executing ? null : _preview,
          icon: const Icon(Icons.preview_outlined),
          label: const Text('生成预览'),
        ),
        FilledButton.icon(
          key: const ValueKey('missingRelink.executePreview'),
          onPressed: ready == 0 || _executing ? null : _execute,
          icon: const Icon(Icons.link_rounded),
          label: Text(_executing ? '更新中' : '应用 $ready 条'),
        ),
      ],
    );
  }
}
