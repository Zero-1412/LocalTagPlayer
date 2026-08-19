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
import '../pages/player/player_state_precision_controls.dart';
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

/** Debug-only 软件解码复核开关；不进入正式启动路径或用户设置。 */
bool playerQaForceSoftwareDecode({Map<String, String>? environment}) {
  final values = environment ?? Platform.environment;
  return values['LOCAL_TAG_PLAYER_QA_FORCE_SOFTWARE_DECODE'] == '1';
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
  final precisionControlsQa =
      environment['LOCAL_TAG_PLAYER_PRECISION_CONTROLS_QA'] == '1';
  final steadyRuntimeQa =
      environment['LOCAL_TAG_PLAYER_STEADY_RUNTIME_QA'] == '1';
  final steadyRuntimeDurationMilliseconds =
      _readQaSteadyRuntimeDurationMilliseconds(environment);
  final automatedLongHoldQa =
      environment['LOCAL_TAG_PLAYER_PIXEL_AUTOMATED_LONG_HOLD_QA'] == '1';
  final automatedLongHoldAction =
      environment['LOCAL_TAG_PLAYER_PIXEL_AUTOMATED_LONG_HOLD_ACTION'] ==
              'backward'
          ? 'backward'
          : 'forward';
  final manualKeyboardAction =
      environment['LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_ACTION'] == 'backward'
          ? 'backward'
          : automatedLongHoldAction;
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
  if (environment['LOCAL_TAG_PLAYER_PIXEL_STARTUP_QA'] == '1') {
    _writeStartupMarker(outputDirectory);
    await _waitForStartupProbe(outputDirectory);
  }
  runApp(
    _PlayerRealPagePixelQaApp(
      samplePath: samplePath,
      outputDirectory: outputDirectory,
      progressDragSeekMode: progressDragSeekMode,
      manualKeyboardQa: manualKeyboardQa,
      automatedLongHoldQa: automatedLongHoldQa,
      precisionControlsQa: precisionControlsQa,
      steadyRuntimeQa: steadyRuntimeQa,
      steadyRuntimeDurationMilliseconds: steadyRuntimeDurationMilliseconds,
      manualKeyboardAction: manualKeyboardAction,
      manualKeyboardHoldMode: manualKeyboardHoldMode,
    ),
  );
}

/**
 * 在正式 PlayerPage 挂载前固定启动测量的墙钟锚点。
 *
 * Dart 与 Win32 探针没有共享的 Stopwatch 实例，因此这里只写 UTC 微秒；探针在同一
 * 台机器上用当前 QPC/UTC 对照把它换算为 QPC 起点，并在报告中保留该换算证据。该文件
 * 只存在于隔离 Debug QA 输出，不进入正式应用或用户数据。
 */
void _writeStartupMarker(Directory outputDirectory) {
  final marker = File(
    '${outputDirectory.path}${Platform.pathSeparator}startup-marker.json',
  );
  marker.writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'testProcessId': pid,
      'windowTitle': 'LocalTagPlayer Real PlayerPage QA',
      'backend': 'media-kit-flutter-texture',
      'surface': 'product-player-page',
      'state': 'window-shown-before-run-app',
      'utcUs': DateTime.now().toUtc().microsecondsSinceEpoch,
    }),
    flush: true,
  );
  _appendLifecycle(outputDirectory, 'startup_marker_before_run_app');
}

/** 启动探针附着前不挂载页面，避免测量起点落在首帧之后。 */
Future<void> _waitForStartupProbe(Directory outputDirectory) async {
  final probeReady = File(
    '${outputDirectory.path}${Platform.pathSeparator}startup-probe-ready.json',
  );
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!probeReady.existsSync() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  if (!probeReady.existsSync()) {
    throw StateError('启动 DWM 探针未在挂载 PlayerPage 前附着');
  }
  _appendLifecycle(outputDirectory, 'startup_probe_attached_before_run_app');
}

int _readQaWindowDimension(String name, {required int fallback}) {
  final parsed = int.tryParse(Platform.environment[name] ?? '');
  return parsed != null && parsed > 0 ? parsed : fallback;
}

