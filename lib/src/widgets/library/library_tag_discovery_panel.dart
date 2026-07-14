part of '../../app.dart';

// ignore_for_file: slash_for_doc_comments

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
    this.semanticLabel,
  });

  final TagItem tag;

  final Color groupColor;

  final int count;

  final bool selected;

  final bool excluded;

  final VoidCallback onToggle;

  final VoidCallback onExcludeToggle;

  /**
   * 真实窗口 QA 使用的稳定语义标签。
   *
   * 二级标签需要携带所属一级上下文，避免辅助树定位时把不同层级的同名标签混在一起。
   */
  final String? semanticLabel;

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
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? LibrarySmokeSemantics.genericTag(tag),
      value: _formatCount(count),
      child: GestureDetector(
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
          Semantics(
            button: true,
            selected: selected,
            label: LibrarySmokeSemantics.primaryTag(tag),
            value: _formatCount(count),
            child: GestureDetector(
              key: LibrarySmokeKeys.primaryHeader(tag.id),
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Icon(Icons.expand_more_rounded,
                        size: 20,
                        color: selected ? _appAccentViolet : _appText),
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
                  semanticLabel: LibrarySmokeSemantics.childTag(
                    tag,
                    TagItem(
                      id: '${tag.id}::default-album',
                      name: TagRules.defaultAlbumTag,
                      displayName: TagRules.defaultAlbumTag,
                      groupId: 'folder.child',
                      parentId: tag.id,
                      source: TagSource.folder,
                    ),
                  ),
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
                    semanticLabel: LibrarySmokeSemantics.childTag(tag, child),
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
      child: Semantics(
        button: true,
        selected: selected,
        label: LibrarySmokeSemantics.primaryTag(tag),
        value: _formatCount(count),
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

@visibleForTesting
bool referenceTopBarSearchShouldFillRow(
  LayoutSize layoutSize,
  double rowWidth,
) {
  /**
   * expanded 主界面顶部栏要把搜索框扩展到按钮左侧剩余空间；
   * medium / compact 或窄行宽下也继续使用弹性宽度，避免右侧动作按钮溢出。
   */
  return layoutSize == LayoutSize.expanded ||
      layoutSize == LayoutSize.compact ||
      rowWidth < 1040;
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
