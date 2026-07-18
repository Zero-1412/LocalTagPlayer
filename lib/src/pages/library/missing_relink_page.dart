import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/tag_rules.dart';
import '../../models/video_item.dart';
import '../../platform/file_system_adapter.dart';
import '../../services/library/library_application_facade.dart';
import '../../services/relink/bulk_path_relink_service.dart';
import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 选择单个 missing 视频的候选文件；取消时返回 null，不进入校验忙碌态。
 */
Future<String?> pickMissingVideoReplacementFile({
  required FileSystemAdapter fileSystem,
  required VideoItem item,
  String? fallbackDirectory,
}) async {
  final candidates = <String>{
    fileSystem.parentPath(item.path),
    if (item.rootPath != null) item.rootPath!,
    if (fallbackDirectory != null) fallbackDirectory,
  };
  String? initialDirectory;
  for (final candidate in candidates) {
    if (candidate.trim().isNotEmpty &&
        await fileSystem.directoryExists(candidate)) {
      initialDirectory = candidate;
      break;
    }
  }
  return fileSystem.pickFile(
    dialogTitle: '选择与 ${item.title} 对应的新文件',
    // 优先使用仍存在的原父目录，再回退记录 root 或当前媒体 root。
    initialDirectory: initialDirectory,
    allowedExtensions: TagRules.videoExtensions
        .map((extension) => extension.substring(1))
        .toList(),
  );
}

/** 对已选择路径执行稳定身份和 fingerprint 校验，并统一展示结果。 */
Future<bool> relinkMissingVideoToPath(
  BuildContext context, {
  required LibraryApplicationFacade store,
  required VideoItem item,
  required String path,
}) async {
  try {
    await store.relinkMissingVideo(item, path);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已重新关联：${item.title}')),
      );
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
    return false;
  }
}

/**
 * 选择并安全重新关联单个 missing 视频；播放器复用该组合入口。
 *
 * missing 管理页会拆开“选择”和“校验”两步，只在已经选中文件后显示行级忙碌态。
 */
Future<bool> pickAndRelinkMissingVideo(
  BuildContext context, {
  required LibraryApplicationFacade store,
  required FileSystemAdapter fileSystem,
  required VideoItem item,
}) async {
  final path = await pickMissingVideoReplacementFile(
    fileSystem: fileSystem,
    item: item,
    fallbackDirectory: store.roots.isEmpty ? null : store.roots.first,
  );
  if (path == null) {
    return false;
  }
  if (!context.mounted) {
    return false;
  }
  return relinkMissingVideoToPath(
    context,
    store: store,
    item: item,
    path: path,
  );
}

/**
 * 缺失视频管理页：展示保留的稳定条目，并提供经过 fingerprint 校验的单文件 relink。
 */
class MissingRelinkPage extends StatefulWidget {
  const MissingRelinkPage({
    super.key,
    required this.store,
    required this.fileSystem,
  });

  /** 当前媒体库；页面只更新被重新关联的单条记录及其 folder 标签索引。 */
  final LibraryApplicationFacade store;

  /** missing/relink 页面共享的文件选择平台边界。 */
  final FileSystemAdapter fileSystem;

  @override
  State<MissingRelinkPage> createState() => _MissingRelinkPageState();
}

/** 维护正在处理的 videoId，防止同一条目被重复提交。 */
class _MissingRelinkPageState extends State<MissingRelinkPage> {
  final Set<String> _relinkingVideoIds = <String>{};
  var _changed = false;

  List<VideoItem> get _missingVideos => widget.store.videos.values
      .where((item) => item.isMissing)
      .toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  /** 选择新文件并请求 store 做稳定身份与 fingerprint 校验。 */
  Future<void> _relink(VideoItem item) async {
    final videoId = item.videoId;
    final path = await pickMissingVideoReplacementFile(
      fileSystem: widget.fileSystem,
      item: item,
      fallbackDirectory:
          widget.store.roots.isEmpty ? null : widget.store.roots.first,
    );
    if (!mounted || path == null) {
      return;
    }
    // 原生文件选择器打开期间不显示行级 spinner；只有选中候选后才锁定该行进入校验。
    setState(() => _relinkingVideoIds.add(videoId));
    try {
      final changed = await relinkMissingVideoToPath(
        context,
        store: widget.store,
        item: item,
        path: path,
      );
      if (!mounted) {
        return;
      }
      if (changed) {
        setState(() => _changed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _relinkingVideoIds.remove(videoId));
      }
    }
  }

  /** 返回媒体库时报告是否有单条索引发生变化。 */
  void _close() => Navigator.of(context).pop(_changed);

  @override
  Widget build(BuildContext context) {
    final missing = _missingVideos;
    return Theme(
      data: maintenanceWorkspaceTheme(Theme.of(context)),
      child: _buildWorkspace(missing),
    );
  }

