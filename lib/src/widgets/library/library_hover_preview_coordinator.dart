import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/playback_settings.dart';
import '../../models/video_item.dart';
import '../../services/player/media_kit_initializer.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库范围内唯一的悬停预览播放器与 Texture owner。
 *
 * 卡片只声明当前 hover 意图，不能各自创建或释放原生 Player。播放器在媒体库内复用，
 * 离开卡片时停止当前媒体但保留 Texture；正式播放入口会显式释放它，避免与主播放器
 * 同时持有两条解码链。状态通知只用于 UI 可见性，不改变正式 filtered queue。
 */
class LibraryHoverPreviewCoordinator extends ChangeNotifier {
  Player? _player;
  VideoController? _controller;
  Timer? _releaseTimer;
  Future<void> _stopTail = Future<void>.value();
  String? _activePath;
  int _generation = 0;
  bool _loading = false;
  bool _ready = false;
  bool _visible = false;
  bool _disposed = false;
  Future<void>? _disposeFuture;
  Future<void>? _releaseFuture;

  Player? get player => _player;

  VideoController? get controller => _controller;

  bool isLoadingFor(VideoItem item) =>
      !_disposed && _activePath == item.path && _loading;

  bool isReadyFor(VideoItem item) =>
      !_disposed && _activePath == item.path && _ready;

  bool isVisibleFor(VideoItem item) =>
      !_disposed && _activePath == item.path && _visible;

  /** 重新进入正在淡出的卡片时只恢复可见性，不重建播放器。 */
  void reenter(VideoItem item) {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    if (isReadyFor(item) && !_visible) {
      _visible = true;
      notifyListeners();
    }
  }

  /**
   * 打开最新 hover 目标，并等待原生侧首帧。
   *
   * [waitUntilFirstFrameRendered] 只作为原生首帧门禁；UI 仍保留静态 poster，直到
   * 当前请求发布 ready 后再淡入 Texture，旧请求不能覆盖新卡片。
   */
  Future<void> open({
    required VideoItem item,
    required PlaybackSettings settings,
    MediaKitInitializer? initializer,
  }) async {
    final releaseFuture = _releaseFuture;
    if (releaseFuture != null) {
      await releaseFuture;
    }
    if (_disposed) return;
    _releaseTimer?.cancel();
    _releaseTimer = null;
    final previousPath = _activePath;
    final requestGeneration = ++_generation;
    _activePath = item.path;
    _loading = true;
    _ready = false;
    _visible = false;
    notifyListeners();

    try {
      if (previousPath != null && previousPath != item.path) {
        _scheduleStopCurrentMedia();
      }
      await _stopTail;
      if (_disposed ||
          requestGeneration != _generation ||
          _activePath != item.path) {
        return;
      }
      (initializer ?? defaultMediaKitInitializer).ensureInitialized();
      if (_player == null || _controller == null) {
        _player = Player(
          configuration:
              const PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
        );
        _controller = VideoController(
          _player!,
          configuration: VideoControllerConfiguration(
            width: 640,
            height: 360,
            hwdec: settings.hwdec,
            enableHardwareAcceleration: settings.hardwareDecodingEnabled,
          ),
        );
      }
      final player = _player!;
      final controller = _controller!;
      if (_disposed ||
          requestGeneration != _generation ||
          _activePath != item.path) {
        return;
      }
      await player.setVolume(0);
      await player.open(Media(item.path), play: true).timeout(
            const Duration(seconds: 10),
          );
      await controller.platform.future
          .then((platform) => platform.waitUntilFirstFrameRendered)
          .timeout(const Duration(seconds: 8));
      if (_disposed ||
          requestGeneration != _generation ||
          _activePath != item.path ||
          !identical(_player, player)) {
        return;
      }
      // 先挂载透明动态层，让 Video/Texture 有机会完成 Flutter 侧合成；
      // 静态 poster 在这段时间内仍然是唯一可见画面。
      _loading = false;
      _ready = true;
      _visible = false;
      notifyListeners();

      await WidgetsBinding.instance.endOfFrame;
      if (_disposed ||
          requestGeneration != _generation ||
          _activePath != item.path ||
          !identical(_player, player)) {
        return;
      }
      _visible = true;
      notifyListeners();
    } catch (error) {
      if (_disposed || requestGeneration != _generation) return;
      _loading = false;
      _ready = false;
      _visible = false;
      notifyListeners();
      // 只写文件名和异常类型，避免用户完整路径进入诊断输出。
      debugPrint(
        'LIBRARY_HOVER_PREVIEW status=failed '
        'file=${item.path.split(RegExp(r'[\\/]')).last} '
        'error=${error.runtimeType}',
      );
    }
  }