/** Debug-only 稳态窗口时长；正式进程不读取该 QA 环境变量。 */
int _readQaSteadyRuntimeDurationMilliseconds(Map<String, String> environment) {
  final parsed = int.tryParse(
    environment['LOCAL_TAG_PLAYER_STEADY_RUNTIME_DURATION_MS'] ?? '',
  );
  return parsed != null && parsed >= 10000 ? parsed : 10000;
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
    required this.precisionControlsQa,
    required this.steadyRuntimeQa,
    required this.steadyRuntimeDurationMilliseconds,
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
  /** 仅 Debug QA：在真实 PlayerPage/NativePlayer 会话中验收倍速、逐帧、A/B 与外挂字幕。 */
  final bool precisionControlsQa;
  /** 仅 Debug QA：在正式 Texture 会话中记录独立稳态运行态分母。 */
  final bool steadyRuntimeQa;
  /** 稳态窗口目标时长，不进入正式播放语义或用户设置。 */
  final int steadyRuntimeDurationMilliseconds;
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
  late final File _steadyRuntimeSamples = File(
    '${widget.outputDirectory.path}${Platform.pathSeparator}steady-runtime-samples.jsonl',
  );
  late final File _steadyRuntimeSummary = File(
    '${widget.outputDirectory.path}${Platform.pathSeparator}steady-runtime-summary.json',
  );
  late final File _steadyRuntimeComplete = File(
    '${widget.outputDirectory.path}${Platform.pathSeparator}steady-runtime-complete.json',
  );
  Timer? _readyTimer;
  Timer? _shutdownTimer;
  Timer? _manualForwardResumeTimer;
  Timer? _precisionControlsTimer;
  Timer? _steadyRuntimeTimer;
  Timer? _rendererTimer;
  var _ready = false;
  var _preparingReady = false;
  var _shuttingDown = false;
  var _manualForwardResumeStarted = false;
  var _precisionControlsStarted = false;
  var _precisionControlsCompleted = false;
  var _steadyRuntimeStarted = false;
  var _steadyRuntimeSampleBusy = false;
  var _steadyRuntimeSampleCount = 0;
  var _steadyRuntimePlayingSampleCount = 0;
  var _steadyRuntimeBufferingSampleCount = 0;
  final Stopwatch _steadyRuntimeWatch = Stopwatch();
  DateTime? _steadyRuntimeStartedAt;
  var _rendererProbeBusy = false;
  var _startupSurfaceReadyPublished = false;
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
    // 长按前进/后退的正式语义都发生在播放时钟上。QA 先冻结画面建立静态基线，
    // 再只在实体或显式 virtual-key 长按的首个方向 Down 后恢复播放；这样不会把
    // 等待输入或自然播放帧算进首帧延迟，也不改变正式页面的暂停/播放行为。
    if ((widget.manualKeyboardQa || widget.automatedLongHoldQa) &&
        (!widget.manualKeyboardQa ||
            (widget.manualKeyboardHoldMode == 'long'))) {
      _manualForwardResumeTimer = Timer.periodic(
        const Duration(milliseconds: 20),
        (_) => unawaited(_resumeAfterKeyboardScanDown()),
      );
    }
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    _shutdownTimer?.cancel();
    _manualForwardResumeTimer?.cancel();
    _precisionControlsTimer?.cancel();
    _steadyRuntimeTimer?.cancel();
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
      // 这只是筛掉 runApp/布局背景变化的 backend readiness 辅助标记，不是 DWM 首帧；
      // 探针仍必须从 startup UTC 起点等待中心桌面像素连续变化。
      if (!_startupSurfaceReadyPublished &&
          File(
            '${widget.outputDirectory.path}${Platform.pathSeparator}startup-marker.json',
          ).existsSync() &&
          player.playerService.textureId.value != null &&
          player.playerService.state.duration > Duration.zero) {
        _startupSurfaceReadyPublished = true;
        File(
          '${widget.outputDirectory.path}${Platform.pathSeparator}startup-surface-ready.json',
        ).writeAsStringSync(
          '${jsonEncode(<String, Object?>{
                'schemaVersion': 1,
                'event': 'texture-id-and-duration-ready',
                'evidence': 'backend-readiness-only',
                'utcUs': DateTime.now().toUtc().microsecondsSinceEpoch,
                'textureGenerationCount': generation,
              })}\n',
          flush: true,
        );
      }
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

  Future<void> _resumeAfterKeyboardScanDown() async {
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
    final expectedAction = widget.manualKeyboardAction;
    bool hasExpectedDown;
    try {
      hasExpectedDown = evidence.readAsLinesSync().any((line) =>
          line.contains(widget.manualKeyboardQa
              ? '"event":"native_keyboard_message"'
              : '"event":"player_keyboard_event"') &&
          line.contains('"action":"$expectedAction"') &&
          line.contains('"phase":"down"'));
    } on FileSystemException {
      // 原生观察器可能正在 flush 当前 JSONL 行；下一次 20ms tick 再重试。
      return;
    }
    if (!hasExpectedDown) return;
    _manualForwardResumeStarted = true;
    _manualForwardResumeTimer?.cancel();
    // 反向长按必须从静态基线直接进入 PlayerPage 的 reverse-preview 命令；如果先
    // 恢复正向播放，探针会把自然播放的首帧误当成反向 seek 的呈现证据。前进长按
    // 才需要在首个 Down 后恢复播放时钟来测量连续扫描。
    if (expectedAction == 'backward') {
      _appendLifecycle(
        widget.outputDirectory,
        widget.manualKeyboardQa
            ? 'manual_long_backward_kept_paused_for_reverse_seek'
            : 'automated_long_backward_kept_paused_for_reverse_seek',
      );
      return;
    }
    final player = _playerKey.currentState;
    if (player == null || player.playerService.state.playing) return;
    try {
      await player.playerService.play();
      final playbackStage = expectedAction == 'backward'
          ? (widget.manualKeyboardQa
              ? 'manual_long_backward_play_started'
              : 'automated_long_backward_play_started')
          : (widget.manualKeyboardQa
              ? 'manual_long_forward_play_started'
              : 'automated_long_forward_play_started');
      _appendLifecycle(
        widget.outputDirectory,
        playbackStage,
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
      if (widget.steadyRuntimeQa) {
        if (!state.playing) {
          await player.playerService.play();
        }
        if (!mounted || _shuttingDown || !player.playerService.state.playing) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted || _shuttingDown) return;
        player.focusNode.requestFocus();
        await WidgetsBinding.instance.endOfFrame;
        _ready = true;
        _readyTimer?.cancel();
        _writeReady(player, state: 'steady-runtime-ready');
        _appendLifecycle(
          widget.outputDirectory,
          'steady_runtime_window_started',
        );
        setState(() {});
        _startSteadyRuntimeSampling(player);
        return;
      }
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
      if (widget.precisionControlsQa) {
        unawaited(_runPrecisionControlsQa());
      }
    } finally {
      if (!_ready) _preparingReady = false;
    }
  }

  void _writeReady(
    PlayerPageState player, {
    String state = 'paused-static-baseline-ready',
  }) {
    File('${widget.outputDirectory.path}${Platform.pathSeparator}ready.json')
        .writeAsStringSync(
      jsonEncode(<String, Object?>{
        'testProcessId': pid,
        'windowTitle': 'LocalTagPlayer Real PlayerPage QA',
        'backend': 'media-kit-flutter-texture',
        'surface': 'product-player-page',
        'state': state,
        'focusReady': player.focusNode.hasFocus,
        'manualKeyboardAction': widget.manualKeyboardAction,
        'manualKeyboardHoldMode': widget.manualKeyboardHoldMode,
        // QA 探针必须尊重当前播放器快捷键设置；只写固定动作对应的键名，
        // 不写路径、媒体身份或其它用户配置。
        'seekBackwardShortcut': player.effectivePlaybackSettings
            .shortcuts[PlayerShortcutAction.seekBackward],
        'seekForwardShortcut': player.effectivePlaybackSettings
            .shortcuts[PlayerShortcutAction.seekForward],
        'automatedLongHoldQa': widget.automatedLongHoldQa,
        'precisionControlsQa': widget.precisionControlsQa,
        'steadyRuntimeQa': widget.steadyRuntimeQa,
        'steadyRuntimeDurationMs': widget.steadyRuntimeDurationMilliseconds,
        'progressDragSeekMode': widget.progressDragSeekMode.name,
        'adaptiveTextureSizingEnabled': player
            .playerService.videoSurfaceDiagnostics.adaptiveTextureSizingEnabled,
        'forcedSoftwareDecodeQa': playerQaForceSoftwareDecode(),
        'textureGenerationCount':
            player.playerService.videoSurfaceDiagnostics.textureGenerationCount,
      }),
      flush: true,
    );
  }

  /**
   * 记录独立稳态播放窗口的匿名运行态快照。
   *
   * 该窗口不启动桌面像素探针，也不把后端属性升级为 DWM 呈现证据；它只为 decoder、
   * VO、total drop 和硬解状态提供有明确时间分母的辅助基线。窗口完成后才允许外部
   * 门禁请求释放当前 PlayerPage。
   */
  void _startSteadyRuntimeSampling(PlayerPageState player) {
    if (_steadyRuntimeStarted || _shuttingDown) return;
    _steadyRuntimeStarted = true;
    _steadyRuntimeStartedAt = DateTime.now().toUtc();
    _steadyRuntimeWatch
      ..reset()
      ..start();
    unawaited(_recordSteadyRuntimeSample(player));
    _steadyRuntimeTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_recordSteadyRuntimeSample(player)),
    );
  }

  Future<void> _recordSteadyRuntimeSample(PlayerPageState player) async {
    if (_steadyRuntimeSampleBusy ||
        !_steadyRuntimeStarted ||
        _shuttingDown ||
        (!_steadyRuntimeWatch.isRunning &&
            _steadyRuntimeWatch.elapsedMilliseconds >=
                widget.steadyRuntimeDurationMilliseconds)) {
      return;
    }
    _steadyRuntimeSampleBusy = true;
    try {
      final snapshot = await player.readSeekTraceRuntimeSnapshot();
      final state = player.playerService.state;
      final elapsedMilliseconds = _steadyRuntimeWatch.elapsedMilliseconds;
      final now = DateTime.now().toUtc();
      _steadyRuntimeSampleCount++;
      if (state.playing) _steadyRuntimePlayingSampleCount++;
      if (state.buffering) _steadyRuntimeBufferingSampleCount++;
      _steadyRuntimeSamples.writeAsStringSync(
        '${jsonEncode(<String, Object?>{
              'schemaVersion': 1,
              'event': 'steady-runtime-sample',
              'utcUs': now.microsecondsSinceEpoch,
              'elapsedMs': elapsedMilliseconds,
              'playing': state.playing,
              'buffering': state.buffering,
              'positionMs': state.position.inMilliseconds,
              ...snapshot,
            })}\n',
        mode: FileMode.append,
        flush: true,
      );
      if (elapsedMilliseconds >= widget.steadyRuntimeDurationMilliseconds) {
        _steadyRuntimeWatch.stop();
        _steadyRuntimeTimer?.cancel();
        final startedAt = _steadyRuntimeStartedAt;
        _steadyRuntimeSummary.writeAsStringSync(
          '${jsonEncode(<String, Object?>{
                'schemaVersion': 1,
                'evidence': 'backend-runtime-steady-window',
                'status': 'complete',
                'requestedDurationMs': widget.steadyRuntimeDurationMilliseconds,
                'actualDurationMs': elapsedMilliseconds,
                'sampleCount': _steadyRuntimeSampleCount,
                'playingSampleCount': _steadyRuntimePlayingSampleCount,
                'bufferingSampleCount': _steadyRuntimeBufferingSampleCount,
                'windowStartUtcUs': startedAt?.microsecondsSinceEpoch,
                'windowEndUtcUs': now.microsecondsSinceEpoch,
                'samplesFile': 'steady-runtime-samples.jsonl',
              })}\n',
          flush: true,
        );
        _steadyRuntimeComplete.writeAsStringSync(
          '${jsonEncode(<String, Object?>{
                'schemaVersion': 1,
                'event': 'steady-runtime-window-complete',
                'utcUs': now.microsecondsSinceEpoch,
              })}\n',
          flush: true,
        );
        _appendLifecycle(
          widget.outputDirectory,
          'steady_runtime_window_complete',
        );
      }
    } finally {
      _steadyRuntimeSampleBusy = false;
    }
  }

  /**
   * 在真实产品页面上串行验收专业控制命令；只保存阶段、结果和匿名属性读回。
   *
   * 该路径故意不走普通 seek 近似逐帧，也不使用文件选择器绕过外挂字幕边界。A/B
   * 状态与字幕文件只存在于隔离 Debug QA 目录，关闭进程后不进入设置、队列或媒体库。
   */
  Future<void> _runPrecisionControlsQa() async {
    if (_precisionControlsStarted || _shuttingDown || !_ready) return;
    _precisionControlsStarted = true;
    final player = _playerKey.currentState;
    if (player == null) {
      _precisionControlsCompleted = true;
      return;
    }
    var frameStepPresented = false;
    var playbackRateApplied = false;
    var playbackRateRestored = false;
    var abLoopASet = false;
    var abLoopBSet = false;
    var loopCompleted = false;
    var abLoopCleared = false;
    var subtitleLoaded = false;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final beforeFrame = await player.readPresentedVideoFrame();
      _appendPrecisionEvidence(<String, Object?>{
        'stage': 'frame_step_before',
        'frame': beforeFrame,
        'frameEvidence': player.lastPresentedVideoFrameEvidence,
      });
      // 给外部桌面合成观察器留出静止基线；该等待只存在于隔离 Debug QA，不能改变
      // 正式页面逐帧命令的用户可感知时序。
      await _precisionObservationDwell();
      try {
        await player.playerService.stepFrame(backward: false);
        frameStepPresented = await player.waitForPresentedVideoFrame(
          beforeFrame,
          const Duration(seconds: 2),
        );
      } catch (error) {
        _appendPrecisionEvidence(<String, Object?>{
          'stage': 'frame_step_error',
          'errorType': error.runtimeType.toString(),
        });
      }
      _appendPrecisionEvidence(<String, Object?>{
        'stage': 'frame_step_complete',
        'success': frameStepPresented,
        'frame': await player.readPresentedVideoFrame(),
        'frameEvidence': player.lastPresentedVideoFrameEvidence,
      });
      await _precisionObservationDwell();

      // 倍速 QA 只触碰当前 PlayerService，不调用页面的持久化设置入口；完成后恢复
      // 原倍速，避免 Debug QA 污染用户偏好或下一次播放器会话。
      const qaPlaybackRate = 1.5;
      final restorePlaybackRate = player.playbackRate;
      _appendPrecisionEvidence(<String, Object?>{
        'stage': 'playback_rate_before',
        'success': true,
        'requestedRate': restorePlaybackRate,
        'readbackRate': await player.playerService.getProperty('speed'),
      });
      try {
        await player.playerService.setRate(qaPlaybackRate);
        final readbackRate = await player.playerService.getProperty('speed');
        playbackRateApplied =
            _isPlaybackRateReadback(readbackRate, qaPlaybackRate);
        _appendPrecisionEvidence(<String, Object?>{
          'stage': 'playback_rate_complete',
          'success': playbackRateApplied,
          'requestedRate': qaPlaybackRate,
          'readbackRate': readbackRate,
        });
        await _precisionObservationDwell();
      } catch (error) {
        _appendPrecisionEvidence(<String, Object?>{
          'stage': 'playback_rate_error',
          'errorType': error.runtimeType.toString(),
        });
      } finally {
        try {
          await player.playerService.setRate(restorePlaybackRate);
          playbackRateRestored = true;
        } catch (error) {
          _appendPrecisionEvidence(<String, Object?>{
            'stage': 'playback_rate_restore_error',
            'errorType': error.runtimeType.toString(),
          });
        }
        _appendPrecisionEvidence(<String, Object?>{
          'stage': 'playback_rate_restored',
          'success': playbackRateRestored,
          'requestedRate': restorePlaybackRate,
        });
      }

      final start = player.playerService.state.position;
      await player.setAbLoopStartWithFeedback();
      abLoopASet = _isMpvAbLoopPoint(
        await player.playerService.getProperty('ab-loop-a'),
      );
      _appendPrecisionEvidence(<String, Object?>{
        'stage': 'ab_loop_a',
        'success': abLoopASet,
        'positionMs': start.inMilliseconds,
      });
      await _precisionObservationDwell();

      final end = start + const Duration(seconds: 2);
      await player.playerService.seek(end);
      await _waitForPlayerPosition(player, end);
      await player.setAbLoopEndWithFeedback();
      abLoopBSet = _isMpvAbLoopPoint(
        await player.playerService.getProperty('ab-loop-b'),
      );
      _appendPrecisionEvidence(<String, Object?>{
        'stage': 'ab_loop_b',
        'success': abLoopBSet,
        'positionMs': player.playerService.state.position.inMilliseconds,
      });
      await _precisionObservationDwell();

      // A/B 的命令读回不是循环播放验收。这里在隔离会话中实际播放，等待位置从
      // B 回到 A，再暂停并记录匿名循环证据；外部桌面观察器负责独立判断 Texture/DWM
      // 是否随该循环出现可见呈现变化。
      var loopReachedEnd = false;
      try {
        // 设置 B 点后当前播放头停在 B；回到 A 再播放，才能证明是 A→B→A
        // 的实际循环，而不是从 B 立即触发一次边界回退。
        await player.playerService.seek(start);
        await _waitForPlayerPosition(player, start);
        await player.playerService.play();
        _appendPrecisionEvidence(<String, Object?>{
          'stage': 'ab_loop_playback_started',
          'success': true,
          'positionMs': player.playerService.state.position.inMilliseconds,
        });
        final loopWatch = Stopwatch()..start();
        while (loopWatch.elapsed < const Duration(seconds: 5)) {
          final position = player.playerService.state.position;
          if (!loopReachedEnd &&
              position >= end - const Duration(milliseconds: 350)) {
            loopReachedEnd = true;
          } else if (loopReachedEnd &&
              position <= start + const Duration(milliseconds: 550)) {
            loopCompleted = true;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        await player.playerService.pause();
      } catch (error) {
        _appendPrecisionEvidence(<String, Object?>{
          'stage': 'ab_loop_playback_error',
          'errorType': error.runtimeType.toString(),
        });
      }
      _appendPrecisionEvidence(<String, Object?>{
        'stage': 'ab_loop_cycle_complete',
        'success': loopCompleted,
        'positionMs': player.playerService.state.position.inMilliseconds,
      });
      await _precisionObservationDwell();

      await player.clearAbLoopWithFeedback();
      final clearedA = await player.playerService.getProperty('ab-loop-a');
      final clearedB = await player.playerService.getProperty('ab-loop-b');
      abLoopCleared = clearedA == 'no' && clearedB == 'no';
      _appendPrecisionEvidence(<String, Object?>{
        'stage': 'ab_loop_clear',
        'success': abLoopCleared,
      });
      await _precisionObservationDwell();

      final subtitle = File(
        '${widget.outputDirectory.path}${Platform.pathSeparator}qa-subtitle.srt',
      );
      subtitle.writeAsStringSync(
        '1\n00:00:00,000 --> 00:00:10,000\nLocal Tag Player QA\n',
        flush: true,
      );
      // 把暂停位置移到外挂字幕的可见时间段，先记录无字幕基线，再加载字幕。
      // 该文件只存在于隔离 QA 输出目录，字幕内容不会进入产品数据或报告。
      const subtitleTarget = Duration(seconds: 1);
      await player.playerService.seek(subtitleTarget);
      await _waitForPlayerPosition(player, subtitleTarget);
      await player.playerService.pause();
      _appendPrecisionEvidence(<String, Object?>{
        'stage': 'external_subtitle_before',
        'success': true,
        'positionMs': player.playerService.state.position.inMilliseconds,
        'frame': await player.readPresentedVideoFrame(),
        'frameEvidence': player.lastPresentedVideoFrameEvidence,
      });
      await _precisionObservationDwell();
      try {
        _appendPrecisionEvidence(<String, Object?>{
          'stage': 'external_subtitle_load_started',
          'success': true,
          'positionMs': player.playerService.state.position.inMilliseconds,
        });
        await player.playerService.addExternalSubtitle(subtitle.path);
        final trackList = await player.playerService.getProperty('track-list');
        subtitleLoaded = trackList.contains('Local Tag Player QA') ||
            trackList.contains('subtitle');
        // sub-add 后给同一 Texture 一个短暂的合成窗口；桌面观察器只记录匿名下方区域
        // 指纹差异，不能把 track-list 读回当作字幕可见性。
        await Future<void>.delayed(const Duration(milliseconds: 450));
        _appendPrecisionEvidence(<String, Object?>{
          'stage': 'external_subtitle_complete',
          'success': subtitleLoaded,
          'trackListObserved': trackList.isNotEmpty,
          'positionMs': player.playerService.state.position.inMilliseconds,
          'frame': await player.readPresentedVideoFrame(),
          'frameEvidence': player.lastPresentedVideoFrameEvidence,
        });
      } catch (error) {
        _appendPrecisionEvidence(<String, Object?>{
          'stage': 'external_subtitle_error',
          'errorType': error.runtimeType.toString(),
        });
      }
      _appendLifecycle(
        widget.outputDirectory,
        frameStepPresented &&
                playbackRateApplied &&
                playbackRateRestored &&
                abLoopASet &&
                abLoopBSet &&
                loopCompleted &&
                abLoopCleared &&
                subtitleLoaded
            ? 'precision_controls_qa_complete'
            : 'precision_controls_qa_incomplete',
      );
    } catch (error) {
      _appendPrecisionEvidence(<String, Object?>{
        'stage': 'precision_controls_qa_error',
        'errorType': error.runtimeType.toString(),
      });
      _appendLifecycle(widget.outputDirectory, 'precision_controls_qa_error');
    } finally {
      _precisionControlsCompleted = true;
    }
  }

  /** 隔离 precision QA 的外部 DWM 观测窗口，不进入正式 PlayerPage 时序。 */
  Future<void> _precisionObservationDwell() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
  }

  Future<void> _waitForPlayerPosition(
    PlayerPageState player,
    Duration target,
  ) async {
    final watch = Stopwatch()..start();
    while (!_shuttingDown && watch.elapsed < const Duration(seconds: 2)) {
      if ((player.playerService.state.position - target).abs() <=
          const Duration(milliseconds: 500)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  bool _isMpvAbLoopPoint(String value) =>
      value != 'no' && value != 'unavailable' && value.isNotEmpty;

  /** 只接受当前 PlayerService 的倍速属性读回，不以命令 Future 完成冒充生效。 */
  bool _isPlaybackRateReadback(String value, double expected) {
    final readback = double.tryParse(value.trim());
    return readback != null && (readback - expected).abs() <= 0.01;
  }

  void _appendPrecisionEvidence(Map<String, Object?> values) {
    File(
      '${widget.outputDirectory.path}${Platform.pathSeparator}precision-controls.jsonl',
    ).writeAsStringSync(
      '${jsonEncode(<String, Object?>{
            'utcUs': DateTime.now().toUtc().microsecondsSinceEpoch,
            ...values,
          })}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<void> _shutdownWhenRequested() async {
    if (_shuttingDown || !_shutdownRequest.existsSync()) return;
    if (widget.precisionControlsQa && !_precisionControlsCompleted) return;
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
    final forceSoftware = playerQaForceSoftwareDecode();
    final backend = MediaKitPlayerBackend(
      hwdec: forceSoftware ? 'no' : hwdec,
      enableHardwareAcceleration:
          forceSoftware ? false : enableHardwareAcceleration,
      forceSoftwareDecodeForQa: forceSoftware,
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
