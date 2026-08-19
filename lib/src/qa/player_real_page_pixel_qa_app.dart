import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import '../core/playback_settings.dart';
import '../features/player/application/player_fullscreen_lifecycle_controller.dart';
import '../models/video_item.dart';
import '../pages/player/player_page.dart';
import '../platform/desktop_file_system_adapter.dart';
import '../services/media/external_media_tools.dart';
import '../services/media/media_probe_backend.dart';
import '../services/media/thumbnail_service.dart';
import '../services/player/media_kit_player_backend.dart';
import '../services/player/player_service.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 判断是否启动真实 PlayerPage 的 Debug 桌面像素 QA。
 *
 * 与直接 MediaKit 表面 QA 相比，此入口刻意挂载产品使用的 PlayerPage、进度条、快捷键
 * 和 Texture 视图；它仍不加载资料库、不写入播放进度，也不会出现在正式路由中。
 */
bool shouldRunPlayerRealPagePixelQa({Map<String, String>? environment}) {
  final values = environment ?? Platform.environment;
  return kDebugMode &&
      Platform.isWindows &&
      values['LOCAL_TAG_PLAYER_REAL_PAGE_PIXEL_QA'] == '1';
}

/** 启动只读单项、正式 MediaKit Texture PlayerPage 的独立 QA 进程。 */
Future<void> runPlayerRealPagePixelQa() async {
  final environment = Platform.environment;
  final samplePath = environment['LOCAL_TAG_PLAYER_PIXEL_SAMPLE']?.trim();
  final outputRoot = environment['LOCAL_TAG_PLAYER_PIXEL_OUTPUT']?.trim();
  final windowWidth = _readQaWindowDimension(
    'LOCAL_TAG_PLAYER_PIXEL_WINDOW_WIDTH',
    fallback: 1280,
  );
  final windowHeight = _readQaWindowDimension(
    'LOCAL_TAG_PLAYER_PIXEL_WINDOW_HEIGHT',
    fallback: 720,
  );
  if (samplePath == null ||
      samplePath.isEmpty ||
      !File(samplePath).existsSync()) {
    throw StateError('真实 PlayerPage 像素 QA 缺少可读取的本地样本');
  }
  if (outputRoot == null || outputRoot.isEmpty) {
    throw StateError('真实 PlayerPage 像素 QA 缺少匿名输出根目录');
  }
  final outputDirectory = Directory(outputRoot);
  if (!outputDirectory.existsSync()) {
    throw StateError('真实 PlayerPage 像素 QA 输出根目录不存在');
  }
  final progressDragSeekMode = _readProgressDragSeekMode(environment);
  final manualKeyboardQa =
      environment['LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_QA'] == '1';
  final automatedLongHoldQa =
      environment['LOCAL_TAG_PLAYER_PIXEL_AUTOMATED_LONG_HOLD_QA'] == '1';
  final manualKeyboardAction =
      environment['LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_ACTION'] == 'backward'
          ? 'backward'
          : 'forward';
  final manualKeyboardHoldMode =
      environment['LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_HOLD_MODE'] == 'long'
          ? 'long'
          : 'short';

  WidgetsFlutterBinding.ensureInitialized();
  _appendLifecycle(outputDirectory, 'bootstrap_started');
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: Size(windowWidth.toDouble(), windowHeight.toDouble()),
      minimumSize: const Size(960, 540),
      title: 'LocalTagPlayer Real PlayerPage QA',
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  _appendLifecycle(outputDirectory, 'window_ready_before_run_app');
  runApp(
    _PlayerRealPagePixelQaApp(
      samplePath: samplePath,
      outputDirectory: outputDirectory,
      progressDragSeekMode: progressDragSeekMode,
      manualKeyboardQa: manualKeyboardQa,
      automatedLongHoldQa: automatedLongHoldQa,
      manualKeyboardAction: manualKeyboardAction,
      manualKeyboardHoldMode: manualKeyboardHoldMode,
    ),
  );
}

int _readQaWindowDimension(String name, {required int fallback}) {
  final parsed = int.tryParse(Platform.environment[name] ?? '');
  return parsed != null && parsed > 0 ? parsed : fallback;
}

