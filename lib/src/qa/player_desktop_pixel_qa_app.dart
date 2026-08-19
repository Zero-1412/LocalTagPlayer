import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import '../services/player/media_kit_player_backend.dart';
import '../services/player/player_hardware_acceleration.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 判断是否启动实际 Debug 可执行程序专用的桌面像素 QA 页面。
 *
 * 此入口只允许 Windows Debug + 明确环境变量，既不加载数据库、媒体库、用户播放设置，
 * 也不出现在正式路由中。它存在的唯一目的是让外部 Win32 输入与 DWM 合成像素在真实
 * 运行程序中相遇，避免 integration_test binding 代替用户输入链路。
 */
bool shouldRunPlayerDesktopPixelQa({Map<String, String>? environment}) {
  final values = environment ?? Platform.environment;
  return kDebugMode &&
      Platform.isWindows &&
      values['LOCAL_TAG_PLAYER_DESKTOP_PIXEL_QA'] == '1';
}

/** 启动无持久化、正式 MediaKit Texture 后端的桌面像素 QA 应用。 */
Future<void> runPlayerDesktopPixelQa() async {
  final samplePath =
      Platform.environment['LOCAL_TAG_PLAYER_PIXEL_SAMPLE']?.trim();
  final outputRoot =
      Platform.environment['LOCAL_TAG_PLAYER_PIXEL_OUTPUT']?.trim();
  final windowTitle =
      Platform.environment['LOCAL_TAG_PLAYER_PIXEL_WINDOW_TITLE']?.trim() ??
          'LocalTagPlayer Desktop Pixel QA';
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
    throw StateError('桌面像素 QA 缺少可读取的本地样本');
  }
  if (outputRoot == null || outputRoot.isEmpty) {
    throw StateError('桌面像素 QA 缺少匿名输出根目录');
  }
  final outputDirectory = Directory(outputRoot);
  if (!outputDirectory.existsSync()) {
    throw StateError('桌面像素 QA 输出根目录不存在');
  }

  WidgetsFlutterBinding.ensureInitialized();
  _appendQaLifecycle(outputDirectory, 'bootstrap_started');
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: Size(windowWidth.toDouble(), windowHeight.toDouble()),
      minimumSize: const Size(960, 540),
      title: windowTitle,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  _appendQaLifecycle(outputDirectory, 'window_ready_before_run_app');
  runApp(
    _PlayerDesktopPixelQaApp(
      samplePath: samplePath,
      outputDirectory: outputDirectory,
      windowTitle: windowTitle,
    ),
  );
}

/**
 * 独立会话矩阵只记录 QA 生命周期阶段，不记录媒体标识或像素内容。
 *
 * 4K 进程如果在 ready.json 前退出，stdout 中的 VideoOutput 析构不足以判断是窗口、
 * Flutter 初始化还是 MediaKit 打开阶段退出；该探针把这些阶段与真实像素证据分开。
 */
