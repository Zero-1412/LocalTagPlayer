import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/tag_rules.dart';
import '../../models/platform_models.dart';
import '../app_theme_tokens.dart';
import 'library_collapsed_sidebar.dart';
import 'library_desktop_scroll_behavior.dart';
import 'library_panel_content_transition.dart';
import 'library_sidebar_brand.dart';
import 'library_sidebar_items.dart';
import 'library_smoke_keys.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

/** 主功能栏专用的无可见滚动条行为，继续保留桌面拖拽设备。 */
class _LibrarySidebarScrollBehavior extends DesktopDragScrollBehavior {
  const _LibrarySidebarScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}

class LibrarySidebar extends StatelessWidget {
  const LibrarySidebar({
    required this.roots,
    required this.tags,
    required this.tagGroups,
    required this.resultCounts,
    required this.selectedLocalLibraryPath,
    required this.childParentTag,
    required this.childTags,
    required this.selectedChildTags,
    required this.selectedGroupTagIds,
    required this.excludedTagIds,
    required this.favoriteCount,
    required this.missingCount,
    required this.favoriteVideosSelected,
    required this.recentPlaybackSelected,
    required this.localLibrarySelected,
    required this.selectedTags,
    required this.isScanning,
    required this.dense,
    required this.onPickFolder,
    required this.onShowAllLibrary,
    required this.onRescan,
    required this.onRemoveLocalLibraryRoot,
    required this.onFavoritesToggle,
    required this.onOpenRecentPlayback,
    required this.onOpenLocalLibraryRoot,
    required this.onOpenDirectoryManager,
    required this.onOpenMissingRelink,
    required this.onOpenTagManager,
    required this.onOpenSettings,
    required this.onChildTagToggle,
    required this.onClearChildTags,
    required this.onGroupTagToggle,
    required this.onGroupTagExcludeToggle,
    this.collapsed = false,
    this.onToggleCollapsed,
    this.width,
  });

