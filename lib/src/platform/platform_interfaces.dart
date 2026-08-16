import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/external_media_tools_state.dart';
import '../models/media_details.dart';
import '../models/platform_models.dart';
import '../models/player_backend_telemetry.dart';
import '../models/player_filter_transaction.dart';
import '../models/player_gpu_capabilities.dart';
import '../models/player_motion_interpolation_capability.dart';
import '../models/player_media_controls.dart';
import '../models/player_video_surface_diagnostics.dart';
import '../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放应用层与底层引擎之间共享的最小运行时能力。
 *
 * 画质协调器和诊断服务可以通过该接口读取引擎属性，但 Flutter 页面不应据此取得
 * media_kit Player、mpv handle、D3D11 纹理或 HWND。正式页面只持有 PlayerService。
 */
abstract interface class PlayerRuntimeAccess {
  /** 当前后端的只读播放状态；UI 不得据此取得原生 Player。 */
  PlayerBackendState get state;

  /** 纹理标识变化通知；原生后端可据此报告纹理挂载与解绑。 */
  ValueListenable<int?> get textureId;

  /**
   * 设置底层引擎属性。
   *
   * 实现必须把初始化失败或属性拒绝返回给调用方；可选功能协调器负责降级，不能静默吞错
   * 后把用户请求冒充为已生效。
   */
  Future<void> setProperty(String property, String value);

  /** 查询底层诊断属性；不可用时返回统一占位文本。 */
  Future<String> getProperty(String property);

  /**
   * 查询原生显卡设备矩阵。
   *
   * 返回值必须区分系统具备某能力与当前渲染器已经唯一锁定该适配器；不支持的平台
   * 返回 `unsupported` 快照，禁止按显卡名称猜测 Compute、Vulkan 或显存。
   */
  Future<PlayerGpuCapabilityMatrix> queryGpuCapabilities();
}

/**
 * 可把一组有序属性作为一次后端事务提交的可选边界。
 *
 * Windows libmpv 用它减少 MethodChannel 往返和原生全量状态采样；不支持该边界的
 * 后端仍由 [PlayerService] 逐项写入，不能因此改变 MediaKit 的既有行为。
 */
abstract interface class PlayerPropertyBatchBoundary {
  /**
   * 按 Map 插入顺序提交完整属性快照。
   *
   * 实现必须在 Future 完成前处理完全部属性，但单个 mpv 可选属性不支持时仍应继续
   * 处理剩余项，避免半套画质或同步配置阻断媒体打开。
   */
  Future<void> setProperties(Map<String, String> properties);
}

/**
 * 在同一个播放器实例上提交滤镜快照，并在读回不一致时恢复旧值的可选边界。
 *
 * 该边界不拥有 Player 或 NativePlayer；实现只能使用当前 [PlayerRuntimeAccess]，
 * 禁止为诊断、验证或回滚创建第二条播放/解码链。
 */
abstract interface class PlayerFilterTransactionBoundary {
  /** 最近一次滤镜事务的路径无关诊断快照。 */
  PlayerFilterTransactionSnapshot get filterTransaction;

  /**
   * 提交并验证一组完整滤镜属性。
   *
   * [label] 必须是代码内固定用途标签；[properties] 的值不进入诊断快照。
   */
  Future<PlayerFilterTransactionSnapshot> applyFilterProperties({
    required String label,
    required Map<String, String> properties,
  });
}

/**
 * 后端可选的结构化播放遥测边界。
 *
 * 不支持该边界的 PlayerBackend 仍可正常播放；PlayerService 会返回显式 unsupported
 * 快照。事件与快照不得包含本地媒体路径，连续切换通过打开代次关联。
 */
abstract interface class PlayerBackendTelemetryBoundary {
  /** 当前后端实例的最新遥测快照。 */
  PlayerBackendTelemetrySnapshot get telemetry;

  /** 首帧、解码器、错误和释放阶段变化流。 */
  Stream<PlayerBackendTelemetryEvent> get telemetryChanges;
}

/**
 * 后端可选的视频表面尺寸与 Flutter 采样诊断边界。
 *
 * 该边界只暴露匿名尺寸、DPR 与采样档位，不泄漏 Texture ID、原生句柄或媒体路径，
 * 也不得因读取快照触发纹理重建。
 */
abstract interface class PlayerVideoSurfaceDiagnosticsBoundary {
  /** 当前视频表面的最近一次只读采样快照。 */
  PlayerVideoSurfaceDiagnostics get videoSurfaceDiagnostics;
}

