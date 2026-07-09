part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

class CacheSettingsPage extends StatefulWidget {
  const CacheSettingsPage({
    super.key,
    required this.store,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.onPlaybackSettingsChanged,
  });

  final LibraryStore store;

  final ThumbnailService thumbnailService;

  final PlaybackSettings playbackSettings;

  final Future<void> Function(PlaybackSettings settings)
      onPlaybackSettingsChanged;

  @override
  State<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

class _CacheSettingsPageState extends State<CacheSettingsPage> {
  late PlaybackSettings _settings = widget.playbackSettings;

  late Future<CacheStats> _statsFuture =
      widget.thumbnailService.statsFor(widget.store.videos.values);

  void _refreshStats() {
    setState(() {
      _statsFuture =
          widget.thumbnailService.statsFor(widget.store.videos.values);
    });
  }

  Future<void> _changeDecoder(String value) async {
    if (value == _settings.hwdec) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换播放解码'),
        content: Text(
          '将硬件解码从 ${PlaybackSettings.labelFor(_settings.hwdec)} 切换为 ${PlaybackSettings.labelFor(value)}。如果只是误触，请取消。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认切换'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      setState(() {});
      return;
    }
    final next = _settings.copyWith(hwdec: value);
    setState(() => _settings = next);
    await widget.onPlaybackSettingsChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _appBackground,
      appBar: AppBar(
        title: const Text('\u8bbe\u7f6e'),
        actions: [
          IconButton(
            tooltip: '\u5237\u65b0\u7f13\u5b58\u7edf\u8ba1',
            onPressed: _refreshStats,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '\u64ad\u653e\u89e3\u7801',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _settings.hwdec,
                    decoration: const InputDecoration(
                      labelText: '\u786c\u4ef6\u89e3\u7801',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final option in PlaybackSettings.decoderOptions)
                        DropdownMenuItem(
                          value: option,
                          child: Text(PlaybackSettings.labelFor(option)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _changeDecoder(value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: FutureBuilder<CacheStats>(
                future: _statsFuture,
                builder: (context, snapshot) {
                  final stats = snapshot.data;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '\u7f29\u7565\u56fe\u7f13\u5b58',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (stats == null)
                        const LinearProgressIndicator()
                      else ...[
                        _SettingsStatLine(
                          label: '\u603b\u6570',
                          value: _formatCount(stats.total),
                        ),
                        _SettingsStatLine(
                          label: '\u5df2\u7f13\u5b58',
                          value: _formatCount(stats.cached),
                        ),
                        _SettingsStatLine(
                          label: '\u7f3a\u5931',
                          value: _formatCount(stats.missing),
                        ),
                        _SettingsStatLine(
                          label: '\u9519\u8bef',
                          value: _formatCount(stats.errors),
                        ),
                        _SettingsStatLine(
                          label: '\u961f\u5217',
                          value:
                              '${stats.active}/${stats.queued}  avg ${stats.averageMs}ms',
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsStatLine extends StatelessWidget {
  const _SettingsStatLine({required this.label, required this.value});

  /**
   * 统计项名称。
   */
  final String label;

  /**
   * 统计项展示值。
   */
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _appTextMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: _appText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

/**
 * 媒体库主结果区当前展示的数据来源。
 *
 * 这里只控制页面展示列表，不改变底层标签筛选语义；播放时仍把当前可见结果作为播放队列传入播放器。
 */
enum _LibraryResultMode {
  /** 全量媒体库结果，受搜索、标签和收藏筛选影响。 */
  library,

  /** 最近播放结果，只展示有播放记录的视频。 */
  recent,

  /** 本地收藏结果，只展示用户收藏的视频。 */
  favorites,

  /** 本地媒体库路径浏览，按文件系统层级展示文件夹和视频。 */
  local,
}

/**
 * 本地媒体库浏览项。
 *
 * 文件夹用于进入下一层路径；视频项复用已入库的 VideoItem，以保持播放、收藏、缩略图和更多操作仍走现有媒体库闭环。
 */
class _LocalLibraryEntry {
  const _LocalLibraryEntry.folder(this.path) : video = null;

  _LocalLibraryEntry.video(VideoItem item)
      : path = item.path,
        video = item;

  /** 文件夹路径或视频文件路径。 */
  final String path;

  /** 视频项；为空时表示该条目是文件夹。 */
  final VideoItem? video;

  bool get isFolder => video == null;

  String get title => isFolder ? p.basename(path) : video!.title;
}

List<VideoItem> recentPlaybackClearTargets(
  Iterable<VideoItem> videos, {
  required Set<String> selectedPathKeys,
  required bool selectedOnly,
}) {
  return videos.where((item) {
    if (item.lastPlayedAt == null) {
      return false;
    }
    return !selectedOnly ||
        selectedPathKeys.contains(TagRules.pathKey(item.path));
  }).toList();
}

class _LibraryPageState extends State<LibraryPage> {
  LibraryStore? _store;
  ThumbnailService? _thumbnailService;
  PlaybackSettings _playbackSettings = PlaybackSettings.defaults;
  final _filterStateSource = FilterStateSource();
  final _searchController = TextEditingController();
  final _selectedTags = <String>{};
  final _selectedChildTags = <String>{};
  final _selectedGroupTagIds = <String, Set<String>>{};
  final _excludedTagIds = <String>{};
  FilterState? _filterState;

  Map<String, int> _visibleResultCounts = const <String, int>{};

  /**
   * 右侧标签发现面板使用的全库稳定计数。
   *
   * 当前筛选会改变视频结果，但标签面板中的其它标签数量不能因为当前筛选被压缩到 0，
   * 否则用户无法判断原始标签规模。
   */
  Map<String, int> _stableTagCounts = const <String, int>{};

  var _filterRevision = 0;
  var _playbackDataRevision = 0;
  var _suppressSearchControllerChange = false;
  var _searchControllerChangeQueued = false;
  var _lastObservedSearchText = '';

  var _isRefreshingVideos = false;

  var _isRefreshingCounts = false;

  var _libraryDataRevision = 0;
  var _showFavoritesOnly = false;
  var _isScanning = false;
  var _sortMode = SortMode.recent;
  var _sortDirection = SortDirection.descending;
  var _denseResultGrid = false;
  var _isTagDiscoveryPanelOpen = true;
  var _resultMode = _LibraryResultMode.library;
  Object? _recentVideoCacheKey;
  Object? _favoriteVideoCacheKey;
  Object? _localEntryCacheKey;
  Object? _tagGroupsCacheKey;
  List<VideoItem> _recentVideoCache = const <VideoItem>[];
  List<VideoItem> _favoriteVideoCache = const <VideoItem>[];
  List<_LocalLibraryEntry> _localEntryCache = const <_LocalLibraryEntry>[];
  final _localEntryCacheByKey = <Object, List<_LocalLibraryEntry>>{};
  List<TagGroup> _tagGroupsCache = const <TagGroup>[];

  /**
   * 最近播放清理时的临时选择集。
   *
   * 只保存 pathKey，不新增数据库字段；确认删除时把对应视频的 lastPlayedAt 清空。
   */
  final _selectedRecentPathKeys = <String>{};

  /**
   * 本地媒体库当前浏览路径。
   *
   * 该路径来自已配置 root 或其子目录，只用于文件系统式浏览，不改变扫描和标签规则。
   */
  String? _localLibraryPath;

  /**
   * 本地媒体库文件夹浏览返回栈。
   *
   * 从侧栏 root 入口进入时清空；从文件夹项进入时记录上一级路径，让返回按钮和鼠标侧键能回到上一层。
   */
  final _localLibraryBackStack = <String>[];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchControllerChanged);
    _load();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchControllerChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchControllerChanged() {
    if (_suppressSearchControllerChange) {
      return;
    }
    final keyword = _searchController.text;
    if (keyword == _lastObservedSearchText || _searchControllerChangeQueued) {
      return;
    }
    _lastObservedSearchText = keyword;
    _searchControllerChangeQueued = true;
    scheduleMicrotask(() {
      _searchControllerChangeQueued = false;
      if (!mounted || _searchController.text != _lastObservedSearchText) {
        return;
      }
      _mutateFilters(() {});
    });
  }

  void _setSearchTextSilently(String value) {
    if (_searchController.text == value) {
      _lastObservedSearchText = value;
      return;
    }
    _suppressSearchControllerChange = true;
    _searchController.text = value;
    _lastObservedSearchText = value;
    _suppressSearchControllerChange = false;
  }

  void _clearSearchSilently() => _setSearchTextSilently('');

  Future<void> _load() async {
    final store = await LibraryStore.load();
    final thumbnailService = await ThumbnailService.create();
    final playbackSettings = await PlaybackSettings.load();
    final sortPreferences = await LibrarySortPreferences.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _sortMode = sortPreferences.mode;
      _sortDirection = sortPreferences.direction;
      _store = store;
      _thumbnailService = thumbnailService;
      _playbackSettings = playbackSettings;
      _lastObservedSearchText = _searchController.text;
      _filterState = _buildImmediateFilterState(store);
      _visibleResultCounts = _fallbackResultCounts(store);
      _stableTagCounts = store.resultCounts(const FilterQuery());
    });
    _scheduleFilterRefresh();
    unawaited(_promptForNewVideos(store));
  }

  Future<void> _promptForNewVideos(LibraryStore store) async {
    if (store.roots.isEmpty) {
      return;
    }
    final count = await store.countUntrackedVideos();
    if (!mounted || count == 0 || _store != store) {
      return;
    }
    final shouldScan = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('\u53d1\u73b0\u65b0\u589e\u89c6\u9891'),
        content: Text(
            '\u5f53\u524d\u76ee\u5f55\u53d1\u73b0 $count \u4e2a\u672a\u5165\u5e93\u89c6\u9891\uff0c\u662f\u5426\u73b0\u5728\u91cd\u65b0\u626b\u63cf\uff1f'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('\u7a0d\u540e'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('\u91cd\u65b0\u626b\u63cf'),
          ),
        ],
      ),
    );
    if (shouldScan == true && mounted && _store == store) {
      await _rescan();
    }
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '\u9009\u62e9\u89c6\u9891\u76ee\u5f55',
    );
    if (path == null || _store == null) {
      return;
    }
    await _scan(() => _store!.addRootAndScan(path));
  }

  Future<void> _rescan() async {
    if (_store == null) {
      return;
    }
    await _scan(_store!.scan);
  }

  Future<void> _scan(Future<int> Function() action) async {
    if (_isScanning) {
      return;
    }
    setState(() => _isScanning = true);
    try {
      final added = await action();
      if (!mounted) {
        return;
      }
      _thumbnailService
          ?.prefetchAll(_store?.videos.values ?? const <VideoItem>[]);
      _markLibraryDataChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '\u626b\u63cf\u5b8c\u6210\uff0c\u65b0\u589e $added \u4e2a\u89c6\u9891')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\u626b\u63cf\u5931\u8d25\uff1a$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  FilterState _computeFilterState(LibraryStore store, FilterQuery query) {
    _filterStateSource.configure(
      engine: TagQueryService(
        videos: store.videos.values,
        tagContext: store.tagQueryContext,
      ),
      totalCount: store.videos.length,
      sourceKey: _libraryDataRevision,
      sortKey: (_sortMode, _sortDirection),
      compare: _compareVideos,
      sortVideos: (videos) => sortedLibraryVideos(
        videos,
        sortMode: _sortMode,
        sortDirection: _sortDirection,
      ),
    );
    return _filterStateSource.update(query);
  }

  FilterState _buildImmediateFilterState(LibraryStore store) {
    return FilterState(
      query: _currentFilterQuery(),
      filteredVideos: sortedLibraryVideos(
        store.videos.values,
        sortMode: _sortMode,
        sortDirection: _sortDirection,
      ),
      resultCount: store.videos.length,
      totalCount: store.videos.length,
    );
  }

  Map<String, int> _fallbackResultCounts(LibraryStore store) {
    return {
      for (final tag in store.allTagItems) tag.id: tag.usageCount,
    };
  }

  /**
   * 构建本地媒体库当前路径的直接子项。
   *
   * 文件夹从磁盘目录读取；视频只取已入库项目，确保播放、缩略图、收藏和更多操作继续复用现有 VideoItem 管线。
   */
  List<_LocalLibraryEntry> _localLibraryEntries(LibraryStore store) {
    final currentPath = _localLibraryPath;
    if (currentPath == null || currentPath.isEmpty) {
      return const <_LocalLibraryEntry>[];
    }
    final directory = Directory(currentPath);
    if (!directory.existsSync()) {
      return const <_LocalLibraryEntry>[];
    }
    final folders = <_LocalLibraryEntry>[];
    final videos = <VideoItem>[];
    final children = directory.listSync(followLinks: false);
    children.sort((a, b) {
      final aIsDirectory = a is Directory;
      final bIsDirectory = b is Directory;
      if (aIsDirectory != bIsDirectory) {
        return aIsDirectory ? -1 : 1;
      }
      return p.basename(a.path).compareTo(p.basename(b.path));
    });
    for (final child in children) {
      if (child is Directory) {
        folders.add(_LocalLibraryEntry.folder(child.path));
        continue;
      }
      if (child is File && TagRules.isVideoPath(child.path)) {
        final video = store.videos[TagRules.pathKey(child.path)];
        if (video != null) {
          videos.add(video);
        }
      }
    }
    return [
      ...folders,
      for (final video in sortedLibraryVideos(
        videos,
        sortMode: _sortMode,
        sortDirection: _sortDirection,
      ))
        _LocalLibraryEntry.video(video),
    ];
  }

  void _mutateFilters(VoidCallback mutation) {
    setState(() {
      _resultMode = _LibraryResultMode.library;
      mutation();
    });
    _scheduleFilterRefresh(refreshCounts: true);
  }

  /**
   * 应用排序字段或方向变更。
   *
   * 排序只改变当前结果的展示顺序，不改变筛选条件、标签数量或收藏状态；
   * 这里直接重排内存中的 `FilterState`，避免切换排序时触发完整过滤和 resultCounts 统计。
   */
  void _applySortChange({
    SortMode? sortMode,
    SortDirection? sortDirection,
  }) {
    late final LibrarySortPreferences preferences;
    setState(() {
      _sortMode = sortMode ?? _sortMode;
      _sortDirection = sortDirection ?? _sortDirection;
      preferences = LibrarySortPreferences(
        mode: _sortMode,
        direction: _sortDirection,
      );
      if (_resultMode != _LibraryResultMode.library || _filterState == null) {
        return;
      }
      final currentState = _filterState!;
      _filterState = FilterState(
        query: currentState.query,
        filteredVideos: sortedLibraryVideos(
          currentState.filteredVideos,
          sortMode: _sortMode,
          sortDirection: _sortDirection,
        ),
        resultCount: currentState.resultCount,
        totalCount: currentState.totalCount,
      );
    });
    unawaited(preferences.save());
  }

  /**
   * 回到媒体库全量视图。
   *
   * 侧栏“媒体库”应像重置入口：清空搜索、一级/二级/分组/排除/收藏筛选，并展示全量视频，
   * 避免用户从最近播放或某个标签视图返回时仍被旧条件限制。
   */
  void _showAllLibraryVideos() {
    final store = _store;
    setState(() {
      _resultMode = _LibraryResultMode.library;
      _localLibraryPath = null;
      _localLibraryBackStack.clear();
      _selectedRecentPathKeys.clear();
      _clearSearchSilently();
      _selectedTags.clear();
      _selectedChildTags.clear();
      _selectedGroupTagIds.clear();
      _excludedTagIds.clear();
      _showFavoritesOnly = false;
      if (store != null) {
        _filterState = _buildImmediateFilterState(store);
      }
    });
  }

  /**
   * 切换到最近播放结果视图。
   *
   * 最近播放是主结果区的一种数据源，不再用弹窗承载；切换时清空筛选条件，让用户看到的列表只由播放记录决定。
   */
  void _showRecentPlaybackVideos() {
    setState(() {
      _resultMode = _LibraryResultMode.recent;
      _localLibraryPath = null;
      _localLibraryBackStack.clear();
      _selectedRecentPathKeys.clear();
      _clearSearchSilently();
      _selectedTags.clear();
      _selectedChildTags.clear();
      _selectedGroupTagIds.clear();
      _excludedTagIds.clear();
      _showFavoritesOnly = false;
    });
  }

  /**
   * 切换到收藏结果视图。
   *
   * 该入口直接从当前内存视频集合筛选收藏项，同时保留 favoriteOnly 状态；
   * 后续再点击右侧标签时会切回普通媒体库筛选，但收藏条件仍会作为 AND 条件叠加。
   */
  void _showFavoriteVideos() {
    setState(() {
      _resultMode = _LibraryResultMode.favorites;
      _localLibraryPath = null;
      _localLibraryBackStack.clear();
      _selectedRecentPathKeys.clear();
      _clearSearchSilently();
      _selectedTags.clear();
      _selectedChildTags.clear();
      _selectedGroupTagIds.clear();
      _excludedTagIds.clear();
      _showFavoritesOnly = true;
    });
  }

  /**
   * 打开本地媒体库路径。
   *
   * 只切换当前浏览路径和结果模式；实际文件扫描仍由添加目录/重新扫描负责。
   */
  void _showLocalLibraryPath(String rootPath) {
    setState(() {
      _resultMode = _LibraryResultMode.local;
      _localLibraryPath = TagRules.normalizeRootPath(rootPath);
      _localLibraryBackStack.clear();
      _selectedRecentPathKeys.clear();
      _clearSearchSilently();
      _selectedTags.clear();
      _selectedChildTags.clear();
      _selectedGroupTagIds.clear();
      _excludedTagIds.clear();
      _showFavoritesOnly = false;
    });
  }

  /**
   * 从当前本地媒体库路径进入子文件夹。
   *
   * 该操作只改变 UI 浏览路径，不触发扫描，也不改变 root 配置或视频索引。
   */
  void _openLocalLibraryFolder(String folderPath) {
    final currentPath = _localLibraryPath;
    setState(() {
      if (currentPath != null && currentPath.isNotEmpty) {
        _localLibraryBackStack.add(currentPath);
      }
      _resultMode = _LibraryResultMode.local;
      _localLibraryPath = TagRules.normalizeRootPath(folderPath);
    });
  }

  /**
   * 回到本地媒体库上一个浏览路径。
   *
   * 返回按钮和鼠标侧键共用该方法，保证两种入口的历史栈行为一致。
   */
  void _goBackLocalLibraryPath() {
    if (_localLibraryBackStack.isEmpty) {
      return;
    }
    setState(() {
      _resultMode = _LibraryResultMode.local;
      _localLibraryPath = _localLibraryBackStack.removeLast();
    });
  }

  /**
   * 从侧栏本地媒体库列表移除 root。
   *
   * 与目录管理保持同一安全语义：只更新配置，不删除磁盘文件，也不清除已索引视频。
   */
  Future<void> _removeLocalLibraryRoot(String root) async {
    final store = _store;
    if (store == null) {
      return;
    }
    final confirmed = await _confirmRemoveRoot(root);
    if (confirmed != true || !mounted) {
      return;
    }
    await store.removeRoot(root);
    if (!mounted) {
      return;
    }
    setState(() {
      if (_localLibraryPath != null &&
          TagRules.pathKey(_localLibraryPath!) == TagRules.pathKey(root)) {
        _resultMode = _LibraryResultMode.library;
        _localLibraryPath = null;
        _localLibraryBackStack.clear();
      }
      _stableTagCounts = store.resultCounts(const FilterQuery());
    });
    _scheduleFilterRefresh(refreshCounts: true);
  }

  /**
   * 清理最近播放记录。
   *
   * 该动作只清空 lastPlayedAt，不删除视频、收藏、标签或播放进度数据。
   */
  Future<void> _clearRecentPlayback({required bool selectedOnly}) async {
    final store = _store;
    if (store == null) {
      return;
    }
    final targets = recentPlaybackClearTargets(
      store.videos.values,
      selectedPathKeys: _selectedRecentPathKeys,
      selectedOnly: selectedOnly,
    );
    for (final item in targets) {
      item.lastPlayedAt = null;
      await store.upsertVideo(item);
    }
    if (!mounted) {
      return;
    }
    setState(_selectedRecentPathKeys.clear);
    _markLibraryDataChanged();
  }

  /**
   * 清理单个最近播放记录。
   *
   * 单条删除不能依赖“先选中再批量删除”的状态刷新顺序，否则真实鼠标快速点击时会出现命中但未删除。
   */
  Future<void> _clearOneRecentPlayback(VideoItem item) async {
    final store = _store;
    if (store == null) {
      return;
    }
    item.lastPlayedAt = null;
    await store.upsertVideo(item);
    if (!mounted) {
      return;
    }
    setState(() => _selectedRecentPathKeys.remove(TagRules.pathKey(item.path)));
    _markLibraryDataChanged();
  }

  /**
   * 切换最近播放清理选择状态。
   */
  void _toggleRecentSelection(VideoItem item) {
    final key = TagRules.pathKey(item.path);
    setState(() {
      if (!_selectedRecentPathKeys.remove(key)) {
        _selectedRecentPathKeys.add(key);
      }
    });
  }

  void _markLibraryDataChanged() {
    _libraryDataRevision += 1;
    _invalidateDerivedCaches();
    final store = _store;
    if (store != null) {
      _stableTagCounts = store.resultCounts(const FilterQuery());
    }
    _scheduleFilterRefresh(refreshCounts: true);
  }

  void _invalidateDerivedCaches() {
    _tagGroupsCacheKey = null;
    _localEntryCacheKey = null;
    _localEntryCacheByKey.clear();
    _recentVideoCacheKey = null;
    _favoriteVideoCacheKey = null;
  }

  /**
   * 播放器返回后只更新播放时间相关的可见状态。
   *
   * `lastPlayedAt` 不会改变标签、收藏、路径或筛选命中集合；因此不能复用
   * `_markLibraryDataChanged` 的全库标签计数与完整筛选刷新路径，否则从播放器
   * 返回主界面会在大媒体库上产生明显卡顿。
   */
  void _markPlaybackTimestampChanged(VideoItem item) {
    _playbackDataRevision += 1;
    if (_resultMode == _LibraryResultMode.library) {
      // 主媒体库默认排序使用添加时间，播放时间更新不再改变当前结果顺序。
      return;
    }

    // 最近播放、本地收藏和本地路径浏览只依赖当前内存对象重建轻量列表。
    if (_resultMode == _LibraryResultMode.recent ||
        (_resultMode == _LibraryResultMode.favorites && item.isFavorite) ||
        _resultMode == _LibraryResultMode.local) {
      setState(() {});
    }
  }

  List<VideoItem> _sortedRecentVideos(LibraryStore store) {
    final key = (
      'recent',
      _libraryDataRevision,
      _playbackDataRevision,
      _sortMode,
      _sortDirection,
    );
    if (_recentVideoCacheKey == key) {
      return _recentVideoCache;
    }
    _recentVideoCacheKey = key;
    _recentVideoCache = sortedLibraryVideos(
      store.videos.values.where((item) => item.lastPlayedAt != null),
      sortMode: _sortMode,
      sortDirection: _sortDirection,
    );
    return _recentVideoCache;
  }

  List<VideoItem> _sortedFavoriteVideos(LibraryStore store) {
    final key = (
      'favorites',
      _libraryDataRevision,
      _sortMode,
      _sortDirection,
    );
    if (_favoriteVideoCacheKey == key) {
      return _favoriteVideoCache;
    }
    _favoriteVideoCacheKey = key;
    _favoriteVideoCache = sortedLibraryVideos(
      store.videos.values.where((item) => item.isFavorite),
      sortMode: _sortMode,
      sortDirection: _sortDirection,
    );
    return _favoriteVideoCache;
  }

  List<_LocalLibraryEntry> _cachedLocalLibraryEntries(LibraryStore store) {
    final key = (
      'local',
      _libraryDataRevision,
      _localLibraryPath,
      _sortMode,
      _sortDirection,
    );
    if (_localEntryCacheKey == key) {
      return _localEntryCache;
    }
    final cached = _localEntryCacheByKey[key];
    if (cached != null) {
      _localEntryCacheKey = key;
      _localEntryCache = cached;
      return cached;
    }
    _localEntryCacheKey = key;
    _localEntryCache = _localLibraryEntries(store);
    _localEntryCacheByKey[key] = _localEntryCache;
    while (_localEntryCacheByKey.length > 24) {
      _localEntryCacheByKey.remove(_localEntryCacheByKey.keys.first);
    }
    return _localEntryCache;
  }

  void _scheduleFilterRefresh({bool refreshCounts = false}) {
    final store = _store;
    if (store == null) {
      return;
    }
    final revision = ++_filterRevision;
    final query = _currentFilterQuery();
    Future<void>.delayed(Duration.zero, () {
      if (!mounted || revision != _filterRevision || _store != store) {
        return;
      }
      final nextState = _computeFilterState(store, query);
      if (!mounted || revision != _filterRevision || _store != store) {
        return;
      }
      setState(() {
        _filterState = nextState;
        _isRefreshingVideos = false;
      });
      _thumbnailService?.prefetchVisible(nextState.filteredVideos.take(36));
      if (!refreshCounts) {
        return;
      }
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted || revision != _filterRevision || _store != store) {
          return;
        }
        final nextCounts = store.resultCounts(query);
        if (!mounted || revision != _filterRevision || _store != store) {
          return;
        }
        setState(() {
          _visibleResultCounts = nextCounts;
          _isRefreshingCounts = false;
        });
      });
    });
  }

  FilterQuery _currentFilterQuery() {
    final store = _store;
    final parentTag = _activeChildParentTag;
    final selectedChildTag = _activeChildTagName;
    return FilterQuery(
      keyword: _searchController.text,
      primaryTagId: parentTag,
      childTagId: parentTag == null ? null : selectedChildTag,
      folderRoots: parentTag == null
          ? const <String>[]
          : store?.roots ?? const <String>[],
      selectedGroupTagIds: {
        for (final entry in _selectedGroupTagIds.entries)
          if (entry.value.isNotEmpty &&
              entry.key != 'folder.primary' &&
              entry.key != 'folder.child')
            entry.key: {...entry.value},
      },
      excludeTagIds: {..._excludedTagIds},
      favoriteOnly: _showFavoritesOnly,
    );
  }

  List<TagGroup> _tagGroupsForSidebar(LibraryStore store) {
    final cacheKey = (
      _libraryDataRevision,
      store.tagsById.length,
      _rootsSignature(store.roots),
    );
    if (_tagGroupsCacheKey == cacheKey) {
      return _tagGroupsCache;
    }
    final folderGroups = folderTagGroupsFromLibraryPaths(
      videos: store.videos.values,
      roots: store.roots,
      templates: store.tagGroups,
    );
    final folderGroupById = {for (final group in folderGroups) group.id: group};
    final itemsByGroup = <String, List<TagItem>>{};
    for (final tag in store.allTagItems.where((tag) => !tag.isHidden)) {
      final groupId = tag.groupId ?? 'manual';
      if (groupId == 'folder.primary' || groupId == 'folder.child') {
        continue;
      }
      (itemsByGroup[groupId] ??= <TagItem>[]).add(tag);
    }
    final groups = <TagGroup>[];
    final knownGroupIds = <String>{};
    for (final group in store.tagGroups) {
      knownGroupIds.add(group.id);
      final folderGroup = folderGroupById[group.id];
      if (folderGroup != null) {
        groups.add(folderGroup);
        continue;
      }
      final items = itemsByGroup[group.id] ?? const <TagItem>[];
      groups.add(_copyGroupWithItems(group, items));
    }
    for (final folderGroup in folderGroups) {
      if (!knownGroupIds.contains(folderGroup.id)) {
        groups.add(folderGroup);
        knownGroupIds.add(folderGroup.id);
      }
    }
    for (final entry in itemsByGroup.entries) {
      if (knownGroupIds.contains(entry.key)) {
        continue;
      }
      groups.add(
        TagGroup(
          id: entry.key,
          name: entry.key,
          displayName: entry.key,
          sortOrder: 999,
          items: _sortedTagItems(entry.value),
        ),
      );
    }
    groups.removeWhere((group) => group.items.isEmpty);
    groups.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) {
        return byOrder;
      }
      return _groupLabel(a).compareTo(_groupLabel(b));
    });
    _tagGroupsCacheKey = cacheKey;
    _tagGroupsCache = List<TagGroup>.unmodifiable(groups);
    return _tagGroupsCache;
  }

  String _rootsSignature(Iterable<String> roots) {
    final normalized = [
      for (final root in roots) TagRules.pathKey(root),
    ]..sort();
    return normalized.join('|');
  }

  TagGroup _copyGroupWithItems(TagGroup group, Iterable<TagItem> items) {
    return TagGroup(
      id: group.id,
      name: group.name,
      displayName: group.displayName,
      sortOrder: group.sortOrder,
      allowMultiSelect: group.allowMultiSelect,
      defaultLogic: group.defaultLogic,
      items: _sortedTagItems(items),
      excludedItems: group.excludedItems,
    );
  }

  List<TagItem> _sortedTagItems(Iterable<TagItem> items) {
    final sorted = items.toList();
    sorted.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) {
        return byOrder;
      }
      final byUsage = b.usageCount.compareTo(a.usageCount);
      if (byUsage != 0) {
        return byUsage;
      }
      return _tagLabel(a).compareTo(_tagLabel(b));
    });
    return sorted;
  }

