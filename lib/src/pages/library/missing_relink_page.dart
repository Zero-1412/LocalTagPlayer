import 'package:flutter/material.dart';

import '../../core/tag_rules.dart';
import '../../features/library/application/library_missing_relink_command_executor.dart';
import '../../models/video_item.dart';
import '../../platform/file_system_adapter.dart';
import '../../services/library/library_application_facade.dart';
import '../../widgets/app_theme_tokens.dart';

import 'missing_bulk_relink_dialog.dart';

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

/** 由 presentation 统一展示单条 relink 结果，不参与路径或身份校验。 */
void showMissingRelinkCommandResult(
  BuildContext context, {
  required VideoItem item,
  required RelinkMissingVideoCommandResult result,
}) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        result.changed ? '已重新关联：${item.title}' : '${result.error}',
      ),
    ),
  );
}

/**
 * presentation 复用的“选择 → 显式 command → 反馈”编排。
 *
 * 文件选择仍经过平台 adapter，稳定身份与 Repository 提交仍由注入的 executor/callback
 * 负责；取消或 Route 已卸载时返回 null，不制造失败反馈。
 */
Future<RelinkMissingVideoCommandResult?> pickAndRelinkMissingVideo(
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
  if (path == null || !context.mounted) {
    return null;
  }
  final result = await LibraryMissingRelinkCommandExecutor().execute(
    RelinkMissingVideoCommand(item: item, newPath: path),
    commit: store.relinkMissingVideo,
  );
  if (!context.mounted) {
    return result;
  }
  showMissingRelinkCommandResult(context, item: item, result: result);
  return result;
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
  final _relinkCommandExecutor = LibraryMissingRelinkCommandExecutor();
  var _changed = false;

  List<VideoItem> get _missingVideos => widget.store.videos.values
      .where((item) => item.isMissing)
      .toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  /** 选择新文件并请求 store 做稳定身份与 fingerprint 校验。 */
  Future<void> _relink(VideoItem item) async {
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
    final operation = _relinkCommandExecutor.execute(
      RelinkMissingVideoCommand(item: item, newPath: path),
      commit: widget.store.relinkMissingVideo,
    );
    setState(() {});
    final result = await operation;
    if (!mounted) {
      return;
    }
    showMissingRelinkCommandResult(context, item: item, result: result);
    setState(() => _changed = _changed || result.changed);
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
                        child: BulkPathRelinkDialog(
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
                    relinkingVideoIds: _relinkCommandExecutor.runningVideoIds,
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
