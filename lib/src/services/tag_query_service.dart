part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

typedef VideoItemComparator = int Function(VideoItem a, VideoItem b);
typedef VideoItemSorter = List<VideoItem> Function(Iterable<VideoItem> videos);

class FilterState {
  const FilterState({
    required this.query,
    required this.filteredVideos,
    required this.resultCount,
    required this.totalCount,
  });

  final FilterQuery query;
  final List<VideoItem> filteredVideos;
  final int resultCount;
  final int totalCount;
}

class FilterStateSource {
  FilterState? _cachedState;
  String? _cachedSignature;
  TagQueryService _engine = const TagQueryService(
    videos: <VideoItem>[],
    tagContext: TagQueryContext(),
  );
  int _totalCount = 0;
  Object? _sourceKey;
  Object? _sortKey;
  VideoItemComparator? _compare;
  VideoItemSorter? _sortVideos;

  FilterState get state {
    final cachedState = _cachedState;
    if (cachedState != null) {
      return cachedState;
    }
    return update(const FilterQuery());
  }

  void configure({
    required TagQueryService engine,
    required int totalCount,
    Object? sourceKey,
    Object? sortKey,
    VideoItemComparator? compare,
    VideoItemSorter? sortVideos,
  }) {
    _engine = engine;
    _totalCount = totalCount;
    _sourceKey = sourceKey ?? engine.sourceSignature;
    _sortKey = sortKey;
    _compare = compare;
    _sortVideos = sortVideos;
  }

  FilterState update(FilterQuery query) {
    final signature = _signature(
      query: query,
      sourceKey: _sourceKey,
      sortKey: _sortKey,
    );
    final cachedState = _cachedState;
    if (cachedState != null && _cachedSignature == signature) {
      return cachedState;
    }

    var filteredVideos = _engine.filter(query);
    final sortVideos = _sortVideos;
    if (sortVideos != null) {
      filteredVideos = sortVideos(filteredVideos);
    }
    final compare = _compare;
    if (sortVideos == null && compare != null) {
      filteredVideos.sort(compare);
    }
    final state = FilterState(
      query: query,
      filteredVideos: List<VideoItem>.unmodifiable(filteredVideos),
      resultCount: filteredVideos.length,
      totalCount: _totalCount,
    );
    _cachedSignature = signature;
    _cachedState = state;
    return state;
  }

  /**
   * 仅重新评估扫描差量中的视频，保留未变项的已过滤列表。
   *
   * 如果尚无可复用状态或查询已变，则回退到完整计算；扫描结果通过
   * stable `videoId` 替换旧项，避免新增、missing 或 relink 导致整个列表重建。
   */
  FilterState applyVideoDelta(
    FilterQuery query,
    Iterable<VideoItem> changedVideos,
  ) {
    final cachedState = _cachedState;
    if (cachedState == null ||
        _querySignature(cachedState.query) != _querySignature(query)) {
      return update(query);
    }
    final changed = changedVideos.toList(growable: false);
    if (changed.isEmpty) {
      return update(query);
    }
    final changedIds = {for (final item in changed) item.videoId};
    final filteredVideos = <VideoItem>[
      for (final item in cachedState.filteredVideos)
        if (!changedIds.contains(item.videoId)) item,
      ...changed.where(
        (item) => query.matches(item, tagContext: _engine.tagContext),
      ),
    ];
    final sortVideos = _sortVideos;
    final sortedVideos =
        sortVideos == null ? filteredVideos : sortVideos(filteredVideos);
    final compare = _compare;
    if (sortVideos == null && compare != null) {
      sortedVideos.sort(compare);
    }
    final state = FilterState(
      query: query,
      filteredVideos: List<VideoItem>.unmodifiable(sortedVideos),
      resultCount: sortedVideos.length,
      totalCount: _totalCount,
    );
    _cachedSignature = _signature(
      query: query,
      sourceKey: _sourceKey,
      sortKey: _sortKey,
    );
    _cachedState = state;
    return state;
  }

  String _signature({
    required FilterQuery query,
    Object? sourceKey,
    Object? sortKey,
  }) {
    final buffer = StringBuffer()
      ..write(_querySignature(query))
      ..write('|source:')
      ..write(sourceKey)
      ..write('|sort:')
      ..write(sortKey);
    return buffer.toString();
  }

  String _sortedStrings(Iterable<String> values) {
    return (values.toList()..sort()).join(',');
  }

