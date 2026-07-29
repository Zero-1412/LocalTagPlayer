import '../../core/tag_rules.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import 'library_tag_display_helpers.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 从真实本地媒体库路径派生右侧发现面板的文件夹标签。
 *
 * 该函数不信任历史 folder 标签记录，而是按当前视频路径相对媒体库 root 的层级重新
 * 计算：root 下一层是一级，再下一层是二级。多个 root 命中时优先使用最上层 root。
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

/** 只保留符合当前 root 层级规则的一级 folder 标签。 */
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
              if (isFolderPrimaryDiscoveryTag(tag)) tag,
          ],
          excludedItems: group.excludedItems,
        ),
  ];
}

/** 返回去除虚拟默认专辑并按实时结果数排序的二级 folder 标签。 */
List<TagItem> secondaryTagsForDiscovery(
  List<TagGroup> groups,
  Map<String, int> resultCounts,
) {
  final tags = <TagItem>[
    for (final group in groups)
      if (group.id == 'folder.child')
        for (final tag in group.items)
          if (isFolderChildDiscoveryTag(tag) &&
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
