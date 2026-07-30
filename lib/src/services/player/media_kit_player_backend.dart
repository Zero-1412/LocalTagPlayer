import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/player_backend_telemetry.dart';
import '../../models/player_gpu_capabilities.dart';
import '../../models/player_video_surface_diagnostics.dart';
import '../../platform/platform_interfaces.dart';
import 'player_backend_telemetry_tracker.dart';
import 'player_texture_output_size_coordinator.dart';
import 'player_video_surface_metrics.dart';
import 'windows_gpu_capability_channel.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 使用现有 media_kit/libmpv 实现 PlayerBackend 的兼容适配器。
 *
 * Player 与 VideoController 的所有权完全留在此类内部；页面只能通过稳定命令、
 * 轻量状态和纹理表面访问播放器，为后续 Windows C++ 后端保留可替换边界。
 */
class MediaKitPlayerBackend
    implements
        PlayerBackend,
        PlayerBackendTelemetryBoundary,
        PlayerVideoSurfaceDiagnosticsBoundary,
        PlayerPropertyBatchBoundary,
        PlayerInteractiveSeekBoundary,
        PlayerGpuRenderBoundary {
  /**
   * media_kit 1.2.6 的 Windows NativePlayer 会在 dispose 返回 5 秒后才调用
   * `mpv_terminate_destroy`；多留 200 ms，确保 released 不早于真实原生销毁。
   */
  static const _windowsNativeDestroyGracePeriod = Duration(
    milliseconds: 5200,
  );

  /** 先展示关键帧，再给连续输入留下一个节流周期，最后精确收敛到用户目标。 */
  static const _interactiveSeekConvergenceDelay = Duration(milliseconds: 120);

  /**
   * 创建 MediaKit 播放后端。
   *
   * Texture 输出默认采用经过 A/B 与重建门禁验证的稳定档位；固定 1920×1080
   * 只保留给显式关闭该参数的 QA 对照，避免小 Widget 长期合成超额像素。
   */
  MediaKitPlayerBackend({
    required String hwdec,
    required bool enableHardwareAcceleration,
    FilterQuality textureFilterQuality = FilterQuality.low,
    bool adaptiveTextureSizingEnabled = true,
  })  : _player = Player(
          // 4K 长视频需要稳定输入窗口；该预算只属于当前播放会话，
          // 不扩大缩略图或媒体详情后台任务的内存占用。
          configuration:
              const PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
        ),
        _controllerConfiguration = VideoControllerConfiguration(
          width: 1920,
          height: 1080,
          hwdec: hwdec,
          enableHardwareAcceleration: enableHardwareAcceleration,
        ),
        _textureFilterQuality = textureFilterQuality,
        _surfaceMetrics = PlayerVideoSurfaceMetricsTracker(
          filterQuality: textureFilterQuality,
        ) {
    _controller = VideoController(
      _player,
      configuration: _controllerConfiguration,
    );
    _textureSizeCoordinator = PlayerTextureOutputSizeCoordinator(
      enabled: adaptiveTextureSizingEnabled,
      requestSize: _requestTextureOutputSize,
    );
    _controller.rect.addListener(_handleTextureRectChanged);
    _controller.id.addListener(_handleTextureIdChanged);
    _errorSubscription = _player.stream.error.listen(_handleBackendError);
    _videoParamsSubscription =
        _player.stream.videoParams.listen(_handleVideoParams);
    _telemetryPositionSubscription =
        _player.stream.position.listen(_handleTelemetryPosition);
    _telemetryObserverInitialization = _attachNativeTelemetryObservers();
  }

  /** 当前适配器独占的 media_kit Player。 */
  final Player _player;

  /** 创建纹理控制器使用的初始配置；稳定布局后可由协调器切换输出档位。 */
  final VideoControllerConfiguration _controllerConfiguration;

  /** 当前适配器独占的视频纹理控制器。 */
  late final VideoController _controller;

  /**
   * Flutter Texture 的合成采样档位。
   *
   * 生产默认保持 media_kit_video 的 `low`（双线性）；只有隔离 QA 会话显式注入其它值。
   */
  final FilterQuality _textureFilterQuality;

  /** Texture 与 Flutter 布局尺寸的纯诊断汇总器。 */
  final PlayerVideoSurfaceMetricsTracker _surfaceMetrics;

  /** 把高频布局变化收敛为稳定档位的原生 Texture 尺寸协调器。 */
  late final PlayerTextureOutputSizeCoordinator _textureSizeCoordinator;

  /** 最近一次非空 Texture ID，仅用于统计代次，不进入诊断正文。 */
  int? _lastTextureId;

  /** 本会话收到的非空 Texture ID 代次数。 */
  var _textureGenerationCount = 0;

  /** dispose 完成信号，保证下一播放器不会越过旧原生资源释放。 */
  final Completer<void> _released = Completer<void>();

  /** 只保存路径无关字段的后端遥测状态机。 */
  final PlayerBackendTelemetryTracker _telemetry =
      PlayerBackendTelemetryTracker(backendName: 'media-kit');

  /** 向页面输出稳定错误分类码，禁止透传可能包含本地路径的原始错误正文。 */
  final StreamController<String> _safeErrors =
      StreamController<String>.broadcast(sync: true);

  /** media_kit 原始错误订阅；后端释放前必须先取消。 */
  late final StreamSubscription<String> _errorSubscription;

  /** 每个新媒体的视频参数订阅，用于约束同实例帧号证据的打开代次。 */
  late final StreamSubscription<VideoParams> _videoParamsSubscription;

  /** 播放位置订阅；只在本代视频参数和 Texture 同时就绪后提供首帧推进证据。 */
  late final StreamSubscription<Duration> _telemetryPositionSubscription;

  /** 同一个 NativePlayer 的帧号与解码器观察器初始化任务。 */
  late final Future<void> _telemetryObserverInitialization;

  /** 是否已在同一个 NativePlayer 上观察帧号。 */
  var _frameObserverAttached = false;

  /** 是否已在同一个 NativePlayer 上观察实际硬解。 */
  var _hwdecObserverAttached = false;

  /** 是否已在同一个 NativePlayer 上观察视频编码。 */
  var _videoCodecObserverAttached = false;

  /** media_kit 当前 VideoController 的 Texture 是否已经具备渲染表面。 */
  var _textureReady = false;

  /** 当前正在打开或播放的匿名代次。 */
  var _activeOpenGeneration = 0;

  /** 最近收到有效视频参数的打开代次。 */
  var _videoParametersGeneration = 0;

  /** 最近收到有效视频参数的时间，供观察器不可用时提供诚实的降级证据。 */
  DateTime? _videoParametersAt;

  /** 后端是否已经进入释放流程。 */
  var _disposed = false;

  /** 每次交互式或精确跳转递增；延迟收敛只允许最后一代写入播放位置。 */
  var _interactiveSeekGeneration = 0;

  /** 串行化重复 dispose 调用，禁止两个释放流程并发进入 media_kit/libmpv。 */
  Future<void>? _disposeFuture;

  @override
  PlayerBackendState get state => PlayerBackendState(
        position: _player.state.position,
        duration: _player.state.duration,
        playing: _player.state.playing,
        buffering: _player.state.buffering,
        volume: _player.state.volume,
        videoTrackCount: _player.state.tracks.video.length,
        audioTrackCount: _player.state.tracks.audio.length,
      );

  @override
  Stream<Duration> get positionChanges => _player.stream.position;

  @override
  Stream<bool> get playingChanges => _player.stream.playing;

  @override
  Stream<bool> get completedChanges => _player.stream.completed;

  @override
  Stream<String> get errorChanges => _safeErrors.stream;

  @override
  PlayerBackendTelemetrySnapshot get telemetry => _telemetry.snapshot;

  @override
  PlayerVideoSurfaceDiagnostics get videoSurfaceDiagnostics {
    final sizing = _textureSizeCoordinator.snapshot;
    return _surfaceMetrics.snapshot.withTextureSizing(
      enabled: sizing.enabled,
      desiredWidth: sizing.desiredSize?.width,
      desiredHeight: sizing.desiredSize?.height,
      requestedWidth: sizing.requestedSize?.width,
      requestedHeight: sizing.requestedSize?.height,
      state: sizing.state,
      requestCount: sizing.requestCount,
      failureCount: sizing.failureCount,
      generationCount: _textureGenerationCount,
    );
  }

  @override
  Stream<PlayerBackendTelemetryEvent> get telemetryChanges => _telemetry.events;

  @override
  ValueListenable<int?> get textureId => _controller.id;

  @override
  Future<void> openPath(String path) async {
    _interactiveSeekGeneration += 1;
    final generation = _telemetry.beginOpen();
    _activeOpenGeneration = generation;
    _videoParametersGeneration = 0;
    _videoParametersAt = null;
    if (generation == 1) {
      // media_kit 的 Future 只证明当前 VideoController Texture 已经具备渲染表面；
      // 固定尺寸初始化可能先显示空表面，因此仍须等待本代 mpv 帧号推进才记录首帧。
      unawaited(_awaitInitialTextureReady());
    }
    if (!await File(path).exists()) {
      // 缺失路径在进入 libmpv 前归一化，既能快速失败，也避免底层错误正文把用户目录
      // 带入 UI 错误流或可复制诊断。
      _recordSafeErrorCode('missing_file');
      throw StateError('missing_file');
    }
    try {
      await _player.open(Media(path));
      if (_activeOpenGeneration == generation) {
        unawaited(_captureDecoder(generation));
      }
    } catch (error) {
      _recordBackendError(error);
      rethrow;
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) {
    _interactiveSeekGeneration += 1;
    return _player.seek(position);
  }

  @override
  Future<void> seekInteractive(Duration position) async {
    final generation = ++_interactiveSeekGeneration;
    final nativePlayer = _nativePlayer;
    if (nativePlayer == null || _player.state.completed) {
      // 非原生平台继续使用公共 API；EOF 必须由 media_kit 清除 completed 状态。
      await _player.seek(position);
      return;
    }
    // media_kit 的公共 seek 使用 absolute 精确定位，长 GOP 随机点击时可能等待较长解码。
    // 交互式入口只要求尽快出现目标附近画面，因此显式选择关键帧；沿用 NativePlayer
    // 的传输锁保证与用户紧邻触发的 play/pause 顺序一致，不绕过既有播放意图。
    await NativePlayer.lock.synchronized(
      () => nativePlayer.command(<String>[
        'seek',
        (position.inMilliseconds / 1000).toStringAsFixed(4),
        'absolute+keyframes',
      ]),
    );
    // 关键帧先提供即时视觉反馈；延迟精确跳转只保留最后一代，连续点击不会被旧目标拉回。
    unawaited(_convergeInteractiveSeek(generation, position));
  }

  /** 在关键帧已经可见后精确收敛；释放、打开新媒体或新 seek 会取消旧代次。 */
  Future<void> _convergeInteractiveSeek(
    int generation,
    Duration position,
  ) async {
    await Future<void>.delayed(_interactiveSeekConvergenceDelay);
    if (_disposed || generation != _interactiveSeekGeneration) {
      return;
    }
    try {
      await _player.seek(position);
    } catch (error) {
      // 延迟任务不能泄漏未处理异常；仍有效的后端错误沿用安全分类流。
      if (!_disposed && generation == _interactiveSeekGeneration) {
        _recordBackendError(error);
      }
    }
  }

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> playOrPause() => _player.playOrPause();

  /**
   * 返回 media_kit 当前播放器实际持有的同一个 NativePlayer。
   *
   * 常规播放继续走 media_kit 公共 API；只有 libmpv 高级属性通过该对象下发，
   * 禁止再创建第二个 mpv_handle 或第二条 Texture/解码链。
   */
  NativePlayer? get _nativePlayer {
    final platform = _player.platform;
    return platform is NativePlayer ? platform : null;
  }

  /**
   * 在现有 NativePlayer 上观察帧号，作为连续切换后的首帧推进证据。
   *
   * 这里只注册属性观察器，不创建第二个 Player、mpv_handle、Texture 或解码链。
   */
  Future<void> _attachNativeTelemetryObservers() async {
    final nativePlayer = _nativePlayer;
    if (nativePlayer == null) {
      return;
    }
    try {
      await nativePlayer.observeProperty(
        'estimated-frame-number',
        (value) async {
          if (_disposed) {
            return;
          }
          final generation = _activeOpenGeneration;
          final frameNumber =
              int.tryParse(value) ?? double.tryParse(value)?.floor();
          if (generation == 0 ||
              !_textureReady ||
              generation != _videoParametersGeneration ||
              frameNumber == null ||
              frameNumber < 0) {
            return;
          }
          _recordFirstFrame(
            generation,
            evidence: 'media-kit-texture+mpv-estimated-frame-number',
          );
        },
      );
      _frameObserverAttached = true;
    } catch (_) {
      // 个别非 libmpv 平台可能不支持属性观察；视频参数事件会保留显式降级证据。
    }
    try {
      await nativePlayer.observeProperty(
        'hwdec-current',
        (value) async {
          if (_disposed || _activeOpenGeneration == 0) {
            return;
          }
          _telemetry.recordDecoder(
            generation: _activeOpenGeneration,
            hwdecCurrent: _normalizeHwdec(value),
            videoCodec: _telemetry.snapshot.videoCodec,
          );
        },
      );
      _hwdecObserverAttached = true;
    } catch (_) {
      // 观察失败时仍由首帧后的显式属性读取提供兼容遥测。
    }
    try {
      await nativePlayer.observeProperty(
        'video-codec',
        (value) async {
          if (_disposed || _activeOpenGeneration == 0) {
            return;
          }
          _telemetry.recordDecoder(
            generation: _activeOpenGeneration,
            hwdecCurrent: _telemetry.snapshot.hwdecCurrent,
            videoCodec: _normalizeTelemetryValue(value),
          );
        },
      );
      _videoCodecObserverAttached = true;
    } catch (_) {
      // 观察失败时仍由首帧后的显式属性读取提供兼容遥测。
    }
  }

  /**
   * 等待 media_kit 确认当前 VideoController 的 Texture 表面已经可用。
   *
   * 该 Future 可能在媒体打开前因固定尺寸空表面完成，因此这里只设置门禁，不能直接
   * 记录当前媒体首帧。
   */
  Future<void> _awaitInitialTextureReady() async {
    try {
      await _controller.waitUntilFirstFrameRendered;
      if (_disposed) {
        return;
      }
      _textureReady = true;
    } catch (_) {
      // 首帧等待失败不能取代正式错误流；快照保持未知，供异常文件测试识别超时。
    }
  }

  /**
   * 处理每个新媒体的有效视频参数。
   *
   * Windows/libmpv 继续等待帧号推进；观察器不可用的平台明确标记为参数就绪降级，
   * 不把它伪装为 Texture 已渲染。
   */
  void _handleVideoParams(VideoParams params) {
    if (_disposed ||
        params.dw == null ||
        params.dh == null ||
        params.dw == 0 ||
        params.dh == 0) {
      return;
    }
    final generation = _activeOpenGeneration;
    if (generation == 0) {
      return;
    }
    _videoParametersGeneration = generation;
    _videoParametersAt = DateTime.now();
    if (_nativePlayer == null) {
      _recordFirstFrame(
        generation,
        evidence: 'video-parameters-ready-fallback',
        at: _videoParametersAt,
      );
      return;
    }
    unawaited(_recordVideoParamsFallback(generation));
  }

  /**
   * 使用 media_kit 当前代播放头更新补充首帧证据。
   *
   * 位置事件只有在本代视频参数与 Texture 均已就绪后才有效，避免快速切换时把上一媒体
   * 的迟到位置写入新代次。该证据比单纯视频参数更强，但仍保留具体来源供 A/B 口径筛选。
   */
  void _handleTelemetryPosition(Duration _) {
    if (_disposed || !_textureReady) {
      return;
    }
    final generation = _activeOpenGeneration;
    if (generation == 0 || generation != _videoParametersGeneration) {
      return;
    }
    _recordFirstFrame(
      generation,
      evidence: 'media-kit-texture+position-update',
    );
  }

  /**
   * 帧号观察器不可用或在有限窗口内没有推进时，保留视频参数降级证据。
   *
   * 等待窗口只用于让更强的帧号/Texture 证据优先；回填时间仍使用视频参数实际到达时间，
   * 不能把诊断等待本身算入首帧耗时。
   */
  Future<void> _recordVideoParamsFallback(int generation) async {
    await _telemetryObserverInitialization;
    if (_frameObserverAttached) {
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    if (_disposed || generation != _videoParametersGeneration) {
      return;
    }
    _recordFirstFrame(
      generation,
      evidence: _frameObserverAttached
          ? 'texture+video-parameters-timeout-fallback'
          : 'video-parameters-ready-fallback',
      at: _videoParametersAt,
    );
  }

  /** 写入首帧快照，并在同一代次异步读取实际解码器。 */
  void _recordFirstFrame(
    int generation, {
    required String evidence,
    DateTime? at,
  }) {
    final recorded = _telemetry.recordFirstFrame(
      generation: generation,
      evidence: evidence,
      at: at,
    );
    if (recorded) {
      unawaited(_captureDecoder(generation));
    }
  }

  /**
   * 从同一个 NativePlayer 读取当前媒体的实际硬解与视频编码。
   *
   * 空 `hwdec-current` 在 libmpv 中代表软件解码，统一记录为 `no`；不可用属性保持未知。
   */
  Future<void> _captureDecoder(int generation) async {
    final values = await Future.wait<String>([
      getProperty('hwdec-current'),
      getProperty('video-codec'),
    ]);
    if (_disposed || generation != _activeOpenGeneration) {
      return;
    }
    final hwdec = _normalizeHwdec(values[0]);
    final codec = _normalizeTelemetryValue(values[1]);
    _telemetry.recordDecoder(
      generation: generation,
      hwdecCurrent: hwdec,
      videoCodec: codec,
    );
  }

  /** 把 libmpv 空硬解属性归一化为明确的软件解码 `no`。 */
  String? _normalizeHwdec(String value) =>
      value == 'empty' || value.trim().isEmpty
          ? 'no'
          : _normalizeTelemetryValue(value);

  /** 把不可用或空属性保留为未知，避免诊断把占位文本当成真实解码值。 */
  String? _normalizeTelemetryValue(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ||
            normalized == 'empty' ||
            normalized == 'unavailable'
        ? null
        : normalized;
  }

  /** 把原始错误转换为路径无关分类码并同时写入错误流和遥测。 */
  void _handleBackendError(String error) => _recordBackendError(error);

  /** 直接记录已经归一化的稳定错误码，不再接触或转换本地路径。 */
  void _recordSafeErrorCode(
    String code, {
    bool affectsCurrentOpen = true,
  }) {
    _telemetry.recordError(
      code,
      affectsCurrentOpen: affectsCurrentOpen,
    );
    if (!_safeErrors.isClosed) {
      _safeErrors.add(code);
    }
  }

  /** 记录一个路径无关错误分类码；释放竞态期间不再向关闭的 UI 流写入。 */
  void _recordBackendError(
    Object error, {
    bool affectsCurrentOpen = true,
  }) {
    final code = classifyPlayerBackendError(error);
    _recordSafeErrorCode(code, affectsCurrentOpen: affectsCurrentOpen);
  }

  @override
  Future<void> setProperty(String property, String value) async {
    final nativePlayer = _nativePlayer;
    if (nativePlayer == null) {
      throw StateError('player_not_initialized');
    }
    // 错误必须返回给事务或功能协调器，不能让上层把失败请求标记为已启用。
    await nativePlayer.setProperty(property, value);
  }

  /**
   * 在同一个 NativePlayer 初始化门禁后连续提交完整属性快照。
   *
   * 第一项等待 Player 与 VideoController 就绪，后续项复用已确认的会话，减少
   * 打开媒体和切换画质档位时重复等待初始化 Future 的开销。
   */
  @override
  Future<void> setProperties(Map<String, String> properties) async {
    final nativePlayer = _nativePlayer;
    if (properties.isEmpty) return;
    if (nativePlayer == null) {
      throw StateError('player_not_initialized');
    }
    var waitForInitialization = true;
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final entry in properties.entries) {
      try {
        await nativePlayer.setProperty(
          entry.key,
          entry.value,
          waitForInitialization: waitForInitialization,
        );
      } catch (error, stackTrace) {
        // 继续处理快照剩余项，最后再把首个失败交给上层统一读回与安全回退。
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      } finally {
        waitForInitialization = false;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  @override
  Future<String> getProperty(String property) async {
    try {
      final nativePlayer = _nativePlayer;
      if (nativePlayer == null) return 'unavailable';
      final value = await nativePlayer.getProperty(property);
      final text = value.trim();
      return text.isEmpty ? 'empty' : text;
    } catch (_) {
      return 'unavailable';
    }
  }

  @override
  Future<PlayerGpuCapabilityMatrix> queryGpuCapabilities() =>
      queryWindowsGpuCapabilities();

  @override
  Future<PlayerGpuActiveAdapter> queryActiveGpuAdapter() =>
      queryWindowsActiveGpuAdapter(backend: 'media-kit');

  @override
  Future<PlayerGpuComputeFrameBudget> benchmarkGpuComputeFrameBudget(
    String adapterLuid,
  ) =>
      benchmarkWindowsGpuComputeFrameBudget(adapterLuid);

  @override
  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) =>
      _player.screenshot(format: format);

  /** 接收原生插件回传的 Texture 像素矩形并刷新同口径缩放诊断。 */
  void _handleTextureRectChanged() {
    final rect = _controller.rect.value;
    if (rect == null || rect.width <= 1 || rect.height <= 1) {
      return;
    }
    _surfaceMetrics.recordTextureSize(rect.size);
    _textureSizeCoordinator.recordActualTextureSize(rect.size);
    _observeCurrentFittedTarget();
  }

  /** 统计 Texture 注册代次；ID 本身属于原生句柄，不写入任何报告。 */
  void _handleTextureIdChanged() {
    final textureId = _controller.id.value;
    if (textureId == null || textureId == _lastTextureId) {
      return;
    }
    _lastTextureId = textureId;
    _textureGenerationCount += 1;
  }

  /** 记录 Flutter 表面指标，并把有效物理画面尺寸交给稳定档位协调器。 */
  void _handleWidgetSurfaceMetrics(
    Size logicalSize,
    double devicePixelRatio,
    BoxFit fit,
    double? aspectRatio,
  ) {
    _surfaceMetrics.recordWidgetSurfaceMetrics(
      logicalSize,
      devicePixelRatio,
      fit,
      aspectRatio,
    );
    _observeCurrentFittedTarget();
  }

  /** Texture 与 Widget 任一侧晚到时都重新合并，避免首次布局丢失自适应目标。 */
  void _observeCurrentFittedTarget() {
    final snapshot = _surfaceMetrics.snapshot;
    final width = snapshot.fittedVideoPhysicalWidthPx;
    final height = snapshot.fittedVideoPhysicalHeightPx;
    if (width == null || height == null) {
      return;
    }
    _textureSizeCoordinator.observeFittedPhysicalTarget(Size(width, height));
  }

  /**
   * 向同一 VideoController 下发稳定档位。
   *
   * 调用只可能来自带去抖和确认门禁的协调器；页面与布局观察器不得直接调用 setSize。
   */
  Future<void> _requestTextureOutputSize(Size size) {
    return _controller.setSize(
      width: size.width.round(),
      height: size.height.round(),
    );
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
    final videoSurface = Video(
      // media_kit 1.3.1 无法通过 copyWith 把非空 aspectRatio 清回 null；
      // 模式变化时重建轻量 Video 视图，底层 Player/解码会话保持不变。
      key: ValueKey('media-kit-video.${fit.name}.${aspectRatio ?? 'auto'}'),
      controller: _controller,
      controls: (_) => const SizedBox.shrink(),
      fit: fit,
      aspectRatio: aspectRatio,
      filterQuality: _textureFilterQuality,
    );
    return PlayerVideoSurfaceMetricsObserver(
      fit: fit,
      aspectRatio: aspectRatio,
      onMetricsChanged: _handleWidgetSurfaceMetrics,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 镜像只作用于视频表面；Flutter 控制条保持原方向与点击坐标。
          Transform.flip(flipX: mirror, child: videoSurface),
          controls,
        ],
      ),
    );
  }

  @override
  Future<void> dispose() => _disposeFuture ??= _disposeOnce();

  /** 串行释放订阅、Player、Texture 与延迟销毁的 Windows 原生资源。 */
  Future<void> _disposeOnce() async {
    if (_released.isCompleted) return;
    _disposed = true;
    _interactiveSeekGeneration += 1;
    _telemetry.beginRelease();
    final playerDisposeWatch = Stopwatch();
    var nativeReleaseWait = Duration.zero;
    try {
      await _errorSubscription.cancel();
      await _videoParamsSubscription.cancel();
      await _telemetryPositionSubscription.cancel();
      await _telemetryObserverInitialization;
      _textureSizeCoordinator.dispose();
      _controller.rect.removeListener(_handleTextureRectChanged);
      _controller.id.removeListener(_handleTextureIdChanged);
      final nativePlayer = _nativePlayer;
      if (nativePlayer != null) {
        for (final property in <String>[
          if (_frameObserverAttached) 'estimated-frame-number',
          if (_hwdecObserverAttached) 'hwdec-current',
          if (_videoCodecObserverAttached) 'video-codec',
        ]) {
          try {
            await nativePlayer.unobserveProperty(property);
          } catch (_) {
            // Player 已先进入销毁时允许观察器随 NativePlayer 一起释放。
          }
        }
      }
      playerDisposeWatch.start();
      await _player.dispose();
      playerDisposeWatch.stop();
      if (Platform.isWindows) {
        // Flutter 纹理解绑早于 libmpv 最终销毁；下一会话必须等这段依赖内置延迟结束，
        // 否则两个 mpv_handle、D3D 资源和解码缓存会在高位重叠。
        final nativeWaitWatch = Stopwatch()..start();
        await Future<void>.delayed(_windowsNativeDestroyGracePeriod);
        nativeWaitWatch.stop();
        nativeReleaseWait = nativeWaitWatch.elapsed;
      }
    } catch (error) {
      if (playerDisposeWatch.isRunning) {
        playerDisposeWatch.stop();
      }
      _recordBackendError(error, affectsCurrentOpen: false);
      rethrow;
    } finally {
      _telemetry.completeRelease(
        playerDisposeDuration: playerDisposeWatch.elapsed,
        nativeReleaseWait: nativeReleaseWait,
      );
      await _safeErrors.close();
      await _telemetry.close();
      if (!_released.isCompleted) _released.complete();
    }
  }

  @override
  Future<void> get released => _released.future;
}