  String _groupLabel(TagGroup group) => group.displayName ?? group.name;

  String _tagLabel(TagItem tag) => tag.displayName ?? tag.name;

  bool get _hasActiveFilters => !_currentFilterQuery().isEmpty;

  void _toggleGroupTag(TagItem tag) {
    final groupId = tag.groupId ?? 'manual';
    if (groupId == 'folder.child') {
      _toggleFolderChildTag(tag);
      return;
    }
    final selected = _selectedGroupTagIds[groupId] ?? <String>{};
    _mutateFilters(() {
      _removeEquivalentLegacySelection(tag);
      _excludedTagIds.remove(tag.id);
      if (selected.contains(tag.id)) {
        selected.remove(tag.id);
      } else {
        if (groupId == 'folder.primary' || groupId == 'folder.child') {
          selected.clear();
        }
        selected.add(tag.id);
      }
      if (groupId == 'folder.primary') {
        _selectedChildTags.clear();
        _selectedGroupTagIds.remove('folder.child');
      }
      if (selected.isEmpty) {
        _selectedGroupTagIds.remove(groupId);
      } else {
        _selectedGroupTagIds[groupId] = selected;
      }
    });
  }

  void _toggleFolderChildTag(TagItem child) {
    final store = _store;
    if (store == null) {
      return;
    }
    final primary = _folderPrimaryForChild(store, child);
    if (primary == null) {
      return;
    }
    _mutateFilters(() {
      _removeEquivalentLegacySelection(primary);
      _removeEquivalentLegacySelection(child);
      _excludedTagIds
        ..remove(primary.id)
        ..remove(child.id);
      _selectedTags.clear();
      _selectedChildTags.clear();
      _selectedGroupTagIds['folder.primary'] = <String>{primary.id};
      final selectedChildIds =
          _selectedGroupTagIds['folder.child'] ?? const <String>{};
      if (selectedChildIds.length == 1 && selectedChildIds.contains(child.id)) {
        _selectedGroupTagIds.remove('folder.child');
      } else {
        _selectedGroupTagIds['folder.child'] = <String>{child.id};
      }
    });
  }