/** 两阶段策略仅由独立 Debug QA 显式传入；未知值安全回退为正式单次精确定位。 */
PlayerProgressDragSeekMode _readProgressDragSeekMode(
  Map<String, String> environment,
) =>
    environment['LOCAL_TAG_PLAYER_QA_PROGRESS_DRAG_SEEK_MODE'] ==
            'fastPreviewThenExact'
        ? PlayerProgressDragSeekMode.fastPreviewThenExact
        : PlayerProgressDragSeekMode.exactOnly;

/**
 * 为反向键盘 QA 选择一个远离媒体起点的静止基线。
 *
 * 反向快捷键以十秒为步长；若自然播放刚超过七秒就暂停，第一次反向会落在零秒附近，
 * 桌面像素没有变化时无法区分“正确停在首帧”和“新帧没有送到 Texture”。该函数只供
 * 隔离 Debug QA 使用，不改变正式 PlayerPage 的播放起点或用户播放进度。
 */
Duration? playerQaReverseBaselineTarget({
  required Duration duration,
  required Duration position,
}) {
  const minimumTarget = Duration(seconds: 18);
  const maximumTarget = Duration(seconds: 30);
  const tailGuard = Duration(seconds: 5);
  if (position >= minimumTarget || duration <= minimumTarget + tailGuard) {
    return null;
  }
  final usableEnd = duration - tailGuard;
  final target = usableEnd < maximumTarget ? usableEnd : maximumTarget;
  return target > position ? target : null;
}

/** 生命周期只写固定阶段与 UTC，不写媒体标识、路径、画面或输入坐标。 */
void _appendLifecycle(Directory outputDirectory, String event) {
  File('${outputDirectory.path}${Platform.pathSeparator}qa-lifecycle.jsonl')
      .writeAsStringSync(
    '${jsonEncode(<String, Object?>{
          'event': event,
          'utcUs': DateTime.now().toUtc().microsecondsSinceEpoch,
        })}\n',
    mode: FileMode.append,
    flush: true,
  );
}

class _PlayerRealPagePixelQaApp extends StatefulWidget {
  const _PlayerRealPagePixelQaApp({
    required this.samplePath,
    required this.outputDirectory,
    required this.progressDragSeekMode,
    required this.manualKeyboardQa,
    required this.automatedLongHoldQa,
    required this.manualKeyboardAction,
    required this.manualKeyboardHoldMode,
  });

  final String samplePath;
  final Directory outputDirectory;
  final PlayerProgressDragSeekMode progressDragSeekMode;
  /** 实体键盘 QA 只显示测试提示；正式 PlayerPage 永不挂载该浮层。 */
  final bool manualKeyboardQa;
  /** 自动化 virtual-key 长按只用于桌面像素诊断，正式页面永不读取该环境变量。 */
  final bool automatedLongHoldQa;
  /** 仅用于 Debug 门禁提示；正式页面永远不读取该环境变量。 */
  final String manualKeyboardAction;
  /** 实体键盘 QA 的短按/长按合同；正式页面永远不读取该环境变量。 */
  final String manualKeyboardHoldMode;

  @override
  State<_PlayerRealPagePixelQaApp> createState() =>
      _PlayerRealPagePixelQaAppState();
}