  final List<String> roots;
  final List<String> tags;
  final List<TagGroup> tagGroups;
  final Map<String, int> resultCounts;
  final String? selectedLocalLibraryPath;
  final String? childParentTag;
  final List<String> childTags;
  final Set<String> selectedChildTags;
  final Map<String, Set<String>> selectedGroupTagIds;
  final Set<String> excludedTagIds;
  final int favoriteCount;
  /** 保留稳定身份但当前路径失效的视频数量。 */
  final int missingCount;
  final bool favoriteVideosSelected;
  final bool recentPlaybackSelected;
  final bool localLibrarySelected;
  final Set<String> selectedTags;
  final bool isScanning;
  final bool dense;
  /** 为“本地媒体库”标题旁的紧凑加号保留目录选择动作。 */
  final VoidCallback onPickFolder;
  final VoidCallback onShowAllLibrary;
  final VoidCallback onRescan;
  final ValueChanged<String> onRemoveLocalLibraryRoot;
  final VoidCallback onFavoritesToggle;
  final VoidCallback onOpenRecentPlayback;
  final ValueChanged<String> onOpenLocalLibraryRoot;
  final VoidCallback onOpenDirectoryManager;
  /** 打开缺失视频与重新关联管理页。 */
  final VoidCallback onOpenMissingRelink;
  /** 打开标签中心；只移动导航入口，不改变标签管理业务。 */
  final VoidCallback onOpenTagManager;
  final VoidCallback onOpenSettings;
  final ValueChanged<String> onChildTagToggle;
  final VoidCallback onClearChildTags;
  final ValueChanged<TagItem> onGroupTagToggle;
  final ValueChanged<TagItem> onGroupTagExcludeToggle;
  /** 是否只显示图标导航；折叠只影响布局，不改变任何媒体库状态。 */
  final bool collapsed;
  /** 在完整侧栏与图标侧栏之间切换。 */
  final VoidCallback? onToggleCollapsed;
  /** expanded 主界面按窗口比例计算出的侧栏宽度；medium 继续使用默认密度宽度。 */
  final double? width;
  @override
  Widget build(BuildContext context) {
    final sidebarWidth = collapsed ? 76.0 : width ?? (dense ? 248 : 274);
    final accessibility = AppAccessibilityScope.of(context);
    final sidebar = AnimatedContainer(
      key: LibrarySmokeKeys.sidebarSurface,
      duration: accessibility.motionDuration(libraryPanelMotionDuration),
      curve: libraryPanelMotionCurve,
      width: sidebarWidth,
      height: MediaQuery.sizeOf(context).height,
      // 侧栏使用稳定结构描边；开合不叠加强阴影，避免主界面左右两侧争夺内容焦点。
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: accessibility.highContrast
                ? libraryTextMuted
                : libraryBorder.withValues(alpha: 0.82),
          ),
        ),
      ),
      child: ClipRect(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: appShell,
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 内容跟随目标状态切换，并在目标宽度中完成布局；外层只负责连续裁剪，
                // 避免动画中途跨过固定阈值时整棵侧栏内容突然替换。
                final content = collapsed
                    ? CollapsedLibrarySidebar(
                        roots: roots,
                        selectedLocalLibraryPath: selectedLocalLibraryPath,
                        mediaSelected: !recentPlaybackSelected &&
                            !favoriteVideosSelected &&
                            !localLibrarySelected,
                        recentSelected: recentPlaybackSelected,
                        favoritesSelected: favoriteVideosSelected,
                        localLibrarySelected: localLibrarySelected,
                        isScanning: isScanning,
                        onToggleCollapsed: onToggleCollapsed,
                        onShowAllLibrary: onShowAllLibrary,
                        onOpenRecentPlayback: onOpenRecentPlayback,
                        onFavoritesToggle: onFavoritesToggle,
                        onOpenDirectoryManager: onOpenDirectoryManager,
                        onOpenMissingRelink: onOpenMissingRelink,
                        onOpenTagManager: onOpenTagManager,
                        onRescan: onRescan,
                        onPickFolder: onPickFolder,
                        onOpenLocalLibraryRoot: onOpenLocalLibraryRoot,
                        onOpenSettings: onOpenSettings,
                      )
                    : Padding(
                        padding: EdgeInsets.fromLTRB(
                            dense ? 14 : 18, 16, dense ? 14 : 18, 16),
                        child: Column(
                          children: [
                            Expanded(
                              child: ScrollConfiguration(
                                behavior: const _LibrarySidebarScrollBehavior(),
                                child: ListView(
                                  padding: EdgeInsets.zero,
                                  children: [
                                    LibrarySidebarBrand(
                                      onToggleCollapsed: onToggleCollapsed,
                                    ),
                                    const SizedBox(height: 22),
                                    const LibrarySidebarSectionLabel(
                                      label: '浏览',
                                    ),
                                    const SizedBox(height: 8),
                                    LibrarySidebarNavItem(
                                      icon: Icons.grid_view_rounded,
                                      label: '\u5a92\u4f53\u5e93',
                                      selected: !recentPlaybackSelected &&
                                          !favoriteVideosSelected &&
                                          !localLibrarySelected,
                                      trailing: roots.isEmpty
                                          ? null
                                          : roots.length.toString(),
                                      onTap: onShowAllLibrary,
                                    ),
                                    LibrarySidebarNavItem(
                                      icon: Icons.history_rounded,
                                      label: '继续观看',
                                      selected: recentPlaybackSelected,
                                      trailing: null,
                                      onTap: onOpenRecentPlayback,
                                    ),
                                    LibrarySidebarNavItem(
                                      icon: Icons.auto_awesome_outlined,
                                      label: '\u672c\u5730\u6536\u85cf',
                                      selected: favoriteVideosSelected,
                                      trailing: favoriteCount.toString(),
                                      onTap: onFavoritesToggle,
                                    ),
                                    LibrarySidebarNavItem(
                                      key: LibrarySmokeKeys.sidebarTagCenter,
                                      icon: Icons.sell_outlined,
                                      label: '标签中心',
                                      selected: false,
                                      onTap: onOpenTagManager,
                                    ),
                                    const SizedBox(height: 18),
                                    const LibrarySidebarSectionLabel(
                                      label: '资料库',
                                    ),
                                    const SizedBox(height: 8),
                                    LibrarySidebarNavItem(
                                      icon: Icons.folder_copy_outlined,
                                      label: '\u76ee\u5f55\u7ba1\u7406',
                                      selected: false,
                                      trailing: roots.isEmpty
                                          ? null
                                          : roots.length.toString(),
                                      onTap: onOpenDirectoryManager,
                                    ),
                                    LibrarySidebarNavItem(
                                      icon: Icons.link_off_rounded,
                                      label: '缺失与重新关联',
                                      selected: false,
                                      trailing: missingCount == 0
                                          ? null
                                          : missingCount.toString(),
                                      onTap: onOpenMissingRelink,
                                    ),
                                    LibrarySidebarNavItem(
                                      key: LibrarySmokeKeys.rescanButton,
                                      icon: isScanning
                                          ? Icons.hourglass_empty_rounded
                                          : Icons.sync_rounded,
                                      label: isScanning
                                          ? '\u626b\u63cf\u4e2d'
                                          : '\u91cd\u65b0\u626b\u63cf',
                                      selected: false,
                                      onTap: isScanning || roots.isEmpty
                                          ? null
                                          : onRescan,
                                    ),
                                    const SizedBox(height: 18),
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: LibrarySidebarSectionLabel(
                                            label:
                                                '\u672c\u5730\u5a92\u4f53\u5e93',
                                          ),
                                        ),
                                        IconButton(
                                          tooltip:
                                              '\u65b0\u589e\u672c\u5730\u5e93\u8def\u5f84',
                                          onPressed:
                                              isScanning ? null : onPickFolder,
                                          icon: const Icon(Icons.add_rounded,
                                              size: 18),
                                          color: const Color(0xffcbd5e1),
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                            width: 28,
                                            height: 28,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (roots.isEmpty)
                                      const Text(
                                        '\u70b9\u51fb + \u6dfb\u52a0\u672c\u5730\u89c6\u9891\u76ee\u5f55',
                                        style: TextStyle(
                                          color: Color(0xff718096),
                                          fontSize: 12,
                                          height: 1.35,
                                        ),
                                      )
                                    else
                                      SizedBox(
                                        height:
                                            math.min(220, 42.0 * roots.length),
                                        child: ScrollConfiguration(
                                          behavior:
                                              const _LibrarySidebarScrollBehavior(),
                                          child: ListView.builder(
                                            itemExtent: 42,
                                            padding: EdgeInsets.zero,
                                            itemCount: roots.length,
                                            itemBuilder: (context, index) {
                                              final root = roots[index];
                                              return LibrarySidebarLocalLibraryItem(
                                                path: root,
                                                selected:
                                                    selectedLocalLibraryPath !=
                                                            null &&
                                                        TagRules.pathKey(
                                                                selectedLocalLibraryPath!) ==
                                                            TagRules.pathKey(
                                                                root),
                                                onTap: () =>
                                                    onOpenLocalLibraryRoot(
                                                        root),
                                                onRemove: () =>
                                                    onRemoveLocalLibraryRoot(
                                                        root),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.035),
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.panel,
                                        ),
                                        border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.055),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          LibrarySidebarLibraryStat(
                                            label: '资料库',
                                            value: roots.length.toString(),
                                          ),
                                          const SizedBox(height: 8),
                                          LibrarySidebarLibraryStat(
                                            label: '\u6807\u7b7e',
                                            value: tags.length.toString(),
                                          ),
                                          const SizedBox(height: 8),
                                          LibrarySidebarLibraryStat(
                                            label: '\u5206\u7ec4',
                                            value: tagGroups.length.toString(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            LibrarySidebarNavItem(
                              icon: Icons.settings_outlined,
                              label: '\u8bbe\u7f6e',
                              selected: false,
                              onTap: onOpenSettings,
                            ),
                          ],
                        ),
                      );
                return AnimatedSwitcher(
                  duration: libraryPanelMotionDuration,
                  switchInCurve: libraryPanelMotionCurve,
                  switchOutCurve: libraryPanelMotionCurve,
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.topLeft,
                    clipBehavior: Clip.hardEdge,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  ),
                  transitionBuilder: (child, animation) {
                    final enteringCollapsed =
                        child.key == const ValueKey<bool>(true);
                    return LibraryPanelContentTransition(
                      animation: animation,
                      horizontalOffset: enteringCollapsed ? -0.28 : -0.14,
                      alignment: Alignment.centerLeft,
                      child: child,
                    );
                  },
                  child: OverflowBox(
                    key: ValueKey<bool>(collapsed),
                    alignment: Alignment.topLeft,
                    minWidth: sidebarWidth,
                    maxWidth: sidebarWidth,
                    minHeight: constraints.maxHeight,
                    maxHeight: constraints.maxHeight,
                    child: SizedBox(
                      width: sidebarWidth,
                      height: constraints.maxHeight,
                      child: content,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    // 侧栏所有嵌套列表统一继承无滚动条行为，避免展开态与折叠态分别维护。
    return ScrollConfiguration(
      behavior: const _LibrarySidebarScrollBehavior(),
      child: sidebar,
    );
  }
}
