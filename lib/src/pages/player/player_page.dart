import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/playback_settings.dart';
import '../../core/tag_rules.dart';
import '../../models/media_details.dart';
import '../../models/video_item.dart';
import '../../platform/file_system_adapter.dart';
import '../../platform/platform_interfaces.dart';
import '../../services/media/media_details_service.dart';
import '../../services/media/thumbnail_service.dart';
import '../../services/player/player_hardware_acceleration.dart';
import '../../services/player/player_hardware_compatibility.dart';
import '../../services/player/player_memory_diagnostics.dart';
import '../../widgets/app_theme_tokens.dart';
import 'player_context_panel.dart';
import 'player_delete_dialog.dart';
import 'player_diagnostics_dialog.dart';
import 'player_dialog_content.dart';
import 'player_hardware_decode_warning_dialog.dart';
import 'player_open_failure_panel.dart';
import 'player_open_request_controller.dart';
import 'player_playback_controller.dart';
import 'player_playback_mode.dart';
import 'player_queue_sidebar.dart';
import 'player_resume_dialog.dart';
import 'player_settings_panel.dart';
import 'player_video_aspect_mode.dart';

// ignore_for_file: slash_for_doc_comments

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
    required this.disposalCompleter,
    required this.fileSystem,
    required this.playerBackendFactory,
    required this.mediaProbeBackendFactory,
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
  /** 页面退出后由播放器原生资源释放流程完成的路由协调信号。 */
  final Completer<void> disposalCompleter;

  /** 文件选择、写入、元数据与文件管理器定位的平台边界。 */
  final FileSystemAdapter fileSystem;

  /** 可选播放器后端工厂，用于测试或原生后端 A/B 切换。 */
  final PlayerBackendFactory playerBackendFactory;

  /** 由组合根选择的媒体探测后端工厂。 */
  final MediaProbeBackendFactory mediaProbeBackendFactory;

  @override
  State<PlayerPage> createState() => PlayerPageState();
}

class PlayerPageState extends State<PlayerPage> {
  late final PlayerBackend _playerBackend;
  /** 诊断弹窗使用的只读播放器边界。 */
  PlayerBackend get playerBackend => _playerBackend;
  late final FocusNode _focusNode;
  late final FocusNode _queueSearchFocusNode;
  late final TextEditingController _queueSearchController;
  late final ScrollController _queueScrollController;
  late final ScrollController _fullscreenQueueScrollController;
  late final MediaDetailsService _detailsService;
  late final String _requestedHwdec;
  late final PlayerPlaybackController _playback;
  final _openRequests = PlayerOpenRequestController();
  /** 正在等待兼容性确认的路径；避免快速点击叠加多个警告弹窗。 */
  String? _compatibilityPromptPath;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<String>? _playerErrorSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;
  Timer? _controlsHideTimer;
  Timer? _queuePrefetchTimer;
  Timer? _fullscreenQueueHideTimer;
  Timer? _playbackHealthTimer;
  var _playbackHealthSampling = false;
  var _controlsVisible = true;
  DateTime? _lastProgressWriteAt;
  Duration _lastPersistedPosition = Duration.zero;
  DateTime? _ignoreQueueSelectionBefore;
  String? _handledCompletedPath;
  String? _openedPath;
  int? _lastSeekLatencyMs;
  DateTime? _lastSeekAt;
  int? _lastVideoFrameNumber;
  double? _lastAudioPts;
  DateTime? _lastVideoAdvanceAt;
  DateTime? _lastAudioAdvanceAt;
  DateTime? _lastHealthSampleAt;
  /** 最近一次 mpv 明确报告的实际硬解状态，不把属性不可用误判为软件解码。 */
  String? _lastHwdecCurrent;
  var _consecutiveSoftwareDecodeSamples = 0;
  var _softwareDecodeConfirmed = false;
  var _videoProgressState = '等待首个视频样本';
  var _audioProgressState = '等待首个音频样本';
  var _videoStallEvents = 0;
  var _audioStallEvents = 0;
  var _textureReadyLogged = false;
  DateTime? _exitRequestedAt;
  /** 路由退出后继续执行的原生 stop；dispose 必须等待它结束，禁止两条命令并发释放。 */
  Future<void>? _exitStopFuture;
  DateTime? _pauseAcknowledgedAt;
  DateTime? _routePopRequestedAt;
  Duration? _pendingSeekTarget;
  var _seekInFlight = false;
  var _isExiting = false;
  /** 恢复选择弹窗期间暂停进度写入，避免刚打开的 0 秒覆盖稳定进度。 */
  var _choosingPlaybackStart = false;
  var _queueEndReached = false;
  /** 标签弹窗打开期间阻止底层播放器重复消费 Escape，避免意外返回媒体库。 */
  var _editingManualTags = false;
  var _playbackMode = PlayerPlaybackMode.sequential;
  var _playbackRate = 1.0;
  /** 当前会话的画面比例，默认保留媒体自身比例。 */
  var _videoAspectMode = PlayerVideoAspectMode.automatic;
  /** 用户主动折叠宽屏右侧队列时保持当前页面内的显示状态。 */
  var _queueSidebarCollapsed = false;
  /** 是否由播放器页面进入桌面窗口全屏。 */
  var _isWindowFullscreen = false;
  /** 全屏时是否在画面右侧显示当前筛选队列浮层。 */
  var _fullscreenQueueVisible = false;
  final _random = math.Random();

