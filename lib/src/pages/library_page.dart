part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放硬件解码设置控件，负责把高影响解码切换收口到确认弹窗之后。
 */
class PlaybackDecoderDropdown extends StatefulWidget {
  const PlaybackDecoderDropdown({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  /** 当前已确认并可传给播放器的播放设置。 */
  final PlaybackSettings settings;

  /** 用户确认切换后回传新的播放设置，由外层负责持久化。 */
  final Future<void> Function(PlaybackSettings settings) onChanged;

  @override
  State<PlaybackDecoderDropdown> createState() =>
      _PlaybackDecoderDropdownState();
}

class _PlaybackDecoderDropdownState extends State<PlaybackDecoderDropdown> {
  late PlaybackSettings _settings = widget.settings;
  /** 具体后端默认折叠；当前已使用高级值时自动展开，避免隐藏真实配置。 */
  late bool _showAdvanced =
      !PlaybackSettings.commonDecoderOptions.contains(widget.settings.hwdec);

  /** 下拉框重建版本，用于取消确认后清理 `FormField` 的内部临时选中态。 */
  var _fieldRevision = 0;

  @override
  void didUpdateWidget(covariant PlaybackDecoderDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.hwdec != widget.settings.hwdec ||
        oldWidget.settings.resumeBehavior != widget.settings.resumeBehavior) {
      // 解码控件必须同步保留外层刚修改的继续观看策略，避免随后切换解码时用旧副本覆盖它。
      _settings = widget.settings;
    }
  }

  /**
   * 只在用户确认后写入解码设置，取消时恢复下拉框显示的旧值。
   */
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
      setState(() => _fieldRevision++);
      return;
    }
    final next = _settings.copyWith(hwdec: value);
    setState(() {
      _settings = next;
      _fieldRevision++;
    });
    await widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final commonValue =
        PlaybackSettings.commonDecoderOptions.contains(_settings.hwdec)
            ? _settings.hwdec
            : null;
    final advancedOptions = PlaybackSettings.decoderOptions
        .where(
            (option) => !PlaybackSettings.commonDecoderOptions.contains(option))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          // 取消确认弹窗时设置值可能不变，revision 让表单字段丢弃内部临时选中态。
          key: ValueKey('common:${_settings.hwdec}:$_fieldRevision'),
          initialValue: commonValue,
          hint: Text(
            commonValue == null ? '当前使用高级后端' : '选择播放解码策略',
          ),
          decoration: const InputDecoration(
            labelText: '播放解码策略',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final option in PlaybackSettings.commonDecoderOptions)
              DropdownMenuItem(
                value: option,
                child: Text(PlaybackSettings.commonLabelFor(option)),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              _changeDecoder(value);
            }
          },
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          initiallyExpanded: _showAdvanced,
          onExpansionChanged: (expanded) => _showAdvanced = expanded,
          tilePadding: EdgeInsets.zero,
          title: const Text(
            '高级选项',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text('仅在排查特定显卡或驱动兼容问题时选择具体后端'),
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('advanced:${_settings.hwdec}:$_fieldRevision'),
              initialValue: advancedOptions.contains(_settings.hwdec)
                  ? _settings.hwdec
                  : null,
              decoration: const InputDecoration(
                labelText: '具体解码后端',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final option in advancedOptions)
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
      ],
    );
  }
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

  /** 更新单个快捷键；发生冲突时交换两个功能的按键，保证绑定始终唯一。 */
  Future<void> _changeShortcut(
    PlayerShortcutAction action,
    String key,
  ) async {
    final shortcuts = Map<PlayerShortcutAction, String>.of(_settings.shortcuts);
    final oldKey = shortcuts[action]!;
    PlayerShortcutAction? conflict;
    for (final entry in shortcuts.entries) {
      if (entry.key != action && entry.value == key) {
        conflict = entry.key;
        break;
      }
    }
    shortcuts[action] = key;
    if (conflict != null) shortcuts[conflict] = oldKey;
    final next = _settings.copyWith(shortcuts: Map.unmodifiable(shortcuts));
    setState(() => _settings = next);
    await widget.onPlaybackSettingsChanged(next);
  }

  /** 恢复项目默认快捷键，并立即持久化。 */
  Future<void> _resetShortcuts() async {
    final next = _settings.copyWith(
      shortcuts: PlaybackSettings.defaultShortcuts,
    );
    setState(() => _settings = next);
    await widget.onPlaybackSettingsChanged(next);
  }

  /** 预览全屏队列交互参数；滑杆松开时由调用方统一持久化。 */
  void _previewFullscreenQueueSettings({
    int? edgeWidth,
    int? hideDelayMs,
  }) {
    setState(() {
      _settings = _settings.copyWith(
        fullscreenQueueEdgeWidth: edgeWidth,
        fullscreenQueueHideDelayMs: hideDelayMs,
      );
    });
  }

  /** 将当前全屏队列交互参数写入现有播放设置文件。 */
  Future<void> _saveFullscreenQueueSettings() async {
    await widget.onPlaybackSettingsChanged(_settings);
  }

  /** 仅恢复全屏队列交互参数，不触碰解码、快捷键或继续观看设置。 */
  Future<void> _resetFullscreenQueueSettings() async {
    final next = _settings.resetFullscreenQueueInteraction();
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
          TextButton.icon(
            key: const ValueKey('settings.refreshCacheStats'),
            style: TextButton.styleFrom(foregroundColor: _appText),
            onPressed: _refreshStats,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('刷新统计'),
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
                  PlaybackDecoderDropdown(
                    settings: _settings,
                    onChanged: (settings) async {
                      setState(() => _settings = settings);
                      await widget.onPlaybackSettingsChanged(settings);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            key: const ValueKey('settings.fullscreenQueue.card'),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '全屏播放列表',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        key: const ValueKey('settings.fullscreenQueue.reset'),
                        onPressed: _resetFullscreenQueueSettings,
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('恢复默认'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '鼠标移到屏幕右侧边缘时展开，离开列表范围后自动隐藏。',
                    style: TextStyle(color: _appTextMuted),
                  ),
                  const SizedBox(height: 16),
                  Text('边缘热区宽度：${_settings.fullscreenQueueEdgeWidth}px'),
                  Slider(
                    key: const ValueKey('settings.fullscreenQueue.edgeWidth'),
                    min: 4,
                    max: 40,
                    divisions: 18,
                    value: _settings.fullscreenQueueEdgeWidth.toDouble(),
                    label: '${_settings.fullscreenQueueEdgeWidth}px',
                    onChanged: (value) => _previewFullscreenQueueSettings(
                      edgeWidth: value.round(),
                    ),
                    onChangeEnd: (_) {
                      unawaited(_saveFullscreenQueueSettings());
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '自动隐藏延迟：${_settings.fullscreenQueueHideDelayMs}ms',
                  ),
                  Slider(
                    key: const ValueKey('settings.fullscreenQueue.hideDelay'),
                    min: 0,
                    max: 1000,
                    divisions: 20,
                    value: _settings.fullscreenQueueHideDelayMs.toDouble(),
                    label: '${_settings.fullscreenQueueHideDelayMs}ms',
                    onChanged: (value) => _previewFullscreenQueueSettings(
                      hideDelayMs: value.round(),
                    ),
                    onChangeEnd: (_) {
                      unawaited(_saveFullscreenQueueSettings());
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('播放器快捷键',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                          SizedBox(height: 6),
                          Text('修改后立即生效；选择已占用按键时会自动交换两个功能。',
                              style: TextStyle(color: _appTextMuted)),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('settings.shortcuts.reset'),
                      onPressed: _resetShortcuts,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('恢复默认'),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 14,
                    runSpacing: 12,
                    children: [
                      for (final action in PlayerShortcutAction.values)
                        SizedBox(
                          width: 310,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(
                              'settings.shortcut.${action.name}.'
                              '${_settings.shortcuts[action]}',
                            ),
                            initialValue: _settings.shortcuts[action],
                            decoration: InputDecoration(
                              labelText:
                                  PlaybackSettings.shortcutActionLabel(action),
                            ),
                            items: [
                              for (final key
                                  in PlaybackSettings.shortcutKeyOptions)
                                DropdownMenuItem(
                                  value: key,
                                  child: Text(
                                    PlaybackSettings.shortcutKeyLabel(key),
                                  ),
                                ),
                            ],
                            onChanged: (key) {
                              if (key != null) _changeShortcut(action, key);
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.fullscreen_exit_rounded),
                    title: Text('退出全屏'),
                    subtitle: Text('固定安全快捷键，不可修改'),
                    trailing: Chip(label: Text('Esc')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '继续观看',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '打开有未完成进度的视频时，默认执行以下操作。',
                    style: TextStyle(color: _appTextMuted),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<PlaybackResumeBehavior>(
                    key: const ValueKey('settings.resumeBehavior'),
                    initialValue: _settings.resumeBehavior,
                    decoration: const InputDecoration(
                      labelText: '默认打开行为',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final behavior in PlaybackResumeBehavior.values)
                        DropdownMenuItem(
                          value: behavior,
                          child:
                              Text(PlaybackSettings.resumeLabelFor(behavior)),
                        ),
                    ],
                    onChanged: (behavior) async {
                      if (behavior == null) {
                        return;
                      }
                      final next = _settings.copyWith(resumeBehavior: behavior);
                      setState(() => _settings = next);
                      await widget.onPlaybackSettingsChanged(next);
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
                          label: '失败',
                          value: _formatCount(stats.errors),
                        ),
                        _SettingsStatLine(
                          label: '活动任务',
                          value: '${stats.active} / ${stats.maxConcurrent}',
                        ),
                        _SettingsStatLine(
                          label: '排队任务',
                          value: _formatCount(stats.queued),
                        ),
                        _SettingsStatLine(
                          label: '后台请求',
                          value: _formatCount(stats.pendingBackgroundRequests),
                        ),
                        _SettingsStatLine(
                          label: '平均耗时',
                          value: '${stats.averageMs} ms',
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

  /** 继续观看结果，只展示具有有效未完成进度的视频。 */
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
  PlaybackSnapshotWriteQueue? _playbackSnapshotQueue;
  ThumbnailService? _thumbnailService;
  MediaDetailsService? _libraryMediaDetailsService;
  PlaybackSettings _playbackSettings = PlaybackSettings.defaults;
  final _filterStateSource = FilterStateSource();
  final _countRefreshCoordinator = LibraryCountRefreshCoordinator();
  final _searchController = TextEditingController();
  /**
   * 主搜索框焦点节点。
   *
   * `Ctrl+K`、真实键盘输入和桌面自动化都必须落到同一个 EditableText，
   * 否则搜索文字不会进入 controller，也就不会触发 `onChanged` 筛选链路。
   */
  final _searchFocusNode = FocusNode(debugLabel: 'library-search-field');
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

  /** 播放器会话内最近使用的 manual 标签，只保留轻量内存顺序。 */
  final List<String> _recentPlayerManualTags = <String>[];

  /** 播放器内单条修改延后到返回媒体库时刷新可见结果，不刷新全库计数。 */
  var _playerScopedLibraryDataChanged = false;
  /** 播放器内 relink 会改变 folder 标签，需要在返回后低频刷新标签计数。 */
  var _playerScopedNeedsCountRefresh = false;

  var _isRefreshingVideos = false;

  var _isRefreshingCounts = false;

  var _libraryDataRevision = 0;
  var _showFavoritesOnly = false;
  var _isScanning = false;
  /** debug 扫描帧采样器；发布构建始终为 null。 */
  LibraryScanUiDiagnostics? _activeScanUiDiagnostics;
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
    HardwareKeyboard.instance.addHandler(_handleGlobalSearchShortcut);
    _searchController.addListener(_handleSearchControllerChanged);
    _load();
  }

  @override
  void dispose() {
    unawaited(_playbackSnapshotQueue?.dispose());
    _libraryMediaDetailsService?.dispose();
    _activeScanUiDiagnostics?.abort();
    HardwareKeyboard.instance.removeHandler(_handleGlobalSearchShortcut);
    _searchController.removeListener(_handleSearchControllerChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _countRefreshCoordinator.dispose();
    super.dispose();
  }

  /**
   * 在媒体库页面处于最上层时稳定处理 Ctrl+K。
   *
   * Windows 真实窗口中焦点可能停在页面容器而不进入局部 Shortcuts 焦点链，
   * 因此页面生命周期内补充全局键盘处理；弹窗或播放器路由位于上层时不抢焦点。
   */
  bool _handleGlobalSearchShortcut(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyK ||
        !HardwareKeyboard.instance.isControlPressed ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    _focusSearchField();
    return true;
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
      _mutateFilters(() {}, refreshCounts: false);
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

  /**
   * 聚焦主搜索框并选中已有关键字。
   *
   * 该方法只处理焦点，不直接触发筛选；真实键盘或自动化输入随后写入
   * `TextEditingController`，再由统一的监听链路刷新结果。
   */
  void _focusSearchField() {
    _searchFocusNode.requestFocus();
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
    // Windows 全局快捷键可能与本帧的页面 Focus 重建竞争；下一帧再次确认焦点，
    // 让真实键盘和自动化输入稳定落到同一个 EditableText。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _searchFocusNode.requestFocus();
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
    });
  }

  Future<void> _load() async {
    final diagnostics = kDebugMode ? LibraryLoadDiagnostics() : null;
    final startupWatch = Stopwatch()..start();
    final store = await LibraryStore.load(diagnostics: diagnostics);
    final thumbnailService = diagnostics == null
        ? await ThumbnailService.create()
        : await diagnostics.measureAsync(
            'startup.thumbnail_service_create',
            ThumbnailService.create,
          );
    final playbackSettings = diagnostics == null
        ? await PlaybackSettings.load()
        : await diagnostics.measureAsync(
            'startup.playback_settings_load',
            PlaybackSettings.load,
          );
    final sortPreferences = diagnostics == null
        ? await LibrarySortPreferences.load()
        : await diagnostics.measureAsync(
            'startup.sort_preferences_load',
            LibrarySortPreferences.load,
          );
    if (!mounted) {
      await store.close();
      return;
    }
    _playbackSnapshotQueue = PlaybackSnapshotWriteQueue(
      writer: (snapshot) async {
        snapshot.item
          ..playbackPosition = snapshot.position
          ..playbackDuration = snapshot.duration
          ..playbackCompleted = snapshot.completed
          ..playbackPositionUpdatedAt = snapshot.updatedAt
          ..lastPlayedAt = snapshot.updatedAt;
        await store.upsertVideo(snapshot.item);
      },
    );
    final firstFrameWatch = Stopwatch()..start();
    void applyHydratedState() => setState(() {
          _sortMode = sortPreferences.mode;
          _sortDirection = sortPreferences.direction;
          _store = store;
          _thumbnailService = thumbnailService;
          _playbackSettings = playbackSettings;
          _lastObservedSearchText = _searchController.text;
          _filterState = _buildImmediateFilterState(store);
          _visibleResultCounts = _fallbackResultCounts(store);
          _stableTagCounts = const <String, int>{};
        });
    if (diagnostics == null) {
      applyHydratedState();
    } else {
      diagnostics.measureSync(
        'ui.hydrated_state_prepare',
        applyHydratedState,
      );
      unawaited(_writeDebugStartupDiagnostics(
        diagnostics,
        startupWatch.elapsed,
        marker: 'hydrated_state_ready',
      ));
    }
    // 首帧只消费 SQLite 已恢复的对象和持久化 usageCount；目录扫描与全库计数不得阻塞首屏。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _store != store) {
        return;
      }
      firstFrameWatch.stop();
      if (diagnostics != null) {
        diagnostics.record(
            'ui.first_frame_build_and_layout', firstFrameWatch.elapsed);
        unawaited(_writeDebugStartupDiagnostics(
          diagnostics,
          startupWatch.elapsed,
          marker: 'first_frame_ready',
        ));
      }
      _scheduleFilterRefresh();
      _scheduleInitialStableTagCounts(store);
      unawaited(_promptForNewVideos(store));
    });
  }

  /**
   * 把 debug 启动阶段写到系统临时目录；仅包含耗时、数量和完成标记。
   */
  Future<void> _writeDebugStartupDiagnostics(
    LibraryLoadDiagnostics diagnostics,
    Duration totalElapsed, {
    required String marker,
  }) async {
    try {
      final file = File(p.join(
        Directory.systemTemp.path,
        'local_tag_player_startup_diagnostics.json',
      ));
      await file.writeAsString(jsonEncode(<String, Object?>{
        'marker': marker,
        'totalMs': double.parse(
          (totalElapsed.inMicroseconds / 1000).toStringAsFixed(3),
        ),
        ...diagnostics.toJson(),
      }));
    } catch (_) {
      // debug 诊断写入失败不能阻塞媒体库首帧。
    }
  }

  /** 在首帧之后的空闲窗口刷新稳定标签计数，过期页面结果会被丢弃。 */
  void _scheduleInitialStableTagCounts(LibraryStore store) {
    _countRefreshCoordinator.schedule(
      query: const FilterQuery(),
      compute: store.resultCounts,
      isStillCurrent: (_) => mounted && _store == store,
      onComplete: (counts) {
        if (!mounted || _store != store) {
          return;
        }
        setState(() => _stableTagCounts = counts);
      },
    );
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
    await _scan(() => _store!.addRootAndScanWithChanges(path));
  }

  Future<void> _rescan() async {
    if (_store == null) {
      return;
    }
    await _scan(_store!.scanWithChanges);
  }

  Future<void> _scan(Future<LibraryScanCommitResult> Function() action) async {
    if (_isScanning) {
      return;
    }
    _activeScanUiDiagnostics?.abort();
    final diagnostics = kDebugMode ? LibraryScanUiDiagnostics() : null;
    diagnostics?.start();
    _activeScanUiDiagnostics = diagnostics;
    var diagnosticsWillFinish = false;
    setState(() => _isScanning = true);
    try {
      final actionWatch = Stopwatch()..start();
      final result = await action();
      actionWatch.stop();
      diagnostics?.recordStage(
        'scan.backend_and_commit',
        actionWatch.elapsed,
        itemCount: result.changedVideos.length,
      );
      if (!mounted) {
        return;
      }
      if (result.cancelled) {
        return;
      }
      // 只为新增或内容变化项目进入缓存队列，避免每次扫描重新排队整个媒体库。
      _thumbnailService?.prefetchAll(result.probeCandidates);
      _startLibraryMediaProbes(result);
      diagnostics?.markPostApply();
      final applyWatch = Stopwatch()..start();
      _applyLibraryScanDelta(result);
      applyWatch.stop();
      diagnostics?.recordStage(
        'ui.delta_schedule',
        applyWatch.elapsed,
        itemCount: result.changedVideos.length,
      );
      if (diagnostics != null) {
        diagnosticsWillFinish = true;
        unawaited(diagnostics.finish(result).whenComplete(() {
          if (identical(_activeScanUiDiagnostics, diagnostics)) {
            _activeScanUiDiagnostics = null;
          }
        }));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('扫描完成：新增 ${result.addedCount}，修改 ${result.modifiedCount}，'
                    '移动 ${result.relinkedCount}，缺失 ${result.missingCount}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\u626b\u63cf\u5931\u8d25\uff1a$error')),
      );
    } finally {
      if (!diagnosticsWillFinish) {
        diagnostics?.abort();
        if (identical(_activeScanUiDiagnostics, diagnostics)) {
          _activeScanUiDiagnostics = null;
        }
      }
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  /**
   * 仅把本轮新增或内容变化项目送入串行媒体探测队列。
   *
   * 新扫描会先 dispose 旧服务并取消其 generation；回调还会校验 store 与 fingerprint，
   * 防止旧文件结果覆盖新内容。SQLite 写入继续由 Dart Repository 完成。
   */
  void _startLibraryMediaProbes(LibraryScanCommitResult result) {
    _libraryMediaDetailsService?.dispose();
    _libraryMediaDetailsService = null;
    final store = _store;
    if (store == null || result.probeCandidates.isEmpty) {
      return;
    }
    final service = MediaDetailsService(
      onUpdated: (item, details, fingerprint) async {
        if (_store != store || item.mediaFingerprint != fingerprint) {
          return;
        }
        item.mediaDetails = details;
        await store.upsertVideo(item);
      },
    );
    _libraryMediaDetailsService = service;
    for (final item in result.probeCandidates) {
      // MediaDetailsService 内部串行执行并用 generation 丢弃过期回调，不在 UI 线程等待。
      unawaited(service.detailsFor(item));
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

  /** 使用扫描差量替换已缓存结果中的变化视频。 */
  FilterState _computeFilterStateFromDelta(
    LibraryStore store,
    FilterQuery query,
    Iterable<VideoItem> changedVideos,
  ) {
    final watch = Stopwatch()..start();
    _filterStateSource.configure(
      engine: TagQueryService(
        videos: store.videos.values,
        tagContext: store.tagQueryContext,
      ),
      totalCount: store.videos.length,
      sourceKey: _libraryDataRevision,
      sortKey: (_sortMode, _sortDirection),
      sortVideos: (videos) => sortedLibraryVideos(
        videos,
        sortMode: _sortMode,
        sortDirection: _sortDirection,
      ),
    );
    final state = _filterStateSource.applyVideoDelta(query, changedVideos);
    watch.stop();
    _activeScanUiDiagnostics?.recordStage(
      'ui.filter_delta_apply',
      watch.elapsed,
      itemCount: changedVideos.length,
    );
    return state;
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

  /**
   * 修改筛选条件并刷新当前可见结果。
   *
   * 高频交互（标签点击、搜索输入）默认只刷新视频列表，标签计数这类重任务
   * 只在库结构变化、扫描、标签管理返回等低频路径显式开启，避免大媒体库下点击卡顿。
   */
  void _mutateFilters(
    VoidCallback mutation, {
    bool refreshCounts = false,
  }) {
    setState(() {
      _resultMode = _LibraryResultMode.library;
      mutation();
    });
    _scheduleFilterRefresh(refreshCounts: refreshCounts);
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
    _scheduleFilterRefresh();
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
   * 从侧栏移除 root，并删除仅受该 root 管理的数据库记录与缩略图缓存。
   *
   * 本地视频文件保持不动；仍被其它重叠 root 覆盖的记录由 Store 保留。
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
    final removedVideos = await store.removeRoot(root);
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
    // 数据库提交后立即刷新总量；大量 JPEG 清理留在低优先级异步阶段，不能阻塞主界面。
    final thumbnailService = _thumbnailService;
    if (thumbnailService != null) {
      unawaited(thumbnailService.deleteThumbnailsFor(removedVideos));
    }
  }

  /**
   * 清理最近播放记录。
   *
   * 该动作清空继续观看状态，但不删除视频、收藏或标签。
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
      _resetContinueWatchingState(item);
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
    _resetContinueWatchingState(item);
    await store.upsertVideo(item);
    if (!mounted) {
      return;
    }
    setState(() => _selectedRecentPathKeys.remove(TagRules.pathKey(item.path)));
    _markLibraryDataChanged();
  }

  /** 清空单条稳定播放快照；videoId 和其它用户维护数据保持不变。 */
  void _resetContinueWatchingState(VideoItem item) {
    item
      ..lastPlayedAt = null
      ..playbackPosition = Duration.zero
      ..playbackDuration = Duration.zero
      ..playbackCompleted = false
      ..playbackPositionUpdatedAt = null;
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
      // 数据变化后先回退到持久化 usageCount，精确计数由延后刷新任务更新。
      _stableTagCounts = const <String, int>{};
    }
    _scheduleFilterRefresh(refreshCounts: true);
  }

  /**
   * 把扫描层输出的不可变差量应用到当前界面。
   *
   * 主结果列表只重新评估变化的 stable `videoId`；路径或 folder 标签
   * 可能影响本地目录与侧边栏，因此只定向失效这两类派生缓存。
   */
  void _applyLibraryScanDelta(LibraryScanCommitResult result) {
    if (result.changedVideos.isEmpty) {
      // 零差量不得提升 revision 或失效 folder 侧边栏，否则每次点击重新扫描
      // 都会无意义地重算整个媒体库。
      return;
    }
    _libraryDataRevision += 1;
    _tagGroupsCacheKey = null;
    _localEntryCacheKey = null;
    _localEntryCacheByKey.clear();
    if (result.changedVideos.any((item) => item.lastPlayedAt != null)) {
      _recentVideoCacheKey = null;
    }
    if (result.changedVideos.any((item) => item.isFavorite)) {
      _favoriteVideoCacheKey = null;
    }
    _stableTagCounts = const <String, int>{};
    _scheduleFilterRefresh(
      refreshCounts: true,
      changedVideos: result.changedVideos,
    );
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
      store.videos.values.where(videoIsContinueWatching),
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

  void _scheduleFilterRefresh({
    bool refreshCounts = false,
    Iterable<VideoItem>? changedVideos,
  }) {
    final store = _store;
    if (store == null) {
      return;
    }
    final revision = ++_filterRevision;
    if (!refreshCounts) {
      _countRefreshCoordinator.cancelPending();
    }
    final query = _currentFilterQuery();
    Future<void>.delayed(Duration.zero, () {
      if (!mounted || revision != _filterRevision || _store != store) {
        return;
      }
      final nextState = changedVideos == null
          ? _computeFilterState(store, query)
          : _computeFilterStateFromDelta(store, query, changedVideos);
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
      _countRefreshCoordinator.schedule(
        query: query,
        compute: store.resultCounts,
        isStillCurrent: (_) =>
            mounted && revision == _filterRevision && _store == store,
        onComplete: (nextCounts) {
          setState(() {
            _visibleResultCounts = nextCounts;
            _isRefreshingCounts = false;
          });
        },
      );
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
    final rebuildWatch = Stopwatch()..start();
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
    rebuildWatch.stop();
    _activeScanUiDiagnostics?.recordStage(
      'ui.folder_sidebar_rebuild',
      rebuildWatch.elapsed,
      itemCount: store.videos.length,
    );
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
    final missingCount =
        store.videos.values.where((item) => item.isMissing).length;
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
        missingCount: missingCount,
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
        onOpenMissingRelink: _openMissingRelink,
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
              _LibraryResultMode.recent => '继续观看',
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
                    onDelete: _requestDeleteVideo,
                  ),
                _LibraryResultMode.recent => videos.isEmpty
                    ? _EmptyState(
                        hasLibrary: store.videos.isNotEmpty,
                        message: '当前没有未完成的观看记录',
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
                        onDeleteVideo: _requestDeleteVideo,
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
                        onDelete: _requestDeleteVideo,
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
        searchFocusNode: _searchFocusNode,
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

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            const _FocusLibrarySearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _FocusLibrarySearchIntent: CallbackAction<_FocusLibrarySearchIntent>(
            onInvoke: (_) {
              _focusSearchField();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: _appBackground,
            body: LayoutBuilder(
              builder: (context, constraints) {
                final layoutSize =
                    LayoutBreakpoints.fromWidth(constraints.maxWidth);
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
          ),
        ),
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
                            final removedVideos = await store.removeRoot(root);
                            if (!mounted || !dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop();
                            _markLibraryDataChanged();
                            final thumbnailService = _thumbnailService;
                            if (thumbnailService != null) {
                              unawaited(thumbnailService
                                  .deleteThumbnailsFor(removedVideos));
                            }
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

  /**
   * 打开缺失视频管理页；返回后只在确有 relink 时刷新派生缓存与标签计数。
   */
  Future<void> _openMissingRelink() async {
    final store = _store;
    if (store == null) {
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      _smoothRoute<bool>(MissingRelinkPage(store: store)),
    );
    if (changed == true && mounted) {
      setState(() {
        _invalidateDerivedCaches();
        _stableTagCounts = store.resultCounts(const FilterQuery());
      });
      _scheduleFilterRefresh(refreshCounts: true);
    }
  }

  Future<bool?> _confirmRemoveRoot(String root) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('\u79fb\u9664\u76ee\u5f55'),
        content: Text(
          '将从媒体库移除该目录，并删除仅属于该目录的视频数据库记录、标签关系、'
          '收藏、播放进度、媒体详情和缩略图缓存。\n\n'
          '不会删除本地视频文件；仍被其它媒体库目录覆盖的视频会保留。\n\n$root',
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
    final compatibility = PlayerHardwareCompatibility.assess(
      details: item.mediaDetails,
      settings: _playbackSettings,
    );
    if (compatibility.status == HardwareDecodeCompatibilityStatus.unsupported) {
      // 预检只读取 hydration 已恢复的缓存详情；用户确认前不创建播放器或预热队列。
      final confirmed = await showPlayerHardwareDecodeWarningDialog(
        context,
        compatibility,
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    final thumbnailService = _thumbnailService!;
    final activeChildTag =
        _selectedChildTags.isEmpty ? null : _selectedChildTags.first;
    final queueTitle = _queueTitle(
      store: store,
      playlistLength: playlist.length,
    );
    // 在路由切换前把当前项附近已经生成的缩略图提升到同步内存视图，播放器队列
    // 首帧可直接复用，不需要先绘制占位底色再等待异步 Future 完成。
    final initialIndex =
        playlist.indexWhere((video) => video.path == item.path);
    final warmStart = math.max(0, initialIndex - 2);
    final warmEnd = math.min(playlist.length, initialIndex + 7);
    await Future.wait(
      playlist
          .sublist(warmStart, warmEnd)
          .where((video) => !video.isMissing)
          .map(thumbnailService.thumbnailFor),
    );
    if (!mounted) {
      return;
    }
    final wasPaused = thumbnailService.isPaused;
    thumbnailService.pause();
    _playerScopedLibraryDataChanged = false;
    _playerScopedNeedsCountRefresh = false;
    final playerDisposed = Completer<void>();
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
            onToggleFavorite: _toggleFavoriteFromPlayer,
            onEditManualTags: _editManualTagsFromPlayer,
            onRelinkMissing: _relinkMissingFromPlayer,
            onPlaybackProgressUpdated: _updatePlaybackProgress,
            onMediaDetailsUpdated: _updateMediaDetails,
            disposalCompleter: playerDisposed,
          ),
        ),
      );
    } finally {
      // 路由返回不代表 media_kit 原生线程已释放；等待完成信号再恢复后台任务。
      await playerDisposed.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );
      unawaited(_sampleMemoryAfterPlayerRelease());
      await _playbackSnapshotQueue?.flush();
      final snapshotError = _playbackSnapshotQueue?.takeLastError();
      if (snapshotError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('部分播放进度保存失败，请稍后重试')),
        );
      }
      if (!wasPaused) {
        thumbnailService.resume();
      }
    }
    if (mounted && _playerScopedLibraryDataChanged) {
      _invalidateDerivedCaches();
      _scheduleFilterRefresh(refreshCounts: _playerScopedNeedsCountRefresh);
      _playerScopedLibraryDataChanged = false;
      _playerScopedNeedsCountRefresh = false;
    }
  }

  /** 返回媒体库后分三次采样，观察原生纹理释放与 Flutter ImageCache 的衰减是否同步。 */
  Future<void> _sampleMemoryAfterPlayerRelease() async {
    await PlayerMemoryDiagnostics.logStage('library_after_release_0ms');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await PlayerMemoryDiagnostics.logStage('library_after_release_500ms');
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await PlayerMemoryDiagnostics.logStage('library_after_release_2000ms');
  }

  /** 播放器内收藏只写当前视频，返回媒体库后再做一次无计数轻刷新。 */
  Future<void> _toggleFavoriteFromPlayer(VideoItem item) async {
    item.isFavorite = !item.isFavorite;
    await _store?.upsertVideo(item);
    _playerScopedLibraryDataChanged = true;
  }

  /** 将播放位置和最近播放时间写入稳定 videoId 对应的视频记录。 */
  Future<void> _updatePlaybackProgress(
    VideoItem item,
    Duration position,
    Duration duration,
    bool completed,
  ) async {
    item.playbackPosition = position;
    if (duration > Duration.zero) {
      // 播放内核偶发的临时 0 时长不能覆盖已经持久化的可靠总时长与完成判断。
      item.playbackDuration = duration;
      item.playbackCompleted = completed;
    }
    final updatedAt = DateTime.now();
    item.playbackPositionUpdatedAt = updatedAt;
    item.lastPlayedAt = updatedAt;
    _playbackSnapshotQueue?.enqueue(PlaybackSnapshot(
      item: item,
      position: item.playbackPosition,
      duration: item.playbackDuration,
      completed: item.playbackCompleted,
      updatedAt: updatedAt,
    ));
    if (mounted) {
      _markPlaybackTimestampChanged(item);
    }
  }

  /** 播放器错误面板复用 missing 管理页的安全 picker 与 fingerprint 校验。 */
  Future<bool> _relinkMissingFromPlayer(VideoItem item) async {
    final store = _store;
    if (store == null) {
      return false;
    }
    final changed = await pickAndRelinkMissingVideo(
      context,
      store: store,
      item: item,
    );
    if (changed) {
      _playerScopedLibraryDataChanged = true;
      _playerScopedNeedsCountRefresh = true;
    }
    return changed;
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
    await _store?.deleteVideo(item.path);
    await _thumbnailService?.deleteThumbnailFor(item);
    if (mounted) {
      _markLibraryDataChanged();
    }
  }

  /**
   * 处理媒体卡片删除动作，并把磁盘文件删除保持为显式可选项。
   *
   * 数据库事务会一并删除标签关系、收藏、播放进度、媒体详情和稳定身份记录；选择仅移出
   * 媒体库时，仍位于受监控 root 的文件会在下次扫描时作为新条目重新出现。
   */
  Future<void> _requestDeleteVideo(VideoItem item) async {
    final deleteLocalFile = await _showVideoDeleteDialog(item);
    if (deleteLocalFile == null || !mounted) {
      return;
    }
    try {
      if (deleteLocalFile) {
        final file = File(item.path);
        if (await file.exists()) {
          await file.delete();
        }
      }
      await _store?.deleteVideo(item.path);
      await _thumbnailService?.deleteThumbnailFor(item);
      if (mounted) {
        _markLibraryDataChanged();
      }
    } on FileSystemException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：${error.message}')),
      );
    }
  }

  /** 返回 null 表示取消，false 表示仅删记录，true 表示同时删除本地文件。 */
  Future<bool?> _showVideoDeleteDialog(VideoItem item) {
    var deleteLocalFile = false;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('删除视频'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  '将删除数据库记录、标签关系、收藏、播放进度、媒体详情和缩略图缓存。'
                  '如果保留本地文件，它在下次扫描时可能重新加入媒体库。',
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: deleteLocalFile,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('同时删除本地视频文件'),
                  subtitle: const Text('此操作无法撤销'),
                  onChanged: (value) => setDialogState(
                    () => deleteLocalFile = value ?? false,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffc53b4d),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(deleteLocalFile),
              child: Text(deleteLocalFile ? '删除文件和记录' : '仅移出媒体库'),
            ),
          ],
        ),
      ),
    );
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
        lockedTags: editingChildTags
            ? _folderChildTagsForItem(item, childParentTag)
            : _folderTagsForItem(item),
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

  /**
   * 从播放器快速编辑单个视频的一级 manual 标签。
   *
   * folder 标签以锁定 chip 展示并在保存时重新合并；建议列表只包含未隐藏的一级 manual
   * 标签，避免把 folder/rule/filename/import/auto 来源误写成手动数据。
   */
  Future<void> _editManualTagsFromPlayer(VideoItem item) async {
    final store = _store;
    if (store == null) {
      return;
    }
    final folderTags = _folderTagsForItem(item);
    final linkedManualTags = _linkedTopLevelManualTags(store, item);
    final manualSuggestions = <String>{
      for (final tag in store.allTagItems)
        if (tag.source == TagSource.manual &&
            tag.parentId == null &&
            !tag.isHidden)
          tag.name,
    };
    final favoriteManualTags = <String>{
      for (final tag in store.allTagItems)
        if (tag.source == TagSource.manual &&
            tag.parentId == null &&
            tag.isFavorite &&
            !tag.isHidden)
          tag.name,
    };
    final initialManualTags = <String>{
      for (final tag in linkedManualTags) tag.name,
      // 兼容旧数据：只接受能解析到已知 manual 来源的兼容字段，不能把其它来源提升为 manual。
      for (final name in item.tags)
        if (manualSuggestions.any(
          (manualName) => TagRules.sameTag(manualName, name),
        ))
          name,
    };
    final updated = await showDialog<Set<String>>(
      context: context,
      builder: (_) => TagEditorDialog(
        title: '${item.title} / 手动标签',
        helperText: '只修改手动标签；文件夹标签由目录结构维护。',
        initialTags: <String>{...folderTags, ...initialManualTags},
        existingTags: manualSuggestions,
        lockedTags: folderTags,
        recentTags: _recentPlayerManualTags,
        favoriteTags: favoriteManualTags,
      ),
    );
    if (updated == null) {
      return;
    }
    final selectedManualNames = _normalizeTagSet(updated)
        .where(
          (tag) => !folderTags.any(
            (folderTag) => TagRules.sameTag(folderTag, tag),
          ),
        )
        .toSet();
    final protectedTagNames = _linkedTopLevelNonManualTagNames(store, item)
      ..addAll(folderTags);
    try {
      for (final tag in linkedManualTags) {
        if (!selectedManualNames.any(
          (selected) => TagRules.sameTag(selected, tag.name),
        )) {
          await store.batchRemoveManualTag(tag, [item]);
        }
      }
      for (final name in selectedManualNames) {
        if (linkedManualTags.any(
          (tag) => TagRules.sameTag(tag.name, name),
        )) {
          continue;
        }
        final tag = await _resolveQuickManualTag(store, name);
        await store.batchAddManualTag(tag, [item]);
      }
      // 兼容字段只重建“受保护的非 manual 来源 + 用户本次选择的 manual 标签”。
      item.tags
        ..clear()
        ..addAll(protectedTagNames)
        ..addAll(selectedManualNames);
      await store.upsertVideo(item);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新手动标签失败：$error')),
        );
      }
      return;
    }
    for (final name in selectedManualNames) {
      _recentPlayerManualTags
          .removeWhere((recent) => TagRules.sameTag(recent, name));
      _recentPlayerManualTags.insert(0, name);
    }
    if (_recentPlayerManualTags.length > 12) {
      _recentPlayerManualTags.removeRange(12, _recentPlayerManualTags.length);
    }
    _playerScopedLibraryDataChanged = true;
  }

  /** 获取当前视频已关联的非 manual 一级标签名，防止快速编辑覆盖其它来源。 */
  Set<String> _linkedTopLevelNonManualTagNames(
    LibraryStore store,
    VideoItem item,
  ) {
    final linkedIds = store.videoTagIdsByPathKey[TagRules.pathKey(item.path)] ??
        const <String>{};
    final tagNames = <String>{};
    for (final id in linkedIds) {
      final tag = store.tagsById[id];
      if (tag != null &&
          tag.source != TagSource.manual &&
          tag.parentId == null) {
        tagNames.add(tag.name);
      }
    }
    return tagNames;
  }

  /** 获取当前视频真实关联的一级 manual 标签，后续增删优先按 tagId 执行。 */
  List<TagItem> _linkedTopLevelManualTags(
    LibraryStore store,
    VideoItem item,
  ) {
    final linkedIds = store.videoTagIdsByPathKey[TagRules.pathKey(item.path)] ??
        const <String>{};
    final result = <TagItem>[];
    for (final id in linkedIds) {
      final tag = store.tagsById[id];
      if (tag != null &&
          tag.source == TagSource.manual &&
          tag.parentId == null) {
        result.add(tag);
      }
    }
    return result;
  }

  /**
   * 将新输入名称解析到稳定 manual tagId。
   *
   * 优先复用 `manual` 默认组；只有一个同名候选时复用该候选；多组同名且无默认组时创建默认组标签，
   * 避免仅按名称随机修改其它分组。
   */
  Future<TagItem> _resolveQuickManualTag(
    LibraryStore store,
    String name,
  ) async {
    final matches = [
      for (final tag in store.allTagItems)
        if (tag.source == TagSource.manual &&
            tag.parentId == null &&
            TagRules.sameTag(tag.name, name))
          tag,
    ];
    for (final tag in matches) {
      if ((tag.groupId ?? 'manual') == 'manual') {
        return tag;
      }
    }
    if (matches.length == 1) {
      return matches.single;
    }
    return store.createManualTag(name: name, groupId: 'manual');
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