/**
 * 为进度条点击和连续快进提供关键帧优先随机跳转的可选后端边界。
 *
 * 交互式跳转只负责尽快显示目标附近关键帧；页面根据交互类型决定是否再通过普通
 * seek 精确收敛。连续鼠标点击和键盘预览可只保留 latest-only 关键帧目标，继续观看
 * 等精确入口仍显式提交普通 seek。
 * 不支持该边界的后端由 [PlayerService] 安全回退到普通 seek，页面不得感知 mpv 参数。
 */
abstract interface class PlayerInteractiveSeekBoundary {
  /** 显示 [position] 附近关键帧，并保持后端原有播放/暂停意图。 */
  Future<void> seekInteractive(Duration position);
}

/**
 * 当前媒体的轨道、章节与音画同步控制。
 *
 * 此边界是可选的：没有 libmpv/MediaKit 支持的测试或 QA 后端必须返回 unsupported，
 * 不得把音轨、字幕或章节塞进通用 [PlayerBackendState]，更不能改变来源 filtered queue。
 */
abstract interface class PlayerMediaControlsBoundary {
  Future<PlayerMediaControlsSnapshot> readMediaControls();

  Future<void> selectAudioTrack(String trackId);

  Future<void> selectSubtitleTrack(String trackId);

  Future<void> toggleSubtitle();

  Future<void> adjustSubtitleDelay(Duration delta);

  Future<void> adjustAudioDelay(Duration delta);

  Future<void> seekChapter(int chapterIndex);
}

/**
 * 播放运行时后端契约。
 *
 * 它只描述打开、控制、状态事件和底层运行时属性；不要求实现知道 Flutter 如何
 * 挂载视频表面。兼容后端可以继续实现下面的聚合接口，不改变现有平台行为。
 */
abstract interface class PlayerRuntimeBackend implements PlayerRuntimeAccess {
  /** 播放位置变化流。 */
  Stream<Duration> get positionChanges;

  /** 播放/暂停状态变化流。 */
  Stream<bool> get playingChanges;

  /** 媒体播放完成事件流。 */
  Stream<bool> get completedChanges;

  /** 原生播放错误流，内容不得包含本地媒体路径。 */
  Stream<String> get errorChanges;

  /** 打开一个媒体路径；filtered queue 的选择仍由页面层负责。 */
  Future<void> openPath(String path);

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> seek(Duration position);

  Future<void> setRate(double rate);

  Future<void> setVolume(double volume);

  Future<void> playOrPause();

  /** 截取当前视频帧，编码格式由调用方指定。 */
  Future<Uint8List?> screenshot({String format = 'image/jpeg'});

  Future<void> dispose();

  /** 等待后端拥有的 Player、纹理与原生资源全部释放。 */
  Future<void> get released;
}

/** Flutter 视频表面渲染契约；不得创建第二个 Player 或解码链。 */
abstract interface class PlayerSurfaceRenderer {
  /**
   * 构建视频纹理表面；具体 Player/纹理控制器不得泄漏给页面。
   *
   * [fit] 控制完整显示或等比裁边，[aspectRatio] 仅在用户显式选择 4:3 / 16:9
   * 时覆盖媒体宽高比；[mirror] 只水平翻转视频纹理，不能影响上层控制条。
   * [reserveTopControlArea] / [reserveBottomControlArea] 表示对应边缘存在必须
   * 显示在原生视频之上的 Flutter 控制区；普通纹理后端可忽略，存在原生 airspace
   * 的后端必须用窗口区域裁剪让位，不能通过永久缩小视频视口制造黑边。
   */
  Widget buildVideoSurface({
    required Widget controls,
    BoxFit fit = BoxFit.contain,
    double? aspectRatio,
    bool mirror = false,
    bool reserveTopControlArea = false,
    bool reserveBottomControlArea = false,
  });
}

/** 当前平台后端的运行时与表面兼容聚合契约。 */
abstract interface class PlayerBackend
    implements PlayerRuntimeBackend, PlayerSurfaceRenderer {}

/**
 * 可返回实际渲染设备证据和显式 Compute 基线的 Windows 播放边界。
 *
 * 基线属于 QA/实验动作，普通播放启动不得自动运行高负载 Compute 压测。
 */
abstract interface class PlayerGpuRenderBoundary {
  Future<PlayerGpuActiveAdapter> queryActiveGpuAdapter();

  Future<PlayerGpuComputeFrameBudget> benchmarkGpuComputeFrameBudget(
    String adapterLuid,
  );
}

