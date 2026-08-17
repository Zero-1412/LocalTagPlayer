import 'package:flutter/material.dart';
import '../../models/platform_models.dart';
import '../app_theme_tokens.dart';
import 'library_desktop_scroll_behavior.dart';
import 'library_smoke_keys.dart';
import 'library_folder_tag_discovery.dart';
import 'library_reference_icon_button.dart';

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
  final _panelScrollController = ScrollController();

  var _mode = TagDiscoveryMode.primary;

  String? _expandedPrimaryTagId;

  var _showAllPrimaryTags = false;

  final _expandedChildTagIds = <String>{};

  @override
  void dispose() {
    _panelScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryGroups = primaryTagGroupsForDiscovery(widget.tagGroups);
    final allSecondaryTags = secondaryTagsForDiscovery(
      widget.tagGroups,
      widget.resultCounts,
    );
    final outerPanelWidth = widget.panelWidth ?? 482.0;
    final innerPanelWidth =
        (outerPanelWidth - 28).clamp(276.0, 592.0).toDouble();
    final panel = Container(
      width: widget.dense ? double.infinity : innerPanelWidth,
      margin: EdgeInsets.fromLTRB(widget.dense ? 12 : 12, 12, 16, 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: librarySurface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: libraryBorder.withValues(alpha: 0.86)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TagDiscoveryPanelHeader(onCollapse: widget.onCollapse),
          const SizedBox(height: 12),
          Container(
            height: libraryTopBarControlHeight,
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
          // 切换器直接连接标签内容，避免重复搜索和说明占用面板高度。
          const SizedBox(height: 16),
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
