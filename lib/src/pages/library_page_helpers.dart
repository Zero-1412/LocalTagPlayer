part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * LibraryPage 的派生显示和排序逻辑。
 *
 * 这里不持有状态、不触发数据库访问，只读取 `_LibraryPageState` 已有状态生成摘要、排序和队列标题，
 * 让页面主体专注生命周期、交互入口和布局组装。
 */
extension _LibraryPageDerivedState on _LibraryPageState {
  /**
   * 构建用于诊断和播放器队列标题的完整筛选表达式。
   */
  String _filterExpression({
    required LibraryStore store,
    required int resultCount,
    required int totalCount,
  }) {
    final parts = <String>[];
    final keyword = _searchController.text.trim();
    if (keyword.isNotEmpty) {
      parts.add('keyword:"$keyword"');
    }
    final primaryTags = _selectedTags.toList()..sort();
    parts.addAll(primaryTags.map((tag) => 'legacy:$tag'));
    final childTags = _selectedChildTags.toList()..sort();
    if (childTags.isNotEmpty) {
      parts.add('child:(${childTags.join('|')})');
    }
    final groupsById = {
      for (final group in _tagGroupsForSidebar(store)) group.id: group
    };
    final selectedEntries = _selectedGroupTagIds.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in selectedEntries) {
      final tagLabels = [
        for (final id in entry.value)
          if (store.tagsById[id] != null) _tagLabel(store.tagsById[id]!),
      ]..sort();
      if (tagLabels.isEmpty) {
        continue;
      }
      final group = groupsById[entry.key];
      parts.add(
        '${group == null ? entry.key : _groupLabel(group)}:(${tagLabels.join('|')})',
      );
    }
    parts.addAll(_excludedTagItems(store).map((tag) => '-${_tagLabel(tag)}'));
    if (_showFavoritesOnly) {
      parts.add('favorite');
    }
    final expression =
        parts.isEmpty ? '\u5168\u90e8\u89c6\u9891' : parts.join(' AND ');
    return '$expression  |  $resultCount / $totalCount';
  }

  /**
   * 构建面向用户的短筛选摘要。
   */
  String _filterSummary({
    required LibraryStore store,
    required int resultCount,
    required int totalCount,
  }) {
    final parts = <String>[];
    final keyword = _searchController.text.trim();
    if (keyword.isNotEmpty) {
      parts.add('"$keyword"');
    }
    final groupsById = {
      for (final group in _tagGroupsForSidebar(store)) group.id: group
    };
    final activeGroupLabels = [
      for (final entry in _selectedGroupTagIds.entries)
        if (entry.value.isNotEmpty)
          _groupLabel(groupsById[entry.key] ??
              TagGroup(id: entry.key, name: entry.key, items: const [])),
    ]..sort();
    if (activeGroupLabels.isNotEmpty) {
      parts.add(activeGroupLabels.join(' + '));
    }
    final excludedCount = _excludedTagIds.length;
    if (excludedCount > 0) {
      parts.add('NOT $excludedCount');
    }
    if (_showFavoritesOnly) {
      parts.add('favorite');
    }
    final label =
        parts.isEmpty ? '\u5168\u90e8\u89c6\u9891' : parts.join(' 路 ');
    return '$label  路  $resultCount / $totalCount';
  }

  /**
   * 当前排序控件对应的视频比较器。
   */
  int _compareVideos(VideoItem a, VideoItem b) {
    return compareLibraryVideosForSort(
      a,
      b,
      sortMode: _sortMode,
      sortDirection: _sortDirection,
    );
  }

  /**
   * 切换排序字段，并只重排当前结果。
   *
   * 排序不改变筛选命中集合和标签计数，因此不能复用完整筛选刷新路径；
   * 否则大媒体库会在每次切换字段时额外触发 resultCounts 重算。
   */
  void _setSortMode(SortMode mode) {
    _applySortChange(sortMode: mode);
  }

  /**
   * 切换排序方向，并只重排当前结果。
   */
  void _toggleSortDirection() {
    _applySortChange(
      sortDirection: _sortDirection == SortDirection.descending
          ? SortDirection.ascending
          : SortDirection.descending,
    );
  }

  /**
   * 当前结果来源对应的顶部摘要。
   */
  String _displaySummary({
    required String filterSummary,
    required int displayResultCount,
    required int displayTotalCount,
  }) {
    return switch (_resultMode) {
      _LibraryResultMode.recent =>
        '\u6700\u8fd1\u64ad\u653e  |  $displayResultCount / $displayTotalCount',
      _LibraryResultMode.favorites =>
        '\u672c\u5730\u6536\u85cf  |  $displayResultCount / $displayTotalCount',
      _LibraryResultMode.local =>
        '\u672c\u5730\u5a92\u4f53\u5e93  |  $displayResultCount \u9879',
      _LibraryResultMode.library => filterSummary,
    };
  }

  /**
   * 当前结果来源对应的详细表达式。
   */
  String _displayExpression({
    required String filterExpression,
  }) {
    return switch (_resultMode) {
      _LibraryResultMode.recent =>
        '\u6309\u6700\u8fd1\u64ad\u653e\u65f6\u95f4\u6392\u5e8f',
      _LibraryResultMode.favorites =>
        '\u4ec5\u663e\u793a\u672c\u5730\u6536\u85cf\u89c6\u9891',
      _LibraryResultMode.local =>
        _localLibraryPath ?? '\u672c\u5730\u5a92\u4f53\u5e93',
      _LibraryResultMode.library => filterExpression,
    };
  }

  /**
   * 播放器过滤队列标题。
   */
  String _queueTitle({
    required LibraryStore store,
    required int playlistLength,
  }) {
    return switch (_resultMode) {
      _LibraryResultMode.recent =>
        '\u6700\u8fd1\u64ad\u653e  |  $playlistLength / ${store.videos.length}',
      _LibraryResultMode.favorites =>
        '\u672c\u5730\u6536\u85cf  |  $playlistLength / ${store.videos.length}',
      _LibraryResultMode.local =>
        '${_localLibraryPath ?? '\u672c\u5730\u5a92\u4f53\u5e93'}  |  $playlistLength / ${store.videos.length}',
      _LibraryResultMode.library => _filterSummary(
          store: store,
          resultCount: playlistLength,
          totalCount: store.videos.length,
        ),
    };
  }
}

