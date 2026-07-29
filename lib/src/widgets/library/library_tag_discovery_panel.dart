import 'package:flutter/material.dart';
import '../../core/tag_rules.dart';
import '../../models/platform_models.dart';
import '../app_theme_tokens.dart';
import 'library_desktop_scroll_behavior.dart';
import 'library_smoke_keys.dart';
import 'library_folder_tag_discovery.dart';

// ignore_for_file: use_key_in_widget_constructors
import 'library_tag_discovery_context.dart';
import 'library_tag_discovery_group.dart';

export 'library_collapsed_tag_discovery_rail.dart'
    show CollapsedTagDiscoveryRail, collapsedTagDiscoveryRailSmokeHarness;

// ignore_for_file: slash_for_doc_comments

enum TagDiscoveryMode { primary, secondary }

enum PrimaryTagSortMode { countDesc, nameAsc, frequentDesc }

/**
 * 右侧标签面板标题。
 *
 * expanded 布局传入 [onCollapse] 后，筛选图标和标题文字共同承担收起动作；不再额外
 * 放置容易误解的独立箭头。dense 弹层不传回调时保持纯标题展示。
 */
class _TagDiscoveryPanelHeader extends StatelessWidget {
  const _TagDiscoveryPanelHeader({this.onCollapse});

  /** 收起右侧标签面板；为空时标题不创建点击语义。 */
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    const headerContent = Padding(
      // 48px 高命中区域替代原箭头按钮，桌面鼠标和键盘焦点都容易定位。
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.filter_alt_outlined,
            color: appAccentViolet,
            size: 24,
          ),
          SizedBox(width: 12),
          Text(
            '\u6807\u7b7e\u7b5b\u9009',
            style: TextStyle(
              color: libraryText,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
    final collapse = onCollapse;
    if (collapse == null) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: headerContent,
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: '\u6536\u8d77\u6807\u7b7e\u7b5b\u9009',
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          label: '\u6536\u8d77\u6807\u7b7e\u7b5b\u9009',
          excludeSemantics: true,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: LibrarySmokeKeys.tagPanelCollapseHeader,
              borderRadius: BorderRadius.circular(10),
              onTap: collapse,
              child: headerContent,
            ),
          ),
        ),
      ),
    );
  }
}

class TagDiscoveryZone extends StatefulWidget {
  const TagDiscoveryZone({
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
  State<TagDiscoveryZone> createState() => TagDiscoveryZoneState();
}

class TagDiscoveryZoneState extends State<TagDiscoveryZone> {
  late final TextEditingController _tagSearchController =
      TextEditingController();

  final _panelScrollController = ScrollController();

  var _mode = TagDiscoveryMode.primary;

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
        (outerPanelWidth - 28).clamp(276.0, 592.0).toDouble();
    final panel = Container(
      width: widget.dense ? double.infinity : innerPanelWidth,
      margin: EdgeInsets.fromLTRB(widget.dense ? 12 : 12, 12, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: librarySurface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: libraryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TagDiscoveryPanelHeader(onCollapse: widget.onCollapse),
          const SizedBox(height: 18),
          Container(
            height: 44,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: librarySurfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TagPanelTabButton(
                    key: LibrarySmokeKeys.primaryTab,
                    label: '\u4e00\u7ea7\u6807\u7b7e',
                    selected: _mode == TagDiscoveryMode.primary,
                    onTap: () => setState(() {
                      _mode = TagDiscoveryMode.primary;
                    }),
                  ),
                ),
                Expanded(
                  child: TagPanelTabButton(
                    key: LibrarySmokeKeys.secondaryTab,
                    label: '\u5168\u90e8\u4e8c\u7ea7\u6807\u7b7e',
                    selected: _mode == TagDiscoveryMode.secondary,
                    onTap: () => setState(() {
                      _mode = TagDiscoveryMode.secondary;
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
              color: libraryTextMuted,
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ScrollConfiguration(
              behavior: const DesktopDragScrollBehavior(),
              child: ListView(
                controller: _panelScrollController,
                children: [
                  if (_mode == TagDiscoveryMode.primary) ...[
                    for (final group in primaryGroups)
                      DiscoveryGroupCard(
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
                        primarySortMode: PrimaryTagSortMode.countDesc,
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
                    SecondaryTagCloud(
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
