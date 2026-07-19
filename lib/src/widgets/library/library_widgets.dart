import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/layout_size.dart';
import '../../core/playback_settings.dart';
import '../../core/tag_rules.dart';
import '../../models/library_sort.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../pages/player/player_open_request_controller.dart';
import '../../services/media/thumbnail_service.dart';
import '../app_theme_tokens.dart';
import '../design_system/app_interaction_surface.dart';
import 'library_smoke_keys.dart';
import 'library_sort_control.dart';
import 'library_video_results.dart';

/** 顶栏搜索框在主布局或窄行中占据剩余宽度，防止动作按钮溢出。 */
bool referenceTopBarSearchShouldFillRow(
  LayoutSize layoutSize,
  double rowWidth,
) {
  return layoutSize != LayoutSize.expanded || rowWidth < 1120;
}

/**
 * 顶栏与首行视频卡片之间的垂直留白。
 *
 * 搜索、筛选状态和结果卡片属于不同视觉层级，保留明确间距可以避免首行缩略图紧贴
 * 搜索表面；该值只影响布局，不改变搜索输入或筛选刷新链路。
 */
const double libraryTopBarBottomSpacing = 18;

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

class DesktopDragScrollBehavior extends MaterialScrollBehavior {
  const DesktopDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

/**
 * 主功能栏专用的无可见滚动条行为。
 *
 * 侧栏仍保留滚轮、触控板和鼠标拖拽滚动，只隐藏桌面端自动绘制的长滚动条，
 * 避免计数文字和本地库动作被滚动条轨道遮挡。
 */
class _LibrarySidebarScrollBehavior extends DesktopDragScrollBehavior {
  const _LibrarySidebarScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

Color libraryGroupColor(String groupId) {
  return switch (groupId) {
    'folder.primary' => appAccentViolet,
    'folder.child' => const Color(0xff6366f1),
    'manual' => const Color(0xff0f766e),
    _ => const Color(0xff64748b),
  };
}

String formatCount(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index += 1) {
    final remaining = text.length - index;
    buffer.write(text[index]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

Map<String, List<TagItem>> childTagItemsByParentId(
  Iterable<TagItem> tags,
  TagQueryContext context,
) {
  final primaryByName = <String, TagItem>{};
  for (final tag in tags) {
    if (_isFolderPrimaryDiscoveryTag(tag)) {
      primaryByName[tag.name] = tag;
      if (tag.displayName != null) {
        primaryByName[tag.displayName!] = tag;
      }
    }
  }

  final grouped = <String, List<TagItem>>{};
  for (final tag in tags) {
    if (!_isFolderChildDiscoveryTag(tag)) {
      continue;
    }
    final parentKey = tag.parentId?.trim();
    if (parentKey == null || parentKey.isEmpty) {
      continue;
    }
    final parent = context.tagsById[parentKey] ?? primaryByName[parentKey];
    if (parent == null) {
      continue;
    }
    grouped.putIfAbsent(parent.id, () => <TagItem>[]).add(tag);
  }
  for (final entry in grouped.entries) {
    entry.value.sort((a, b) {
      final byCount = b.usageCount.compareTo(a.usageCount);
      if (byCount != 0) {
        return byCount;
      }
      return (a.displayName ?? a.name).compareTo(b.displayName ?? b.name);
    });
  }
  return grouped;
}

List<TagItem> strictChildItemsForParent(
  TagItem parent,
  Map<String, List<TagItem>> childItemsByParent,
) {
  return childItemsByParent[parent.id] ?? const <TagItem>[];
}

List<TagItem> displayChildItemsForPrimary(
  TagItem parent,
  Map<String, List<TagItem>> childItemsByParent,
) {
  return strictChildItemsForParent(parent, childItemsByParent)
      .where((child) => !TagRules.sameTag(
            child.displayName ?? child.name,
            TagRules.defaultAlbumTag,
          ))
      .toList();
}

String? secondaryTagParentLabel(
  TagItem tag, {
  required bool showParentLabel,
}) {
  if (!showParentLabel) {
    return null;
  }
  final parentLabel = tag.parentId?.trim();
  return parentLabel == null || parentLabel.isEmpty ? null : parentLabel;
}

bool secondaryTagNameHasConflict(
  TagItem tag,
  Iterable<TagItem> allSecondaryTags,
) {
  final name = (tag.displayName ?? tag.name).trim().toLowerCase();
  if (name.isEmpty) {
    return false;
  }
  var matches = 0;
  for (final candidate in allSecondaryTags) {
    final candidateName =
        (candidate.displayName ?? candidate.name).trim().toLowerCase();
    if (candidateName != name) {
      continue;
    }
    matches += 1;
    if (matches > 1) {
      return true;
    }
  }
  return false;
}

/**
 * 判断标签是否可作为右侧发现面板的一级文件夹标签。
 *
 * 一级标签只能来自本地媒体库 root 下第一层目录；历史数据里如果有二级或 manual 标签被错误写入
 * `folder.primary` 组，这里会在展示层过滤掉，避免破坏文件树层级。
 */
bool _isFolderPrimaryDiscoveryTag(TagItem tag) {
  return tag.source == TagSource.folder &&
      tag.groupId == 'folder.primary' &&
      tag.parentId == null &&
      tag.id.startsWith('folder.primary:');
}

/**
 * 判断标签是否可作为右侧发现面板的二级文件夹标签。
 *
 * 二级标签必须有父级一级目录，且只在一级展开卡或“全部二级标签”页签中展示。
 */
bool _isFolderChildDiscoveryTag(TagItem tag) {
  final parentId = tag.parentId?.trim();
  return tag.source == TagSource.folder &&
      tag.groupId == 'folder.child' &&
      parentId != null &&
      parentId.isNotEmpty &&
      tag.id.startsWith('folder.child:');
}

/**
 * 从真实本地媒体库路径派生右侧发现面板的文件夹标签。
 *
 * 该函数不信任历史 `tags` 表里的 folder.primary / folder.child 记录，而是按当前视频路径相对
 * 媒体库 root 的层级重新计算：root 下一层是一级，下一层是二级。多个 root 命中时优先使用最上层
 * root，避免 `X:\test-media\崩坏三` 这样的子 root 把 `李素裳` 误当一级。
 */
List<TagGroup> folderTagGroupsFromLibraryPaths({
  required Iterable<VideoItem> videos,
  required Iterable<String> roots,
  required Iterable<TagGroup> templates,
}) {
  final primaryCounts = <String, int>{};
  final childCounts = <String, int>{};
  final childParents = <String, String>{};
  for (final item in videos) {
    final segments = TagRules.relativeFolderSegmentsForBestRoot(
      item.path,
      roots: roots,
      fallbackRoot: item.rootPath,
    );
    if (segments.isEmpty) {
      continue;
    }
    final primary = segments.first;
    final primaryId = TagRules.tagIdFor(
      name: primary,
      groupId: 'folder.primary',
    );
    primaryCounts[primaryId] = (primaryCounts[primaryId] ?? 0) + 1;
    final child = segments.length > 1 ? segments[1] : TagRules.defaultAlbumTag;
    final childId = TagRules.tagIdFor(
      name: child,
      groupId: 'folder.child',
      parentId: primary,
    );
    childCounts[childId] = (childCounts[childId] ?? 0) + 1;
    childParents[childId] = primary;
  }

  final templateById = {for (final group in templates) group.id: group};
  final primaryTemplate = templateById['folder.primary'] ??
      const TagGroup(id: 'folder.primary', name: 'folder.primary', items: []);
  final childTemplate = templateById['folder.child'] ??
      const TagGroup(id: 'folder.child', name: 'folder.child', items: []);

  TagGroup copyTemplate(TagGroup template, List<TagItem> items) => TagGroup(
        id: template.id,
        name: template.name,
        displayName: template.displayName,
        sortOrder: template.sortOrder,
        allowMultiSelect: template.allowMultiSelect,
        defaultLogic: template.defaultLogic,
        items: items,
        excludedItems: template.excludedItems,
      );

  final primaryItems = [
    for (final entry in primaryCounts.entries)
      TagItem(
        id: entry.key,
        name: entry.key.split(':').last,
        displayName: entry.key.split(':').last,
        groupId: 'folder.primary',
        source: TagSource.folder,
        usageCount: entry.value,
      ),
  ]..sort((a, b) {
      final byCount = b.usageCount.compareTo(a.usageCount);
      if (byCount != 0) {
        return byCount;
      }
      return (a.displayName ?? a.name).compareTo(b.displayName ?? b.name);
    });

  final childItems = [
    for (final entry in childCounts.entries)
      TagItem(
        id: entry.key,
        name: entry.key.split(':').last,
        displayName: entry.key.split(':').last,
        groupId: 'folder.child',
        parentId: childParents[entry.key],
        source: TagSource.folder,
        usageCount: entry.value,
      ),
  ]..sort((a, b) {
      final byCount = b.usageCount.compareTo(a.usageCount);
      if (byCount != 0) {
        return byCount;
      }
      return (a.displayName ?? a.name).compareTo(b.displayName ?? b.name);
    });

  return [
    copyTemplate(primaryTemplate, primaryItems),
    copyTemplate(childTemplate, childItems),
  ];
}

List<TagGroup> primaryTagGroupsForDiscovery(List<TagGroup> groups) {
  return [
    for (final group in groups)
      if (group.id == 'folder.primary')
        TagGroup(
          id: group.id,
          name: group.name,
          displayName: group.displayName,
          sortOrder: group.sortOrder,
          allowMultiSelect: group.allowMultiSelect,
          defaultLogic: group.defaultLogic,
          items: [
            for (final tag in group.items)
              if (_isFolderPrimaryDiscoveryTag(tag)) tag,
          ],
          excludedItems: group.excludedItems,
        ),
  ];
}

List<TagItem> secondaryTagsForDiscovery(
  List<TagGroup> groups,
  Map<String, int> resultCounts,
) {
  final tags = <TagItem>[
    for (final group in groups)
      if (group.id == 'folder.child')
        for (final tag in group.items)
          if (_isFolderChildDiscoveryTag(tag) &&
              !TagRules.sameTag(
                tag.displayName ?? tag.name,
                TagRules.defaultAlbumTag,
              ))
            tag,
  ];
  tags.sort((a, b) {
    final byCount = (resultCounts[b.id] ?? b.usageCount)
        .compareTo(resultCounts[a.id] ?? a.usageCount);
    if (byCount != 0) {
      return byCount;
    }
    return (a.displayName ?? a.name).compareTo(b.displayName ?? b.name);
  });
  return tags;
}

/**
 * 左右侧栏共用的内容进入与离开动画。
 *
 * 宽度变化由外层布局负责；这里只组合淡入、横向位移和轻微缩放，让面板状态切换
 * 更容易被感知，同时保持子树身份和业务状态不变。
 */
class LibraryPanelContentTransition extends StatelessWidget {
  const LibraryPanelContentTransition({
    super.key,
    required this.animation,
    required this.horizontalOffset,
    required this.alignment,
    required this.child,
  });

  /** AnimatedSwitcher 提供的进入或离开进度。 */
  final Animation<double> animation;

  /** 内容起始位置相对自身宽度的横向偏移。 */
  final double horizontalOffset;

  /** 缩放锚点；左栏固定左侧，右栏固定右侧。 */
  final Alignment alignment;

  /** 不参与额外重建的侧栏内容。 */
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = animation.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: motion,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(horizontalOffset, 0),
          end: Offset.zero,
        ).animate(motion),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.965, end: 1).animate(motion),
          alignment: alignment,
          child: child,
        ),
      ),
    );
  }
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
                    ? _CollapsedLibrarySidebar(
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

/**
 * 左侧功能栏的图标折叠态。
 *
 * 所有主入口仍保留为真实按钮并提供 tooltip；本地 root 以文件夹图标继续可达，移除
 * 等低频管理动作统一从“目录管理”进入，避免在 76px 宽度内堆叠危险按钮。
 */
class _CollapsedLibrarySidebar extends StatelessWidget {
  const _CollapsedLibrarySidebar({
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
          _SidebarBrandToggle(
            collapsed: true,
            dimension: 42,
            onToggleCollapsed: onToggleCollapsed,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _CollapsedSidebarItem(
                  icon: Icons.grid_view_rounded,
                  tooltip: '媒体库',
                  selected: mediaSelected,
                  onTap: onShowAllLibrary,
                ),
                _CollapsedSidebarItem(
                  icon: Icons.history_rounded,
                  tooltip: '继续观看',
                  selected: recentSelected,
                  onTap: onOpenRecentPlayback,
                ),
                _CollapsedSidebarItem(
                  icon: Icons.auto_awesome_outlined,
                  tooltip: '本地收藏',
                  selected: favoritesSelected,
                  onTap: onFavoritesToggle,
                ),
                _CollapsedSidebarItem(
                  key: LibrarySmokeKeys.sidebarTagCenter,
                  icon: Icons.sell_outlined,
                  tooltip: '标签中心',
                  selected: false,
                  onTap: onOpenTagManager,
                ),
                const _CollapsedSidebarDivider(),
                _CollapsedSidebarItem(
                  icon: Icons.folder_copy_outlined,
                  tooltip: '目录管理',
                  selected: false,
                  onTap: onOpenDirectoryManager,
                ),
                _CollapsedSidebarItem(
                  icon: Icons.link_off_rounded,
                  tooltip: '缺失与重新关联',
                  selected: false,
                  onTap: onOpenMissingRelink,
                ),
                _CollapsedSidebarItem(
                  icon: isScanning
                      ? Icons.hourglass_empty_rounded
                      : Icons.sync_rounded,
                  tooltip: isScanning ? '扫描中' : '重新扫描',
                  selected: false,
                  onTap: isScanning || roots.isEmpty ? null : onRescan,
                ),
                _CollapsedSidebarItem(
                  icon: Icons.create_new_folder_outlined,
                  tooltip: '新增本地库路径',
                  selected: false,
                  onTap: isScanning ? null : onPickFolder,
                ),
                if (roots.isNotEmpty) const _CollapsedSidebarDivider(),
                for (final root in roots)
                  _CollapsedSidebarItem(
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
          _CollapsedSidebarItem(
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

/** 图标折叠态的单个入口；选中态仅用背景和强调色表达。 */
class _CollapsedSidebarItem extends StatelessWidget {
  const _CollapsedSidebarItem({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: onTap != null,
          selected: selected,
          label: tooltip,
          child: Material(
            color: selected ? const Color(0xff2b3650) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: SizedBox.square(
                dimension: 46,
                child: Icon(
                  icon,
                  size: 21,
                  color: selected
                      ? appAccentViolet
                      : onTap == null
                          ? const Color(0xff526077)
                          : const Color(0xffa7b4c6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/** 折叠导航的轻量分组线。 */
class _CollapsedSidebarDivider extends StatelessWidget {
  const _CollapsedSidebarDivider();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Divider(height: 1, color: Color(0xff2a3548)),
      );
}

class LibrarySidebarSectionLabel extends StatelessWidget {
  const LibrarySidebarSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xff7f8ca1),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.45,
      ),
    );
  }
}

class LibrarySidebarBrand extends StatelessWidget {
  const LibrarySidebarBrand({this.onToggleCollapsed});

  /** 通过品牌图标收起主功能栏；为 null 时保持只读品牌头。 */
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _SidebarBrandToggle(
          collapsed: false,
          dimension: 36,
          onToggleCollapsed: onToggleCollapsed,
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '\u672c\u5730\u6807\u7b7e\u64ad\u653e\u5668',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'LOCAL LIBRARY',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xff95a3b8),
                  fontSize: 9,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/**
 * 品牌区与主功能栏折叠状态共用的唯一切换入口。
 *
 * 展开态三角向右，折叠态三角向下；按钮使用克制的紫色品牌底，
 * 不依赖发光阴影表达可点击性，也不额外占用侧栏横向空间。
 */
class _SidebarBrandToggle extends StatelessWidget {
  const _SidebarBrandToggle({
    required this.collapsed,
    required this.dimension,
    required this.onToggleCollapsed,
  });

  /** true 表示当前仅显示图标轨道。 */
  final bool collapsed;

  /** 展开和折叠布局各自使用的品牌方块尺寸。 */
  final double dimension;

  /** 切换主功能栏状态；为空时品牌图标保持只读。 */
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final tooltip = collapsed ? '展开功能栏' : '折叠功能栏';
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: onToggleCollapsed != null,
        label: tooltip,
        child: Container(
          key: LibrarySmokeKeys.sidebarCollapseToggle,
          width: dimension,
          height: dimension,
          decoration: BoxDecoration(
            color: appAccentViolet,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.control),
              onTap: onToggleCollapsed,
              child: AnimatedRotation(
                turns: collapsed ? 0.25 : 0,
                duration: appMotionDuration,
                curve: appMotionCurve,
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: collapsed ? 28 : 29,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LibrarySidebarLibraryStat extends StatelessWidget {
  const LibrarySidebarLibraryStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xff8ea0b8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xffcbd5e1),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class LibrarySidebarLocalLibraryItem extends StatelessWidget {
  const LibrarySidebarLocalLibraryItem({
    required this.path,
    required this.selected,
    required this.onTap,
    required this.onRemove,
  });

  /**
   * 标签库中显示的标签名。
   */
  final String path;

  /**
   * 当前标签是否已参与筛选，用于给列表项提供选中态。
   */
  final bool selected;

  /**
   * 点击标签后切换媒体库筛选。
   */
  final VoidCallback onTap;

  /**
   * 从“我的标签库”快捷列表移除；不删除真实标签或视频关联。
   */
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final label = p.basename(path).isEmpty ? path : p.basename(path);
    return Semantics(
      button: true,
      selected: selected,
      label: LibrarySmokeSemantics.localRoot(path),
      value: path,
      child: Material(
        key: LibrarySmokeKeys.localRoot(path),
        color: selected ? const Color(0xff263244) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(left: 10, right: 2),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 17,
                  color: selected ? appAccentViolet : const Color(0xff94a3b8),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xffcbd5e1),
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '\u79fb\u9664\u672c\u5730\u5e93\u8def\u5f84',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: const Color(0xff94a3b8),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LibrarySidebarNavItem extends StatelessWidget {
  const LibrarySidebarNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        button: onTap != null,
        selected: selected,
        label: label,
        child: Material(
          color: selected
              ? appAccentViolet.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: onTap,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? appAccentViolet : libraryTextMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? libraryText : const Color(0xffb8c3d3),
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (trailing != null)
                    Text(
                      trailing!,
                      style: const TextStyle(
                        color: Color(0xff94a3b8),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/** 单行筛选工具栏中一个可移除筛选项的轻量描述。 */
class _FilterToolbarEntry {
  const _FilterToolbarEntry({
    required this.label,
    required this.onRemove,
    this.icon,
  });

  final String label;
  final VoidCallback onRemove;
  final IconData? icon;
}

/**
 * 顶栏左侧独立搜索表面。
 *
 * 搜索区域只表达“输入查询”的意图，不再混入已生效标签或结果数量；
 * 真实 [TextField] / controller 输入链路保持不变，标签状态由右侧低对比度区域单独展示。
 */
class _LibrarySearchSurface extends StatefulWidget {
  const _LibrarySearchSurface({
    required this.controller,
    required this.searchFocusNode,
    required this.compact,
    required this.keywordActive,
    required this.onSearchChanged,
    required this.onClearKeyword,
  });

  /** 页面持有的唯一搜索文本控制器。 */
  final TextEditingController controller;

  /** 与 `Ctrl+K`、真实键盘和自动化输入共享的焦点节点。 */
  final FocusNode searchFocusNode;

  /** 紧凑布局使用更短提示并降低内部留白。 */
  final bool compact;

  /** 关键词存在时强调边框，并提供独立清除入口。 */
  final bool keywordActive;

  /** 搜索文本变化统一进入页面已有的筛选刷新链路。 */
  final ValueChanged<String> onSearchChanged;

  /** 只清除关键词，不改变其它标签条件。 */
  final VoidCallback onClearKeyword;

  @override
  State<_LibrarySearchSurface> createState() => _LibrarySearchSurfaceState();
}

/** 只保存搜索表面的 hover/focus 视觉状态，不介入关键词和筛选业务状态。 */
class _LibrarySearchSurfaceState extends State<_LibrarySearchSurface> {
  /** 鼠标是否停留在搜索表面；只用于轻量颜色反馈。 */
  var _hovered = false;

  /** 真实搜索输入是否持有键盘焦点。 */
  var _focused = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.searchFocusNode.hasFocus;
    widget.searchFocusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _LibrarySearchSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchFocusNode == widget.searchFocusNode) {
      return;
    }
    oldWidget.searchFocusNode.removeListener(_handleFocusChanged);
    _focused = widget.searchFocusNode.hasFocus;
    widget.searchFocusNode.addListener(_handleFocusChanged);
  }

  /** 同步真实 TextField 焦点，让边框反馈与键盘焦点保持一致。 */
  void _handleFocusChanged() {
    if (mounted && _focused != widget.searchFocusNode.hasFocus) {
      setState(() => _focused = widget.searchFocusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    widget.searchFocusNode.removeListener(_handleFocusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    final compact = widget.compact;
    final keywordActive = widget.keywordActive;
    final outline = accessibility.highContrast
        ? appAccentViolet
        : _focused
            ? appAccentViolet
            : keywordActive
                ? appAccentViolet.withValues(alpha: 0.62)
                : _hovered
                    ? libraryTextMuted.withValues(alpha: 0.64)
                    : libraryBorder;
    final surface = _hovered && !_focused
        ? Color.alphaBlend(
            appAccentViolet.withValues(alpha: 0.045),
            librarySurface,
          )
        : librarySurface;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        key: LibrarySmokeKeys.searchSurface,
        height: compact ? 44 : 50,
        duration: accessibility.fadeDuration(AppMotion.hover),
        curve: AppMotion.standardCurve,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: outline,
            width: accessibility.highContrast || _focused ? 1.5 : 1,
          ),
          boxShadow: _focused
              ? <BoxShadow>[
                  BoxShadow(
                    color: appAccentViolet.withValues(alpha: 0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : librarySoftShadow,
        ),
        child: Row(
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: compact ? AppSpacing.sm : AppSpacing.md,
                right: AppSpacing.xs,
              ),
              child: Icon(
                Icons.search_rounded,
                size: compact ? 20 : 22,
                color: _focused || keywordActive
                    ? appAccentViolet
                    : libraryTextMuted,
              ),
            ),
            Expanded(
              child: SizedBox(
                key: LibrarySmokeKeys.searchInputLane,
                /**
               * 必须保持为 TextField，而不是把输入模拟成 GestureDetector 或 SearchBar；
               * 真实键盘、自动化输入和 controller 改写因此继续触发同一条 onChanged 链路。
               */
                child: TextField(
                  key: LibrarySmokeKeys.searchField,
                  controller: widget.controller,
                  focusNode: widget.searchFocusNode,
                  textInputAction: TextInputAction.search,
                  onChanged: widget.onSearchChanged,
                  onSubmitted: widget.onSearchChanged,
                  cursorColor: appAccentViolet,
                  style: const TextStyle(
                    color: libraryText,
                    fontSize: AppTypography.body,
                    fontWeight: AppTypography.medium,
                  ),
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: compact ? 12 : 15,
                    ),
                    hintText: compact
                        ? '\u641c\u7d22\u6587\u4ef6\u0020\u002f\u0020\u6807\u7b7e'
                        : '\u641c\u7d22\u6587\u4ef6\u540d\u002f\u6807\u7b7e\u002f\u8def\u5f84\u002e\u002e\u002e',
                    hintStyle: const TextStyle(
                      color: libraryTextMuted,
                      fontSize: AppTypography.body,
                      fontWeight: AppTypography.medium,
                    ),
                  ),
                ),
              ),
            ),
            if (keywordActive)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xxs),
                child: _LibraryStatusIconAction(
                  tooltip: '\u6e05\u9664\u641c\u7d22\u5173\u952e\u8bcd',
                  icon: Icons.close_rounded,
                  onPressed: widget.onClearKeyword,
                ),
              )
            else
              const SizedBox(width: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

/** 搜索与筛选状态共用的 40 像素图标动作，保留 tooltip、焦点和按压反馈。 */
class _LibraryStatusIconAction extends StatelessWidget {
  const _LibraryStatusIconAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  /** 鼠标悬停和辅助技术读取的动作名称。 */
  final String tooltip;

  /** 与动作语义对应的 Material 图标。 */
  final IconData icon;

  /** 点击或键盘激活回调。 */
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 40,
      child: Tooltip(
        message: tooltip,
        child: AppInteractionSurface(
          semanticLabel: tooltip,
          onTap: onPressed,
          padding: EdgeInsets.zero,
          borderRadius: AppRadius.control,
          backgroundColor: Colors.transparent,
          child: Center(
            child: Icon(icon, size: 17, color: libraryTextMuted),
          ),
        ),
      ),
    );
  }
}

/**
 * 搜索框右侧的筛选结果状态区域。
 *
 * 该区域使用低对比度实色表面，与更高权重的搜索输入形成明确层级；筛选标签只表达当前状态，
 * 空间不足时折叠为数量，不反向压缩搜索框或复制过滤计算。
 */
class _LibraryFilterStatusArea extends StatelessWidget {
  const _LibraryFilterStatusArea({
    required this.compact,
    required this.defaultLabel,
    required this.filters,
    required this.resultCount,
    this.resultCountLabel,
    required this.refreshing,
    required this.progressLabel,
    required this.progressValue,
    required this.progressPaused,
    required this.onToggleProgressPaused,
    required this.onCancelProgress,
    required this.onClearAll,
    this.showResultStatus = true,
  });

  /** 紧凑布局只展示最必要的状态。 */
  final bool compact;

  /** 非全库来源在没有筛选标签时展示的上下文名称。 */
  final String defaultLabel;

  /** 当前标签、收藏与排除条件。 */
  final List<_FilterToolbarEntry> filters;

  /** 当前筛选结果数量。 */
  final int resultCount;

  /** 非纯视频来源的精确统计文案，例如“40 个文件夹 · 0 个视频”。 */
  final String? resultCountLabel;

  /** 结果或旁路计数正在后台刷新。 */
  final bool refreshing;

  /** 扫描或媒体解析期间替代普通数量的状态。 */
  final String? progressLabel;

  /** 后台任务的确定型进度；null 表示未知总量。 */
  final double? progressValue;

  /** 后台任务是否暂停。 */
  final bool progressPaused;

  /** 暂停或继续后台任务。 */
  final VoidCallback? onToggleProgressPaused;

  /** 取消当前可取消的扫描任务；媒体解析等不可取消任务传 null。 */
  final VoidCallback? onCancelProgress;

  /** 一次清除全部筛选；为空时不绘制入口。 */
  final VoidCallback? onClearAll;

  /** 是否在本区域末端绘制结果数量；宽屏由排序控件之后的独立状态承担。 */
  final bool showResultStatus;

  @override
  Widget build(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    // 结果数量是高频导航反馈。桌面文字放大时预留最多 80px，避免五位数媒体库数量
    // 在仍有充足搜索空间的窗口里被省略；紧凑布局继续优先保护搜索与清除操作。
    final resultTextScaleAllowance = compact
        ? 0.0
        : (accessibility.textScaler.scale(1).clamp(1.0, 1.5) - 1) * 160;
    final resultLabel =
        progressLabel ?? resultCountLabel ?? '$resultCount \u4e2a\u89c6\u9891';
    return Semantics(
      container: true,
      liveRegion: refreshing || progressLabel != null,
      label: '\u5f53\u524d\u7b5b\u9009\u72b6\u6001\uff0c$resultLabel',
      child: Container(
        height: compact ? 44 : 50,
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
        decoration: BoxDecoration(
          color: accessibility.highContrast
              ? librarySurface
              : librarySurface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: accessibility.highContrast
                ? libraryTextMuted
                : libraryBorder.withValues(alpha: 0.82),
            width: accessibility.highContrast ? 1.5 : 1,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasFilters = filters.isNotEmpty;
            // 活动筛选及其清除入口是结果语义的一部分；窄空间下先让位普通数量，
            // 避免用户只能从结果变化猜测筛选是否仍然生效。扫描进度仍保持可见。
            final showInlineResultStatus = showResultStatus &&
                (progressLabel != null ||
                    !hasFilters ||
                    constraints.maxWidth >= 230);
            final trailingWidth = !showInlineResultStatus
                ? 0.0
                : progressLabel == null
                    ? resultCountLabel != null
                        ? 200.0 + resultTextScaleAllowance
                        : (compact ? 74.0 : 92.0 + resultTextScaleAllowance)
                    : 224.0;
            final showClearAll = onClearAll != null && hasFilters;
            final clearWidth = showClearAll ? 40.0 : 0.0;
            final filterBudget = math.max(
              0.0,
              constraints.maxWidth -
                  trailingWidth -
                  clearWidth -
                  (compact ? 8.0 : 14.0),
            );
            // 标签过多时只在状态区内折叠，不污染搜索输入。
            final maxVisibleFilters = filterBudget >= 145
                ? 2
                : filterBudget >= 92
                    ? 1
                    : 0;
            final visibleFilters = filters.take(maxVisibleFilters).toList();
            final hiddenCount = filters.length - visibleFilters.length;
            final showCollapsedCount = hiddenCount > 0 &&
                filterBudget >= (visibleFilters.isEmpty ? 56 : 42);
            final visibleFilterBudget = math.max(
              0.0,
              filterBudget -
                  (showCollapsedCount ? (visibleFilters.isEmpty ? 56 : 42) : 0),
            );
            final showSourceLabel = filters.isEmpty && filterBudget >= 96;
            return Row(
              children: [
                if (showSourceLabel) ...[
                  _SourceContextChip(label: defaultLabel),
                  const SizedBox(width: 6),
                ],
                if (visibleFilters.isNotEmpty)
                  ConstrainedBox(
                    key: LibrarySmokeKeys.searchFilterLane,
                    constraints: BoxConstraints(maxWidth: visibleFilterBudget),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: Row(
                        children: [
                          for (var index = 0;
                              index < visibleFilters.length;
                              index++) ...[
                            _CurrentFilterChip(
                              avatar: visibleFilters[index].icon == null
                                  ? null
                                  : Icon(
                                      visibleFilters[index].icon,
                                      size: 14,
                                      color: libraryTextMuted,
                                    ),
                              label: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: compact ? 68 : 84,
                                ),
                                child: Text(
                                  visibleFilters[index].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              onDeleted: visibleFilters[index].onRemove,
                            ),
                            if (index != visibleFilters.length - 1)
                              const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (visibleFilters.isNotEmpty) const SizedBox(width: 6),
                if (showCollapsedCount) ...[
                  _CollapsedFilterCount(
                    count: hiddenCount,
                    showFilterPrefix: visibleFilters.isEmpty,
                  ),
                  // 折叠数量已是窄宽最后一项时不保留无意义尾间距，避免 452px 桌面窗口溢出。
                  if (showClearAll || showInlineResultStatus)
                    const SizedBox(width: 6),
                ],
                if (showClearAll)
                  _LibraryStatusIconAction(
                    tooltip: '\u6e05\u7a7a\u5168\u90e8\u7b5b\u9009',
                    icon: Icons.filter_alt_off_outlined,
                    onPressed: onClearAll!,
                  ),
                if (showInlineResultStatus) ...[
                  const Spacer(),
                  SizedBox(
                    width: math.min(trailingWidth, constraints.maxWidth),
                    child: _FilterResultLine(
                      resultCount: resultCount,
                      resultCountLabel: resultCountLabel,
                      refreshing: refreshing,
                      progressLabel: progressLabel,
                      progressValue: progressValue,
                      progressPaused: progressPaused,
                      onToggleProgressPaused: onToggleProgressPaused,
                      onCancelProgress: onCancelProgress,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/** 非全库来源的只读上下文 chip，不伪装成可删除筛选条件。 */
class _SourceContextChip extends StatelessWidget {
  const _SourceContextChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: libraryBorder),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: libraryTextMuted,
          fontSize: AppTypography.caption,
          fontWeight: AppTypography.strong,
        ),
      ),
    );
  }
}

/** 被折叠的筛选数量，不承担交互，避免与真实筛选 chip 混淆。 */
class _CollapsedFilterCount extends StatelessWidget {
  const _CollapsedFilterCount({
    required this.count,
    required this.showFilterPrefix,
  });

  /** 当前未单独展示的活动筛选数量。 */
  final int count;

  /** 没有可见 chip 时用“筛选 N”明确表达当前状态，而不是只显示含糊的“+N”。 */
  final bool showFilterPrefix;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: libraryBorder),
      ),
      child: Text(
        showFilterPrefix ? '筛选 $count' : '+$count',
        style: const TextStyle(
          color: libraryTextMuted,
          fontSize: AppTypography.caption,
          fontWeight: AppTypography.strong,
        ),
      ),
    );
  }
}

/** 多选状态只替换搜索框右侧区域，搜索输入和关键词保持可见。 */
class _LibrarySelectionToolbar extends StatelessWidget {
  const _LibrarySelectionToolbar({
    required this.selectedCount,
    required this.allSelected,
    required this.onToggleSelectAll,
    required this.onDeleteSelected,
    required this.onCancel,
  });

  /** 当前完整结果范围内已选择的视频数量。 */
  final int selectedCount;

  /** 当前完整结果是否已全部选择。 */
  final bool allSelected;

  /** 圆形复选框承担全选/取消全选入口。 */
  final VoidCallback? onToggleSelectAll;

  /** 删除已选视频；未选择时由页面传入 null。 */
  final VoidCallback? onDeleteSelected;

  /** 退出多选并清空临时选择。 */
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: LibrarySmokeKeys.selectionStatusArea,
      width: double.infinity,
      height: 50,
      child: Row(
        children: [
          InkWell(
            key: LibrarySmokeKeys.librarySelectAll,
            borderRadius: BorderRadius.circular(8),
            onTap: onToggleSelectAll,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  Checkbox(
                    value: allSelected,
                    onChanged: onToggleSelectAll == null
                        ? null
                        : (_) => onToggleSelectAll!(),
                    shape: const CircleBorder(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 6),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        color: libraryText,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                      children: [
                        const TextSpan(text: '\u5df2\u9009\u62e9 '),
                        TextSpan(
                          text: '$selectedCount',
                          style: const TextStyle(
                            color: appAccentViolet,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const TextSpan(text: ' \u9879'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            key: LibrarySmokeKeys.libraryDeleteSelected,
            onPressed: onDeleteSelected,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('\u5220\u9664'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xffe26573),
              disabledForegroundColor: libraryTextMuted.withValues(alpha: 0.45),
              backgroundColor: onDeleteSelected == null
                  ? Colors.transparent
                  : const Color(0x24e26573),
              minimumSize: const Size(68, 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: LibrarySmokeKeys.libraryCancelSelection,
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: libraryTextMuted,
              minimumSize: const Size(56, 34),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('\u53d6\u6d88'),
          ),
        ],
      ),
    );
  }
}

class _CurrentFilterChip extends StatelessWidget {
  const _CurrentFilterChip({
    required this.label,
    this.avatar,
    this.onDeleted,
  });

  final Widget? avatar;

  final Widget label;

  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: avatar,
      label: label,
      onDeleted: onDeleted,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      color: WidgetStateProperty.resolveWith((states) {
        // 紫色只表示交互状态变化，常态保持中性灰，避免与数量和选中态争夺注意力。
        if (states.contains(WidgetState.focused) ||
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed)) {
          return appAccentViolet.withValues(alpha: 0.18);
        }
        return librarySurfaceAlt;
      }),
      deleteIconColor: libraryTextMuted,
      deleteIcon: const Icon(Icons.close_rounded, size: 15),
      deleteButtonTooltipMessage: '\u79fb\u9664\u8be5\u7b5b\u9009',
      labelStyle: const TextStyle(
        color: libraryText,
        fontSize: AppTypography.caption,
        fontWeight: AppTypography.strong,
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
    );
  }
}

class _FilterResultLine extends StatelessWidget {
  const _FilterResultLine({
    required this.resultCount,
    this.resultCountLabel,
    required this.refreshing,
    required this.progressLabel,
    required this.progressValue,
    required this.progressPaused,
    required this.onToggleProgressPaused,
    required this.onCancelProgress,
  });

  final int resultCount;

  /** 自定义结果统计；为空时沿用“视频”语义。 */
  final String? resultCountLabel;

  final bool refreshing;

  final String? progressLabel;

  final double? progressValue;

  final bool progressPaused;

  final VoidCallback? onToggleProgressPaused;

  /** 当前扫描的取消入口；为空时不占用进度行空间。 */
  final VoidCallback? onCancelProgress;

  @override
  Widget build(BuildContext context) {
    final operationInProgress = progressLabel != null;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (!operationInProgress) ...[
        const Icon(Icons.circle, size: 7, color: appAccentViolet),
        const SizedBox(width: AppSpacing.xs),
      ],
      Flexible(
        child: Text(
          progressLabel ?? resultCountLabel ?? '$resultCount 个视频',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: libraryText,
            fontSize: 13,
            fontWeight: AppTypography.strong,
          ),
        ),
      ),
      if (operationInProgress) ...[
        const SizedBox(width: 8),
        if (progressValue == null)
          const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          SizedBox(
            width: 64,
            child: LinearProgressIndicator(
              value: progressValue!.clamp(0, 1),
              minHeight: 4,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: const Color(0xffe7e4ff),
            ),
          ),
        if (onToggleProgressPaused != null) ...[
          const SizedBox(width: 4),
          SizedBox.square(
            dimension: 28,
            child: IconButton(
              key: ValueKey(progressPaused
                  ? 'qa.media_import.resume'
                  : 'qa.media_import.pause'),
              tooltip: progressPaused ? '继续后台任务' : '暂停后台任务',
              padding: EdgeInsets.zero,
              iconSize: 18,
              color: appAccentViolet,
              onPressed: onToggleProgressPaused,
              icon: Icon(
                progressPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              ),
            ),
          ),
        ],
        if (onCancelProgress != null) ...[
          const SizedBox(width: 2),
          SizedBox.square(
            dimension: 28,
            child: IconButton(
              key: const ValueKey('qa.library_scan.cancel'),
              tooltip: '取消扫描',
              padding: EdgeInsets.zero,
              iconSize: 17,
              color: libraryTextMuted,
              onPressed: onCancelProgress,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ] else if (refreshing) ...[
        const SizedBox(width: 8),
        const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ],
    ]);
  }
}

class SmartListDraftDialog extends StatefulWidget {
  const SmartListDraftDialog({
    required this.suggestedName,
    required this.querySummary,
    required this.queryExpression,
    required this.resultCount,
    required this.totalCount,
    required this.onConfirmDraft,
  });

  final String suggestedName;
  final String querySummary;
  final String queryExpression;
  final int resultCount;
  final int totalCount;
  final VoidCallback onConfirmDraft;

  @override
  State<SmartListDraftDialog> createState() => SmartListDraftDialogState();
}

class SmartListDraftDialogState extends State<SmartListDraftDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.suggestedName);
  var _autoRefreshPreview = true;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _confirmDraft() {
    Navigator.of(context).pop();
    widget.onConfirmDraft();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
      actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xfff5f3ff),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xffd8d4ff)),
            ),
            child: const Icon(Icons.bookmark_add_outlined,
                color: appAccentViolet, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '\u4fdd\u5b58\u7b5b\u9009\u8349\u6848',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '\u7b5b\u9009\u540d\u79f0',
                prefixIcon: Icon(Icons.edit_outlined),
              ),
            ),
            const SizedBox(height: 14),
            _SmartListPreviewPanel(
              querySummary: widget.querySummary,
              queryExpression: widget.queryExpression,
              resultCount: widget.resultCount,
              totalCount: widget.totalCount,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _autoRefreshPreview,
              onChanged: (value) {
                setState(() => _autoRefreshPreview = value);
              },
              contentPadding: EdgeInsets.zero,
              title: const Text('\u81ea\u52a8\u5237\u65b0\u9884\u89c8'),
              subtitle: const Text(
                  '\u4ec5\u9a8c\u8bc1 UI \u6d41\u7a0b\uff0c\u4e0d\u5199\u5165 SQLite'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('\u53d6\u6d88'),
        ),
        FilledButton.icon(
          onPressed: _confirmDraft,
          icon: const Icon(Icons.check_rounded),
          label: const Text('\u786e\u8ba4\u8349\u6848'),
        ),
      ],
    );
  }
}

class _SmartListPreviewPanel extends StatelessWidget {
  const _SmartListPreviewPanel({
    required this.querySummary,
    required this.queryExpression,
    required this.resultCount,
    required this.totalCount,
  });

  final String querySummary;
  final String queryExpression;
  final int resultCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: libraryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.manage_search_rounded,
                  size: 18, color: appAccentViolet),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  querySummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: libraryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$resultCount / $totalCount',
                style: const TextStyle(
                  color: appAccentViolet,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            queryExpression,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: libraryTextMuted,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/**
 * 根据结果区是否处于绝对顶部收起或恢复媒体库顶部信息区。
 *
 * 动画只包裹顶部 chrome，不读取筛选结果，也不驱动视频逐项动画；[visibleListenable]
 * 由结果滚动组件仅在跨越顶部边界时更新，避免逐像素重建页面。
 */
class LibraryScrollResponsiveHeader extends StatefulWidget {
  const LibraryScrollResponsiveHeader({
    super.key,
    required this.visibleListenable,
    required this.child,
  });

  /** 顶部信息区的目标可见状态。 */
  final ValueListenable<bool> visibleListenable;

  /** 保留原有搜索、筛选、排序和动作语义的顶部内容。 */
  final Widget child;

  @override
  State<LibraryScrollResponsiveHeader> createState() =>
      _LibraryScrollResponsiveHeaderState();
}

/** 管理可打断的顶部尺寸、透明度和短距离位移动画。 */
class _LibraryScrollResponsiveHeaderState
    extends State<LibraryScrollResponsiveHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _visibilityAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
      value: widget.visibleListenable.value ? 1 : 0,
    );
    _visibilityAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.045),
      end: Offset.zero,
    ).animate(_visibilityAnimation);
    widget.visibleListenable.addListener(_handleVisibilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animateToTarget();
  }

  @override
  void didUpdateWidget(covariant LibraryScrollResponsiveHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibleListenable != widget.visibleListenable) {
      oldWidget.visibleListenable.removeListener(_handleVisibilityChanged);
      widget.visibleListenable.addListener(_handleVisibilityChanged);
    }
    _animateToTarget();
  }

  /** 响应轻量可见性通知，并从当前动画进度直接反向。 */
  void _handleVisibilityChanged() {
    if (mounted) {
      _animateToTarget();
    }
  }

  /** 根据无障碍策略平滑抵达目标；reduced motion 下立即完成结构变化。 */
  void _animateToTarget() {
    final visible = widget.visibleListenable.value;
    final accessibility = AppAccessibilityScope.of(context);
    if (accessibility.reduceMotion) {
      _controller.value = visible ? 1 : 0;
      return;
    }
    if (visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    widget.visibleListenable.removeListener(_handleVisibilityChanged);
    _visibilityAnimation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final targetVisible = widget.visibleListenable.value;
        return ExcludeFocus(
          excluding: !targetVisible,
          child: ExcludeSemantics(
            excluding: !targetVisible,
            child: IgnorePointer(
              ignoring: !targetVisible,
              child: SizeTransition(
                sizeFactor: _visibilityAnimation,
                alignment: Alignment.topCenter,
                child: FadeTransition(
                  opacity: _visibilityAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ReferenceTopBar extends StatelessWidget {
  const ReferenceTopBar({
    required this.controller,
    required this.searchFocusNode,
    required this.videoCount,
    this.resultCountLabel,
    required this.keyword,
    required this.selectedTags,
    required this.selectedChildTags,
    required this.selectedGroupTags,
    required this.excludedTags,
    required this.defaultChipLabel,
    required this.showFavoritesOnly,
    required this.refreshing,
    required this.progressLabel,
    required this.progressValue,
    required this.sortMode,
    required this.sortDirection,
    required this.layoutSize,
    required this.hasActiveFilters,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onSortDirectionToggle,
    required this.denseResultGrid,
    required this.onResultViewChanged,
    required this.onOpenTagManager,
    required this.onOpenFilters,
    this.tagPanelOpen = false,
    this.onToggleTagPanel,
    required this.onRemovePrimaryTag,
    required this.onRemoveChildTag,
    required this.onRemoveGroupTag,
    required this.onRemoveExcludedTag,
    required this.onClearKeyword,
    required this.onClearFavoritesOnly,
    required this.onClearAll,
    this.progressPaused = false,
    this.onToggleProgressPaused,
    this.onCancelProgress,
    this.selectionMode = false,
    this.selectedCount = 0,
    this.allSelected = false,
    this.onEnterSelectionMode,
    this.onToggleSelectAll,
    this.onDeleteSelected,
    this.onCancelSelectionMode,
  });

  final TextEditingController controller;

  /**
   * 主搜索框焦点节点。
   *
   * 顶部栏内部处理 `Ctrl+K` 时只请求该节点焦点，不直接改写搜索业务状态；
   * 文本变化仍统一从 TextField 的 controller / onChanged 进入筛选链路。
   */
  final FocusNode searchFocusNode;

  /** 当前可见结果数量；与搜索和 chips 同处一个结果状态区域。 */
  final int videoCount;

  /** 本地目录等混合来源的精确统计文案。 */
  final String? resultCountLabel;

  /** 当前关键词只保留在真实输入框中，不重复渲染为 chip。 */
  final String keyword;

  /** 当前一级 folder 标签筛选。 */
  final List<String> selectedTags;

  /** 当前二级 folder 标签筛选。 */
  final List<String> selectedChildTags;

  /** 当前分组标签筛选。 */
  final List<TagItem> selectedGroupTags;

  /** 当前排除标签筛选。 */
  final List<TagItem> excludedTags;

  /** 最近播放、本地收藏或本地目录等非全库结果来源名称。 */
  final String defaultChipLabel;

  /** 是否启用收藏筛选。 */
  final bool showFavoritesOnly;

  /** 当前结果或标签计数是否正在后台刷新。 */
  final bool refreshing;

  /** 扫描或媒体解析时替代普通结果数量的状态。 */
  final String? progressLabel;

  /** 已知总量任务的进度值。 */
  final double? progressValue;

  final SortMode sortMode;

  final SortDirection sortDirection;

  final LayoutSize layoutSize;

  final bool hasActiveFilters;

  final ValueChanged<String> onSearchChanged;

  final ValueChanged<SortMode> onSortChanged;

  final VoidCallback onSortDirectionToggle;

  final bool denseResultGrid;

  final ValueChanged<bool> onResultViewChanged;

  final VoidCallback onOpenTagManager;

  final VoidCallback onOpenFilters;

  /** expanded 桌面布局中的标签浏览面板是否已经展开。 */
  final bool tagPanelOpen;

  /** 从页面标题区展开或收起标签浏览面板；中小布局继续使用底部筛选面板。 */
  final VoidCallback? onToggleTagPanel;

  final ValueChanged<String> onRemovePrimaryTag;

  final ValueChanged<String> onRemoveChildTag;

  final ValueChanged<TagItem> onRemoveGroupTag;

  final ValueChanged<TagItem> onRemoveExcludedTag;

  final VoidCallback onClearKeyword;

  final VoidCallback onClearFavoritesOnly;

  final VoidCallback? onClearAll;

  /** true 时暂停按钮切换为继续图标。 */
  final bool progressPaused;

  /** 后台媒体解析存在时提供暂停/继续入口。 */
  final VoidCallback? onToggleProgressPaused;

  /** 扫描期间提供取消入口；其它后台任务保持为空。 */
  final VoidCallback? onCancelProgress;

  /** true 时整条顶栏替换为批量选择状态。 */
  final bool selectionMode;

  /** 当前完整结果范围内已选择的视频数量。 */
  final int selectedCount;

  /** 当前完整结果是否已全部选择。 */
  final bool allSelected;

  /** 进入多选模式；为空时当前结果来源不支持批量删除。 */
  final VoidCallback? onEnterSelectionMode;

  /** 切换完整当前结果的全选状态。 */
  final VoidCallback? onToggleSelectAll;

  /** 删除已选视频；未选择时页面传入 null。 */
  final VoidCallback? onDeleteSelected;

  /** 退出多选并清空临时选择。 */
  final VoidCallback? onCancelSelectionMode;

  @override
  Widget build(BuildContext context) {
    final compact = layoutSize == LayoutSize.compact;
    final accessibility = AppAccessibilityScope.of(context);
    // 只在非紧凑桌面工具栏扩展结果状态宽度；125%/150% 下完整保留
    // “11163 个视频”这类关键反馈，同时不改变筛选、排序或搜索语义。
    final resultTextScaleAllowance = compact
        ? 0.0
        : (accessibility.textScaler.scale(1).clamp(1.0, 1.5) - 1) * 160;
    final keywordActive = keyword.trim().isNotEmpty;
    final activeFilters = <_FilterToolbarEntry>[
      if (showFavoritesOnly)
        _FilterToolbarEntry(
          label: '\u672c\u5730\u6536\u85cf',
          icon: Icons.favorite_rounded,
          onRemove: onClearFavoritesOnly,
        ),
      for (final tag in selectedTags)
        _FilterToolbarEntry(
          label: tag,
          onRemove: () => onRemovePrimaryTag(tag),
        ),
      for (final tag in selectedChildTags)
        _FilterToolbarEntry(
          label: tag,
          onRemove: () => onRemoveChildTag(tag),
        ),
      for (final tag in selectedGroupTags)
        _FilterToolbarEntry(
          label: tag.displayName ?? tag.name,
          onRemove: () => onRemoveGroupTag(tag),
        ),
      for (final tag in excludedTags)
        _FilterToolbarEntry(
          label: 'NOT ${tag.displayName ?? tag.name}',
          onRemove: () => onRemoveExcludedTag(tag),
        ),
    ];
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            const FocusLibrarySearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          FocusLibrarySearchIntent: CallbackAction<FocusLibrarySearchIntent>(
            onInvoke: (_) {
              searchFocusNode.requestFocus();
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
              // 顶部栏单独作为 smoke 宿主时也补一次下一帧聚焦，保持与真实页面一致。
              WidgetsBinding.instance.addPostFrameCallback((_) {
                searchFocusNode.requestFocus();
                controller.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: controller.text.length,
                );
              });
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                layoutSize == LayoutSize.expanded ? 20 : 12,
                12,
                layoutSize == LayoutSize.expanded ? 20 : 12,
                libraryTopBarBottomSpacing,
              ),
              child: DecoratedBox(
                key: LibrarySmokeKeys.libraryResultToolbar,
                decoration: BoxDecoration(
                  color: layoutSize == LayoutSize.expanded
                      ? Colors.transparent
                      : librarySurface,
                  borderRadius: BorderRadius.circular(AppRadius.panel),
                  border: layoutSize == LayoutSize.expanded
                      ? null
                      : Border.all(color: libraryBorder),
                ),
                child: Padding(
                  // expanded 主界面改用“标题 + 操作 + 状态”的分层结构，不再把所有功能
                  // 塞进一个后台工具条式容器；中小布局仍保留紧凑单行，避免占用结果空间。
                  padding: layoutSize == LayoutSize.expanded
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrowMedium = layoutSize == LayoutSize.medium &&
                          constraints.maxWidth < 620;
                      final proportionalDesktop =
                          layoutSize == LayoutSize.expanded &&
                              constraints.maxWidth >= 1180;
                      final searchSurface = _LibrarySearchSurface(
                        controller: controller,
                        searchFocusNode: searchFocusNode,
                        compact: compact,
                        keywordActive: keywordActive,
                        onSearchChanged: onSearchChanged,
                        onClearKeyword: onClearKeyword,
                      );
                      final filterStatus = _LibraryFilterStatusArea(
                        compact: compact || narrowMedium,
                        defaultLabel: defaultChipLabel,
                        filters: activeFilters,
                        resultCount: videoCount,
                        resultCountLabel: resultCountLabel,
                        refreshing: refreshing,
                        progressLabel: progressLabel,
                        progressValue: progressValue,
                        progressPaused: progressPaused,
                        onToggleProgressPaused: onToggleProgressPaused,
                        onCancelProgress: onCancelProgress,
                        onClearAll: onClearAll,
                        showResultStatus: !proportionalDesktop,
                      );
                      final resultStatus = SizedBox(
                        key: LibrarySmokeKeys.toolbarResultStatus,
                        width: progressLabel == null
                            ? (resultCountLabel == null ? 92 : 200) +
                                resultTextScaleAllowance
                            : 224,
                        child: _FilterResultLine(
                          resultCount: videoCount,
                          resultCountLabel: resultCountLabel,
                          refreshing: refreshing,
                          progressLabel: progressLabel,
                          progressValue: progressValue,
                          progressPaused: progressPaused,
                          onToggleProgressPaused: onToggleProgressPaused,
                          onCancelProgress: onCancelProgress,
                        ),
                      );
                      final selectionStatus = _LibrarySelectionToolbar(
                        selectedCount: selectedCount,
                        allSelected: allSelected,
                        onToggleSelectAll: onToggleSelectAll,
                        onDeleteSelected: onDeleteSelected,
                        onCancel: onCancelSelectionMode,
                      );
                      final sortControl = _CompactTopSortControl(
                        sortMode: sortMode,
                        sortDirection: sortDirection,
                        showCurrentField: layoutSize == LayoutSize.expanded,
                        onChanged: onSortChanged,
                        onDirectionToggle: onSortDirectionToggle,
                      );
                      final normalActions = SizedBox(
                        key: LibrarySmokeKeys.toolbarActions,
                        height: 48,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (onEnterSelectionMode != null)
                              if (compact || narrowMedium)
                                _ReferenceIconButton(
                                  key: LibrarySmokeKeys.libraryEnterSelection,
                                  tooltip: '\u591a\u9009',
                                  icon: Icons.checklist_rounded,
                                  onPressed: onEnterSelectionMode!,
                                )
                              else
                                _TopToolbarTextButton(
                                  key: LibrarySmokeKeys.libraryEnterSelection,
                                  onPressed: onEnterSelectionMode!,
                                  label: '\u591a\u9009',
                                ),
                            if (onEnterSelectionMode != null &&
                                !compact &&
                                !narrowMedium)
                              const SizedBox(width: 8),
                            if (!compact && !narrowMedium)
                              ResultViewToggle(
                                dense: denseResultGrid,
                                onChanged: onResultViewChanged,
                              ),
                          ],
                        ),
                      );
                      if (layoutSize == LayoutSize.expanded) {
                        final pageTitle = defaultChipLabel == '全部视频'
                            ? '媒体库'
                            : defaultChipLabel;
                        final resultStatusWidth = progressLabel == null
                            ? (resultCountLabel == null ? 104.0 : 200.0) +
                                resultTextScaleAllowance
                            : 224.0;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          pageTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: libraryText,
                                            fontSize: 24,
                                            height: 1.12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          defaultChipLabel == '全部视频'
                                              ? '全部视频 · 浏览、搜索并整理你的本地视频'
                                              : '当前资料库视图',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: libraryTextMuted,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    key: LibrarySmokeKeys.toolbarResultStatus,
                                    width: resultStatusWidth,
                                    child: _FilterResultLine(
                                      resultCount: videoCount,
                                      resultCountLabel: resultCountLabel,
                                      refreshing: refreshing,
                                      progressLabel: progressLabel,
                                      progressValue: progressValue,
                                      progressPaused: progressPaused,
                                      onToggleProgressPaused:
                                          onToggleProgressPaused,
                                      onCancelProgress: onCancelProgress,
                                    ),
                                  ),
                                  if (onToggleTagPanel != null) ...[
                                    const SizedBox(width: 12),
                                    _TagDiscoveryHeaderButton(
                                      expanded: tagPanelOpen,
                                      activeFilterCount: activeFilters.length,
                                      onPressed: onToggleTagPanel!,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // 搜索和动作直接落在画布上，各自用自身 surface 表达可交互性；
                            // 不再用大圆角容器包裹一组已经带边框的控件，避免“容器套容器”。
                            SizedBox(
                              key: LibrarySmokeKeys.headerActionLane,
                              height: 50,
                              child: Row(
                                children: [
                                  Expanded(child: searchSurface),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 380,
                                    child: selectionMode
                                        ? selectionStatus
                                        : Row(
                                            children: [
                                              // 桌面动作带保留固定宽度以避免进入多选时搜索框跳动；
                                              // 排序字段使用紧凑稳定宽度，余量只作为方向与低频动作的分组间距。
                                              SizedBox(
                                                width:
                                                    _expandedSortControlWidth,
                                                child: sortControl,
                                              ),
                                              const SizedBox(width: 12),
                                              // 把少量响应式余量留在动作分组之间，保持视图切换与右边界对齐。
                                              const Spacer(),
                                              normalActions,
                                            ],
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            if (!selectionMode && activeFilters.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              KeyedSubtree(
                                key: LibrarySmokeKeys.filterStatusArea,
                                child: _LibraryFilterStatusArea(
                                  compact: false,
                                  defaultLabel: defaultChipLabel,
                                  filters: activeFilters,
                                  resultCount: videoCount,
                                  resultCountLabel: resultCountLabel,
                                  refreshing: refreshing,
                                  progressLabel: progressLabel,
                                  progressValue: progressValue,
                                  progressPaused: progressPaused,
                                  onToggleProgressPaused:
                                      onToggleProgressPaused,
                                  onCancelProgress: onCancelProgress,
                                  onClearAll: onClearAll,
                                  showResultStatus: false,
                                ),
                              ),
                            ],
                          ],
                        );
                      }
                      if (proportionalDesktop) {
                        return SizedBox(
                          height: 50,
                          child: Row(
                            children: [
                              // 搜索从 60% 收敛到 50%，把标签浏览和媒体库状态提升为同级主场景。
                              Expanded(flex: 5, child: searchSurface),
                              const SizedBox(width: 12),
                              if (selectionMode) ...[
                                Expanded(flex: 5, child: selectionStatus),
                                // 与常态区域保留相同总间距，进入多选时搜索框宽度不会跳动。
                                const SizedBox(width: 8),
                              ] else ...[
                                Expanded(
                                  flex: 4,
                                  child: KeyedSubtree(
                                    key: LibrarySmokeKeys.filterStatusArea,
                                    child: Row(
                                      children: [
                                        Expanded(child: filterStatus),
                                        const SizedBox(width: 8),
                                        sortControl,
                                        const SizedBox(width: 10),
                                        resultStatus,
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(flex: 1, child: normalActions),
                              ],
                            ],
                          ),
                        );
                      }
                      return Row(
                        children: [
                          if (layoutSize != LayoutSize.expanded) ...[
                            _ReferenceIconButton(
                              tooltip: '\u6253\u5f00\u667a\u80fd\u7b5b\u9009',
                              icon: hasActiveFilters
                                  ? Icons.filter_alt_rounded
                                  : Icons.filter_alt_outlined,
                              onPressed: onOpenFilters,
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(child: searchSurface),
                          const SizedBox(width: 8),
                          if (selectionMode)
                            SizedBox(width: 280, child: selectionStatus)
                          else ...[
                            SizedBox(
                              key: LibrarySmokeKeys.filterStatusArea,
                              width: progressLabel != null
                                  ? math.min(
                                      360,
                                      math.max(
                                          224, constraints.maxWidth * 0.42),
                                    )
                                  : activeFilters.isNotEmpty
                                      ? narrowMedium
                                          ? 82
                                          : math.min(
                                              220,
                                              math.max(
                                                142,
                                                constraints.maxWidth * 0.24,
                                              ),
                                            )
                                      : narrowMedium
                                          ? 82
                                          : resultCountLabel != null
                                              ? 200 + resultTextScaleAllowance
                                              : 118 + resultTextScaleAllowance,
                              child: filterStatus,
                            ),
                            if (!compact &&
                                !(progressLabel != null &&
                                    constraints.maxWidth < 700)) ...[
                              const SizedBox(width: 8),
                              sortControl,
                            ],
                            if (compact) ...[
                              const SizedBox(width: 8),
                              _ReferenceIconButton(
                                tooltip: '标签中心',
                                icon: Icons.sell_outlined,
                                onPressed: onOpenTagManager,
                              ),
                            ],
                            if (!(progressLabel != null &&
                                constraints.maxWidth < 700)) ...[
                              const SizedBox(width: 8),
                              normalActions,
                            ],
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/**
 * 顶部搜索框聚焦意图。
 *
 * 独立 intent 让快捷键层只负责焦点转移，不复制搜索和筛选逻辑。
 */
class FocusLibrarySearchIntent extends Intent {
  const FocusLibrarySearchIntent();
}

/**
 * 顶部搜索栏 smoke test 入口。
 *
 * 只暴露真实顶部栏里的搜索输入链路，避免测试复制一份搜索 UI 后漏掉桌面输入问题。
 */
@visibleForTesting
Widget referenceTopBarSearchSmokeHarness({
  required TextEditingController controller,
  required ValueChanged<String> onSearchChanged,
  FocusNode? searchFocusNode,
  int videoCount = 0,
  String? resultCountLabel,
  String? keyword,
  List<String> selectedTags = const <String>[],
  List<String> selectedChildTags = const <String>[],
  List<TagItem> selectedGroupTags = const <TagItem>[],
  List<TagItem> excludedTags = const <TagItem>[],
  String defaultChipLabel = '\u5168\u90e8\u89c6\u9891',
  bool showFavoritesOnly = false,
  bool refreshing = false,
  String? progressLabel,
  double? progressValue,
  bool progressPaused = false,
  VoidCallback? onToggleProgressPaused,
  VoidCallback? onCancelProgress,
  LayoutSize layoutSize = LayoutSize.expanded,
  SortDirection sortDirection = SortDirection.descending,
  ValueChanged<SortMode>? onSortChanged,
  VoidCallback? onSortDirectionToggle,
  ValueChanged<String>? onRemovePrimaryTag,
  ValueChanged<String>? onRemoveChildTag,
  ValueChanged<TagItem>? onRemoveGroupTag,
  ValueChanged<TagItem>? onRemoveExcludedTag,
  VoidCallback? onClearKeyword,
  VoidCallback? onClearFavoritesOnly,
  VoidCallback? onClearAll,
  bool selectionMode = false,
  int selectedCount = 0,
  bool allSelected = false,
  AppAccessibilityData? accessibility,
  VoidCallback? onEnterSelectionMode,
  VoidCallback? onToggleSelectAll,
  VoidCallback? onDeleteSelected,
  VoidCallback? onCancelSelectionMode,
  bool tagPanelOpen = false,
  VoidCallback? onToggleTagPanel,
}) {
  final app = MaterialApp(
    builder: accessibility == null
        ? null
        : (context, child) {
            // focused test 必须让文字缩放同时进入 MediaQuery 和设计策略作用域，
            // 避免只扩大宽度预算却没有真实放大文字的假验收。
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(textScaler: accessibility.textScaler),
              child: child!,
            );
          },
    home: Scaffold(
      body: ReferenceTopBar(
        controller: controller,
        searchFocusNode:
            searchFocusNode ?? FocusNode(debugLabel: 'search-smoke-field'),
        videoCount: videoCount,
        resultCountLabel: resultCountLabel,
        keyword: keyword ?? controller.text,
        selectedTags: selectedTags,
        selectedChildTags: selectedChildTags,
        selectedGroupTags: selectedGroupTags,
        excludedTags: excludedTags,
        defaultChipLabel: defaultChipLabel,
        showFavoritesOnly: showFavoritesOnly,
        refreshing: refreshing,
        progressLabel: progressLabel,
        progressValue: progressValue,
        progressPaused: progressPaused,
        onToggleProgressPaused: onToggleProgressPaused,
        onCancelProgress: onCancelProgress,
        sortMode: SortMode.recent,
        sortDirection: sortDirection,
        layoutSize: layoutSize,
        hasActiveFilters: (keyword ?? controller.text).trim().isNotEmpty ||
            showFavoritesOnly ||
            selectedTags.isNotEmpty ||
            selectedChildTags.isNotEmpty ||
            selectedGroupTags.isNotEmpty ||
            excludedTags.isNotEmpty,
        onSearchChanged: onSearchChanged,
        onSortChanged: onSortChanged ?? (_) {},
        onSortDirectionToggle: onSortDirectionToggle ?? () {},
        denseResultGrid: false,
        onResultViewChanged: (_) {},
        onOpenTagManager: () {},
        onOpenFilters: () {},
        tagPanelOpen: tagPanelOpen,
        onToggleTagPanel: onToggleTagPanel,
        onRemovePrimaryTag: onRemovePrimaryTag ?? (_) {},
        onRemoveChildTag: onRemoveChildTag ?? (_) {},
        onRemoveGroupTag: onRemoveGroupTag ?? (_) {},
        onRemoveExcludedTag: onRemoveExcludedTag ?? (_) {},
        onClearKeyword: onClearKeyword ?? () {},
        onClearFavoritesOnly: onClearFavoritesOnly ?? () {},
        onClearAll: onClearAll,
        selectionMode: selectionMode,
        selectedCount: selectedCount,
        allSelected: allSelected,
        onEnterSelectionMode: onEnterSelectionMode,
        onToggleSelectAll: onToggleSelectAll,
        onDeleteSelected: onDeleteSelected,
        onCancelSelectionMode: onCancelSelectionMode,
      ),
    ),
  );
  if (accessibility == null) {
    return app;
  }
  return AppAccessibilityScope(data: accessibility, child: app);
}

/**
 * 顶部搜索到结果列表的 smoke test 入口。
 *
 * 该 harness 只验证输入链路会驱动结果数量和可见列表变化；真实业务过滤仍由
 * `LibraryPage` / `TagQueryService` 负责，测试里不复制完整标签筛选语义。
 */
@visibleForTesting
class ReferenceTopBarSearchResultSmokeHarness extends StatefulWidget {
  const ReferenceTopBarSearchResultSmokeHarness({
    super.key,
    required this.items,
  });

  /**
   * 用于 smoke 的可搜索标题列表。
   *
   * 只使用字符串能避免测试依赖真实媒体库或数据库。
   */
  final List<String> items;

  @override
  State<ReferenceTopBarSearchResultSmokeHarness> createState() =>
      ReferenceTopBarSearchResultSmokeHarnessState();
}

class ReferenceTopBarSearchResultSmokeHarnessState
    extends State<ReferenceTopBarSearchResultSmokeHarness> {
  /**
   * smoke harness 自己持有 controller，模拟真实页面中的单一输入源。
   */
  final _controller = TextEditingController();

  /**
   * smoke harness 自己持有焦点节点，验证 `Ctrl+K` 能把焦点转给 TextField。
   */
  final _focusNode = FocusNode(debugLabel: 'search-result-smoke-field');

  var _keyword = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = _keyword.trim().toLowerCase();
    final filtered = token.isEmpty
        ? widget.items
        : widget.items
            .where((item) => item.toLowerCase().contains(token))
            .toList();
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ReferenceTopBar(
              controller: _controller,
              searchFocusNode: _focusNode,
              videoCount: filtered.length,
              keyword: _keyword,
              selectedTags: const <String>[],
              selectedChildTags: const <String>[],
              selectedGroupTags: const <TagItem>[],
              excludedTags: const <TagItem>[],
              defaultChipLabel: '\u5168\u90e8\u89c6\u9891',
              showFavoritesOnly: false,
              refreshing: false,
              progressLabel: null,
              progressValue: null,
              sortMode: SortMode.recent,
              sortDirection: SortDirection.descending,
              layoutSize: LayoutSize.expanded,
              hasActiveFilters: token.isNotEmpty,
              onSearchChanged: (value) => setState(() => _keyword = value),
              onSortChanged: (_) {},
              onSortDirectionToggle: () {},
              denseResultGrid: false,
              onResultViewChanged: (_) {},
              onOpenTagManager: () {},
              onOpenFilters: () {},
              onRemovePrimaryTag: (_) {},
              onRemoveChildTag: (_) {},
              onRemoveGroupTag: (_) {},
              onRemoveExcludedTag: (_) {},
              onClearKeyword: () {
                _controller.clear();
                setState(() => _keyword = '');
              },
              onClearFavoritesOnly: () {},
              onClearAll: null,
            ),
            Text('结果 ${filtered.length}/${widget.items.length}'),
            Expanded(
              child: ListView(
                children: [
                  for (final item in filtered) Text(item),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/**
 * 顶栏低频文字动作。
 *
 * 保留 48px 命中高度与相邻控件对齐，但使用透明背景和无边框文字视觉，
 * 让低频“多选”入口不再与高频排序、视图切换争夺同等权重。
 */
class _TopToolbarTextButton extends StatelessWidget {
  const _TopToolbarTextButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  /** 按钮短文案。 */
  final String label;

  /** 点击动作。 */
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? libraryText
              : libraryTextMuted;
        }),
        overlayColor: WidgetStatePropertyAll(
          appAccentViolet.withValues(alpha: 0.10),
        ),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/**
 * expanded 主界面标题区里的标签浏览入口。
 *
 * 横向按钮取代右侧竖排窄条，并用同一个入口承担展开与收起，避免内容区边缘出现
 * 与视频卡片无关的强视觉噪声；筛选数量只作状态提示，不复制过滤计算。
 */
class _TagDiscoveryHeaderButton extends StatelessWidget {
  const _TagDiscoveryHeaderButton({
    required this.expanded,
    required this.activeFilterCount,
    required this.onPressed,
  });

  /** 右侧标签发现面板当前是否展开。 */
  final bool expanded;

  /** 当前已生效标签条件数量，用于入口上的轻量状态提示。 */
  final int activeFilterCount;

  /** 切换右侧标签发现面板。 */
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tooltip = expanded ? '折叠标签筛选' : '展开标签筛选';
    return Tooltip(
      message: tooltip,
      child: Semantics(
        key: LibrarySmokeKeys.collapsedTagRail,
        button: true,
        label: tooltip,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(
            expanded ? Icons.view_sidebar_rounded : Icons.sell_outlined,
            size: 18,
          ),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('标签'),
              if (activeFilterCount > 0) ...[
                const SizedBox(width: 7),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: appAccentViolet.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.capsule),
                  ),
                  child: Text(
                    '$activeFilterCount',
                    style: const TextStyle(
                      color: appAccentViolet,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: expanded ? libraryText : libraryTextMuted,
            backgroundColor: expanded ? librarySurfaceAlt : Colors.transparent,
            side: BorderSide(
              color: expanded
                  ? appAccentViolet.withValues(alpha: 0.44)
                  : libraryBorder,
            ),
            minimumSize: const Size(88, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
        ),
      ),
    );
  }
}

/** 宽桌面排序字段的视觉宽度，同时约束触发入口与弹层。 */
const double _expandedSortFieldWidth = 168;

/** 排序字段、6px 间距和 48px 方向命中区组成的稳定动作宽度。 */
const double _expandedSortControlWidth = _expandedSortFieldWidth + 6 + 48;

/**
 * 媒体库顶部的响应式排序控件。
 *
 * 宽桌面以紧凑固定宽度显示当前字段；中等窗口压缩成图标，
 * 两种形态仍分别回调页面已有排序状态，不复制排序逻辑。
 */
class _CompactTopSortControl extends StatelessWidget {
  const _CompactTopSortControl({
    required this.sortMode,
    required this.sortDirection,
    required this.showCurrentField,
    required this.onChanged,
    required this.onDirectionToggle,
  });

  /** 当前排序字段。 */
  final SortMode sortMode;

  /** 当前排序方向。 */
  final SortDirection sortDirection;

  /** 是否在宽桌面布局中展示当前排序字段。 */
  final bool showCurrentField;

  /** 选择排序字段后交给页面已有轻量重排入口。 */
  final ValueChanged<SortMode> onChanged;

  /** 切换排序方向。 */
  final VoidCallback onDirectionToggle;

  @override
  Widget build(BuildContext context) {
    final ascending = sortDirection == SortDirection.ascending;
    final fieldButton = PopupMenuButton<SortMode>(
      key: LibrarySmokeKeys.topSortFieldButton,
      tooltip: '\u6392\u5e8f\u5b57\u6bb5\uff1a${sortModeLabel(sortMode)}',
      onSelected: onChanged,
      color: librarySurface,
      initialValue: sortMode,
      // 强制从按钮下方展开，避免默认行为把当前选中项对齐到按钮并遮挡触发入口。
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      // 宽桌面入口与弹层共享同一几何宽度，避免触发按钮和菜单各自伸缩造成割裂。
      constraints: showCurrentField
          ? const BoxConstraints.tightFor(width: _expandedSortFieldWidth)
          : null,
      itemBuilder: (context) => [
        for (final mode in SortMode.values)
          PopupMenuItem<SortMode>(
            key: LibrarySmokeKeys.topSortMenuItem(mode),
            value: mode,
            child: Row(
              children: [
                Icon(
                  mode == sortMode
                      ? Icons.check_rounded
                      : Icons.circle_outlined,
                  size: 17,
                  color: mode == sortMode ? appAccentViolet : libraryTextMuted,
                ),
                const SizedBox(width: 8),
                Text(sortModeLabel(mode)),
              ],
            ),
          ),
      ],
      borderRadius: BorderRadius.circular(AppRadius.control),
      style: showCurrentField
          ? IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )
          : IconButton.styleFrom(
              backgroundColor: librarySurface,
              foregroundColor: libraryTextMuted,
              fixedSize: const Size(38, 38),
              side: const BorderSide(color: libraryBorder),
            ),
      icon: showCurrentField ? null : const Icon(Icons.sort_rounded, size: 20),
      child: showCurrentField
          ? SizedBox(
              width: _expandedSortFieldWidth,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: librarySurface,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: libraryBorder),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sort_rounded,
                      size: 19,
                      color: appAccentViolet,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        sortModeLabel(sortMode),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: libraryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: libraryTextMuted,
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        fieldButton,
        const SizedBox(width: 6),
        _ReferenceIconButton(
          tooltip: ascending
              ? '\u5207\u6362\u4e3a\u5012\u5e8f'
              : '\u5207\u6362\u4e3a\u6b63\u5e8f',
          icon: ascending
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded,
          onPressed: onDirectionToggle,
        ),
      ],
    );
  }
}

class _ReferenceIconButton extends StatelessWidget {
  const _ReferenceIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;

  final IconData icon;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: librarySurface,
        foregroundColor: libraryTextMuted,
        fixedSize: const Size(38, 38),
        side: const BorderSide(color: libraryBorder),
      ),
    );
  }
}

@visibleForTesting
class ResultViewToggle extends StatefulWidget {
  const ResultViewToggle({
    super.key,
    required this.dense,
    required this.onChanged,
  });

  /** true 表示使用紧凑列表，false 表示使用卡片网格。 */
  final bool dense;

  /** 请求切换结果视图；整个滑块每次点击只翻转一次当前状态。 */
  final ValueChanged<bool> onChanged;

  @override
  State<ResultViewToggle> createState() => _ResultViewToggleState();
}

/**
 * 网格/列表滑块状态。
 *
 * 滑块先在独立动画控制器中完成连续位移，再提交会触发结果区重布局的视图状态；
 * 快速重复点击会从当前进度反向运行，避免重型网格/列表切换阻塞滑块首帧。
 */
class _ResultViewToggleState extends State<ResultViewToggle>
    with SingleTickerProviderStateMixin {
  static const _slideDuration = Duration(milliseconds: 180);

  late final AnimationController _controller;
  late bool _visualDense;
  var _transitionVersion = 0;

  @override
  void initState() {
    super.initState();
    _visualDense = widget.dense;
    _controller = AnimationController(
      vsync: this,
      value: widget.dense ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(covariant ResultViewToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dense == widget.dense || widget.dense == _visualDense) {
      return;
    }
    // 外部状态变化时同步视觉目标，但不反向触发页面回调。
    _transitionVersion += 1;
    setState(() => _visualDense = widget.dense);
    _animateTo(widget.dense);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /** 根据剩余距离计算时长，让快速反向保持与正向一致的移动速度。 */
  Duration _remainingDuration(double target) {
    final distance = (_controller.value - target).abs();
    return Duration(
      milliseconds:
          math.max(1, (_slideDuration.inMilliseconds * distance).round()),
    );
  }

  /** 从当前进度平滑移动到目标，不重置动画端点。 */
  TickerFuture _animateTo(bool dense) {
    final target = dense ? 1.0 : 0.0;
    return _controller.animateTo(
      target,
      duration: _remainingDuration(target),
      curve: Curves.easeOutCubic,
    );
  }

  /** 响应整块控件点击；动画稳定后才提交较重的结果视图切换。 */
  Future<void> _toggle() async {
    final targetDense = !_visualDense;
    final version = ++_transitionVersion;
    setState(() => _visualDense = targetDense);
    try {
      await _animateTo(targetDense).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted ||
        version != _transitionVersion ||
        _visualDense != targetDense) {
      return;
    }
    if (widget.dense != targetDense) {
      widget.onChanged(targetDense);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tooltip = _visualDense ? '切换为网格视图' : '切换为列表视图';
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: LibrarySmokeKeys.resultViewToggle,
            borderRadius: BorderRadius.circular(10),
            excludeFromSemantics: true,
            onTap: _toggle,
            child: Ink(
              width: 72,
              height: 48,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: librarySurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: libraryBorder),
              ),
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final progress = _controller.value;
                    return Stack(
                      children: [
                        Transform.translate(
                          offset: Offset(32 * progress, 0),
                          child: Container(
                            key: LibrarySmokeKeys.resultViewToggleThumb,
                            width: 30,
                            height: 32,
                            decoration: BoxDecoration(
                              color: librarySurfaceAlt,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        IgnorePointer(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _TopViewIcon(
                                icon: Icons.grid_view_rounded,
                                color: Color.lerp(
                                  appAccentViolet,
                                  libraryTextMuted,
                                  progress,
                                )!,
                              ),
                              _TopViewIcon(
                                icon: Icons.view_list_rounded,
                                color: Color.lerp(
                                  libraryTextMuted,
                                  appAccentViolet,
                                  progress,
                                )!,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/** 滑块内只负责绘制状态的图标，不单独承担点击命中。 */
class _TopViewIcon extends StatelessWidget {
  const _TopViewIcon({
    required this.icon,
    required this.color,
  });

  /** 当前布局类型对应的图标。 */
  final IconData icon;

  /** 颜色直接跟随滑块控制器插值，避免额外隐式动画相互抢帧。 */
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 32,
      child: Center(
        child: Icon(
          icon,
          size: 18,
          color: color,
        ),
      ),
    );
  }
}

/**
 * 继续观看结果视图。
 *
 * 这里的删除只清理播放记录，不删除视频文件；选择状态由 LibraryPage 保存，
 * 避免滚动重建时丢失用户正在批量清理的选择。
 */
class RecentPlaybackView extends StatelessWidget {
  const RecentPlaybackView({
    required this.videos,
    required this.selectedPathKeys,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.dense,
    required this.onOpen,
    required this.onEditTags,
    required this.onToggleFavorite,
    required this.onDeleteVideo,
    required this.onToggleSelected,
    required this.onSelectAll,
    required this.onClearSelection,
    required this.onDeleteOne,
    required this.onDeleteSelected,
    required this.onDeleteAll,
  });

  final List<VideoItem> videos;
  final Set<String> selectedPathKeys;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  final bool dense;
  final void Function(VideoItem item, List<VideoItem> playlist) onOpen;
  final ValueChanged<VideoItem> onEditTags;
  final ValueChanged<VideoItem> onToggleFavorite;
  /** 卡片更多菜单的完整视频删除动作，与“清除播放记录”保持语义隔离。 */
  final ValueChanged<VideoItem> onDeleteVideo;
  final ValueChanged<VideoItem> onToggleSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final ValueChanged<VideoItem> onDeleteOne;
  final VoidCallback onDeleteSelected;
  final VoidCallback onDeleteAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
          child: Row(
            children: [
              Text(
                '\u5df2\u9009 ${selectedPathKeys.length} / ${videos.length}',
                style: const TextStyle(
                  color: libraryTextMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: selectedPathKeys.length == videos.length
                    ? onClearSelection
                    : onSelectAll,
                child: Text(selectedPathKeys.length == videos.length
                    ? '\u53d6\u6d88\u5168\u9009'
                    : '\u5168\u9009'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: selectedPathKeys.isEmpty ? null : onDeleteSelected,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('\u5220\u9664\u5df2\u9009'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: videos.isEmpty ? null : onDeleteAll,
                icon: const Icon(Icons.clear_all_rounded, size: 18),
                label: const Text('\u6e05\u7a7a\u5168\u90e8'),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < LayoutBreakpoints.compactMaxWidth;
              final narrow = constraints.maxWidth < 560;
              if (dense) {
                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 14 : 22,
                    2,
                    compact ? 14 : 22,
                    22,
                  ),
                  itemExtent: narrow ? 138 : 126,
                  itemCount: videos.length,
                  itemBuilder: (context, index) {
                    final item = videos[index];
                    return _RecentPlaybackRow(
                      item: item,
                      selected: selectedPathKeys
                          .contains(TagRules.pathKey(item.path)),
                      thumbnailService: thumbnailService,
                      playbackSettings: playbackSettings,
                      onOpen: () => onOpen(item, videos),
                      onEditTags: () => onEditTags(item),
                      onToggleFavorite: () => onToggleFavorite(item),
                      onDeleteVideo: () => onDeleteVideo(item),
                      onToggleSelected: () => onToggleSelected(item),
                      onDelete: () => onDeleteOne(item),
                    );
                  },
                );
              }
              return GridView.builder(
                padding: EdgeInsets.fromLTRB(
                    compact ? 14 : 22, 2, compact ? 14 : 22, 22),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: narrow ? 500 : (compact ? 248 : 286),
                  mainAxisExtent: libraryVideoCardMainAxisExtent(
                    gridWidth: constraints.maxWidth,
                    narrow: narrow,
                    compact: compact,
                  ),
                  mainAxisSpacing: compact ? 14 : 16,
                  crossAxisSpacing: compact ? 10 : 14,
                ),
                itemCount: videos.length,
                itemBuilder: (context, index) {
                  final item = videos[index];
                  return _RecentPlaybackCard(
                    item: item,
                    selected:
                        selectedPathKeys.contains(TagRules.pathKey(item.path)),
                    thumbnailService: thumbnailService,
                    playbackSettings: playbackSettings,
                    onOpen: () => onOpen(item, videos),
                    onToggleFavorite: () => onToggleFavorite(item),
                    onToggleSelected: () => onToggleSelected(item),
                    onDelete: () => onDeleteOne(item),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RecentPlaybackRow extends StatelessWidget {
  const _RecentPlaybackRow({
    required this.item,
    required this.selected,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.onOpen,
    required this.onEditTags,
    required this.onToggleFavorite,
    required this.onDeleteVideo,
    required this.onToggleSelected,
    required this.onDelete,
  });

  final VideoItem item;
  final bool selected;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  final VoidCallback onOpen;
  final VoidCallback onEditTags;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDeleteVideo;
  final VoidCallback onToggleSelected;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(value: selected, onChanged: (_) => onToggleSelected()),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: InteractiveVideoListRow(
                  item: item,
                  thumbnailService: thumbnailService,
                  playbackSettings: playbackSettings,
                  onOpen: onOpen,
                  onEditTags: onEditTags,
                  onToggleFavorite: onToggleFavorite,
                  onDelete: onDeleteVideo,
                ),
              ),
              LinearProgressIndicator(
                value: videoPlaybackProgressFraction(item),
                minHeight: 3,
                color: appAccentViolet,
                backgroundColor: libraryBorder,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '\u5220\u9664\u8be5\u64ad\u653e\u8bb0\u5f55',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}

class _RecentPlaybackCard extends StatelessWidget {
  const _RecentPlaybackCard({
    required this.item,
    required this.selected,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onToggleSelected,
    required this.onDelete,
  });

  final VideoItem item;
  final bool selected;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  final VoidCallback onOpen;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleSelected;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InteractiveVideoCard(
          item: item,
          thumbnailService: thumbnailService,
          playbackSettings: playbackSettings,
          onOpen: onOpen,
          onToggleFavorite: onToggleFavorite,
        ),
        Positioned(
          top: 8,
          left: 48,
          child:
              Checkbox(value: selected, onChanged: (_) => onToggleSelected()),
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 6,
          child: LinearProgressIndicator(
            value: videoPlaybackProgressFraction(item),
            minHeight: 4,
            borderRadius: BorderRadius.circular(99),
            color: appAccentViolet,
            backgroundColor: const Color(0x55000000),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton.filledTonal(
            tooltip: '\u5220\u9664\u8be5\u64ad\u653e\u8bb0\u5f55',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ),
      ],
    );
  }
}

/**
 * 本地媒体库路径浏览视图。
 *
 * 文件夹使用文件夹卡片/行，视频复用现有视频卡片/行；这样本地浏览不会绕开
 * 播放队列、收藏和更多编辑等媒体库已有行为。
 */
class TagEditorDialog extends StatefulWidget {
  const TagEditorDialog({
    super.key,
    required this.title,
    required this.initialTags,
    required this.existingTags,
    this.lockedTags = const <String>{},
    this.helperText,
    this.recentTags = const <String>[],
    this.favoriteTags = const <String>{},
  });

  final String title;
  final Set<String> initialTags;
  final Set<String> existingTags;

  /** 由 folder 等外部来源维护、在当前弹窗中只能查看不能删除的标签。 */
  final Set<String> lockedTags;

  /** 当前编辑范围和来源边界说明。 */
  final String? helperText;

  /** 当前会话最近使用的 manual 标签，顺序由调用方维护。 */
  final List<String> recentTags;

  /** 用户在标签中心标记为收藏的 manual 标签。 */
  final Set<String> favoriteTags;

  @override
  State<TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<TagEditorDialog> {
  late final Set<String> _tags = _normalizeTags(widget.initialTags);
  final _controller = TextEditingController();
  String _query = '';

  /** 当前选择是否与打开弹窗时不同；只用于提示未保存状态，不提前写入标签数据。 */
  bool _dirty = false;

  /** 统一保存入口，让按钮和 Ctrl+Enter 走同一条结果归一化链路。 */
  void _save() {
    _addTag(_controller.text);
    Navigator.of(context).pop(_tags);
  }

  /** 关闭弹窗但不提交修改；Escape 与取消按钮共用此入口。 */
  void _cancel() => Navigator.of(context).pop();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addTag(String raw) {
    final tag = TagRules.normalizeTag(raw);
    if (tag.isEmpty) {
      return;
    }
    setState(() {
      _dirty = _addNormalizedTag(tag) || _dirty;
      _controller.clear();
      _query = '';
    });
  }

  /** 添加归一化标签并返回当前选择是否真实发生变化。 */
  bool _addNormalizedTag(String tag) {
    if (!_tags.any((existing) => TagRules.sameTag(existing, tag))) {
      _tags.add(tag);
      return true;
    }
    return false;
  }

  /** 清除当前搜索词并恢复完整候选，不影响已经选择的标签。 */
  void _clearQuery() {
    _controller.clear();
    setState(() => _query = '');
  }

  /** 标签是否由当前弹窗之外的来源维护。 */
  bool _isLocked(String tag) =>
      widget.lockedTags.any((locked) => TagRules.sameTag(locked, tag));

  Set<String> _normalizeTags(Iterable<String> tags) {
    final normalized = <String>{};
    for (final raw in tags) {
      final tag = TagRules.normalizeTag(raw);
      if (tag.isEmpty ||
          normalized.any((existing) => TagRules.sameTag(existing, tag))) {
        continue;
      }
      normalized.add(tag);
    }
    return normalized;
  }

  /** 返回未选中且匹配当前搜索词的候选，保持大小写不敏感。 */
  List<String> _availableTags(
    Iterable<String> source, {
    bool sort = true,
  }) {
    final query = _query.trim().toLowerCase();
    final result = _normalizeTags(source.where(
      (tag) =>
          !_tags.any((selected) => TagRules.sameTag(selected, tag)) &&
          (query.isEmpty || tag.toLowerCase().contains(query)),
    )).toList();
    if (sort) {
      result.sort();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _availableTags(widget.existingTags);
    final recent = _availableTags(widget.recentTags, sort: false);
    final favorites = _availableTags(widget.favoriteTags);
    final theme = maintenanceWorkspaceTheme(Theme.of(context));
    return Theme(
      data: theme,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
          const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        },
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: AlertDialog(
            key: const ValueKey('tagEditor.dialog'),
            insetPadding: const EdgeInsets.all(24),
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: appAccentViolet.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: const SizedBox.square(
                    dimension: 40,
                    child: Icon(
                      Icons.sell_outlined,
                      color: libraryAccent,
                      size: 21,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '管理当前视频关联的标签',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: libraryTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: math.min(560, MediaQuery.sizeOf(context).width - 96),
              height: math.min(580, MediaQuery.sizeOf(context).height * 0.72),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.helperText != null) ...[
                    _TagEditorSectionCard(
                      title: '编辑范围',
                      icon: Icons.info_outline_rounded,
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        widget.helperText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: libraryTextMuted,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: '搜索或新建 manual 标签',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              key: const ValueKey('tagEditor.clearSearch'),
                              tooltip: '清除搜索',
                              onPressed: _clearQuery,
                              icon: const Icon(Icons.close_rounded),
                            ),
                      helperText: 'Tab 浏览候选，Enter 添加，Ctrl+Enter 保存，Esc 取消',
                    ),
                    // 搜索链路继续只使用当前 TextField/controller；清除不创建第二输入状态。
                    onChanged: (value) => setState(() => _query = value),
                    onSubmitted: _addTag,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _TagEditorSectionCard(
                      title: '当前与可用标签',
                      icon: Icons.local_offer_outlined,
                      expandChild: true,
                      trailing: Text(
                        '${_tags.length} 个已选',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: libraryAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final tag in (_tags.toList()..sort()))
                                  Tooltip(
                                    message: _isLocked(tag)
                                        ? '文件夹来源标签，只能通过目录结构修改'
                                        : '移除手动标签',
                                    child: InputChip(
                                      avatar: _isLocked(tag)
                                          ? const Icon(
                                              Icons.lock_outline_rounded,
                                              size: 15)
                                          : null,
                                      label: Text(tag),
                                      onDeleted: _isLocked(tag)
                                          ? null
                                          : () => setState(() {
                                                _dirty =
                                                    _tags.remove(tag) || _dirty;
                                              }),
                                      deleteButtonTooltipMessage:
                                          '从当前视频移除 $tag',
                                    ),
                                  ),
                              ],
                            ),
                            if (_tags.isEmpty)
                              const Text(
                                '尚未选择标签，可从下方候选添加或直接输入新标签。',
                                style: TextStyle(
                                  color: libraryTextMuted,
                                  height: 1.4,
                                ),
                              ),
                            _TagSuggestionSection(
                              title: '最近使用',
                              tags: recent.take(8).toList(),
                              icon: Icons.history_rounded,
                              onSelected: (tag) => setState(() {
                                _dirty = _addNormalizedTag(tag) || _dirty;
                              }),
                            ),
                            _TagSuggestionSection(
                              title: '收藏标签',
                              tags: favorites.take(8).toList(),
                              icon: Icons.star_rounded,
                              onSelected: (tag) => setState(() {
                                _dirty = _addNormalizedTag(tag) || _dirty;
                              }),
                            ),
                            _TagSuggestionSection(
                              title: _query.trim().isEmpty ? '全部可用标签' : '搜索结果',
                              tags: suggestions,
                              icon: Icons.sell_outlined,
                              onSelected: (tag) => setState(() {
                                _dirty = _addNormalizedTag(tag) || _dirty;
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_dirty) ...[
                    const SizedBox(height: 10),
                    Semantics(
                      liveRegion: true,
                      child: const Row(
                        key: ValueKey('tagEditor.unsavedChanges'),
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: libraryAccent,
                            size: 17,
                          ),
                          SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              '修改尚未保存；取消将放弃本次调整。',
                              style: TextStyle(
                                color: libraryTextMuted,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('tagEditor.cancel'),
                onPressed: _cancel,
                child: const Text('\u53d6\u6d88'),
              ),
              FilledButton.icon(
                key: const ValueKey('tagEditor.save'),
                onPressed: _save,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('\u4fdd\u5b58'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/** 标签编辑器内部统一的维护页面分区，不再借用播放器弹窗材质。 */
class _TagEditorSectionCard extends StatelessWidget {
  const _TagEditorSectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    this.expandChild = false,
  });

  /** 分区标题。 */
  final String title;

  /** 分区语义图标。 */
  final IconData icon;

  /** 分区主体。 */
  final Widget child;

  /** 标题右侧的数量或状态。 */
  final Widget? trailing;

  /** 分区内边距。 */
  final EdgeInsetsGeometry padding;

  /** 是否让主体占满分区剩余高度。 */
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: librarySurfaceAlt.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: libraryBorder),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: libraryAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: libraryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            if (expandChild) Expanded(child: child) else child,
          ],
        ),
      ),
    );
  }
}

/** manual 标签编辑器中的轻量候选分区。 */
class _TagSuggestionSection extends StatelessWidget {
  const _TagSuggestionSection({
    required this.title,
    required this.tags,
    required this.icon,
    required this.onSelected,
  });

  final String title;
  final List<String> tags;
  final IconData icon;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: libraryAccent),
              const SizedBox(width: 6),
              Text(title, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in tags)
                ActionChip(
                  label: Text(tag),
                  onPressed: () => onSelected(tag),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