/**
 * 媒体库视频排序比较器。
 *
 * [sortMode] 指定字段，[sortDirection] 指定方向。添加时间只使用 `addedAt`，
 * 播放返回更新 `lastPlayedAt` 时不应改变主媒体库默认顺序。
 */
@visibleForTesting
int compareLibraryVideosForSort(
  VideoItem a,
  VideoItem b, {
  required SortMode sortMode,
  required SortDirection sortDirection,
}) {
  final int value;
  switch (sortMode) {
    case SortMode.recent:
      value = a.addedAt.compareTo(b.addedAt);
      break;
    case SortMode.name:
      value = a.title.compareTo(b.title);
      break;
    case SortMode.folder:
      final folder = a.folder.compareTo(b.folder);
      value = folder == 0 ? a.title.compareTo(b.title) : folder;
      break;
  }
  return sortDirection == SortDirection.descending ? -value : value;
}

/**
 * 按媒体库当前排序规则返回不可变视频列表。
 *
 * [videos] 可以来自全库、标签筛选结果、本地收藏或最近播放；统一入口能避免不同来源各自实现排序，
 * 导致“媒体库排序”和“标签筛选排序”表现不一致。
 */
@visibleForTesting
List<VideoItem> sortedLibraryVideos(
  Iterable<VideoItem> videos, {
  required SortMode sortMode,
  required SortDirection sortDirection,
}) {
  final sorted = videos.toList()
    ..sort((a, b) => compareLibraryVideosForSort(
          a,
          b,
          sortMode: sortMode,
          sortDirection: sortDirection,
        ));
  return List<VideoItem>.unmodifiable(sorted);
}
