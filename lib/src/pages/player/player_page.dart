import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/playback_settings.dart';
import '../../features/library/domain/library_query_snapshot.dart';
import '../../features/player/application/player_backend_event_bridge.dart';
import '../../features/player/application/player_fullscreen_lifecycle_controller.dart';
import '../../features/player/application/player_interaction_state_controller.dart';
import '../../features/player/application/player_open_request_controller.dart';
import '../../features/player/application/player_session_controller.dart';
import '../../features/player/application/player_shortcut_gate_controller.dart';
import '../../models/media_details.dart';
import '../../models/video_item.dart';
import '../../platform/file_system_adapter.dart';
import '../../platform/platform_interfaces.dart';
import '../../services/media/media_details_service.dart';
import '../../services/media/thumbnail_service.dart';
import '../../services/player/player_adaptive_quality.dart';
import '../../services/player/player_hdr_mapping_experiment.dart';
import '../../services/player/player_gpu_capability_detector.dart';
import '../../services/player/player_nvidia_video_enhancement_experiment.dart';
import '../../services/player/player_resource_lifecycle_coordinator.dart';
import '../../services/player/player_service.dart';
// ignore_for_file: slash_for_doc_comments

export 'player_opening_widgets.dart';
export 'player_chrome_widgets.dart';
export 'player_stability_snapshot.dart';
import 'player_state_initialization.dart';
export 'player_state_initialization.dart';
export 'player_state_events.dart';
import 'player_state_nvidia.dart';
export 'player_state_nvidia.dart';
export 'player_state_transport.dart';
export 'player_state_health.dart';
export 'player_state_controls.dart';
export 'player_state_chrome.dart';
import 'player_state_performance.dart';
export 'player_state_performance.dart';
import 'player_state_opening.dart';
export 'player_state_opening.dart';
import 'player_state_queue.dart';
export 'player_state_queue.dart';
export 'player_state_dialogs.dart';
export 'player_state_item_actions.dart';
export 'player_state_diagnostics.dart';
export 'player_state_helpers.dart';
import 'player_state_resources.dart';
export 'player_state_resources.dart';
import 'player_state_view.dart';
export 'player_state_view.dart';
export 'player_top_bar.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.initialItem,
    required this.playlist,
    this.queueSnapshot,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.onPlaybackSettingsChanged,
    required this.activeTags,
    required this.activeChildTag,
    required this.queueTitle,
    required this.onDeleteVideo,
    required this.onToggleFavorite,
    required this.onRenameFile,
    required this.onEditManualTags,
    required this.onRelinkMissing,
    required this.onPlaybackProgressUpdated,
    required this.onMediaDetailsUpdated,
    required this.disposalCompleter,
    required this.fileSystem,
    required this.playerServiceFactory,
    required this.mediaProbeBackendFactory,
    required this.fullscreenSessionController,
  });

  final VideoItem initialItem;
  /** 已接受媒体库结果对应的队列版本；独立播放器测试可不提供。 */
  final LibraryQueueSnapshot? queueSnapshot;
  /** 与 [queueSnapshot] stable-ID 顺序一致的不可变来源队列。 */
  final List<VideoItem> playlist;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  /** 保存全局播放器设置；调用方必须同步更新应用内存状态与持久化文件。 */
  final Future<void> Function(PlaybackSettings settings)
      onPlaybackSettingsChanged;
  final List<String> activeTags;
  final String? activeChildTag;
  final String queueTitle;
  /** 删除媒体库记录，并按用户确认结果选择是否把本地文件移入回收站。 */
  final Future<void> Function(VideoItem item, bool moveLocalFileToTrash)
      onDeleteVideo;
  final Future<void> Function(VideoItem item) onToggleFavorite;
  /** 通过媒体库协调物理文件与稳定 mutable path 的同目录重命名事务。 */
  final Future<void> Function(VideoItem item, String newBaseName) onRenameFile;
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

  /** 组合根提供的应用层播放服务工厂；页面不选择或取得具体后端。 */
  final PlayerServiceFactory playerServiceFactory;

  /** 由组合根选择的媒体探测后端工厂。 */
  final MediaProbeBackendFactory mediaProbeBackendFactory;

  /** 媒体库 Route 持有的播放器全屏会话状态，不参与持久化。 */
  final PlayerFullscreenSessionController fullscreenSessionController;

  @override
  State<PlayerPage> createState() => PlayerPageState();
}

