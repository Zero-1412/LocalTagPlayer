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
 * [sortMode] 指定字段，[sortDirection] 指定方向。`recent` 保留旧偏好名，但 UI 展示为
 * Windows 风格的“日期”，优先使用文件修改时间；“添加时间”单独对应应用入库时间。
 */
@visibleForTesting
int compareLibraryVideosForSort(
  VideoItem a,
  VideoItem b, {
  required SortMode sortMode,
  required SortDirection sortDirection,
}) {
  if (sortMode == SortMode.size) {
    final value = _compareNullableFileSize(a.fileSize, b.fileSize);
    if (value != 0) {
      return sortDirection == SortDirection.descending ? -value : value;
    }
    return _compareVideoIdentity(a, b);
  }

  final int value;
  switch (sortMode) {
    case SortMode.name:
      value = _compareWindowsLikeText(a.title, b.title);
      break;
    case SortMode.recent:
      value = _sortDateMs(a).compareTo(_sortDateMs(b));
      break;
    case SortMode.type:
      final type = _compareWindowsLikeText(
        p.extension(a.path).toLowerCase(),
        p.extension(b.path).toLowerCase(),
      );
      value = type == 0 ? _compareWindowsLikeText(a.title, b.title) : type;
      break;
    case SortMode.size:
      value = 0;
      break;
    case SortMode.folder:
      final folder = _compareWindowsLikeText(a.folder, b.folder);
      value = folder == 0 ? _compareWindowsLikeText(a.title, b.title) : folder;
      break;
    case SortMode.added:
      value = a.addedAt.compareTo(b.addedAt);
      break;
  }
  if (value == 0) {
    return _compareVideoIdentity(a, b);
  }
  return sortDirection == SortDirection.descending ? -value : value;
}

/**
 * Windows 资源管理器常用的“日期”更接近文件修改时间。
 *
 * 旧库或手工构造测试项可能没有 `modifiedMs`，此时回退到应用入库时间，保证排序稳定可用。
 */
int _sortDateMs(VideoItem item) {
  return item.modifiedMs ?? item.addedAt.millisecondsSinceEpoch;
}

/**
 * 比较文件大小，并把未知大小稳定放在列表末尾。
 */
int _compareNullableFileSize(int? a, int? b) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return 1;
  }
  if (b == null) {
    return -1;
  }
  return a.compareTo(b);
}

/**
 * 对文件名、目录和扩展名做接近 Windows 的大小写不敏感自然排序。
 *
 * 这样 `video2` 会排在 `video10` 前面，比单纯字符串比较更符合文件管理器习惯。
 */
int _compareWindowsLikeText(String a, String b) {
  final left = _naturalSortTokens(a);
  final right = _naturalSortTokens(b);
  final length = math.min(left.length, right.length);
  for (var index = 0; index < length; index += 1) {
    final l = left[index];
    final r = right[index];
    final lNumber = int.tryParse(l);
    final rNumber = int.tryParse(r);
    final int result;
    if (lNumber != null && rNumber != null) {
      result = lNumber.compareTo(rNumber);
    } else {
      result = l.toLowerCase().compareTo(r.toLowerCase());
    }
    if (result != 0) {
      return result;
    }
  }
  return left.length.compareTo(right.length);
}

/**
 * 将文本拆成数字和非数字片段，供自然排序比较器复用。
 */
List<String> _naturalSortTokens(String value) {
  return RegExp(r'\d+|\D+')
      .allMatches(value)
      .map((match) => match.group(0) ?? '')
      .where((token) => token.isNotEmpty)
      .toList();
}

/**
 * 字段值完全相同时使用标题和路径兜底，避免列表在刷新后出现不必要跳动。
 */
int _compareVideoIdentity(VideoItem a, VideoItem b) {
  final title = _compareWindowsLikeText(a.title, b.title);
  if (title != 0) {
    return title;
  }
  return TagRules.pathKey(a.path).compareTo(TagRules.pathKey(b.path));
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