  /** 构建缺失视频维护工作区；只更换页面 surface，不改变 relink 稳定身份流程。 */
  Widget _buildWorkspace(List<VideoItem> missing) {
    return Scaffold(
      backgroundColor: libraryBackground,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回媒体库',
          onPressed: _close,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('缺失与重新关联'),
        actions: [
          OutlinedButton.icon(
            key: const ValueKey('missingRelink.bulkPreview'),
            onPressed: missing.isEmpty
                ? null
                : () async {
                    final count = await showDialog<int>(
                      context: context,
                      builder: (_) => maintenanceDialogSurface(
                        context: context,
                        child: _BulkPathRelinkDialog(
                          store: widget.store,
                          fileSystem: widget.fileSystem,
                        ),
                      ),
                    );
                    if (count != null && count > 0 && mounted) {
                      setState(() => _changed = true);
                    }
                  },
            icon: const Icon(Icons.drive_file_move_outline, size: 18),
            label: const Text('批量路径替换'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = constraints.maxWidth < 700 ? 16.0 : 24.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(padding, 8, padding, padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MissingRelinkOverview(missingCount: missing.length),
                const SizedBox(height: 16),
                Expanded(
                  child: _MissingVideoList(
                    missing: missing,
                    relinkingVideoIds: _relinkingVideoIds,
                    onRelink: _relink,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/** 页面顶部说明 missing 只代表路径失效，稳定身份与用户数据仍然保留。 */
class _MissingRelinkOverview extends StatelessWidget {
  const _MissingRelinkOverview({required this.missingCount});

  final int missingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: librarySurface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: libraryBorder),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: missingCount == 0
                  ? const Color(0x203fc487)
                  : appAccentViolet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Icon(
              missingCount == 0
                  ? Icons.check_circle_outline_rounded
                  : Icons.link_off_rounded,
              color:
                  missingCount == 0 ? const Color(0xff61d49a) : appAccentViolet,
              size: 26,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 240, maxWidth: 660),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  missingCount == 0 ? '所有视频路径均可访问' : '$missingCount 个视频路径失效',
                  style: const TextStyle(
                    color: libraryText,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  '缺失记录不会被自动删除。重新关联只更新 mutable path，并通过 fingerprint 防止选错文件。',
                  style: TextStyle(
                    color: libraryTextMuted,
                    fontSize: 13,
                    height: 1.42,
                  ),
                ),
              ],
            ),
          ),
          const _RelinkDataBadge(
            icon: Icons.shield_outlined,
            label: '标签与播放记录已保留',
          ),
        ],
      ),
    );
  }
}

/** 缺失条目列表结构表面；空态与有数据状态共享稳定布局。 */
class _MissingVideoList extends StatelessWidget {
  const _MissingVideoList({
    required this.missing,
    required this.relinkingVideoIds,
    required this.onRelink,
  });

  final List<VideoItem> missing;
  final Set<String> relinkingVideoIds;
  final ValueChanged<VideoItem> onRelink;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: librarySurface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: libraryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '待处理视频',
                    style: TextStyle(
                      color: libraryText,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${missing.length} 项',
                  style: const TextStyle(
                    color: libraryTextMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: missing.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          color: Color(0xff61d49a),
                          size: 36,
                        ),
                        SizedBox(height: 12),
                        Text(
                          '当前没有缺失视频',
                          style: TextStyle(
                            color: libraryText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '扫描发现路径失效时，记录会安全保留在这里。',
                          style: TextStyle(color: libraryTextMuted),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    key: const ValueKey('missingRelink.list'),
                    padding: const EdgeInsets.all(12),
                    itemCount: missing.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = missing[index];
                      return _MissingVideoRow(
                        item: item,
                        busy: relinkingVideoIds.contains(item.videoId),
                        onRelink: () => onRelink(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/** 单个 missing 条目的内容优先行，窄宽与大文字下动作自然换到下一行。 */
class _MissingVideoRow extends StatelessWidget {
  const _MissingVideoRow({
    required this.item,
    required this.busy,
    required this.onRelink,
  });

  final VideoItem item;
  final bool busy;
  final VoidCallback onRelink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: libraryBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final compact = constraints.maxWidth < 620 || textScale > 1.3;
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x20e0a24c),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: const Icon(
                  Icons.link_off_rounded,
                  color: Color(0xffe4aa58),
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: libraryText,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Tooltip(
                      message: item.path,
                      child: Text(
                        item.path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
            ],
          );
          final action = FilledButton.icon(
            key: ValueKey('missingRelink.${item.videoId}'),
            onPressed: busy ? null : onRelink,
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.find_in_page_outlined, size: 18),
            label: Text(busy ? '校验中' : '重新关联'),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 16),
              action,
            ],
          );
        },
      ),
    );
  }
}