class _PlayerRealPagePixelQaAppState extends State<_PlayerRealPagePixelQaApp> {
  final GlobalKey<PlayerPageState> _playerKey = GlobalKey<PlayerPageState>();
  final Completer<void> _disposalCompleter = Completer<void>();
  final PlayerFullscreenSessionController _fullscreenSession =
      PlayerFullscreenSessionController();
  late final DesktopFFmpegBackend _ffmpegBackend = DesktopFFmpegBackend();
  late final ThumbnailService _thumbnailService = ThumbnailService.forDirectory(
    Directory(
        '${widget.outputDirectory.path}${Platform.pathSeparator}thumbnail-index'),
    _ffmpegBackend,
  );
  late final VideoItem _item = VideoItem(
    // 固定匿名身份仅存在于隔离进程内，绝不与资料库的 stable identity 混用。
    videoId: 'desktop-pixel-qa-item',
    path: widget.samplePath,
    title: 'Desktop Pixel QA sample',
    folder: File(widget.samplePath).parent.path,
    tags: const <String>{},
    addedAt: DateTime.utc(2026, 8, 18),
  );
  late final File _shutdownRequest = File(
    '${widget.outputDirectory.path}${Platform.pathSeparator}shutdown.request',
  );
  late final File _rendererEvents = File(
    '${widget.outputDirectory.path}${Platform.pathSeparator}renderer-events.jsonl',
  );
  Timer? _readyTimer;
  Timer? _shutdownTimer;
  Timer? _manualForwardResumeTimer;
  Timer? _rendererTimer;
  var _ready = false;
  var _preparingReady = false;
  var _shuttingDown = false;
  var _manualForwardResumeStarted = false;
  var _rendererProbeBusy = false;
  bool? _lastFullscreen;
  int? _lastTextureGeneration;
  double? _lastTextureWidth;
  double? _lastTextureHeight;

