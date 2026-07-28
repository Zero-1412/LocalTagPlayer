import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/external_media_tools_state.dart';
import '../models/media_details.dart';
import '../models/platform_models.dart';
import '../models/player_gpu_capabilities.dart';
import '../models/player_motion_interpolation_capability.dart';
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

  /** 设置底层引擎属性；不存在的属性允许被实现安全忽略。 */
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
 * 单个播放会话的底层引擎和视频表面契约。
 *
 * 该接口只由 PlayerService 与组合根持有；PlayerPage 依赖应用层服务，避免把
 * MediaKit、libmpv 或 Windows 增强能力直接耦合进 Flutter 页面。
 */
abstract interface class PlayerBackend implements PlayerRuntimeAccess {
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

  Future<void> dispose();

  /** 等待后端拥有的 Player、纹理与原生资源全部释放。 */
  Future<void> get released;
}

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
