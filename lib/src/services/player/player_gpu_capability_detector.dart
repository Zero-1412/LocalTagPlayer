import '../../models/player_gpu_capabilities.dart';
import '../../platform/platform_interfaces.dart';

// ignore_for_file: slash_for_doc_comments

/** 第三阶段 GPU 能力检测快照；未知能力不能被解释为支持。 */
class PlayerGpuCapabilitySnapshot {
  const PlayerGpuCapabilitySnapshot({
    required this.outputDriver,
    required this.gpuApi,
    required this.gpuContext,
    required this.d3d11FeatureLevel,
    required this.hwdecCurrent,
    required this.capabilityMatrix,
    required this.selectedAdapter,
    required this.adapterSelectionSource,
    required this.rendererDetected,
    required this.vulkanDetected,
    required this.computeShaderVerified,
    required this.hdrSourceDetected,
  });

  final String outputDriver;
  final String gpuApi;
  final String gpuContext;
  final String d3d11FeatureLevel;
  final String hwdecCurrent;

  /** 原生平台返回的系统设备矩阵。 */
  final PlayerGpuCapabilityMatrix capabilityMatrix;

  /** 有足够证据与当前播放会话唯一匹配的适配器；多卡不明确时保持 null。 */
  final PlayerGpuAdapterCapabilities? selectedAdapter;

  /** 活动适配器判定来源，用于诊断复核而非长期持久化。 */
  final String adapterSelectionSource;

  final bool rendererDetected;
  final bool vulkanDetected;
  final bool computeShaderVerified;
  final bool hdrSourceDetected;

  /** 第三阶段功能进入实现前使用的保守总状态。 */
  String get readinessLabel {
    if (!rendererDetected) return '未检测到可验证 GPU 渲染器';
    if (!capabilityMatrix.ready) return 'GPU 渲染已检测，原生设备矩阵不可用';
    if (selectedAdapter == null) return 'GPU 设备已枚举，活动适配器尚未唯一确认';
    if (!computeShaderVerified) return '活动 GPU 已确认，Compute 能力未验证';
    return '活动 GPU 与 Compute 能力已验证';
  }
}

/**
 * 合并当前播放会话属性与 PlayerBackend 原生设备矩阵。
 *
 * 单硬件适配器可直接唯一匹配；多显卡只有 Feature Level 唯一匹配时才选择设备。
 * 枚举顺序和显卡名称都不能作为活动适配器证据，防止错误开启高负载增强。
 */
class PlayerGpuCapabilityDetector {
  const PlayerGpuCapabilityDetector();

  Future<PlayerGpuCapabilitySnapshot> detect(PlayerBackend backend) async {
    final values = <String, String>{};
    for (final property in const <String>[
      'current-vo',
      'gpu-api',
      'gpu-context',
      'd3d11-feature-level',
      'hwdec-current',
      'video-params/gamma',
    ]) {
      try {
        values[property] = await backend.getProperty(property);
      } catch (_) {
        values[property] = 'unavailable';
      }
    }

    PlayerGpuCapabilityMatrix matrix;
    try {
      matrix = await backend.queryGpuCapabilities();
    } catch (_) {
      matrix = const PlayerGpuCapabilityMatrix(
        platformSupported: false,
        probeStatus: 'failed',
        detectionSource: 'backend-query-failed',
        vulkanLoaderAvailable: false,
        vulkanInstanceAvailable: false,
        adapters: <PlayerGpuAdapterCapabilities>[],
        errorCode: 'backend-query-failed',
      );
    }

    final output = values['current-vo'] ?? 'unavailable';
    final api = values['gpu-api'] ?? 'unavailable';
    final context = values['gpu-context'] ?? 'unavailable';
    final d3d11FeatureLevel = values['d3d11-feature-level'] ?? 'unavailable';
    final combined = '$output $api $context'.toLowerCase();
    final sessionUsesGpuRenderer = _available(d3d11FeatureLevel) ||
        combined.contains('gpu') ||
        combined.contains('d3d11') ||
        combined.contains('vulkan') ||
        combined.contains('angle');
    final selection = _selectAdapter(
      matrix,
      d3d11FeatureLevel,
      sessionUsesGpuRenderer,
    );
    // 系统设备矩阵不能替代当前会话证据；只有属性确认 GPU renderer 后，才尝试
    // 把单硬件卡或唯一 Feature Level 匹配为活动适配器。
    final rendererDetected = sessionUsesGpuRenderer;
    final gamma = (values['video-params/gamma'] ?? '').toLowerCase();
    return PlayerGpuCapabilitySnapshot(
      outputDriver: output,
      gpuApi: api,
      gpuContext: context,
      d3d11FeatureLevel: d3d11FeatureLevel,
      hwdecCurrent: values['hwdec-current'] ?? 'unavailable',
      capabilityMatrix: matrix,
      selectedAdapter: selection.adapter,
      adapterSelectionSource: selection.source,
      rendererDetected: rendererDetected,
      vulkanDetected: combined.contains('vulkan') ||
          selection.adapter?.vulkanSupported == true,
      computeShaderVerified: selection.adapter?.computeShaderSupported == true,
      hdrSourceDetected: gamma.contains('pq') ||
          gamma.contains('hlg') ||
          gamma.contains('st2084'),
    );
  }

  static _AdapterSelection _selectAdapter(
    PlayerGpuCapabilityMatrix matrix,
    String sessionFeatureLevel,
    bool sessionUsesGpuRenderer,
  ) {
    if (!matrix.ready) {
      return const _AdapterSelection(null, 'matrix-unavailable');
    }
    if (!sessionUsesGpuRenderer) {
      return const _AdapterSelection(null, 'session-renderer-unverified');
    }
    final hardware = matrix.adapters
        .where((adapter) => !adapter.isSoftware)
        .toList(growable: false);
    if (hardware.length == 1) {
      return _AdapterSelection(hardware.single, 'single-hardware-adapter');
    }
    if (_available(sessionFeatureLevel)) {
      final matches = hardware
          .where(
            (adapter) => adapter.d3dFeatureLevel == sessionFeatureLevel,
          )
          .toList(growable: false);
      if (matches.length == 1) {
        return _AdapterSelection(matches.single, 'unique-feature-level-match');
      }
    }
    return const _AdapterSelection(null, 'multi-adapter-unresolved');
  }

  static bool _available(String value) =>
      value.isNotEmpty && value != 'empty' && value != 'unavailable';
}

/** 能力检测内部使用的适配器选择结果。 */
class _AdapterSelection {
  const _AdapterSelection(this.adapter, this.source);

  final PlayerGpuAdapterCapabilities? adapter;
  final String source;
}