  static const _playbackRates = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];

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
  }

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'player-shortcuts');
    _queueSearchFocusNode = FocusNode(debugLabel: 'player-queue-search');
    _queueSearchController = TextEditingController();
    _queueScrollController = ScrollController();
    _fullscreenQueueScrollController = ScrollController();
    _detailsService = MediaDetailsService(
      onUpdated: widget.onMediaDetailsUpdated,
      probeBackend: widget.mediaProbeBackendFactory(),
    );
    _requestedHwdec =
        PlayerHardwareAcceleration.resolve(widget.playbackSettings.hwdec);
    _playback = PlayerPlaybackController(
      sourcePlaylist: widget.playlist.isEmpty
          ? <VideoItem>[widget.initialItem]
          : widget.playlist,
      activeParentTag: _activeParentTag,
      initialChildTag: widget.activeChildTag,
      initialPath: widget.initialItem.path,
    );
    _playerBackend = widget.playerBackendFactory(
      hwdec: _requestedHwdec,
      enableHardwareAcceleration:
          widget.playbackSettings.hardwareDecodingEnabled,
    );
    _playerBackend.textureId.addListener(_handleTextureReadyForDiagnostics);
    unawaited(PlayerMemoryDiagnostics.logStage(
      'player_constructed',
      backend: _playerBackend,
    ));
    _completedSubscription =
        _playerBackend.completedChanges.listen(_handlePlaybackCompleted);
    _playerErrorSubscription =
        _playerBackend.errorChanges.listen(_handlePlayerError);
    _positionSubscription =
        _playerBackend.positionChanges.listen(_handlePosition);
    _playingSubscription = _playerBackend.playingChanges.listen((playing) {
      if (!mounted) return;
      if (playing) {
        _showVideoControls();
      } else {
        _controlsHideTimer?.cancel();
        if (!_controlsVisible) setState(() => _controlsVisible = true);
      }
    });
    _requestOpenCurrent();
    // 诊断弹窗关闭时仍持续独立观察视频帧与音频播放头，避免瞬时 AV offset 掩盖单路停滞。
    _playbackHealthTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_sampleIndependentPlaybackProgress()),
    );
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
    unawaited(_playerBackend.stop());
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
    final duration = _playerBackend.state.duration;
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
    final duration = _playerBackend.state.duration;
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
    unawaited(_playerBackend.setRate(rate));
  }

  /** 按固定档位调整倍速，供菜单与键盘快捷键共用同一条状态链路。 */
  void _stepPlaybackRate(int delta) {
    final current = _playbackRates.indexOf(_playbackRate);
    final next = (current + delta).clamp(0, _playbackRates.length - 1);
    _setPlaybackRate(_playbackRates[next]);
  }

  /** 更新队列播放方式，不改变 filtered queue 的内容或顺序。 */
  void _setPlaybackMode(PlayerPlaybackMode mode) {
    setState(() {
      _playbackMode = mode;
      _queueEndReached = false;
    });
  }

  /**
   * 更新当前会话的画面比例并立即应用到 mpv。
   *
   * 自动、4:3 与 16:9 保持完整画面；铺满使用 panscan 等比裁边，主要用于
   * 1728×1080 等非 16:9 视频在全屏时消除左右留边和源内黑边的组合效果。
   */
  Future<void> _setVideoAspectMode(PlayerVideoAspectMode mode) async {
    if (_videoAspectMode != mode && mounted) {
      setState(() => _videoAspectMode = mode);
    }
    await _applyVideoAspectMode();
  }

  /** 把页面比例状态映射为后端通用 mpv 属性；后端不支持时允许安全忽略。 */
  Future<void> _applyVideoAspectMode() async {
    await _setMpvProperty(
      'video-aspect-override',
      _videoAspectMode.mpvAspectOverride,
    );
    await _setMpvProperty('panscan', _videoAspectMode.mpvPanscan);
    // 切换模式时归零历史缩放，避免诊断或外部属性残留叠加到新的比例选择。
    await _setMpvProperty('video-zoom', '0');
    await _setMpvProperty('video-pan-x', '0');
    await _setMpvProperty('video-pan-y', '0');
  }

  /** 鼠标进入或移动时显示控制条；播放中空闲三秒后自动淡出。 */
  /**
   * 执行 seek 并记录从请求到播放器返回的耗时，供持续诊断识别随机拖动压力。
   */
  Future<void> _seekWithDiagnostics(Duration target) async {
    if (_isExiting) {
      return;
    }
    // 拖动进度条时只保留最新目标，避免大量并发 seek 让视频解码停止而音频继续推进。
    _pendingSeekTarget = target < Duration.zero ? Duration.zero : target;
    if (_seekInFlight) {
      return;
    }
    _seekInFlight = true;
    try {
      while (!_isExiting && _pendingSeekTarget != null) {
        final requested = _pendingSeekTarget!;
        _pendingSeekTarget = null;
        final stopwatch = Stopwatch()..start();
        await _playerBackend.seek(requested);
        // media_kit 的 seek Future 只代表命令已提交；等待位置接近目标后再记录真实延迟。
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (!_isExiting && DateTime.now().isBefore(deadline)) {
          final delta = (_playerBackend.state.position - requested).abs();
          if (delta <= const Duration(milliseconds: 750)) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        stopwatch.stop();
        _lastSeekLatencyMs = stopwatch.elapsedMilliseconds;
        _lastSeekAt = DateTime.now();
      }
    } finally {
      _seekInFlight = false;
    }
  }

  /**
   * 在路由消失前先停止原生播放，保证返回媒体库后不会残留声音。
   */
  Future<void> _exitPlayer() async {
    if (_isExiting) {
      return;
    }
    _isExiting = true;
    _exitRequestedAt = DateTime.now();
    unawaited(PlayerMemoryDiagnostics.logStage(
      'exit_requested',
      backend: _playerBackend,
    ));
    _pendingSeekTarget = null;
    _openRequests.cancel();
    _detailsService.dispose();
    _persistOpenedProgress();
    try {
      // pause 的确认路径比 stop 短，先确保音频静音，不能让原生 stop 阻塞路由退出。
      await _playerBackend.pause().timeout(const Duration(milliseconds: 800));
      _pauseAcknowledgedAt = DateTime.now();
      unawaited(PlayerMemoryDiagnostics.logStage(
        'pause_acknowledged',
        backend: _playerBackend,
      ));
    } catch (_) {
      // 即使 pause 超时也继续退出；下方 stop 与 dispose 仍会终止原生播放。
    }
    _exitStopFuture ??= _stopForExitDiagnostics();
    if (mounted) {
      _routePopRequestedAt = DateTime.now();
      Navigator.of(context).maybePop();
    }
  }

  /** 原生 stop 不阻塞路由退出，但完成时必须留下可与 GPU 计数器对齐的阶段标记。 */
  Future<void> _stopForExitDiagnostics() async {
    try {
      await _playerBackend.stop().timeout(const Duration(seconds: 3));
      await PlayerMemoryDiagnostics.logStage(
        'stop_acknowledged',
        backend: _playerBackend,
      );
    } catch (_) {
      debugPrint('PLAYER_MEMORY_STAGE stage=stop_timeout');
    }
  }

  /** 首个有效纹理ID只记录一次，避免每次尺寸变化污染阶段日志。 */
  void _handleTextureReadyForDiagnostics() {
    if (_textureReadyLogged || _playerBackend.textureId.value == null) {
      return;
    }
    _textureReadyLogged = true;
    unawaited(PlayerMemoryDiagnostics.logStage(
      'texture_ready',
      backend: _playerBackend,
    ));
  }

  /**
   * 每秒分别读取 mpv 的当前视频帧号与音频播放头。
   *
   * `estimated-frame-number` 代表视频链路是否继续交付帧，`audio-pts` 包含音频驱动延迟；
   * 两者不共用 `time-pos`，因此可以识别“画面停住但声音继续”及其反向故障。
   */
  Future<void> _sampleIndependentPlaybackProgress() async {
    if (_playbackHealthSampling || _isExiting) {
      return;
    }
    _playbackHealthSampling = true;
    try {
      final frame =
          _parseMpvInt(await _getMpvProperty('estimated-frame-number'));
      final audioPts = _parseMpvNumber(await _getMpvProperty('audio-pts'));
      final hwdecCurrent = await _getMpvProperty('hwdec-current');
      final now = DateTime.now();
      _lastHealthSampleAt = now;
      if (frame != null) {
        if (_lastVideoFrameNumber == null || frame != _lastVideoFrameNumber) {
          _lastVideoAdvanceAt = now;
          _videoProgressState = '视频帧持续推进';
        }
        _lastVideoFrameNumber = frame;
      }
      if (audioPts != null) {
        if (_lastAudioPts == null ||
            (audioPts - _lastAudioPts!).abs() >= 0.01) {
          _lastAudioAdvanceAt = now;
          _audioProgressState = '音频播放头持续推进';
        }
        _lastAudioPts = audioPts;
      }

      final canJudge = _playerBackend.state.playing &&
          !_playerBackend.state.buffering &&
          (_lastSeekAt == null || now.difference(_lastSeekAt!).inSeconds >= 2);
      // mpv 在已开始软件解码时可能把 hwdec-current 返回为空；平台接口不可用才保持未知。
      final effectiveHwdec =
          hwdecCurrent == 'empty' && canJudge ? 'no' : hwdecCurrent;
      if (effectiveHwdec != 'empty' && effectiveHwdec != 'unavailable') {
        _lastHwdecCurrent = effectiveHwdec;
        if (canJudge &&
            widget.playbackSettings.hardwareDecodingEnabled &&
            effectiveHwdec == 'no') {
          _consecutiveSoftwareDecodeSamples++;
        } else {
          _consecutiveSoftwareDecodeSamples = 0;
        }
      }
      if (_consecutiveSoftwareDecodeSamples >= 3 && !_softwareDecodeConfirmed) {
        _softwareDecodeConfirmed = true;
        // 运行时热切换 hwdec 会让部分超规格视频直接打开失败；只记录确认结果并保留软件回退可播放性。
        debugPrint(
          'PLAYER_HEALTH software_decode_confirmed requested=$_requestedHwdec actual=$hwdecCurrent',
        );
      }
      if (canJudge &&
          frame != null &&
          _lastVideoAdvanceAt != null &&
          now.difference(_lastVideoAdvanceAt!) >= const Duration(seconds: 3)) {
        if (_videoProgressState != '视频帧停滞') {
          _videoStallEvents++;
          debugPrint(
              'PLAYER_HEALTH video_stall frame=$frame audio_pts=$audioPts');
        }
        _videoProgressState = '视频帧停滞';
      }
      if (canJudge &&
          audioPts != null &&
          _lastAudioAdvanceAt != null &&
          now.difference(_lastAudioAdvanceAt!) >= const Duration(seconds: 3)) {
        if (_audioProgressState != '音频播放头停滞') {
          _audioStallEvents++;
          debugPrint(
              'PLAYER_HEALTH audio_stall frame=$frame audio_pts=$audioPts');
        }
        _audioProgressState = '音频播放头停滞';
      }
    } finally {
      _playbackHealthSampling = false;
    }
  }

  void _showVideoControls() {
    _controlsHideTimer?.cancel();
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    if (_playerBackend.state.playing) {
      _controlsHideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _playerBackend.state.playing) {
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
      final bytes = await _playerBackend.screenshot(format: 'image/jpeg');
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
      final outputPath = await widget.fileSystem.pickSavePath(
        dialogTitle: '保存当前画面',
        suggestedName:
            '${safeTitle.isEmpty ? 'video' : safeTitle}_$timestamp.jpg',
        allowedExtensions: const <String>['jpg'],
      );
      if (outputPath == null || !mounted) return;
      await widget.fileSystem.writeBytes(outputPath, bytes, flush: true);
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
  Widget _buildVideoControls() {
    return MouseRegion(
      onEnter: (_) => _showVideoControls(),
      onHover: (_) => _showVideoControls(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _showVideoControls,
        child: Stack(children: [
          if (_isWindowFullscreen)
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
              key: const ValueKey('player.controls.opacity'),
              duration: const Duration(milliseconds: 180),
              opacity: _controlsVisible ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: StreamBuilder<Duration>(
                  stream: _playerBackend.positionChanges,
                  initialData: _playerBackend.state.position,
                  builder: (context, positionSnapshot) {
                    final position = positionSnapshot.data ?? Duration.zero;
                    final duration = _playerBackend.state.duration;
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
                                _seekWithDiagnostics(
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
                              tooltip:
                                  _playerBackend.state.playing ? '暂停' : '播放',
                              color: Colors.white,
                              onPressed: () {
                                unawaited(_playerBackend.playOrPause());
                                _showVideoControls();
                              },
                              icon: Icon(
                                _playerBackend.state.playing
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
                            Listener(
                              onPointerSignal: (event) {
                                if (event is PointerScrollEvent) {
                                  final delta =
                                      event.scrollDelta.dy < 0 ? 5 : -5;
                                  final volume =
                                      (_playerBackend.state.volume + delta)
                                          .clamp(0, 100)
                                          .toDouble();
                                  unawaited(_playerBackend.setVolume(volume));
                                  _showVideoControls();
                                }
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
                                        key: const ValueKey('player.volume'),
                                        value: _playerBackend.state.volume
                                            .clamp(0, 100),
                                        max: 100,
                                        onChanged: (value) => unawaited(
                                            _playerBackend.setVolume(value)),
                                      ),
                                    ),
                                  ),
                                ],
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
                            IconButton(
                              key: const ValueKey('player.screenshot'),
                              tooltip: '当前帧截图',
                              onPressed: () =>
                                  unawaited(_saveCurrentFrameScreenshot()),
                              icon: const Icon(Icons.photo_camera_outlined,
                                  size: 21),
                            ),
                            IconButton(
                              key: const ValueKey('player.settings'),
                              tooltip: '播放设置',
                              onPressed: () =>
                                  unawaited(_showControlSettingsDialog()),
                              icon:
                                  const Icon(Icons.settings_outlined, size: 21),
                            ),
                            IconButton(
                              key: const ValueKey('player.fullscreen.toggle'),
                              tooltip: _isWindowFullscreen ? '退出全屏' : '全屏',
                              onPressed: () =>
                                  unawaited(_toggleWindowFullscreen()),
                              icon: Icon(_isWindowFullscreen
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded),
                            ),
                            IconButton(
                              key: const ValueKey('player.queue.toggle'),
                              tooltip: _isWindowFullscreen
                                  ? '播放列表'
                                  : _queueSidebarCollapsed
                                      ? '展开筛选结果队列'
                                      : '折叠筛选结果队列',
                              onPressed: () {
                                if (_isWindowFullscreen) {
                                  if (_fullscreenQueueVisible) {
                                    _fullscreenQueueHideTimer?.cancel();
                                    setState(
                                        () => _fullscreenQueueVisible = false);
                                  } else {
                                    _showFullscreenQueueSidebar();
                                  }
                                } else {
                                  setState(() {
                                    _queueSidebarCollapsed =
                                        !_queueSidebarCollapsed;
                                  });
                                }
                              },
                              icon: const Icon(Icons.playlist_play_rounded),
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

  /** 切换桌面窗口全屏，并让页面布局与窗口状态同步更新。 */
  Future<void> _toggleWindowFullscreen() async {
    final target = !_isWindowFullscreen;
    await windowManager.setFullScreen(target);
    if (!mounted) {
      return;
    }
    setState(() {
      _isWindowFullscreen = target;
      _fullscreenQueueVisible = false;
    });
    _showVideoControls();
  }

  /** 鼠标进入右侧热区或队列时展示全屏侧栏，并取消待执行的自动隐藏。 */
  void _showFullscreenQueueSidebar() {
    _fullscreenQueueHideTimer?.cancel();
    if (mounted && !_fullscreenQueueVisible) {
      setState(() => _fullscreenQueueVisible = true);
    }
  }

  /** 鼠标离开队列宽度后短延迟收回侧栏，避免边缘抖动导致反复闪烁。 */
  void _scheduleFullscreenQueueHide() {
    _fullscreenQueueHideTimer?.cancel();
    _fullscreenQueueHideTimer = Timer(
        Duration(
          milliseconds: widget.playbackSettings.fullscreenQueueHideDelayMs,
        ), () {
      if (mounted && _fullscreenQueueVisible) {
        setState(() => _fullscreenQueueVisible = false);
      }
    });
  }

  /** 打开参考图式分组设置浮层，并复用现有播放状态与诊断入口。 */
  Future<void> _showControlSettingsDialog() {
    return showPlayerSettingsDialog(
      context,
      playbackMode: _playbackMode,
      videoAspectMode: _videoAspectMode,
      playbackRate: _playbackRate,
      playbackRates: _playbackRates,
      onPlaybackModeChanged: _setPlaybackMode,
      onVideoAspectModeChanged: (mode) {
        unawaited(_setVideoAspectMode(mode));
      },
      onPlaybackRateChanged: _setPlaybackRate,
      onShowShortcuts: _showControlShortcutHelp,
      onShowDiagnostics: () => unawaited(_showDiagnosticsDialog()),
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

  void _ensureQueueIndexVisible(
    int index, {
    required bool center,
    bool animated = true,
    ScrollController? controller,
    int layoutAttempt = 0,
  }) {
    if (index < 0 || index >= _queue.length) {
      return;
    }
    final targetController = controller ??
        (_isWindowFullscreen && _fullscreenQueueVisible
            ? _fullscreenQueueScrollController
            : _queueScrollController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!targetController.hasClients ||
          !targetController.position.hasContentDimensions) {
        if (layoutAttempt < 4) {
          // 首次路由/全屏队列刚挂载时列表尺寸可能晚一帧建立；有限重试确保定位请求不丢失。
          Future<void>.delayed(const Duration(milliseconds: 16), () {
            if (mounted) {
              _ensureQueueIndexVisible(
                index,
                center: center,
                animated: animated,
                controller: targetController,
                layoutAttempt: layoutAttempt + 1,
              );
            }
          });
        }
        return;
      }
      final position = targetController.position;
      final viewport = position.viewportDimension;
      final clampedOffset = playerQueueScrollOffsetForIndex(
        index: index,
        viewportExtent: viewport,
        itemExtent: playerQueueItemExtent,
        minScrollExtent: position.minScrollExtent,
        maxScrollExtent: position.maxScrollExtent,
        center: center,
      );
      if (animated) {
        unawaited(targetController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 220),
          curve: appMotionCurve,
        ));
      } else {
        targetController.jumpTo(clampedOffset);
      }
    });
  }

  void _prefetchQueueWindow({int radius = 5}) {
    if (_queue.isEmpty) {
      return;
    }
    final start = math.max(0, _index - radius);
    final end = math.min(_queue.length - 1, _index + radius);
    for (var index = start; index <= end; index++) {
      final item = _queue[index];
      if (item.isMissing) {
        // missing 条目只展示稳定状态和 Relink，不派发失效路径的媒体/缩略图 I/O。
        continue;
      }
      if (index == _index) {
        // 播放期间只补齐当前视频详情，避免滚动列表时 FFprobe 与 4K 解码争抢磁盘。
        unawaited(_detailsService.detailsFor(item, priority: true));
      }
    }
    // 播放期间不再补建队列缩略图，避免快速滚动与视频解码争抢磁盘和解码器。
  }

  /**
   * 媒体确认可播放后再预取队列窗口，避免大文件首次 open 与 FFprobe/缩略图任务争抢磁盘。
   */
  void _scheduleQueuePrefetch() {
    _queuePrefetchTimer?.cancel();
    _queuePrefetchTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted && !_openRequests.isOpening) {
        _prefetchQueueWindow();
      }
    });
  }

  Future<void> _applyPlaybackPerformanceProfile() async {
    final options = <String, String>{
      'video-sync': 'display-resample',
      'interpolation': 'no',
      // 固定解码并发，避免 FFmpeg 在高核心数机器上为单个视频扩张大量工作线程。
      'vd-lavc-threads': '4',
      'cache': 'yes',
      'hwdec': _requestedHwdec,
      // 允许 mpv 对高分辨率 HEVC/VP9/AV1 等编码尝试用户选择的硬解后端。
      'hwdec-codecs': 'all',
      // 缓存暂时耗尽时让 mpv 等待输入恢复，不以连续丢帧追赶播放时钟。
      'cache-pause': 'yes',
      'demuxer-readahead-secs': '15',
      'demuxer-max-bytes': '96MiB',
      'demuxer-max-back-bytes': '32MiB',
    };
    for (final entry in options.entries) {
      await _setMpvProperty(entry.key, entry.value);
    }
    // 部分后端会在打开新媒体时重建渲染参数；每次 open 前后恢复用户当前比例。
    await _applyVideoAspectMode();
  }

  Future<void> _setMpvProperty(String property, String value) async {
    try {
      final platform = _playerBackend;
      await platform.setProperty(property, value);
    } catch (_) {
      // 部分 mpv 构建会拒绝少数属性；诊断信息会展示实际生效值。
    }
  }

  Future<String> _getMpvProperty(String property) async {
    try {
      final platform = _playerBackend;
      final value = await platform.getProperty(property);
      final text = value.toString().trim();
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
    final compatibility = PlayerHardwareCompatibility.assess(
      details: _currentItem.mediaDetails,
      settings: widget.playbackSettings,
    );
    if (_openedPath != null &&
        _openedPath != _currentItem.path &&
        compatibility.status == HardwareDecodeCompatibilityStatus.unsupported) {
      // 队列切换先保留当前播放会话；超规格媒体不交给 open worker。
      unawaited(_confirmQueueHardwareDecodeRisk(
        _currentItem,
        compatibility,
      ));
      return;
    }
    if (_openRequests.request(_currentItem.path)) {
      unawaited(_drainOpenRequests());
    }
  }

  /**
   * 串行阻止播放器队列内的超规格视频。
   *
   * 取消时恢复已经打开的视频索引；用户快速选择其它项时丢弃旧结果并重新评估
   * 最新选择，避免过期弹窗打开错误媒体。
   */
  Future<void> _confirmQueueHardwareDecodeRisk(
    VideoItem item,
    HardwareDecodeCompatibilityAssessment compatibility,
  ) async {
    if (_compatibilityPromptPath != null) {
      return;
    }
    final requestedPath = item.path;
    _compatibilityPromptPath = requestedPath;
    await showPlayerHardwareDecodeWarningDialog(
      context,
      compatibility,
    );
    _compatibilityPromptPath = null;
    if (!mounted) {
      return;
    }
    if (_currentItem.path != requestedPath) {
      _requestOpenCurrent();
      return;
    }
    final openedPath = _openedPath;
    final openedIndex = openedPath == null
        ? -1
        : _queue.indexWhere((video) => video.path == openedPath);
    if (openedIndex >= 0) {
      setState(() => _playback.jumpTo(openedIndex));
      _ensureQueueIndexVisible(openedIndex, center: true);
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
          // 每个新媒体独立判断实际解码器，不能沿用上一条视频的 no/恢复状态。
          _lastHwdecCurrent = null;
          _consecutiveSoftwareDecodeSamples = 0;
          _softwareDecodeConfirmed = false;
          await _applyPlaybackPerformanceProfile();
          if (!mounted) {
            return;
          }
          await _playerBackend.openPath(path);
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
              await _playerBackend.stop();
            }
            continue;
          }
          _openedPath = path;
          unawaited(PlayerMemoryDiagnostics.logStage(
            'media_opened',
            backend: _playerBackend,
          ));
          _openRequests.markSuccess();
          _scheduleQueuePrefetch();
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
        duration: _playerBackend.state.duration,
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
    final duration = _playerBackend.state.duration;
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
      await _playerBackend.pause();
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
    await _seekWithDiagnostics(start);
    await _playerBackend.play();
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
    // 鼠标单击发生在已经可见的队列项上，只更新选中态；若此处立刻滚动，
    // 双击的第二击会落到移动后的另一行。离屏选中项由“定位已选中”显式定位。
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

  /** 从离屏位置回到播放项时同步选中态，避免两个高亮指向不同视频。 */
  void _returnToPlayingQueueItem(ScrollController controller) {
    if (_queue.isEmpty) {
      return;
    }
    setState(() => _playback.select(_index));
    _ensureQueueIndexVisible(
      _index,
      center: true,
      // 显式定位需要立即落点；大队列跨段动画会连续重建 Windows 无障碍树，
      // 不仅浪费可视区域 I/O，还可能让桌面端语义桥接失稳。
      animated: false,
      controller: controller,
    );
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
  }

  /** 切换或退出前补写当前位置、总时长和动态完成态。 */
  void _persistOpenedProgress() {
    final openedPath = _openedPath;
    final position = _playerBackend.state.position;
    final duration = _playerBackend.state.duration;
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
      await _playerBackend.stop();
      await widget.onDeleteFile(item);
      if (!mounted) {
        return;
      }
      setState(() {
        _queueEndReached = false;
        _playback.removeSelectedItem(item);
      });
      if (_queue.isEmpty) {
        await _exitPlayer();
        return;
      }
      _ensureQueueIndexVisible(_index, center: true);
      _requestOpenCurrent();
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
    final stat = await widget.fileSystem.statFile(item.path);
    final details = await _detailsService.detailsFor(item);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded),
            SizedBox(width: 10),
            Text('视频信息'),
          ],
        ),
        content: SizedBox(
          width: 700,
          height: math.min(590, MediaQuery.sizeOf(context).height * 0.72),
          child: SingleChildScrollView(
            child: Column(
              children: [
                PlayerDialogSectionCard(
                  title: '文件',
                  icon: Icons.insert_drive_file_outlined,
                  child: Column(
                    children: [
                      PlayerDialogInfoRow(
                          label: '文件名', value: item.title, emphasize: true),
                      PlayerDialogInfoRow(label: '路径', value: item.path),
                      PlayerDialogInfoRow(label: '目录', value: item.folder),
                      PlayerDialogInfoRow(
                        label: '大小',
                        value: _formatBytes(stat?.size ?? item.fileSize ?? 0),
                      ),
                      PlayerDialogInfoRow(
                        label: '修改时间',
                        value: stat?.modifiedAt?.toString() ?? '未知',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                PlayerDialogSectionCard(
                  title: '媒体',
                  icon: Icons.movie_outlined,
                  child: Column(
                    children: [
                      PlayerDialogInfoRow(
                          label: '视频', value: details.videoLabel),
                      PlayerDialogInfoRow(
                          label: '音频', value: details.audioLabel),
                      PlayerDialogInfoRow(
                          label: '媒体指纹', value: item.mediaFingerprint ?? '未读取'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                PlayerDialogSectionCard(
                  title: '整理状态',
                  icon: Icons.sell_outlined,
                  child: Column(
                    children: [
                      PlayerDialogInfoRow(
                          label: '标签',
                          value: item.tags.isEmpty
                              ? '未添加'
                              : (item.tags.toList()..sort()).join('、')),
                      PlayerDialogInfoRow(
                          label: '二级标签', value: _childTagSummary(item)),
                      PlayerDialogInfoRow(
                          label: '收藏', value: item.isFavorite ? '是' : '否'),
                    ],
                  ),
                ),
                if (item.mediaDetailsError != null ||
                    item.thumbnailError != null) ...[
                  const SizedBox(height: 12),
                  PlayerDialogSectionCard(
                    title: '异常',
                    icon: Icons.warning_amber_rounded,
                    child: Column(
                      children: [
                        if (item.mediaDetailsError != null)
                          PlayerDialogInfoRow(
                              label: '媒体信息', value: item.mediaDetailsError!),
                        if (item.thumbnailError != null)
                          PlayerDialogInfoRow(
                              label: '缩略图', value: item.thumbnailError!),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDiagnosticsDialog() async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => PlaybackDiagnosticsDialog(
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
      await widget.fileSystem.revealInFileManager(_currentItem.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开文件位置，请确认文件仍然存在')),
        );
      }
    }
  }

  Future<PlaybackDiagnosticsSnapshot> buildDiagnosticsSnapshot() async {
    final before = _playerBackend.state.position;
    final wasPlaying = _playerBackend.state.playing;
    final wasBuffering = _playerBackend.state.buffering;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final after = _playerBackend.state.position;
    final progressMs = after.inMilliseconds - before.inMilliseconds;
    final expectedMs = wasPlaying && !wasBuffering ? 900 : 0;
    final smooth = expectedMs == 0 || progressMs >= expectedMs;
    // 播放诊断只读已有详情，打开弹窗不能为兜底探测再创建一个 media_kit Player。
    final details =
        _detailsService.cachedDetailsFor(_currentItem) ?? const MediaDetails();
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
      'estimated-frame-number',
      'audio-pts',
      'native-render-requests',
      'native-rendered-frames',
      'native-skipped-renders',
      'native-texture-copies',
      'native-surface-resizes',
      'native-surface-width',
      'native-surface-height',
    ]) {
      mpv[property] = await _getMpvProperty(property);
    }
    final sampledHwdec = mpv['hwdec-current'];
    if (sampledHwdec != null &&
        sampledHwdec != 'empty' &&
        sampledHwdec != 'unavailable') {
      _lastHwdecCurrent = sampledHwdec;
    }
    final estimatedFps = _parseMpvNumber(mpv['estimated-vf-fps']);
    final frameDurationMs =
        estimatedFps == null || estimatedFps <= 0 ? null : 1000 / estimatedFps;
    final lines = <String>[
      '\u5f53\u524d\u89c6\u9891: ${_currentItem.title}',
      '\u64ad\u653e\u4f4d\u7f6e: ${_formatDuration(after)} / ${_formatDuration(_playerBackend.state.duration)}',
      '\u64ad\u653e\u72b6\u6001: ${_playerBackend.state.playing ? '\u64ad\u653e\u4e2d' : '\u6682\u505c'}',
      '\u7f13\u51b2\u72b6\u6001: ${_playerBackend.state.buffering ? '\u7f13\u51b2\u4e2d' : '\u6b63\u5e38'}',
      '\u91c7\u6837\u63a8\u8fdb: $progressMs ms / 1200 ms',
      '\u6d41\u7545\u63a8\u65ad: ${smooth ? '\u6b63\u5e38' : '\u53ef\u80fd\u5361\u987f\u6216\u89e3\u7801\u8ddf\u4e0d\u4e0a'}',
      '\u8bbe\u7f6e\u786c\u89e3: ${widget.playbackSettings.hwdec}',
      'mpv 请求硬解: $_requestedHwdec',
      'mpv \u5b9e\u9645\u786c\u89e3: ${mpv['hwdec-current']}',
      'mpv \u8f93\u51fa\u9a71\u52a8: ${mpv['current-vo']}',
      'mpv \u89c6\u9891\u7f16\u7801: ${mpv['video-codec']}',
      'mpv \u97f3\u9891\u7f16\u7801: ${mpv['audio-codec']}',
      'mpv \u5bb9\u5668 FPS: ${mpv['container-fps']}',
      'mpv \u4f30\u7b97\u89c6\u9891 FPS: ${mpv['estimated-vf-fps']}',
      '估算单帧耗时: ${frameDurationMs?.toStringAsFixed(2) ?? 'unavailable'} ms',
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
      '原生渲染请求: ${mpv['native-render-requests']}',
      '原生实际渲染帧: ${mpv['native-rendered-frames']}',
      '原生跳过渲染: ${mpv['native-skipped-renders']}',
      '原生纹理复制: ${mpv['native-texture-copies']}',
      '原生表面重建: ${mpv['native-surface-resizes']}',
      '原生表面尺寸: ${mpv['native-surface-width']}x${mpv['native-surface-height']}',
      '视频帧推进: $_videoProgressState',
      '视频当前帧号: ${_lastVideoFrameNumber ?? -1}',
      '视频停滞事件: $_videoStallEvents',
      '音频播放头推进: $_audioProgressState',
      '音频当前 PTS: ${_lastAudioPts?.toStringAsFixed(3) ?? 'unavailable'}',
      '音频停滞事件: $_audioStallEvents',
      '独立推进采样时间: ${_lastHealthSampleAt?.toIso8601String() ?? 'none'}',
      '退出请求时间: ${_exitRequestedAt?.toIso8601String() ?? 'none'}',
      '暂停确认时间: ${_pauseAcknowledgedAt?.toIso8601String() ?? 'none'}',
      '路由退出请求时间: ${_routePopRequestedAt?.toIso8601String() ?? 'none'}',
      '最近 seek 耗时: ${_lastSeekLatencyMs ?? -1} ms',
      '最近 seek 时间: ${_lastSeekAt?.toIso8601String() ?? 'none'}',
      '媒体详情活动读取: ${_detailsService.activeReads}',
      '媒体详情排队读取: ${_detailsService.queuedReads}',
      '\u89c6\u9891\u4fe1\u606f: ${details.videoLabel}',
      '\u97f3\u9891\u4fe1\u606f: ${details.audioLabel}',
      '\u5df2\u8bc6\u522b\u89c6\u9891\u8f68: ${_playerBackend.state.videoTrackCount}',
      '\u5df2\u8bc6\u522b\u97f3\u9891\u8f68: ${_playerBackend.state.audioTrackCount}',
      '\u97f3\u91cf: ${_playerBackend.state.volume.toStringAsFixed(0)}',
      '\u7f29\u7565\u56fe\u961f\u5217: ${widget.thumbnailService.isPaused ? '\u5df2\u6682\u505c' : '\u8fd0\u884c\u4e2d'}',
      '\u7f29\u7565\u56fe\u6d3b\u8dc3\u4efb\u52a1: ${widget.thumbnailService.activeJobs} / ${widget.thumbnailService.maxConcurrentJobs}',
      '\u7f29\u7565\u56fe\u540e\u53f0\u4efb\u52a1: ${widget.thumbnailService.activeBackgroundJobs} / ${widget.thumbnailService.maxBackgroundJobs}',
      '\u7f29\u7565\u56fe\u6392\u961f: ${widget.thumbnailService.queuedJobs}',
      '\u8fdb\u7a0b\u5185\u5b58: ${_formatBytes(ProcessInfo.currentRss)}',
      '\u5904\u7406\u5668\u6838\u5fc3: ${Platform.numberOfProcessors}',
      if (_openRequests.hasFailure)
        '最近打开错误类型: ${_openRequests.failureCode ?? 'unknown'}',
    ];
    return PlaybackDiagnosticsSnapshot(
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
      hwdecCurrent: _lastHwdecCurrent,
      videoCodec:
          mpv['video-codec'] == 'empty' || mpv['video-codec'] == 'unavailable'
              ? details.videoCodec
              : mpv['video-codec'],
      videoWidth: details.width,
      videoHeight: details.height,
      seekLatencyMs: _lastSeekLatencyMs,
      detailsQueued: _detailsService.queuedReads,
      frameDurationMs: frameDurationMs,
      videoStalled: _videoProgressState == '视频帧停滞',
      audioStalled: _audioProgressState == '音频播放头停滞',
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
    if (_isWindowFullscreen && event.logicalKey == LogicalKeyboardKey.escape) {
      // Escape 是桌面全屏的固定安全出口，必须先于页面返回逻辑消费。
      unawaited(_toggleWindowFullscreen());
      return KeyEventResult.handled;
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
    final pressedKey = _playerShortcutKeyId(event.logicalKey);
    final shortcuts = widget.playbackSettings.shortcuts;
    bool matches(PlayerShortcutAction action) =>
        pressedKey != null && shortcuts[action] == pressedKey;
    if (matches(PlayerShortcutAction.playPause)) {
      unawaited(_playerBackend.playOrPause());
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.seekBackward)) {
      unawaited(_seekWithDiagnostics(
          _playerBackend.state.position - const Duration(seconds: 5)));
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.seekForward)) {
      unawaited(_seekWithDiagnostics(
          _playerBackend.state.position + const Duration(seconds: 5)));
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.previous)) {
      _jumpTo(_index - 1, ignoreFollowUpSelection: true);
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.next)) {
      _jumpTo(_index + 1, ignoreFollowUpSelection: true);
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.editTags)) {
      unawaited(_editManualTags());
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.screenshot)) {
      unawaited(_saveCurrentFrameScreenshot());
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.fullscreen)) {
      unawaited(_toggleWindowFullscreen());
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.speedDown)) {
      _stepPlaybackRate(-1);
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.speedUp)) {
      _stepPlaybackRate(1);
      return KeyEventResult.handled;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _moveQueueSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveQueueSelection(1);
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
        unawaited(_exitPlayer());
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons == kBackMouseButton) {
      unawaited(_exitPlayer());
    }
  }

  @override
  void dispose() {
    _openRequests.cancel();
    _controlsHideTimer?.cancel();
    _queuePrefetchTimer?.cancel();
    _fullscreenQueueHideTimer?.cancel();
    _playbackHealthTimer?.cancel();
    _playerBackend.textureId.removeListener(_handleTextureReadyForDiagnostics);
    _detailsService.dispose();
    _persistOpenedProgress();
    _queueScrollController.dispose();
    _fullscreenQueueScrollController.dispose();
    _queueSearchFocusNode.dispose();
    _queueSearchController.dispose();
    _focusNode.dispose();
    unawaited(_releaseAsyncResources());
    super.dispose();
  }

  /**
   * 等待流订阅和 media_kit 原生播放器真正释放，再通知媒体库允许下一次进入。
   */
  Future<void> _releaseAsyncResources() async {
    final releaseStartedAt = DateTime.now();
    await PlayerMemoryDiagnostics.logStage(
      'dispose_started',
      backend: _playerBackend,
    );
    try {
      await Future.wait<void>([
        if (_completedSubscription != null) _completedSubscription!.cancel(),
        if (_playerErrorSubscription != null)
          _playerErrorSubscription!.cancel(),
        if (_positionSubscription != null) _positionSubscription!.cancel(),
        if (_playingSubscription != null) _playingSubscription!.cancel(),
      ]);
      // stop 与 dispose 必须串行；此前路由 pop 后两者可能并发进入 media_kit/libmpv，
      // 导致纹理解绑完成但解码池和驱动缓存更晚才释放。
      await (_exitStopFuture ??= _stopForExitDiagnostics());
      await _playerBackend.dispose();
      await _playerBackend.released;
    } finally {
      await PlayerMemoryDiagnostics.logStage('player_disposed');
      debugPrint(
        'PLAYER_EXIT requested=${_exitRequestedAt?.toIso8601String()} '
        'pause_ack=${_pauseAcknowledgedAt?.toIso8601String()} '
        'pop=${_routePopRequestedAt?.toIso8601String()} '
        'dispose_start=${releaseStartedAt.toIso8601String()} '
        'dispose_end=${DateTime.now().toIso8601String()}',
      );
      if (!widget.disposalCompleter.isCompleted) {
        widget.disposalCompleter.complete();
      }
    }
  }

  /** 构建当前 filtered queue 侧栏；不同布局实例使用独立滚动控制器。 */
  Widget _buildQueueSidebar({
    ScrollController? scrollController,
    Key? key,
  }) {
    final controller = scrollController ?? _queueScrollController;
    final queuePanel = PlayerQueueSidebar(
      key: const ValueKey('player.queue.sidebar.content'),
      embedded: true,
      playlist: _queue,
      sourcePlaylist: _sourcePlaylist,
      playingIndex: _index,
      selectedIndex: _selectedIndex,
      scrollController: controller,
      thumbnailService: widget.thumbnailService,
      detailsService: _detailsService,
      activeTags: widget.activeTags,
      selectedChildTag: _selectedChildTag,
      onChildTagSelected: _selectChildTag,
      onSelect: _select,
      onPlay: _jumpTo,
      onReturnToPlaying: () => _returnToPlayingQueueItem(controller),
      onLocateSelected: () => _ensureQueueIndexVisible(
        _selectedIndex,
        center: true,
        // 与“回到播放”一致，一次跳转避免大队列动画期间的语义节点风暴。
        animated: false,
        controller: controller,
      ),
      onSearchQueue: _searchQueue,
      onDeleteSelected: _selectedIndex == _index ? _deleteSelectedFile : null,
    );
    return PlayerSidePanel(
      key: key ?? const ValueKey('player.queue.sidebar'),
      queuePanel: queuePanel,
      item: _currentItem,
      queueEndReached: _queueEndReached,
      onToggleFavorite: () {
        unawaited(widget.onToggleFavorite(_currentItem));
        setState(() {});
      },
      onEditManualTags: () => unawaited(_editManualTags()),
      onRevealFile: () => unawaited(_revealCurrentFile()),
      onVideoInfo: () => unawaited(_showVideoInfoDialog()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 中窄窗口改用底部队列，避免侧栏挤压蓝图式横向控制层。
    final hasWideQueueSidebar = MediaQuery.sizeOf(context).width >= 1100;
    final queueSidebar = _buildQueueSidebar();
    return Theme(
      data: _playerPageTheme(),
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Listener(
          onPointerDown: _handlePointerDown,
          child: Scaffold(
            backgroundColor: const Color(0xff070d1d),
            body: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    children: [
                      if (!_isWindowFullscreen)
                        _PlayerTopBar(
                          searchController: _queueSearchController,
                          searchFocusNode: _queueSearchFocusNode,
                          onBack: () => unawaited(_exitPlayer()),
                          onSearch: _searchQueue,
                          onOpenQueue: hasWideQueueSidebar
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
                                      key: const ValueKey(
                                          'player.video.surface'),
                                      margin: _isWindowFullscreen
                                          ? EdgeInsets.zero
                                          : const EdgeInsets.fromLTRB(
                                              18, 18, 18, 12),
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: const Color(0xff1f2937)),
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
                                                child: _playerBackend
                                                    .buildVideoSurface(
                                                  controls:
                                                      _buildVideoControls(),
                                                  fit: _videoAspectMode
                                                      .surfaceFit,
                                                  aspectRatio: _videoAspectMode
                                                      .surfaceAspectRatio,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (_openRequests.isOpening)
                                            const Positioned.fill(
                                              child: ColoredBox(
                                                color: Color(0x66000000),
                                                child: Center(
                                                    child:
                                                        CircularProgressIndicator()),
                                              ),
                                            ),
                                          if (!_openRequests.isOpening &&
                                              _openRequests.hasFailure)
                                            Positioned.fill(
                                              child: PlayerOpenFailurePanel(
                                                failureCode:
                                                    _openRequests.failureCode ??
                                                        'unknown',
                                                canSkip: _playback.hasNext,
                                                onRetry: _retryFailedOpen,
                                                onSkip: _skipFailedOpen,
                                                onDiagnostics: () {
                                                  unawaited(
                                                      _showDiagnosticsDialog());
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
                                ],
                              ),
                            ),
                            if (_isWindowFullscreen && _fullscreenQueueVisible)
                              TweenAnimationBuilder<double>(
                                key: const ValueKey('player.fullscreenQueue'),
                                tween: Tween<double>(begin: 0, end: 440),
                                duration: appMotionDuration,
                                curve: appMotionCurve,
                                builder: (context, width, child) {
                                  return SizedBox(
                                    width: width,
                                    child: ClipRect(
                                      child: OverflowBox(
                                        alignment: Alignment.centerRight,
                                        minWidth: 440,
                                        maxWidth: 440,
                                        child: child,
                                      ),
                                    ),
                                  );
                                },
                                child: MouseRegion(
                                  onEnter: (_) => _showFullscreenQueueSidebar(),
                                  onExit: (_) => _scheduleFullscreenQueueHide(),
                                  child: SafeArea(
                                    child: _buildQueueSidebar(
                                      key: const ValueKey(
                                          'player.fullscreenQueue.sidebar'),
                                      scrollController:
                                          _fullscreenQueueScrollController,
                                    ),
                                  ),
                                ),
                              ),
                            if (hasWideQueueSidebar && !_isWindowFullscreen)
                              AnimatedSize(
                                duration: appMotionDuration,
                                curve: appMotionCurve,
                                child: ClipRect(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    widthFactor: _queueSidebarCollapsed ? 0 : 1,
                                    child: IgnorePointer(
                                      ignoring: _queueSidebarCollapsed,
                                      child: queueSidebar,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isWindowFullscreen)
                  Positioned(
                    key: const ValueKey('player.fullscreenQueue.edge'),
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: widget.playbackSettings.fullscreenQueueEdgeWidth
                        .toDouble(),
                    child: MouseRegion(
                      opaque: true,
                      onEnter: (_) => _showFullscreenQueueSidebar(),
                      child: const SizedBox.expand(),
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

/** 播放器范围统一使用暗色弹窗、菜单、输入框和按钮语义。 */
ThemeData _playerPageTheme() {
  const surface = Color(0xff111a2b);
  const border = Color(0xff2a3855);
  return ThemeData.dark(useMaterial3: true).copyWith(
    colorScheme: const ColorScheme.dark(
      primary: Color(0xff8b73ff),
      surface: surface,
      onSurface: Color(0xffe7ecf7),
      outline: border,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: border),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xff151f32),
      surfaceTintColor: Colors.transparent,
      textStyle: const TextStyle(color: Color(0xffe7ecf7), fontSize: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: const BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xff0b1425),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xff7457ff)),
      ),
    ),
  );
}

/** 将 Flutter 逻辑键归一为设置 JSON 使用的稳定标识。 */
String? _playerShortcutKeyId(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.space) return 'Space';
  if (key == LogicalKeyboardKey.keyJ) return 'J';
  if (key == LogicalKeyboardKey.keyL) return 'L';
  if (key == LogicalKeyboardKey.keyT) return 'T';
  if (key == LogicalKeyboardKey.keyF) return 'F';
  if (key == LogicalKeyboardKey.keyS) return 'S';
  if (key == LogicalKeyboardKey.pageUp) return 'PageUp';
  if (key == LogicalKeyboardKey.pageDown) return 'PageDown';
  if (key == LogicalKeyboardKey.arrowLeft) return 'ArrowLeft';
  if (key == LogicalKeyboardKey.arrowRight) return 'ArrowRight';
  if (key == LogicalKeyboardKey.bracketLeft) return 'BracketLeft';
  if (key == LogicalKeyboardKey.bracketRight) return 'BracketRight';
  return null;
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
            key: const ValueKey('player.back'),
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
