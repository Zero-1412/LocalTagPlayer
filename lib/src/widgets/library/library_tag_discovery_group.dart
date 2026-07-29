import 'package:flutter/material.dart';

import '../../models/platform_models.dart';
import '../app_theme_tokens.dart';
import 'library_tag_discovery_panel.dart';
import 'library_tag_discovery_rows.dart';
import 'library_tag_display_helpers.dart';

// ignore_for_file: slash_for_doc_comments

class DiscoveryGroupCard extends StatelessWidget {
  const DiscoveryGroupCard({
    super.key,
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

  final PrimaryTagSortMode primarySortMode;

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
    final groupColor = libraryGroupColor(group.id);
    final rankedItems = group.items.toList()
      ..sort((a, b) {
        switch (primarySortMode) {
          case PrimaryTagSortMode.countDesc:
            final byCount = (stablePrimaryCounts[b.id] ??
                    resultCounts[b.id] ??
                    b.usageCount)
                .compareTo(stablePrimaryCounts[a.id] ??
                    resultCounts[a.id] ??
                    a.usageCount);
            if (byCount != 0) {
              return byCount;
            }
          case PrimaryTagSortMode.frequentDesc:
            final byClicks = (primaryClickCounts[b.id] ?? 0)
                .compareTo(primaryClickCounts[a.id] ?? 0);
            if (byClicks != 0) {
              return byClicks;
            }
          case PrimaryTagSortMode.nameAsc:
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
              PrimaryAccordionRow(
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
              CollapsedPrimaryRow(
                tag: tag,
                count: resultCounts[tag.id] ?? 0,
                selected: selectedIds.contains(tag.id),
                onToggle: () => onExpandedPrimaryChanged(tag),
              ),
          if (rankedItems.length > defaultLimit)
            ShowMorePrimaryButton(
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
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: libraryBorder),
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
                        color: libraryText,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              Text(
                '${group.items.length}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: libraryTextMuted,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          for (final tag in visibleItems)
            if (expandedTag != null && tag.id == expandedTag.id)
              PrimaryAccordionRow(
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
              CollapsedPrimaryRow(
                tag: tag,
                count: resultCounts[tag.id] ?? 0,
                selected: selectedIds.contains(tag.id),
                onToggle: () => onExpandedPrimaryChanged(tag),
              ),
          if (primary && visibleItems.length < rankedItems.length)
            ShowMorePrimaryButton(
              remainingCount: rankedItems.length - visibleItems.length,
              expanded: showAllPrimaryTags,
              onPressed: onShowAllPrimaryTags,
            ),
        ],
      ),
    );
  }
}
