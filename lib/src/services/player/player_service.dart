import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/playback_settings.dart';
import '../../models/player_backend_telemetry.dart';
import '../../models/player_filter_transaction.dart';
import '../../models/player_gpu_capabilities.dart';
import '../../models/player_motion_interpolation_capability.dart';
import '../../models/player_feature_apply_result.dart';
import '../../models/player_video_surface_diagnostics.dart';
import '../../platform/platform_interfaces.dart';
import 'player_hdr_mapping_experiment.dart';
import 'player_smooth_motion.dart';
import 'player_video_super_resolution.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * Flutter 播放器页面唯一依赖的 PlayerFacade。
 *
 * 服务独占一个 [PlayerBackend]，常规命令由 MediaKit 公共 API 完成，高级画质
 * 通过后端持有的同一个 NativePlayer 提交；页面只消费统一状态、命令和视频表面。
 * 底层属性访问不能由此泄漏具体 Player、mpv handle、D3D11 纹理或 HWND。
 */
class PlayerService
    implements
        PlayerRuntimeAccess,
        PlayerBackendTelemetryBoundary,
        PlayerVideoSurfaceDiagnosticsBoundary,
        PlayerFilterTransactionBoundary,
        PlayerPropertyBatchBoundary,
        PlayerGpuRenderBoundary,
        PlayerOverlaySurfaceBoundary,
        PlayerMotionInterpolationBoundary {
  /** 创建一个独占单个播放 Route 生命周期的服务。 */
  PlayerService({required PlayerBackend backend}) : _backend = backend;

  /** 具体引擎只在服务内部持有，页面和业务控制器不可取得该引用。 */
  final PlayerBackend _backend;

  /**
   * 只有隔离 Windows child HWND QA 后端返回 true。
   *
   * 正式 MediaKit Texture 即使底层也是 libmpv，也不能据此宣称 NVIDIA 原生增强可用。
   */
  bool get supportsNativeNvidiaVideoEnhancement {
    final boundary = _backend is PlayerNativeNvidiaVideoEnhancementBoundary
        ? _backend as PlayerNativeNvidiaVideoEnhancementBoundary
        : null;
    return boundary?.supportsNativeNvidiaVideoEnhancement ?? false;
  }

  /** 当前服务内最近一次滤镜属性事务的只读诊断快照。 */
  PlayerFilterTransactionSnapshot _filterTransaction =
      const PlayerFilterTransactionSnapshot(
    supported: true,
    sequence: 0,
    label: 'idle',
    phase: PlayerFilterTransactionPhase.idle,
    requestedPropertyCount: 0,
    verifiedPropertyCount: 0,
    mismatchedProperties: <String>[],
    rollbackAttempted: false,
    rollbackVerified: false,
    failureCode: null,
    completedAt: null,
    totalDuration: null,
  );

  /** 当前服务内递增的匿名滤镜事务序号。 */
  var _filterTransactionSequence = 0;

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

  /**
   * 返回后端结构化遥测；普通测试后端和未实现平台使用显式 unsupported 快照。
   */
  @override
  PlayerBackendTelemetrySnapshot get telemetry {
    final boundary = _backend is PlayerBackendTelemetryBoundary
        ? _backend as PlayerBackendTelemetryBoundary
        : null;
    return boundary?.telemetry ??
        const PlayerBackendTelemetrySnapshot.unsupported();
  }

  /** 转发可选后端遥测事件；未实现后端使用空流，不改变播放行为。 */
  @override
  Stream<PlayerBackendTelemetryEvent> get telemetryChanges {
    final boundary = _backend is PlayerBackendTelemetryBoundary
        ? _backend as PlayerBackendTelemetryBoundary
        : null;
    return boundary?.telemetryChanges ??
        const Stream<PlayerBackendTelemetryEvent>.empty();
  }

  /**
   * 返回后端最近一次视频表面尺寸快照。
   *
   * 不支持的测试或平台后端返回显式 unsupported，不扩大通用 PlayerBackend contract。
   */
  @override
  PlayerVideoSurfaceDiagnostics get videoSurfaceDiagnostics {
    final boundary = _backend is PlayerVideoSurfaceDiagnosticsBoundary
        ? _backend as PlayerVideoSurfaceDiagnosticsBoundary
        : null;
    return boundary?.videoSurfaceDiagnostics ??
        const PlayerVideoSurfaceDiagnostics.unsupported();
  }

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

  /**
   * 执行用户进度条或连续按键触发的低延迟随机跳转。
   *
   * 支持交互式边界的后端只落到目标附近关键帧；调用方在交互结束时通过 [seek]
   * 精确收敛最终目标。其它后端复用精确 seek，不扩大通用 [PlayerBackend] 契约。
   */
  Future<void> seekInteractive(Duration position) {
    final boundary = _backend is PlayerInteractiveSeekBoundary
        ? _backend as PlayerInteractiveSeekBoundary
        : null;
    return boundary?.seekInteractive(position) ?? _backend.seek(position);
  }

  /** 设置当前会话倍速。 */
  Future<void> setRate(double rate) => _backend.setRate(rate);

  /** 设置当前会话音量。 */
  Future<void> setVolume(double volume) => _backend.setVolume(volume);

  /** 在播放与暂停之间切换。 */
  Future<void> playOrPause() => _backend.playOrPause();

  @override
  Future<void> setProperty(String property, String value) =>
      _backend.setProperty(property, value);

  /**
   * 优先使用后端批量边界；普通后端保持原有逐项写入顺序。
   *
   * 该分派只优化属性传输，不改变 PlayerBackend、filtered queue 或媒体生命周期。
   */
  @override
  Future<void> setProperties(Map<String, String> properties) async {
    final batchBoundary = _backend is PlayerPropertyBatchBoundary
        ? _backend as PlayerPropertyBatchBoundary
        : null;
    if (batchBoundary != null) {
      await batchBoundary.setProperties(properties);
      return;
    }
    for (final entry in properties.entries) {
      await _backend.setProperty(entry.key, entry.value);
    }
  }

  @override
  PlayerFilterTransactionSnapshot get filterTransaction => _filterTransaction;

  /**
   * 在当前后端实例上完成滤镜写前快照、提交、读回验证与失败回滚。
   *
   * 该方法只调用 [_backend]，不会创建第二个 Player、NativePlayer 或 Texture。
   * `deband` 回滚时先关闭主开关，恢复其它参数与 `vf` 后再恢复旧开关，避免短暂运行
   * 半套去色带参数。
   */
  @override
  Future<PlayerFilterTransactionSnapshot> applyFilterProperties({
    required String label,
    required Map<String, String> properties,
  }) async {
    final sequence = ++_filterTransactionSequence;
    final watch = Stopwatch()..start();
    final previousValues = <String, String>{};
    final unavailablePrevious = <String>[];
    for (final property in properties.keys) {
      final value = _normalizePropertyReadback(
        await _backend.getProperty(property),
      );
      if (value == null) {
        unavailablePrevious.add(property);
      } else {
        previousValues[property] = value;
      }
    }

    var failureCode = 'filter_readback_mismatch';
    var writeFailed = false;
    try {
      await setProperties(properties);
    } catch (_) {
      writeFailed = true;
      failureCode = 'filter_write_failed';
    }
    final mismatches = writeFailed
        ? properties.keys.toList(growable: false)
        : await _mismatchedProperties(properties);
    if (mismatches.isEmpty) {
      watch.stop();
      return _filterTransaction = PlayerFilterTransactionSnapshot(
        supported: true,
        sequence: sequence,
        label: label,
        phase: PlayerFilterTransactionPhase.applied,
        requestedPropertyCount: properties.length,
        verifiedPropertyCount: properties.length,
        mismatchedProperties: const <String>[],
        rollbackAttempted: false,
        rollbackVerified: false,
        failureCode: null,
        completedAt: DateTime.now(),
        totalDuration: watch.elapsed,
      );
    }

    var rollbackWriteFailed = false;
    try {
      await _restoreFilterProperties(previousValues);
    } catch (_) {
      rollbackWriteFailed = true;
    }
    final rollbackMismatches = rollbackWriteFailed
        ? previousValues.keys.toList(growable: false)
        : await _mismatchedProperties(previousValues);
    final rollbackVerified =
        unavailablePrevious.isEmpty && rollbackMismatches.isEmpty;
    if (unavailablePrevious.isNotEmpty) {
      failureCode = '${failureCode}_snapshot_incomplete';
    } else if (!rollbackVerified) {
      failureCode = '${failureCode}_rollback_failed';
    }
    watch.stop();
    return _filterTransaction = PlayerFilterTransactionSnapshot(
      supported: true,
      sequence: sequence,
      label: label,
      phase: rollbackVerified
          ? PlayerFilterTransactionPhase.rolledBack
          : PlayerFilterTransactionPhase.rollbackFailed,
      requestedPropertyCount: properties.length,
      verifiedPropertyCount: properties.length - mismatches.length,
      mismatchedProperties: List<String>.unmodifiable(mismatches),
      rollbackAttempted: true,
      rollbackVerified: rollbackVerified,
      failureCode: failureCode,
      completedAt: DateTime.now(),
      totalDuration: watch.elapsed,
    );
  }

  /** 把 PlayerBackend 的占位读回转换为可安全写回的真实空值。 */
  String? _normalizePropertyReadback(String value) {
    final normalized = value.trim();
    if (normalized == 'unavailable') {
      return null;
    }
    return normalized == 'empty' ? '' : normalized;
  }

  /**
   * 返回与目标快照不一致的属性名，不把属性值带入诊断。
   *
   * libmpv 的属性写入完成早于观察事件回送，Windows 原生后端可能在批量提交后的
   * 首次读回仍暴露旧快照。这里只对实际不一致项提供最多 200ms 的有界收敛窗口；
   * 首次一致时没有额外等待，持续不一致仍进入原有回滚，不能把旧值冒充成功。
   */
  Future<List<String>> _mismatchedProperties(
    Map<String, String> expected,
  ) async {
    const maximumAttempts = 5;
    for (var attempt = 0; attempt < maximumAttempts; attempt++) {
      final mismatches = <String>[];
      for (final entry in expected.entries) {
        final actual = _normalizePropertyReadback(
          await _backend.getProperty(entry.key),
        );
        if (!_propertyValuesMatch(entry.key, entry.value.trim(), actual)) {
          mismatches.add(entry.key);
        }
      }
      if (mismatches.isEmpty || attempt == maximumAttempts - 1) {
        return mismatches;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return const <String>[];
  }

  /**
   * 按 mpv 的规范化读回语义比较属性。
   *
   * 数值属性可能补齐六位小数；`lavfi=[graph]` 会读回为带长度前缀的
   * `lavfi=graph=%N%graph`。这里只做等价归一化，不放宽滤镜节点或参数内容。
   */
  bool _propertyValuesMatch(
    String property,
    String expected,
    String? actual,
  ) {
    if (actual == null) {
      return false;
    }
    if (property == 'vf') {
      return _normalizeVideoFilterValue(expected) ==
          _normalizeVideoFilterValue(actual);
    }
    final expectedNumber = double.tryParse(expected);
    final actualNumber = double.tryParse(actual);
    if (expectedNumber != null && actualNumber != null) {
      return (expectedNumber - actualNumber).abs() < 0.000001;
    }
    return expected == actual;
  }

  /** 把 libmpv 的 lavfi 长度前缀读回恢复为调用方提交的方括号形式。 */
  String _normalizeVideoFilterValue(String value) {
    if (value.startsWith('lavfi=[') && value.endsWith(']')) {
      return value.substring(7, value.length - 1);
    }
    final match = RegExp(r'^lavfi=graph=%\d+%(.*)$').firstMatch(value);
    return match?.group(1) ?? value;
  }

  /** 以去色带主开关最后恢复的顺序写回旧滤镜快照。 */
  Future<void> _restoreFilterProperties(
    Map<String, String> previousValues,
  ) async {
    final previousDeband = previousValues['deband'];
    if (previousDeband != null) {
      await setProperties(const <String, String>{'deband': 'no'});
    }
    final body = <String, String>{
      for (final entry in previousValues.entries)
        if (entry.key != 'deband') entry.key: entry.value,
    };
    if (body.isNotEmpty) {
      await setProperties(body);
    }
    if (previousDeband != null) {
      await setProperties(<String, String>{'deband': previousDeband});
    }
  }

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
  Future<PlayerOpenPreferencesApplyResult> applyOpenPreferences({
    required String videoAspectOverride,
    required String panscan,
    required PlayerVideoScaler videoScaler,
    required PlayerVideoOutputRange videoOutputRange,
    required double playbackRate,
    required bool videoSuperResolutionEnabled,
    PlayerSmoothMotionMode smoothMotionMode = PlayerSmoothMotionMode.off,
    bool hdrDynamicToneMappingExperimentEnabled = false,
  }) async {
    try {
      // 比例、平移与输出电平必须作为同一快照提交，避免打开阶段逐项平台往返。
      await setProperties(<String, String>{
        'video-aspect-override': videoAspectOverride,
        'panscan': panscan,
        // 清除历史缩放和平移，防止它们叠加到新的全局比例模式。
        'video-zoom': '0',
        'video-pan-x': '0',
        'video-pan-y': '0',
        'video-output-levels': switch (videoOutputRange) {
          PlayerVideoOutputRange.automatic => 'auto',
          PlayerVideoOutputRange.limited => 'limited',
          PlayerVideoOutputRange.full => 'full',
        },
      });
    } catch (_) {
      // 比例属性属于可选能力，不能因为后端不支持而阻止媒体打开。
    }
    final scalingResult = await PlayerVideoSuperResolution.apply(
      backend: this,
      enabled: videoSuperResolutionEnabled,
      baseScaler: videoScaler,
    );
    final hdrResult = await PlayerHdrMappingExperiment.apply(
      backend: this,
      enabled: hdrDynamicToneMappingExperimentEnabled,
    );
    await setRate(playbackRate);
    final smoothMotionResult = await applySmoothMotion(smoothMotionMode);
    return PlayerOpenPreferencesApplyResult(
      scaling: scalingResult,
      hdrToneMapping: hdrResult,
      smoothMotion: smoothMotionResult,
    );
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
    bool reserveBottomControlArea = false,
  }) =>
      _backend.buildVideoSurface(
        controls: controls,
        fit: fit,
        aspectRatio: aspectRatio,
        mirror: mirror,
        reserveTopControlArea: reserveTopControlArea,
        reserveBottomControlArea: reserveBottomControlArea,
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
 * 一次媒体级显示偏好恢复的可验证结果。
 *
 * 页面用它区分持久设置请求与当前会话实际状态，不能再仅凭开关显示“已启用”。
 */
class PlayerOpenPreferencesApplyResult {
  const PlayerOpenPreferencesApplyResult({
    required this.scaling,
    required this.hdrToneMapping,
    required this.smoothMotion,
  });

  /** GPU 缩放属性的读回结果。 */
  final PlayerFeatureApplyResult scaling;

  /** HDR 转 SDR 色调映射属性的读回结果。 */
  final PlayerFeatureApplyResult hdrToneMapping;

  /** 显示同步插值的既有类型化结果。 */
  final PlayerSmoothMotionApplyResult smoothMotion;
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
