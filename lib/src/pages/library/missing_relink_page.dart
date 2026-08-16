import 'package:flutter/material.dart';

import '../../core/tag_rules.dart';
import '../../features/library/application/library_missing_relink_command_executor.dart';
import '../../models/video_item.dart';
import '../../platform/file_system_adapter.dart';
import '../../services/library/library_application_facade.dart';
import '../../widgets/app_theme_tokens.dart';
import '../../widgets/maintenance_workspace_app_bar.dart';

import 'missing_bulk_relink_dialog.dart';
import 'missing_relink_sections.dart';

export 'missing_relink_sections.dart';

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
  final result = await LibraryMissingRelinkCommandExecutor().executeById(
    RelinkMissingVideoCommand(item: item, newPath: path),
    commitById: store.relinkMissingVideoById,
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
    final operation = _relinkCommandExecutor.executeById(
      RelinkMissingVideoCommand(item: item, newPath: path),
      commitById: widget.store.relinkMissingVideoById,
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

  /** 打开批量路径替换预览；页面只接收完成数量，不拥有映射与校验语义。 */
  Future<void> _openBulkRelinkPreview(List<VideoItem> missing) async {
    if (missing.isEmpty) {
      return;
    }
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
  }

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
      appBar: MaintenanceWorkspaceAppBar(
        title: '缺失与重新关联',
        onBack: _close,
        actionIcon: Icons.drive_file_move_outline,
        actionLabel: '批量路径替换',
        actionTooltip: '批量路径替换',
        actionKey: const ValueKey('missingRelink.bulkPreview'),
        onAction:
            missing.isEmpty ? null : () => _openBulkRelinkPreview(missing),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = constraints.maxWidth < 700 ? 16.0 : 24.0;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, 18, padding, padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MissingRelinkOverview(missingCount: missing.length),
                    const SizedBox(height: 16),
                    Expanded(
                      child: MissingVideoList(
                        missing: missing,
                        relinkingVideoIds:
                            _relinkCommandExecutor.runningVideoIds,
                        onRelink: _relink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