void _appendQaLifecycle(Directory outputDirectory, String event) {
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

class _PlayerDesktopPixelQaApp extends StatefulWidget {
  const _PlayerDesktopPixelQaApp({
    required this.samplePath,
    required this.outputDirectory,
    required this.windowTitle,
  });

  final String samplePath;
  final Directory outputDirectory;
  final String windowTitle;

  @override
  State<_PlayerDesktopPixelQaApp> createState() =>
      _PlayerDesktopPixelQaAppState();
}

class _PlayerDesktopPixelQaAppState extends State<_PlayerDesktopPixelQaApp> {
  late final MediaKitPlayerBackend _backend = MediaKitPlayerBackend(
    hwdec: PlayerHardwareAcceleration.resolve('d3d11va-copy'),
    enableHardwareAcceleration: true,
  );
  final FocusNode _focusNode = FocusNode(debugLabel: 'desktop-pixel-qa');
  late final File _inputEvents = File(
    '${widget.outputDirectory.path}${Platform.pathSeparator}received-input-events.jsonl',
  );
  late final File _rendererEvents = File(
    '${widget.outputDirectory.path}${Platform.pathSeparator}renderer-events.jsonl',
  );
  late final File _shutdownRequest = File(
    '${widget.outputDirectory.path}${Platform.pathSeparator}shutdown.request',
  );
  Timer? _fullscreenSettledTimer;
  Timer? _shutdownWatchTimer;
  String? _error;
  var _ready = false;
  var _disposed = false;
  var _backendDisposed = false;
  var _shuttingDown = false;
  var _interactionBusy = false;

  @override
  void initState() {
    super.initState();
    _appendQaLifecycle(widget.outputDirectory, 'state_initialized');
    // 外层矩阵不能强杀持有 ANGLE/D3D11 表面的进程；该私有文件是 Debug QA 专用的
    // 单向退出协议，先 await backend.dispose 再结束进程，避免下一会话继承脏 GPU 状态。
    _shutdownWatchTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => unawaited(_shutdownWhenRequested()),
    );
    unawaited(_openPausedSurface());
  }

  @override
  void dispose() {
    _disposed = true;
    _fullscreenSettledTimer?.cancel();
    _shutdownWatchTimer?.cancel();
    _focusNode.dispose();
    if (!_backendDisposed) unawaited(_backend.dispose());
    super.dispose();
  }

  Future<void> _openPausedSurface() async {
    try {
      _appendQaLifecycle(widget.outputDirectory, 'media_open_started');
      await _backend.openPath(widget.samplePath);
      await _backend.play();
      await _waitFor(
        () =>
            _backend.textureId.value != null &&
            _backend.state.duration > const Duration(seconds: 12) &&
            // 反向 5 秒交互必须有真实可退距离；不能在起始帧把目标钳到 0 秒后把
            // “无像素变化”误诊为呈现卡顿。
            _backend.state.position > const Duration(seconds: 7),
        const Duration(seconds: 30),
      );
      await _backend.pause();
      await _waitFor(() => !_backend.state.playing, const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      _focusNode.requestFocus();
      // 基线本身也必须写入 Texture 诊断。这样 4K/DPI 实验能够区分“窗口已是 4K”
      // 与“输出表面已按协调器重建为 4K”，不能只在全屏后才留下代次证据。
      _appendRendererEvent('paused_surface_baseline_ready');
      _writeReady();
      _appendQaLifecycle(widget.outputDirectory, 'paused_baseline_ready');
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      _appendQaLifecycle(widget.outputDirectory, 'media_open_failed');
      File('${widget.outputDirectory.path}${Platform.pathSeparator}desktop-pixel-qa-failure.txt')
          .writeAsStringSync(error.toString(), flush: true);
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _writeReady() {
    File('${widget.outputDirectory.path}${Platform.pathSeparator}ready.json')
        .writeAsStringSync(
      jsonEncode(<String, Object?>{
        'testProcessId': pid,
        'windowTitle': widget.windowTitle,
        'backend': 'media-kit-flutter-texture',
        'state': 'paused-static-baseline-ready',
        'focusReady': _focusNode.hasFocus,
        'textureGenerationCount':
            _backend.videoSurfaceDiagnostics.textureGenerationCount,
      }),
      flush: true,
    );
  }

  void _appendInput(String event, {int? targetMilliseconds}) {
    _inputEvents.writeAsStringSync(
      '${jsonEncode(<String, Object?>{
            'event': event,
            'utcUs': DateTime.now().toUtc().microsecondsSinceEpoch,
            if (targetMilliseconds != null) 'targetMs': targetMilliseconds,
          })}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<void> _seekBackward() async {
    if (_interactionBusy) return;
    _interactionBusy = true;
    final target = _backend.state.position - const Duration(seconds: 5);
    _appendInput('pointer_seek_backward',
        targetMilliseconds: target.inMilliseconds);
    try {
      await _backend
          .seekInteractive(target > Duration.zero ? target : Duration.zero);
    } finally {
      _interactionBusy = false;
    }
  }

  /** 全屏只通过专用 Debug QA 键触发，用于测窗口几何与 Texture 重建；正常播放器路由不变。 */
  Future<void> _toggleFullscreen() async {
    final entering = !await windowManager.isFullScreen();
    _appendInput(
        entering ? 'keyboard_enter_fullscreen' : 'keyboard_exit_fullscreen');
    await windowManager.setFullScreen(entering);
    _appendRendererEvent(
        entering ? 'fullscreen_requested' : 'windowed_requested');
    _fullscreenSettledTimer?.cancel();
    _fullscreenSettledTimer = Timer(const Duration(milliseconds: 700), () {
      if (!_disposed) _appendRendererEvent('fullscreen_settled');
    });
  }

  void _appendRendererEvent(String event) {
    _rendererEvents.writeAsStringSync(
      '${jsonEncode(<String, Object?>{
            'event': event,
            'utcUs': DateTime.now().toUtc().microsecondsSinceEpoch,
            'textureGenerationCount':
                _backend.videoSurfaceDiagnostics.textureGenerationCount,
            'textureWidthPx': _backend.videoSurfaceDiagnostics.textureWidthPx,
            'textureHeightPx': _backend.videoSurfaceDiagnostics.textureHeightPx,
          })}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<void> _shutdownWhenRequested() async {
    if (_disposed || _shuttingDown || !_shutdownRequest.existsSync()) return;
    _shuttingDown = true;
    _appendQaLifecycle(widget.outputDirectory, 'shutdown_requested');
    _shutdownWatchTimer?.cancel();
    _fullscreenSettledTimer?.cancel();
    try {
      await _backend.dispose();
      _backendDisposed = true;
      _appendRendererEvent('backend_disposed_before_exit');
    } finally {
      // 这是显式环境变量才会启用的独立 QA 进程；正常产品 main 路径永不进入这里。
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Focus(
            autofocus: true,
            focusNode: _focusNode,
            onKeyEvent: (_, event) {
              _appendInput('keyboard_${event.runtimeType}');
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter &&
                  _ready) {
                unawaited(_toggleFullscreen());
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _backend.buildVideoSurface(
                  controls: const SizedBox.expand(),
                  fit: BoxFit.contain,
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: 220,
                      height: 48,
                      child: Listener(
                        onPointerDown: (_) => _appendInput('pointer_down'),
                        onPointerUp: (_) => _appendInput('pointer_up'),
                        child: ElevatedButton(
                          onPressed: _ready && !_interactionBusy
                              ? _seekBackward
                              : null,
                          child: Text(
                            _error ??
                                (_ready
                                    ? 'QA 反向交互 seek'
                                    : '正在建立静止 Texture 基线…'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/** 不接受异常窗口尺寸，避免 QA 环境变量把探针窗口放到无效或不可见状态。 */
int _readQaWindowDimension(String name, {required int fallback}) {
  final parsed = int.tryParse(Platform.environment[name]?.trim() ?? '');
  if (parsed == null || parsed < 540 || parsed > 7680) return fallback;
  return parsed;
}

Future<void> _waitFor(
  bool Function() predicate,
  Duration timeout,
) async {
  final watch = Stopwatch()..start();
  while (!predicate() && watch.elapsed < timeout) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  if (!predicate()) throw TimeoutException('桌面像素 QA 会话未在时限内就绪', timeout);
}
