import 'package:flutter/material.dart';

import '../../models/platform_models.dart';
import '../app_theme_tokens.dart';
import 'library_tag_discovery_chip.dart';
import 'library_tag_display_helpers.dart';

// ignore_for_file: slash_for_doc_comments

class TagPanelTabButton extends StatelessWidget {
  const TagPanelTabButton({
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
    final accessibility = AppAccessibilityScope.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: AnimatedContainer(
            duration: accessibility.fadeDuration(AppMotion.press),
            curve: AppMotion.standardCurve,
            decoration: BoxDecoration(
              color: selected ? librarySurface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected
                    ? appAccentViolet.withValues(alpha: 0.42)
                    : Colors.transparent,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 7,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : const [],
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? appAccentViolet : libraryTextMuted,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class SmartFilterContextCard extends StatelessWidget {
  const SmartFilterContextCard({super.key, required this.items});

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
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffc9c2ff)),
        boxShadow: [
          BoxShadow(
            color: appAccentViolet.withAlpha(18),
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
                  size: 16, color: appAccentViolet),
              SizedBox(width: 6),
              Text(
                '\u5f53\u524d\u7b5b\u9009\uff08\u0041\u004e\u0044\uff09',
                style: TextStyle(
                  color: appAccentViolet,
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
                    color: librarySurfaceAlt,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: libraryBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sell_outlined,
                          size: 11, color: appAccentViolet),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          item,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: libraryText,
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
class ActivePathBar extends StatelessWidget {
  const ActivePathBar({super.key, required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final effectiveItems =
        items.isEmpty ? const ['\u5168\u90e8\u89c6\u9891'] : items;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: libraryBorder),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.route_outlined, size: 18, color: appAccentStrong),
          for (var index = 0; index < effectiveItems.length; index++) ...[
            if (index > 0)
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: libraryTextMuted,
              ),
            Text(
              effectiveItems[index],
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: index == effectiveItems.length - 1
                        ? appAccentStrong
                        : libraryTextMuted,
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
class PopularTagRail extends StatelessWidget {
  const PopularTagRail({
    super.key,
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
                color: libraryTextMuted,
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
          TagFilterChip(
            tag: tag,
            groupColor: libraryGroupColor(tag.groupId ?? 'manual'),
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

class SecondaryTagCloud extends StatelessWidget {
  const SecondaryTagCloud({
    super.key,
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
              SecondaryTagPill(
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

class SecondaryTagPill extends StatelessWidget {
  const SecondaryTagPill({
    super.key,
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
    final displayName = tag.displayName ?? tag.name;
    final semanticLabel = parentLabel == null || parentLabel.isEmpty
        ? displayName
        : '$displayName / $parentLabel';
    final background = excluded
        ? const Color(0xfffff1f0)
        : selected
            ? const Color(0xfff2efff)
            : librarySurfaceAlt;
    final border = excluded
        ? const Color(0xffffb4ad)
        : selected
            ? const Color(0xffd2caff)
            : const Color(0xffe6ecf5);
    final textColor = excluded ? const Color(0xffb42318) : appAccentViolet;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      value: formatCount(count),
      child: Tooltip(
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
                        excluded ? 'NOT $displayName' : displayName,
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
                          color: librarySurfaceAlt,
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
      ),
    );
  }
}