  @override
  void initState() {
    super.initState();
    _appendLifecycle(widget.outputDirectory, 'state_initialized');
    _readyTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => unawaited(_pauseWhenPlayerPageIsReady()),
    );
    _shutdownTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => unawaited(_shutdownWhenRequested()),
    );
    // 全屏 QA 只读地采样窗口状态与 Texture 代次；它不参与正式页面布局，也不创建
    // 第二个播放器。稳定事件由门禁脚本与桌面几何变化联合验收。
    _rendererTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => unawaited(_recordRendererState()),
    );
    // 长按前进的正式语义是连续播放。QA 先冻结画面建立静态基线，再只在实体或
    // 显式 virtual-key 长按的首个 forward Down 后恢复播放；这样不会把等待输入或
    // 自然播放帧算进首帧延迟，也不改变正式页面的暂停/播放行为。
    if ((widget.manualKeyboardQa || widget.automatedLongHoldQa) &&
        (!widget.manualKeyboardQa ||
            (widget.manualKeyboardHoldMode == 'long' &&
                widget.manualKeyboardAction == 'forward'))) {
      _manualForwardResumeTimer = Timer.periodic(
        const Duration(milliseconds: 20),
        (_) => unawaited(_resumeAfterForwardScanDown()),
      );
    }
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    _shutdownTimer?.cancel();
    _manualForwardResumeTimer?.cancel();
    _rendererTimer?.cancel();
    super.dispose();
  }

  Future<void> _recordRendererState() async {
    if (_rendererProbeBusy || _shuttingDown) return;
    final player = _playerKey.currentState;
    if (player == null) return;
    _rendererProbeBusy = true;
    try {
      final fullscreen = await windowManager.isFullScreen();
      if (_shuttingDown) return;
      final surface = player.playerService.videoSurfaceDiagnostics;
      final generation = surface.textureGenerationCount;
      final width = surface.textureWidthPx;
      final height = surface.textureHeightPx;
      final changed = _lastFullscreen != fullscreen ||
          _lastTextureGeneration != generation ||
          _lastTextureWidth != width ||
          _lastTextureHeight != height;
      if (!changed) return;
      _lastFullscreen = fullscreen;
      _lastTextureGeneration = generation;
      _lastTextureWidth = width;
      _lastTextureHeight = height;
      _rendererEvents.writeAsStringSync(
        '${jsonEncode(<String, Object?>{
              'event': fullscreen ? 'fullscreen_settled' : 'windowed_settled',
              'utcUs': DateTime.now().toUtc().microsecondsSinceEpoch,
              'fullscreen': fullscreen,
              'textureGenerationCount': generation,
              'textureWidthPx': width,
              'textureHeightPx': height,
              'adaptiveTextureSizingEnabled':
                  surface.adaptiveTextureSizingEnabled,
              'textureResizeState': surface.textureResizeState,
            })}\n',
        mode: FileMode.append,
        flush: true,
      );
    } finally {
      _rendererProbeBusy = false;
    }
  }

  Future<void> _resumeAfterForwardScanDown() async {
    if (!_ready ||
        _manualForwardResumeStarted ||
        _shuttingDown ||
        (!widget.manualKeyboardQa && !widget.automatedLongHoldQa)) {
      return;
    }
    final evidenceName = widget.manualKeyboardQa
        ? 'native-keyboard-qpc-events.jsonl'
        : 'player-input-events.jsonl';
    final evidence = File(
      '${widget.outputDirectory.path}${Platform.pathSeparator}$evidenceName',
    );
    if (!evidence.existsSync()) return;
    bool hasForwardDown;
    try {
      hasForwardDown = evidence.readAsLinesSync().any((line) =>
          line.contains(widget.manualKeyboardQa
              ? '"event":"native_keyboard_message"'
              : '"event":"player_keyboard_event"') &&
          line.contains('"action":"forward"') &&
          line.contains('"phase":"down"'));
    } on FileSystemException {
      // 原生观察器可能正在 flush 当前 JSONL 行；下一次 20ms tick 再重试。
      return;
    }
    if (!hasForwardDown) return;
    _manualForwardResumeStarted = true;
    _manualForwardResumeTimer?.cancel();
    final player = _playerKey.currentState;
    if (player == null || player.playerService.state.playing) return;
    try {
      await player.playerService.play();
      _appendLifecycle(
        widget.outputDirectory,
        widget.manualKeyboardQa
            ? 'manual_long_forward_play_started'
            : 'automated_long_forward_play_started',
      );
    } catch (_) {
      // 只读 QA 的恢复失败留给像素门禁报告；不向正式页面泄漏异常。
    }
  }

  Future<void> _pauseWhenPlayerPageIsReady() async {
    if (_ready || _preparingReady || _shuttingDown) return;
    final player = _playerKey.currentState;
    if (player == null) return;
    final state = player.playerService.state;
    if (player.playerService.textureId.value == null ||
        state.duration <= const Duration(seconds: 12) ||
        state.position <= const Duration(seconds: 7)) {
      return;
    }
    _preparingReady = true;
    try {
      final reverseBaselineTarget = playerQaReverseBaselineTarget(
        duration: state.duration,
        position: state.position,
      );
      if (reverseBaselineTarget != null) {
        // 仅把隔离 QA 基线移到可反向验证的区间；该 seek 不计入输入到像素时延。
        await player.playerService.seek(reverseBaselineTarget);
      }
      await player.playerService.pause();
      if (!mounted || _shuttingDown || player.playerService.state.playing) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted || _shuttingDown) return;
      // 外部 Win32 scan-code 只能由 PlayerPage 自己的 Focus 链收到。专用 QA 在静态
      // 基线前显式请求该既有 FocusNode，避免把窗口前台状态误当成 Flutter 键盘焦点；
      // 正式页面仍只在用户点击视频表面时请求焦点。
      player.focusNode.requestFocus();
      await WidgetsBinding.instance.endOfFrame;
      _ready = true;
      _readyTimer?.cancel();
      _writeReady(player);
      _appendLifecycle(widget.outputDirectory, 'paused_baseline_ready');
      if (widget.manualKeyboardQa) {
        _appendLifecycle(
            widget.outputDirectory, 'manual_keyboard_input_waiting');
      }
      setState(() {});
    } finally {
      if (!_ready) _preparingReady = false;
    }
  }

  void _writeReady(PlayerPageState player) {
    File('${widget.outputDirectory.path}${Platform.pathSeparator}ready.json')
        .writeAsStringSync(
      jsonEncode(<String, Object?>{
        'testProcessId': pid,
        'windowTitle': 'LocalTagPlayer Real PlayerPage QA',
        'backend': 'media-kit-flutter-texture',
        'surface': 'product-player-page',
        'state': 'paused-static-baseline-ready',
        'focusReady': player.focusNode.hasFocus,
        'manualKeyboardAction': widget.manualKeyboardAction,
        'manualKeyboardHoldMode': widget.manualKeyboardHoldMode,
        'automatedLongHoldQa': widget.automatedLongHoldQa,
        'progressDragSeekMode': widget.progressDragSeekMode.name,
        'adaptiveTextureSizingEnabled': player
            .playerService.videoSurfaceDiagnostics.adaptiveTextureSizingEnabled,
        'textureGenerationCount':
            player.playerService.videoSurfaceDiagnostics.textureGenerationCount,
      }),
      flush: true,
    );
  }

  Future<void> _shutdownWhenRequested() async {
    if (_shuttingDown || !_shutdownRequest.existsSync()) return;
    _shuttingDown = true;
    _readyTimer?.cancel();
    _shutdownTimer?.cancel();
    _appendLifecycle(widget.outputDirectory, 'shutdown_requested');
    // 先卸载真实页面，让其资源协调器经过既有 stop/dispose/released 链；不强杀含
    // D3D11/ANGLE 表面的进程，避免下一轮独立会话继承不完整的释放状态。
    runApp(const SizedBox.shrink());
    try {
      await _disposalCompleter.future.timeout(const Duration(seconds: 12));
      _appendLifecycle(widget.outputDirectory, 'player_resources_released');
    } on TimeoutException {
      _appendLifecycle(
          widget.outputDirectory, 'player_resources_release_timeout');
    } finally {
      exit(0);
    }
  }

  PlayerService _createPlayerService({
    required String hwdec,
    required bool enableHardwareAcceleration,
    required PlayerRendererPreference rendererPreference,
  }) {
    // 仅 Debug QA 可显式关闭自适应 Texture 尺寸，用来隔离“自然 4K 输出回落到
    // 稳定档位时的 Texture 重建”与 PlayerPage/输入链本身。正式进程不设置该变量，
    // 因此仍保持默认的自适应输出策略。
    final disableAdaptiveTextureSizing =
        Platform.environment['LOCAL_TAG_PLAYER_QA_DISABLE_ADAPTIVE_TEXTURE'] ==
            '1';
    final backend = MediaKitPlayerBackend(
      hwdec: hwdec,
      enableHardwareAcceleration: enableHardwareAcceleration,
      adaptiveTextureSizingEnabled: !disableAdaptiveTextureSizing,
    );
    return PlayerService(runtimeBackend: backend, surfaceRenderer: backend);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Stack(
          children: <Widget>[
            PlayerPage(
              key: _playerKey,
              initialItem: _item,
              playlist: <VideoItem>[_item],
              thumbnailService: _thumbnailService,
              playbackSettings: PlaybackSettings.defaults,
              // QA 不持久化设置、播放进度、标签或媒体详情；测试的唯一可写对象是显式
              // 输出根中的匿名生命周期与 Slider 语义回执。
              onPlaybackSettingsChanged: (_) async {},
              activeTags: const <String>[],
              activeChildTag: null,
              queueTitle: 'Desktop Pixel QA',
              onDeleteVideo: (_) async {},
              onToggleFavorite: (_) async {},
              onRenameFile: (_, __) async {},
              onEditManualTags: (_) async {},
              onRelinkMissing: (_) async => false,
              onPlaybackProgressUpdated: (_, __, ___, ____) async {},
              onMediaDetailsUpdated: (_, __, ___) async {},
              disposalCompleter: _disposalCompleter,
              fileSystem: const DesktopFileSystemAdapter(),
              playerServiceFactory: _createPlayerService,
              mediaProbeBackendFactory: () =>
                  createMediaProbeBackend(_ffmpegBackend),
              fullscreenSessionController: _fullscreenSession,
              progressDragSeekMode: widget.progressDragSeekMode,
            ),
            if (widget.manualKeyboardQa && _ready)
              Positioned(
                top: 20,
                left: 20,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xCC121212),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(
                        '实体键盘测量已就绪：请${widget.manualKeyboardHoldMode == 'long' ? '长按' : '短按'} ${widget.manualKeyboardAction == 'backward' ? 'J' : 'L'}${widget.manualKeyboardHoldMode == 'long' ? ' 后松开' : ' 一次'}',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}