class PlayerPageState extends State<PlayerPage> {
  /**
   * 供同库状态扩展触发受控重建。
   *
   * `setState` 的生命周期所有权仍保留在真正的 [State] 子类中。
   */
  void rebuild(VoidCallback action) => setState(action);

  /** 供同库状态扩展只读访问页面输入。 */
  PlayerPage get pageWidget => widget;

  /** 解析 MPV 数值属性；不可用占位保持为空，避免伪造诊断值。 */
  double? parseMpvNumber(String? value) {
    final text = value?.trim();
    if (text == null ||
        text.isEmpty ||
        text == 'empty' ||
        text == 'unavailable') {
      return null;
    }
    return double.tryParse(text);
  }

  /** 将 MPV 数值属性安全转换为整数诊断值。 */
  int? parseMpvInt(String? value) => parseMpvNumber(value)?.round();

  /** 页面独占的应用层播放服务；资源释放只允许由 [playerResources] 调用。 */
  late final PlayerService playerServiceOwner;
  /** 诊断弹窗使用的只读播放服务。 */
  PlayerService get playerService => playerServiceOwner;
  /**
   * 真实画质集成测试使用的会话门禁入口。
   *
   * 测试仍先证明设置开关已挂载且可响应；实际 A/B 调用此方法并等待完整的能力复核、
   * 滤镜写入、驱动确认或安全回滚，避免 child HWND 坐标命中偶发性污染画质结论。
   */
  @visibleForTesting
  Future<void> setNvidiaVideoEnhancementForTesting(bool enabled) =>
      setNvidiaVideoEnhancementExperimentEnabled(enabled);
  /** 真实 SDR→HDR 集成测试使用的会话门禁入口。 */
  @visibleForTesting
  Future<void> setNvidiaVideoHdrForTesting(bool enabled) =>
      setNvidiaVideoHdrExperimentEnabled(enabled);
  late final FocusNode focusNode;
  late final ScrollController queueScrollController;
  late final ScrollController fullscreenQueueScrollController;
  late final MediaDetailsService detailsService;
  late final String requestedHwdec;
  late final PlayerSessionController playback;
  final openRequests = PlayerOpenRequestController();
  /** 用于把设置浮层右边缘锚定到齿轮按钮，而不是按整个窗口居中。 */
  final settingsButtonAnchorKey = GlobalKey();
  /** 用于把画面内鼠标位置换算到底部控制区，不额外叠加拦截按钮的命中层。 */
  final videoControlsRegionKey = GlobalKey();
  /** 正在等待兼容性确认的路径；避免快速点击叠加多个警告弹窗。 */
  String? compatibilityPromptPath;
  /** 集中持有四类后端事件订阅，并在 PlayerService 释放前统一取消。 */
  late final PlayerBackendEventBridge backendEvents;
  /** Texture listener 与 backend/native surface 串行释放的唯一 owner。 */
  late final PlayerResourceLifecycleCoordinator playerResources;
  /** 桌面全屏状态与窗口命令顺序的唯一 owner。 */
  late final PlayerFullscreenLifecycleController windowFullscreen;
  /** 主控制条与短时快捷键反馈的纯状态及 Timer owner。 */
  late final PlayerInteractionStateController<IconData> interaction;
  /** 快捷键暂停深度与处理/焦点恢复资格的纯状态 owner。 */
  final shortcutGate = PlayerShortcutGateController();
  Timer? queuePrefetchTimer;
  Timer? fullscreenQueueHideTimer;
  Timer? playbackHealthTimer;
  var playbackHealthSampling = false;
  /** 第二阶段自动画质协调器；只消费低频诊断样本，不创建额外定时器。 */
  final PlayerAdaptiveQualityCoordinator adaptiveQualityCoordinator =
      PlayerAdaptiveQualityCoordinator();
  /** 第三阶段能力检测器；只通过 PlayerService 查询当前引擎的真实运行属性。 */
  final PlayerGpuCapabilityDetector gpuCapabilityDetector =
      const PlayerGpuCapabilityDetector();
  /** HDR 映射复用播放健康样本，并在压力出现后锁存关闭到下一媒体。 */
  final PlayerHdrMappingSafetyCoordinator hdrMappingSafetyCoordinator =
      PlayerHdrMappingSafetyCoordinator();
  /** 暗部增强复用同一低频压力判定，但拥有独立计数与会话回滚锁存。 */
  final PlayerHdrMappingSafetyCoordinator darkSceneSafetyCoordinator =
      PlayerHdrMappingSafetyCoordinator(featureLabel: '暗部增强');
  /** NVIDIA D3D11 滤镜复用同一掉帧熔断，但独立锁存且不改其它增强设置。 */
  final PlayerHdrMappingSafetyCoordinator nvidiaVideoSafetyCoordinator =
      PlayerHdrMappingSafetyCoordinator(featureLabel: 'NVIDIA 视频增强');
  /** 显示同步插值复用同一播放压力熔断，但不与 AI 补帧或 NVIDIA 能力混淆。 */
  final PlayerHdrMappingSafetyCoordinator smoothMotionSafetyCoordinator =
      PlayerHdrMappingSafetyCoordinator(featureLabel: '显示同步插值');
  /** 当前会话已经实际送入后端的自动增强档位。 */
  PlayerAdaptiveQualityLevel adaptiveQualityLevel =
      PlayerAdaptiveQualityLevel.off;
  /** 最近一次播放器会话能力检测结果；新媒体打开时作废并重新检测。 */
  PlayerGpuCapabilitySnapshot? gpuCapabilitySnapshot;
  /** HDR 映射只有在当前媒体与实际活动 LUID 均通过门槛后才对本会话生效。 */
  var hdrMappingExperimentActive = false;
  /** 当前 SDR 会话已经通过分辨率、硬解和传递函数门槛并启用暗部增强。 */
  var darkSceneEnhancementActive = false;
  /** 暗部增强只回滚当前媒体，不改写用户的持久开关。 */
  String? darkSceneEnhancementRollbackReason;
  /** 暗部增强自动回滚时间，用于与诊断掉帧样本对齐。 */
  DateTime? darkSceneEnhancementRollbackAt;
  /** 当前媒体最近一次 HDR 自动回滚原因；全局开关不会被改写。 */
  String? hdrMappingRollbackReason;
  /** 当前媒体 HDR 自动回滚发生时间，用于与掉帧和功耗基线对齐。 */
  DateTime? hdrMappingRollbackAt;
  /** 画质余量扩展采样每两秒执行一次，供自动增强与 HDR 压力保护共享。 */
  var qualityMarginSampleTick = 0;
  DateTime? lastProgressWriteAt;
  Duration lastPersistedPosition = Duration.zero;
  DateTime? ignoreQueueSelectionBefore;
  String? handledCompletedPath;
  String? openedPath;
  /** 当前打开请求使用的已验证缩略图；只承担原生纹理首帧占位。 */
  File? openingPosterFile;
  /** [openingPosterFile] 对应路径，防止快速切换时旧 Future 覆盖新视频。 */
  String? openingPosterPath;
  int? lastSeekLatencyMs;
  DateTime? lastSeekAt;
  int? lastVideoFrameNumber;
  double? lastAudioPts;
  DateTime? lastVideoAdvanceAt;
  DateTime? lastAudioAdvanceAt;
  DateTime? lastHealthSampleAt;
  /** 最近一次 mpv 明确报告的实际硬解状态，不把属性不可用误判为软件解码。 */
  String? lastHwdecCurrent;
  var consecutiveSoftwareDecodeSamples = 0;
  var softwareDecodeConfirmed = false;
  var videoProgressState = '等待首个视频样本';
  var audioProgressState = '等待首个音频样本';
  var videoStallEvents = 0;
  var audioStallEvents = 0;
  DateTime? exitRequestedAt;
  DateTime? pauseAcknowledgedAt;
  DateTime? routePopRequestedAt;
  Duration? pendingSeekTarget;
  /** seek 工作器繁忙时记录用户最新目标，使连续快捷键基于尚未确认的目标累加。 */
  Duration? latestRequestedSeekTarget;
  /** 每个 seek 输入递增；工作器只提交短时间内不再被替换的最新一代。 */
  var seekRequestGeneration = 0;
  var seekInFlight = false;
  var isExiting = false;
  /** 恢复选择弹窗期间暂停进度写入，避免刚打开的 0 秒覆盖稳定进度。 */
  var choosingPlaybackStart = false;
  var queueEndReached = false;
  /** 文件重命名事务期间阻止重复点击和播放器快捷键并发操作。 */
  var renamingFile = false;
  /**
   * Flutter 弹层对应的原生裁剪矩形栈。
   *
   * 菜单继续打开信息或诊断弹窗时，内层可临时替换外层裁剪策略；最后一层关闭后
   * 才恢复完整 child HWND，避免嵌套路由交接时闪回并覆盖 Flutter。
   */
  final List<Rect?> overlaySurfaceRects = <Rect?>[];
  late PlayerPlaybackMode playbackMode;
  late double playbackRate;
  /** 是否仅水平翻转当前视频画面，控制条与命中区域保持原方向。 */
  late bool mirrorVideo;
  /** 当前全局画面比例；打开新媒体后会重新应用到后端。 */
  late PlayerVideoAspectMode videoAspectMode;
  /** 当前缩放器基线；超分关闭后恢复该值。 */
  late PlayerVideoScaler videoScaler;
  /** 用户请求的流畅度增强档位；运行期回滚不会改写此持久偏好。 */
  late PlayerSmoothMotionMode smoothMotionMode;
  /** 当前媒体是否已通过属性读回确认显示同步插值配置。 */
  var smoothMotionActive = false;
  /** 最近一次类型化配置或回退结果，不包含原生错误与路径。 */
  var smoothMotionApplyReason = '尚未应用';
  /** 当前媒体显示同步插值的自动回滚原因。 */
  String? smoothMotionRollbackReason;
  /** 当前媒体显示同步插值的自动回滚时间。 */
  DateTime? smoothMotionRollbackAt;
  /** 当前显示输出电平策略。 */
  late PlayerVideoOutputRange videoOutputRange;
  /** 当前全局 GPU 高质量缩放开关；只影响 libmpv 渲染缩放器，不调用 NVIDIA AI。 */
  late bool videoSuperResolutionEnabled;
  /** 当前用户选择与硬解条件是否允许 MPV 专属画质强化实际生效。 */
  bool get mpvEnhancementsAvailable =>
      effectivePlaybackSettings.rendererPreference !=
          PlayerRendererPreference.mediaKit &&
      effectivePlaybackSettings.hardwareDecodingEnabled;
  /** 当前媒体是否已经由自动策略请求 NVIDIA RTX 视频超分。 */
  var nvidiaVideoEnhancementExperimentEnabled = false;
  /** 当前 SDR 媒体是否已经由自动策略请求 NVIDIA RTX Video HDR。 */
  var nvidiaVideoHdrExperimentEnabled = false;
  /**
   * NVIDIA 独占 `vf` 时是否暂时挂起了当前媒体的 CPU 画质增强。
   *
   * 这里只改变会话运行态，不覆盖压缩画质和暗场增强的持久偏好。
   */
  var nvidiaCpuEnhancementsSuspended = false;
  /** NVIDIA 开启前暗场增强是否实际活动，用于关闭或失败后恢复当前媒体。 */
  var nvidiaSuspendedDarkSceneEnhancement = false;
  /** NVIDIA 视频增强只回滚当前媒体，不自动切换用户选择的解码器。 */
  String? nvidiaVideoEnhancementRollbackReason;
  /** NVIDIA 视频增强自动回滚时间，用于与诊断掉帧样本对齐。 */
  DateTime? nvidiaVideoEnhancementRollbackAt;
  /** 当前媒体的 NVIDIA 自动决策原因；不持久化，也不依赖 NVIDIA App 状态页。 */
  var nvidiaVideoAutomaticReason = '等待当前媒体能力';
  /** 内嵌 mpv 的 d3d11vpp NVIDIA 模式能力；探测只读且不触碰插件 ABI。 */
  var nvidiaVideoEnhancementCapability =
      const PlayerNvidiaVideoEnhancementCapability.probing();
  /** 当前压缩画质增强档位；只控制实时滤镜与低频性能协调。 */
  late PlayerCompressionEnhancementMode compressionEnhancementMode;
  /** 快进与快退快捷键共用的离散跳转秒数。 */
  late int seekStepSeconds;
  /** 当前播放器会话使用的全局配置快照。 */
  late PlaybackSettings effectivePlaybackSettings;
  /** 页面即时音量；避免异步后端快照让滑条、图标和键盘反馈不同步。 */
  late double volume;
  /** 一键静音前最近一次非零音量，用于准确恢复用户原值。 */
  double lastAudibleVolume = 100;
  /** 串行保存设置，避免连续点击时旧写入覆盖最后一次选择。 */
  Future<void> playbackSettingsSaveTail = Future<void>.value();
  /** 用户主动折叠宽屏右侧队列时保持当前页面内的显示状态。 */
  var queueSidebarCollapsed = false;
  /** 全屏时是否在画面右侧显示不改变视频尺寸的当前筛选队列覆盖层。 */
  var fullscreenQueueVisible = false;
  /** 宽屏队列折叠时，指针是否进入非全屏顶部标题栏热区。 */
  var pointerInWindowTopBarRegion = false;
  final random = math.Random();

