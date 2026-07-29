import 'package:flutter/material.dart';

import '../../core/tag_rules.dart';
import '../../models/platform_models.dart';
import '../app_theme_tokens.dart';
import 'library_smoke_keys.dart';
import 'library_tag_discovery_chip.dart';
import 'library_tag_display_helpers.dart';

// ignore_for_file: slash_for_doc_comments

class PrimaryAccordionRow extends StatelessWidget {
  const PrimaryAccordionRow({
    super.key,
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
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: libraryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            selected: selected,
            label: LibrarySmokeSemantics.primaryTag(tag),
            value: formatCount(count),
            child: GestureDetector(
              key: LibrarySmokeKeys.primaryHeader(tag.id),
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: selected ? appAccentViolet : libraryText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tag.displayName ?? tag.name,
                        style: const TextStyle(
                          color: libraryText,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      formatCount(count),
                      style: const TextStyle(
                        color: libraryTextMuted,
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
                TagFilterChip(
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
                  TagFilterChip(
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
              child: ExpandAllChildrenButton(
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

class ExpandAllChildrenButton extends StatelessWidget {
  const ExpandAllChildrenButton({
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
              color: libraryTextMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class CollapsedPrimaryRow extends StatelessWidget {
  const CollapsedPrimaryRow({
    super.key,
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
        value: formatCount(count),
        child: Material(
          key: LibrarySmokeKeys.primaryRow(tag.id),
          color: selected ? librarySurfaceAlt : librarySurface,
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
                  color: selected ? const Color(0xffd8d4ff) : libraryBorder,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.chevron_right_rounded,
                      size: 20, color: libraryText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tag.displayName ?? tag.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: libraryText,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    formatCount(count),
                    style: const TextStyle(
                      color: libraryTextMuted,
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

class ShowMorePrimaryButton extends StatelessWidget {
  const ShowMorePrimaryButton({
    super.key,
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
          foregroundColor: appAccentViolet,
          side: const BorderSide(color: Color(0xffd8d4ff)),
          backgroundColor: librarySurfaceAlt,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );
  }
}

/**
 * 右侧标签筛选面板收起后的恢复入口。
 *
 * 窄条需要保留按钮语义和稳定 key，真实窗口 smoke test 与辅助技术都依赖该入口恢复右侧标签发现闭环。
 */
const double collapsedTagDiscoveryRailWidth = 44;

/** 折叠条减少横向占用，把释放空间还给默认视频网格。 */
const EdgeInsets collapsedTagDiscoveryRailMargin =
    EdgeInsets.fromLTRB(8, 12, 12, 16);

/** 右侧折叠条包含外边距后的完整布局宽度。 */
double get collapsedTagDiscoveryRailLayoutWidth =>
    collapsedTagDiscoveryRailWidth + collapsedTagDiscoveryRailMargin.horizontal;