  String _querySignature(FilterQuery query) {
    String sortedGroups(Map<String, Set<String>> values) {
      final entries = values.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return entries
          .map((entry) => '${entry.key}:${_sortedStrings(entry.value)}')
          .join(';');
    }

    return [
      query.keyword ?? '',
      query.primaryTagId ?? '',
      query.childTagId ?? '',
      _sortedStrings(query.folderRoots),
      _sortedStrings(query.includeTagIds),
      _sortedStrings(query.excludeTagIds),
      sortedGroups(query.selectedGroupTagIds),
      query.sortRule.name,
      query.favoriteOnly,
      query.unplayedOnly,
      query.errorOnly,
      query.groups
          .map((group) =>
              '${group.id}:${group.items.map((tag) => tag.id).join(',')}')
          .join(';'),
      query.excludedItems.map((tag) => tag.id).join(','),
    ].join('|');
  }
}

class TagQueryService {
  const TagQueryService({
    required this.videos,
    required this.tagContext,
  });

  final Iterable<VideoItem> videos;
  final TagQueryContext tagContext;

  String get sourceSignature {
    final buffer = StringBuffer();
    for (final item in videos) {
      buffer
        ..write(TagRules.pathKey(item.path))
        ..write(',')
        ..write(_sortedStrings(item.tags))
        ..write(',')
        ..write(_childTagSignature(item.childTags))
        ..write(',')
        ..write(item.isFavorite)
        ..write(',')
        ..write(item.lastPlayedAt?.millisecondsSinceEpoch)
        ..write(',')
        ..write(item.thumbnailError)
        ..write(',')
        ..write(item.mediaDetailsError)
        ..write(';');
    }
    buffer
      ..write('|tags:')
      ..write(_tagContextSignature);
    return buffer.toString();
  }

  List<VideoItem> filter(FilterQuery query) {
    return videos
        .where((item) => query.matches(item, tagContext: tagContext))
        .toList();
  }

  Map<String, int> resultCounts(FilterQuery query, Iterable<TagItem> tags) {
    final counts = <String, int>{for (final tag in tags) tag.id: 0};
    final tagsByGroup = <String, List<TagItem>>{};
    for (final tag in tags) {
      (tagsByGroup[tag.groupId ?? '__ungrouped__'] ??= <TagItem>[]).add(tag);
    }

    for (final groupTags in tagsByGroup.values) {
      if (groupTags.isEmpty) {
        continue;
      }
      final candidateIds = {for (final tag in groupTags) tag.id};
      final candidateIdsByName = <String, Set<String>>{};
      for (final tag in groupTags) {
        (candidateIdsByName[tag.name.trim().toLowerCase()] ??= <String>{})
            .add(tag.id);
      }
      // 同组候选共享同一个 baseQuery：移除候选所在组后只扫描一次视频集合，
      // 避免“候选标签数 x 全量视频”的同步阻塞。
      final baseQuery = _withoutCandidateGroup(query, groupTags.first);
      for (final item in videos) {
        if (!baseQuery.matches(item, tagContext: tagContext)) {
          continue;
        }
        final countedIds = <String>{};
        final indexedTagIds =
            tagContext.videoTagIdsByPathKey[TagRules.pathKey(item.path)];
        if (indexedTagIds != null) {
          for (final tagId in indexedTagIds) {
            if (candidateIds.contains(tagId)) {
              counts[tagId] = (counts[tagId] ?? 0) + 1;
              countedIds.add(tagId);
            }
          }
        }
        // 兼容旧库快照时按视频实际拥有的标签名反查候选，避免每个视频再次遍历整组标签。
        final legacyNames = <String>{
          for (final tag in item.tags) tag.trim().toLowerCase(),
          for (final children in item.childTags.values)
            for (final tag in children) tag.trim().toLowerCase(),
        };
        for (final name in legacyNames) {
          for (final tagId in candidateIdsByName[name] ?? const <String>{}) {
            if (countedIds.add(tagId)) {
              counts[tagId] = (counts[tagId] ?? 0) + 1;
            }
          }
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
      folderRoots: query.folderRoots,
      sortRule: query.sortRule,
      excludedItems: query.excludedItems,
      favoriteOnly: query.favoriteOnly,
      unplayedOnly: query.unplayedOnly,
      errorOnly: query.errorOnly,
    );
  }

  Map<String, int> selectedResultCounts(
      FilterQuery query, Iterable<TagItem> tags) {
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
          (children) =>
              children.any((value) => TagRules.sameTag(value, tag.name)),
        );
  }

  String _sortedStrings(Iterable<String> values) {
    return (values.toList()..sort()).join(',');
  }

  String _childTagSignature(Map<String, Set<String>> childTags) {
    final entries = childTags.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries
        .map((entry) => '${entry.key}:${_sortedStrings(entry.value)}')
        .join('/');
  }

  String get _tagContextSignature {
    final tagIds = tagContext.tagsById.keys.toList()..sort();
    final videoLinks = tagContext.videoTagIdsByPathKey.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final id in tagIds)
        '$id:${tagContext.tagsById[id]?.aliases.join(',') ?? ''}',
      for (final entry in videoLinks)
        '${entry.key}:${(entry.value.toList()..sort()).join(',')}',
    ].join(';');
  }
}
