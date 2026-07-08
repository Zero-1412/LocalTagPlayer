part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

enum SortMode { recent, name, folder }

class LibrarySmokeKeys {
  const LibrarySmokeKeys._();

  static const localPointerBackRegion =
      ValueKey<String>('smoke.local.pointer-back-region');
  static const localBackButton = ValueKey<String>('smoke.local.back-button');
  static const primaryTab = ValueKey<String>('smoke.tag.primary-tab');
  static const secondaryTab = ValueKey<String>('smoke.tag.secondary-tab');
  static const moreSecondaryTags =
      ValueKey<String>('smoke.tag.more-secondary-tags');
  static const listActionState = ValueKey<String>('smoke.list.action-state');
  static const collapsedTagRail = ValueKey<String>('smoke.tag.collapsed-rail');
  static const searchField = ValueKey<String>('smoke.top.search-field');

  /**
   * 本地媒体库 root 项命中标识。
   *
   * key 使用 pathKey 保持 Windows 大小写不敏感路径在测试和运行时一致。
   */
  static ValueKey<String> localRoot(String path) =>
      ValueKey<String>('smoke.local.root:${TagRules.pathKey(path)}');

  /**
   * 本地媒体库文件夹项命中标识。
   */
  static ValueKey<String> localFolder(String path) =>
      ValueKey<String>('smoke.local.folder:${TagRules.pathKey(path)}');

  /**
   * 右侧一级折叠行命中标识。
   */
  static ValueKey<String> primaryRow(String tagId) =>
      ValueKey<String>('smoke.tag.primary-row:$tagId');

  /**
   * 右侧一级展开卡片标题行命中标识。
   */
  static ValueKey<String> primaryHeader(String tagId) =>
      ValueKey<String>('smoke.tag.primary-header:$tagId');

  /**
   * 右侧一级卡片内“展开全部 / 收起”命中标识。
   */
  static ValueKey<String> childExpandButton(String tagId) =>
      ValueKey<String>('smoke.tag.child-expand:$tagId');

  /**
   * 列表行整行命中标识。
   */
  static ValueKey<String> videoListRow(String path) =>
      ValueKey<String>('smoke.list.row:${TagRules.pathKey(path)}');

  /**
   * 列表行播放按钮命中标识。
   */
  static ValueKey<String> listPlay(String path) =>
      ValueKey<String>('smoke.list.play:${TagRules.pathKey(path)}');

  /**
   * 列表行收藏按钮命中标识。
   */
  static ValueKey<String> listFavorite(String path) =>
      ValueKey<String>('smoke.list.favorite:${TagRules.pathKey(path)}');

  /**
   * 列表行更多按钮命中标识。
   */
  static ValueKey<String> listMore(String path) =>
      ValueKey<String>('smoke.list.more:${TagRules.pathKey(path)}');

  /**
   * 右侧标签 chip 命中标识。
   */
  static ValueKey<String> tagChip(String tagId) =>
      ValueKey<String>('smoke.tag.chip:$tagId');

  /**
   * 右侧标签筛选后结果项标识。
   */
  static ValueKey<String> tagResult(String title) =>
      ValueKey<String>('smoke.tag.result:$title');
}

class _DesktopDragScrollBehavior extends MaterialScrollBehavior {
  const _DesktopDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

Color _groupColor(String groupId) {
  return switch (groupId) {
    'folder.primary' => _appAccentViolet,
    'folder.child' => const Color(0xff6366f1),
    'manual' => const Color(0xff0f766e),
    _ => const Color(0xff64748b),
  };
}

String _formatCount(int value) {
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
    if (tag.groupId == 'folder.primary') {
      primaryByName[tag.name] = tag;
      if (tag.displayName != null) {
        primaryByName[tag.displayName!] = tag;
      }
    }
  }

