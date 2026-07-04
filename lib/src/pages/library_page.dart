part of '../../main.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  LibraryStore? _store;
  ThumbnailService? _thumbnailService;
  PlaybackSettings _playbackSettings = PlaybackSettings.defaults;
  final _searchController = TextEditingController();
  final _selectedTags = <String>{};
  final _selectedChildTags = <String>{};
  final _selectedGroupTagIds = <String, Set<String>>{};
  final _excludedTagIds = <String>{};
  var _showFavoritesOnly = false;
  var _isScanning = false;
  var _sortMode = SortMode.recent;
  var _isFilterSidebarOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = await LibraryStore.load();
    final thumbnailService = await ThumbnailService.create();
    final playbackSettings = await PlaybackSettings.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _store = store;
      _thumbnailService = thumbnailService;
      _playbackSettings = playbackSettings;
    });
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

  List<VideoItem> _filteredVideos() {
    final store = _store;
    final thumbnailService = _thumbnailService;
    if (store == null || thumbnailService == null) {
      return const [];
    }

    final items = TagQueryService(
      videos: store.videos.values,
      tagContext: store.tagQueryContext,
    ).filter(_currentFilterQuery());

    _sortVideos(items);
    return items;
  }

  FilterQuery _currentFilterQuery() {
    final selectedTag = _selectedTags.isEmpty ? null : _selectedTags.first;
    final parentTag = _activeChildParentTag;
    final selectedChildTag =
        _selectedChildTags.isEmpty ? null : _selectedChildTags.first;
    return FilterQuery(
      keyword: _searchController.text,
      primaryTagId: selectedTag,
      childTagId: parentTag == null ? null : selectedChildTag,
      selectedGroupTagIds: {
        for (final entry in _selectedGroupTagIds.entries)
          if (entry.value.isNotEmpty) entry.key: {...entry.value},
      },
      excludeTagIds: {..._excludedTagIds},
      favoriteOnly: _showFavoritesOnly,
    );
  }

  List<TagGroup> _tagGroupsForSidebar(LibraryStore store) {
    final itemsByGroup = <String, List<TagItem>>{};
    for (final tag in store.allTagItems.where((tag) => !tag.isHidden)) {
      final groupId = tag.groupId ?? 'manual';
      (itemsByGroup[groupId] ??= <TagItem>[]).add(tag);
    }
    final groups = <TagGroup>[];
    final knownGroupIds = <String>{};
    for (final group in store.tagGroups) {
      knownGroupIds.add(group.id);
      final items = itemsByGroup[group.id] ?? const <TagItem>[];
      groups.add(_copyGroupWithItems(group, items));
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
    return groups;
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
    final selected = _selectedGroupTagIds[groupId] ?? <String>{};
    setState(() {
      _removeEquivalentLegacySelection(tag);
      _excludedTagIds.remove(tag.id);
      if (selected.contains(tag.id)) {
        selected.remove(tag.id);
      } else {
        selected.add(tag.id);
      }
      if (selected.isEmpty) {
        _selectedGroupTagIds.remove(groupId);
      } else {
        _selectedGroupTagIds[groupId] = selected;
      }
    });
  }

  void _toggleExcludedTag(TagItem tag) {
    setState(() {
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
    setState(() {
      _selectedGroupTagIds[groupId]?.remove(tag.id);
      _selectedGroupTagIds.removeWhere((_, selected) => selected.isEmpty);
    });
  }

  void _removeExcludedTag(TagItem tag) {
    setState(() => _excludedTagIds.remove(tag.id));
  }

  void _clearAllFilters() {
    setState(() {
      _searchController.clear();
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

  void _showSaveSmartListTodo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('保存当前筛选 / Smart List 将在后续阶段接入持久化。')),
    );
  }

  List<TagItem> _selectedGroupTagItems(LibraryStore store) {
    final selectedIds =
        _selectedGroupTagIds.values.expand((ids) => ids).toSet();
    return [
      for (final id in selectedIds)
        if (store.tagsById[id] != null) store.tagsById[id]!,
    ]..sort((a, b) => _tagLabel(a).compareTo(_tagLabel(b)));
  }

  List<TagItem> _excludedTagItems(LibraryStore store) {
    return [
      for (final id in _excludedTagIds)
        if (store.tagsById[id] != null) store.tagsById[id]!,
    ]..sort((a, b) => _tagLabel(a).compareTo(_tagLabel(b)));
  }

  String _currentQueueTitle() {
    final store = _store;
    final parts = <String>[];
    final keyword = _searchController.text.trim();
    if (keyword.isNotEmpty) {
      parts.add('搜索 "$keyword"');
    }
    final primaryTags = _selectedTags.toList()..sort();
    parts.addAll(primaryTags);
    final childTags = _selectedChildTags.toList()..sort();
    parts.addAll(childTags);
    if (store != null) {
      parts.addAll(_selectedGroupTagItems(store).map(_tagLabel));
      parts.addAll(_excludedTagItems(store).map((tag) => '-${_tagLabel(tag)}'));
    }
    if (_showFavoritesOnly) {
      parts.add('我的收藏');
    }
    return parts.isEmpty ? '当前列表' : parts.join(' / ');
  }

  void _sortVideos(List<VideoItem> items) {
    switch (_sortMode) {
      case SortMode.recent:
        items.sort((a, b) {
          final bTime = b.lastPlayedAt ?? b.addedAt;
          final aTime = a.lastPlayedAt ?? a.addedAt;
          return bTime.compareTo(aTime);
        });
      case SortMode.name:
        items.sort((a, b) => a.title.compareTo(b.title));
      case SortMode.folder:
        items.sort((a, b) {
          final folder = a.folder.compareTo(b.folder);
          return folder == 0 ? a.title.compareTo(b.title) : folder;
        });
    }
  }

  void _toggleSingleSelection(Set<String> target, String tag) {
    final wasSelected = target.contains(tag);
    target.clear();
    if (!wasSelected) {
      target.add(tag);
    }
  }

  String? get _activeChildParentTag {
    if (_selectedTags.length != 1) {
      return null;
    }
    return _selectedTags.first;
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final thumbnailService = _thumbnailService;
    if (store == null || thumbnailService == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final videos = _filteredVideos();
    final tags = store.allTags.toList()..sort();
    final filterQuery = _currentFilterQuery();
    final tagGroups = _tagGroupsForSidebar(store);
    final resultCounts = store.resultCounts(filterQuery);
    final selectedGroupTags = _selectedGroupTagItems(store);
    final excludedTags = _excludedTagItems(store);
    final childParentTag = _activeChildParentTag;
    final childTags = childParentTag == null
        ? <String>[]
        : TagRules.sortedChildTags(store.childTagsFor(childParentTag));
    final favoriteCount =
        store.videos.values.where((item) => item.isFavorite).length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _thumbnailService?.prefetchVisible(videos.take(36));
    });

    Widget buildSidebar({required bool dense}) {
      return _Sidebar(
        roots: store.roots,
        tags: tags,
        tagGroups: tagGroups,
        resultCounts: resultCounts,
        favoriteTags: store.favoriteTags,
        childParentTag: childParentTag,
        childTags: childTags,
        selectedChildTags: _selectedChildTags,
        selectedGroupTagIds: _selectedGroupTagIds,
        excludedTagIds: _excludedTagIds,
        favoriteCount: favoriteCount,
        showFavoritesOnly: _showFavoritesOnly,
        selectedTags: _selectedTags,
        isScanning: _isScanning,
        dense: dense,
        onPickFolder: _pickFolder,
        onRescan: _rescan,
        onAddFavoriteTag: _addFavoriteTag,
        onRemoveFavoriteTag: _removeFavoriteTag,
        onFavoritesToggle: () =>
            setState(() => _showFavoritesOnly = !_showFavoritesOnly),
        onChildTagToggle: (tag) {
          setState(() {
            _removeEquivalentGroupSelection(
              tagName: tag,
              parentTag: _activeChildParentTag,
            );
            _toggleSingleSelection(_selectedChildTags, tag);
          });
        },
        onClearChildTags: () => setState(_selectedChildTags.clear),
        onTagToggle: (tag) {
          setState(() {
            _removeEquivalentGroupSelection(tagName: tag);
            _toggleSingleSelection(_selectedTags, tag);
            _selectedChildTags.clear();
          });
        },
        onClearTags: () => setState(() {
          _selectedTags.clear();
          _selectedChildTags.clear();
        }),
        onGroupTagToggle: _toggleGroupTag,
        onGroupTagExcludeToggle: _toggleExcludedTag,
      );
    }

    Widget buildMain(LayoutSize layoutSize) {
      return Column(
        children: [
          _TopBar(
            controller: _searchController,
            videoCount: videos.length,
            totalCount: store.videos.length,
            sortMode: _sortMode,
            layoutSize: layoutSize,
            hasActiveFilters: _hasActiveFilters,
            onSearchChanged: (_) => setState(() {}),
            onSortChanged: (value) => setState(() => _sortMode = value),
            onOpenSettings: _openSettings,
            onOpenTagManager: () => _openTagManager(videos),
            onOpenFilters: () {
              if (layoutSize == LayoutSize.compact) {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: _appSurface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  builder: (_) => FractionallySizedBox(
                    heightFactor: 0.92,
                    child: buildSidebar(dense: true),
                  ),
                );
                return;
              }
              setState(() => _isFilterSidebarOpen = !_isFilterSidebarOpen);
            },
          ),
          _ActiveFilterBar(
            selectedTags: _selectedTags.toList()..sort(),
            selectedChildTags: _selectedChildTags.toList()..sort(),
            selectedGroupTags: selectedGroupTags,
            excludedTags: excludedTags,
            showFavoritesOnly: _showFavoritesOnly,
            resultCount: videos.length,
            totalCount: store.videos.length,
            onRemovePrimaryTag: (tag) => setState(() {
              _selectedTags.remove(tag);
              _selectedChildTags.clear();
            }),
            onRemoveChildTag: (tag) =>
                setState(() => _selectedChildTags.remove(tag)),
            onRemoveGroupTag: _removeGroupTag,
            onRemoveExcludedTag: _removeExcludedTag,
            onClearFavoritesOnly: () =>
                setState(() => _showFavoritesOnly = false),
            onClearAll: _hasActiveFilters ? _clearAllFilters : null,
            onSaveSmartList: _showSaveSmartListTodo,
          ),
          if (childParentTag != null)
            _ChildTagStrip(
              parentTag: childParentTag,
              tags: childTags,
              selectedTags: _selectedChildTags,
              onToggle: (tag) {
                setState(() {
                  _removeEquivalentGroupSelection(
                    tagName: tag,
                    parentTag: _activeChildParentTag,
                  );
                  _toggleSingleSelection(_selectedChildTags, tag);
                });
              },
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: _motionDuration,
              switchInCurve: _motionCurve,
              switchOutCurve: Curves.easeInCubic,
              child: videos.isEmpty
                  ? _EmptyState(
                      key: ValueKey('empty-${store.videos.isNotEmpty}'),
                      hasLibrary: store.videos.isNotEmpty,
                    )
                  : _VideoGrid(
                      key: ValueKey(
                        '${videos.length}-${_selectedTags.join('|')}-${_selectedChildTags.join('|')}-${_selectedGroupTagIds.values.expand((ids) => ids).join('|')}-${_excludedTagIds.join('|')}-${_searchController.text}',
                      ),
                      videos: videos,
                      thumbnailService: thumbnailService,
                      playbackSettings: _playbackSettings,
                      onOpen: _openVideo,
                      onEditTags: _editTags,
                      onToggleFavorite: _toggleFavorite,
                    ),
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
          final showPersistentSidebar = layoutSize == LayoutSize.expanded ||
              (layoutSize == LayoutSize.medium && _isFilterSidebarOpen);
          return Row(
            children: [
              if (showPersistentSidebar)
                buildSidebar(dense: layoutSize != LayoutSize.expanded),
              Expanded(child: buildMain(layoutSize)),
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
      setState(() {});
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
      setState(() {});
    }
  }

  Future<void> _addFavoriteTag() async {
    final controller = TextEditingController();
    final existingTags = _store?.allTags.toList() ?? const <String>[];
    existingTags.sort();
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('\u6dfb\u52a0\u5e38\u7528\u6807\u7b7e'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '\u6807\u7b7e\u540d',
                  hintText: '\u8f93\u5165\u6216\u9009\u62e9\u6807\u7b7e\u540d',
                ),
                onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in existingTags)
                        ActionChip(
                          label: Text(tag),
                          onPressed: () => Navigator.of(context).pop(tag),
                        ),
                    ],
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
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('\u6dfb\u52a0'),
          ),
        ],
      ),
    );
    controller.dispose();
    final tag = picked == null ? null : TagRules.normalizeTag(picked);
    if (tag == null || tag.isEmpty || _store == null) {
      return;
    }
    if (!_store!.favoriteTags
        .any((existing) => TagRules.sameTag(existing, tag))) {
      setState(() => _store!.favoriteTags.add(tag));
      await _store!.saveMetadata();
    }
  }

  Future<void> _removeFavoriteTag(String tag) async {
    final store = _store;
    if (store == null) {
      return;
    }
    setState(() {
      store.favoriteTags.remove(tag);
      _selectedTags.remove(tag);
      _selectedChildTags.clear();
    });
    await store.saveMetadata();
  }

  Future<void> _openVideo(VideoItem item, List<VideoItem> playlist) async {
    final thumbnailService = _thumbnailService!;
    final activeChildTag =
        _selectedChildTags.isEmpty ? null : _selectedChildTags.first;
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
            queueTitle: _currentQueueTitle(),
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
      setState(() {});
    }
  }

  Future<void> _toggleFavorite(VideoItem item) async {
    setState(() => item.isFavorite = !item.isFavorite);
    await _store?.upsertVideo(item);
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
      setState(() {});
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
      setState(() {});
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
