import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/player_gpu_capabilities.dart';
import '../../models/player_motion_interpolation_capability.dart';
import '../../platform/platform_interfaces.dart';
import 'windows_gpu_capability_channel.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * Windows C++ 播放器的 Flutter 适配器。
 *
 * `stub`模式验证纹理与生命周期，`mpv`模式接入原生解码和 D3D11 共享纹理，
 * `hwnd`模式隔离验证 libmpv 直接输出到 Flutter child HWND；三者都只用于显式
 * A/B；默认生产路径由 MediaKitPlayerBackend 同时承载常规播放与高级 libmpv 属性。
 */
class WindowsNativePlayerBackend
    implements
        PlayerBackend,
        PlayerFramePresentationEvidenceBoundary,
        PlayerPropertyBatchBoundary,
        PlayerGpuRenderBoundary,
        PlayerOverlaySurfaceBoundary,
        PlayerMotionInterpolationBoundary,
        PlayerInteractiveSeekBoundary,
        PlayerNativeNvidiaVideoEnhancementBoundary {
  WindowsNativePlayerBackend({this.mode = 'stub'})
      : _positionChanges = StreamController<Duration>.broadcast(),
        _playingChanges = StreamController<bool>.broadcast(),
        _completedChanges = StreamController<bool>.broadcast(),
        _errorChanges = StreamController<String>.broadcast() {
    _ready = _initialize();
  }

  final StreamController<Duration> _positionChanges;
  /** 原生创建模式：`stub`验证纹理，`mpv`验证 ANGLE，`hwnd`验证 D3D11VA。 */
  final String mode;

  @override
  String get framePresentationEvidenceKind =>
      mode == 'hwnd' ? 'child-hwnd' : 'texture';

  @override
  bool get supportsNativeNvidiaVideoEnhancement => mode == 'hwnd';
  final StreamController<bool> _playingChanges;
  final StreamController<bool> _completedChanges;
  final StreamController<String> _errorChanges;
  final ValueNotifier<int?> _textureId = ValueNotifier<int?>(null);
  final Completer<void> _released = Completer<void>();
  late final Future<void> _ready;
  Timer? _pollTimer;
  PlayerBackendState _state = const PlayerBackendState(
    position: Duration.zero,
    duration: Duration.zero,
    playing: false,
    buffering: false,
    volume: 100,
    videoTrackCount: 0,
    audioTrackCount: 0,
  );
  String _lifecycle = 'creating';
  final Map<String, String> _properties = <String, String>{};
  int _completedCount = 0;
  int _errorCount = 0;
  bool _polling = false;
  bool _disposed = false;

  /** 创建指定原生会话并启动低频状态轮询。 */
  Future<void> _initialize() async {
    final value = await windowsNativePlayerChannel
        .invokeMapMethod<String, Object?>('create', {'mode': mode});
    _applyState(value);
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => unawaited(_pollState()),
    );
  }

  /** 拉取原生节流快照；上一轮未结束时丢弃本轮，避免平台消息积压。 */
  Future<void> _pollState() async {
    if (_disposed || _polling) return;
    _polling = true;
    try {
      final value = await windowsNativePlayerChannel
          .invokeMapMethod<String, Object?>('state');
      _applyState(value);
    } catch (error) {
      // dispose 可能与最后一次轮询交错；关闭后的错误流不能再接收事件。
      if (!_disposed) _errorChanges.add(error.runtimeType.toString());
    } finally {
      _polling = false;
    }
  }

  /** 合并原生轻量快照，并只在字段变化时通知页面。 */
  void _applyState(Map<String, Object?>? value) {
    if (value == null || _disposed) return;
    final previous = _state;
    final position = Duration(milliseconds: value['positionMs'] as int? ?? 0);
    final duration = Duration(milliseconds: value['durationMs'] as int? ?? 0);
    final playing = value['playing'] as bool? ?? false;
    _state = PlayerBackendState(
      position: position,
      duration: duration,
      playing: playing,
      buffering: value['buffering'] as bool? ?? false,
      volume: (value['volume'] as num?)?.toDouble() ?? 100,
      videoTrackCount: duration > Duration.zero ? 1 : 0,
      audioTrackCount: 0,
    );
    _lifecycle = value['lifecycle'] as String? ?? _lifecycle;
    for (final property in const [
      'hwdec-current',
      'd3d11va-zero-copy',
      'mpv-version',
      'vf',
      'deband',
      'deband-iterations',
      'deband-threshold',
      'deband-range',
      'deband-grain',
      'native-nvidia-vsr-state',
      'native-nvidia-hdr-state',
      'video-params/primaries',
      'video-params/gamma',
      'video-params/colorlevels',
      'video-params/colormatrix',
      'video-output-levels',
      'video-target-params/colorlevels',
      'video-params/w',
      'video-params/h',
      'video-codec',
      'audio-codec',
      'avsync',
      'audio-pts',
      'demuxer-cache-duration',
      'container-fps',
      'estimated-vf-fps',
      'display-fps',
      'video-sync',
      'interpolation',
      'tscale',
      'display-sync-active',
      'estimated-frame-number',
      'native-frame-number-source',
      'frame-drop-count',
      'native-render-requests',
      'native-rendered-frames',
      'native-skipped-renders',
      'native-texture-copies',
      'native-surface-resizes',
      'native-mpv-events',
      'native-event-batch-yields',
      'native-surface-left',
      'native-surface-top',
      'native-surface-width',
      'native-surface-height',
      'native-surface-kind',
      'native-surface-visible',
      'native-surface-occluded',
      'native-overlay-partial',
      'native-overlay-left',
      'native-overlay-top',
      'native-overlay-width',
      'native-overlay-height',
      'native-input-forwarding',
      'native-input-mode',
      'native-airspace-inset-top',
      'native-airspace-inset-bottom',
      'native-video-plugin-state',
      'native-video-plugin-name',
      'native-video-plugin-frames',
      'native-video-plugin-fallbacks',
      'native-video-plugin-error',
      'native-motion-interpolation-state',
      'native-motion-interpolation-error',
      'native-motion-interpolation-configured',
      'native-motion-interpolation-enabled',
      'native-motion-interpolation-fallbacks',
      'native-nvofa-driver-state',
      'native-nvofa-driver-error',
      'native-nvofa-api-version',
      'native-nvofa-d3d11',
      'native-d3d11-adapter-state',
      'native-d3d11-adapter-error',
      'native-d3d11-adapter-luid',
    ]) {
      final propertyValue = value[property];
      if (propertyValue != null) _properties[property] = '$propertyValue';
    }
    final texture = value['textureId'] as int?;
    _textureId.value = texture == null || texture < 0 ? null : texture;
    if (position != previous.position) _positionChanges.add(position);
    if (playing != previous.playing) _playingChanges.add(playing);
    final completedCount = value['completedCount'] as int? ?? _completedCount;
    if (completedCount > _completedCount) _completedChanges.add(true);
    _completedCount = completedCount;
    final errorCount = value['errorCount'] as int? ?? _errorCount;
    if (errorCount > _errorCount) {
      _errorChanges.add(value['lastError'] as String? ?? 'mpv playback error');
    }
    _errorCount = errorCount;
  }

  /** 将单个控制动作送入原生队列，并直接合并命令返回的状态快照。 */
  Future<void> _command(String name, {String? text, int? integer}) async {
    await _ready;
    final value = await windowsNativePlayerChannel
        .invokeMapMethod<String, Object?>('command', {
      'name': name,
      if (text != null) 'text': text,
      if (integer != null) 'integer': integer,
    });
    _applyState(value);
  }

  /** 把有序属性快照合并为一次平台调用，避免每项都触发 MethodChannel 与全量采样。 */
  Future<void> _setProperties(Map<String, String> properties) async {
    if (properties.isEmpty) return;
    await _ready;
    final values = properties.entries
        .map(
          (entry) => <String, Object?>{
            'property': entry.key,
            'value': _normalizedPropertyValue(entry.key, entry.value),
          },
        )
        .toList(growable: false);
    final state = await windowsNativePlayerChannel
        .invokeMapMethod<String, Object?>('setProperties', {
      'properties': values,
    });
    _applyState(state);
  }

  /** 保持 child HWND 非 copy 与 Flutter Texture copy-back 的既有硬解边界。 */
  String _normalizedPropertyValue(String property, String value) {
    if (mode == 'hwnd' && property == 'hwdec') {
      return 'd3d11va';
    }
    if (mode == 'mpv' && property == 'hwdec' && value == 'd3d11va') {
      return 'd3d11va-copy';
    }
    return value;
  }

  /**
   * 把 Flutter 视频占位区域同步到原生 child HWND。
   *
   * 坐标使用 Flutter 逻辑画布；runner 再按实际 view 客户区换算为物理像素。
   * 默认 MediaKit 与纹理实验路径不会调用该方法，因此不会引入额外平台消息。
   */
  Future<void> _setHwndSurfaceRect({
    required int left,
    required int top,
    required int width,
    required int height,
    required int viewWidth,
    required int viewHeight,
    required int airspaceTop,
    required int airspaceBottom,
    required bool visible,
  }) async {
    if (_disposed || mode != 'hwnd') return;
    await _ready;
    if (_disposed) return;
    await windowsNativePlayerChannel.invokeMethod<void>('setSurfaceRect', {
      'left': left,
      'top': top,
      'width': width,
      'height': height,
      'viewWidth': viewWidth,
      'viewHeight': viewHeight,
      'airspaceTop': airspaceTop,
      'airspaceBottom': airspaceBottom,
      'visible': visible,
    });
  }

  /**
   * 在 Flutter 弹层挂载前裁剪 child HWND，关闭最后一层弹层后恢复完整区域。
   *
   * 纹理与 stub 模式没有独立 airspace，因此直接返回；默认 MediaKit 也不会实现
   * 该可选边界。提供弹层矩形时原生视频在矩形外继续实时播放；未提供矩形的模态
   * 弹窗才完整隐藏原生表面。
   */
  @override
  Future<void> setFlutterOverlayVisible(
    bool visible, {
    Rect? overlayRect,
    Size? viewSize,
  }) async {
    if (mode != 'hwnd' || _disposed) return;
    await _ready;
    if (_disposed) return;
    final partial = visible && overlayRect != null && viewSize != null;
    await windowsNativePlayerChannel.invokeMethod<void>(
      'setSurfaceOccluded',
      <String, Object?>{
        'occluded': visible,
        'partial': partial,
        if (partial) ...<String, Object?>{
          'overlayLeft': overlayRect.left.round(),
          'overlayTop': overlayRect.top.round(),
          'overlayWidth': overlayRect.width.round(),
          'overlayHeight': overlayRect.height.round(),
          'viewWidth': viewSize.width.round(),
          'viewHeight': viewSize.height.round(),
        },
      },
    );
    await _pollState();
  }

  @override
  PlayerBackendState get state => _state;

  @override
  Stream<Duration> get positionChanges => _positionChanges.stream;

  @override
  Stream<bool> get playingChanges => _playingChanges.stream;

  @override
  Stream<bool> get completedChanges => _completedChanges.stream;

  @override
  Stream<String> get errorChanges => _errorChanges.stream;

  @override
  ValueListenable<int?> get textureId => _textureId;

  @override
  Future<void> openPath(String path) {
    return _command('open', text: path);
  }

  @override
  Future<void> play() => _command('play');

  @override
  Future<void> pause() => _command('pause');

  @override
  Future<void> stop() => _command('stop');

  @override
  Future<void> seek(Duration position) =>
      _command('seek', integer: position.inMilliseconds);

  @override
  Future<void> seekInteractive(Duration position) async {
    await _command('seek-fast', integer: position.inMilliseconds);
    // 页面在精确恢复入口提交普通 seek；原生层只承担廉价关键帧预览。
  }

  @override
  Future<void> setRate(double rate) =>
      _command('rate', integer: (rate * 1000).round());

  @override
  Future<void> setVolume(double volume) =>
      _command('volume', integer: (volume * 1000).round());

  @override
  Future<void> playOrPause() => state.playing ? pause() : play();

  @override
  Future<void> setProperty(String property, String value) {
    // 缓存档位由播放器会话统一约束；原生 A/B 后端必须接受同一组值，避免设置页显示
    // 已关闭高质量缓存而此处仍静默覆盖为固定 64 MiB。
    return _command(
      'property',
      text: '$property=${_normalizedPropertyValue(property, value)}',
    );
  }

  @override
  Future<void> setProperties(Map<String, String> properties) =>
      _setProperties(properties);

  @override
  Future<String> getProperty(String property) async {
    await _ready;
    if (_properties.containsKey(property)) return _properties[property]!;
    if (property == 'current-vo') {
      if (mode == 'hwnd') return 'gpu-next-d3d11-child-hwnd';
      return mode == 'mpv' ? 'libmpv-angle-d3d11' : 'flutter-pixel-buffer';
    }
    if (property == 'native-lifecycle') return _lifecycle;
    return 'unavailable';
  }

  @override
  Future<PlayerGpuCapabilityMatrix> queryGpuCapabilities() =>
      queryWindowsGpuCapabilities();

  @override
  Future<PlayerGpuActiveAdapter> queryActiveGpuAdapter() =>
      queryWindowsActiveGpuAdapter(backend: 'windows-native');

  @override
  Future<PlayerGpuComputeFrameBudget> benchmarkGpuComputeFrameBudget(
    String adapterLuid,
  ) =>
      benchmarkWindowsGpuComputeFrameBudget(adapterLuid);

  @override
  Future<PlayerMotionInterpolationCapability>
      queryMotionInterpolationCapability() async {
    if (mode != 'mpv' && mode != 'hwnd') {
      return const PlayerMotionInterpolationCapability.unsupported();
    }
    await _ready;
    await _pollState();
    final runtimeState =
        _properties['native-motion-interpolation-state'] ?? 'unavailable';
    final errorCode = _properties['native-motion-interpolation-error'] ?? '';
    final enabled =
        _properties['native-motion-interpolation-enabled'] == 'true';
    final fallbackCount = int.tryParse(
          _properties['native-motion-interpolation-fallbacks'] ?? '',
        ) ??
        0;
    final nvidiaDriverState =
        _properties['native-nvofa-driver-state'] ?? 'unavailable';
    final nvidiaDriverError =
        _properties['native-nvofa-driver-error'] ?? 'not-probed';
    final nvidiaApiVersion = int.tryParse(
          _properties['native-nvofa-api-version'] ?? '',
        ) ??
        0;
    final nvidiaD3D11Available = _properties['native-nvofa-d3d11'] == 'true';
    final status = switch (runtimeState) {
      'not-configured' ||
      'runtime-not-configured' ||
      'script-not-configured' =>
        PlayerMotionInterpolationStatus.notConfigured,
      'ready' => PlayerMotionInterpolationStatus.ready,
      'requested' => PlayerMotionInterpolationStatus.requested,
      'active' => PlayerMotionInterpolationStatus.active,
      'fallback' => PlayerMotionInterpolationStatus.fallback,
      _ => PlayerMotionInterpolationStatus.unavailable,
    };
    return PlayerMotionInterpolationCapability(
      status: status,
      backend: 'windows-native-libmpv',
      runtimeState: runtimeState,
      errorCode: errorCode,
      enabled: enabled,
      fallbackCount: fallbackCount,
      nvidiaDriverState: nvidiaDriverState,
      nvidiaDriverError: nvidiaDriverError,
      nvidiaOpticalFlowApiVersion: nvidiaApiVersion,
      nvidiaD3D11Available: nvidiaD3D11Available,
    );
  }

  @override
  Future<PlayerMotionInterpolationApplyResult> setMotionInterpolationEnabled(
    bool enabled,
  ) async {
    final before = await queryMotionInterpolationCapability();
    if (enabled && !before.canEnable) {
      return PlayerMotionInterpolationApplyResult(
        applied: false,
        capability: before,
      );
    }
    await _command(
      'motion-interpolation',
      integer: enabled ? 1 : 0,
    );
    var after = await queryMotionInterpolationCapability();
    bool matchesRequest(PlayerMotionInterpolationCapability capability) =>
        enabled
            ? capability.enabled &&
                (capability.status ==
                        PlayerMotionInterpolationStatus.requested ||
                    capability.status == PlayerMotionInterpolationStatus.active)
            : !capability.enabled &&
                capability.status != PlayerMotionInterpolationStatus.fallback;
    // 原生命令与固定属性快照通过不同平台消息返回，紧邻读回可能仍看到旧状态。
    // 只在该短窗口内等待状态确认，不把命令投递成功本身冒充插帧已经应用。
    for (var attempt = 0; attempt < 40 && !matchesRequest(after); attempt++) {
      if (after.status == PlayerMotionInterpolationStatus.fallback ||
          after.status == PlayerMotionInterpolationStatus.unavailable) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      after = await queryMotionInterpolationCapability();
    }
    final applied = matchesRequest(after);
    return PlayerMotionInterpolationApplyResult(
      applied: applied,
      capability: after,
    );
  }

  @override
  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) async {
    if (!mode.startsWith('mpv') && mode != 'hwnd') return null;
    final extension = format.toLowerCase().contains('png') ? 'png' : 'jpg';
    final temporaryFile = File(
      '${Directory.systemTemp.path}\\'
      'local_tag_player_${pid}_${DateTime.now().microsecondsSinceEpoch}.'
      '$extension',
    );
    try {
      await _command('screenshot', text: temporaryFile.path);
      // libmpv 命令已在原生工作线程串行完成；短暂轮询覆盖杀毒软件延迟文件可见性。
      for (var attempt = 0; attempt < 20; attempt++) {
        if (await temporaryFile.exists() && await temporaryFile.length() > 0) {
          return await temporaryFile.readAsBytes();
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return null;
    } finally {
      try {
        if (await temporaryFile.exists()) await temporaryFile.delete();
      } catch (_) {
        // 临时截图清理失败不应改变播放会话；系统临时目录会负责后续回收。
      }
    }
  }

  @override
  Widget buildVideoSurface({
    required Widget controls,
    BoxFit fit = BoxFit.contain,
    double? aspectRatio,
    bool mirror = false,
    bool reserveTopControlArea = false,
    bool reserveBottomControlArea = false,
  }) {
    if (mode == 'hwnd') {
      return _WindowsHwndVideoSurface(
        backend: this,
        controls: controls,
        reserveTopControlArea: reserveTopControlArea,
        reserveBottomControlArea: reserveBottomControlArea,
      );
    }
    final textureSurface = ValueListenableBuilder<int?>(
      valueListenable: _textureId,
      builder: (_, texture, __) => texture == null
          ? const ColoredBox(color: Colors.black)
          : Texture(textureId: texture),
    );
    final videoSurface = aspectRatio == null
        ? textureSurface
        : FittedBox(
            fit: fit,
            child: SizedBox(
              width: aspectRatio * 1000,
              height: 1000,
              child: textureSurface,
            ),
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        // 与 MediaKit 后端一致，镜像不翻转上层 Flutter 控制条。
        Transform.flip(flipX: mirror, child: videoSurface),
        controls,
      ],
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    try {
      await _ready;
      await windowsNativePlayerChannel.invokeMethod<void>('dispose');
    } finally {
      _textureId.value = null;
      await Future.wait<void>([
        _positionChanges.close(),
        _playingChanges.close(),
        _completedChanges.close(),
        _errorChanges.close(),
      ]);
      _textureId.dispose();
      if (!_released.isCompleted) _released.complete();
    }
  }

  @override
  Future<void> get released => _released.future;
}

/**
 * 隔离 child HWND 的 Flutter 占位面。
 *
 * 原生窗口无法直接被 Flutter overlay 覆盖，因此视频 HWND 始终使用完整占位矩形，
 * 再由 runner 从窗口 region 中扣除当前可见的顶部/底部控制区。这样控制条隐藏后
 * 视频立即恢复填满，既不永久制造黑边，也不因控制条显隐反复改变 mpv 输出尺寸。
 */
class _WindowsHwndVideoSurface extends StatefulWidget {
  const _WindowsHwndVideoSurface({
    required this.backend,
    required this.controls,
    required this.reserveTopControlArea,
    required this.reserveBottomControlArea,
  });

  /** 拥有方法通道与原生会话的后端。 */
  final WindowsNativePlayerBackend backend;

  /** 必须继续挂载的正式播放器控制层。 */
  final Widget controls;

  /** 全屏顶部语境存在时，为它保留不可被 child HWND 覆盖的区域。 */
  final bool reserveTopControlArea;

  /** 底部完整控制条可见时，为 Flutter 合成层临时让出区域。 */
  final bool reserveBottomControlArea;

  @override
  State<_WindowsHwndVideoSurface> createState() =>
      _WindowsHwndVideoSurfaceState();
}

/** 负责把 Flutter 逻辑布局转换成 child HWND 物理像素矩形。 */
class _WindowsHwndVideoSurfaceState extends State<_WindowsHwndVideoSurface>
    with WidgetsBindingObserver {
  static const double _fullscreenTopAirspace = 64;
  static const double _visibleControlsOcclusion = 128;
  // 隐藏进度线的视觉高度仍是 3px，但点击区为 12px；HWND 必须让出同样的
  // 底部区域，否则鼠标会先被原生子窗口吃掉，Flutter 进度线无法收到首击。
  static const double _hiddenProgressOcclusion = 12;
  final GlobalKey _placeholderKey = GlobalKey();
  Rect? _lastLogicalRect;
  Size? _lastLogicalViewSize;
  double? _lastDevicePixelRatio;
  double? _lastTopAirspace;
  double? _lastBottomAirspace;
  bool _syncScheduled = false;

  /** 普通窗口没有顶部悬浮控件，不应为历史全屏布局永久压缩视频视口。 */
  double get _topAirspace =>
      widget.reserveTopControlArea ? _fullscreenTopAirspace : 0;

  /** 控制条收起后只让出常驻细进度条，不再保留整块黑色控制区。 */
  double get _bottomAirspace => widget.reserveBottomControlArea
      ? _visibleControlsOcclusion
      : _hiddenProgressOcclusion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleRectSync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleRectSync();
  }

  @override
  void didUpdateWidget(covariant _WindowsHwndVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleRectSync();
  }

  @override
  void didChangeMetrics() {
    _scheduleRectSync();
  }

  /** 合并同一帧内的布局变更，避免窗口动画向平台线程发送重复 MoveWindow。 */
  void _scheduleRectSync() {
    if (_syncScheduled || !mounted) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) unawaited(_syncRect());
    });
  }

  /** 读取最终布局并只在逻辑矩形或 Flutter 画布尺寸变化时同步原生窗口。 */
  Future<void> _syncRect() async {
    final renderObject =
        _placeholderKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject == null || !renderObject.hasSize) return;
    final origin = renderObject.localToGlobal(Offset.zero);
    final viewSize = MediaQuery.sizeOf(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final logicalRect = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      renderObject.size.width,
      renderObject.size.height,
    );
    if (_lastLogicalRect == logicalRect &&
        _lastLogicalViewSize == viewSize &&
        _lastDevicePixelRatio == devicePixelRatio &&
        _lastTopAirspace == _topAirspace &&
        _lastBottomAirspace == _bottomAirspace) {
      return;
    }
    _lastLogicalRect = logicalRect;
    _lastLogicalViewSize = viewSize;
    _lastTopAirspace = _topAirspace;
    _lastBottomAirspace = _bottomAirspace;
    // 跨 DPI 移窗时逻辑尺寸可能保持不变；仍须让 runner 按新的父 HWND
    // 客户区重新计算物理矩形，避免 child HWND 沿用旧显示器的缩放比例。
    _lastDevicePixelRatio = devicePixelRatio;
    await widget.backend._setHwndSurfaceRect(
      left: logicalRect.left.round(),
      top: logicalRect.top.round(),
      width: logicalRect.width.round(),
      height: logicalRect.height.round(),
      viewWidth: viewSize.width.round(),
      viewHeight: viewSize.height.round(),
      airspaceTop: _topAirspace.round(),
      airspaceBottom: _bottomAirspace.round(),
      visible: logicalRect.width >= 64 && logicalRect.height >= 64,
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleRectSync();
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          key: _placeholderKey,
          color: Colors.black,
          child: const SizedBox.expand(
            key: ValueKey<String>('windows-native.hwnd.placeholder'),
          ),
        ),
        widget.controls,
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      widget.backend._setHwndSurfaceRect(
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        viewWidth: 1,
        viewHeight: 1,
        airspaceTop: 0,
        airspaceBottom: 0,
        visible: false,
      ),
    );
    super.dispose();
  }
}
