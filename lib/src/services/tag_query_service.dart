part of '../../main.dart';

class TagQueryService {
  const TagQueryService({
    required this.videos,
    required this.tagContext,
  });

  final Iterable<VideoItem> videos;
  final TagQueryContext tagContext;

  List<VideoItem> filter(FilterQuery query) {
    return videos
        .where((item) => query.matches(item, tagContext: tagContext))
        .toList();
  }

  Map<String, int> resultCounts(FilterQuery query, Iterable<TagItem> tags) {
    final counts = <String, int>{for (final tag in tags) tag.id: 0};
    final tagList = tags.toList();
    for (final tag in tagList) {
      final baseQuery = _withoutCandidateGroup(query, tag);
      for (final item in videos.where((item) => baseQuery.matches(item, tagContext: tagContext))) {
        if (_hasTag(item, tag)) {
          counts[tag.id] = (counts[tag.id] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  FilterQuery _withoutCandidateGroup(FilterQuery query, TagItem candidate) {
    final groupId = candidate.groupId;
    if (groupId == null) {
      return query;
    }
    return FilterQuery(
      keyword: query.keyword,
      primaryTagId: query.primaryTagId,
      childTagId: query.childTagId,
      groups: [
        for (final group in query.groups)
          if (group.id != groupId) group,
      ],
      includeTagIds: {
        for (final tagId in query.includeTagIds)
          if (tagContext.tagsById[tagId]?.groupId != groupId) tagId,
      },
      excludeTagIds: query.excludeTagIds,
      selectedGroupTagIds: {
        for (final entry in query.selectedGroupTagIds.entries)
          if (entry.key != groupId) entry.key: entry.value,
      },
      sortRule: query.sortRule,
      excludedItems: query.excludedItems,
      favoriteOnly: query.favoriteOnly,
      unplayedOnly: query.unplayedOnly,
      errorOnly: query.errorOnly,
    );
  }

  Map<String, int> selectedResultCounts(FilterQuery query, Iterable<TagItem> tags) {
    final counts = <String, int>{for (final tag in tags) tag.id: 0};
    for (final item in filter(query)) {
      for (final tag in tags) {
        if (_hasTag(item, tag)) {
          counts[tag.id] = (counts[tag.id] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  bool _hasTag(VideoItem item, TagItem tag) {
    if (tagContext.videoHasTagId(item, tag.id)) {
      return true;
    }
    return item.tags.any((value) => TagRules.sameTag(value, tag.name)) ||
        item.childTags.values.any(
          (children) => children.any((value) => TagRules.sameTag(value, tag.name)),
        );
  }
}