  final grouped = <String, List<TagItem>>{};
  for (final tag in tags) {
    if (tag.groupId != 'folder.child') {
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
          items: group.items,
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
          if (!TagRules.sameTag(
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

class _Sidebar extends StatelessWidget {
  const _Sidebar({
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
    required this.onOpenSettings,
    required this.onChildTagToggle,
    required this.onClearChildTags,
    required this.onGroupTagToggle,
    required this.onGroupTagExcludeToggle,
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
  final bool favoriteVideosSelected;
  final bool recentPlaybackSelected;
  final bool localLibrarySelected;
  final Set<String> selectedTags;
  final bool isScanning;
  final bool dense;
  final VoidCallback onPickFolder;
  final VoidCallback onShowAllLibrary;
  final VoidCallback onRescan;
  final ValueChanged<String> onRemoveLocalLibraryRoot;
  final VoidCallback onFavoritesToggle;
  final VoidCallback onOpenRecentPlayback;
  final ValueChanged<String> onOpenLocalLibraryRoot;
  final VoidCallback onOpenDirectoryManager;
  final VoidCallback onOpenSettings;
  final ValueChanged<String> onChildTagToggle;
  final VoidCallback onClearChildTags;
  final ValueChanged<TagItem> onGroupTagToggle;
  final ValueChanged<TagItem> onGroupTagExcludeToggle;
  /** expanded 主界面按窗口比例计算出的侧栏宽度；medium 继续使用默认密度宽度。 */
  final double? width;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? (dense ? 248 : 274),
      height: MediaQuery.sizeOf(context).height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: _appShell,
          border: Border(right: BorderSide(color: Color(0xff263244))),
        ),
        child: SafeArea(
          child: Padding(
            padding:
                EdgeInsets.fromLTRB(dense ? 16 : 22, 18, dense ? 16 : 22, 18),
            child: Column(
              children: [
                Expanded(
                  child: ScrollConfiguration(
                    behavior: const _DesktopDragScrollBehavior(),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        const _SidebarBrand(),
                        const SizedBox(height: 24),
                        _SidebarPrimaryButton(
                          icon: Icons.add_rounded,
                          label: '\u6dfb\u52a0\u76ee\u5f55',
                          onPressed: isScanning ? null : onPickFolder,
                        ),
                        const SizedBox(height: 24),
                        _SidebarNavItem(
                          icon: Icons.grid_view_rounded,
                          label: '\u5a92\u4f53\u5e93',
                          selected: !recentPlaybackSelected &&
                              !favoriteVideosSelected &&
                              !localLibrarySelected,
                          trailing:
                              roots.isEmpty ? null : roots.length.toString(),
                          onTap: onShowAllLibrary,
                        ),
                        _SidebarNavItem(
                          icon: Icons.history_rounded,
                          label: '\u6700\u8fd1\u64ad\u653e',
                          selected: recentPlaybackSelected,
                          trailing: null,
                          onTap: onOpenRecentPlayback,
                        ),
                        _SidebarNavItem(
                          icon: Icons.auto_awesome_outlined,
                          label: '\u667a\u80fd\u6536\u85cf',
                          selected: favoriteVideosSelected,
                          trailing: favoriteCount.toString(),
                          onTap: onFavoritesToggle,
                        ),
                        const SizedBox(height: 18),
                        _SidebarSectionLabel(
                            label: '\u76ee\u5f55\u4e0e\u670d\u52a1'),
                        const SizedBox(height: 8),
                        _SidebarNavItem(
                          icon: Icons.folder_copy_outlined,
                          label: '\u76ee\u5f55\u7ba1\u7406',
                          selected: false,
                          trailing:
                              roots.isEmpty ? null : roots.length.toString(),
                          onTap: onOpenDirectoryManager,
                        ),
                        _SidebarNavItem(
                          icon: isScanning
                              ? Icons.hourglass_empty_rounded
                              : Icons.sync_rounded,
                          label: isScanning
                              ? '\u626b\u63cf\u4e2d'
                              : '\u91cd\u65b0\u626b\u63cf',
                          selected: false,
                          onTap: isScanning || roots.isEmpty ? null : onRescan,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Expanded(
                              child: _SidebarSectionLabel(
                                label: '\u672c\u5730\u5a92\u4f53\u5e93',
                              ),
                            ),
                            IconButton(
                              tooltip:
                                  '\u65b0\u589e\u672c\u5730\u5e93\u8def\u5f84',
                              onPressed: isScanning ? null : onPickFolder,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              color: const Color(0xffcbd5e1),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
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
                            height: math.min(220, 42.0 * roots.length),
                            child: ScrollConfiguration(
                              behavior: const _DesktopDragScrollBehavior(),
                              child: ListView.builder(
                                itemExtent: 42,
                                padding: EdgeInsets.zero,
                                itemCount: roots.length,
                                itemBuilder: (context, index) {
                                  final root = roots[index];
                                  return _SidebarLocalLibraryItem(
                                    path: root,
                                    selected: selectedLocalLibraryPath !=
                                            null &&
                                        TagRules.pathKey(
                                                selectedLocalLibraryPath!) ==
                                            TagRules.pathKey(root),
                                    onTap: () => onOpenLocalLibraryRoot(root),
                                    onRemove: () =>
                                        onRemoveLocalLibraryRoot(root),
                                  );
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: 18),
                        _SidebarSectionLabel(label: '\u5b58\u50a8\u4f4d\u7f6e'),
                        const SizedBox(height: 8),
                        if (roots.isEmpty)
                          const Text(
                            '\u8fd8\u6ca1\u6709\u6dfb\u52a0\u76ee\u5f55',
                            style: TextStyle(
                                color: Color(0xff718096), fontSize: 12),
                          )
                        else
                          for (final root in roots.take(2))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    root,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xffcbd5e1),
                                      fontSize: 11,
                                      height: 1.25,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: const LinearProgressIndicator(
                                      minHeight: 4,
                                      value: 0.58,
                                      color: _appAccentViolet,
                                      backgroundColor: Color(0xff293548),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        const SizedBox(height: 12),
                        _SidebarLibraryStat(
                          label: '\u6807\u7b7e',
                          value: tags.length.toString(),
                        ),
                        const SizedBox(height: 6),
                        _SidebarLibraryStat(
                          label: '\u5206\u7ec4',
                          value: tagGroups.length.toString(),
                        ),
                        if (roots.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: const LinearProgressIndicator(
                              minHeight: 4,
                              value: 0.58,
                              color: _appAccentViolet,
                              backgroundColor: Color(0xff293548),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _SidebarNavItem(
                  icon: Icons.settings_outlined,
                  label: '\u8bbe\u7f6e',
                  selected: false,
                  onTap: onOpenSettings,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xff718096),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
    );
  }
}

class _SidebarPrimaryButton extends StatelessWidget {
  const _SidebarPrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: _appAccentViolet,
          disabledBackgroundColor: const Color(0xff334155),
          foregroundColor: Colors.white,
          disabledForegroundColor: const Color(0xff94a3b8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: _appAccentViolet,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: _appAccentViolet.withAlpha(90),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 32,
          ),
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
                  fontSize: 16,
                  height: 1.18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '\u672c\u5730\u89c6\u9891\u7ba1\u7406\u5de5\u4f5c\u53f0',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xff95a3b8),
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SidebarLibraryStat extends StatelessWidget {
  const _SidebarLibraryStat({
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

class _SidebarLocalLibraryItem extends StatelessWidget {
  const _SidebarLocalLibraryItem({
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
    return Material(
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
                color: selected ? _appAccentViolet : const Color(0xff94a3b8),
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
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        button: onTap != null,
        selected: selected,
        label: label,
        child: Material(
          color: selected ? const Color(0xff283449) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected ? Colors.white : const Color(0xff94a3b8),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            selected ? Colors.white : const Color(0xffcbd5e1),
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
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

class _LibraryHeroArea extends StatelessWidget {
  const _LibraryHeroArea({
    required this.selectedTags,
    required this.selectedChildTags,
    required this.selectedGroupTags,
    required this.excludedTags,
    required this.keyword,
    required this.defaultChipLabel,
    required this.querySummary,
    required this.queryExpression,
    required this.showFavoritesOnly,
    required this.resultCount,
    required this.totalCount,
    required this.refreshing,
    required this.onRemovePrimaryTag,
    required this.onRemoveChildTag,
    required this.onRemoveGroupTag,
    required this.onRemoveExcludedTag,
    required this.onClearKeyword,
    required this.onClearFavoritesOnly,
    required this.onClearAll,
  });

  final List<String> selectedTags;

  final List<String> selectedChildTags;

  final List<TagItem> selectedGroupTags;

  final List<TagItem> excludedTags;

  final String keyword;

  final String defaultChipLabel;

  final String querySummary;

  final String queryExpression;

  final bool showFavoritesOnly;

  final int resultCount;

  final int totalCount;

  final bool refreshing;

  final ValueChanged<String> onRemovePrimaryTag;

  final ValueChanged<String> onRemoveChildTag;

  final ValueChanged<TagItem> onRemoveGroupTag;

  final ValueChanged<TagItem> onRemoveExcludedTag;

  final VoidCallback onClearKeyword;

  final VoidCallback onClearFavoritesOnly;

  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    final activeChips = <Widget>[
      if (keyword.trim().isNotEmpty)
        _CurrentFilterChip(
          avatar: const Icon(Icons.search_rounded, size: 18),
          label: Text(keyword.trim()),
          onDeleted: onClearKeyword,
        ),
      if (showFavoritesOnly)
        _CurrentFilterChip(
          avatar: const Icon(Icons.favorite, size: 18),
          label: const Text('\u667a\u80fd\u6536\u85cf'),
          onDeleted: onClearFavoritesOnly,
        ),
      for (final tag in selectedTags)
        _CurrentFilterChip(
          label: Text('\u4e00\u7ea7\u6807\u7b7e\uff1a$tag'),
          onDeleted: () => onRemovePrimaryTag(tag),
        ),
      for (final tag in selectedChildTags)
        _CurrentFilterChip(
          label: Text('\u4e8c\u7ea7\u6807\u7b7e\uff1a$tag'),
          onDeleted: () => onRemoveChildTag(tag),
        ),
      for (final tag in selectedGroupTags)
        _CurrentFilterChip(
          avatar: Icon(
            Icons.add_circle_outline,
            size: 18,
            color: _groupColor(tag.groupId ?? 'manual'),
          ),
          label: Text(tag.displayName ?? tag.name),
          side: BorderSide(
            color: _groupColor(tag.groupId ?? 'manual').withAlpha(150),
          ),
          onDeleted: () => onRemoveGroupTag(tag),
        ),
      for (final tag in excludedTags)
        _CurrentFilterChip(
          avatar: const Icon(Icons.remove_circle_outline, size: 18),
          label: Text('NOT ${tag.displayName ?? tag.name}'),
          selected: true,
          selectedColor: const Color(0xffffe3df),
          onDeleted: () => onRemoveExcludedTag(tag),
        ),
      if (onClearAll == null)
        _CurrentFilterChip(
          avatar: const Icon(Icons.video_library_outlined, size: 18),
          label: Text(defaultChipLabel),
          visualDensity: VisualDensity.compact,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 18, 14),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: _appPanel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _appBorder),
          boxShadow: _appSoftShadow,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final title = Text(
              '\u5f53\u524d\u7b5b\u9009\uff08AND\uff09',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _appText,
                    fontWeight: FontWeight.w900,
                  ),
            );
            final clearAction = TextButton.icon(
              onPressed: onClearAll,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('\u6e05\u7a7a\u5168\u90e8'),
              style: TextButton.styleFrom(
                foregroundColor: _appTextMuted,
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            );
            final resultLine = _FilterResultLine(
              resultCount: resultCount,
              querySummary: querySummary,
              refreshing: refreshing,
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [...activeChips, clearAction],
                  ),
                  const SizedBox(height: 10),
                  resultLine,
                  Tooltip(
                    message: queryExpression,
                    child: const SizedBox(height: 1, width: double.infinity),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    title,
                    const SizedBox(width: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final chip in activeChips) ...[
                              chip,
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                    clearAction,
                    const SizedBox(width: 12),
                    resultLine,
                  ],
                ),
                Tooltip(
                  message: queryExpression,
                  child: const SizedBox(height: 1, width: double.infinity),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CurrentFilterChip extends StatelessWidget {
  const _CurrentFilterChip({
    required this.label,
    this.avatar,
    this.onDeleted,
    this.visualDensity,
    this.selected = false,
    this.selectedColor,
    this.side,
  });

  final Widget? avatar;

  final Widget label;

  final VoidCallback? onDeleted;

  final VisualDensity? visualDensity;

  final bool selected;

  final Color? selectedColor;

  final BorderSide? side;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: avatar,
      label: label,
      onDeleted: onDeleted,
      visualDensity: visualDensity ?? VisualDensity.compact,
      selected: selected,
      selectedColor: selectedColor,
      side: side ?? const BorderSide(color: Color(0xffd8d4ff)),
      backgroundColor: const Color(0xfff6f4ff),
      deleteIconColor: _appAccentViolet,
      labelStyle: const TextStyle(
        color: _appAccentViolet,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class _FilterResultLine extends StatelessWidget {
  const _FilterResultLine({
    required this.resultCount,
    required this.querySummary,
    required this.refreshing,
  });

  final int resultCount;

  final String querySummary;

  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: querySummary,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '\u5171',
            style: TextStyle(
              color: _appTextMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            _formatCount(resultCount),
            style: const TextStyle(
              color: _appAccentViolet,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Text(
            ' \u4e2a\u89c6\u9891',
            style: TextStyle(
              color: _appTextMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (refreshing) ...[
            const SizedBox(width: 8),
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }
}

class _SmartListDraftDialog extends StatefulWidget {
  const _SmartListDraftDialog({
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
  State<_SmartListDraftDialog> createState() => _SmartListDraftDialogState();
}

class _SmartListDraftDialogState extends State<_SmartListDraftDialog> {
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
                color: _appAccentViolet, size: 20),
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
        color: const Color(0xfff8fafc),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.manage_search_rounded,
                  size: 18, color: _appAccentViolet),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  querySummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _appText,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$resultCount / $totalCount',
                style: const TextStyle(
                  color: _appAccentViolet,
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
              color: _appTextMuted,
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

enum _TagDiscoveryMode { primary, secondary }

enum _PrimaryTagSortMode { countDesc, nameAsc, frequentDesc }

class _TagDiscoveryZone extends StatefulWidget {
  const _TagDiscoveryZone({
    required this.tagGroups,
    required this.resultCounts,
    required this.favoriteTags,
    required this.selectedTags,
    required this.selectedChildTags,
    required this.selectedGroupTagIds,
    required this.excludedTagIds,
    required this.childParentTag,
    required this.childTags,
    required this.childTagItemsByParent,
    required this.favoriteCount,
    required this.showFavoritesOnly,
    required this.dense,
    required this.onFavoritesToggle,
    required this.onTagToggle,
    required this.onChildTagToggle,
    required this.onGroupTagToggle,
    required this.onFolderPrimaryChildSelected,
    required this.onGroupTagExcludeToggle,
    this.onCollapse,
    this.panelWidth,
  });

  final List<TagGroup> tagGroups;
  final Map<String, int> resultCounts;
  final List<String> favoriteTags;
  final Set<String> selectedTags;
  final Set<String> selectedChildTags;
  final Map<String, Set<String>> selectedGroupTagIds;
  final Set<String> excludedTagIds;
  final String? childParentTag;
  final List<String> childTags;
  final Map<String, List<TagItem>> childTagItemsByParent;
  final int favoriteCount;
  final bool showFavoritesOnly;
  final bool dense;
  final VoidCallback onFavoritesToggle;
  final ValueChanged<String> onTagToggle;
  final ValueChanged<String> onChildTagToggle;
  final ValueChanged<TagItem> onGroupTagToggle;
  final void Function(TagItem primary, TagItem? child)
      onFolderPrimaryChildSelected;
  final ValueChanged<TagItem> onGroupTagExcludeToggle;
  final VoidCallback? onCollapse;
  /** expanded 主界面按窗口比例计算出的右侧面板外框宽度。 */
  final double? panelWidth;

  @override
  State<_TagDiscoveryZone> createState() => _TagDiscoveryZoneState();
}

class _TagDiscoveryZoneState extends State<_TagDiscoveryZone> {
  late final TextEditingController _tagSearchController =
      TextEditingController();

  final _panelScrollController = ScrollController();

  var _mode = _TagDiscoveryMode.primary;

  String? _expandedPrimaryTagId;

  var _showAllPrimaryTags = false;

  var _showAllHotSecondaryTags = false;

  final _expandedChildTagIds = <String>{};

  @override
  void dispose() {
    _tagSearchController.dispose();
    _panelScrollController.dispose();
    super.dispose();
  }

  bool _matchesSearch(String value) {
    final keyword = _tagSearchController.text.trim().toLowerCase();
    if (keyword.isEmpty) {
      return true;
    }
    return value.toLowerCase().contains(keyword);
  }

  TagGroup _filteredGroup(TagGroup group) {
    return TagGroup(
      id: group.id,
      name: group.name,
      displayName: group.displayName,
      sortOrder: group.sortOrder,
      allowMultiSelect: group.allowMultiSelect,
      defaultLogic: group.defaultLogic,
      items: [
        for (final tag in group.items)
          if (!TagRules.sameTag(tag.name, TagRules.defaultAlbumTag) &&
              _matchesSearch(tag.displayName ?? tag.name))
            tag,
      ],
      excludedItems: group.excludedItems,
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryGroups =
        primaryTagGroupsForDiscovery(widget.tagGroups).map(_filteredGroup);
    final allSecondaryTags = secondaryTagsForDiscovery(
      widget.tagGroups,
      widget.resultCounts,
    ).where((tag) => _matchesSearch(tag.displayName ?? tag.name)).toList();
    // 热门区保留蓝图里的轻量入口，完整列表由“全部二级标签”页签承载。
    final hotSecondaryTags = _showAllHotSecondaryTags
        ? allSecondaryTags
        : allSecondaryTags.take(12).toList();

    final outerPanelWidth = widget.panelWidth ?? 482.0;
    final innerPanelWidth =
        (outerPanelWidth - 44).clamp(276.0, 576.0).toDouble();
    final panel = Container(
      width: widget.dense ? double.infinity : innerPanelWidth,
      margin: EdgeInsets.fromLTRB(widget.dense ? 16 : 20, 16, 24, 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _appPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffe6ecf5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0f172a).withAlpha(10),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_alt_outlined,
                  color: _appAccentViolet, size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '\u6807\u7b7e\u7b5b\u9009',
                  style: TextStyle(
                    color: _appText,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (widget.onCollapse != null)
                IconButton(
                  tooltip: '\u6536\u8d77\u6807\u7b7e\u7b5b\u9009',
                  onPressed: widget.onCollapse,
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            height: 44,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xfff1f5f9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TagPanelTabButton(
                    key: LibrarySmokeKeys.primaryTab,
                    label: '\u4e00\u7ea7\u6807\u7b7e',
                    selected: _mode == _TagDiscoveryMode.primary,
                    onTap: () => setState(() {
                      _mode = _TagDiscoveryMode.primary;
                    }),
                  ),
                ),
                Expanded(
                  child: _TagPanelTabButton(
                    key: LibrarySmokeKeys.secondaryTab,
                    label: '\u5168\u90e8\u4e8c\u7ea7\u6807\u7b7e',
                    selected: _mode == _TagDiscoveryMode.secondary,
                    onTap: () => setState(() {
                      _mode = _TagDiscoveryMode.secondary;
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '\u9009\u62e9\u4e00\u7ea7\u6807\u7b7e\u4ee5\u67e5\u770b\u5bf9\u5e94\u7684\u4e8c\u7ea7\u6807\u7b7e\uff08\u4e0e\u5176\u4ed6\u6761\u4ef6\u4e3a AND \u5173\u7cfb\uff09',
            style: TextStyle(
              color: Color(0xff64748b),
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ScrollConfiguration(
              behavior: const _DesktopDragScrollBehavior(),
              child: ListView(
                controller: _panelScrollController,
                children: [
                  if (_mode == _TagDiscoveryMode.primary) ...[
                    for (final group in primaryGroups)
                      _DiscoveryGroupCard(
                        group: group,
                        primary: true,
                        childItemsByParent: widget.childTagItemsByParent,
                        resultCounts: widget.resultCounts,
                        stablePrimaryCounts: widget.resultCounts,
                        primaryClickCounts: const <String, int>{},
                        selectedIds: widget.selectedGroupTagIds[group.id] ??
                            const <String>{},
                        childSelectedIds:
                            widget.selectedGroupTagIds['folder.child'] ??
                                const <String>{},
                        excludedIds: widget.excludedTagIds,
                        onToggle: widget.onGroupTagToggle,
                        onFolderPrimaryChildSelected:
                            widget.onFolderPrimaryChildSelected,
                        onExcludeToggle: widget.onGroupTagExcludeToggle,
                        expandedPrimaryTagId: _expandedPrimaryTagId,
                        showAllPrimaryTags: _showAllPrimaryTags,
                        primarySortMode: _PrimaryTagSortMode.countDesc,
                        expandedChildTagIds: _expandedChildTagIds,
                        onExpandedPrimaryChanged: (tag) => setState(() {
                          _expandedPrimaryTagId =
                              _expandedPrimaryTagId == tag.id ? null : tag.id;
                        }),
                        onShowAllPrimaryTags: () => setState(() {
                          _showAllPrimaryTags = !_showAllPrimaryTags;
                        }),
                        onExpandChildTags: (tag) => setState(() {
                          if (!_expandedChildTagIds.add(tag.id)) {
                            _expandedChildTagIds.remove(tag.id);
                          }
                        }),
                      ),
                    const SizedBox(height: 16),
                    const _HotSecondaryTitle(),
                    const SizedBox(height: 10),
                    _SecondaryTagCloud(
                      tags: hotSecondaryTags,
                      allSecondaryTags: allSecondaryTags,
                      resultCounts: widget.resultCounts,
                      selectedGroupTagIds: widget.selectedGroupTagIds,
                      excludedTagIds: widget.excludedTagIds,
                      showParentLabel: false,
                      showParentLabelForConflicts: true,
                      onGroupTagToggle: widget.onGroupTagToggle,
                      onGroupTagExcludeToggle: widget.onGroupTagExcludeToggle,
                    ),
                    _MoreSecondaryButton(
                      expanded: _showAllHotSecondaryTags,
                      visibleCount: hotSecondaryTags.length,
                      totalCount: allSecondaryTags.length,
                      onPressed: allSecondaryTags.length > 12
                          ? () => setState(() {
                                _showAllHotSecondaryTags =
                                    !_showAllHotSecondaryTags;
                              })
                          : null,
                    ),
                  ] else ...[
                    _SecondaryTagCloud(
                      tags: allSecondaryTags,
                      allSecondaryTags: allSecondaryTags,
                      resultCounts: widget.resultCounts,
                      selectedGroupTagIds: widget.selectedGroupTagIds,
                      excludedTagIds: widget.excludedTagIds,
                      showParentLabel: true,
                      showParentLabelForConflicts: false,
                      onGroupTagToggle: widget.onGroupTagToggle,
                      onGroupTagExcludeToggle: widget.onGroupTagExcludeToggle,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.dense) {
      return panel;
    }
    return SizedBox(width: outerPanelWidth, child: panel);
  }
}

class _TagPanelTabButton extends StatelessWidget {
  const _TagPanelTabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;

  final bool selected;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _appAccentViolet : _appTextMuted,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _SmartFilterContextCard extends StatelessWidget {
  const _SmartFilterContextCard({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    // 空筛选时仍展示“全部视频”，避免上下文卡片在空列表下消失。
    final effectiveItems =
        items.isEmpty ? const ['\u5168\u90e8\u89c6\u9891'] : items;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xfff3f0ff),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffc9c2ff)),
        boxShadow: [
          BoxShadow(
            color: _appAccentViolet.withAlpha(18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_tree_outlined,
                  size: 16, color: _appAccentViolet),
              SizedBox(width: 6),
              Text(
                '\u5f53\u524d\u7b5b\u9009\uff08\u0041\u004e\u0044\uff09',
                style: TextStyle(
                  color: _appAccentViolet,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final item in effectiveItems.take(8))
                Container(
                  height: 20,
                  constraints: const BoxConstraints(maxWidth: 104),
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    color: _appPanel,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: const Color(0xffd8d4ff)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sell_outlined,
                          size: 11, color: _appAccentViolet),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          item,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _appText,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _ActivePathBar extends StatelessWidget {
  const _ActivePathBar({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final effectiveItems =
        items.isEmpty ? const ['\u5168\u90e8\u89c6\u9891'] : items;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xffeef4f3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _appBorder),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.route_outlined, size: 18, color: _appAccentStrong),
          for (var index = 0; index < effectiveItems.length; index++) ...[
            if (index > 0)
              const Icon(Icons.chevron_right, size: 16, color: _appTextMuted),
            Text(
              effectiveItems[index],
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: index == effectiveItems.length - 1
                        ? _appAccentStrong
                        : _appTextMuted,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

// ignore: unused_element
class _PopularTagRail extends StatelessWidget {
  const _PopularTagRail({
    required this.favoriteTags,
    required this.groupTags,
    required this.resultCounts,
    required this.selectedTags,
    required this.selectedGroupTagIds,
    required this.excludedTagIds,
    required this.favoriteCount,
    required this.showFavoritesOnly,
    required this.onFavoritesToggle,
    required this.onTagToggle,
    required this.onGroupTagToggle,
    required this.onGroupTagExcludeToggle,
  });

  final List<String> favoriteTags;

  final List<TagItem> groupTags;

  final Map<String, int> resultCounts;

  final Set<String> selectedTags;

  final Map<String, Set<String>> selectedGroupTagIds;

  final Set<String> excludedTagIds;

  final int favoriteCount;

  final bool showFavoritesOnly;

  final VoidCallback onFavoritesToggle;

  final ValueChanged<String> onTagToggle;

  final ValueChanged<TagItem> onGroupTagToggle;

  final ValueChanged<TagItem> onGroupTagExcludeToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '\u5feb\u6377',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _appTextMuted,
                fontWeight: FontWeight.w900,
              ),
        ),
        FilterChip(
          avatar: const Icon(Icons.favorite_border, size: 15),
          label: Text('\u6536\u85cf $favoriteCount'),
          selected: showFavoritesOnly,
          selectedColor: const Color(0xffffe1e8),
          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
          onSelected: (_) => onFavoritesToggle(),
        ),
        for (final tag in favoriteTags.take(5))
          FilterChip(
            avatar: const Icon(Icons.star_outline, size: 15),
            label: Text(tag),
            selected: selectedTags.contains(tag),
            selectedColor: const Color(0xfffff0c2),
            visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
            onSelected: (_) => onTagToggle(tag),
          ),
        for (final tag in groupTags)
          _TagFilterChip(
            tag: tag,
            groupColor: _groupColor(tag.groupId ?? 'manual'),
            count: resultCounts[tag.id] ?? 0,
            selected: selectedGroupTagIds[tag.groupId ?? 'manual']
                    ?.contains(tag.id) ??
                false,
            excluded: excludedTagIds.contains(tag.id),
            onToggle: () => onGroupTagToggle(tag),
            onExcludeToggle: () => onGroupTagExcludeToggle(tag),
          ),
      ],
    );
  }
}

class _SecondaryTagCloud extends StatelessWidget {
  const _SecondaryTagCloud({
    required this.tags,
    required this.allSecondaryTags,
    required this.resultCounts,
    required this.selectedGroupTagIds,
    required this.excludedTagIds,
    required this.showParentLabel,
    required this.showParentLabelForConflicts,
    required this.onGroupTagToggle,
    required this.onGroupTagExcludeToggle,
  });

  final List<TagItem> tags;
  final List<TagItem> allSecondaryTags;
  final Map<String, int> resultCounts;
  final Map<String, Set<String>> selectedGroupTagIds;
  final Set<String> excludedTagIds;
  final bool showParentLabel;
  final bool showParentLabelForConflicts;
  final ValueChanged<TagItem> onGroupTagToggle;
  final ValueChanged<TagItem> onGroupTagExcludeToggle;

  @override
  Widget build(BuildContext context) {
    const spacing = 9.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: spacing,
          runSpacing: 9,
          children: [
            for (final tag in tags)
              _SecondaryTagPill(
                tag: tag,
                count: resultCounts[tag.id] ?? 0,
                showParentLabel: showParentLabel ||
                    (showParentLabelForConflicts &&
                        secondaryTagNameHasConflict(tag, allSecondaryTags)),
                selected: selectedGroupTagIds[tag.groupId ?? 'manual']
                        ?.contains(tag.id) ??
                    false,
                excluded: excludedTagIds.contains(tag.id),
                onToggle: () => onGroupTagToggle(tag),
                onExcludeToggle: () => onGroupTagExcludeToggle(tag),
              ),
          ],
        );
      },
    );
  }
}

class _HotSecondaryTitle extends StatelessWidget {
  const _HotSecondaryTitle();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '\u70ed\u95e8\u4e8c\u7ea7\u6807\u7b7e\uff08\u53ef\u76f4\u63a5\u9009\u62e9\uff09',
      style: TextStyle(
        color: _appText,
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _MoreSecondaryButton extends StatelessWidget {
  const _MoreSecondaryButton({
    required this.expanded,
    required this.visibleCount,
    required this.totalCount,
    required this.onPressed,
  });

  final bool expanded;
  final int visibleCount;
  final int totalCount;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = expanded
        ? '\u6536\u8d77\u6807\u7b7e \u2303'
        : '\u66f4\u591a\u6807\u7b7e ($visibleCount/$totalCount) \u2304';
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Center(
        child: OutlinedButton(
          key: LibrarySmokeKeys.moreSecondaryTags,
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: _appAccentViolet,
            disabledForegroundColor: _appTextMuted,
            backgroundColor: const Color(0xfffbfaff),
            side: const BorderSide(color: Color(0xffd8d4ff)),
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(118, 32),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _SecondaryTagPill extends StatelessWidget {
  const _SecondaryTagPill({
    required this.tag,
    required this.count,
    required this.showParentLabel,
    required this.selected,
    required this.excluded,
    required this.onToggle,
    required this.onExcludeToggle,
  });

  final TagItem tag;
  final int count;
  final bool showParentLabel;
  final bool selected;
  final bool excluded;
  final VoidCallback onToggle;
  final VoidCallback onExcludeToggle;

  @override
  Widget build(BuildContext context) {
    final parentLabel =
        secondaryTagParentLabel(tag, showParentLabel: showParentLabel);
    final background = excluded
        ? const Color(0xfffff1f0)
        : selected
            ? const Color(0xfff2efff)
            : Colors.white;
    final border = excluded
        ? const Color(0xffffb4ad)
        : selected
            ? const Color(0xffd2caff)
            : const Color(0xffe6ecf5);
    final textColor = excluded ? const Color(0xffb42318) : _appAccentViolet;
    return Tooltip(
      message:
          '\u70b9\u51fb\u52a0\u5165\u7b5b\u9009\uff0c\u957f\u6309\u8bbe\u4e3a NOT \u6392\u9664',
      child: GestureDetector(
        onLongPress: onExcludeToggle,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onToggle,
            child: Container(
              constraints: const BoxConstraints(minHeight: 31),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected || excluded) ...[
                    Icon(
                      excluded
                          ? Icons.remove_circle_outline
                          : Icons.check_circle_rounded,
                      size: 15,
                      color: textColor,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      excluded
                          ? 'NOT ${tag.displayName ?? tag.name}'
                          : (tag.displayName ?? tag.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (parentLabel != null && parentLabel.isNotEmpty) ...[
                    const SizedBox(width: 7),
                    Container(
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xfff1f5f9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        parentLabel,
                        style: const TextStyle(
                          color: Color(0xff94a3b8),
                          fontSize: 10,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TagFilterChip extends StatelessWidget {
  const _TagFilterChip({
    required this.tag,
    required this.groupColor,
    required this.count,
    required this.selected,
    required this.excluded,
    required this.onToggle,
    required this.onExcludeToggle,
  });

  final TagItem tag;

  final Color groupColor;

  final int count;

  final bool selected;

  final bool excluded;

  final VoidCallback onToggle;

  final VoidCallback onExcludeToggle;

  @override
  Widget build(BuildContext context) {
    final textColor = excluded ? const Color(0xffb42318) : groupColor;
    final borderColor = excluded
        ? const Color(0xffffb4ad)
        : selected
            ? const Color(0xffd8d4ff)
            : const Color(0xffe6ecf5);
    final backgroundColor = excluded
        ? const Color(0xfffff1f0)
        : selected
            ? const Color(0xfff3f0ff)
            : Colors.white;
    return GestureDetector(
      onLongPress: onExcludeToggle,
      child: Material(
        key: LibrarySmokeKeys.tagChip(tag.id),
        color: backgroundColor,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onToggle,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected || excluded) ...[
                  Icon(
                    excluded
                        ? Icons.remove_circle_outline
                        : Icons.check_circle_rounded,
                    size: 16,
                    color: textColor,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  excluded
                      ? 'NOT ${tag.displayName ?? tag.name}'
                      : (tag.displayName ?? tag.name),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatCount(count),
                  style: const TextStyle(
                    color: _appTextMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _DiscoveryGroupCard extends StatelessWidget {
  const _DiscoveryGroupCard({
    required this.group,
    required this.primary,
    required this.childItemsByParent,
    required this.resultCounts,
    required this.stablePrimaryCounts,
    required this.primaryClickCounts,
    required this.selectedIds,
    required this.childSelectedIds,
    required this.excludedIds,
    required this.onToggle,
    required this.onFolderPrimaryChildSelected,
    required this.onExcludeToggle,
    required this.expandedPrimaryTagId,
    required this.showAllPrimaryTags,
    required this.primarySortMode,
    required this.expandedChildTagIds,
    required this.onExpandedPrimaryChanged,
    required this.onShowAllPrimaryTags,
    required this.onExpandChildTags,
  });

  final TagGroup group;

  final bool primary;

  final Map<String, List<TagItem>> childItemsByParent;

  final Map<String, int> resultCounts;

  final Map<String, int> stablePrimaryCounts;

  final Map<String, int> primaryClickCounts;

  final Set<String> selectedIds;

  final Set<String> childSelectedIds;

  final Set<String> excludedIds;

  final ValueChanged<TagItem> onToggle;
  final void Function(TagItem primary, TagItem? child)
      onFolderPrimaryChildSelected;
  final ValueChanged<TagItem> onExcludeToggle;

  final String? expandedPrimaryTagId;

  final bool showAllPrimaryTags;

  final _PrimaryTagSortMode primarySortMode;

  final Set<String> expandedChildTagIds;

  final ValueChanged<TagItem> onExpandedPrimaryChanged;

  final VoidCallback onShowAllPrimaryTags;

  final ValueChanged<TagItem> onExpandChildTags;

  List<TagItem> _childTagsFor(TagItem tag) =>
      displayChildItemsForPrimary(tag, childItemsByParent);

  List<TagItem> _visibleChildTagsFor(TagItem tag) {
    final childTags = _childTagsFor(tag);
    if (expandedChildTagIds.contains(tag.id)) {
      return childTags;
    }
    return childTags.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    final groupColor = _groupColor(group.id);
    final rankedItems = group.items.toList()
      ..sort((a, b) {
        switch (primarySortMode) {
          case _PrimaryTagSortMode.countDesc:
            final byCount = (stablePrimaryCounts[b.id] ??
                    resultCounts[b.id] ??
                    b.usageCount)
                .compareTo(stablePrimaryCounts[a.id] ??
                    resultCounts[a.id] ??
                    a.usageCount);
            if (byCount != 0) {
              return byCount;
            }
          case _PrimaryTagSortMode.frequentDesc:
            final byClicks = (primaryClickCounts[b.id] ?? 0)
                .compareTo(primaryClickCounts[a.id] ?? 0);
            if (byClicks != 0) {
              return byClicks;
            }
          case _PrimaryTagSortMode.nameAsc:
            break;
        }
        return (a.displayName ?? a.name).compareTo(b.displayName ?? b.name);
      });
    final defaultLimit = primary ? 7 : 4;
    final visibleItems = (primary && showAllPrimaryTags
            ? rankedItems
            : rankedItems.take(defaultLimit))
        .toList();
    final title = group.id == 'folder.primary'
        ? '\u4e00\u7ea7\u6807\u7b7e'
        : (group.displayName ?? group.name);
    final expandedTag = expandedPrimaryTagId == null || visibleItems.isEmpty
        ? null
        : [
            for (final tag in visibleItems)
              if (tag.id == expandedPrimaryTagId) tag,
          ].firstOrNull;
    if (primary) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tag in visibleItems)
            if (expandedTag != null && tag.id == expandedTag.id)
              _PrimaryAccordionRow(
                tag: tag,
                groupColor: groupColor,
                count: resultCounts[tag.id] ?? 0,
                selected: selectedIds.contains(tag.id),
                onToggle: () => onExpandedPrimaryChanged(tag),
                onFilterToggle: () => onToggle(tag),
                childTags: _visibleChildTagsFor(tag),
                childTagCount: _childTagsFor(tag).length,
                childTagsExpanded: expandedChildTagIds.contains(tag.id),
                resultCounts: resultCounts,
                selectedIds: selectedIds,
                childSelectedIds: childSelectedIds,
                excludedIds: excludedIds,
                onDefaultAlbumToggle: () =>
                    onFolderPrimaryChildSelected(tag, null),
                onChildToggle: (child) =>
                    onFolderPrimaryChildSelected(tag, child),
                onChildExcludeToggle: onExcludeToggle,
                onExpandAllChildren: () => onExpandChildTags(tag),
              )
            else
              _CollapsedPrimaryRow(
                tag: tag,
                count: resultCounts[tag.id] ?? 0,
                selected: selectedIds.contains(tag.id),
                onToggle: () => onExpandedPrimaryChanged(tag),
              ),
          if (rankedItems.length > defaultLimit)
            _ShowMorePrimaryButton(
              remainingCount: rankedItems.length - defaultLimit,
              expanded: showAllPrimaryTags,
              onPressed: onShowAllPrimaryTags,
            ),
        ],
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xfffbfcff),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 16,
                decoration: BoxDecoration(
                  color: groupColor,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: _appText,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              Text(
                '${group.items.length}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _appTextMuted,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          for (final tag in visibleItems)
            if (expandedTag != null && tag.id == expandedTag.id)
              _PrimaryAccordionRow(
                tag: tag,
                groupColor: groupColor,
                count: resultCounts[tag.id] ?? 0,
                selected: selectedIds.contains(tag.id),
                onToggle: () => onExpandedPrimaryChanged(tag),
                onFilterToggle: () => onToggle(tag),
                childTags: _visibleChildTagsFor(tag),
                childTagCount: _childTagsFor(tag).length,
                childTagsExpanded: expandedChildTagIds.contains(tag.id),
                resultCounts: resultCounts,
                selectedIds: selectedIds,
                childSelectedIds: childSelectedIds,
                excludedIds: excludedIds,
                onDefaultAlbumToggle: () =>
                    onFolderPrimaryChildSelected(tag, null),
                onChildToggle: (child) =>
                    onFolderPrimaryChildSelected(tag, child),
                onChildExcludeToggle: onExcludeToggle,
                onExpandAllChildren: () => onExpandChildTags(tag),
              )
            else
              _CollapsedPrimaryRow(
                tag: tag,
                count: resultCounts[tag.id] ?? 0,
                selected: selectedIds.contains(tag.id),
                onToggle: () => onExpandedPrimaryChanged(tag),
              ),
          if (primary && visibleItems.length < rankedItems.length)
            _ShowMorePrimaryButton(
              remainingCount: rankedItems.length - visibleItems.length,
              expanded: showAllPrimaryTags,
              onPressed: onShowAllPrimaryTags,
            ),
        ],
      ),
    );
  }
}

class _PrimaryAccordionRow extends StatelessWidget {
  const _PrimaryAccordionRow({
    required this.tag,
    required this.groupColor,
    required this.count,
    required this.selected,
    required this.onToggle,
    required this.onFilterToggle,
    required this.childTags,
    required this.childTagCount,
    required this.childTagsExpanded,
    required this.resultCounts,
    required this.selectedIds,
    required this.childSelectedIds,
    required this.excludedIds,
    required this.onDefaultAlbumToggle,
    required this.onChildToggle,
    required this.onChildExcludeToggle,
    required this.onExpandAllChildren,
  });

  final TagItem tag;
  final Color groupColor;
  final int count;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onFilterToggle;
  final List<TagItem> childTags;
  final int childTagCount;
  final bool childTagsExpanded;
  final Map<String, int> resultCounts;
  final Set<String> selectedIds;
  final Set<String> childSelectedIds;
  final Set<String> excludedIds;
  final VoidCallback onDefaultAlbumToggle;
  final ValueChanged<TagItem> onChildToggle;
  final ValueChanged<TagItem> onChildExcludeToggle;
  final VoidCallback onExpandAllChildren;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xfffbfcff),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffe6ecf5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            key: LibrarySmokeKeys.primaryHeader(tag.id),
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: SizedBox(
              height: 40,
              child: Row(
                children: [
                  Icon(Icons.expand_more_rounded,
                      size: 20, color: selected ? _appAccentViolet : _appText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tag.displayName ?? tag.name,
                      style: const TextStyle(
                        color: _appText,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    _formatCount(count),
                    style: const TextStyle(
                      color: _appTextMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _TagFilterChip(
                  tag: TagItem(
                    id: '${tag.id}::default-album',
                    name: TagRules.defaultAlbumTag,
                    displayName: TagRules.defaultAlbumTag,
                    groupId: 'folder.child',
                    parentId: tag.id,
                    source: TagSource.folder,
                  ),
                  groupColor: groupColor,
                  count: count,
                  selected: selected && childSelectedIds.isEmpty,
                  excluded: false,
                  onToggle: onDefaultAlbumToggle,
                  onExcludeToggle: () {},
                ),
                for (final child in childTags)
                  _TagFilterChip(
                    tag: child,
                    groupColor: groupColor,
                    count: resultCounts[child.id] ?? 0,
                    selected: childSelectedIds.contains(child.id),
                    excluded: excludedIds.contains(child.id),
                    onToggle: () => onChildToggle(child),
                    onExcludeToggle: () => onChildExcludeToggle(child),
                  ),
              ],
            ),
          ),
          if (childTagCount > childTags.length || childTagsExpanded) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: _ExpandAllChildrenButton(
                key: LibrarySmokeKeys.childExpandButton(tag.id),
                childTagCount: childTagCount + 1,
                expanded: childTagsExpanded,
                onPressed: onExpandAllChildren,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpandAllChildrenButton extends StatelessWidget {
  const _ExpandAllChildrenButton({
    super.key,
    required this.childTagCount,
    required this.expanded,
    required this.onPressed,
  });

  final int childTagCount;

  final bool expanded;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            expanded
                ? '\u6536\u8d77\uff08$childTagCount\uff09 \u2303'
                : '\u5c55\u5f00\u5168\u90e8\uff08$childTagCount\uff09 \u2304',
            style: const TextStyle(
              color: _appTextMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapsedPrimaryRow extends StatelessWidget {
  const _CollapsedPrimaryRow({
    required this.tag,
    required this.count,
    required this.selected,
    required this.onToggle,
  });

  final TagItem tag;
  final int count;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: LibrarySmokeKeys.primaryRow(tag.id),
        color: selected ? const Color(0xfff5f3ff) : const Color(0xfffbfcff),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onToggle,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? const Color(0xffd8d4ff)
                    : const Color(0xffe6ecf5),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: _appText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tag.displayName ?? tag.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _appText,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  _formatCount(count),
                  style: const TextStyle(
                    color: _appTextMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
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

class _ShowMorePrimaryButton extends StatelessWidget {
  const _ShowMorePrimaryButton({
    required this.remainingCount,
    required this.expanded,
    required this.onPressed,
  });

  final int remainingCount;

  final bool expanded;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(
          expanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          size: 18,
        ),
        label: Text(
          expanded
              ? '\u6536\u8d77\u4e00\u7ea7\u6807\u7b7e'
              : '\u66f4\u591a\u4e00\u7ea7\u6807\u7b7e\uff08$remainingCount\uff09',
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: _appAccentViolet,
          side: const BorderSide(color: Color(0xffd8d4ff)),
          backgroundColor: const Color(0xfff8f7ff),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );
  }
}

@visibleForTesting
bool referenceTopBarShouldCollapseActions(LayoutSize layoutSize) {
  return layoutSize != LayoutSize.expanded;
}

/**
 * 右侧标签筛选面板收起后的恢复入口。
 *
 * 窄条需要保留按钮语义和稳定 key，真实窗口 smoke test 与辅助技术都依赖该入口恢复右侧标签发现闭环。
 */
class _CollapsedTagDiscoveryRail extends StatelessWidget {
  const _CollapsedTagDiscoveryRail({required this.onExpand});

  /**
   * 恢复右侧标签筛选面板的回调。
   */
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: LibrarySmokeKeys.collapsedTagRail,
      button: true,
      label: '\u5c55\u5f00\u6807\u7b7e\u7b5b\u9009',
      hint: '\u6062\u590d\u53f3\u4fa7\u6807\u7b7e\u7b5b\u9009\u9762\u677f',
      onTap: onExpand,
      child: Tooltip(
        message: '\u5c55\u5f00\u6807\u7b7e\u7b5b\u9009',
        child: Container(
          width: 58,
          margin: const EdgeInsets.fromLTRB(10, 16, 24, 24),
          decoration: BoxDecoration(
            color: _appPanel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xffe6ecf5)),
            boxShadow: _appSoftShadow,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onExpand,
              child: const ExcludeSemantics(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.filter_alt_outlined, color: _appAccentViolet),
                    SizedBox(height: 10),
                    RotatedBox(
                      quarterTurns: 1,
                      child: Text(
                        '\u6807\u7b7e\u7b5b\u9009',
                        style: TextStyle(
                          color: _appText,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
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
 * 为 widget smoke test 暴露收起窄条，不把私有实现泄漏到业务入口。
 */
@visibleForTesting
Widget collapsedTagDiscoveryRailSmokeHarness({
  required VoidCallback onExpand,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: _CollapsedTagDiscoveryRail(
          onExpand: onExpand,
        ),
      ),
    ),
  );
}

class _ReferenceTopBar extends StatelessWidget {
  const _ReferenceTopBar({
    required this.controller,
    required this.videoCount,
    required this.totalCount,
    required this.keyword,
    required this.sortMode,
    required this.layoutSize,
    required this.hasActiveFilters,
    required this.favoritesSelected,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.denseResultGrid,
    required this.onResultViewChanged,
    required this.onFavoritesToggle,
    required this.onOpenTagManager,
    required this.onOpenFilters,
  });

  final TextEditingController controller;

  final int videoCount;

  final int totalCount;

  final String keyword;

  final SortMode sortMode;

  final LayoutSize layoutSize;

  final bool hasActiveFilters;

  final bool favoritesSelected;

  final ValueChanged<String> onSearchChanged;

  final ValueChanged<SortMode> onSortChanged;

  final bool denseResultGrid;

  final ValueChanged<bool> onResultViewChanged;

  final VoidCallback onFavoritesToggle;

  final VoidCallback onOpenTagManager;

  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final compact = layoutSize == LayoutSize.compact;
    final keywordActive = keyword.trim().isNotEmpty;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(compact ? 12 : 20, 14, compact ? 12 : 20, 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final constrained = constraints.maxWidth < 760;
            final collapseActions =
                referenceTopBarShouldCollapseActions(layoutSize) || constrained;
            // 非最大化窗口虽然仍可能处于 expanded 断点，但右侧面板会挤占可用宽度；
            // 搜索框必须在真实行宽不足时让出空间，避免工具条右侧按钮越界。
            final fitSearchToRemainingWidth =
                compact || constraints.maxWidth < 1040;
            final searchField = ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 180,
                maxWidth: fitSearchToRemainingWidth ? double.infinity : 760,
              ),
              child: Container(
                height: compact ? 44 : 50,
                decoration: BoxDecoration(
                  color: _appPanel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: keywordActive ? _appAccentViolet : _appBorder,
                    width: keywordActive ? 1.4 : 1,
                  ),
                  boxShadow: _appSoftShadow,
                ),
                /**
                 * 主搜索框使用 TextField 而不是 Material SearchBar。
                 *
                 * Windows 桌面自动化和真实键盘输入都需要稳定触发 EditableText 的输入链路；
                 * SearchBar 在 smoke test 中出现过可聚焦但 type_text 不写入的问题。
                 */
                child: TextField(
                  key: LibrarySmokeKeys.searchField,
                  controller: controller,
                  textInputAction: TextInputAction.search,
                  onChanged: onSearchChanged,
                  onSubmitted: onSearchChanged,
                  style: const TextStyle(
                    color: _appText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 15,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 23,
                      color: keywordActive
                          ? _appAccentViolet
                          : const Color(0xff566274),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 44,
                    ),
                    hintText: compact
                        ? '\u641c\u7d22\u6587\u4ef6\u0020\u002f\u0020\u6807\u7b7e'
                        : '\u641c\u7d22\u6587\u4ef6\u540d\u0020\u002f\u0020\u6807\u7b7e\u0020\u002f\u0020\u8def\u5f84\u002e\u002e\u002e',
                    hintStyle: const TextStyle(
                      color: Color(0xff566274),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    suffixIcon: constrained
                        ? null
                        : const Padding(
                            padding: EdgeInsets.only(right: 14),
                            child: Center(
                              widthFactor: 1,
                              child: Text(
                                'Ctrl + K',
                                style: TextStyle(
                                  color: Color(0xff8a94a6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 68,
                      minHeight: 44,
                    ),
                  ),
                ),
              ),
            );
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
                if (fitSearchToRemainingWidth)
                  Expanded(child: searchField)
                else
                  searchField,
                SizedBox(width: collapseActions ? 8 : 12),
                _ReferenceActionButton(
                  tooltip: '\u6807\u7b7e\u4e2d\u5fc3',
                  icon: Icons.sell_outlined,
                  label: collapseActions ? null : '\u6807\u7b7e\u4e2d\u5fc3',
                  onPressed: onOpenTagManager,
                ),
                const SizedBox(width: 8),
                _ReferenceActionButton(
                  tooltip: '\u6536\u85cf\u7b5b\u9009',
                  icon: Icons.star_border_rounded,
                  label: collapseActions ? null : '\u6536\u85cf\u7b5b\u9009',
                  selected: favoritesSelected,
                  onPressed: onFavoritesToggle,
                ),
                const SizedBox(width: 8),
                const SizedBox(width: 12),
                if (!compact)
                  _TopSortMenu(
                    sortMode: sortMode,
                    onChanged: onSortChanged,
                  ),
                if (!compact) const SizedBox(width: 8),
                if (!compact)
                  ResultViewToggle(
                    dense: denseResultGrid,
                    onChanged: onResultViewChanged,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
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
}) {
  return MaterialApp(
    home: Scaffold(
      body: _ReferenceTopBar(
        controller: controller,
        videoCount: 0,
        totalCount: 0,
        keyword: controller.text,
        sortMode: SortMode.recent,
        layoutSize: LayoutSize.expanded,
        hasActiveFilters: false,
        favoritesSelected: false,
        onSearchChanged: onSearchChanged,
        onSortChanged: (_) {},
        denseResultGrid: false,
        onResultViewChanged: (_) {},
        onFavoritesToggle: () {},
        onOpenTagManager: () {},
        onOpenFilters: () {},
      ),
    ),
  );
}

class _ReferenceActionButton extends StatelessWidget {
  const _ReferenceActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.label,
    this.selected = false,
  });

  final String tooltip;

  final IconData icon;

  final VoidCallback onPressed;

  final String? label;

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? const Color(0xfff5f3ff) : _appPanel,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Container(
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: label == null ? 9 : 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? const Color(0xffd8d4ff) : _appBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 19,
                    color: selected ? _appAccentViolet : _appAccentStrong),
                if (label != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    label!,
                    style: const TextStyle(
                      color: _appText,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReferenceIconButton extends StatelessWidget {
  const _ReferenceIconButton({
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
        backgroundColor: _appPanel,
        foregroundColor: _appAccentStrong,
        fixedSize: const Size(38, 38),
        side: const BorderSide(color: _appBorder),
      ),
    );
  }
}

class _TopSortMenu extends StatelessWidget {
  const _TopSortMenu({
    required this.sortMode,
    required this.onChanged,
  });

  final SortMode sortMode;
  final ValueChanged<SortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = switch (sortMode) {
      SortMode.recent => '\u6309\u6dfb\u52a0\u65f6\u95f4',
      SortMode.name => '\u6309\u540d\u79f0',
      SortMode.folder => '\u6309\u76ee\u5f55',
    };
    return PopupMenuButton<SortMode>(
      tooltip: '\u6392\u5e8f',
      onSelected: onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(
            value: SortMode.recent,
            child: Text('\u6309\u6dfb\u52a0\u65f6\u95f4')),
        PopupMenuItem(value: SortMode.name, child: Text('\u6309\u540d\u79f0')),
        PopupMenuItem(
            value: SortMode.folder, child: Text('\u6309\u76ee\u5f55')),
      ],
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _appPanel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _appBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: _appText,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more_rounded,
                size: 18, color: _appTextMuted),
          ],
        ),
      ),
    );
  }
}

@visibleForTesting
class ResultViewToggle extends StatelessWidget {
  const ResultViewToggle({
    super.key,
    required this.dense,
    required this.onChanged,
  });

  final bool dense;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _appPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _appBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TopViewButton(
            icon: Icons.grid_view_rounded,
            selected: !dense,
            onPressed: () => onChanged(false),
          ),
          const SizedBox(width: 2),
          _TopViewButton(
            icon: Icons.view_list_rounded,
            selected: dense,
            onPressed: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _TopViewButton extends StatelessWidget {
  const _TopViewButton({
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onPressed,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xffeef2ff) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: selected ? _appAccentViolet : _appTextMuted,
        ),
      ),
    );
  }
}

/**
 * 最近播放结果视图。
 *
 * 这里的删除只清理播放记录，不删除视频文件；选择状态由 LibraryPage 保存，
 * 避免滚动重建时丢失用户正在批量清理的选择。
 */
class _RecentPlaybackView extends StatelessWidget {
  const _RecentPlaybackView({
    required this.videos,
    required this.selectedPathKeys,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.dense,
    required this.onOpen,
    required this.onEditTags,
    required this.onToggleFavorite,
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
                  color: _appTextMuted,
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
                  mainAxisExtent: narrow ? 366 : (compact ? 322 : 348),
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
                    onEditTags: () => onEditTags(item),
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
  final VoidCallback onToggleSelected;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(value: selected, onChanged: (_) => onToggleSelected()),
        Expanded(
          child: _InteractiveVideoListRow(
            item: item,
            thumbnailService: thumbnailService,
            playbackSettings: playbackSettings,
            onOpen: onOpen,
            onEditTags: onEditTags,
            onToggleFavorite: onToggleFavorite,
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
    required this.onEditTags,
    required this.onToggleFavorite,
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
  final VoidCallback onToggleSelected;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _InteractiveVideoCard(
          item: item,
          thumbnailService: thumbnailService,
          playbackSettings: playbackSettings,
          onOpen: onOpen,
          onEditTags: onEditTags,
          onToggleFavorite: onToggleFavorite,
        ),
        Positioned(
          top: 8,
          left: 8,
          child:
              Checkbox(value: selected, onChanged: (_) => onToggleSelected()),
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
class _LocalLibraryView extends StatelessWidget {
  const _LocalLibraryView({
    required this.currentPath,
    required this.entries,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.dense,
    required this.canGoBack,
    required this.onBack,
    required this.onOpenFolder,
    required this.onOpenVideo,
    required this.onEditTags,
    required this.onToggleFavorite,
  });

  final String? currentPath;
  final List<_LocalLibraryEntry> entries;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  final bool dense;
  final bool canGoBack;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenFolder;
  final void Function(VideoItem item, List<VideoItem> playlist) onOpenVideo;
  final ValueChanged<VideoItem> onEditTags;
  final ValueChanged<VideoItem> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final localVideos = [
      for (final entry in entries)
        if (entry.video != null) entry.video!,
    ];
    return Listener(
      key: LibrarySmokeKeys.localPointerBackRegion,
      onPointerDown: (event) {
        // Windows 鼠标侧键“后退”通常映射为第 4 键；只在有路径历史时消费为本地媒体库返回。
        const mouseBackButton = 0x08;
        if (canGoBack && event.buttons == mouseBackButton) {
          onBack();
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
            child: Row(
              children: [
                IconButton(
                  key: LibrarySmokeKeys.localBackButton,
                  tooltip: '\u8fd4\u56de\u4e0a\u4e00\u5c42',
                  onPressed: canGoBack ? onBack : null,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: _appTextMuted,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    currentPath ?? '\u672c\u5730\u5a92\u4f53\u5e93',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _appTextMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const _EmptyState(
                    hasLibrary: true,
                    message:
                        '\u5f53\u524d\u76ee\u5f55\u6ca1\u6709\u5df2\u5165\u5e93\u89c6\u9891\u6216\u5b50\u6587\u4ef6\u5939',
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth <
                          LayoutBreakpoints.compactMaxWidth;
                      final narrow = constraints.maxWidth < 560;
                      if (dense) {
                        return ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 14 : 22,
                            2,
                            compact ? 14 : 22,
                            22,
                          ),
                          itemExtent: narrow ? 132 : 120,
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            if (entry.isFolder) {
                              return _LocalFolderRow(
                                path: entry.path,
                                onOpen: () => onOpenFolder(entry.path),
                              );
                            }
                            final video = entry.video!;
                            return _InteractiveVideoListRow(
                              item: video,
                              thumbnailService: thumbnailService,
                              playbackSettings: playbackSettings,
                              onOpen: () => onOpenVideo(video, localVideos),
                              onEditTags: () => onEditTags(video),
                              onToggleFavorite: () => onToggleFavorite(video),
                            );
                          },
                        );
                      }
                      return GridView.builder(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 14 : 22,
                          2,
                          compact ? 14 : 22,
                          22,
                        ),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent:
                              narrow ? 500 : (compact ? 248 : 286),
                          // 单列网格会把 16:9 缩略图拉高，卡片高度必须跟着增长；
                          // 否则普通窗口下标题、标签和底部按钮会挤出可视区域。
                          mainAxisExtent: narrow ? 430 : (compact ? 300 : 340),
                          mainAxisSpacing: compact ? 14 : 16,
                          crossAxisSpacing: compact ? 10 : 14,
                        ),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          if (entry.isFolder) {
                            return _LocalFolderCard(
                              path: entry.path,
                              onOpen: () => onOpenFolder(entry.path),
                            );
                          }
                          final video = entry.video!;
                          return _InteractiveVideoCard(
                            item: video,
                            thumbnailService: thumbnailService,
                            playbackSettings: playbackSettings,
                            onOpen: () => onOpenVideo(video, localVideos),
                            onEditTags: () => onEditTags(video),
                            onToggleFavorite: () => onToggleFavorite(video),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

@visibleForTesting
class LocalLibrarySmokeHarness extends StatefulWidget {
  const LocalLibrarySmokeHarness({
    super.key,
    required this.rootPath,
    required this.childPath,
    this.dense = false,
  });

  /**
   * smoke test 使用的本地媒体库 root 路径。
   */
  final String rootPath;

  /**
   * smoke test 使用的子文件夹路径。
   */
  final String childPath;

  /**
   * 是否使用列表视图；默认覆盖网格文件夹卡片路径。
   */
  final bool dense;

  @override
  State<LocalLibrarySmokeHarness> createState() =>
      _LocalLibrarySmokeHarnessState();
}

class _LocalLibrarySmokeHarnessState extends State<LocalLibrarySmokeHarness> {
  late String _currentPath = widget.rootPath;
  late final ThumbnailService _thumbnailService;
  late final Directory _thumbnailDirectory;
  final _backStack = <String>[];

  @override
  void initState() {
    super.initState();
    _thumbnailDirectory =
        Directory.systemTemp.createTempSync('ltp_local_harness_thumbs_');
    _thumbnailService = ThumbnailService._(_thumbnailDirectory);
  }

  @override
  void dispose() {
    try {
      if (_thumbnailDirectory.existsSync()) {
        _thumbnailDirectory.deleteSync(recursive: true);
      }
    } on FileSystemException {
      // 测试缩略图目录只承载 harness 临时文件，清理失败不影响交互断言。
    }
    super.dispose();
  }

  /**
   * 进入子文件夹并记录返回栈。
   *
   * 该逻辑只服务 widget smoke test，用来验证真实文件夹入口、返回按钮和鼠标侧键共用同一行为。
   */
  void _openFolder(String path) {
    setState(() {
      _backStack.add(_currentPath);
      _currentPath = path;
    });
  }

  /**
   * 从测试返回栈回到上一层路径。
   */
  void _goBack() {
    if (_backStack.isEmpty) {
      return;
    }
    setState(() {
      _currentPath = _backStack.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _currentPath == widget.rootPath
        ? <_LocalLibraryEntry>[_LocalLibraryEntry.folder(widget.childPath)]
        : const <_LocalLibraryEntry>[];
    return MaterialApp(
      home: Scaffold(
        body: _LocalLibraryView(
          currentPath: _currentPath,
          entries: entries,
          thumbnailService: _thumbnailService,
          playbackSettings: PlaybackSettings.defaults,
          dense: widget.dense,
          canGoBack: _backStack.isNotEmpty,
          onBack: _goBack,
          onOpenFolder: _openFolder,
          onOpenVideo: (_, __) {},
          onEditTags: (_) {},
          onToggleFavorite: (_) {},
        ),
      ),
    );
  }
}

/**
 * 列表行操作 smoke test 的最小宿主。
 *
 * 只挂载真实 `_InteractiveVideoListRow` 并统计播放、收藏、更多三个回调，不打开播放器、
 * 不写数据库，也不触发真实标签编辑弹窗。
 */
@visibleForTesting
class VideoListRowSmokeHarness extends StatefulWidget {
  const VideoListRowSmokeHarness({super.key});

  @override
  State<VideoListRowSmokeHarness> createState() =>
      _VideoListRowSmokeHarnessState();
}

class _VideoListRowSmokeHarnessState extends State<VideoListRowSmokeHarness> {
  late final Directory _thumbnailDirectory;
  late final ThumbnailService _thumbnailService;
  late final VideoItem _item;
  var _openCount = 0;
  var _favoriteCount = 0;
  var _moreCount = 0;

  @override
  void initState() {
    super.initState();
    _thumbnailDirectory =
        Directory.systemTemp.createTempSync('ltp_list_harness_thumbs_');
    _thumbnailService = ThumbnailService._(_thumbnailDirectory);
    _item = VideoItem(
      path: r'C:\smoke\media\Alpha\clip.mp4',
      title: 'Smoke Clip',
      folder: r'C:\smoke\media\Alpha',
      tags: const {'Alpha', 'Child01'},
      addedAt: DateTime(2026),
    );
  }

  @override
  void dispose() {
    try {
      if (_thumbnailDirectory.existsSync()) {
        _thumbnailDirectory.deleteSync(recursive: true);
      }
    } on FileSystemException {
      // 测试缩略图目录只承载 harness 临时文件，清理失败不影响交互断言。
    }
    super.dispose();
  }

  /**
   * 列表行 smoke test 的状态汇总。
   *
   * 测试只验证三个按钮是否命中对应回调，不打开播放器、不改数据库、不触发标签编辑弹窗。
   */
  String get _actionState =>
      'open=$_openCount favorite=$_favoriteCount more=$_moreCount';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 980,
          height: 160,
          child: Column(
            children: [
              Text(_actionState, key: LibrarySmokeKeys.listActionState),
              Expanded(
                child: _InteractiveVideoListRow(
                  item: _item,
                  thumbnailService: _thumbnailService,
                  playbackSettings: PlaybackSettings.defaults,
                  onOpen: () => setState(() => _openCount += 1),
                  onToggleFavorite: () {
                    setState(() {
                      _favoriteCount += 1;
                      _item.isFavorite = !_item.isFavorite;
                    });
                  },
                  onEditTags: () => setState(() => _moreCount += 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
class TagDiscoverySmokeHarness extends StatefulWidget {
  const TagDiscoverySmokeHarness({
    super.key,
    required this.childCount,
  });

  /**
   * 为一级标签生成的二级标签数量。
   *
   * 数量大于 9 时可覆盖右侧面板的“展开全部 / 收起”交互路径。
   */
  final int childCount;

  @override
  State<TagDiscoverySmokeHarness> createState() =>
      _TagDiscoverySmokeHarnessState();
}

class _TagDiscoverySmokeHarnessState extends State<TagDiscoverySmokeHarness> {
  final _selectedGroupTagIds = <String, Set<String>>{};

  late final TagItem _primary = const TagItem(
    id: 'folder.primary:alpha',
    name: 'Alpha',
    displayName: 'Alpha',
    groupId: 'folder.primary',
    source: TagSource.folder,
    usageCount: 99,
  );

  late final List<TagItem> _children = [
    for (var index = 1; index <= widget.childCount; index += 1)
      TagItem(
        id: 'folder.child:alpha:child${index.toString().padLeft(2, '0')}',
        name: 'Child${index.toString().padLeft(2, '0')}',
        displayName: 'Child${index.toString().padLeft(2, '0')}',
        groupId: 'folder.child',
        parentId: _primary.id,
        source: TagSource.folder,
        usageCount: 20 - index,
      ),
  ];

  /**
   * 根据右侧标签 chip 的当前选中态生成测试结果标题。
   *
   * 该结果区只用于验证 UI 事件链是否把默认专辑和二级标签选择传到上层状态；
   * 真实媒体库筛选仍由 `FilterQuery` / `TagQueryService` 负责。
   */
  List<String> get _resultTitles {
    final selectedPrimary =
        _selectedGroupTagIds['folder.primary']?.contains(_primary.id) ?? false;
    if (!selectedPrimary) {
      return const <String>[];
    }
    final childIds = _selectedGroupTagIds['folder.child'] ?? const <String>{};
    if (childIds.isEmpty) {
      return const <String>[
        'Alpha Default Video',
        'Child01 Video',
        'Child02 Video',
      ];
    }
    final childId = childIds.first;
    final child = _children.firstWhere(
      (item) => item.id == childId,
      orElse: () => _children.first,
    );
    return ['${child.displayName ?? child.name} Video'];
  }

  /**
   * 测试用的一级 / 二级互斥选择回调。
   *
   * 这里不复制筛选引擎，只维护右侧面板需要的选中态，避免 smoke test 扩大到查询语义。
   */
  void _selectPrimaryChild(TagItem primary, TagItem? child) {
    setState(() {
      _selectedGroupTagIds['folder.primary'] = {primary.id};
      _selectedGroupTagIds['folder.child'] =
          child == null ? <String>{} : <String>{child.id};
    });
  }

  /**
   * 从“全部二级标签”页签直接选择二级标签。
   *
   * 测试宿主将其解释为当前一级 Alpha 下的互斥二级选择，避免引入真实查询引擎。
   */
  void _toggleSecondaryTag(TagItem child) {
    setState(() {
      _selectedGroupTagIds['folder.primary'] = {_primary.id};
      _selectedGroupTagIds['folder.child'] = {child.id};
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = [
      TagGroup(id: 'folder.primary', name: 'folder.primary', items: [_primary]),
      TagGroup(id: 'folder.child', name: 'folder.child', items: _children),
    ];
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 520,
          height: 820,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: const Color(0xfff8fafc),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final title in _resultTitles)
                      Text(title, key: LibrarySmokeKeys.tagResult(title)),
                  ],
                ),
              ),
              Expanded(
                child: _TagDiscoveryZone(
                  tagGroups: groups,
                  resultCounts: {
                    _primary.id: _primary.usageCount,
                    for (final child in _children) child.id: child.usageCount,
                  },
                  favoriteTags: const [],
                  selectedTags: const {},
                  selectedChildTags: const {},
                  selectedGroupTagIds: _selectedGroupTagIds,
                  excludedTagIds: const {},
                  childParentTag: null,
                  childTags: const [],
                  childTagItemsByParent: {_primary.id: _children},
                  favoriteCount: 0,
                  showFavoritesOnly: false,
                  dense: false,
                  onFavoritesToggle: () {},
                  onTagToggle: (_) {},
                  onChildTagToggle: (_) {},
                  onGroupTagToggle: _toggleSecondaryTag,
                  onFolderPrimaryChildSelected: _selectPrimaryChild,
                  onGroupTagExcludeToggle: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalFolderCard extends StatelessWidget {
  const _LocalFolderCard({required this.path, required this.onOpen});

  final String path;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: LibrarySmokeKeys.localFolder(path),
      color: _appPanel,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(color: _appBorder),
            borderRadius: BorderRadius.circular(8),
            boxShadow: _appSoftShadow,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_rounded,
                  size: 58, color: _appAccentViolet),
              const SizedBox(height: 16),
              Text(
                p.basename(path),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _appText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalFolderRow extends StatelessWidget {
  const _LocalFolderRow({required this.path, required this.onOpen});

  final String path;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: LibrarySmokeKeys.localFolder(path),
      color: _appPanel,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: _appBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder_rounded,
                  color: _appAccentViolet, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  p.basename(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _appText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _appTextMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoGrid extends StatelessWidget {
  const _VideoGrid({
    required this.videos,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.dense,
    required this.onOpen,
    required this.onEditTags,
    required this.onToggleFavorite,
  });

  final List<VideoItem> videos;

  final ThumbnailService thumbnailService;

  final PlaybackSettings playbackSettings;

  final bool dense;

  final void Function(VideoItem item, List<VideoItem> playlist) onOpen;

  final ValueChanged<VideoItem> onEditTags;

  final ValueChanged<VideoItem> onToggleFavorite;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
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
            itemExtent: narrow ? 132 : 120,
            scrollCacheExtent: const ScrollCacheExtent.pixels(720),
            itemCount: videos.length,
            itemBuilder: (context, index) {
              final item = videos[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _InteractiveVideoListRow(
                  item: item,
                  thumbnailService: thumbnailService,
                  playbackSettings: playbackSettings,
                  onOpen: () => onOpen(item, videos),
                  onEditTags: () => onEditTags(item),
                  onToggleFavorite: () => onToggleFavorite(item),
                ),
              );
            },
          );
        }
        return GridView.builder(
          padding:
              EdgeInsets.fromLTRB(compact ? 14 : 22, 2, compact ? 14 : 22, 22),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: narrow ? 500 : (compact ? 248 : 286),
            // 单列网格会把 16:9 缩略图拉高，卡片高度必须跟着增长；
            // 否则普通窗口下标题、标签和底部按钮会挤出可视区域。
            mainAxisExtent: narrow ? 430 : (compact ? 300 : 340),
            mainAxisSpacing: compact ? 14 : 16,
            crossAxisSpacing: compact ? 10 : 14,
          ),
          itemCount: videos.length,
          scrollCacheExtent: const ScrollCacheExtent.pixels(720),
          itemBuilder: (context, index) {
            final item = videos[index];
            return _InteractiveVideoCard(
              item: item,
              thumbnailService: thumbnailService,
              playbackSettings: playbackSettings,
              onOpen: () => onOpen(item, videos),
              onEditTags: () => onEditTags(item),
              onToggleFavorite: () => onToggleFavorite(item),
            );
          },
        );
      },
    );
  }
}

/**
 * 列表模式下的单条视频结果。
 *
 * 行内容限制在可读宽度内，避免超宽桌面窗口把“播放 / 收藏 / 更多”
 * 操作区推到视线外，导致入口存在但真实点击和视觉发现都不稳定。
 */
class _InteractiveVideoListRow extends StatelessWidget {
  const _InteractiveVideoListRow({
    required this.item,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.onOpen,
    required this.onEditTags,
    required this.onToggleFavorite,
  });

  final VideoItem item;

  final ThumbnailService thumbnailService;

  final PlaybackSettings playbackSettings;

  final VoidCallback onOpen;

  final VoidCallback onEditTags;

  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final tags = item.tags.toList()..sort();
    return Material(
      key: LibrarySmokeKeys.videoListRow(item.path),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onDoubleTap: onOpen,
        child: Ink(
          decoration: BoxDecoration(
            color: _appPanel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _appBorder),
          ),
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;
              final thumbnailWidth = narrow ? 116.0 : 146.0;
              final visibleTagCount = narrow ? 2 : 4;
              // 中等宽度窗口下右侧标签面板会压缩列表列宽；行按钮应先降级为图标，
              // 而不是继续保留 276px 操作区导致整行底部出现 overflow 条纹。
              final compactActions = constraints.maxWidth < 700;
              final rowContentWidth = math.min(
                constraints.maxWidth,
                narrow ? constraints.maxWidth : 980.0,
              );
              return Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: rowContentWidth,
                  child: Row(
                    children: [
                      SizedBox(
                        width: thumbnailWidth,
                        child: _VideoPreview(
                          item: item,
                          thumbnailService: thumbnailService,
                          playbackSettings: playbackSettings,
                          onOpen: (_) => onOpen(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item.title,
                              maxLines: narrow ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: _appText,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              item.folder,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xff718096),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 24,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  if (tags.isEmpty)
                                    const _ListTagPill(
                                      label: '\u672a\u6dfb\u52a0\u6807\u7b7e',
                                    )
                                  else ...[
                                    for (final tag
                                        in tags.take(visibleTagCount))
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 6),
                                        child: _ListTagPill(label: tag),
                                      ),
                                    if (tags.length > visibleTagCount)
                                      _ListTagPill(
                                        label:
                                            '+${tags.length - visibleTagCount}',
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _ListRowActions(
                        item: item,
                        onOpen: onOpen,
                        onToggleFavorite: onToggleFavorite,
                        onEditTags: onEditTags,
                        compact: compactActions,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ListTagPill extends StatelessWidget {
  const _ListTagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: const Color(0xfff4f6fb),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _appBorder),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xff4b5565),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ListRowActions extends StatelessWidget {
  const _ListRowActions({
    required this.item,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onEditTags,
    required this.compact,
  });

  final VideoItem item;

  final VoidCallback onOpen;

  final VoidCallback onToggleFavorite;

  final VoidCallback onEditTags;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: compact ? 112 : 276,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!compact) ...[
            SizedBox(
              width: 78,
              height: 34,
              child: GestureDetector(
                key: LibrarySmokeKeys.listPlay(item.path),
                behavior: HitTestBehavior.opaque,
                onTap: onOpen,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _appAccentViolet,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_arrow_rounded,
                          size: 18, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        '\u64ad\u653e',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton.outlined(
            key: LibrarySmokeKeys.listFavorite(item.path),
            tooltip: item.isFavorite
                ? '\u53d6\u6d88\u6536\u85cf'
                : '\u6dfb\u52a0\u6536\u85cf',
            onPressed: onToggleFavorite,
            icon:
                Icon(item.isFavorite ? Icons.favorite : Icons.favorite_border),
            style: IconButton.styleFrom(
              fixedSize: const Size(34, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            key: LibrarySmokeKeys.listMore(item.path),
            onPressed: onEditTags,
            tooltip: '\u66f4\u591a',
            icon: const Icon(Icons.more_horiz_rounded),
            style: IconButton.styleFrom(
              fixedSize: const Size(34, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractiveVideoCard extends StatefulWidget {
  const _InteractiveVideoCard({
    required this.item,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.onOpen,
    required this.onEditTags,
    required this.onToggleFavorite,
  });

  final VideoItem item;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  final VoidCallback onOpen;
  final VoidCallback onEditTags;
  final VoidCallback onToggleFavorite;

  @override
  State<_InteractiveVideoCard> createState() => _InteractiveVideoCardState();
}

class _InteractiveVideoCardState extends State<_InteractiveVideoCard> {
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: _motionDuration,
          curve: _motionCurve,
          scale: _pressed ? 0.992 : 1,
          child: AnimatedContainer(
            duration: _motionDuration,
            curve: _motionCurve,
            decoration: BoxDecoration(
              color: _appPanel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered ? _appAccentViolet : _appBorder,
              ),
              boxShadow: [
                ..._appSoftShadow,
                if (_hovered)
                  BoxShadow(
                    color: _appAccentViolet.withAlpha(45),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onDoubleTap: widget.onOpen,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _VideoPreview(
                        item: item,
                        thumbnailService: widget.thumbnailService,
                        playbackSettings: widget.playbackSettings,
                        onOpen: (_) => widget.onOpen(),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: _appText,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.folder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff718096),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      SizedBox(
                        height: 26,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: item.tags.isEmpty
                                ? [
                                    const Text(
                                      '\u672a\u6dfb\u52a0\u6807\u7b7e',
                                      style: TextStyle(color: Colors.black45),
                                    ),
                                  ]
                                : [
                                    for (final tag
                                        in (item.tags.toList()..sort()))
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 6),
                                        child: Chip(
                                          label: Text(tag),
                                          labelStyle:
                                              const TextStyle(fontSize: 12),
                                          visualDensity: const VisualDensity(
                                            horizontal: -3,
                                            vertical: -4,
                                          ),
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                  ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final iconOnly = constraints.maxWidth < 260;
                          return Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: widget.onOpen,
                                  icon: const Icon(Icons.play_arrow),
                                  label: Text(iconOnly ? '' : '\u64ad\u653e'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _appAccentViolet,
                                    foregroundColor: Colors.white,
                                    fixedSize: const Size.fromHeight(34),
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.outlined(
                                tooltip: item.isFavorite
                                    ? '\u53d6\u6d88\u6536\u85cf'
                                    : '\u6dfb\u52a0\u6536\u85cf',
                                onPressed: widget.onToggleFavorite,
                                icon: Icon(item.isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border),
                                style: IconButton.styleFrom(
                                  fixedSize: const Size(34, 34),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.outlined(
                                tooltip: '\u66f4\u591a',
                                onPressed: widget.onEditTags,
                                icon: const Icon(Icons.more_horiz_rounded),
                                style: IconButton.styleFrom(
                                  fixedSize: const Size(34, 34),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
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

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({
    required this.item,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.onOpen,
  });

  final VideoItem item;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  final ValueChanged<VideoItem> onOpen;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late Future<File?> _future;
  Timer? _hoverTimer;
  Player? _hoverPlayer;
  VideoController? _hoverController;
  var _isHoverPreviewLoading = false;
  var _isHoverPreviewReady = false;

  @override
  void initState() {
    super.initState();
    _future = widget.thumbnailService.thumbnailFor(widget.item);
  }

  @override
  void didUpdateWidget(covariant _VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.path != widget.item.path ||
        oldWidget.thumbnailService != widget.thumbnailService) {
      _stopHoverPreview();
      _future = widget.thumbnailService.thumbnailFor(widget.item);
    }
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    unawaited(_disposeHoverPlayer());
    super.dispose();
  }

  void _onEnter(PointerEnterEvent _) {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 900), _startHoverPreview);
  }

  void _onExit(PointerExitEvent _) {
    _hoverTimer?.cancel();
    _stopHoverPreview();
  }

  Future<void> _startHoverPreview() async {
    if (_hoverPlayer != null || _isHoverPreviewLoading) {
      return;
    }
    setState(() => _isHoverPreviewLoading = true);

    final player = Player(
      configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
    );
    final controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        width: 640,
        height: 360,
        hwdec: widget.playbackSettings.hwdec,
        enableHardwareAcceleration:
            widget.playbackSettings.hardwareDecodingEnabled,
      ),
    );

    _hoverPlayer = player;
    _hoverController = controller;

    try {
      await player.setVolume(0);
      await player.open(Media(widget.item.path), play: true).timeout(
            const Duration(seconds: 10),
          );
      await controller.platform.future
          .then((platform) => platform.waitUntilFirstFrameRendered)
          .timeout(const Duration(seconds: 8), onTimeout: () {});
      if (!mounted || _hoverPlayer != player) {
        await player.dispose();
        return;
      }
      setState(() {
        _isHoverPreviewLoading = false;
        _isHoverPreviewReady = true;
      });
    } catch (_) {
      if (_hoverPlayer == player) {
        _hoverPlayer = null;
        _hoverController = null;
      }
      await player.dispose();
      if (mounted) {
        setState(() {
          _isHoverPreviewLoading = false;
          _isHoverPreviewReady = false;
        });
      }
    }
  }

  void _stopHoverPreview() {
    final player = _hoverPlayer;
    _hoverPlayer = null;
    _hoverController = null;
    if (mounted) {
      setState(() {
        _isHoverPreviewLoading = false;
        _isHoverPreviewReady = false;
      });
    }
    if (player != null) {
      unawaited(player.dispose());
    }
  }

  Future<void> _disposeHoverPlayer() async {
    final player = _hoverPlayer;
    _hoverPlayer = null;
    _hoverController = null;
    if (player != null) {
      await player.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoverController = _hoverController;
    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<File?>(
                key: ValueKey(widget.item.path),
                future: _future,
                builder: (context, snapshot) {
                  final file = snapshot.data;
                  if (file != null && file.existsSync()) {
                    return Image.file(
                      file,
                      key: ValueKey(file.path),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: false,
                    );
                  }
                  return Container(
                    color: const Color(0xffd8f0f0),
                    child: Center(
                      child: snapshot.connectionState == ConnectionState.waiting
                          ? const SizedBox.square(
                              dimension: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.4),
                            )
                          : const Icon(Icons.movie_outlined, size: 42),
                    ),
                  );
                },
              ),
              if (_isHoverPreviewReady && hoverController != null)
                Video(
                  controller: hoverController,
                  controls: NoVideoControls,
                  fit: BoxFit.cover,
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.02),
                        Colors.black.withValues(alpha: 0.34),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: _isHoverPreviewLoading
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.86),
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(18),
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      )
                    : IconButton.filled(
                        tooltip: _isHoverPreviewReady
                            ? '\u6b63\u5728\u9884\u89c8\uff0c\u70b9\u51fb\u64ad\u653e'
                            : '\u64ad\u653e',
                        onPressed: () => widget.onOpen(widget.item),
                        icon: const Icon(Icons.play_arrow_rounded, size: 34),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.88),
                          foregroundColor: const Color(0xff073b3b),
                          fixedSize: const Size(58, 58),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasLibrary, this.message});

  final bool hasLibrary;

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasLibrary
                ? Icons.filter_alt_off_outlined
                : Icons.video_library_outlined,
            size: 54,
            color: Colors.black38,
          ),
          const SizedBox(height: 12),
          Text(message ??
              (hasLibrary
                  ? '\u6ca1\u6709\u5339\u914d\u7684\u89c6\u9891'
                  : '\u6dfb\u52a0\u89c6\u9891\u76ee\u5f55\u540e\u5f00\u59cb\u626b\u63cf')),
        ],
      ),
    );
  }
}

class TagEditorDialog extends StatefulWidget {
  const TagEditorDialog({
    super.key,
    required this.title,
    required this.initialTags,
    required this.existingTags,
  });

  final String title;
  final Set<String> initialTags;
  final Set<String> existingTags;

  @override
  State<TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<TagEditorDialog> {
  late final Set<String> _tags = _normalizeTags(widget.initialTags);
  final _controller = TextEditingController();

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
      _addNormalizedTag(tag);
      _controller.clear();
    });
  }

  void _addNormalizedTag(String tag) {
    if (!_tags.any((existing) => TagRules.sameTag(existing, tag))) {
      _tags.add(tag);
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final suggestions = _normalizeTags(
      widget.existingTags.where(
        (tag) => !_tags.any((selected) => TagRules.sameTag(selected, tag)),
      ),
    ).toList()
      ..sort();
    return AlertDialog(
      title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '\u65b0\u6807\u7b7e',
                prefixIcon: Icon(Icons.sell_outlined),
              ),
              onSubmitted: _addTag,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in (_tags.toList()..sort()))
                  InputChip(
                    label: Text(tag),
                    onDeleted: () => setState(() => _tags.remove(tag)),
                  ),
              ],
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('\u5df2\u6709\u6807\u7b7e',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in suggestions.take(24))
                    ActionChip(
                      label: Text(tag),
                      onPressed: () => setState(() => _addNormalizedTag(tag)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('\u53d6\u6d88'),
        ),
        FilledButton(
          onPressed: () {
            _addTag(_controller.text);
            Navigator.of(context).pop(_tags);
          },
          child: const Text('\u4fdd\u5b58'),
        ),
      ],
    );
  }
}
