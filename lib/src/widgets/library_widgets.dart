part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

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
                          label: '\u672c\u5730\u6536\u85cf',
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
          label: const Text('\u672c\u5730\u6536\u85cf'),
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

class _ReferenceTopBar extends StatelessWidget {
  const _ReferenceTopBar({
    required this.controller,
    required this.videoCount,
    required this.totalCount,
    required this.keyword,
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
  });

  final TextEditingController controller;

  final int videoCount;

  final int totalCount;

  final String keyword;

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
                referenceTopBarSearchShouldFillRow(
              layoutSize,
              constraints.maxWidth,
            );
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
                const SizedBox(width: 12),
                if (!compact)
                  _TopSortControl(
                    sortMode: sortMode,
                    sortDirection: sortDirection,
                    onChanged: onSortChanged,
                    onDirectionToggle: onSortDirectionToggle,
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
  SortDirection sortDirection = SortDirection.descending,
  ValueChanged<SortMode>? onSortChanged,
  VoidCallback? onSortDirectionToggle,
}) {
  return MaterialApp(
    home: Scaffold(
      body: _ReferenceTopBar(
        controller: controller,
        videoCount: 0,
        totalCount: 0,
        keyword: controller.text,
        sortMode: SortMode.recent,
        sortDirection: sortDirection,
        layoutSize: LayoutSize.expanded,
        hasActiveFilters: false,
        onSearchChanged: onSearchChanged,
        onSortChanged: onSortChanged ?? (_) {},
        onSortDirectionToggle: onSortDirectionToggle ?? () {},
        denseResultGrid: false,
        onResultViewChanged: (_) {},
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
  });

  final String tooltip;

  final IconData icon;

  final VoidCallback onPressed;

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: _appPanel,
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
                color: _appBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: _appAccentStrong),
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