/**
 * 仅由 Windows 原生 child HWND/D3D11 QA 后端实现的 NVIDIA 实验边界。
 *
 * MediaKit Texture 与普通原生纹理后端不得实现该接口，避免正式播放误发
 * `d3d11vpp scaling-mode=nvidia` 探测或请求。
 */
abstract interface class PlayerNativeNvidiaVideoEnhancementBoundary {
  /** 当前后端是否拥有经过隔离门禁的原生 D3D11 输出链。 */
  bool get supportsNativeNvidiaVideoEnhancement;
}

/**
 * 需要在 Flutter 弹层显示期间让出原生视频 airspace 的可选边界。
 *
 * 普通纹理后端无需实现；child HWND 等始终位于 Flutter 合成层之上的后端通过该
 * 边界在弹层出现前隐藏原生表面，并在最后一层弹层关闭后恢复。
 */
abstract interface class PlayerOverlaySurfaceBoundary {
  /**
   * 同步 Flutter 是否正在显示可能与原生视频表面重叠的弹层。
   *
   * [visible] 为 true 时原生后端必须先完成让出，再允许调用方挂载弹层。
   * [overlayRect] 与 [viewSize] 同时存在时，只裁剪弹层实际覆盖的逻辑区域；
   * 未提供矩形的模态弹窗仍可要求原生表面完整让出。
   */
  Future<void> setFlutterOverlayVisible(
    bool visible, {
    Rect? overlayRect,
    Size? viewSize,
  });
}

/**
 * Windows 原生播放器可选的运动补偿插帧边界。
 *
 * MediaKit 等后端无需伪造实现；PlayerService 会返回明确 unsupported 快照。
 * 路径、DLL 与第三方 SDK 句柄必须留在平台实现内部。
 */
abstract interface class PlayerMotionInterpolationBoundary {
  /** 查询本机运行时、脚本和当前会话的实际状态。 */
  Future<PlayerMotionInterpolationCapability>
      queryMotionInterpolationCapability();

  /**
   * 改变当前会话的插帧意图并读回结果。
   *
   * [enabled] 为 false 时必须只移除本边界拥有的滤镜条目。
   */
  Future<PlayerMotionInterpolationApplyResult> setMotionInterpolationEnabled(
    bool enabled,
  );
}

/**
 * 根据用户硬解设置创建独占播放会话后端。
 *
 * 默认工厂返回 media_kit 适配器；后续 Windows C++ 实现可在组合根切换，
 * PlayerPage 不需要感知具体后端类型。
 */
typedef PlayerBackendFactory = PlayerBackend Function({
  required String hwdec,
  required bool enableHardwareAcceleration,
});

/**
 * PlayerBackend 暴露给 Flutter UI 的不可变状态快照。
 *
 * 仅保留渲染与交互需要的轻量字段，避免未来原生后端高频跨边界传递复杂对象。
 */
class PlayerBackendState {
  const PlayerBackendState({
    required this.position,
    required this.duration,
    required this.playing,
    required this.buffering,
    required this.volume,
    required this.videoTrackCount,
    required this.audioTrackCount,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final double volume;
  final int videoTrackCount;
  final int audioTrackCount;
}

abstract interface class FFmpegBackend {
  Future<ExternalMediaToolsState> locateTools();

  Future<bool> isAvailable();

  Future<String?> version();

  Future<File?> createThumbnail({
    required VideoItem item,
    required File output,
    bool allowFallback,
  });

  /**
   * 在不扰动主播放器位置的前提下提取指定时间点预览帧。
   *
   * 实现必须限制自身线程与输出尺寸；失败返回 null 或抛出可诊断异常，UI 不得直连进程。
   */
  Future<File?> createFramePreview({
    required VideoItem item,
    required File output,
    required Duration position,
  });

  Future<MediaDetails?> probe(VideoItem item);
}

/**
 * 媒体信息批处理平台边界。
 *
 * 原生实现只负责读取文件与生成紧凑结果；SQLite 写入仍由 Dart Repository 串行完成，
 * 避免双端数据库连接引入锁与迁移风险。
 */
abstract interface class MediaProbeBackend {
  /** 批量探测同一代请求；实现必须限制并发并保留输入顺序。 */
  Future<List<MediaProbeResult>> probeBatch({
    required int generationId,
    required List<MediaProbeRequest> requests,
  });

  /** 取消指定代的排队与执行中任务，旧结果不得继续写回。 */
  Future<void> cancelGeneration(int generationId);
}

/** 创建独立媒体探测会话后端的组合根工厂。 */
typedef MediaProbeBackendFactory = MediaProbeBackend Function();