  /** 卡片离开时先显示 poster，短暂保留共享 Texture 以便快速回入复用。 */
  void exit(VideoItem item,
      {Duration delay = const Duration(milliseconds: 180)}) {
    if (!isLoadingFor(item) && !isReadyFor(item)) return;
    final wasReady = _ready;
    _generation++;
    _loading = false;
    // 已有首帧时保留 ready，180ms 内回入可直接恢复显示；加载中的目标则立即失效。
    _ready = wasReady;
    _visible = false;
    notifyListeners();
    _releaseTimer?.cancel();
    _releaseTimer = Timer(delay, () {
      if (_activePath == item.path) {
        _scheduleStopCurrentMedia();
        _ready = false;
        _activePath = null;
        notifyListeners();
      }
    });
  }

  /** 正式播放器打开前释放共享预览，不能让两条原生解码链重叠。 */
  Future<void> releaseForPlayback() {
    final current = _releaseFuture;
    if (current != null) {
      return current;
    }
    final future = _releasePlayerForPlayback();
    _releaseFuture = future;
    unawaited(future.whenComplete(() {
      if (identical(_releaseFuture, future)) {
        _releaseFuture = null;
      }
    }));
    return future;
  }

  Future<void> _releasePlayerForPlayback() async {
    if (_disposed) return;
    _generation++;
    _releaseTimer?.cancel();
    _releaseTimer = null;
    _activePath = null;
    _loading = false;
    _ready = false;
    _visible = false;
    notifyListeners();
    await _disposePlayer();
  }

  Future<void> _stopCurrentMedia([Player? target]) async {
    final player = target ?? _player;
    if (player == null) return;
    try {
      await player.stop().timeout(const Duration(milliseconds: 800));
    } catch (_) {
      // 共享预览只影响 hover 反馈；stop 超时不能阻塞媒体库交互。
    }
  }

  Future<void> _disposePlayer() async {
    final existing = _player;
    _player = null;
    _controller = null;
    await _stopTail;
    if (existing != null) {
      try {
        await existing.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {
        // dispose 失败不回写卡片状态；下次 hover 会建立新的独占会话。
      }
    }
  }

  /** 串行化共享播放器的 stop，避免旧媒体未释放就开始 open 新媒体。 */
  void _scheduleStopCurrentMedia() {
    final player = _player;
    _stopTail = _stopTail.then<void>((_) => _stopCurrentMedia(player));
  }

  Future<void> disposeAsync() {
    return _disposeFuture ??= () async {
      _disposed = true;
      _generation++;
      _releaseTimer?.cancel();
      _releaseTimer = null;
      await _disposePlayer();
      super.dispose();
    }();
  }

  @override
  void dispose() {
    // Flutter dispose 没有 Future；所有拥有原生资源的生产宿主使用 disposeAsync。
    _disposed = true;
    _releaseTimer?.cancel();
    unawaited(_disposePlayer());
    super.dispose();
  }
}

/** 为同一媒体库结果页提供共享 hover 预览 owner。 */
class LibraryHoverPreviewScope extends StatefulWidget {
  const LibraryHoverPreviewScope({
    super.key,
    required this.child,
    this.coordinator,
  });

  final Widget child;
  final LibraryHoverPreviewCoordinator? coordinator;

  static LibraryHoverPreviewCoordinator? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_LibraryHoverPreviewInherited>()
        ?.coordinator;
  }

  @override
  State<LibraryHoverPreviewScope> createState() =>
      _LibraryHoverPreviewScopeState();
}

class _LibraryHoverPreviewScopeState extends State<LibraryHoverPreviewScope> {
  late final LibraryHoverPreviewCoordinator _defaultCoordinator;
  late LibraryHoverPreviewCoordinator _coordinator;
  late bool _ownsCoordinator;

  @override
  void initState() {
    super.initState();
    _ownsCoordinator = widget.coordinator == null;
    _defaultCoordinator = LibraryHoverPreviewCoordinator();
    _coordinator = widget.coordinator ?? _defaultCoordinator;
  }

  @override
  void didUpdateWidget(covariant LibraryHoverPreviewScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coordinator == widget.coordinator) return;
    final next = widget.coordinator ?? _defaultCoordinator;
    final oldOwns = _ownsCoordinator;
    _coordinator = next;
    _ownsCoordinator = widget.coordinator == null;
    if (oldOwns && !identical(next, _defaultCoordinator)) {
      unawaited(_defaultCoordinator.disposeAsync());
    }
  }

  @override
  void dispose() {
    if (_ownsCoordinator) {
      unawaited(_coordinator.disposeAsync());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _LibraryHoverPreviewInherited(
        coordinator: _coordinator,
        child: widget.child,
      );
}

class _LibraryHoverPreviewInherited extends InheritedWidget {
  const _LibraryHoverPreviewInherited({
    required this.coordinator,
    required super.child,
  });

  final LibraryHoverPreviewCoordinator coordinator;

  @override
  bool updateShouldNotify(_LibraryHoverPreviewInherited oldWidget) =>
      !identical(oldWidget.coordinator, coordinator);
}
