part of '../../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 选择并安全重新关联单个 missing 视频；播放器和管理页共用同一文件类型与校验入口。
 */
Future<bool> pickAndRelinkMissingVideo(
  BuildContext context, {
  required LibraryStore store,
  required VideoItem item,
}) async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: '选择与 ${item.title} 对应的新文件',
    type: FileType.custom,
    allowedExtensions: TagRules.videoExtensions
        .map((extension) => extension.substring(1))
        .toList(),
    allowMultiple: false,
  );
  final path = result?.files.single.path;
  if (path == null) {
    return false;
  }
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
 * 缺失视频管理页：展示保留的稳定条目，并提供经过 fingerprint 校验的单文件 relink。
 */
class MissingRelinkPage extends StatefulWidget {
  const MissingRelinkPage({super.key, required this.store});

  /** 当前媒体库；页面只更新被重新关联的单条记录及其 folder 标签索引。 */
  final LibraryStore store;

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
    setState(() => _relinkingVideoIds.add(videoId));
    try {
      final changed = await pickAndRelinkMissingVideo(
        context,
        store: widget.store,
        item: item,
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
    return Scaffold(
      backgroundColor: _appBackground,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回媒体库',
          onPressed: _close,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text('缺失视频 · ${missing.length}'),
        actions: [
          TextButton.icon(
            key: const ValueKey('missingRelink.bulkPreview'),
            onPressed: missing.isEmpty
                ? null
                : () async {
                    final count = await showDialog<int>(
                      context: context,
                      builder: (_) => _BulkPathRelinkDialog(
                        store: widget.store,
                      ),
                    );
                    if (count != null && count > 0 && mounted) {
                      setState(() => _changed = true);
                    }
                  },
            icon: const Icon(Icons.drive_file_move_outline),
            label: const Text('批量路径替换'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: missing.isEmpty
          ? const Center(
              child: _EmptyState(
                hasLibrary: true,
                message: '当前没有缺失视频',
              ),
            )
          : ListView.separated(
              key: const ValueKey('missingRelink.list'),
              padding: const EdgeInsets.all(24),
              itemCount: missing.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = missing[index];
                final videoId = item.videoId;
                final busy = _relinkingVideoIds.contains(videoId);
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.link_off_rounded),
                    title: Text(item.title),
                    subtitle: Text(
                      item.path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: FilledButton.icon(
                      key: ValueKey('missingRelink.$videoId'),
                      onPressed: busy ? null : () => _relink(item),
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.find_in_page_outlined),
                      label: const Text('重新关联'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/** 批量路径替换的只读预览与二次确认弹窗。 */
class _BulkPathRelinkDialog extends StatefulWidget {
  const _BulkPathRelinkDialog({required this.store});

  final LibraryStore store;

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
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择迁移后的新目录',
    );
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
      builder: (context) => AlertDialog(
        title: const Text('确认批量重新关联'),
        content: Text('将更新 $ready 条视频的 mutable path。文件本身不会被移动或删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认更新'),
          ),
        ],
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
    final visiblePreviews =
        filterBulkRelinkPreviews(_previews, _searchController.text);
    return AlertDialog(
      title: const Text('批量路径替换预览'),
      content: SizedBox(
        width: 720,
        height: 520,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('missingRelink.oldPrefix'),
              controller: _oldPrefixController,
              decoration: const InputDecoration(
                labelText: '旧路径前缀',
                hintText: r'X:\test-media',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('missingRelink.newPrefix'),
              controller: _newPrefixController,
              decoration: InputDecoration(
                labelText: '新路径前缀',
                hintText: r'E:\video',
                suffixIcon: IconButton(
                  tooltip: '选择新目录',
                  onPressed: _pickNewPrefix,
                  icon: const Icon(Icons.folder_open_rounded),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _previews.isEmpty
                    ? '输入前缀后先生成只读预览'
                    : '共 ${_previews.length} 条，$ready 条可安全更新',
              ),
            ),
            if (_rootUpdateFailed) ...[
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '视频已更新，但扫描 root 保存失败；请在目录管理中确认新 root。',
                  style: TextStyle(color: Colors.redAccent),
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
                hintText: '搜索标题、旧/新路径或状态',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: visiblePreviews.length,
                      itemBuilder: (context, index) {
                        final preview = visiblePreviews[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(_bulkRelinkStatusIcon(preview.status)),
                          title: Text(preview.item.path),
                          subtitle: Text(preview.newPath),
                          trailing:
                              Text(_bulkRelinkStatusLabel(preview.status)),
                        );
                      },
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
