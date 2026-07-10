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
  late final PlayerPlaybackController _playback;
  final _openRequests = PlayerOpenRequestController();
  StreamSubscription<bool>? _completedSubscription;
  DateTime? _ignoreQueueSelectionBefore;
  String? _handledCompletedPath;
  String? _openedPath;
  var _queueEndReached = false;

  static const double _queueItemExtent = 82;

  List<VideoItem> get _sourcePlaylist => _playback.sourcePlaylist;

  List<VideoItem> get _queue => _playback.queue;

  String? get _selectedChildTag => _playback.selectedChildTag;

  int get _index => _playback.playingIndex;

  int get _selectedIndex => _playback.selectedIndex;

  VideoItem get _currentItem => _playback.currentItem;

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

  void _selectChildTag(String tag) {
    if (_queue.isEmpty) {
      return;
    }
    final preferredPath = _currentItem.path;
    setState(() {
      _queueEndReached = false;
      _playback.toggleChildTag(tag, preferredPath: preferredPath);
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
    _playback = PlayerPlaybackController(
      sourcePlaylist: widget.playlist.isEmpty
          ? <VideoItem>[widget.initialItem]
          : widget.playlist,
      activeParentTag: _activeParentTag,
      initialChildTag: widget.activeChildTag,
      initialPath: widget.initialItem.path,
    );
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
    _completedSubscription =
        _player.stream.completed.listen(_handlePlaybackCompleted);
    _requestOpenCurrent();
    _prefetchQueueWindow();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        _ensureQueueIndexVisible(_index, center: true, animated: false);
      }
    });
  }

  /**
   * 处理播放完成事件，在当前 filtered queue 内顺序进入下一条。
   *
   * media_kit 在打开新媒体时会发送 false，因此路径去重只防御同一 EOF 的重复 true；
   * 到达队尾时明确停止并提示，不默认循环到队首。
   */
  void _handlePlaybackCompleted(bool completed) {
    if (!completed) {
      _handledCompletedPath = null;
      // 用户在队尾重新播放或拖动进度后，完成提示应立即退出。
      if (mounted && _queueEndReached) {
        setState(() => _queueEndReached = false);
      }
      return;
    }
    if (!mounted || _queue.isEmpty) {
      return;
    }
    final completedPath = _currentItem.path;
    // 旧媒体在快速切换期间迟到的 EOF 不能推进新队列项。
    if (_openedPath != completedPath) {
      return;
    }
    if (_handledCompletedPath == completedPath) {
      return;
    }
    _handledCompletedPath = completedPath;
    final nextIndex = _playback.nextIndex;
    if (nextIndex == null) {
      setState(() => _queueEndReached = true);
      _showQueueEndMessage();
      return;
    }
    _jumpTo(nextIndex, ignoreFollowUpSelection: true);
  }

  /** 提示当前筛选队列已经播放完毕，避免用户误以为播放器卡住。 */
  void _showQueueEndMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已播放到当前筛选队列末尾，共 ${_queue.length} 项'),
        ),
      );
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
    if (_openRequests.request(_currentItem.path)) {
      unawaited(_drainOpenRequests());
    }
  }

  Future<void> _drainOpenRequests() async {
    if (mounted) {
      setState(_openRequests.beginDrain);
    }
    var shouldContinue = false;
    try {
      while (mounted) {
        final path = _openRequests.takePendingPath();
        if (path == null) {
          break;
        }
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
          _openedPath = path;
          _openRequests.markSuccess();
        } catch (error) {
          if (!mounted) {
            return;
          }
          // 只记录错误类型，避免异常正文中的本地路径进入 UI 或可复制诊断摘要。
          _openRequests.markFailure(
            path,
            code: error.runtimeType.toString(),
          );
        }
      }
    } finally {
      shouldContinue = mounted && _openRequests.hasPending;
      _openRequests.finishDrain(keepOpening: shouldContinue);
      if (mounted && !shouldContinue) {
        setState(() {});
      }
    }
    if (shouldContinue) {
      unawaited(_drainOpenRequests());
    }
  }

  /** 重新打开最近失败的视频，并继续复用 latest-request worker。 */
  void _retryFailedOpen() {
    if (_openRequests.retryFailure()) {
      setState(() => _queueEndReached = false);
      unawaited(_drainOpenRequests());
    }
  }

  /** 跳过失败项；队尾不循环，只显示当前筛选队列结束提示。 */
  void _skipFailedOpen() {
    final nextIndex = _playback.nextIndex;
    setState(() {
      _queueEndReached = nextIndex == null;
      _openRequests.clearFailure();
    });
    if (nextIndex == null) {
      _showQueueEndMessage();
      return;
    }
    _jumpTo(nextIndex, ignoreFollowUpSelection: true);
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
    setState(() => _playback.select(index));
    _ensureQueueIndexVisible(index, center: false);
  }

  void _moveQueueSelection(int delta, {bool center = false}) {
    if (_queue.isEmpty) {
      return;
    }
    late int nextIndex;
    setState(() => nextIndex = _playback.moveSelection(delta));
    _ensureQueueIndexVisible(nextIndex, center: center);
  }

  void _selectQueueIndex(int index, {bool center = false}) {
    if (_queue.isEmpty) {
      return;
    }
    late int nextIndex;
    setState(() => nextIndex = _playback.selectQueueIndex(index));
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
      _queueEndReached = false;
      _playback.jumpTo(index);
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
    final confirmed = await showPlayerDeleteConfirmationDialog(context, item);
    if (!confirmed || !mounted) {
      return;
    }

    try {
      await _player.stop();
      await widget.onDeleteFile(item);
      if (!mounted) {
        return;
      }
      setState(() {
        _queueEndReached = false;
        _playback.removeSelectedItem(item);
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
      if (_openRequests.hasFailure)
        '最近打开错误类型: ${_openRequests.failureCode ?? 'unknown'}',
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
    _openRequests.cancel();
    unawaited(_completedSubscription?.cancel());
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
                tooltip: '播放诊断',
                onPressed: _showDiagnosticsDialog,
                icon: const Icon(Icons.monitor_heart_outlined),
              ),
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
                            if (_openRequests.isOpening)
                              const Positioned.fill(
                                child: ColoredBox(
                                  color: Color(0x66000000),
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                ),
                              ),
                            if (!_openRequests.isOpening &&
                                _openRequests.hasFailure)
                              Positioned.fill(
                                child: _PlayerOpenFailurePanel(
                                  failureCode:
                                      _openRequests.failureCode ?? 'unknown',
                                  canSkip: _playback.hasNext,
                                  onRetry: _retryFailedOpen,
                                  onSkip: _skipFailedOpen,
                                  onDiagnostics: () {
                                    unawaited(_showDiagnosticsDialog());
                                  },
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
                      previousIndex: _playback.previousIndex,
                      nextIndex: _playback.nextIndex,
                      queueEndReached: _queueEndReached,
                      onPlayIndex: (index) {
                        _jumpTo(index, ignoreFollowUpSelection: true);
                      },
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
