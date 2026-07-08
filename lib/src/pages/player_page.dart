part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

class _HorizontalWheelScroller extends StatelessWidget {
  const _HorizontalWheelScroller({
    required this.children,
    this.padding = EdgeInsets.zero,
    this.spacing = 0,
  });

  /**
   * 横向滚动内容，主要用于播放器队列中的二级标签筛选条。
   */
  final List<Widget> children;

  /**
   * 列表内边距，保持调用方控制与当前布局对齐。
   */
  final EdgeInsetsGeometry padding;

  /**
   * 子项之间的固定间距。
   */
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const _DesktopDragScrollBehavior(),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: children.length,
        itemBuilder: (context, index) => children[index],
        separatorBuilder: (context, index) => SizedBox(width: spacing),
      ),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.initialItem,
    required this.playlist,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.activeTags,
    required this.activeChildTag,
    required this.queueTitle,
    required this.onDeleteFile,
    required this.onToggleFavorite,
    required this.onMediaDetailsUpdated,
  });

  final VideoItem initialItem;
  final List<VideoItem> playlist;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  final List<String> activeTags;
  final String? activeChildTag;
  final String queueTitle;
  final Future<void> Function(VideoItem item) onDeleteFile;
  final Future<void> Function(VideoItem item) onToggleFavorite;
  final Future<void> Function(
          VideoItem item, MediaDetails details, String? fingerprint)
      onMediaDetailsUpdated;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  late final FocusNode _focusNode;
  late final ScrollController _queueScrollController;
  late final MediaDetailsService _detailsService;
  late final List<VideoItem> _sourcePlaylist;
  late final List<VideoItem> _queue;
  String? _selectedChildTag;
  late int _index;
  late int _selectedIndex;
  var _isOpening = false;
  var _openWorkerRunning = false;
  String? _pendingOpenPath;
  DateTime? _ignoreQueueSelectionBefore;

  static const double _queueItemExtent = 82;

  VideoItem get _currentItem => _queue[_index];

  String get _filterSummary {
    final value = widget.queueTitle.trim();
    return value.isEmpty ? '\u5168\u90e8\u89c6\u9891' : value;
  }

  String? get _activeParentTag {
    if (widget.activeTags.length != 1) {
      return null;
    }
    return widget.activeTags.first;
  }

  List<VideoItem> _playlistForChildTag(String? childTag) {
    final parent = _activeParentTag;
    if (parent == null || childTag == null) {
      return List<VideoItem>.of(_sourcePlaylist);
    }
    return _sourcePlaylist
        .where((item) => TagRules.matchesChildTag(item, parent, childTag))
        .toList();
  }

  void _setPlaylistForChildTag(String? childTag,
      {required String preferredPath}) {
    final next = _playlistForChildTag(childTag);
    _queue
      ..clear()
      ..addAll(next.isEmpty ? _sourcePlaylist : next);
    _index = _queue.indexWhere((item) => item.path == preferredPath);
    if (_index < 0) {
      _index = 0;
    }
    _selectedIndex = _index;
  }

  void _selectChildTag(String tag) {
    if (_queue.isEmpty) {
      return;
    }
    final preferredPath = _currentItem.path;
    final nextTag = _selectedChildTag == tag ? null : tag;
    setState(() {
      _selectedChildTag = nextTag;
      _setPlaylistForChildTag(nextTag, preferredPath: preferredPath);
    });
    _ensureQueueIndexVisible(_index, center: true);
    _requestOpenCurrent();
    _prefetchQueueWindow();
  }

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'player-shortcuts');
    _queueScrollController = ScrollController();
    _detailsService =
        MediaDetailsService(onUpdated: widget.onMediaDetailsUpdated);
    _sourcePlaylist = widget.playlist.isEmpty
        ? <VideoItem>[widget.initialItem]
        : List<VideoItem>.of(widget.playlist);
    _queue = <VideoItem>[];
    _selectedChildTag = widget.activeChildTag;
    _setPlaylistForChildTag(_selectedChildTag,
        preferredPath: widget.initialItem.path);
    _player = Player(
      configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
    );
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        width: 1920,
        height: 1080,
        hwdec: widget.playbackSettings.hwdec,
        enableHardwareAcceleration:
            widget.playbackSettings.hardwareDecodingEnabled,
      ),
    );
    _requestOpenCurrent();
    _prefetchQueueWindow();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        _ensureQueueIndexVisible(_index, center: true, animated: false);
      }
    });
  }

  void _ensureQueueIndexVisible(int index,
      {required bool center, bool animated = true}) {
    if (index < 0 || index >= _queue.length) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_queueScrollController.hasClients) {
        return;
      }
      final position = _queueScrollController.position;
      final viewport = position.viewportDimension;
      final baseOffset = index * _queueItemExtent;
      final targetOffset = center
          ? baseOffset - (viewport - _queueItemExtent) / 2
          : baseOffset - _queueItemExtent;
      final clampedOffset = targetOffset.clamp(
          position.minScrollExtent, position.maxScrollExtent);
      if (animated) {
        unawaited(_queueScrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 220),
          curve: _motionCurve,
        ));
      } else {
        _queueScrollController.jumpTo(clampedOffset);
      }
    });
  }

  void _prefetchQueueWindow({int radius = 5}) {
    if (_queue.isEmpty) {
      return;
    }
    final start = math.max(0, _index - radius);
    final end = math.min(_queue.length - 1, _index + radius);
    final visibleItems = <VideoItem>[];
    for (var index = start; index <= end; index++) {
      final item = _queue[index];
      visibleItems.add(item);
      unawaited(_detailsService.detailsFor(item));
    }
    widget.thumbnailService.prefetchVisible(visibleItems);
  }

  Future<void> _applyPlaybackPerformanceProfile() async {
    final options = <String, String>{
      'video-sync': 'display-resample',
      'interpolation': 'no',
      'vd-lavc-threads': '0',
      'cache': 'yes',
      'cache-pause': 'no',
      'demuxer-max-bytes': '512MiB',
      'demuxer-max-back-bytes': '128MiB',
    };
    for (final entry in options.entries) {
      await _setMpvProperty(entry.key, entry.value);
    }
  }

  Future<void> _setMpvProperty(String property, String value) async {
    try {
      final platform = _player.platform;
      if (platform == null) {
        return;
      }
      await (platform as dynamic).setProperty(property, value);
    } catch (_) {
      // 部分 mpv 构建会拒绝少数属性；诊断信息会展示实际生效值。
    }
  }

  Future<String> _getMpvProperty(String property) async {
    try {
      final platform = _player.platform;
      if (platform == null) {
        return 'unavailable';
      }
      final value = await (platform as dynamic).getProperty(property);
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? 'empty' : text;
    } catch (error) {
      return 'unavailable';
    }
  }

  void _requestOpenCurrent() {
    if (_queue.isEmpty) {
      return;
    }
    _pendingOpenPath = _currentItem.path;
    if (!_openWorkerRunning) {
      unawaited(_drainOpenRequests());
    }
  }

  Future<void> _drainOpenRequests() async {
    _openWorkerRunning = true;
    if (mounted) {
      setState(() => _isOpening = true);
    }
    var shouldContinue = false;
    try {
      while (mounted) {
        final path = _pendingOpenPath;
        if (path == null) {
          break;
        }
        _pendingOpenPath = null;
        try {
          await _applyPlaybackPerformanceProfile();
          if (!mounted) {
            return;
          }
          await _player.open(Media(path));
          if (!mounted) {
            return;
          }
          await _applyPlaybackPerformanceProfile();
        } catch (_) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    '\u89c6\u9891\u6253\u5f00\u5931\u8d25\uff0c\u53ef\u80fd\u662f\u7f16\u7801\u4e0d\u652f\u6301\u6216\u6587\u4ef6\u635f\u574f')),
          );
        }
      }
    } finally {
      _openWorkerRunning = false;
      shouldContinue = mounted && _pendingOpenPath != null;
      if (mounted && !shouldContinue) {
        setState(() => _isOpening = false);
      }
    }
    if (shouldContinue) {
      unawaited(_drainOpenRequests());
    }
  }

  void _select(int index) {
    if (index < 0 || index >= _queue.length) {
      return;
    }
    final ignoreBefore = _ignoreQueueSelectionBefore;
    if (ignoreBefore != null) {
      if (DateTime.now().isBefore(ignoreBefore) && index != _index) {
        return;
      }
      _ignoreQueueSelectionBefore = null;
    }
    setState(() => _selectedIndex = index);
    _ensureQueueIndexVisible(index, center: false);
  }

  void _moveQueueSelection(int delta, {bool center = false}) {
    if (_queue.isEmpty) {
      return;
    }
    final nextIndex = (_selectedIndex + delta).clamp(0, _queue.length - 1);
    setState(() => _selectedIndex = nextIndex);
    _ensureQueueIndexVisible(nextIndex, center: center);
  }

  void _selectQueueIndex(int index, {bool center = false}) {
    if (_queue.isEmpty) {
      return;
    }
    final nextIndex = index.clamp(0, _queue.length - 1);
    setState(() => _selectedIndex = nextIndex);
    _ensureQueueIndexVisible(nextIndex, center: center);
  }

  void _focusPlayingQueueItem() {
    if (_queue.isEmpty) {
      return;
    }
    _ensureQueueIndexVisible(_index, center: true);
  }

  void _focusSelectedQueueItem() {
    if (_queue.isEmpty) {
      return;
    }
    _ensureQueueIndexVisible(_selectedIndex, center: true);
  }

  void _jumpTo(int index, {bool ignoreFollowUpSelection = false}) {
    if (index < 0 || index >= _queue.length) {
      return;
    }
    if (ignoreFollowUpSelection) {
      _ignoreQueueSelectionBefore =
          DateTime.now().add(const Duration(milliseconds: 700));
    }
    setState(() {
      _index = index;
      _selectedIndex = index;
    });
    _ensureQueueIndexVisible(index, center: true);
    _requestOpenCurrent();
    _prefetchQueueWindow();
  }

  Future<void> _deleteSelectedFile() async {
    if (_queue.isEmpty) {
      return;
    }
    if (_selectedIndex != _index) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                '\u53ea\u80fd\u5220\u9664\u5f53\u524d\u6b63\u5728\u64ad\u653e\u4e14\u5df2\u9009\u4e2d\u7684\u89c6\u9891')),
      );
      return;
    }

    final item = _queue[_selectedIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('\u5220\u9664\u89c6\u9891\u6587\u4ef6'),
        content: Text('${item.title}\n\n${item.path}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('\u53d6\u6d88'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('\u5220\u9664'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _player.stop();
      await widget.onDeleteFile(item);
      if (!mounted) {
        return;
      }
      setState(() {
        _sourcePlaylist.removeWhere((video) => video.path == item.path);
        _queue.removeAt(_selectedIndex);
        if (_queue.isEmpty) {
          return;
        }
        if (_selectedIndex >= _queue.length) {
          _selectedIndex = _queue.length - 1;
        }
        _index = _selectedIndex;
      });
      if (_queue.isEmpty) {
        Navigator.of(context).maybePop();
        return;
      }
      _ensureQueueIndexVisible(_index, center: true);
      _requestOpenCurrent();
      _prefetchQueueWindow();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('\u5df2\u5220\u9664\u89c6\u9891\u6587\u4ef6')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                '\u5220\u9664\u5931\u8d25\uff0c\u8bf7\u68c0\u67e5\u6587\u4ef6\u6743\u9650')),
      );
    }
  }

  Future<void> _showPlayerContextMenu(TapDownDetails details) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(
          value: 'info',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.info_outline),
            title: Text('\u89c6\u9891\u4fe1\u606f'),
          ),
        ),
        PopupMenuItem(
          value: 'diagnostics',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.monitor_heart_outlined),
            title: Text('\u8bca\u65ad\u68c0\u67e5'),
          ),
        ),
      ],
    );
    if (!mounted) {
      return;
    }
    switch (action) {
      case 'info':
        await _showVideoInfoDialog();
      case 'diagnostics':
        await _showDiagnosticsDialog();
    }
  }

  Future<void> _showVideoInfoDialog() async {
    final item = _currentItem;
    final stat = await File(item.path).stat();
    final details = await _detailsService.detailsFor(item);
    if (!mounted) {
      return;
    }
    final lines = <String>[
      '\u6587\u4ef6\u540d: ${item.title}',
      '\u8def\u5f84: ${item.path}',
      '\u76ee\u5f55: ${item.folder}',
      '\u5927\u5c0f: ${_formatBytes(stat.size)}',
      '\u4fee\u6539\u65f6\u95f4: ${stat.modified}',
      '\u6807\u7b7e: ${item.tags.isEmpty ? '\u672a\u6dfb\u52a0' : (item.tags.toList()..sort()).join(', ')}',
      '\u4e8c\u7ea7\u6807\u7b7e: ${_childTagSummary(item)}',
      '\u6536\u85cf: ${item.isFavorite ? '\u662f' : '\u5426'}',
      '\u89c6\u9891: ${details.videoLabel}',
      '\u97f3\u9891: ${details.audioLabel}',
      '\u5a92\u4f53\u6307\u7eb9: ${item.mediaFingerprint ?? '\u672a\u8bfb\u53d6'}',
      '\u5a92\u4f53\u4fe1\u606f\u9519\u8bef: ${item.mediaDetailsError ?? '\u65e0'}',
      '\u7f29\u7565\u56fe\u9519\u8bef: ${item.thumbnailError ?? '\u65e0'}',
    ];
    await _showTextDialog('\u89c6\u9891\u4fe1\u606f', lines);
  }

  Future<void> _showDiagnosticsDialog() async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _PlaybackDiagnosticsDialog(
        playerPage: this,
        title: '\u64ad\u653e\u8bca\u65ad',
      ),
    );
  }

  Future<_PlaybackDiagnosticsSnapshot> _buildDiagnosticsSnapshot() async {
    final before = _player.state.position;
    final wasPlaying = _player.state.playing;
    final wasBuffering = _player.state.buffering;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final after = _player.state.position;
    final progressMs = after.inMilliseconds - before.inMilliseconds;
    final expectedMs = wasPlaying && !wasBuffering ? 900 : 0;
    final smooth = expectedMs == 0 || progressMs >= expectedMs;
    final details = await _detailsService.detailsFor(_currentItem);
    final tracks = _player.state.tracks;
    final mpv = <String, String>{};
    for (final property in const <String>[
      'hwdec-current',
      'current-vo',
      'video-codec',
      'audio-codec',
      'container-fps',
      'estimated-vf-fps',
      'display-fps',
      'video-sync',
      'interpolation',
      'avsync',
      'total-avsync-change',
      'mistimed-frame-count',
      'vo-delayed-frame-count',
      'vo-drop-frame-count',
      'decoder-frame-drop-count',
      'frame-drop-count',
      'demuxer-cache-duration',
      'cache-buffering-state',
    ]) {
      mpv[property] = await _getMpvProperty(property);
    }
    final lines = <String>[
      '\u5f53\u524d\u89c6\u9891: ${_currentItem.title}',
      '\u64ad\u653e\u4f4d\u7f6e: ${_formatDuration(after)} / ${_formatDuration(_player.state.duration)}',
      '\u64ad\u653e\u72b6\u6001: ${_player.state.playing ? '\u64ad\u653e\u4e2d' : '\u6682\u505c'}',
      '\u7f13\u51b2\u72b6\u6001: ${_player.state.buffering ? '\u7f13\u51b2\u4e2d' : '\u6b63\u5e38'}',
      '\u91c7\u6837\u63a8\u8fdb: $progressMs ms / 1200 ms',
      '\u6d41\u7545\u63a8\u65ad: ${smooth ? '\u6b63\u5e38' : '\u53ef\u80fd\u5361\u987f\u6216\u89e3\u7801\u8ddf\u4e0d\u4e0a'}',
      '\u8bbe\u7f6e\u786c\u89e3: ${widget.playbackSettings.hwdec}',
      'mpv \u5b9e\u9645\u786c\u89e3: ${mpv['hwdec-current']}',
      'mpv \u8f93\u51fa\u9a71\u52a8: ${mpv['current-vo']}',
      'mpv \u89c6\u9891\u7f16\u7801: ${mpv['video-codec']}',
      'mpv \u97f3\u9891\u7f16\u7801: ${mpv['audio-codec']}',
      'mpv \u5bb9\u5668 FPS: ${mpv['container-fps']}',
      'mpv \u4f30\u7b97\u89c6\u9891 FPS: ${mpv['estimated-vf-fps']}',
      'mpv \u663e\u793a FPS: ${mpv['display-fps']}',
      'mpv \u89c6\u9891\u540c\u6b65: ${mpv['video-sync']}',
      'mpv \u63d2\u5e27: ${mpv['interpolation']}',
      'mpv AV \u504f\u79fb: ${mpv['avsync']}',
      'mpv AV \u7d2f\u8ba1\u4fee\u6b63: ${mpv['total-avsync-change']}',
      'mpv \u65f6\u5e8f\u5f02\u5e38\u5e27: ${mpv['mistimed-frame-count']}',
      'mpv VO \u5ef6\u8fdf\u5e27: ${mpv['vo-delayed-frame-count']}',
      'mpv VO \u6389\u5e27: ${mpv['vo-drop-frame-count']}',
      'mpv \u89e3\u7801\u6389\u5e27: ${mpv['decoder-frame-drop-count']}',
      'mpv \u603b\u6389\u5e27: ${mpv['frame-drop-count']}',
      'mpv \u7f13\u5b58\u65f6\u957f: ${mpv['demuxer-cache-duration']}',
      'mpv \u7f13\u5b58\u72b6\u6001: ${mpv['cache-buffering-state']}',
      '\u89c6\u9891\u4fe1\u606f: ${details.videoLabel}',
      '\u97f3\u9891\u4fe1\u606f: ${details.audioLabel}',
      '\u5df2\u8bc6\u522b\u89c6\u9891\u8f68: ${tracks.video.length}',
      '\u5df2\u8bc6\u522b\u97f3\u9891\u8f68: ${tracks.audio.length}',
      '\u97f3\u91cf: ${_player.state.volume.toStringAsFixed(0)}',
      '\u7f29\u7565\u56fe\u961f\u5217: ${widget.thumbnailService.isPaused ? '\u5df2\u6682\u505c' : '\u8fd0\u884c\u4e2d'}',
      '\u7f29\u7565\u56fe\u6d3b\u8dc3\u4efb\u52a1: ${widget.thumbnailService.activeJobs} / ${widget.thumbnailService.maxConcurrentJobs}',
      '\u7f29\u7565\u56fe\u540e\u53f0\u4efb\u52a1: ${widget.thumbnailService.activeBackgroundJobs} / ${widget.thumbnailService.maxBackgroundJobs}',
      '\u7f29\u7565\u56fe\u6392\u961f: ${widget.thumbnailService.queuedJobs}',
      '\u8fdb\u7a0b\u5185\u5b58: ${_formatBytes(ProcessInfo.currentRss)}',
      '\u5904\u7406\u5668\u6838\u5fc3: ${Platform.numberOfProcessors}',
    ];
    return _PlaybackDiagnosticsSnapshot(
      lines: lines,
      sampledAt: DateTime.now(),
      wasPlaying: wasPlaying,
      wasBuffering: wasBuffering,
      progressMs: progressMs,
      expectedMs: expectedMs,
      smooth: smooth,
      avSync: _parseMpvNumber(mpv['avsync']),
      mistimedFrames: _parseMpvInt(mpv['mistimed-frame-count']),
      voDelayedFrames: _parseMpvInt(mpv['vo-delayed-frame-count']),
      voDroppedFrames: _parseMpvInt(mpv['vo-drop-frame-count']),
      decoderDroppedFrames: _parseMpvInt(mpv['decoder-frame-drop-count']),
      totalDroppedFrames: _parseMpvInt(mpv['frame-drop-count']),
      cacheDuration: _parseMpvNumber(mpv['demuxer-cache-duration']),
      cacheBufferingState: _parseMpvNumber(mpv['cache-buffering-state']),
    );
  }

  static double? _parseMpvNumber(String? value) {
    final text = value?.trim();
    if (text == null ||
        text.isEmpty ||
        text == 'empty' ||
        text == 'unavailable') {
      return null;
    }
    return double.tryParse(text);
  }

  static int? _parseMpvInt(String? value) {
    final number = _parseMpvNumber(value);
    return number?.round();
  }

  Future<void> _showTextDialog(String title, List<String> lines) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 680,
          child: SelectionArea(
            child: SingleChildScrollView(
              child: Text(lines.join('\n')),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('\u5173\u95ed'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 2)} ${units[unit]}';
  }

  String _childTagSummary(VideoItem item) {
    final parts = <String>[];
    for (final entry in item.childTags.entries) {
      final values = entry.value.toList()..sort();
      parts.add('${entry.key}: ${values.join(', ')}');
    }
    return parts.isEmpty ? '\u65e0' : parts.join(' / ');
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.insert &&
        HardwareKeyboard.instance.isAltPressed) {
      unawaited(widget.onToggleFavorite(_currentItem));
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_currentItem.isFavorite
                ? '\u5df2\u6dfb\u52a0\u5230\u6211\u7684\u6536\u85cf'
                : '\u5df2\u53d6\u6d88\u6536\u85cf')),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete &&
        HardwareKeyboard.instance.isControlPressed &&
        HardwareKeyboard.instance.isShiftPressed) {
      unawaited(_deleteSelectedFile());
      return KeyEventResult.handled;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _moveQueueSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveQueueSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.pageUp:
        _jumpTo(_index - 1, ignoreFollowUpSelection: true);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.pageDown:
        _jumpTo(_index + 1, ignoreFollowUpSelection: true);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _selectQueueIndex(0, center: true);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _selectQueueIndex(_queue.length - 1, center: true);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _jumpTo(_selectedIndex, ignoreFollowUpSelection: true);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.of(context).maybePop();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons == kBackMouseButton) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _pendingOpenPath = null;
    _queueScrollController.dispose();
    _focusNode.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showQueueSidebar = MediaQuery.sizeOf(context).width >= 760;
    final queueSidebar = _PlayerQueueSidebar(
      playlist: _queue,
      sourcePlaylist: _sourcePlaylist,
      playingIndex: _index,
      selectedIndex: _selectedIndex,
      scrollController: _queueScrollController,
      thumbnailService: widget.thumbnailService,
      detailsService: _detailsService,
      activeTags: widget.activeTags,
      selectedChildTag: _selectedChildTag,
      queueTitle: widget.queueTitle,
      onChildTagSelected: _selectChildTag,
      onSelect: _select,
      onPlay: _jumpTo,
      onLocatePlaying: _focusPlayingQueueItem,
      onLocateSelected: _focusSelectedQueueItem,
      onDeleteSelected: _selectedIndex == _index ? _deleteSelectedFile : null,
    );
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Listener(
        onPointerDown: _handlePointerDown,
        child: Scaffold(
          backgroundColor: const Color(0xff080b10),
          appBar: AppBar(
            toolbarHeight: 68,
            backgroundColor: const Color(0xff080b10),
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '正在播放',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xff7f8da3),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currentItem.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_index + 1} / ${_queue.length}   $_filterSummary',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff94a3b8),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: _currentItem.isFavorite ? '取消收藏' : '收藏',
                onPressed: () {
                  unawaited(widget.onToggleFavorite(_currentItem));
                  setState(() {});
                },
                icon: Icon(_currentItem.isFavorite
                    ? Icons.favorite
                    : Icons.favorite_border),
              ),
              IconButton(
                tooltip: '视频信息',
                onPressed: _showVideoInfoDialog,
                icon: const Icon(Icons.info_outline),
              ),
              if (!showQueueSidebar)
                IconButton(
                  tooltip: '播放队列',
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: const Color(0xff17191c),
                      builder: (_) => FractionallySizedBox(
                        heightFactor: 0.82,
                        child: queueSidebar,
                      ),
                    );
                  },
                  icon: const Icon(Icons.playlist_play),
                ),
            ],
          ),
          body: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xff1f2937)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 26,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onSecondaryTapDown: _showPlayerContextMenu,
                                child: Center(
                                  child: Video(controller: _controller),
                                ),
                              ),
                            ),
                            if (_isOpening)
                              const Positioned.fill(
                                child: ColoredBox(
                                  color: Color(0x66000000),
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    _PlayerContextPanel(
                      item: _currentItem,
                      queueTitle: _filterSummary,
                      index: _index,
                      total: _queue.length,
                      activeTags: widget.activeTags,
                      activeChildTag: _selectedChildTag,
                    ),
                  ],
                ),
              ),
              if (showQueueSidebar) queueSidebar,
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerContextPanel extends StatelessWidget {
  const _PlayerContextPanel({
    required this.item,
    required this.queueTitle,
    required this.index,
    required this.total,
    required this.activeTags,
    required this.activeChildTag,
  });

  final VideoItem item;
  final String queueTitle;
  final int index;
  final int total;
  final List<String> activeTags;
  final String? activeChildTag;

  @override
  Widget build(BuildContext context) {
    final tags = item.tags.toList()..sort();
    final visibleTags = [
      ...activeTags,
      if (activeChildTag != null) activeChildTag!,
      ...tags.where((tag) => !activeTags.contains(tag)).take(8),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff101722),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xff243044)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff94a3b8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 2,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                _PlayerMetaChip(
                  icon: Icons.playlist_play_rounded,
                  label: '${index + 1} / $total',
                  emphasized: true,
                ),
                _PlayerMetaChip(
                  icon: Icons.account_tree_outlined,
                  label: queueTitle,
                  emphasized: false,
                ),
                for (final tag in visibleTags)
                  _PlayerMetaChip(
                    icon: Icons.sell_outlined,
                    label: tag,
                    emphasized:
                        activeTags.contains(tag) || activeChildTag == tag,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerMetaChip extends StatelessWidget {
  const _PlayerMetaChip({
    required this.icon,
    required this.label,
    required this.emphasized,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: emphasized ? const Color(0xff312e81) : const Color(0xff17202c),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: emphasized ? const Color(0xff7c73ff) : const Color(0xff2d3a4d),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: emphasized ? Colors.white : const Color(0xff94a3b8),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: emphasized ? Colors.white : const Color(0xffcbd5e1),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackDiagnosticsSnapshot {
  const _PlaybackDiagnosticsSnapshot({
    required this.lines,
    required this.sampledAt,
    required this.wasPlaying,
    required this.wasBuffering,
    required this.progressMs,
    required this.expectedMs,
    required this.smooth,
    required this.avSync,
    required this.mistimedFrames,
    required this.voDelayedFrames,
    required this.voDroppedFrames,
    required this.decoderDroppedFrames,
    required this.totalDroppedFrames,
    required this.cacheDuration,
    required this.cacheBufferingState,
  });

  final List<String> lines;
  final DateTime sampledAt;
  final bool wasPlaying;
  final bool wasBuffering;
  final int progressMs;
  final int expectedMs;
  final bool smooth;
  final double? avSync;
  final int? mistimedFrames;
  final int? voDelayedFrames;
  final int? voDroppedFrames;
  final int? decoderDroppedFrames;
  final int? totalDroppedFrames;
  final double? cacheDuration;
  final double? cacheBufferingState;
}

class _PlaybackDiagnosticsDialog extends StatefulWidget {
  const _PlaybackDiagnosticsDialog({
    required this.playerPage,
    required this.title,
  });

  final _PlayerPageState playerPage;
  final String title;

  @override
  State<_PlaybackDiagnosticsDialog> createState() =>
      _PlaybackDiagnosticsDialogState();
}

class _PlaybackDiagnosticsDialogState
    extends State<_PlaybackDiagnosticsDialog> {
  Timer? _nextRefreshTimer;
  StreamSubscription<bool>? _playingSubscription;
  _PlaybackDiagnosticsSnapshot? _snapshot;
  _PlaybackDiagnosticsSnapshot? _previousSnapshot;
  var _sampleCount = 0;
  var _isSampling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _playingSubscription =
        widget.playerPage._player.stream.playing.listen((playing) {
      if (playing && !_isSampling) {
        _scheduleRefresh(Duration.zero);
      } else if (!playing) {
        _nextRefreshTimer?.cancel();
      }
    });
    _scheduleRefresh(Duration.zero);
  }

  @override
  void dispose() {
    _nextRefreshTimer?.cancel();
    unawaited(_playingSubscription?.cancel());
    super.dispose();
  }

  void _scheduleRefresh(Duration delay) {
    _nextRefreshTimer?.cancel();
    _nextRefreshTimer = Timer(delay, () {
      unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (_isSampling || !mounted) {
      return;
    }
    setState(() {
      _isSampling = true;
      _error = null;
    });
    try {
      final snapshot = await widget.playerPage._buildDiagnosticsSnapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _previousSnapshot = _snapshot;
        _snapshot = snapshot;
        _sampleCount++;
        _isSampling = false;
      });
      if (snapshot.wasPlaying) {
        _scheduleRefresh(const Duration(milliseconds: 250));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isSampling = false;
      });
      _scheduleRefresh(const Duration(seconds: 2));
    }
  }

  List<String> _analysisLines() {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return const ['诊断状态: 正在采集第一组样本'];
    }

    final reasons = <String>[];
    if (!snapshot.wasPlaying) {
      reasons.add('视频已暂停，诊断已停止在最后一组样本');
    }
    if (snapshot.wasBuffering) {
      reasons.add('播放器正在缓冲，优先检查磁盘读取、文件源或缓存状态');
    }
    if (!snapshot.smooth && snapshot.wasPlaying && !snapshot.wasBuffering) {
      reasons.add('播放位置推进不足，可能存在渲染阻塞、解码跟不上或 UI 线程压力');
    }
    final decoderDelta = _delta(
        snapshot.decoderDroppedFrames, _previousSnapshot?.decoderDroppedFrames);
    if (decoderDelta != null && decoderDelta > 0) {
      reasons.add('解码掉帧增加 $decoderDelta，可能是 HEVC 解码压力或硬解回退/拷贝开销');
    }
    final voDelta =
        _delta(snapshot.voDroppedFrames, _previousSnapshot?.voDroppedFrames);
    if (voDelta != null && voDelta > 0) {
      reasons.add('视频输出掉帧增加 $voDelta，可能是渲染/显示同步压力');
    }
    final delayedDelta =
        _delta(snapshot.voDelayedFrames, _previousSnapshot?.voDelayedFrames);
    if (delayedDelta != null && delayedDelta > 0) {
      reasons.add('视频输出延迟帧增加 $delayedDelta，显示链路可能跟不上');
    }
    final mistimedDelta =
        _delta(snapshot.mistimedFrames, _previousSnapshot?.mistimedFrames);
    if (mistimedDelta != null && mistimedDelta > 0) {
      reasons.add('时序异常帧增加 $mistimedDelta，可能是刷新率/同步策略不稳定');
    }
    final avSync = snapshot.avSync?.abs();
    if (avSync != null && avSync > 0.08) {
      reasons.add('AV 偏移 ${snapshot.avSync!.toStringAsFixed(3)} 秒，音画同步正在明显修正');
    }
    if (snapshot.cacheDuration != null && snapshot.cacheDuration! < 3) {
      reasons.add('缓存时长低于 3 秒，可能存在读盘或解复用供给不足');
    }
    if (snapshot.cacheBufferingState != null &&
        snapshot.cacheBufferingState! < 100) {
      reasons.add('缓存状态未满，播放器可能正在等待数据');
    }
    if (reasons.isEmpty) {
      reasons.add('未发现明显掉帧、缓冲或音画同步异常');
    }

    return <String>[
      '诊断状态: ${snapshot.wasPlaying ? '播放中持续采集' : '暂停，停止采集'}',
      '连续采样: $_sampleCount',
      '最近采样: ${_formatSampleTime(snapshot.sampledAt)}',
      '异常提示: ${reasons.join('；')}',
      '',
    ];
  }

  int? _delta(int? current, int? previous) {
    if (current == null || previous == null) {
      return null;
    }
    return current - previous;
  }

  String _formatSampleTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      ..._analysisLines(),
      if (_error != null) '诊断错误: $_error',
      ...?_snapshot?.lines,
    ];
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          if (_isSampling)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: 760,
        child: SelectionArea(
          child: SingleChildScrollView(
            child: Text(lines.join('\n')),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

/**
 * 播放器右侧的筛选结果队列，承接库页传入的 filteredVideos。
 */
class _PlayerQueueSidebar extends StatelessWidget {
  const _PlayerQueueSidebar({
    required this.playlist,
    required this.sourcePlaylist,
    required this.playingIndex,
    required this.selectedIndex,
    required this.scrollController,
    required this.thumbnailService,
    required this.detailsService,
    required this.activeTags,
    required this.selectedChildTag,
    required this.queueTitle,
    required this.onChildTagSelected,
    required this.onSelect,
    required this.onPlay,
    required this.onLocatePlaying,
    required this.onLocateSelected,
    required this.onDeleteSelected,
  });

  /**
   * 当前播放器实际消费的队列。
   */
  final List<VideoItem> playlist;

  /**
   * 原始筛选结果队列，用于子标签切换后恢复上下文。
   */
  final List<VideoItem> sourcePlaylist;

  /**
   * 正在播放的视频索引。
   */
  final int playingIndex;

  /**
   * 当前键盘或鼠标选中的队列项索引。
   */
  final int selectedIndex;

  /**
   * 播放器页持有的队列滚动控制器，用于定位当前播放或选中项。
   */
  final ScrollController scrollController;

  /**
   * 队列缩略图来源。
   */
  final ThumbnailService thumbnailService;

  /**
   * 队列媒体信息来源。
   */
  final MediaDetailsService detailsService;

  /**
   * 库页传入的当前筛选标签上下文。
   */
  final List<String> activeTags;

  /**
   * 播放器页内部选中的子标签。
   */
  final String? selectedChildTag;

  /**
   * 队列顶部显示的筛选摘要。
   */
  final String queueTitle;

  /**
   * 切换播放器页内部子标签筛选。
   */
  final ValueChanged<String> onChildTagSelected;

  /**
   * 单击队列项时更新当前选择。
   */
  final ValueChanged<int> onSelect;

  /**
   * 双击队列项时跳转播放。
   */
  final ValueChanged<int> onPlay;

  /**
   * 将右侧队列滚动回正在播放项，不改变选择或播放状态。
   */
  final VoidCallback onLocatePlaying;

  /**
   * 将右侧队列滚动回当前选中项，不改变选择或播放状态。
   */
  final VoidCallback onLocateSelected;

  /**
   * 删除当前视频的入口；为 null 时禁用。
   */
  final VoidCallback? onDeleteSelected;

  String? get _activeParentTag {
    if (activeTags.length != 1) {
      return null;
    }
    return activeTags.first;
  }

  List<String> get _childTags {
    final parent = _activeParentTag;
    if (parent == null) {
      return const <String>[];
    }
    final tags = <String>{};
    for (final item in sourcePlaylist) {
      tags.addAll(
          item.childTags[parent] ?? const <String>{TagRules.defaultAlbumTag});
    }
    return TagRules.sortedChildTags(tags);
  }

  String get _filterSummary {
    if (queueTitle.trim().isEmpty) {
      return '\u5168\u90e8\u89c6\u9891';
    }
    return queueTitle;
  }

  List<Widget> _contextPathWidgets() {
    if (activeTags.length == 1 && selectedChildTag != null) {
      return [
        _QueueContextChip(label: activeTags.first, emphasized: true),
        const Icon(Icons.chevron_right_rounded,
            size: 16, color: Color(0xff7686a0)),
        _QueueContextChip(label: selectedChildTag!, emphasized: true),
      ];
    }
    final contextChips = <String>[
      ...activeTags,
      if (selectedChildTag != null) selectedChildTag!,
    ];
    if (contextChips.isEmpty) {
      return const [_QueueContextChip(label: '全部视频')];
    }
    return [
      for (final tag in contextChips.take(5)) _QueueContextChip(label: tag),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sidebarWidth = math.min(360.0, MediaQuery.sizeOf(context).width);
    return Container(
      width: sidebarWidth,
      color: const Color(0xff0f1621),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            decoration: const BoxDecoration(
              color: Color(0xff0f1621),
              border: Border(
                left: BorderSide(color: Color(0xff243044)),
                bottom: BorderSide(color: Color(0xff243044)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: const Color(0xff312e81),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xff6d5dfc)),
                      ),
                      child: const Icon(Icons.format_list_bulleted_rounded,
                          color: Colors.white, size: 17),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '筛选结果队列',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '当前筛选（AND）',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xff8f9bad),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Tooltip(
                      message:
                          '↑/↓ 选中队列项\nEnter 播放选中\nPageUp/PageDown 切换上/下一个视频\nHome/End 跳到队首/队尾',
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.keyboard_alt_outlined,
                            size: 17, color: Colors.white54),
                      ),
                    ),
                    IconButton(
                      tooltip: '定位当前播放',
                      onPressed: onLocatePlaying,
                      icon: const Icon(Icons.my_location_rounded, size: 17),
                      color: Colors.white70,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      tooltip: '定位已选中',
                      onPressed: onLocateSelected,
                      icon: const Icon(Icons.center_focus_strong_rounded,
                          size: 17),
                      color: Colors.white70,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      tooltip: '删除当前视频',
                      onPressed: onDeleteSelected,
                      icon: const Icon(Icons.delete_outline, size: 17),
                      color: Colors.white70,
                      disabledColor: Colors.white24,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Tooltip(
                  message: _filterSummary,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xff121c2b),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xff344369)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 16,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: _contextPathWidgets(),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '已选中 ${selectedIndex + 1} / 正在播放 ${playingIndex + 1} / 共 ${playlist.length} 项',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff9aa7bb),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_activeParentTag != null)
            SizedBox(
              height: 44,
              child: _HorizontalWheelScroller(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                spacing: 8,
                children: [
                  for (final tag in _childTags)
                    _PlayerChildTagChip(
                      label: tag,
                      selected: selectedChildTag == tag,
                      onPressed: () => onChildTagSelected(tag),
                    ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                  itemExtent: 82,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(720),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  itemCount: playlist.length,
                  itemBuilder: (context, index) {
                    final item = playlist[index];
                    return _QueueListItem(
                      item: item,
                      index: index,
                      playing: index == playingIndex,
                      selected: index == selectedIndex,
                      thumbnailService: thumbnailService,
                      detailsService: detailsService,
                      onTap: () => onSelect(index),
                      onDoubleTap: () => onPlay(index),
                    );
                  },
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: AnimatedBuilder(
                    animation: scrollController,
                    builder: (context, _) {
                      final showPlaying = !_isQueueIndexVisible(playingIndex);
                      final showSelected = selectedIndex != playingIndex &&
                          !_isQueueIndexVisible(selectedIndex);
                      if (!showPlaying && !showSelected) {
                        return const SizedBox.shrink();
                      }
                      return _QueueFloatingLocator(
                        showPlaying: showPlaying,
                        showSelected: showSelected,
                        onLocatePlaying: onLocatePlaying,
                        onLocateSelected: onLocateSelected,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isQueueIndexVisible(int index) {
    if (index < 0 || index >= playlist.length) {
      return true;
    }
    if (!scrollController.hasClients) {
      return true;
    }
    final position = scrollController.position;
    final top = position.pixels;
    return playerQueueIndexIsVisible(
      index: index,
      scrollOffset: top,
      viewportExtent: position.viewportDimension,
      itemExtent: _PlayerPageState._queueItemExtent,
    );
  }
}

@visibleForTesting
bool playerQueueIndexIsVisible({
  required int index,
  required double scrollOffset,
  required double viewportExtent,
  required double itemExtent,
  double tolerance = 12,
}) {
  if (index < 0 || viewportExtent <= 0 || itemExtent <= 0) {
    return true;
  }
  final top = scrollOffset;
  final bottom = top + viewportExtent;
  final itemTop = index * itemExtent;
  final itemBottom = itemTop + itemExtent;
  return itemBottom > top + tolerance && itemTop < bottom - tolerance;
}

/**
 * 播放器队列顶部的紧凑上下文芯片，用于在播放时保留库页筛选语境。
 */
class _QueueContextChip extends StatelessWidget {
  const _QueueContextChip({
    required this.label,
    this.emphasized = false,
  });

  /**
   * 从当前父标签或子标签上下文复制出的筛选标签。
   */
  final String label;

  /**
   * 是否作为层级路径中的关键节点强调显示。
   */
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      constraints: const BoxConstraints(maxWidth: 108),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: emphasized ? const Color(0xff253861) : const Color(0xff1c2740),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
            color:
                emphasized ? const Color(0xff5c78c9) : const Color(0xff344369)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sell_outlined, size: 12, color: Color(0xffa7b4ff)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xffdbe4ff),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerChildTagChip extends StatelessWidget {
  const _PlayerChildTagChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        selected ? const Color(0xff254d7d) : const Color(0xff242832);
    final borderColor =
        selected ? const Color(0xff5d9cec) : const Color(0xff38404d);
    final textColor =
        selected ? const Color(0xffffffff) : const Color(0xffb7c0cc);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueStateBadge extends StatelessWidget {
  const _QueueStateBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 19,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueFloatingLocator extends StatelessWidget {
  const _QueueFloatingLocator({
    required this.showPlaying,
    required this.showSelected,
    required this.onLocatePlaying,
    required this.onLocateSelected,
  });

  final bool showPlaying;
  final bool showSelected;
  final VoidCallback onLocatePlaying;
  final VoidCallback onLocateSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: showPlaying || showSelected ? 1 : 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xee101722),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xff344369)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              if (showPlaying)
                _QueueLocatorButton(
                  icon: Icons.play_arrow_rounded,
                  label: '回到播放',
                  onPressed: onLocatePlaying,
                ),
              if (showSelected)
                _QueueLocatorButton(
                  icon: Icons.center_focus_strong_rounded,
                  label: '回到选中',
                  onPressed: onLocateSelected,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueLocatorButton extends StatelessWidget {
  const _QueueLocatorButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xffdbe4ff),
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _QueueListItem extends StatefulWidget {
  const _QueueListItem({
    required this.item,
    required this.index,
    required this.playing,
    required this.selected,
    required this.thumbnailService,
    required this.detailsService,
    required this.onTap,
    required this.onDoubleTap,
  });

  /**
   * 队列项对应的视频，不改变播放队列顺序。
   */
  final VideoItem item;

  /**
   * 当前项在筛选结果队列中的零基序号。
   */
  final int index;

  /**
   * 该项是否为播放器正在消费的视频。
   */
  final bool playing;

  /**
   * 该项是否为键盘或鼠标当前选中的队列项。
   */
  final bool selected;

  /**
   * 缩略图服务，仅用于队列项预览。
   */
  final ThumbnailService thumbnailService;

  /**
   * 媒体详情服务，仅用于显示编码和分辨率摘要。
   */
  final MediaDetailsService detailsService;

  /**
   * 单击队列项时只移动选择，不直接改变播放。
   */
  final VoidCallback onTap;

  /**
   * 双击队列项时切换实际播放位置。
   */
  final VoidCallback onDoubleTap;

  @override
  State<_QueueListItem> createState() => _QueueListItemState();
}

class _QueueListItemState extends State<_QueueListItem> {
  late Future<File?> _thumbnailFuture;
  late Future<MediaDetails> _detailsFuture;
  var _hovered = false;

  @override
  void initState() {
    super.initState();
    _loadItemFutures();
  }

  @override
  void didUpdateWidget(covariant _QueueListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.path != widget.item.path) {
      _loadItemFutures();
    }
  }

  void _loadItemFutures() {
    _thumbnailFuture = widget.thumbnailService.thumbnailFor(widget.item);
    _detailsFuture = widget.detailsService.detailsFor(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    final emphasis = widget.playing
        ? 3
        : widget.selected
            ? 2
            : _hovered
                ? 1
                : 0;
    final infoColor = emphasis >= 2
        ? const Color(0xffb7d3ff)
        : _hovered
            ? const Color(0xffa0aabb)
            : const Color(0xff7a8493);
    final titleColor = widget.playing
        ? const Color(0xffffffff)
        : widget.selected
            ? const Color(0xffeef2f6)
            : _hovered
                ? const Color(0xffdde4ed)
                : const Color(0xffb9c1cc);
    final backgroundColor = widget.playing
        ? const Color(0xff20385c)
        : widget.selected
            ? const Color(0xff242d3a)
            : _hovered
                ? const Color(0xff1d2530)
                : const Color(0xff151a21);
    final borderColor = widget.playing
        ? const Color(0xff7aa7ff)
        : widget.selected
            ? const Color(0xff52647d)
            : _hovered
                ? const Color(0xff3a4658)
                : const Color(0xff222936);
    final accentColor = widget.playing
        ? const Color(0xff8fb8ff)
        : widget.selected
            ? const Color(0xffa7b4ff)
            : _hovered
                ? const Color(0xff7f8da3)
                : const Color(0xff566171);
    final showHoverAction = _hovered && !widget.playing;
    final stateBadgeLabel = widget.playing
        ? '播放中'
        : widget.selected
            ? '已选中'
            : null;
    final stateBadgeIcon = widget.playing
        ? Icons.play_arrow_rounded
        : widget.selected
            ? Icons.center_focus_strong_rounded
            : null;
    final stateBadgeColor =
        widget.playing ? const Color(0xff7aa7ff) : const Color(0xffa7b4ff);
    final shadow = widget.playing
        ? const [
            BoxShadow(
              color: Color(0x550c3b7b),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ]
        : widget.selected || _hovered
            ? const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ]
            : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: _motionCurve,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor),
              boxShadow: shadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 3,
                  height: 52,
                  decoration: BoxDecoration(
                    color: widget.playing || widget.selected || _hovered
                        ? accentColor
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 5),
                SizedBox(
                  width: 88,
                  height: 50,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FutureBuilder<File?>(
                          future: _thumbnailFuture,
                          builder: (context, snapshot) {
                            final file = snapshot.data;
                            if (file != null && file.existsSync()) {
                              return Image.file(
                                file,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.low,
                                cacheWidth: 160,
                                gaplessPlayback: true,
                              );
                            }
                            return const ColoredBox(
                              color: Color(0xff242932),
                              child: Center(
                                child: Icon(Icons.movie_outlined,
                                    color: Color(0xff687282), size: 22),
                              ),
                            );
                          },
                        ),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 120),
                          opacity: showHoverAction ? 1 : 0,
                          child: const ColoredBox(
                            color: Color(0x66000000),
                            child: Center(
                              child: Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FutureBuilder<MediaDetails>(
                    future: _detailsFuture,
                    builder: (context, snapshot) {
                      final details = snapshot.data;
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 28,
                                child: Text(
                                  (widget.index + 1).toString().padLeft(2, '0'),
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: TextStyle(
                                    color: accentColor,
                                    fontSize: 11,
                                    fontWeight: emphasis >= 2
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  widget.item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: titleColor,
                                    fontSize: 12,
                                    height: 1.15,
                                    fontWeight: emphasis >= 2
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (stateBadgeLabel != null &&
                                  stateBadgeIcon != null) ...[
                                const SizedBox(width: 6),
                                _QueueStateBadge(
                                  label: stateBadgeLabel,
                                  icon: stateBadgeIcon,
                                  color: stateBadgeColor,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _detailsLine(details),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: infoColor, fontSize: 11, height: 1.1),
                          ),
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 120),
                            opacity: showHoverAction ? 1 : 0,
                            child: const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Text(
                                '双击播放',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(0xffa7b4ff),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _detailsLine(MediaDetails? details) {
    if (details == null) {
      return '\u5a92\u4f53\u4fe1\u606f\u8bfb\u53d6\u4e2d';
    }
    return '${details.videoLabel}  |  ${details.audioLabel}';
  }
}
