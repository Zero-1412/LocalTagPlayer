import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/playback_settings.dart';
import '../../models/player_gpu_capabilities.dart';
import '../../models/player_motion_interpolation_capability.dart';
import '../../platform/platform_interfaces.dart';
import 'player_hdr_mapping_experiment.dart';
import 'player_smooth_motion.dart';
import 'player_video_super_resolution.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * Flutter 播放器页面唯一依赖的应用层播放服务。
 *
 * 服务独占一个 [PlayerBackend]，把 MediaKit 与 Windows libmpv 的选择留在组合根；
 * 页面只消费统一状态、命令和视频表面。底层属性访问仅供既有画质协调器与诊断逐步
 * 迁移，不能由此泄漏具体 Player、mpv handle、D3D11 纹理或 HWND。
 */
class PlayerService
    implements
        PlayerRuntimeAccess,
        PlayerGpuRenderBoundary,
        PlayerOverlaySurfaceBoundary,
        PlayerMotionInterpolationBoundary {
  /** 创建一个独占单个播放 Route 生命周期的服务。 */
  PlayerService({required PlayerBackend backend}) : _backend = backend;

  /** 具体引擎只在服务内部持有，页面和业务控制器不可取得该引用。 */
  final PlayerBackend _backend;

  @override
  PlayerBackendState get state => _backend.state;

  /** 播放位置变化流。 */
  Stream<Duration> get positionChanges => _backend.positionChanges;

  /** 播放/暂停状态变化流。 */
  Stream<bool> get playingChanges => _backend.playingChanges;

  /** 媒体播放完成事件流。 */
  Stream<bool> get completedChanges => _backend.completedChanges;

  /** 不包含本地路径的播放错误流。 */
  Stream<String> get errorChanges => _backend.errorChanges;

  @override
  ValueListenable<int?> get textureId => _backend.textureId;

  /** 打开当前 filtered queue 选中的本地媒体。 */
  Future<void> openPath(String path) => _backend.openPath(path);

  /** 开始或继续播放。 */
  Future<void> play() => _backend.play();

  /** 暂停播放并保留当前帧。 */
  Future<void> pause() => _backend.pause();

  /** 停止当前媒体。 */
  Future<void> stop() => _backend.stop();

  /** 跳转到指定媒体位置。 */
  Future<void> seek(Duration position) => _backend.seek(position);

  /** 设置当前会话倍速。 */
  Future<void> setRate(double rate) => _backend.setRate(rate);

  /** 设置当前会话音量。 */
  Future<void> setVolume(double volume) => _backend.setVolume(volume);

  /** 在播放与暂停之间切换。 */
  Future<void> playOrPause() => _backend.playOrPause();

  @override
  Future<void> setProperty(String property, String value) =>
      _backend.setProperty(property, value);

  @override
  Future<String> getProperty(String property) => _backend.getProperty(property);

  @override
  Future<PlayerGpuCapabilityMatrix> queryGpuCapabilities() =>
      _backend.queryGpuCapabilities();

  /**
   * 应用每次 open 前后都必须恢复的类型化播放偏好。
   *
   * [videoAspectOverride] 与 [panscan] 由平台无关的画面比例模型计算；服务负责把
   * 它们与缩放、输出范围、HDR 和倍速按稳定顺序送入当前引擎。
   */
  Future<PlayerSmoothMotionApplyResult> applyOpenPreferences({
    required String videoAspectOverride,
    required String panscan,
    required PlayerVideoScaler videoScaler,
    required PlayerVideoOutputRange videoOutputRange,
    required double playbackRate,
    required bool videoSuperResolutionEnabled,
    PlayerSmoothMotionMode smoothMotionMode = PlayerSmoothMotionMode.off,
    bool hdrDynamicToneMappingExperimentEnabled = false,
  }) async {
    /** 单个可选属性失败时继续应用其余偏好，兼容能力较少的后端。 */
    Future<void> setPropertySafely(String property, String value) async {
      try {
        await setProperty(property, value);
      } catch (_) {
        // 比例属性属于可选能力，不能因为后端不支持而阻止媒体打开。
      }
    }

    await setPropertySafely('video-aspect-override', videoAspectOverride);
    await setPropertySafely('panscan', panscan);
    // 清除历史缩放和平移，防止它们叠加到新的全局比例模式。
    await setPropertySafely('video-zoom', '0');
    await setPropertySafely('video-pan-x', '0');
    await setPropertySafely('video-pan-y', '0');
    await setPropertySafely(
      'video-output-levels',
      switch (videoOutputRange) {
        PlayerVideoOutputRange.automatic => 'auto',
        PlayerVideoOutputRange.limited => 'limited',
        PlayerVideoOutputRange.full => 'full',
      },
    );
    await PlayerVideoSuperResolution.apply(
      backend: this,
      enabled: videoSuperResolutionEnabled,
      baseScaler: videoScaler,
    );
    await PlayerHdrMappingExperiment.apply(
      backend: this,
      enabled: hdrDynamicToneMappingExperimentEnabled,
    );
    await setRate(playbackRate);
    return applySmoothMotion(smoothMotionMode);
  }

  /**
   * 应用类型化的显示同步插值意图。
   *
   * 页面不接触 `video-sync`、`interpolation` 或 `tscale` 字符串；后端缺少能力
   * 时由统一协调器回退并返回可诊断结果。
   */
  Future<PlayerSmoothMotionApplyResult> applySmoothMotion(
    PlayerSmoothMotionMode mode,
  ) =>
      PlayerSmoothMotion.apply(backend: this, mode: mode);

  /** 截取当前视频帧；失败语义由具体后端保持不变。 */
  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) =>
      _backend.screenshot(format: format);

  /**
   * 构建当前后端的视频表面。
   *
   * MediaKit Texture、Windows 原生 Texture 与 child HWND 的实现差异全部留在
   * 后端；Flutter 页面只提供控制层及平台无关的 fit、比例、镜像与顶部控制区
   * 避让意图。
   */
  Widget buildVideoSurface({
    required Widget controls,
    BoxFit fit = BoxFit.contain,
    double? aspectRatio,
    bool mirror = false,
    bool reserveTopControlArea = false,
  }) =>
      _backend.buildVideoSurface(
        controls: controls,
        fit: fit,
        aspectRatio: aspectRatio,
        mirror: mirror,
        reserveTopControlArea: reserveTopControlArea,
      );

  @override
  Future<PlayerGpuActiveAdapter> queryActiveGpuAdapter() {
    final boundary = _backend is PlayerGpuRenderBoundary
        ? _backend as PlayerGpuRenderBoundary
        : null;
    return boundary?.queryActiveGpuAdapter() ??
        Future<PlayerGpuActiveAdapter>.value(
          const PlayerGpuActiveAdapter.unsupported(),
        );
  }

  @override
  Future<PlayerGpuComputeFrameBudget> benchmarkGpuComputeFrameBudget(
    String adapterLuid,
  ) {
    final boundary = _backend is PlayerGpuRenderBoundary
        ? _backend as PlayerGpuRenderBoundary
        : null;
    return boundary?.benchmarkGpuComputeFrameBudget(adapterLuid) ??
        Future<PlayerGpuComputeFrameBudget>.value(
          PlayerGpuComputeFrameBudget(
            probeStatus: 'unsupported',
            adapterLuid: adapterLuid,
            detectionSource: 'player-service',
            targetFrameRate: 0,
            computeSliceRatio: 0,
            samples: const <PlayerGpuComputeResolutionBudget>[],
            errorCode: 'backend-capability-unsupported',
          ),
        );
  }

  @override
  Future<void> setFlutterOverlayVisible(
    bool visible, {
    Rect? overlayRect,
    Size? viewSize,
  }) {
    final boundary = _backend is PlayerOverlaySurfaceBoundary
        ? _backend as PlayerOverlaySurfaceBoundary
        : null;
    return boundary?.setFlutterOverlayVisible(
          visible,
          overlayRect: overlayRect,
          viewSize: viewSize,
        ) ??
        Future<void>.value();
  }

  @override
  Future<PlayerMotionInterpolationCapability>
      queryMotionInterpolationCapability() {
    final boundary = _backend is PlayerMotionInterpolationBoundary
        ? _backend as PlayerMotionInterpolationBoundary
        : null;
    return boundary?.queryMotionInterpolationCapability() ??
        Future<PlayerMotionInterpolationCapability>.value(
          const PlayerMotionInterpolationCapability.unsupported(),
        );
  }

  @override
  Future<PlayerMotionInterpolationApplyResult> setMotionInterpolationEnabled(
    bool enabled,
  ) async {
    final boundary = _backend is PlayerMotionInterpolationBoundary
        ? _backend as PlayerMotionInterpolationBoundary
        : null;
    if (boundary == null) {
      return const PlayerMotionInterpolationApplyResult(
        applied: false,
        capability: PlayerMotionInterpolationCapability.unsupported(),
      );
    }
    return boundary.setMotionInterpolationEnabled(enabled);
  }

  /** 释放服务独占的引擎、视频表面和原生资源。 */
  Future<void> dispose() => _backend.dispose();

  /** 等待底层 Player、纹理、D3D11/HWND 资源完成释放。 */
  Future<void> get released => _backend.released;
}

/**
 * 根据用户硬解设置创建独占播放 Route 服务。
 *
 * 具体 MediaKit/Windows libmpv 后端只允许在应用组合根内选择。
 */
typedef PlayerServiceFactory = PlayerService Function({
  required String hwdec,
  required bool enableHardwareAcceleration,
  required PlayerRendererPreference rendererPreference,
});