  TagItem? _folderPrimaryForChild(LibraryStore store, TagItem child) {
    final parent = child.parentId?.trim();
    if (parent == null || parent.isEmpty) {
      return null;
    }
    for (final group in _tagGroupsForSidebar(store)) {
      if (group.id != 'folder.primary') {
        continue;
      }
      for (final primary in group.items) {
        if (primary.id == parent || TagRules.sameTag(primary.name, parent)) {
          return primary;
        }
      }
    }
    return null;
  }

  void _selectFolderPrimaryChild(TagItem primary, TagItem? child) {
    _mutateFilters(() {
      _removeEquivalentLegacySelection(primary);
      if (child != null) {
        _removeEquivalentLegacySelection(child);
      }
      _excludedTagIds
        ..remove(primary.id)
        ..remove(child?.id);
      _selectedTags.clear();
      _selectedChildTags.clear();
      _selectedGroupTagIds['folder.primary'] = <String>{primary.id};
      if (child == null) {
        _selectedGroupTagIds.remove('folder.child');
        return;
      }
      final selectedChildIds =
          _selectedGroupTagIds['folder.child'] ?? const <String>{};
      if (selectedChildIds.length == 1 && selectedChildIds.contains(child.id)) {
        _selectedGroupTagIds.remove('folder.child');
      } else {
        _selectedGroupTagIds['folder.child'] = <String>{child.id};
      }
    });
  }

