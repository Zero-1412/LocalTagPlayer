part of '../../main.dart';

enum SortMode { recent, name, folder }

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.roots,
    required this.tags,
    required this.tagGroups,
    required this.resultCounts,
    required this.favoriteTags,
    required this.childParentTag,
    required this.childTags,
    required this.selectedChildTags,
    required this.selectedGroupTagIds,
    required this.excludedTagIds,
    required this.favoriteCount,
    required this.showFavoritesOnly,
    required this.selectedTags,
    required this.isScanning,
    required this.dense,
    required this.onPickFolder,
    required this.onRescan,
    required this.onAddFavoriteTag,
    required this.onRemoveFavoriteTag,
    required this.onFavoritesToggle,
    required this.onChildTagToggle,
    required this.onClearChildTags,
    required this.onTagToggle,
    required this.onClearTags,
    required this.onGroupTagToggle,
    required this.onGroupTagExcludeToggle,
  });

  final List<String> roots;
  final List<String> tags;
  final List<TagGroup> tagGroups;
  final Map<String, int> resultCounts;
  final List<String> favoriteTags;
  final String? childParentTag;
  final List<String> childTags;
  final Set<String> selectedChildTags;
  final Map<String, Set<String>> selectedGroupTagIds;
  final Set<String> excludedTagIds;
  final int favoriteCount;
  final bool showFavoritesOnly;
  final Set<String> selectedTags;
  final bool isScanning;
  final bool dense;
  final VoidCallback onPickFolder;
  final VoidCallback onRescan;
  final VoidCallback onAddFavoriteTag;
  final ValueChanged<String> onRemoveFavoriteTag;
  final VoidCallback onFavoritesToggle;
  final ValueChanged<String> onChildTagToggle;
  final VoidCallback onClearChildTags;
  final ValueChanged<String> onTagToggle;
  final VoidCallback onClearTags;
  final ValueChanged<TagItem> onGroupTagToggle;
  final ValueChanged<TagItem> onGroupTagExcludeToggle;
  @override
  Widget build(BuildContext context) {
    final horizontalPadding = dense ? 14.0 : 18.0;
    return SizedBox(
      width: dense ? 292 : 336,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: _appSurface,
          border: Border(right: BorderSide(color: _appBorder)),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(horizontalPadding),
            child: ScrollConfiguration(
              behavior: const _DesktopDragScrollBehavior(),
              child: ListView(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.video_library_outlined),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '\u672c\u5730\u6807\u7b7e\u64ad\u653e\u5668',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: isScanning ? null : onPickFolder,
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('\u6dfb\u52a0\u76ee\u5f55'),
                      ),
                      OutlinedButton.icon(
                        onPressed: isScanning || roots.isEmpty ? null : onRescan,
                        icon: isScanning
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                        label: Text(isScanning ? '\u626b\u63cf\u4e2d' : '\u91cd\u65b0\u626b\u63cf'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('\u89c6\u9891\u76ee\u5f55', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  if (roots.isEmpty)
                    const Text('\u8fd8\u6ca1\u6709\u6dfb\u52a0\u76ee\u5f55', style: TextStyle(color: Colors.black54))
                  else
                    ...roots.map(
                      (root) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          root,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text('\u5e38\u7528\u6807\u7b7e', style: Theme.of(context).textTheme.labelLarge),
                      const Spacer(),
                      IconButton(
                        tooltip: '\u6dfb\u52a0\u5e38\u7528\u6807\u7b7e',
                        onPressed: onAddFavoriteTag,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FilterChip(
                    avatar: const Icon(Icons.favorite_border, size: 18),
                    label: Text('\u6536\u85cf $favoriteCount'),
                    selected: showFavoritesOnly,
                    onSelected: (_) => onFavoritesToggle(),
                  ),
                  const SizedBox(height: 8),
                  if (favoriteTags.isEmpty)
                    const Text('\u70b9\u51fb + \u6dfb\u52a0\u5e38\u7528\u6807\u7b7e', style: TextStyle(color: Colors.black54))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in favoriteTags)
                          InputChip(
                            label: Text(tag),
                            selected: selectedTags.contains(tag),
                            onPressed: () => onTagToggle(tag),
                            onDeleted: () => onRemoveFavoriteTag(tag),
                          ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  Text('\u5206\u7ec4\u6807\u7b7e', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  if (tagGroups.isEmpty)
                    const Text(
                      '\u626b\u63cf\u6216\u7f16\u8f91\u6807\u7b7e\u540e\uff0c\u8fd9\u91cc\u4f1a\u663e\u793a\u53ef\u7ec4\u5408\u7b5b\u9009\u7684\u6807\u7b7e\u3002',
                      style: TextStyle(color: Colors.black54),
                    )
                  else
                    for (final group in tagGroups)
                      _TagFilterGroup(
                        group: group,
                        resultCounts: resultCounts,
                        selectedIds: selectedGroupTagIds[group.id] ?? const <String>{},
                        excludedIds: excludedTagIds,
                        onToggle: onGroupTagToggle,
                        onExcludeToggle: onGroupTagExcludeToggle,
                      ),
                  if (childParentTag != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '\u4e8c\u7ea7\u6807\u7b7e / $childParentTag',
                            style: Theme.of(context).textTheme.labelLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: selectedChildTags.isEmpty ? null : onClearChildTags,
                          child: const Text('\u6e05\u7a7a'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in TagRules.sortedChildTags(
                          childTags.isEmpty ? const <String>[TagRules.defaultAlbumTag] : childTags,
                        ))
                          FilterChip(
                            label: Text(tag),
                            selected: selectedChildTags.contains(tag),
                            onSelected: (_) => onChildTagToggle(tag),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text('\u517c\u5bb9\u6807\u7b7e', style: Theme.of(context).textTheme.labelLarge),
                      const Spacer(),
                      TextButton(
                        onPressed: selectedTags.isEmpty ? null : onClearTags,
                        child: const Text('\u6e05\u7a7a'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (tags.isEmpty)
                    const Text(
                      '\u70b9\u51fb\u89c6\u9891\u5361\u7247\u4e0a\u7684\u6807\u7b7e\u6309\u94ae\uff0c\u4e3a\u89c6\u9891\u6dfb\u52a0\u5206\u7c7b\u6807\u7b7e\u3002',
                      style: TextStyle(color: Colors.black54),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in tags.take(40))
                          FilterChip(
                            label: Text(tag),
                            selected: selectedTags.contains(tag),
                            onSelected: (_) => onTagToggle(tag),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TagFilterGroup extends StatelessWidget {
  const _TagFilterGroup({
    required this.group,
    required this.resultCounts,
    required this.selectedIds,
    required this.excludedIds,
    required this.onToggle,
    required this.onExcludeToggle,
  });

  final TagGroup group;
  final Map<String, int> resultCounts;
  final Set<String> selectedIds;
  final Set<String> excludedIds;
  final ValueChanged<TagItem> onToggle;
  final ValueChanged<TagItem> onExcludeToggle;

  @override
  Widget build(BuildContext context) {
    final title = group.displayName ?? group.name;
    final visibleItems = group.items.take(36).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _appTextMuted,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in visibleItems)
                _TagFilterChip(
                  tag: tag,
                  count: resultCounts[tag.id] ?? 0,
                  selected: selectedIds.contains(tag.id),
                  excluded: excludedIds.contains(tag.id),
                  onToggle: () => onToggle(tag),
                  onExcludeToggle: () => onExcludeToggle(tag),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TagFilterChip extends StatelessWidget {
  const _TagFilterChip({
    required this.tag,
    required this.count,
    required this.selected,
    required this.excluded,
    required this.onToggle,
    required this.onExcludeToggle,
  });

  final TagItem tag;
  final int count;
  final bool selected;
  final bool excluded;
  final VoidCallback onToggle;
  final VoidCallback onExcludeToggle;

  @override
  Widget build(BuildContext context) {
    final label = tag.displayName ?? tag.name;
    return InputChip(
      avatar: excluded
          ? const Icon(Icons.remove_circle_outline, size: 18)
          : selected
              ? const Icon(Icons.check, size: 18)
              : null,
      label: Text('$label $count'),
      selected: selected || excluded,
      selectedColor: excluded ? const Color(0xffffe3df) : const Color(0xffd8efea),
      onPressed: onToggle,
      onDeleted: onExcludeToggle,
      deleteIcon: Icon(
        excluded ? Icons.close : Icons.remove_circle_outline,
        size: 18,
      ),
      deleteButtonTooltipMessage: excluded ? '\u53d6\u6d88\u6392\u9664' : '\u6392\u9664\u8fd9\u4e2a\u6807\u7b7e',
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ActiveFilterBar extends StatelessWidget {
  const _ActiveFilterBar({
    required this.selectedTags,
    required this.selectedChildTags,
    required this.selectedGroupTags,
    required this.excludedTags,
    required this.showFavoritesOnly,
    required this.resultCount,
    required this.totalCount,
    required this.onRemovePrimaryTag,
    required this.onRemoveChildTag,
    required this.onRemoveGroupTag,
    required this.onRemoveExcludedTag,
    required this.onClearFavoritesOnly,
    required this.onClearAll,
    required this.onSaveSmartList,
  });

  final List<String> selectedTags;
  final List<String> selectedChildTags;
  final List<TagItem> selectedGroupTags;
  final List<TagItem> excludedTags;
  final bool showFavoritesOnly;
  final int resultCount;
  final int totalCount;
  final ValueChanged<String> onRemovePrimaryTag;
  final ValueChanged<String> onRemoveChildTag;
  final ValueChanged<TagItem> onRemoveGroupTag;
  final ValueChanged<TagItem> onRemoveExcludedTag;
  final VoidCallback onClearFavoritesOnly;
  final VoidCallback? onClearAll;
  final VoidCallback onSaveSmartList;

  @override
  Widget build(BuildContext context) {
    final chips = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (showFavoritesOnly)
          InputChip(
            avatar: const Icon(Icons.favorite, size: 18),
            label: const Text('\u6536\u85cf'),
            onDeleted: onClearFavoritesOnly,
          ),
        for (final tag in selectedTags)
          InputChip(
            label: Text(tag),
            onDeleted: () => onRemovePrimaryTag(tag),
          ),
        for (final tag in selectedChildTags)
          InputChip(
            label: Text(tag),
            onDeleted: () => onRemoveChildTag(tag),
          ),
        for (final tag in selectedGroupTags)
          InputChip(
            label: Text(tag.displayName ?? tag.name),
            onDeleted: () => onRemoveGroupTag(tag),
          ),
        for (final tag in excludedTags)
          InputChip(
            avatar: const Icon(Icons.remove_circle_outline, size: 18),
            label: Text('-${tag.displayName ?? tag.name}'),
            selected: true,
            selectedColor: const Color(0xffffe3df),
            onDeleted: () => onRemoveExcludedTag(tag),
          ),
        if (onClearAll == null)
          const Chip(
            avatar: Icon(Icons.filter_alt_outlined, size: 18),
            label: Text('\u672a\u8bbe\u7f6e\u7b5b\u9009'),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
    final actions = Wrap(
      spacing: 6,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: [
        TextButton.icon(
          onPressed: onClearAll,
          icon: const Icon(Icons.filter_alt_off_outlined),
          label: const Text('\u6e05\u7a7a'),
        ),
        OutlinedButton.icon(
          onPressed: onSaveSmartList,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: const Text('\u4fdd\u5b58\u7b5b\u9009'),
        ),
        SizedBox(
          width: 112,
          child: Text(
            '$resultCount / $totalCount',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _appBorder)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                chips,
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: actions,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: chips),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }
}


class CacheStats {
  const CacheStats({
    required this.total,
    required this.cached,
    required this.missing,
    required this.errors,
    required this.queued,
    required this.active,
    required this.activeBackground,
    required this.maxConcurrent,
    required this.maxBackground,
    required this.maxBackgroundQueued,
    required this.paused,
    required this.completedThisRun,
    required this.failedThisRun,
    required this.ffmpegCompleted,
    required this.fallbackCompleted,
    required this.averageMs,
  });

  final int total;
  final int cached;
  final int missing;
  final int errors;
  final int queued;
  final int active;
  final int activeBackground;
  final int maxConcurrent;
  final int maxBackground;
  final int maxBackgroundQueued;
  final bool paused;
  final int completedThisRun;
  final int failedThisRun;
  final int ffmpegCompleted;
  final int fallbackCompleted;
  final int averageMs;
}

class _ChildTagStrip extends StatelessWidget {
  const _ChildTagStrip({
    required this.parentTag,
    required this.tags,
    required this.selectedTags,
    required this.onToggle,
  });

  final String parentTag;
  final List<String> tags;
  final Set<String> selectedTags;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final effectiveTags = TagRules.sortedChildTags(tags.isEmpty ? const <String>[TagRules.defaultAlbumTag] : tags);
    return SizedBox(
      height: 50,
      child: _HorizontalWheelScroller(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        children: [
          Chip(
            avatar: const Icon(Icons.account_tree_outlined, size: 18),
            label: Text(parentTag),
            visualDensity: VisualDensity.compact,
          ),
          for (final tag in effectiveTags)
            FilterChip(
              label: Text(tag),
              selected: selectedTags.contains(tag),
              onSelected: (_) => onToggle(tag),
            ),
        ],
      ),
    );
  }
}

class _HorizontalWheelScroller extends StatefulWidget {
  const _HorizontalWheelScroller({
    required this.children,
    this.padding = EdgeInsets.zero,
    this.spacing = 8,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double spacing;

  @override
  State<_HorizontalWheelScroller> createState() => _HorizontalWheelScrollerState();
}

class _HorizontalWheelScrollerState extends State<_HorizontalWheelScroller> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) {
      return;
    }
    final target = (_controller.offset + delta).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          final delta = event.scrollDelta.dy.abs() >= event.scrollDelta.dx.abs()
              ? event.scrollDelta.dy
              : event.scrollDelta.dx;
          _scrollBy(delta * 1.6);
        }
      },
      child: ScrollConfiguration(
        behavior: const _DesktopDragScrollBehavior(),
        child: Scrollbar(
          controller: _controller,
          thumbVisibility: true,
          child: ListView.separated(
            controller: _controller,
            padding: widget.padding,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            itemCount: widget.children.length,
            separatorBuilder: (_, __) => SizedBox(width: widget.spacing),
            itemBuilder: (context, index) => widget.children[index],
          ),
        ),
      ),
    );
  }
}

class _DesktopDragScrollBehavior extends MaterialScrollBehavior {
  const _DesktopDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

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
  final ValueChanged<PlaybackSettings> onPlaybackSettingsChanged;

  @override
  State<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

class _CacheSettingsPageState extends State<CacheSettingsPage> {
  late Future<_CacheDiagnostics> _future;
  Timer? _refreshTimer;
  var _isCachingThumbnails = false;
  var _isCachingMedia = false;
  var _isRetryingFailures = false;
  var _isClearingFailures = false;
  late PlaybackSettings _playbackSettings;
  late final MediaDetailsService _mediaDetailsService;

  @override
  void initState() {
    super.initState();
    _playbackSettings = widget.playbackSettings;
    _mediaDetailsService = MediaDetailsService(
      onUpdated: (item, details, fingerprint) async {
        item.mediaDetails = details;
        item.mediaFingerprint = fingerprint ?? item.mediaFingerprint;
        await widget.store.upsertVideo(item);
      },
    );
    _future = _load();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    unawaited(widget.store.save());
    super.dispose();
  }

  Future<_CacheDiagnostics> _load() async {
    final items = widget.store.videos.values.toList();
    final tools = await ExternalMediaTools.find();
    final thumbnailStats = await widget.thumbnailService.statsFor(items);
    if (_isCachingThumbnails && thumbnailStats.queued == 0 && thumbnailStats.active == 0) {
      _isCachingThumbnails = false;
      unawaited(widget.store.save());
    }
    if (_isCachingMedia && _mediaDetailsService.queuedReads == 0 && _mediaDetailsService.activeReads == 0) {
      _isCachingMedia = false;
      unawaited(widget.store.save());
    }
    var mediaCached = 0;
    var mediaMissing = 0;
    var mediaErrors = 0;
    for (final item in items) {
      if (item.mediaDetails != null) {
        mediaCached++;
      } else {
        mediaMissing++;
      }
      if (item.mediaDetailsError != null) {
        mediaErrors++;
      }
    }
    return _CacheDiagnostics(
      thumbnailStats: thumbnailStats,
      mediaTotal: items.length,
      mediaCached: mediaCached,
      mediaMissing: mediaMissing,
      mediaErrors: mediaErrors,
      mediaQueued: _mediaDetailsService.queuedReads,
      mediaActive: _mediaDetailsService.activeReads,
      mediaCompletedThisRun: _mediaDetailsService.completedThisRun,
      mediaFailedThisRun: _mediaDetailsService.failedThisRun,
      tools: tools,
      abnormalFiles: items
          .where((item) => item.thumbnailError != null || item.mediaDetailsError != null)
          .toList(),
    );
  }

  void _refresh() {
    if (mounted) {
      setState(() => _future = _load());
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refresh();
    });
  }

  Future<void> _cacheMissingThumbnails() async {
    if (_isCachingThumbnails) {
      return;
    }
    setState(() => _isCachingThumbnails = true);
    _startAutoRefresh();
    final missing = <VideoItem>[];
    for (final item in widget.store.videos.values) {
      final file = await widget.thumbnailService.thumbnailFor(item);
      if (file == null || !await file.exists()) {
        missing.add(item);
      }
    }
    widget.thumbnailService.prefetchAll(missing);
    _refresh();
  }

  Future<void> _cacheMissingMediaDetails() async {
    if (_isCachingMedia) {
      return;
    }
    setState(() => _isCachingMedia = true);
    _startAutoRefresh();
    for (final item in widget.store.videos.values) {
      if (item.mediaDetails == null) {
        unawaited(_mediaDetailsService.detailsFor(item));
      }
    }
    _refresh();
  }

  Future<void> _retryFailures() async {
    if (_isRetryingFailures || _isClearingFailures || _isCachingThumbnails || _isCachingMedia) {
      return;
    }
    final failed = widget.store.videos.values
        .where((item) => item.thumbnailError != null || item.mediaDetailsError != null)
        .toList();
    if (failed.isEmpty) {
      return;
    }
    setState(() {
      _isRetryingFailures = true;
      _isCachingThumbnails = true;
      _isCachingMedia = true;
    });
    try {
      await widget.thumbnailService.retryFailed(failed);
      for (final item in failed.where((item) => item.thumbnailError == null)) {
        await widget.store.upsertVideo(item);
      }
      for (final item in failed.where((item) => item.mediaDetailsError != null)) {
        item.mediaDetails = null;
        item.mediaDetailsError = null;
        await widget.store.upsertVideo(item);
        unawaited(_mediaDetailsService.detailsFor(item));
      }
    } finally {
      if (mounted) {
        setState(() => _isRetryingFailures = false);
      }
    }
    _refresh();
  }

  Future<void> _clearFailureRecords() async {
    if (_isRetryingFailures || _isClearingFailures || _isCachingThumbnails || _isCachingMedia) {
      return;
    }
    setState(() => _isClearingFailures = true);
    try {
      for (final item in widget.store.videos.values) {
        if (item.thumbnailError == null && item.mediaDetailsError == null) {
          continue;
        }
        item.thumbnailError = null;
        item.mediaDetailsError = null;
        await widget.store.upsertVideo(item);
      }
    } finally {
      if (mounted) {
        setState(() => _isClearingFailures = false);
      }
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final layoutSize = LayoutBreakpoints.fromWidth(MediaQuery.sizeOf(context).width);
    final compact = layoutSize == LayoutSize.compact;
    final busy = _isRetryingFailures || _isClearingFailures || _isCachingThumbnails || _isCachingMedia;
    final compactActions = <Widget>[
      PopupMenuButton<String>(
        tooltip: '\u7f13\u5b58\u64cd\u4f5c',
        icon: const Icon(Icons.more_vert),
        onSelected: (value) {
          switch (value) {
            case 'thumbs':
              _cacheMissingThumbnails();
              break;
            case 'pause':
              setState(() {
                widget.thumbnailService.isPaused
                    ? widget.thumbnailService.resume()
                    : widget.thumbnailService.pause();
              });
              _refresh();
              break;
            case 'media':
              _cacheMissingMediaDetails();
              break;
            case 'retry':
              _retryFailures();
              break;
            case 'clear':
              _clearFailureRecords();
              break;
            case 'refresh':
              _refresh();
              break;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'thumbs',
            enabled: !_isCachingThumbnails,
            child: const Text('\u7ee7\u7eed\u7f13\u5b58\u7f29\u7565\u56fe'),
          ),
          PopupMenuItem(
            value: 'pause',
            child: Text(widget.thumbnailService.isPaused ? '\u7ee7\u7eed\u7f29\u7565\u56fe\u961f\u5217' : '\u6682\u505c\u7f29\u7565\u56fe\u961f\u5217'),
          ),
          PopupMenuItem(
            value: 'media',
            enabled: !_isCachingMedia,
            child: const Text('\u7ee7\u7eed\u8bfb\u53d6\u89c6\u9891\u4fe1\u606f'),
          ),
          PopupMenuItem(
            value: 'retry',
            enabled: !busy,
            child: const Text('\u91cd\u8bd5\u5931\u8d25\u9879'),
          ),
          PopupMenuItem(
            value: 'clear',
            enabled: !busy,
            child: const Text('\u6e05\u9664\u5931\u8d25\u8bb0\u5f55'),
          ),
          const PopupMenuItem(
            value: 'refresh',
            child: Text('\u5237\u65b0'),
          ),
        ],
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('\u7f13\u5b58\u4e0e\u8bca\u65ad'),
        actions: compact ? compactActions : [
          IconButton(
            tooltip: _isCachingThumbnails ? '\u7f29\u7565\u56fe\u7f13\u5b58\u4e2d' : '\u7ee7\u7eed\u7f13\u5b58\u7f29\u7565\u56fe',
            onPressed: _isCachingThumbnails ? null : _cacheMissingThumbnails,
            icon: const Icon(Icons.image_search),
          ),
          IconButton(
            tooltip: widget.thumbnailService.isPaused ? '\u7ee7\u7eed\u7f29\u7565\u56fe\u961f\u5217' : '\u6682\u505c\u7f29\u7565\u56fe\u961f\u5217',
            onPressed: () {
              setState(() {
                widget.thumbnailService.isPaused
                    ? widget.thumbnailService.resume()
                    : widget.thumbnailService.pause();
              });
              _refresh();
            },
            icon: Icon(widget.thumbnailService.isPaused ? Icons.play_arrow : Icons.pause),
          ),
          IconButton(
            tooltip: _isCachingMedia ? '\u89c6\u9891\u4fe1\u606f\u8bfb\u53d6\u4e2d' : '\u7ee7\u7eed\u8bfb\u53d6\u89c6\u9891\u4fe1\u606f',
            onPressed: _isCachingMedia ? null : _cacheMissingMediaDetails,
            icon: const Icon(Icons.manage_search),
          ),
          IconButton(
            tooltip: _isRetryingFailures ? '\u5931\u8d25\u9879\u91cd\u8bd5\u4e2d' : '\u91cd\u8bd5\u5931\u8d25\u9879',
            onPressed: busy ? null : _retryFailures,
            icon: const Icon(Icons.replay),
          ),
          IconButton(
            tooltip: _isClearingFailures ? '\u6b63\u5728\u6e05\u9664\u5931\u8d25\u8bb0\u5f55' : '\u6e05\u9664\u5931\u8d25\u8bb0\u5f55',
            onPressed: busy ? null : _clearFailureRecords,
            icon: const Icon(Icons.clear_all),
          ),
          IconButton(
            tooltip: '\u5237\u65b0',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_CacheDiagnostics>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return ListView(
            padding: EdgeInsets.fromLTRB(compact ? 14 : 24, 20, compact ? 14 : 24, 28),
            children: [
              const SettingsNotice(
                icon: Icons.info_outline,
                title: '\u7f13\u5b58\u961f\u5217\u4f1a\u81ea\u52a8\u5237\u65b0',
                message: '\u961f\u5217\u4e3a 0 \u8868\u793a\u5f53\u524d\u6ca1\u6709\u4efb\u52a1\u5728\u6267\u884c\uff1b\u53f3\u4e0a\u89d2\u6309\u94ae\u53ef\u7ee7\u7eed\u8865\u7f13\u5b58\u6216\u6682\u505c\u961f\u5217\u3002',
              ),
              const SizedBox(height: 14),
              _PlaybackSettingsCard(
                settings: _playbackSettings,
                onChanged: (settings) {
                  setState(() => _playbackSettings = settings);
                  widget.onPlaybackSettingsChanged(settings);
                },
              ),
              const SizedBox(height: 14),
              _StatsCard(
                title: 'FFmpeg / FFprobe',
                lines: [
                  data.tools.hasFfmpeg
                      ? 'FFmpeg: ${data.tools.ffmpegPath}'
                      : 'FFmpeg: \u672a\u627e\u5230\uff0c\u7f29\u7565\u56fe\u5c06\u56de\u9000\u5230\u64ad\u653e\u5668\u622a\u56fe\uff0c\u901f\u5ea6\u4f1a\u6162',
                  'FFmpeg \u7248\u672c: ${data.tools.ffmpegVersion ?? '\u672a\u77e5'}',
                  data.tools.hasFfprobe
                      ? 'FFprobe: ${data.tools.ffprobePath}'
                      : 'FFprobe: \u672a\u627e\u5230\uff0c\u89c6\u9891\u4fe1\u606f\u5c06\u56de\u9000\u5230\u64ad\u653e\u5668\u8bfb\u53d6\uff0c\u901f\u5ea6\u4f1a\u6162',
                  'FFprobe \u7248\u672c: ${data.tools.ffprobeVersion ?? '\u672a\u77e5'}',
                ],
              ),
              const SizedBox(height: 14),
              _StatsCard(
                title: '\u7f29\u7565\u56fe',
                lines: [
                  '\u603b\u6570: ${data.thumbnailStats.total}',
                  '\u5df2\u7f13\u5b58: ${data.thumbnailStats.cached}',
                  '\u672a\u7f13\u5b58: ${data.thumbnailStats.missing}',
                  '\u961f\u5217\u4e2d: ${data.thumbnailStats.queued}',
                  '\u540e\u53f0\u6392\u961f\u4e0a\u9650: ${data.thumbnailStats.maxBackgroundQueued}',
                  '\u6b63\u5728\u6267\u884c: ${data.thumbnailStats.active} / ${data.thumbnailStats.maxConcurrent}',
                  '\u540e\u53f0\u6267\u884c: ${data.thumbnailStats.activeBackground} / ${data.thumbnailStats.maxBackground}',
                  '\u961f\u5217\u72b6\u6001: ${data.thumbnailStats.paused ? '\u5df2\u6682\u505c' : '\u8fd0\u884c\u4e2d'}',
                  '\u672c\u6b21\u5b8c\u6210: ${data.thumbnailStats.completedThisRun}',
                  'FFmpeg \u5b8c\u6210: ${data.thumbnailStats.ffmpegCompleted}',
                  '\u64ad\u653e\u5668\u515c\u5e95: ${data.thumbnailStats.fallbackCompleted}',
                  '\u5e73\u5747\u8017\u65f6: ${data.thumbnailStats.averageMs} ms',
                  '\u5931\u8d25: ${data.thumbnailStats.errors}',
                ],
              ),
              const SizedBox(height: 14),
              _StatsCard(
                title: '\u89c6\u9891\u4fe1\u606f',
                lines: [
                  '\u603b\u6570: ${data.mediaTotal}',
                  '\u5df2\u7f13\u5b58: ${data.mediaCached}',
                  '\u672a\u7f13\u5b58: ${data.mediaMissing}',
                  '\u5931\u8d25: ${data.mediaErrors}',
                  '\u961f\u5217\u4e2d: ${data.mediaQueued}',
                  '\u6b63\u5728\u6267\u884c: ${data.mediaActive}',
                  '\u672c\u6b21\u5b8c\u6210: ${data.mediaCompletedThisRun}',
                  '\u672c\u6b21\u5931\u8d25: ${data.mediaFailedThisRun}',
                ],
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '\u5f02\u5e38\u6587\u4ef6',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      if (data.abnormalFiles.isEmpty)
                        const Text('\u6682\u65e0\u5931\u8d25\u8bb0\u5f55', style: TextStyle(color: _appTextMuted))
                      else
                        for (final item in data.abnormalFiles.take(50))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              [
                                if (item.thumbnailError != null) '\u7f29\u7565\u56fe: ${item.thumbnailError}',
                                if (item.mediaDetailsError != null) '\u5a92\u4f53\u4fe1\u606f: ${item.mediaDetailsError}',
                              ].join('\n'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CacheDiagnostics {
  const _CacheDiagnostics({
    required this.tools,
    required this.thumbnailStats,
    required this.mediaTotal,
    required this.mediaCached,
    required this.mediaMissing,
    required this.mediaErrors,
    required this.mediaQueued,
    required this.mediaActive,
    required this.mediaCompletedThisRun,
    required this.mediaFailedThisRun,
    required this.abnormalFiles,
  });

  final ExternalMediaToolsState tools;
  final CacheStats thumbnailStats;
  final int mediaTotal;
  final int mediaCached;
  final int mediaMissing;
  final int mediaErrors;
  final int mediaQueued;
  final int mediaActive;
  final int mediaCompletedThisRun;
  final int mediaFailedThisRun;
  final List<VideoItem> abnormalFiles;
}

class SettingsNotice extends StatelessWidget {
  const SettingsNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xffe6f4f1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffb9d9d3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _appAccentStrong),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xff173f3a),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xff45615d),
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackSettingsCard extends StatelessWidget {
  const _PlaybackSettingsCard({required this.settings, required this.onChanged});

  final PlaybackSettings settings;
  final ValueChanged<PlaybackSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '\u64ad\u653e\u8bbe\u7f6e',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: settings.hwdec,
              decoration: const InputDecoration(
                labelText: '\u786c\u4ef6\u89e3\u7801\u5668',
                helperText: '\u66f4\u6539\u540e\u5bf9\u65b0\u6253\u5f00\u7684\u64ad\u653e\u5668\u548c\u60ac\u505c\u9884\u89c8\u751f\u6548',
              ),
              items: [
                for (final value in PlaybackSettings.decoderOptions)
                  DropdownMenuItem(
                    value: value,
                    child: Text(PlaybackSettings.labelFor(value)),
                  ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                onChanged(settings.copyWith(hwdec: value));
              },
            ),
          ],
        ),
      ),
    );
  }
}
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  line,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _appTextMuted,
                        height: 1.25,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.videoCount,
    required this.totalCount,
    required this.sortMode,
    required this.layoutSize,
    required this.hasActiveFilters,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onOpenSettings,
    required this.onOpenTagManager,
    required this.onOpenFilters,
  });

  final TextEditingController controller;
  final int videoCount;
  final int totalCount;
  final SortMode sortMode;
  final LayoutSize layoutSize;
  final bool hasActiveFilters;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<SortMode> onSortChanged;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenTagManager;
  final VoidCallback onOpenFilters;
  @override
  Widget build(BuildContext context) {
    final compact = layoutSize == LayoutSize.compact;
    final showFilterButton = layoutSize != LayoutSize.expanded;
    final sortButton = SegmentedButton<SortMode>(
      segments: const [
        ButtonSegment(
          value: SortMode.recent,
          icon: Icon(Icons.schedule),
          tooltip: '\u6700\u8fd1\u64ad\u653e',
        ),
        ButtonSegment(
          value: SortMode.name,
          icon: Icon(Icons.sort_by_alpha),
          tooltip: '\u6309\u540d\u79f0',
        ),
        ButtonSegment(
          value: SortMode.folder,
          icon: Icon(Icons.folder_outlined),
          tooltip: '\u6309\u76ee\u5f55',
        ),
      ],
      selected: {sortMode},
      onSelectionChanged: (values) => onSortChanged(values.single),
    );
    final sortControl = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: sortButton,
    );
    final countText = Text(
      '$videoCount / $totalCount',
      textAlign: compact ? TextAlign.left : TextAlign.right,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 14 : 24, 20, compact ? 14 : 24, 12),
        child: Column(
          children: [
            Row(
              children: [
                if (showFilterButton) ...[
                  IconButton.filledTonal(
                    tooltip: layoutSize == LayoutSize.compact ? '\u6253\u5f00\u7b5b\u9009' : '\u6298\u53e0\u7b5b\u9009\u680f',
                    onPressed: onOpenFilters,
                    icon: Icon(hasActiveFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: SearchBar(
                    controller: controller,
                    leading: const Icon(Icons.search),
                    hintText: compact
                        ? '\u641c\u7d22\u6587\u4ef6 / \u6807\u7b7e'
                        : '\u641c\u7d22\u6587\u4ef6\u540d / \u8def\u5f84 / \u6807\u7b7e / \u522b\u540d',
                    onChanged: onSearchChanged,
                    elevation: const WidgetStatePropertyAll(0),
                    backgroundColor: const WidgetStatePropertyAll(Color(0xffeef4f3)),
                    side: const WidgetStatePropertyAll(
                      BorderSide(color: Color(0xffd4dfdc)),
                    ),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (!compact) ...[
                  Flexible(child: sortControl),
                  const SizedBox(width: 8),
                ],
                IconButton.outlined(
                  tooltip: '标签管理',
                  onPressed: onOpenTagManager,
                  icon: const Icon(Icons.sell_outlined),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: '\u7f13\u5b58\u8bbe\u7f6e',
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune),
                ),
                if (!compact) ...[
                  const SizedBox(width: 16),
                  SizedBox(width: 96, child: countText),
                ],
              ],
            ),
            if (compact) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: sortControl),
                  const SizedBox(width: 12),
                  countText,
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VideoGrid extends StatelessWidget {
  const _VideoGrid({
    super.key,
    required this.videos,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.onOpen,
    required this.onEditTags,
    required this.onToggleFavorite,
  });

  final List<VideoItem> videos;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  final void Function(VideoItem item, List<VideoItem> playlist) onOpen;
  final ValueChanged<VideoItem> onEditTags;
  final ValueChanged<VideoItem> onToggleFavorite;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < LayoutBreakpoints.compactMaxWidth;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(compact ? 14 : 24, 10, compact ? 14 : 24, 24),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: compact ? 560 : 410,
            mainAxisExtent: compact ? 390 : 420,
            mainAxisSpacing: compact ? 12 : 18,
            crossAxisSpacing: compact ? 12 : 18,
          ),
          itemCount: videos.length,
          scrollCacheExtent: const ScrollCacheExtent.pixels(720),
          itemBuilder: (context, index) {
            final item = videos[index];
            return _InteractiveVideoCard(
              item: item,
              thumbnailService: thumbnailService,
              playbackSettings: playbackSettings,
              onOpen: () => onOpen(item, videos),
              onEditTags: () => onEditTags(item),
              onToggleFavorite: () => onToggleFavorite(item),
            );
          },
        );
      },
    );
  }
}

class _InteractiveVideoCard extends StatefulWidget {
  const _InteractiveVideoCard({
    required this.item,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.onOpen,
    required this.onEditTags,
    required this.onToggleFavorite,
  });

  final VideoItem item;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  final VoidCallback onOpen;
  final VoidCallback onEditTags;
  final VoidCallback onToggleFavorite;

  @override
  State<_InteractiveVideoCard> createState() => _InteractiveVideoCardState();
}

class _InteractiveVideoCardState extends State<_InteractiveVideoCard> {
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: _motionDuration,
          curve: _motionCurve,
          scale: _pressed ? 0.992 : 1,
          child: AnimatedContainer(
            duration: _motionDuration,
            curve: _motionCurve,
            decoration: BoxDecoration(
              color: _appSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered ? const Color(0xff9ccbc5) : _appBorder,
              ),
              boxShadow: [
                if (_hovered)
                  BoxShadow(
                    color: _appAccent.withAlpha(28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onDoubleTap: widget.onOpen,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _VideoPreview(
                        item: item,
                        thumbnailService: widget.thumbnailService,
                        playbackSettings: widget.playbackSettings,
                        onOpen: (_) => widget.onOpen(),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.folder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _appTextMuted,
                            ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 46,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: item.tags.isEmpty
                                ? [
                                    const Text(
                                      '\u672a\u6dfb\u52a0\u6807\u7b7e',
                                      style: TextStyle(color: Colors.black45),
                                    ),
                                  ]
                                : [
                                    for (final tag in (item.tags.toList()..sort()))
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: Chip(
                                          label: Text(tag),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ),
                                  ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final iconOnly = constraints.maxWidth < 260;
                          return Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: widget.onOpen,
                                  icon: const Icon(Icons.play_arrow),
                                  label: Text(iconOnly ? '' : '\u64ad\u653e'),
                                  style: FilledButton.styleFrom(
                                    fixedSize: const Size.fromHeight(42),
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.outlined(
                                tooltip: item.isFavorite ? '\u53d6\u6d88\u6536\u85cf' : '\u6dfb\u52a0\u6536\u85cf',
                                onPressed: widget.onToggleFavorite,
                                icon: Icon(item.isFavorite ? Icons.favorite : Icons.favorite_border),
                                style: IconButton.styleFrom(
                                  fixedSize: const Size(42, 42),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.outlined(
                                tooltip: '\u7f16\u8f91\u6807\u7b7e',
                                onPressed: widget.onEditTags,
                                icon: const Icon(Icons.sell_outlined),
                                style: IconButton.styleFrom(
                                  fixedSize: const Size(42, 42),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({
    required this.item,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.onOpen,
  });

  final VideoItem item;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  final ValueChanged<VideoItem> onOpen;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late Future<File?> _future;
  Timer? _hoverTimer;
  Player? _hoverPlayer;
  VideoController? _hoverController;
  var _isHoverPreviewLoading = false;
  var _isHoverPreviewReady = false;

  @override
  void initState() {
    super.initState();
    _future = widget.thumbnailService.thumbnailFor(widget.item);
  }

  @override
  void didUpdateWidget(covariant _VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.path != widget.item.path ||
        oldWidget.thumbnailService != widget.thumbnailService) {
      _stopHoverPreview();
      _future = widget.thumbnailService.thumbnailFor(widget.item);
    }
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    unawaited(_disposeHoverPlayer());
    super.dispose();
  }

  void _onEnter(PointerEnterEvent _) {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 900), _startHoverPreview);
  }

  void _onExit(PointerExitEvent _) {
    _hoverTimer?.cancel();
    _stopHoverPreview();
  }

  Future<void> _startHoverPreview() async {
    if (_hoverPlayer != null || _isHoverPreviewLoading) {
      return;
    }
    setState(() => _isHoverPreviewLoading = true);

    final player = Player(
      configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
    );
    final controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        width: 640,
        height: 360,
        hwdec: widget.playbackSettings.hwdec,
        enableHardwareAcceleration: widget.playbackSettings.hardwareDecodingEnabled,
      ),
    );

    _hoverPlayer = player;
    _hoverController = controller;

    try {
      await player.setVolume(0);
      await player.open(Media(widget.item.path), play: true).timeout(
            const Duration(seconds: 10),
          );
      await controller.platform.future
          .then((platform) => platform.waitUntilFirstFrameRendered)
          .timeout(const Duration(seconds: 8), onTimeout: () {});
      if (!mounted || _hoverPlayer != player) {
        await player.dispose();
        return;
      }
      setState(() {
        _isHoverPreviewLoading = false;
        _isHoverPreviewReady = true;
      });
    } catch (_) {
      if (_hoverPlayer == player) {
        _hoverPlayer = null;
        _hoverController = null;
      }
      await player.dispose();
      if (mounted) {
        setState(() {
          _isHoverPreviewLoading = false;
          _isHoverPreviewReady = false;
        });
      }
    }
  }

  void _stopHoverPreview() {
    final player = _hoverPlayer;
    _hoverPlayer = null;
    _hoverController = null;
    if (mounted) {
      setState(() {
        _isHoverPreviewLoading = false;
        _isHoverPreviewReady = false;
      });
    }
    if (player != null) {
      unawaited(player.dispose());
    }
  }

  Future<void> _disposeHoverPlayer() async {
    final player = _hoverPlayer;
    _hoverPlayer = null;
    _hoverController = null;
    if (player != null) {
      await player.dispose();
    }
  }
  @override
  Widget build(BuildContext context) {
    final hoverController = _hoverController;
    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<File?>(
                key: ValueKey(widget.item.path),
                future: _future,
                builder: (context, snapshot) {
                  final file = snapshot.data;
                  if (file != null && file.existsSync()) {
                    return Image.file(
                      file,
                      key: ValueKey(file.path),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: false,
                    );
                  }
                  return Container(
                    color: const Color(0xffd8f0f0),
                    child: Center(
                      child: snapshot.connectionState == ConnectionState.waiting
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4),
                            )
                          : const Icon(Icons.movie_outlined, size: 42),
                    ),
                  );
                },
              ),
              if (_isHoverPreviewReady && hoverController != null)
                Video(
                  controller: hoverController,
                  controls: NoVideoControls,
                  fit: BoxFit.cover,
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.02),
                        Colors.black.withValues(alpha: 0.34),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: _isHoverPreviewLoading
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.86),
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(18),
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      )
                    : IconButton.filled(
                        tooltip: _isHoverPreviewReady ? '\u6b63\u5728\u9884\u89c8\uff0c\u70b9\u51fb\u64ad\u653e' : '\u64ad\u653e',
                        onPressed: () => widget.onOpen(widget.item),
                        icon: const Icon(Icons.play_arrow_rounded, size: 34),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.88),
                          foregroundColor: const Color(0xff073b3b),
                          fixedSize: const Size(58, 58),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key, required this.hasLibrary});

  final bool hasLibrary;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasLibrary ? Icons.filter_alt_off_outlined : Icons.video_library_outlined,
            size: 54,
            color: Colors.black38,
          ),
          const SizedBox(height: 12),
          Text(hasLibrary ? '\u6ca1\u6709\u5339\u914d\u7684\u89c6\u9891' : '\u6dfb\u52a0\u89c6\u9891\u76ee\u5f55\u540e\u5f00\u59cb\u626b\u63cf'),
        ],
      ),
    );
  }
}

class TagEditorDialog extends StatefulWidget {
  const TagEditorDialog({
    super.key,
    required this.title,
    required this.initialTags,
    required this.existingTags,
  });

  final String title;
  final Set<String> initialTags;
  final Set<String> existingTags;

  @override
  State<TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<TagEditorDialog> {
  late final Set<String> _tags = _normalizeTags(widget.initialTags);
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addTag(String raw) {
    final tag = TagRules.normalizeTag(raw);
    if (tag.isEmpty) {
      return;
    }
    setState(() {
      _addNormalizedTag(tag);
      _controller.clear();
    });
  }

  void _addNormalizedTag(String tag) {
    if (!_tags.any((existing) => TagRules.sameTag(existing, tag))) {
      _tags.add(tag);
    }
  }

  Set<String> _normalizeTags(Iterable<String> tags) {
    final normalized = <String>{};
    for (final raw in tags) {
      final tag = TagRules.normalizeTag(raw);
      if (tag.isEmpty || normalized.any((existing) => TagRules.sameTag(existing, tag))) {
        continue;
      }
      normalized.add(tag);
    }
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _normalizeTags(
      widget.existingTags.where(
        (tag) => !_tags.any((selected) => TagRules.sameTag(selected, tag)),
      ),
    ).toList()
      ..sort();
    return AlertDialog(
      title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '\u65b0\u6807\u7b7e',
                prefixIcon: Icon(Icons.sell_outlined),
              ),
              onSubmitted: _addTag,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in (_tags.toList()..sort()))
                  InputChip(
                    label: Text(tag),
                    onDeleted: () => setState(() => _tags.remove(tag)),
                  ),
              ],
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('\u5df2\u6709\u6807\u7b7e', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in suggestions.take(24))
                    ActionChip(
                      label: Text(tag),
                      onPressed: () => setState(() => _addNormalizedTag(tag)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('\u53d6\u6d88'),
        ),
        FilledButton(
          onPressed: () {
            _addTag(_controller.text);
            Navigator.of(context).pop(_tags);
          },
          child: const Text('\u4fdd\u5b58'),
        ),
      ],
    );
  }
}





