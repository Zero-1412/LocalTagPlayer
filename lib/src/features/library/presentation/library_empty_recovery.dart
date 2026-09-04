import 'package:flutter/material.dart';

import '../../../widgets/app_theme_tokens.dart';
import '../../../widgets/library/library_smoke_keys.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库首次使用与零结果的可恢复空状态。
 *
 * 空库优先建立目录 root 以自动生成 folder 标签；有库但筛选为空时只修改查询状态，
 * 不把“没有命中”误导成再次导入相同文件。
 */
class LibraryEmptyRecovery extends StatelessWidget {
  const LibraryEmptyRecovery({
    super.key,
    required this.hasLibrary,
    required this.hasActiveFilters,
    required this.message,
    required this.onAddFolder,
    required this.onAddFiles,
    required this.onClearFilters,
    required this.onOpenFilters,
  });

  final bool hasLibrary;
  final bool hasActiveFilters;
  final String? message;
  final VoidCallback onAddFolder;
  final VoidCallback onAddFiles;
  final VoidCallback onClearFilters;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    if (!hasLibrary) {
      return _RecoveryContent(
        icon: Icons.create_new_folder_outlined,
        title: '添加媒体目录，自动建立标签视图',
        description: '选择一个视频根目录后，会按前两级文件夹生成可筛选标签；也可以只添加视频文件。',
        primary: FilledButton.icon(
          key: LibrarySmokeKeys.emptyAddFolder,
          onPressed: onAddFolder,
          icon: const Icon(Icons.folder_open_rounded),
          label: const Text('选择视频目录'),
        ),
        secondary: TextButton.icon(
          key: LibrarySmokeKeys.emptyAddFiles,
          onPressed: onAddFiles,
          icon: const Icon(Icons.video_file_outlined),
          label: const Text('添加视频文件'),
        ),
      );
    }
    if (hasActiveFilters) {
      return _RecoveryContent(
        icon: Icons.filter_alt_off_outlined,
        title: '没有匹配的视频',
        description: '当前关键词或标签组合没有结果。可以清除全部筛选，或打开筛选面板调整条件。',
        primary: FilledButton.icon(
          key: LibrarySmokeKeys.emptyClearFilters,
          onPressed: onClearFilters,
          icon: const Icon(Icons.filter_alt_off_rounded),
          label: const Text('清除全部筛选'),
        ),
        secondary: TextButton.icon(
          key: LibrarySmokeKeys.emptyOpenFilters,
          onPressed: onOpenFilters,
          icon: const Icon(Icons.tune_rounded),
          label: const Text('查看筛选条件'),
        ),
      );
    }
    return _RecoveryContent(
      icon: Icons.video_library_outlined,
      title: message ?? '当前没有可显示的视频',
      description: '可以返回全部视频，或从左侧切换其它媒体来源。',
    );
  }
}

/** 空状态共享的紧凑排版，保证窄窗口与 150% 文字缩放仍可换行。 */
class _RecoveryContent extends StatelessWidget {
  const _RecoveryContent({
    required this.icon,
    required this.title,
    required this.description,
    this.primary,
    this.secondary,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: libraryAccent),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: libraryText,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: libraryTextMuted, height: 1.45),
                ),
                if (primary != null) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [primary!, if (secondary != null) secondary!],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}