  void _toggleExcludedTag(TagItem tag) {
    _mutateFilters(() {
      for (final selected in _selectedGroupTagIds.values) {
        selected.remove(tag.id);
      }
      _selectedGroupTagIds.removeWhere((_, selected) => selected.isEmpty);
      if (!_excludedTagIds.remove(tag.id)) {
        _excludedTagIds.add(tag.id);
      }
    });
  }

  void _removeGroupTag(TagItem tag) {
    final groupId = tag.groupId ?? 'manual';
    _mutateFilters(() {
      _selectedGroupTagIds[groupId]?.remove(tag.id);
      _selectedGroupTagIds.removeWhere((_, selected) => selected.isEmpty);
    });
  }

  void _removeExcludedTag(TagItem tag) {
    _mutateFilters(() => _excludedTagIds.remove(tag.id));
  }

  void _clearAllFilters() {
    _mutateFilters(() {
      _clearSearchSilently();
      _selectedTags.clear();
      _selectedChildTags.clear();
      _selectedGroupTagIds.clear();
      _excludedTagIds.clear();
      _showFavoritesOnly = false;
    });
  }

  void _removeEquivalentLegacySelection(TagItem tag) {
    if (tag.parentId == null) {
      _selectedTags
          .removeWhere((selected) => TagRules.sameTag(selected, tag.name));
      if (_selectedTags.isEmpty) {
        _selectedChildTags.clear();
      }
      return;
    }
    if (_selectedTags
        .any((selected) => TagRules.sameTag(selected, tag.parentId!))) {
      _selectedChildTags
          .removeWhere((selected) => TagRules.sameTag(selected, tag.name));
    }
  }

