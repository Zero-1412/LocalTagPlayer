import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/tag_rules.dart';
import 'library_sidebar_brand.dart';
import 'library_collapsed_sidebar_items.dart';
import 'library_smoke_keys.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

/**
 * 左侧功能栏的图标折叠态。
 *
 * 所有主入口仍保留为真实按钮并提供 tooltip；本地 root 以文件夹图标继续可达，移除
 * 等低频管理动作统一从“目录管理”进入，避免在 76px 宽度内堆叠危险按钮。
 */
class CollapsedLibrarySidebar extends StatelessWidget {
  const CollapsedLibrarySidebar({
    required this.roots,
    required this.selectedLocalLibraryPath,
    required this.mediaSelected,
    required this.recentSelected,
    required this.favoritesSelected,
    required this.localLibrarySelected,
    required this.isScanning,
    required this.onToggleCollapsed,
    required this.onShowAllLibrary,
    required this.onOpenRecentPlayback,
    required this.onFavoritesToggle,
    required this.onOpenSimilarVideos,
    required this.onOpenDirectoryManager,
    required this.onOpenMissingRelink,
    required this.onOpenTagManager,
    required this.onRescan,
    required this.onPickFolder,
    required this.onOpenLocalLibraryRoot,
    required this.onOpenSettings,
  });

  final List<String> roots;
  final String? selectedLocalLibraryPath;
  final bool mediaSelected;
  final bool recentSelected;
  final bool favoritesSelected;
  final bool localLibrarySelected;
  final bool isScanning;
  final VoidCallback? onToggleCollapsed;
  final VoidCallback onShowAllLibrary;
  final VoidCallback onOpenRecentPlayback;
  final VoidCallback onFavoritesToggle;
  /** 折叠状态下仍可打开重复下载候选页。 */
  final VoidCallback onOpenSimilarVideos;
  final VoidCallback onOpenDirectoryManager;
  final VoidCallback onOpenMissingRelink;
  /** 折叠状态下仍可打开标签中心。 */
  final VoidCallback onOpenTagManager;
  final VoidCallback onRescan;
  final VoidCallback onPickFolder;
  final ValueChanged<String> onOpenLocalLibraryRoot;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      child: Column(
        children: [
          LibrarySidebarBrandToggle(
            collapsed: true,
            dimension: 42,
            onToggleCollapsed: onToggleCollapsed,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                CollapsedSidebarItem(
                  icon: Icons.grid_view_rounded,
                  tooltip: '媒体库',
                  selected: mediaSelected,
                  onTap: onShowAllLibrary,
                ),
                CollapsedSidebarItem(
                  icon: Icons.history_rounded,
                  tooltip: '继续观看',
                  selected: recentSelected,
                  onTap: onOpenRecentPlayback,
                ),
                CollapsedSidebarItem(
                  icon: Icons.auto_awesome_outlined,
                  tooltip: '本地收藏',
                  selected: favoritesSelected,
                  onTap: onFavoritesToggle,
                ),
                CollapsedSidebarItem(
                  icon: Icons.find_replace_outlined,
                  tooltip: '相似视频',
                  selected: false,
                  onTap: onOpenSimilarVideos,
                ),
                CollapsedSidebarItem(
                  key: LibrarySmokeKeys.sidebarTagCenter,
                  icon: Icons.sell_outlined,
                  tooltip: '标签中心',
                  selected: false,
                  onTap: onOpenTagManager,
                ),
                const CollapsedSidebarDivider(),
                CollapsedSidebarItem(
                  icon: Icons.folder_copy_outlined,
                  tooltip: '目录管理',
                  selected: false,
                  onTap: onOpenDirectoryManager,
                ),
                CollapsedSidebarItem(
                  icon: Icons.link_off_rounded,
                  tooltip: '缺失与重新关联',
                  selected: false,
                  onTap: onOpenMissingRelink,
                ),
                CollapsedSidebarItem(
                  icon: isScanning
                      ? Icons.hourglass_empty_rounded
                      : Icons.sync_rounded,
                  tooltip: isScanning ? '扫描中' : '重新扫描',
                  selected: false,
                  onTap: isScanning || roots.isEmpty ? null : onRescan,
                ),
                CollapsedSidebarItem(
                  icon: Icons.create_new_folder_outlined,
                  tooltip: '新增本地库路径',
                  selected: false,
                  onTap: isScanning ? null : onPickFolder,
                ),
                if (roots.isNotEmpty) const CollapsedSidebarDivider(),
                for (final root in roots)
                  CollapsedSidebarItem(
                    icon: Icons.folder_outlined,
                    tooltip: p.basename(root).isEmpty ? root : p.basename(root),
                    selected: localLibrarySelected &&
                        selectedLocalLibraryPath != null &&
                        TagRules.pathKey(selectedLocalLibraryPath!) ==
                            TagRules.pathKey(root),
                    onTap: () => onOpenLocalLibraryRoot(root),
                  ),
              ],
            ),
          ),
          CollapsedSidebarItem(
            icon: Icons.settings_outlined,
            tooltip: '设置',
            selected: false,
            onTap: onOpenSettings,
          ),
        ],
      ),
    );
  }
}
