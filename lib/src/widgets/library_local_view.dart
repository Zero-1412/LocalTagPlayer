part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

class _LocalLibraryView extends StatelessWidget {
  const _LocalLibraryView({
    required this.currentPath,
    required this.entries,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.dense,
    required this.canGoBack,
    required this.onBack,
    required this.onOpenFolder,
    required this.onOpenVideo,
    required this.onEditTags,
    required this.onToggleFavorite,
  });

  final String? currentPath;
  final List<_LocalLibraryEntry> entries;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  final bool dense;
  final bool canGoBack;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenFolder;
  final void Function(VideoItem item, List<VideoItem> playlist) onOpenVideo;
  final ValueChanged<VideoItem> onEditTags;
  final ValueChanged<VideoItem> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final localVideos = [
      for (final entry in entries)
        if (entry.video != null) entry.video!,
    ];
    return Listener(
      key: LibrarySmokeKeys.localPointerBackRegion,
      onPointerDown: (event) {
        // Windows 鼠标侧键“后退”通常映射为第 4 键；只在有路径历史时消费为本地媒体库返回。
        const mouseBackButton = 0x08;
        if (canGoBack && event.buttons == mouseBackButton) {
          onBack();
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
            child: Row(
              children: [
                IconButton(
                  key: LibrarySmokeKeys.localBackButton,
                  tooltip: '\u8fd4\u56de\u4e0a\u4e00\u5c42',
                  onPressed: canGoBack ? onBack : null,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: _appTextMuted,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    currentPath ?? '\u672c\u5730\u5a92\u4f53\u5e93',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _appTextMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const _EmptyState(
                    hasLibrary: true,
                    message:
                        '\u5f53\u524d\u76ee\u5f55\u6ca1\u6709\u5df2\u5165\u5e93\u89c6\u9891\u6216\u5b50\u6587\u4ef6\u5939',
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth <
                          LayoutBreakpoints.compactMaxWidth;
                      final narrow = constraints.maxWidth < 560;
                      if (dense) {
                        return ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 14 : 22,
                            2,
                            compact ? 14 : 22,
                            22,
                          ),
                          itemExtent: narrow ? 132 : 120,
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            if (entry.isFolder) {
                              return _LocalFolderRow(
                                path: entry.path,
                                onOpen: () => onOpenFolder(entry.path),
                              );
                            }
                            final video = entry.video!;
                            return _InteractiveVideoListRow(
                              item: video,
                              thumbnailService: thumbnailService,
                              playbackSettings: playbackSettings,
                              onOpen: () => onOpenVideo(video, localVideos),
                              onEditTags: () => onEditTags(video),
                              onToggleFavorite: () => onToggleFavorite(video),
                            );
                          },
                        );
                      }
                      return GridView.builder(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 14 : 22,
                          2,
                          compact ? 14 : 22,
                          22,
                        ),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent:
                              narrow ? 500 : (compact ? 248 : 286),
                          // 单列网格会把 16:9 缩略图拉高，卡片高度必须跟着增长；
                          // 否则普通窗口下标题、标签和底部按钮会挤出可视区域。
                          mainAxisExtent: narrow ? 430 : (compact ? 300 : 340),
                          mainAxisSpacing: compact ? 14 : 16,
                          crossAxisSpacing: compact ? 10 : 14,
                        ),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          if (entry.isFolder) {
                            return _LocalFolderCard(
                              path: entry.path,
                              onOpen: () => onOpenFolder(entry.path),
                            );
                          }
                          final video = entry.video!;
                          return _InteractiveVideoCard(
                            item: video,
                            thumbnailService: thumbnailService,
                            playbackSettings: playbackSettings,
                            onOpen: () => onOpenVideo(video, localVideos),
                            onEditTags: () => onEditTags(video),
                            onToggleFavorite: () => onToggleFavorite(video),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

@visibleForTesting
class LocalLibrarySmokeHarness extends StatefulWidget {
  const LocalLibrarySmokeHarness({
    super.key,
    required this.rootPath,
    required this.childPath,
    this.dense = false,
  });

  /**
   * smoke test 使用的本地媒体库 root 路径。
   */
  final String rootPath;

  /**
   * smoke test 使用的子文件夹路径。
   */
  final String childPath;

  /**
   * 是否使用列表视图；默认覆盖网格文件夹卡片路径。
   */
  final bool dense;

  @override
  State<LocalLibrarySmokeHarness> createState() =>
      _LocalLibrarySmokeHarnessState();
}

class _LocalLibrarySmokeHarnessState extends State<LocalLibrarySmokeHarness> {
  late String _currentPath = widget.rootPath;
  late final ThumbnailService _thumbnailService;
  late final Directory _thumbnailDirectory;
  final _backStack = <String>[];

  @override
  void initState() {
    super.initState();
    _thumbnailDirectory =
        Directory.systemTemp.createTempSync('ltp_local_harness_thumbs_');
    _thumbnailService = ThumbnailService._(_thumbnailDirectory);
  }

  @override
  void dispose() {
    try {
      if (_thumbnailDirectory.existsSync()) {
        _thumbnailDirectory.deleteSync(recursive: true);
      }
    } on FileSystemException {
      // 测试缩略图目录只承载 harness 临时文件，清理失败不影响交互断言。
    }
    super.dispose();
  }

  /**
   * 进入子文件夹并记录返回栈。
   *
   * 该逻辑只服务 widget smoke test，用来验证真实文件夹入口、返回按钮和鼠标侧键共用同一行为。
   */
  void _openFolder(String path) {
    setState(() {
      _backStack.add(_currentPath);
      _currentPath = path;
    });
  }

  /**
   * 从测试返回栈回到上一层路径。
   */
  void _goBack() {
    if (_backStack.isEmpty) {
      return;
    }
    setState(() {
      _currentPath = _backStack.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _currentPath == widget.rootPath
        ? <_LocalLibraryEntry>[_LocalLibraryEntry.folder(widget.childPath)]
        : const <_LocalLibraryEntry>[];
    return MaterialApp(
      home: Scaffold(
        body: _LocalLibraryView(
          currentPath: _currentPath,
          entries: entries,
          thumbnailService: _thumbnailService,
          playbackSettings: PlaybackSettings.defaults,
          dense: widget.dense,
          canGoBack: _backStack.isNotEmpty,
          onBack: _goBack,
          onOpenFolder: _openFolder,
          onOpenVideo: (_, __) {},
          onEditTags: (_) {},
          onToggleFavorite: (_) {},
        ),
      ),
    );
  }
}

/**
 * 列表行操作 smoke test 的最小宿主。
 *
 * 只挂载真实 `_InteractiveVideoListRow` 并统计播放、收藏、更多三个回调，不打开播放器、
 * 不写数据库，也不触发真实标签编辑弹窗。
 */
@visibleForTesting
class VideoListRowSmokeHarness extends StatefulWidget {
  const VideoListRowSmokeHarness({super.key});

  @override
  State<VideoListRowSmokeHarness> createState() =>
      _VideoListRowSmokeHarnessState();
}

class _VideoListRowSmokeHarnessState extends State<VideoListRowSmokeHarness> {
  late final Directory _thumbnailDirectory;
  late final ThumbnailService _thumbnailService;
  late final VideoItem _item;
  var _openCount = 0;
  var _favoriteCount = 0;
  var _moreCount = 0;

  @override
  void initState() {
    super.initState();
    _thumbnailDirectory =
        Directory.systemTemp.createTempSync('ltp_list_harness_thumbs_');
    _thumbnailService = ThumbnailService._(_thumbnailDirectory);
    _item = VideoItem(
      path: r'C:\smoke\media\Alpha\clip.mp4',
      title: 'Smoke Clip',
      folder: r'C:\smoke\media\Alpha',
      tags: const {'Alpha', 'Child01'},
      addedAt: DateTime(2026),
    );
  }

  @override
  void dispose() {
    try {
      if (_thumbnailDirectory.existsSync()) {
        _thumbnailDirectory.deleteSync(recursive: true);
      }
    } on FileSystemException {
      // 测试缩略图目录只承载 harness 临时文件，清理失败不影响交互断言。
    }
    super.dispose();
  }

  /**
   * 列表行 smoke test 的状态汇总。
   *
   * 测试只验证三个按钮是否命中对应回调，不打开播放器、不改数据库、不触发标签编辑弹窗。
   */
  String get _actionState =>
      'open=$_openCount favorite=$_favoriteCount more=$_moreCount';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1400,
          height: 160,
          child: Column(
            children: [
              Text(_actionState, key: LibrarySmokeKeys.listActionState),
              Expanded(
                child: _InteractiveVideoListRow(
                  item: _item,
                  thumbnailService: _thumbnailService,
                  playbackSettings: PlaybackSettings.defaults,
                  onOpen: () => setState(() => _openCount += 1),
                  onToggleFavorite: () {
                    setState(() {
                      _favoriteCount += 1;
                      _item.isFavorite = !_item.isFavorite;
                    });
                  },
                  onEditTags: () => setState(() => _moreCount += 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
class TagDiscoverySmokeHarness extends StatefulWidget {
  const TagDiscoverySmokeHarness({
    super.key,
    required this.childCount,
  });

  /**
   * 为一级标签生成的二级标签数量。
   *
   * 数量大于 9 时可覆盖右侧面板的“展开全部 / 收起”交互路径。
   */
  final int childCount;

  @override
  State<TagDiscoverySmokeHarness> createState() =>
      _TagDiscoverySmokeHarnessState();
}

class _TagDiscoverySmokeHarnessState extends State<TagDiscoverySmokeHarness> {
  final _selectedGroupTagIds = <String, Set<String>>{};

  late final TagItem _primary = const TagItem(
    id: 'folder.primary:alpha',
    name: 'Alpha',
    displayName: 'Alpha',
    groupId: 'folder.primary',
    source: TagSource.folder,
    usageCount: 99,
  );

  late final List<TagItem> _children = [
    for (var index = 1; index <= widget.childCount; index += 1)
      TagItem(
        id: 'folder.child:alpha:child${index.toString().padLeft(2, '0')}',
        name: 'Child${index.toString().padLeft(2, '0')}',
        displayName: 'Child${index.toString().padLeft(2, '0')}',
        groupId: 'folder.child',
        parentId: _primary.id,
        source: TagSource.folder,
        usageCount: 20 - index,
      ),
  ];

  /**
   * 根据右侧标签 chip 的当前选中态生成测试结果标题。
   *
   * 该结果区只用于验证 UI 事件链是否把默认专辑和二级标签选择传到上层状态；
   * 真实媒体库筛选仍由 `FilterQuery` / `TagQueryService` 负责。
   */
  List<String> get _resultTitles {
    final selectedPrimary =
        _selectedGroupTagIds['folder.primary']?.contains(_primary.id) ?? false;
    if (!selectedPrimary) {
      return const <String>[];
    }
    final childIds = _selectedGroupTagIds['folder.child'] ?? const <String>{};
    if (childIds.isEmpty) {
      return const <String>[
        'Alpha Default Video',
        'Child01 Video',
        'Child02 Video',
      ];
    }
    final childId = childIds.first;
    final child = _children.firstWhere(
      (item) => item.id == childId,
      orElse: () => _children.first,
    );
    return ['${child.displayName ?? child.name} Video'];
  }

  /**
   * 测试用的一级 / 二级互斥选择回调。
   *
   * 这里不复制筛选引擎，只维护右侧面板需要的选中态，避免 smoke test 扩大到查询语义。
   */
  void _selectPrimaryChild(TagItem primary, TagItem? child) {
    setState(() {
      _selectedGroupTagIds['folder.primary'] = {primary.id};
      _selectedGroupTagIds['folder.child'] =
          child == null ? <String>{} : <String>{child.id};
    });
  }

  /**
   * 从“全部二级标签”页签直接选择二级标签。
   *
   * 测试宿主将其解释为当前一级 Alpha 下的互斥二级选择，避免引入真实查询引擎。
   */
  void _toggleSecondaryTag(TagItem child) {
    setState(() {
      _selectedGroupTagIds['folder.primary'] = {_primary.id};
      _selectedGroupTagIds['folder.child'] = {child.id};
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = [
      TagGroup(id: 'folder.primary', name: 'folder.primary', items: [_primary]),
      TagGroup(id: 'folder.child', name: 'folder.child', items: _children),
    ];
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 520,
          height: 820,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: const Color(0xfff8fafc),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final title in _resultTitles)
                      Text(title, key: LibrarySmokeKeys.tagResult(title)),
                  ],
                ),
              ),
              Expanded(
                child: _TagDiscoveryZone(
                  tagGroups: groups,
                  resultCounts: {
                    _primary.id: _primary.usageCount,
                    for (final child in _children) child.id: child.usageCount,
                  },
                  favoriteTags: const [],
                  selectedTags: const {},
                  selectedChildTags: const {},
                  selectedGroupTagIds: _selectedGroupTagIds,
                  excludedTagIds: const {},
                  childParentTag: null,
                  childTags: const [],
                  childTagItemsByParent: {_primary.id: _children},
                  favoriteCount: 0,
                  showFavoritesOnly: false,
                  dense: false,
                  onFavoritesToggle: () {},
                  onTagToggle: (_) {},
                  onChildTagToggle: (_) {},
                  onGroupTagToggle: _toggleSecondaryTag,
                  onFolderPrimaryChildSelected: _selectPrimaryChild,
                  onGroupTagExcludeToggle: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalFolderCard extends StatelessWidget {
  const _LocalFolderCard({required this.path, required this.onOpen});

  final String path;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: LibrarySmokeSemantics.localFolder(path),
      value: path,
      child: Material(
        key: LibrarySmokeKeys.localFolder(path),
        color: _appPanel,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              border: Border.all(color: _appBorder),
              borderRadius: BorderRadius.circular(8),
              boxShadow: _appSoftShadow,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.folder_rounded,
                    size: 58, color: _appAccentViolet),
                const SizedBox(height: 16),
                Text(
                  p.basename(path),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _appText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalFolderRow extends StatelessWidget {
  const _LocalFolderRow({required this.path, required this.onOpen});

  final String path;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: LibrarySmokeSemantics.localFolder(path),
      value: path,
      child: Material(
        key: LibrarySmokeKeys.localFolder(path),
        color: _appPanel,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: _appBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_rounded,
                    color: _appAccentViolet, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    p.basename(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _appText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: _appTextMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