/** missing 数据保留角标使用图标与文字双重编码。 */
class _RelinkDataBadge extends StatelessWidget {
  const _RelinkDataBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.capsule),
        border: Border.all(color: libraryBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: appAccentViolet),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: libraryText,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/** 批量路径替换的只读预览与二次确认弹窗。 */
class _BulkPathRelinkDialog extends StatefulWidget {
  const _BulkPathRelinkDialog({
    required this.store,
    required this.fileSystem,
  });

  final LibraryApplicationFacade store;
  final FileSystemAdapter fileSystem;

  @override
  State<_BulkPathRelinkDialog> createState() => _BulkPathRelinkDialogState();
}

class _BulkPathRelinkDialogState extends State<_BulkPathRelinkDialog> {
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
                    _BulkRelinkSummaryBadge(
                      icon: Icons.check_circle_outline_rounded,
                      label: '$ready 可更新',
                      color: const Color(0xff61d49a),
                    ),
                    _BulkRelinkSummaryBadge(
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
                  ? const _BulkRelinkLoadingState()
                  : visiblePreviews.isEmpty
                      ? _BulkRelinkEmptyPreview(
                          hasPreview: _previews.isNotEmpty,
                        )
                      : ListView.separated(
                          itemCount: visiblePreviews.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) =>
                              _BulkRelinkPreviewRow(
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

/** 批量预览摘要角标。 */
class _BulkRelinkSummaryBadge extends StatelessWidget {
  const _BulkRelinkSummaryBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.capsule),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/** 生成只读预览期间的稳定加载状态，不使用大面积 shimmer。 */
class _BulkRelinkLoadingState extends StatelessWidget {
  const _BulkRelinkLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('正在校验路径与 fingerprint…'),
        ],
      ),
    );
  }
}

/** 预览尚未生成或搜索无结果时的解释性空状态。 */
class _BulkRelinkEmptyPreview extends StatelessWidget {
  const _BulkRelinkEmptyPreview({required this.hasPreview});

  final bool hasPreview;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasPreview ? Icons.search_off_rounded : Icons.preview_outlined,
            size: 32,
            color: libraryTextMuted,
          ),
          const SizedBox(height: 10),
          Text(
            hasPreview ? '没有匹配的预览项' : '输入路径映射后生成只读预览',
            style: const TextStyle(
              color: libraryTextMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/** 单个批量 Relink 预览条目，状态由图标、文字和色彩共同表达。 */
class _BulkRelinkPreviewRow extends StatelessWidget {
  const _BulkRelinkPreviewRow({required this.preview});

  final BulkPathRelinkPreview preview;

  @override
  Widget build(BuildContext context) {
    final color = _bulkRelinkStatusColor(preview.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: libraryBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              _bulkRelinkStatusIcon(preview.status),
              color: color,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Tooltip(
              message: '${preview.item.path}\n→ ${preview.newPath}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview.item.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: libraryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '→ ${preview.newPath}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: libraryTextMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          _BulkRelinkSummaryBadge(
            icon: _bulkRelinkStatusIcon(preview.status),
            label: _bulkRelinkStatusLabel(preview.status),
            color: color,
          ),
        ],
      ),
    );
  }
}

String _bulkRelinkStatusLabel(BulkRelinkStatus status) => switch (status) {
      BulkRelinkStatus.ready => '可更新',
      BulkRelinkStatus.targetMissing => '目标不存在',
      BulkRelinkStatus.pathConflict => '路径冲突',
      BulkRelinkStatus.fingerprintMismatch => '指纹不一致',
      BulkRelinkStatus.executionFailed => '执行失败，可重试',
    };

IconData _bulkRelinkStatusIcon(BulkRelinkStatus status) => switch (status) {
      BulkRelinkStatus.ready => Icons.check_circle_outline_rounded,
      BulkRelinkStatus.targetMissing => Icons.help_outline_rounded,
      BulkRelinkStatus.pathConflict => Icons.warning_amber_rounded,
      BulkRelinkStatus.fingerprintMismatch => Icons.fingerprint_rounded,
      BulkRelinkStatus.executionFailed => Icons.refresh_rounded,
    };

/** 批量预览状态的语义色；图标和文字仍保留，颜色不是唯一编码。 */
Color _bulkRelinkStatusColor(BulkRelinkStatus status) => switch (status) {
      BulkRelinkStatus.ready => const Color(0xff61d49a),
      BulkRelinkStatus.targetMissing => const Color(0xffe4aa58),
      BulkRelinkStatus.pathConflict => const Color(0xffe07280),
      BulkRelinkStatus.fingerprintMismatch => const Color(0xffc18cff),
      BulkRelinkStatus.executionFailed => const Color(0xffe07280),
    };