  void _removeEquivalentGroupSelection({
    required String tagName,
    String? parentTag,
  }) {
    final store = _store;
    if (store == null) {
      return;
    }
    final removedIds = <String>{};
    for (final tag in store.allTagItems) {
      if (!TagRules.sameTag(tag.name, tagName)) {
        continue;
      }
      if (parentTag == null) {
        if (tag.parentId != null) {
          continue;
        }
      } else if (tag.parentId == null ||
          !TagRules.sameTag(tag.parentId!, parentTag)) {
        continue;
      }
      removedIds.add(tag.id);
    }
    if (removedIds.isEmpty) {
      return;
    }
    for (final selected in _selectedGroupTagIds.values) {
      selected.removeAll(removedIds);
    }
    _selectedGroupTagIds.removeWhere((_, selected) => selected.isEmpty);
    _excludedTagIds.removeAll(removedIds);
  }

  // ignore: unused_element
  void _showSaveSmartListTodo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '\u4fdd\u5b58\u5f53\u524d\u7b5b\u9009 / Smart List \u5c06\u5728\u540e\u7eed\u9636\u6bb5\u63a5\u5165\u6301\u4e45\u5316\u3002',
        ),
      ),
    );
  }

  // ignore: unused_element
  void _showSmartListDraftDialog() {
    final store = _store;
    if (store == null) {
      return;
    }
    final filterState = _filterState ?? _buildImmediateFilterState(store);
    final querySummary = _filterSummary(
      store: store,
      resultCount: filterState.resultCount,
      totalCount: filterState.totalCount,
    );
    final queryExpression = _filterExpression(
      store: store,
      resultCount: filterState.resultCount,
      totalCount: filterState.totalCount,
    );
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _SmartListDraftDialog(
        suggestedName: querySummary,
        querySummary: querySummary,
        queryExpression: queryExpression,
        resultCount: filterState.resultCount,
        totalCount: filterState.totalCount,
        onConfirmDraft: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Smart List \u6301\u4e45\u5316\u5c06\u5728\u540e\u7eed\u63a5\u5165\u3002',
              ),
            ),
          );
        },
      ),
    );
  }

  List<TagItem> _selectedGroupTagItems(LibraryStore store) {
    final selectedIds =
        _selectedGroupTagIds.values.expand((ids) => ids).toSet();
    final folderTagsById = {
      for (final group in _tagGroupsForSidebar(store))
        for (final tag in group.items) tag.id: tag,
    };
    return [
      for (final id in selectedIds)
        if (folderTagsById[id] != null)
          folderTagsById[id]!
        else if (store.tagsById[id] != null)
          store.tagsById[id]!,
    ]..sort((a, b) => _tagLabel(a).compareTo(_tagLabel(b)));
  }

  List<TagItem> _excludedTagItems(LibraryStore store) {
    return [
      for (final id in _excludedTagIds)
        if (store.tagsById[id] != null) store.tagsById[id]!,
    ]..sort((a, b) => _tagLabel(a).compareTo(_tagLabel(b)));
  }

  void _toggleSingleSelection(Set<String> target, String tag) {
    final wasSelected = target.contains(tag);
    target.clear();
    if (!wasSelected) {
      target.add(tag);
    }
  }

  String? get _activeChildParentTag {
    if (_selectedTags.length == 1) {
      return _selectedTags.first;
    }
    final store = _store;
    final selectedFolderIds =
        _selectedGroupTagIds['folder.primary'] ?? const <String>{};
    if (store == null || selectedFolderIds.length != 1) {
      return null;
    }
    return _folderDiscoveryTagById(store, selectedFolderIds.first)?.name ??
        store.tagQueryContext.findTag(selectedFolderIds.first)?.name;
  }

  String? get _activeChildTagName {
    if (_selectedChildTags.length == 1) {
      return _selectedChildTags.first;
    }
    final store = _store;
    final selectedChildIds =
        _selectedGroupTagIds['folder.child'] ?? const <String>{};
    if (store == null || selectedChildIds.length != 1) {
      return null;
    }
    return _folderDiscoveryTagById(store, selectedChildIds.first)?.name ??
        store.tagQueryContext.findTag(selectedChildIds.first)?.name;
  }

  /**
   * 从真实路径派生的 folder 标签候选中按 id 查找标签。
   *
   * 该查找用于把 UI 选中态转换回 `primaryTagId/childTagId`，避免历史 SQLite tag id
   * 与当前文件树 root 不一致时影响筛选结果。
   */
  TagItem? _folderDiscoveryTagById(LibraryStore store, String tagId) {
    for (final group in _tagGroupsForSidebar(store)) {
      for (final tag in group.items) {
        if (tag.id == tagId) {
          return tag;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final thumbnailService = _thumbnailService;
    if (store == null || thumbnailService == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final filterState = _filterState ?? _buildImmediateFilterState(store);
    final filteredVideos = filterState.filteredVideos;
    final recentVideos = _sortedRecentVideos(store);
    final favoriteVideos = _sortedFavoriteVideos(store);
    final videos = switch (_resultMode) {
      _LibraryResultMode.recent => recentVideos,
      _LibraryResultMode.favorites => favoriteVideos,
      _LibraryResultMode.local => const <VideoItem>[],
      _LibraryResultMode.library => filteredVideos,
    };
    final localEntries = _resultMode == _LibraryResultMode.local
        ? _cachedLocalLibraryEntries(store)
        : const <_LocalLibraryEntry>[];
    final displayResultCount = switch (_resultMode) {
      _LibraryResultMode.recent => videos.length,
      _LibraryResultMode.favorites => videos.length,
      _LibraryResultMode.local => localEntries.length,
      _LibraryResultMode.library => filterState.resultCount,
    };
    final displayTotalCount = _resultMode == _LibraryResultMode.library
        ? filterState.totalCount
        : store.videos.length;
    final tags = store.allTags.toList()..sort();
    final tagGroups = _tagGroupsForSidebar(store);
    final resultCounts = _visibleResultCounts.isEmpty
        ? _fallbackResultCounts(store)
        : _visibleResultCounts;
    final pathDerivedTagCounts = {
      for (final group in tagGroups)
        if (group.id == 'folder.primary' || group.id == 'folder.child')
          for (final tag in group.items) tag.id: tag.usageCount,
    };
    final stableTagCounts = {
      ...(_stableTagCounts.isEmpty
          ? _fallbackResultCounts(store)
          : _stableTagCounts),
      ...pathDerivedTagCounts,
    };
    final selectedGroupTags = _selectedGroupTagItems(store);
    final excludedTags = _excludedTagItems(store);
    final filterExpression = _filterExpression(
      store: store,
      resultCount: filterState.resultCount,
      totalCount: filterState.totalCount,
    );
    final filterSummary = _filterSummary(
      store: store,
      resultCount: displayResultCount,
      totalCount: displayTotalCount,
    );
    final displaySummary = _displaySummary(
      filterSummary: filterSummary,
      displayResultCount: displayResultCount,
      displayTotalCount: displayTotalCount,
    );
    final displayExpression = _displayExpression(
      filterExpression: filterExpression,
    );
    final childParentTag = _activeChildParentTag;
    final childTags = childParentTag == null
        ? <String>[]
        : TagRules.sortedChildTags(store.childTagsFor(childParentTag))
            .where((tag) =>
                !TagRules.sameTag(tag, TagRules.defaultAlbumTag) &&
                !TagRules.sameTag(tag, childParentTag))
            .toList();
    final childTagItemsByParent = childTagItemsByParentId(
      tagGroups.expand((group) => group.items),
      store.tagQueryContext,
    );
    final favoriteCount =
        store.videos.values.where((item) => item.isFavorite).length;
    Widget buildSidebar({required bool dense, double? width}) {
      return _Sidebar(
        roots: store.roots,
        tags: tags,
        tagGroups: tagGroups,
        resultCounts: resultCounts,
        selectedLocalLibraryPath: _localLibraryPath,
        childParentTag: childParentTag,
        childTags: childTags,
        selectedChildTags: _selectedChildTags,
        selectedGroupTagIds: _selectedGroupTagIds,
        excludedTagIds: _excludedTagIds,
        favoriteCount: favoriteCount,
        favoriteVideosSelected:
            _resultMode == _LibraryResultMode.favorites || _showFavoritesOnly,
        recentPlaybackSelected: _resultMode == _LibraryResultMode.recent,
        localLibrarySelected: _resultMode == _LibraryResultMode.local,
        selectedTags: _selectedTags,
        isScanning: _isScanning,
        dense: dense,
        width: width,
        onPickFolder: _pickFolder,
        onShowAllLibrary: _showAllLibraryVideos,
        onRescan: _rescan,
        onRemoveLocalLibraryRoot: _removeLocalLibraryRoot,
        onFavoritesToggle: _showFavoriteVideos,
        onOpenRecentPlayback: _showRecentPlaybackVideos,
        onOpenLocalLibraryRoot: _showLocalLibraryPath,
        onOpenDirectoryManager: _openDirectoryManager,
        onOpenSettings: _openSettings,
        onChildTagToggle: (tag) {
          _mutateFilters(() {
            _removeEquivalentGroupSelection(
              tagName: tag,
              parentTag: _activeChildParentTag,
            );
            _toggleSingleSelection(_selectedChildTags, tag);
          });
        },
        onClearChildTags: () => _mutateFilters(_selectedChildTags.clear),
        onGroupTagToggle: _toggleGroupTag,
        onGroupTagExcludeToggle: _toggleExcludedTag,
      );
    }

    Widget buildFilterPanel({required bool dense, double? panelWidth}) {
      return _TagDiscoveryZone(
        tagGroups: tagGroups,
        resultCounts: stableTagCounts,
        favoriteTags: store.favoriteTags,
        selectedTags: _selectedTags,
        selectedChildTags: _selectedChildTags,
        selectedGroupTagIds: _selectedGroupTagIds,
        excludedTagIds: _excludedTagIds,
        childParentTag: childParentTag,
        childTags: childTags,
        childTagItemsByParent: childTagItemsByParent,
        favoriteCount: favoriteCount,
        showFavoritesOnly: _showFavoritesOnly,
        dense: dense,
        panelWidth: panelWidth,
        onFavoritesToggle: () =>
            _mutateFilters(() => _showFavoritesOnly = !_showFavoritesOnly),
        onTagToggle: (tag) {
          _mutateFilters(() {
            _removeEquivalentGroupSelection(tagName: tag);
            _toggleSingleSelection(_selectedTags, tag);
            _selectedChildTags.clear();
          });
        },
        onChildTagToggle: (tag) {
          _mutateFilters(() {
            _removeEquivalentGroupSelection(
              tagName: tag,
              parentTag: _activeChildParentTag,
            );
            _toggleSingleSelection(_selectedChildTags, tag);
          });
        },
        onGroupTagToggle: _toggleGroupTag,
        onFolderPrimaryChildSelected: _selectFolderPrimaryChild,
        onGroupTagExcludeToggle: _toggleExcludedTag,
        onCollapse: dense
            ? null
            : () => setState(() => _isTagDiscoveryPanelOpen = false),
      );
    }

    Widget buildMain(
      LayoutSize layoutSize, {
      Widget? topBar,
    }) {
      return Column(
        children: [
          if (topBar != null) topBar,
          _LibraryHeroArea(
            selectedTags: _selectedTags.toList()..sort(),
            selectedChildTags: _selectedChildTags.toList()..sort(),
            selectedGroupTags: selectedGroupTags,
            excludedTags: excludedTags,
            keyword: _searchController.text,
            defaultChipLabel: switch (_resultMode) {
              _LibraryResultMode.recent => '\u6700\u8fd1\u64ad\u653e',
              _LibraryResultMode.favorites => '\u672c\u5730\u6536\u85cf',
              _LibraryResultMode.local => '\u672c\u5730\u5a92\u4f53\u5e93',
              _LibraryResultMode.library => '\u5168\u90e8\u89c6\u9891',
            },
            querySummary: displaySummary,
            queryExpression: displayExpression,
            showFavoritesOnly: _showFavoritesOnly,
            resultCount: displayResultCount,
            totalCount: displayTotalCount,
            refreshing: _isRefreshingVideos || _isRefreshingCounts,
            onRemovePrimaryTag: (tag) => _mutateFilters(() {
              _selectedTags.remove(tag);
              _selectedChildTags.clear();
            }),
            onRemoveChildTag: (tag) =>
                _mutateFilters(() => _selectedChildTags.remove(tag)),
            onRemoveGroupTag: _removeGroupTag,
            onRemoveExcludedTag: _removeExcludedTag,
            onClearKeyword: () => _mutateFilters(_clearSearchSilently),
            onClearFavoritesOnly: () =>
                _mutateFilters(() => _showFavoritesOnly = false),
            onClearAll: _hasActiveFilters ? _clearAllFilters : null,
          ),
          Expanded(
            child: RepaintBoundary(
              child: switch (_resultMode) {
                _LibraryResultMode.local => _LocalLibraryView(
                    currentPath: _localLibraryPath,
                    entries: localEntries,
                    thumbnailService: thumbnailService,
                    playbackSettings: _playbackSettings,
                    dense: _denseResultGrid,
                    canGoBack: _localLibraryBackStack.isNotEmpty,
                    onBack: _goBackLocalLibraryPath,
                    onOpenFolder: _openLocalLibraryFolder,
                    onOpenVideo: _openVideo,
                    onEditTags: _editTags,
                    onToggleFavorite: _toggleFavorite,
                  ),
                _LibraryResultMode.recent => videos.isEmpty
                    ? _EmptyState(
                        hasLibrary: store.videos.isNotEmpty,
                        message:
                            '\u8fd8\u6ca1\u6709\u6700\u8fd1\u64ad\u653e\u8bb0\u5f55',
                      )
                    : _RecentPlaybackView(
                        videos: videos,
                        selectedPathKeys: _selectedRecentPathKeys,
                        thumbnailService: thumbnailService,
                        playbackSettings: _playbackSettings,
                        dense: _denseResultGrid,
                        onOpen: _openVideo,
                        onEditTags: _editTags,
                        onToggleFavorite: _toggleFavorite,
                        onToggleSelected: _toggleRecentSelection,
                        onSelectAll: () => setState(() {
                          _selectedRecentPathKeys
                            ..clear()
                            ..addAll(videos
                                .map((item) => TagRules.pathKey(item.path)));
                        }),
                        onClearSelection: () =>
                            setState(_selectedRecentPathKeys.clear),
                        onDeleteOne: _clearOneRecentPlayback,
                        onDeleteSelected: () =>
                            _clearRecentPlayback(selectedOnly: true),
                        onDeleteAll: () =>
                            _clearRecentPlayback(selectedOnly: false),
                      ),
                _ => videos.isEmpty
                    ? _EmptyState(
                        hasLibrary: store.videos.isNotEmpty,
                        message: _resultMode == _LibraryResultMode.favorites
                            ? '\u8fd8\u6ca1\u6709\u6536\u85cf\u89c6\u9891'
                            : null,
                      )
                    : _VideoGrid(
                        videos: videos,
                        thumbnailService: thumbnailService,
                        playbackSettings: _playbackSettings,
                        dense: _denseResultGrid,
                        onOpen: _openVideo,
                        onEditTags: _editTags,
                        onToggleFavorite: _toggleFavorite,
                      ),
              },
            ),
          ),
        ],
      );
    }

    Widget buildTopBar(LayoutSize layoutSize) {
      return _ReferenceTopBar(
        controller: _searchController,
        videoCount: displayResultCount,
        totalCount: displayTotalCount,
        keyword: _searchController.text,
        sortMode: _sortMode,
        sortDirection: _sortDirection,
        layoutSize: layoutSize,
        hasActiveFilters: _hasActiveFilters,
        onSearchChanged: (_) => _handleSearchControllerChanged(),
        onSortChanged: _setSortMode,
        onSortDirectionToggle: _toggleSortDirection,
        denseResultGrid: _denseResultGrid,
        onResultViewChanged: (dense) =>
            setState(() => _denseResultGrid = dense),
        onOpenTagManager: () => _openTagManager(videos),
        onOpenFilters: () {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: _appBackground,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            builder: (_) => FractionallySizedBox(
              heightFactor: 0.92,
              child: buildFilterPanel(dense: true),
            ),
          );
        },
      );
    }

    Widget buildExpandedContent(MainLibraryLayoutSlots layoutSlots) {
      return Column(
        children: [
          buildTopBar(LayoutSize.expanded),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: buildMain(
                    LayoutSize.expanded,
                  ),
                ),
                AnimatedSize(
                  duration: _motionDuration,
                  curve: _motionCurve,
                  alignment: Alignment.centerRight,
                  child: AnimatedSwitcher(
                    duration: _motionDuration,
                    switchInCurve: _motionCurve,
                    switchOutCurve: Curves.easeInCubic,
                    child: _isTagDiscoveryPanelOpen
                        ? buildFilterPanel(
                            dense: false,
                            panelWidth: layoutSlots.filterPanelWidth,
                          )
                        : _CollapsedTagDiscoveryRail(
                            onExpand: () => setState(
                              () => _isTagDiscoveryPanelOpen = true,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: _appBackground,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layoutSize = LayoutBreakpoints.fromWidth(constraints.maxWidth);
          final showMainSidebar = layoutSize != LayoutSize.compact;
          final expandedSlots =
              mainLibraryLayoutSlotsForWidth(constraints.maxWidth);
          return Row(
            children: [
              if (showMainSidebar)
                buildSidebar(
                  dense: layoutSize != LayoutSize.expanded,
                  width: layoutSize == LayoutSize.expanded
                      ? expandedSlots.sidebarWidth
                      : null,
                ),
              Expanded(
                child: layoutSize == LayoutSize.expanded
                    ? buildExpandedContent(expandedSlots)
                    : buildMain(
                        layoutSize,
                        topBar: buildTopBar(layoutSize),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openSettings() async {
    final store = _store;
    final thumbnailService = _thumbnailService;
    if (store == null || thumbnailService == null) {
      return;
    }
    await Navigator.of(context).push(
      _smoothRoute<void>(
        CacheSettingsPage(
          store: store,
          thumbnailService: thumbnailService,
          playbackSettings: _playbackSettings,
          onPlaybackSettingsChanged: (settings) async {
            await settings.save();
            if (mounted) {
              setState(() => _playbackSettings = settings);
            }
          },
        ),
      ),
    );
    if (mounted) {
      _markLibraryDataChanged();
    }
  }

  Future<void> _openTagManager(List<VideoItem> currentResults) async {
    final store = _store;
    if (store == null) {
      return;
    }
    await Navigator.of(context).push(
      _smoothRoute<void>(
        TagManagerPage(
          store: store,
          currentResults: List<VideoItem>.of(currentResults),
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _invalidateDerivedCaches();
        _stableTagCounts = store.resultCounts(const FilterQuery());
      });
      _scheduleFilterRefresh(refreshCounts: true);
    }
  }

  Future<void> _openDirectoryManager() async {
    final store = _store;
    if (store == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('\u76ee\u5f55\u7ba1\u7406'),
        content: SizedBox(
          width: 520,
          child: store.roots.isEmpty
              ? const Text(
                  '\u8fd8\u6ca1\u6709\u6dfb\u52a0\u89c6\u9891\u76ee\u5f55\u3002')
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: store.roots.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final root = store.roots[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(
                          root,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: '\u79fb\u9664\u76ee\u5f55',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () async {
                            final confirmed = await _confirmRemoveRoot(root);
                            if (confirmed != true) {
                              return;
                            }
                            await store.removeRoot(root);
                            if (!mounted || !dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop();
                            _markLibraryDataChanged();
                          },
                        ),
                      );
                    },
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('\u5173\u95ed'),
          ),
          OutlinedButton.icon(
            onPressed: _isScanning
                ? null
                : () {
                    Navigator.of(dialogContext).pop();
                    unawaited(_pickFolder());
                  },
            icon: const Icon(Icons.add_rounded),
            label: const Text('\u6dfb\u52a0\u76ee\u5f55'),
          ),
          FilledButton.icon(
            onPressed: _isScanning || store.roots.isEmpty
                ? null
                : () {
                    Navigator.of(dialogContext).pop();
                    unawaited(_rescan());
                  },
            icon: const Icon(Icons.sync_rounded),
            label: const Text('\u91cd\u65b0\u626b\u63cf'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmRemoveRoot(String root) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('\u79fb\u9664\u76ee\u5f55'),
        content: Text(
          '\u53ea\u4ece\u76ee\u5f55\u5217\u8868\u79fb\u9664\uff0c\u4e0d\u5220\u9664\u78c1\u76d8\u6587\u4ef6\uff0c\u4e5f\u4e0d\u4f1a\u7acb\u5373\u5220\u9664\u5df2\u5165\u5e93\u89c6\u9891\u8bb0\u5f55\u3002\n\n$root',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('\u53d6\u6d88'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('\u79fb\u9664'),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<void> _addLibraryTag() async {
    final controller = TextEditingController();
    final existingTags = _store?.allTagItems.toList() ?? const <TagItem>[];
    existingTags.sort((a, b) => _tagLabel(a).compareTo(_tagLabel(b)));
    final picked = await showDialog<String>(
      context: context,
      builder: (context) {
        var keyword = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            /**
             * 弹窗内搜索只影响候选展示，不改变真实标签数据。
             */
            final visibleTags = existingTags
                .where((tag) {
                  final label = _tagLabel(tag);
                  if (keyword.trim().isEmpty) {
                    return true;
                  }
                  final normalizedKeyword = keyword.toLowerCase();
                  return label.toLowerCase().contains(normalizedKeyword) ||
                      tag.name.toLowerCase().contains(normalizedKeyword);
                })
                .take(80)
                .toList();
            return AlertDialog(
              title: const Text(
                  '\u6dfb\u52a0\u5230\u6211\u7684\u6807\u7b7e\u5e93'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '\u641c\u7d22\u6216\u65b0\u5efa\u6807\u7b7e',
                        hintText:
                            '\u8f93\u5165\u6807\u7b7e\u540d\uff0c\u4e0b\u65b9\u4f1a\u5373\u65f6\u8fc7\u6ee4',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) =>
                          setDialogState(() => keyword = value),
                      onSubmitted: (value) =>
                          Navigator.of(context).pop(value.trim()),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: visibleTags.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Text(
                                    '\u6ca1\u6709\u5339\u914d\u7684\u5df2\u6709\u6807\u7b7e'),
                              ),
                            )
                          : ScrollConfiguration(
                              behavior: const _DesktopDragScrollBehavior(),
                              child: SingleChildScrollView(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final tag in visibleTags)
                                      ActionChip(
                                        label: Text(_tagLabel(tag)),
                                        onPressed: () => Navigator.of(context)
                                            .pop(_tagLabel(tag)),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('\u53d6\u6d88'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(controller.text.trim()),
                  child: const Text('\u6dfb\u52a0'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    final tag = picked == null ? null : TagRules.normalizeTag(picked);
    if (tag == null || tag.isEmpty || _store == null) {
      return;
    }
    try {
      if (!_store!.allTagItems.any(
        (existing) =>
            (existing.groupId ?? 'manual') == 'manual' &&
            TagRules.sameTag(existing.name, tag),
      )) {
        await _store!.createManualTag(name: tag, groupId: 'manual');
      }
      if (!_store!.favoriteTags
          .any((existing) => TagRules.sameTag(existing, tag))) {
        setState(() {
          _invalidateDerivedCaches();
          _store!.favoriteTags.add(tag);
          _stableTagCounts = _store!.resultCounts(const FilterQuery());
        });
        await _store!.saveMetadata();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('\u6dfb\u52a0\u6807\u7b7e\u5931\u8d25\uff1a$error')),
      );
    }
  }

  // ignore: unused_element
  Future<void> _removeLibraryTag(String tag) async {
    final store = _store;
    if (store == null) {
      return;
    }
    _mutateFilters(() {
      _invalidateDerivedCaches();
      store.favoriteTags.remove(tag);
      _selectedTags.remove(tag);
      _selectedChildTags.clear();
      _stableTagCounts = store.resultCounts(const FilterQuery());
    });
    await store.saveMetadata();
  }

  Future<void> _openVideo(VideoItem item, List<VideoItem> playlist) async {
    final store = _store;
    if (store == null) {
      return;
    }
    final thumbnailService = _thumbnailService!;
    final activeChildTag =
        _selectedChildTags.isEmpty ? null : _selectedChildTags.first;
    final queueTitle = _queueTitle(
      store: store,
      playlistLength: playlist.length,
    );
    final wasPaused = thumbnailService.isPaused;
    thumbnailService.pause();
    try {
      await Navigator.of(context).push(
        _smoothRoute<void>(
          PlayerPage(
            initialItem: item,
            playlist: List<VideoItem>.of(playlist),
            thumbnailService: thumbnailService,
            playbackSettings: _playbackSettings,
            activeTags: _selectedTags.toList()..sort(),
            activeChildTag: activeChildTag,
            queueTitle: queueTitle,
            onDeleteFile: _deleteVideoFile,
            onToggleFavorite: _toggleFavorite,
            onMediaDetailsUpdated: _updateMediaDetails,
          ),
        ),
      );
    } finally {
      if (!wasPaused) {
        thumbnailService.resume();
      }
    }
    item.lastPlayedAt = DateTime.now();
    await _store?.upsertVideo(item);
    if (mounted) {
      _markPlaybackTimestampChanged(item);
    }
  }

  Future<void> _toggleFavorite(VideoItem item) async {
    setState(() => item.isFavorite = !item.isFavorite);
    await _store?.upsertVideo(item);
    if (mounted) {
      _markLibraryDataChanged();
    }
  }

  Future<void> _updateMediaDetails(
    VideoItem item,
    MediaDetails details,
    String? fingerprint,
  ) async {
    item.mediaDetails = details;
    item.mediaFingerprint = fingerprint ?? item.mediaFingerprint;
    await _store?.upsertVideo(item);
    if (mounted) {
      _markLibraryDataChanged();
    }
  }

  Future<void> _deleteVideoFile(VideoItem item) async {
    final file = File(item.path);
    if (await file.exists()) {
      await file.delete();
    }
    _store?.videos.remove(TagRules.pathKey(item.path));
    await _store?.deleteVideo(item.path);
    if (mounted) {
      _markLibraryDataChanged();
    }
  }

  Future<void> _editTags(VideoItem item) async {
    final childParentTag = _activeChildParentTag;
    final editingChildTags = childParentTag != null;
    final updated = await showDialog<Set<String>>(
      context: context,
      builder: (_) => TagEditorDialog(
        title:
            editingChildTags ? '${item.title} / $childParentTag' : item.title,
        initialTags: editingChildTags
            ? (item.childTags[childParentTag] ?? const <String>{})
            : item.tags,
        existingTags: editingChildTags
            ? (_store?.childTagsFor(childParentTag) ?? const {})
            : (_store?.allTags ?? const {}),
      ),
    );
    if (updated == null) {
      return;
    }
    setState(() {
      final normalized = _normalizeTagSet(updated);
      if (editingChildTags) {
        item.childTags[childParentTag] = {
          ..._folderChildTagsForItem(item, childParentTag),
          ...normalized,
        };
      } else {
        item.tags
          ..clear()
          ..addAll({
            ..._folderTagsForItem(item),
            ...normalized,
          });
      }
    });
    await _store?.replaceManualTags(item,
        parentTag: editingChildTags ? childParentTag : null);
    if (mounted) {
      _markLibraryDataChanged();
    }
  }

  Set<String> _folderTagsForItem(VideoItem item) {
    final rootPath = item.rootPath;
    if (rootPath == null || rootPath.isEmpty) {
      return const <String>{};
    }
    return TagRules.parentTagsFor(rootPath, item.path);
  }

  Set<String> _folderChildTagsForItem(VideoItem item, String parentTag) {
    final rootPath = item.rootPath;
    if (rootPath == null || rootPath.isEmpty) {
      return const <String>{};
    }
    return TagRules.childTagsFor(rootPath, item.path)[parentTag] ??
        const <String>{};
  }

  Set<String> _normalizeTagSet(Iterable<String> tags) {
    final seen = <String>{};
    final normalized = <String>{};
    for (final raw in tags) {
      final tag = TagRules.normalizeTag(raw);
      if (tag.isEmpty) {
        continue;
      }
      if (seen.add(tag.toLowerCase())) {
        normalized.add(tag);
      }
    }
    return normalized;
  }
}
