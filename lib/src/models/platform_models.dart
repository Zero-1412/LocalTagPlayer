part of '../../main.dart';

enum TagSource { folder, manual, rule, filename, import, auto }

enum CacheStatusKind { unknown, missing, queued, loading, ready, failed }

enum DiagnoseSeverity { normal, warning, error }

enum TagGroupLogic { sameGroupOr, sameGroupAnd }

enum SortRule { titleAsc, addedDesc, lastPlayedDesc }

class TagItem {
  const TagItem({
    required this.id,
    required this.name,
    required this.source,
    this.displayName,
    this.groupId,
    this.parentId,
    this.color,
    this.aliases = const <String>[],
    this.usageCount = 0,
    this.isFavorite = false,
    this.isHidden = false,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String? displayName;
  final String? groupId;
  final TagSource source;
  final String? parentId;
  final String? color;
  final List<String> aliases;
  final int usageCount;
  final bool isFavorite;
  final bool isHidden;
  final int sortOrder;

  bool matchesNameOrAlias(String normalizedToken) {
    if (id.toLowerCase().contains(normalizedToken) ||
        name.toLowerCase().contains(normalizedToken) ||
        (displayName?.toLowerCase().contains(normalizedToken) ?? false)) {
      return true;
    }
    return aliases.any((alias) => alias.toLowerCase().contains(normalizedToken));
  }
}

class VideoTagLink {
  const VideoTagLink({
    required this.videoPath,
    required this.tagId,
    required this.source,
    this.locked = false,
  });

  final String videoPath;
  final String tagId;
  final TagSource source;
  final bool locked;
}

class TagUsageSummary {
  const TagUsageSummary({
    this.total = 0,
    this.folder = 0,
    this.manual = 0,
    this.rule = 0,
    this.filename = 0,
    this.imported = 0,
    this.auto = 0,
  });

  final int total;
  final int folder;
  final int manual;
  final int rule;
  final int filename;
  final int imported;
  final int auto;

  int countFor(TagSource source) {
    switch (source) {
      case TagSource.folder:
        return folder;
      case TagSource.manual:
        return manual;
      case TagSource.rule:
        return rule;
      case TagSource.filename:
        return filename;
      case TagSource.import:
        return imported;
      case TagSource.auto:
        return auto;
    }
  }

  TagUsageSummary increment(TagSource source, int count) {
    return TagUsageSummary(
      total: total + count,
      folder: folder + (source == TagSource.folder ? count : 0),
      manual: manual + (source == TagSource.manual ? count : 0),
      rule: rule + (source == TagSource.rule ? count : 0),
      filename: filename + (source == TagSource.filename ? count : 0),
      imported: imported + (source == TagSource.import ? count : 0),
      auto: auto + (source == TagSource.auto ? count : 0),
    );
  }
}

class TagQueryContext {
  const TagQueryContext({
    this.tagsById = const <String, TagItem>{},
    this.videoTagIdsByPathKey = const <String, Set<String>>{},
  });

  final Map<String, TagItem> tagsById;
  final Map<String, Set<String>> videoTagIdsByPathKey;

  Iterable<TagItem> tagsFor(VideoItem item) sync* {
    final ids = videoTagIdsByPathKey[TagRules.pathKey(item.path)] ?? const <String>{};
    for (final id in ids) {
      final tag = tagsById[id];
      if (tag != null) {
        yield tag;
      }
    }
  }

  bool videoHasTagId(VideoItem item, String tagId) {
    return videoTagIdsByPathKey[TagRules.pathKey(item.path)]?.contains(tagId) ?? false;
  }
}

class TagGroup {
  const TagGroup({
    required this.id,
    required this.name,
    required this.items,
    this.displayName,
    this.sortOrder = 0,
    this.allowMultiSelect = true,
    this.defaultLogic = TagGroupLogic.sameGroupOr,
    this.excludedItems = const <TagItem>[],
  });

  final String id;
  final String name;
  final String? displayName;
  final int sortOrder;
  final bool allowMultiSelect;
  final TagGroupLogic defaultLogic;
  final List<TagItem> items;
  final List<TagItem> excludedItems;

  bool get isEmpty => items.isEmpty && excludedItems.isEmpty;
}

class FilterQuery {
  const FilterQuery({
    this.keyword,
    this.primaryTagId,
    this.childTagId,
    this.groups = const <TagGroup>[],
    this.includeTagIds = const <String>{},
    this.excludeTagIds = const <String>{},
    this.selectedGroupTagIds = const <String, Set<String>>{},
    this.sortRule = SortRule.titleAsc,
    this.excludedItems = const <TagItem>[],
    this.favoriteOnly = false,
    this.unplayedOnly = false,
    this.errorOnly = false,
  });

  final String? keyword;
  final String? primaryTagId;
  final String? childTagId;
  final List<TagGroup> groups;
  final Set<String> includeTagIds;
  final Set<String> excludeTagIds;
  final Map<String, Set<String>> selectedGroupTagIds;
  final SortRule sortRule;
  final List<TagItem> excludedItems;
  final bool favoriteOnly;
  final bool unplayedOnly;
  final bool errorOnly;

  bool get isEmpty =>
      (keyword == null || keyword!.trim().isEmpty) &&
      primaryTagId == null &&
      childTagId == null &&
      groups.every((group) => group.isEmpty) &&
      includeTagIds.isEmpty &&
      excludeTagIds.isEmpty &&
      selectedGroupTagIds.values.every((tagIds) => tagIds.isEmpty) &&
      excludedItems.isEmpty &&
      !favoriteOnly &&
      !unplayedOnly &&
      !errorOnly;

  bool matches(VideoItem item, {TagQueryContext tagContext = const TagQueryContext()}) {
    if (favoriteOnly && !item.isFavorite) {
      return false;
    }
    if (unplayedOnly && item.lastPlayedAt != null) {
      return false;
    }
    if (errorOnly && item.thumbnailError == null && item.mediaDetailsError == null) {
      return false;
    }
    if (primaryTagId != null && !item.tags.any((tag) => TagRules.sameTag(tag, primaryTagId!))) {
      return false;
    }
    if (primaryTagId != null && childTagId != null && !TagRules.matchesChildTag(item, primaryTagId!, childTagId!)) {
      return false;
    }
    if (!TagRules.matchesSearch(item, keyword ?? '', tagItems: tagContext.tagsFor(item))) {
      return false;
    }
    if (includeTagIds.any((tagId) => !_matchesTagIdOrName(item, tagId, tagContext))) {
      return false;
    }
    if (excludeTagIds.any((tagId) => _matchesTagIdOrName(item, tagId, tagContext))) {
      return false;
    }
    if (selectedGroupTagIds.values.any(
      (tagIds) => tagIds.isNotEmpty && !tagIds.any((tagId) => _matchesTagIdOrName(item, tagId, tagContext)),
    )) {
      return false;
    }
    if (excludedItems.any((tag) => _matchesTagItem(item, tag, tagContext))) {
      return false;
    }

    // Filter groups are ANDed together; each group matches when any included item matches and no group-level NOT item matches.
    for (final group in groups.where((group) => !group.isEmpty)) {
      if (group.excludedItems.any((tag) => _matchesTagItem(item, tag, tagContext))) {
        return false;
      }
      if (group.items.isNotEmpty && !group.items.any((tag) => _matchesTagItem(item, tag, tagContext))) {
        return false;
      }
    }
    return true;
  }

  static bool _matchesTagItem(VideoItem item, TagItem tag, TagQueryContext tagContext) {
    if (tagContext.videoHasTagId(item, tag.id)) {
      return true;
    }
    final indexedTagIds = tagContext.videoTagIdsByPathKey[TagRules.pathKey(item.path)];
    if (indexedTagIds != null && tagContext.tagsById.containsKey(tag.id)) {
      return false;
    }
    final parentId = tag.parentId;
    if (parentId != null) {
      return TagRules.matchesChildTag(item, parentId, tag.name);
    }
    if (tag.id != tag.name && _matchesTagIdOrName(item, tag.id, tagContext)) {
      return true;
    }
    return item.tags.any((itemTag) => TagRules.sameTag(itemTag, tag.name)) ||
        item.childTags.values.any((children) => children.any((childTag) => TagRules.sameTag(childTag, tag.name)));
  }

  static bool _matchesTagIdOrName(VideoItem item, String tagIdOrName, TagQueryContext tagContext) {
    if (tagContext.videoHasTagId(item, tagIdOrName)) {
      return true;
    }
    final indexedTag = tagContext.tagsById[tagIdOrName];
    if (indexedTag != null) {
      return _matchesTagItem(item, indexedTag, tagContext);
    }
    return item.tags.any((itemTag) => TagRules.sameTag(itemTag, tagIdOrName)) ||
        item.childTags.values.any((children) => children.any((childTag) => TagRules.sameTag(childTag, tagIdOrName)));
  }
}

class PlaybackSession {
  const PlaybackSession({
    required this.currentPath,
    required this.queuePaths,
    this.filterQuery = const FilterQuery(),
    this.id,
    this.currentVideoId,
    this.createdAt,
    this.position = Duration.zero,
    this.duration,
    this.isPlaying = false,
  });

  final String? id;
  final String currentPath;
  final List<String> queuePaths;
  final FilterQuery filterQuery;
  final String? currentVideoId;
  final DateTime? createdAt;
  final Duration position;
  final Duration? duration;
  final bool isPlaying;
}

class CacheStatus {
  const CacheStatus({
    required this.kind,
    this.path,
    this.message,
    this.updatedAt,
  });

  final CacheStatusKind kind;
  final String? path;
  final String? message;
  final DateTime? updatedAt;
}

class DiagnoseStatus {
  const DiagnoseStatus({
    required this.severity,
    required this.message,
    this.position,
    this.droppedFrames,
    this.audioVideoOffset,
    this.sampledAt,
  });

  final DiagnoseSeverity severity;
  final String message;
  final Duration? position;
  final int? droppedFrames;
  final Duration? audioVideoOffset;
  final DateTime? sampledAt;
}