  static const playbackRates = PlaybackSettings.playbackRates;
  static const seekStepOptions = PlaybackSettings.seekStepOptions;

  List<VideoItem> get sourcePlaylist => playback.sourcePlaylist;

  List<VideoItem> get queue => playback.queue;

  String? get selectedChildTag => playback.selectedChildTag;

  int get index => playback.playingIndex;

  int get selectedIndex => playback.selectedIndex;

  VideoItem get currentItem => playback.currentItem;

  PlayerOpenTarget get currentOpenTarget =>
      (videoId: currentItem.videoId, path: currentItem.path);

  bool get controlsVisible => interaction.controlsVisible;

  bool get shortcutFeedbackVisible => interaction.feedbackVisible;

  String? get shortcutFeedbackLabel => interaction.feedbackLabel;

  IconData get shortcutFeedbackIcon => interaction.feedbackIcon;

  bool get shortcutFeedbackIsSeekWatermark =>
      interaction.feedbackIsSeekWatermark;

  bool get settingsDialogOpen => interaction.settingsOpen;

  bool get isWindowFullscreen => windowFullscreen.isFullscreen;

  bool get fullscreenTransitionInProgress =>
      windowFullscreen.transitionInProgress;

  String get filterSummary {
    final value = widget.queueTitle.trim();
    return value.isEmpty ? '\u5168\u90e8\u89c6\u9891' : value;
  }

  String? get activeParentTag =>
      widget.activeTags.length == 1 ? widget.activeTags.first : null;

  void selectChildTag(String tag) {
    if (queue.isEmpty) {
      return;
    }
    persistOpenedProgress();
    setState(() {
      queueEndReached = false;
      playback.toggleChildTag(tag, preferredVideoId: currentItem.videoId);
    });
    ensureQueueIndexVisible(index, center: true);
    requestOpenCurrent();
  }

  @override
  void initState() {
    super.initState();
    initializePlayerPage();
  }

  @override
  void dispose() {
    disposePlayerPage();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => buildPlayerPage(context);
}
