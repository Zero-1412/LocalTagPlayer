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
    required this.onEditManualTags,
    required this.onRelinkMissing,
    required this.onPlaybackProgressUpdated,
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
  final Future<void> Function(VideoItem item) onEditManualTags;
  final Future<bool> Function(VideoItem item) onRelinkMissing;
  final Future<void> Function(
    VideoItem item,
    Duration position,
    Duration duration,
    bool completed,
  ) onPlaybackProgressUpdated;
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
  late final FocusNode _queueSearchFocusNode;
  late final TextEditingController _queueSearchController;
  late final ScrollController _queueScrollController;
  late final MediaDetailsService _detailsService;
  final _fileLocationService = const DesktopFileLocationService();
  late final PlayerPlaybackController _playback;
  final _openRequests = PlayerOpenRequestController();
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<String>? _playerErrorSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;
  Timer? _controlsHideTimer;
  var _controlsVisible = true;
  /** 最近一次视频控件上下文，供页面级 F 快捷键切换同一 Video 全屏状态。 */
  BuildContext? _videoControlsContext;
  DateTime? _lastProgressWriteAt;
  Duration _lastPersistedPosition = Duration.zero;
  DateTime? _ignoreQueueSelectionBefore;
  String? _handledCompletedPath;
  String? _openedPath;
  /** 恢复选择弹窗期间暂停进度写入，避免刚打开的 0 秒覆盖稳定进度。 */
  var _choosingPlaybackStart = false;
  var _queueEndReached = false;
  /** 标签弹窗打开期间阻止底层播放器重复消费 Escape，避免意外返回媒体库。 */
  var _editingManualTags = false;
  var _playbackMode = PlayerPlaybackMode.sequential;
  var _playbackRate = 1.0;
  final _random = math.Random();

  static const _playbackRates = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];

  static const double _queueItemExtent = 104;

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
    _persistOpenedProgress();
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
    _queueSearchFocusNode = FocusNode(debugLabel: 'player-queue-search');
    _queueSearchController = TextEditingController();
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
    _playerErrorSubscription = _player.stream.error.listen(_handlePlayerError);
    _positionSubscription = _player.stream.position.listen(_handlePosition);
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (!mounted) return;
      if (playing) {
        _showVideoControls();
      } else {
        _controlsHideTimer?.cancel();
        if (!_controlsVisible) setState(() => _controlsVisible = true);
      }
    });
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
   * 处理播放内核在 open 完成后才报告的运行期错误。
   *
   * 打开 worker 运行期间由可播放性确认统一收口，避免旧媒体迟到错误覆盖快速切换后的新视频。
   */
  void _handlePlayerError(String _) {
    if (!mounted || _openRequests.isOpening) {
      return;
    }
    final path = _openedPath;
    if (path == null || path != _currentItem.path) {
      return;
    }
    _openedPath = null;
    _openRequests.markFailure(path, code: 'media_kit_error');
    unawaited(_player.stop());
    setState(() {});
  }

  /** 以低频写入当前已打开视频的进度，避免播放流每帧触发 SQLite。 */
  void _handlePosition(Duration position) {
    final openedPath = _openedPath;
    if (_openRequests.isOpening ||
        _choosingPlaybackStart ||
        openedPath == null ||
        position <= Duration.zero) {
      return;
    }
    final now = DateTime.now();
    final elapsed = _lastProgressWriteAt == null
        ? const Duration(days: 1)
        : now.difference(_lastProgressWriteAt!);
    final advanced = (position - _lastPersistedPosition).abs();
    if (elapsed < const Duration(seconds: 5) &&
        advanced < const Duration(seconds: 5)) {
      return;
    }
    final item = _itemForPath(openedPath);
    if (item == null) {
      return;
    }
    _lastProgressWriteAt = now;
    _lastPersistedPosition = position;
    final duration = _player.state.duration;
    unawaited(widget.onPlaybackProgressUpdated(
      item,
      position,
      duration,
      playerPlaybackIsNearCompletion(position: position, duration: duration),
    ));
  }

  /** 从来源队列解析当前路径，确保进度写入对应视频而不是刚切换的新条目。 */
  VideoItem? _itemForPath(String path) {
    for (final item in _sourcePlaylist) {
      if (TagRules.pathKey(item.path) == TagRules.pathKey(path)) {
        return item;
      }
    }
    return null;
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
    final duration = _player.state.duration;
    unawaited(
      widget.onPlaybackProgressUpdated(
        _currentItem,
        duration,
        duration,
        true,
      ),
    );
    final targetIndex = playerCompletionTargetIndex(
      mode: _playbackMode,
      currentIndex: _index,
      queueLength: _queue.length,
      randomValue: _random.nextDouble(),
    );
    if (targetIndex == null) {
      setState(() => _queueEndReached = true);
      _showQueueEndMessage();
      return;
    }
    _jumpTo(targetIndex, ignoreFollowUpSelection: true);
  }

  /** 修改倍速并立即应用到当前播放内核；切换视频时 media_kit 会保留该状态。 */
  void _setPlaybackRate(double rate) {
    if (!_playbackRates.contains(rate)) {
      return;
    }
    setState(() => _playbackRate = rate);
    unawaited(_player.setRate(rate));
  }

  /** 按固定档位调整倍速，供菜单与键盘快捷键共用同一条状态链路。 */
  void _stepPlaybackRate(int delta) {
    final current = _playbackRates.indexOf(_playbackRate);
    final next = (current + delta).clamp(0, _playbackRates.length - 1);
    _setPlaybackRate(_playbackRates[next]);
  }

  /** 鼠标进入或移动时显示控制条；播放中空闲三秒后自动淡出。 */
  void _showVideoControls() {
    _controlsHideTimer?.cancel();
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    if (_player.state.playing) {
      _controlsHideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _player.state.playing) {
          setState(() => _controlsVisible = false);
        }
      });
    }
  }

  /** 在播放器内展示已经实现的快捷键，不引入蓝图中的占位能力。 */
  void _showControlShortcutHelp() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Space 播放/暂停 · J/L 快退/快进 · ↑/↓ 选择队列 · '
            'T 添加标签 · F 全屏 · S 截图 · [/] 调整倍速',
          ),
        ),
      );
  }

  /**
   * 抓取当前视频帧并让用户选择保存位置。
   *
   * 截图由 media_kit 获取编码后的 JPEG；文件写入只发生在用户确认保存路径后，
   * 不修改媒体库记录、缩略图缓存或当前 filtered queue。
   */
  Future<void> _saveCurrentFrameScreenshot() async {
    try {
      final bytes = await _player.screenshot(format: 'image/jpeg');
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前画面暂时无法截图')),
        );
        return;
      }
      final safeTitle =
          _currentItem.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存当前画面',
        fileName: '${safeTitle.isEmpty ? 'video' : safeTitle}_$timestamp.jpg',
        type: FileType.custom,
        allowedExtensions: const ['jpg'],
      );
      if (outputPath == null || !mounted) return;
      await File(outputPath).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('截图已保存')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('截图保存失败，请重试')),
      );
    }
  }

  /** 构建画面底部统一控制条，并在全屏顶部保留最小队列语境。 */
  Widget _buildVideoControls(VideoState state) {
    _videoControlsContext = state.context;
    return MouseRegion(
      onEnter: (_) => _showVideoControls(),
      onHover: (_) => _showVideoControls(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _showVideoControls,
        child: Stack(children: [
          if (isFullscreen(state.context))
            Positioned(
              left: 20,
              right: 20,
              top: 18,
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_index + 1} / ${_queue.length} · $_filterSummary',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      key: const ValueKey('player.fullscreenEditTags'),
                      tooltip: '标签',
                      onPressed: () => unawaited(_editManualTags()),
                      icon: const Icon(Icons.sell_outlined, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _controlsVisible ? 1 : 0.12,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: StreamBuilder<Duration>(
                  stream: _player.stream.position,
                  initialData: _player.state.position,
                  builder: (context, positionSnapshot) {
                    final position = positionSnapshot.data ?? Duration.zero;
                    final duration = _player.state.duration;
                    final maxMs =
                        math.max(1, duration.inMilliseconds).toDouble();
                    const controlAccent = Color(0xff7457ff);
                    return Container(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xe6000000)],
                        ),
                      ),
                      child: IconTheme(
                        data: const IconThemeData(color: Colors.white),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          SliderTheme(
                            data: const SliderThemeData(
                              trackHeight: 3,
                              activeTrackColor: controlAccent,
                              inactiveTrackColor: Color(0xff26314b),
                              thumbColor: Color(0xffd7deff),
                              thumbShape: RoundSliderThumbShape(
                                enabledThumbRadius: 5,
                              ),
                              overlayColor: Color(0x337457ff),
                              overlayShape: RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                            ),
                            child: Slider(
                              value: position.inMilliseconds
                                  .clamp(0, maxMs.toInt())
                                  .toDouble(),
                              max: maxMs,
                              onChanged: (value) => unawaited(
                                _player.seek(
                                  Duration(milliseconds: value.round()),
                                ),
                              ),
                            ),
                          ),
                          Row(children: [
                            IconButton(
                              tooltip: '上一条',
                              color: Colors.white,
                              disabledColor: const Color(0xff5e6a82),
                              onPressed: _playback.previousIndex == null
                                  ? null
                                  : () => _jumpTo(
                                        _playback.previousIndex!,
                                        ignoreFollowUpSelection: true,
                                      ),
                              icon: const Icon(Icons.skip_previous_rounded),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              tooltip: _player.state.playing ? '暂停' : '播放',
                              color: Colors.white,
                              onPressed: () {
                                unawaited(_player.playOrPause());
                                _showVideoControls();
                              },
                              icon: Icon(
                                _player.state.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              tooltip: '下一条',
                              color: Colors.white,
                              disabledColor: const Color(0xff5e6a82),
                              onPressed: _playback.nextIndex == null
                                  ? null
                                  : () => _jumpTo(
                                        _playback.nextIndex!,
                                        ignoreFollowUpSelection: true,
                                      ),
                              icon: const Icon(Icons.skip_next_rounded),
                            ),
                            const SizedBox(width: 16),
                            const Icon(Icons.volume_up_rounded, size: 20),
                            SizedBox(
                              width: 130,
                              child: SliderTheme(
                                data: const SliderThemeData(
                                  trackHeight: 3,
                                  activeTrackColor: controlAccent,
                                  inactiveTrackColor: Color(0xff26314b),
                                  thumbColor: Color(0xffd7deff),
                                  thumbShape: RoundSliderThumbShape(
                                    enabledThumbRadius: 4,
                                  ),
                                  overlayShape: RoundSliderOverlayShape(
                                    overlayRadius: 10,
                                  ),
                                ),
                                child: Slider(
                                  value: _player.state.volume.clamp(0, 100),
                                  max: 100,
                                  onChanged: (value) =>
                                      unawaited(_player.setVolume(value)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Text(
                              '${_formatControlDuration(position)} / '
                              '${_formatControlDuration(duration)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            PopupMenuButton<double>(
                              tooltip: '播放速度',
                              initialValue: _playbackRate,
                              onSelected: _setPlaybackRate,
                              itemBuilder: (_) => [
                                for (final rate in _playbackRates)
                                  PopupMenuItem(
                                    value: rate,
                                    child: Text('${rate}x'),
                                  ),
                              ],
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${_playbackRate}x',
                                      style: const TextStyle(
                                        color: Color(0xffcbd5e1),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 17,
                                      color: Color(0xff8794ac),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '快捷键',
                              onPressed: _showControlShortcutHelp,
                              icon: const Icon(Icons.keyboard_alt_outlined,
                                  size: 21),
                            ),
                            IconButton(
                              tooltip: '截图',
                              onPressed: () =>
                                  unawaited(_saveCurrentFrameScreenshot()),
                              icon: const Icon(Icons.photo_camera_outlined,
                                  size: 21),
                            ),
                            PopupMenuButton<PlayerPlaybackMode>(
                              tooltip: '播放模式',
                              initialValue: _playbackMode,
                              onSelected: (mode) {
                                setState(() {
                                  _playbackMode = mode;
                                  _queueEndReached = false;
                                });
                              },
                              itemBuilder: (_) => [
                                for (final mode in PlayerPlaybackMode.values)
                                  PopupMenuItem(
                                    value: mode,
                                    child: Row(children: [
                                      Icon(mode.icon, size: 18),
                                      const SizedBox(width: 8),
                                      Text(mode.label),
                                      if (mode == _playbackMode) ...[
                                        const Spacer(),
                                        const Icon(Icons.check_rounded,
                                            size: 18),
                                      ],
                                    ]),
                                  ),
                              ],
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Icon(
                                    Icons.picture_in_picture_alt_outlined,
                                    size: 21),
                              ),
                            ),
                            IconButton(
                              tooltip: '播放诊断',
                              onPressed: () =>
                                  unawaited(_showDiagnosticsDialog()),
                              icon:
                                  const Icon(Icons.settings_outlined, size: 21),
                            ),
                            IconButton(
                              tooltip:
                                  isFullscreen(state.context) ? '退出全屏' : '全屏',
                              onPressed: () =>
                                  unawaited(toggleFullscreen(state.context)),
                              icon: Icon(isFullscreen(state.context)
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded),
                            ),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ]),
      ),
    );
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
      if (item.isMissing) {
        // missing 条目只展示稳定状态和 Relink，不派发失效路径的媒体/缩略图 I/O。
        continue;
      }
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
    if (_currentItem.isMissing) {
      _openedPath = null;
      _openRequests.markFailure(
        _currentItem.path,
        code: 'missing_media',
      );
      if (mounted) {
        setState(() {});
      }
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
          final playable = await _waitForPlayableMedia();
          if (!playable) {
            // 快速切换已有更新请求时只放弃旧验证，不展示过时错误。
            if (!_openRequests.hasPending) {
              _openedPath = null;
              _openRequests.markFailure(
                path,
                code: 'unplayable_media',
              );
              await _player.stop();
            }
            continue;
          }
          _openedPath = path;
          _openRequests.markSuccess();
          final openedItem = _itemForPath(path);
          if (openedItem != null) {
            _lastPersistedPosition = Duration.zero;
            _lastProgressWriteAt = null;
            _choosingPlaybackStart = true;
            try {
              await _choosePlaybackStart(openedItem);
            } finally {
              _choosingPlaybackStart = false;
            }
          }
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

  /**
   * 等待本地媒体产生有效时长或 codec 证据。
   *
   * 0 字节/损坏 MP4 的 `Player.open` 可能成功返回却永久停在 00:00；限定等待窗口后将其
   * 归入稳定错误面板。检测期间如出现更新 open 请求则立即放弃旧验证，保护快速切换流畅度。
   */
  Future<bool> _waitForPlayableMedia() async {
    const attempts = 6;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (_openRequests.hasPending) {
        return false;
      }
      final videoCodec = await _getMpvProperty('video-codec');
      final audioCodec = await _getMpvProperty('audio-codec');
      if (playerMediaStateIsPlayable(
        duration: _player.state.duration,
        videoCodec: videoCodec,
        audioCodec: audioCodec,
      )) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  /** 按设置页默认行为处理有效进度；仅“每次询问”继续弹出选择框。 */
  Future<void> _choosePlaybackStart(VideoItem item) async {
    final duration = _player.state.duration;
    final saved = playerResumePosition(
      saved: item.playbackPosition,
      duration: duration,
      completed: item.playbackCompleted,
    );
    if (saved == null) {
      return;
    }
    final behavior = widget.playbackSettings.resumeBehavior;
    PlayerResumeChoice choice;
    if (behavior == PlaybackResumeBehavior.ask) {
      await _player.pause();
      if (!mounted || _openedPath != item.path) {
        return;
      }
      choice = await showPlayerResumeDialog(
        context,
        item: item,
        position: saved,
        duration: duration,
      );
    } else {
      choice = behavior == PlaybackResumeBehavior.continueWatching
          ? PlayerResumeChoice.continueWatching
          : PlayerResumeChoice.restart;
    }
    if (!mounted || _openedPath != item.path) {
      return;
    }
    final start =
        choice == PlayerResumeChoice.continueWatching ? saved : Duration.zero;
    await _player.seek(start);
    await _player.play();
    _lastPersistedPosition = start;
    _lastProgressWriteAt = DateTime.now();
    if (choice == PlayerResumeChoice.restart) {
      unawaited(widget.onPlaybackProgressUpdated(
        item,
        Duration.zero,
        duration,
        false,
      ));
    }
  }

  /** 从失败面板重新关联 missing 文件，成功后原地打开同一稳定 videoId。 */
  Future<void> _relinkCurrentMissing() async {
    final item = _currentItem;
    final relinked = await widget.onRelinkMissing(item);
    if (!mounted || !relinked) {
      return;
    }
    setState(() => _openRequests.clearFailure());
    _requestOpenCurrent();
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

  /** 搜索当前 filtered queue 并直接定位播放，不访问全媒体库。 */
  void _searchQueue(String query) {
    final index = playerQueueSearchIndex(
      _queue,
      query,
      startIndex: _index,
    );
    if (index == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前队列没有匹配项')),
      );
      return;
    }
    _jumpTo(index, ignoreFollowUpSelection: true);
  }

  void _jumpTo(int index, {bool ignoreFollowUpSelection = false}) {
    if (index < 0 || index >= _queue.length) {
      return;
    }
    _persistOpenedProgress();
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

  /** 切换或退出前补写当前位置、总时长和动态完成态。 */
  void _persistOpenedProgress() {
    final openedPath = _openedPath;
    final position = _player.state.position;
    final duration = _player.state.duration;
    if (openedPath == null || position <= Duration.zero) {
      return;
    }
    final item = _itemForPath(openedPath);
    if (item == null) {
      return;
    }
    unawaited(widget.onPlaybackProgressUpdated(
      item,
      position,
      duration,
      playerPlaybackIsNearCompletion(position: position, duration: duration),
    ));
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

  /** 打开当前视频的 manual 标签编辑器，并在保存后刷新播放器上下文。 */
  Future<void> _editManualTags() async {
    _editingManualTags = true;
    try {
      await widget.onEditManualTags(_currentItem);
      if (mounted) {
        setState(() {});
      }
    } finally {
      _editingManualTags = false;
    }
  }

  /** 通过平台边界定位当前媒体文件，并稳定展示失败原因。 */
  Future<void> _revealCurrentFile() async {
    try {
      await _fileLocationService.reveal(_currentItem.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开文件位置，请确认文件仍然存在')),
        );
      }
    }
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

  /** 蓝图控制栏固定显示两位小时，避免时长跨小时后横向跳动。 */
  String _formatControlDuration(Duration value) {
    final hours = value.inHours.toString().padLeft(2, '0');
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
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
    if (_editingManualTags && event.logicalKey == LogicalKeyboardKey.escape) {
      // 弹窗自己的 Escape 只负责取消编辑；播放器页面不能再对同一按键执行返回。
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyK &&
        HardwareKeyboard.instance.isControlPressed) {
      // 顶部搜索与右侧队列搜索共用定位逻辑，Ctrl+K 仅负责聚焦而不重建队列。
      _queueSearchFocusNode.requestFocus();
      _queueSearchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _queueSearchController.text.length,
      );
      return KeyEventResult.handled;
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
      case LogicalKeyboardKey.space:
        unawaited(_player.playOrPause());
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyJ:
        unawaited(
            _player.seek(_player.state.position - const Duration(seconds: 5)));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyL:
        unawaited(
            _player.seek(_player.state.position + const Duration(seconds: 5)));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyT:
        unawaited(_editManualTags());
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyS:
        unawaited(_saveCurrentFrameScreenshot());
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        final videoContext = _videoControlsContext;
        if (videoContext != null) {
          unawaited(toggleFullscreen(videoContext));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.bracketLeft:
        _stepPlaybackRate(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.bracketRight:
        _stepPlaybackRate(1);
        return KeyEventResult.handled;
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
    _controlsHideTimer?.cancel();
    unawaited(_completedSubscription?.cancel());
    unawaited(_playerErrorSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_playingSubscription?.cancel());
    _persistOpenedProgress();
    _queueScrollController.dispose();
    _queueSearchFocusNode.dispose();
    _queueSearchController.dispose();
    _focusNode.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 中窄窗口改用底部队列，避免侧栏挤压蓝图式横向控制层。
    final showQueueSidebar = MediaQuery.sizeOf(context).width >= 1100;
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
      onDiagnostics: () => unawaited(_showDiagnosticsDialog()),
      onSearchQueue: _searchQueue,
      onDeleteSelected: _selectedIndex == _index ? _deleteSelectedFile : null,
    );
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Listener(
        onPointerDown: _handlePointerDown,
        child: Scaffold(
          backgroundColor: const Color(0xff070d1d),
          body: Column(
            children: [
              _PlayerTopBar(
                searchController: _queueSearchController,
                searchFocusNode: _queueSearchFocusNode,
                onBack: () => Navigator.of(context).maybePop(),
                onSearch: _searchQueue,
                onOpenQueue: showQueueSidebar
                    ? null
                    : () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: const Color(0xff0d1528),
                          builder: (_) => FractionallySizedBox(
                            heightFactor: 0.82,
                            child: queueSidebar,
                          ),
                        );
                      },
              ),
              Expanded(
                child: Row(
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
                                border:
                                    Border.all(color: const Color(0xff1f2937)),
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
                                      onSecondaryTapDown:
                                          _showPlayerContextMenu,
                                      child: Center(
                                        child: Video(
                                          controller: _controller,
                                          controls: _buildVideoControls,
                                        ),
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
                                            _openRequests.failureCode ??
                                                'unknown',
                                        canSkip: _playback.hasNext,
                                        onRetry: _retryFailedOpen,
                                        onSkip: _skipFailedOpen,
                                        onDiagnostics: () {
                                          unawaited(_showDiagnosticsDialog());
                                        },
                                        onRelink: _currentItem.isMissing
                                            ? () {
                                                unawaited(
                                                    _relinkCurrentMissing());
                                              }
                                            : null,
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
                            queueEndReached: _queueEndReached,
                            playbackMode: _playbackMode,
                            onToggleFavorite: () {
                              unawaited(widget.onToggleFavorite(_currentItem));
                              setState(() {});
                            },
                            onEditManualTags: () {
                              unawaited(_editManualTags());
                            },
                            onRevealFile: () {
                              unawaited(_revealCurrentFile());
                            },
                            onVideoInfo: () {
                              unawaited(_showVideoInfoDialog());
                            },
                            onDiagnostics: () {
                              unawaited(_showDiagnosticsDialog());
                            },
                            onPlaybackModeChanged: (mode) {
                              setState(() {
                                _playbackMode = mode;
                                _queueEndReached = false;
                              });
                            },
                          ),
                          const _PlayerShortcutHintBar(),
                        ],
                      ),
                    ),
                    if (showQueueSidebar) queueSidebar,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/** 蓝图风格的播放器顶栏；刻意不提供“打开文件”，避免绕过媒体库与筛选队列。 */
class _PlayerTopBar extends StatelessWidget {
  const _PlayerTopBar({
    required this.searchController,
    required this.searchFocusNode,
    required this.onBack,
    required this.onSearch,
    required this.onOpenQueue,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final VoidCallback onBack;
  final ValueChanged<String> onSearch;
  final VoidCallback? onOpenQueue;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(children: [
          IconButton(
            tooltip: '返回媒体库',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: const Color(0xffcbd5e1),
          ),
          const Icon(Icons.play_arrow_rounded,
              color: Color(0xff7c5cff), size: 30),
          const SizedBox(width: 8),
          const Text(
            'local_tag_player',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 396),
            child: TextField(
              controller: searchController,
              focusNode: searchFocusNode,
              onSubmitted: onSearch,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Ctrl + K   搜索当前队列',
                hintStyle: const TextStyle(color: Color(0xff77839a)),
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        onPressed: () {
                          searchController.clear();
                          onSearch('');
                        },
                        icon: const Icon(Icons.close_rounded, size: 17),
                      ),
                filled: true,
                fillColor: const Color(0xff0b1326),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: Color(0xff202c46)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: Color(0xff202c46)),
                ),
              ),
            ),
          ),
          const Spacer(),
          if (onOpenQueue != null)
            IconButton(
              tooltip: '播放队列',
              onPressed: onOpenQueue,
              icon: const Icon(Icons.playlist_play_rounded),
            )
          else
            const SizedBox(width: 48),
        ]),
      ),
    );
  }
}

/** 只提示已经实现的快捷键，避免蓝图占位能力误导用户。 */
class _PlayerShortcutHintBar extends StatelessWidget {
  const _PlayerShortcutHintBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 38,
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xff0d1528),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xff202c46)),
      ),
      child: const SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          Icon(Icons.lightbulb_outline_rounded,
              color: Color(0xffd7a855), size: 18),
          SizedBox(width: 7),
          Text('快捷键', style: TextStyle(color: Color(0xff8895aa))),
          SizedBox(width: 16),
          _ShortcutHint(keys: 'Space', label: '播放/暂停'),
          _ShortcutHint(keys: 'J / L', label: '快退/快进'),
          _ShortcutHint(keys: 'T', label: '添加标签'),
          _ShortcutHint(keys: 'F', label: '全屏/退出全屏'),
          _ShortcutHint(keys: 'S', label: '截图'),
        ]),
      ),
    );
  }
}

class _ShortcutHint extends StatelessWidget {
  const _ShortcutHint({required this.keys, required this.label});

  final String keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xff182141),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(keys,
              style: const TextStyle(
                  color: Color(0xffb7b9ff),
                  fontSize: 10,
                  fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(color: Color(0xff7f8ba0), fontSize: 11)),
      ]),
    );
  }
}
