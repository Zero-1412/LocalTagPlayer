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
  final bool rendererDetected;
  final bool vulkanDetected;
  final bool computeShaderVerified;
  final bool hdrSourceDetected;

  /** 第三阶段功能进入实现前使用的保守总状态。 */
  String get readinessLabel {
    if (!rendererDetected) return '未检测到可验证 GPU 渲染器';
    if (!computeShaderVerified) return 'GPU 渲染已检测，Compute 能力待原生验证';
    return 'GPU 与 Compute 能力已验证';
  }
}

/**
 * 只通过 PlayerBackend 查询当前渲染会话能力。
 *
 * 检测不执行厂商命令、不扫描设备，也不根据 GPU 名称推测 Vulkan/Compute/HDR；只有
 * 后端明确返回的当前 API、上下文和源信号才记为已检测。
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
    final output = values['current-vo'] ?? 'unavailable';
    final api = values['gpu-api'] ?? 'unavailable';
    final context = values['gpu-context'] ?? 'unavailable';
    final d3d11FeatureLevel = values['d3d11-feature-level'] ?? 'unavailable';
    final combined = '$output $api $context'.toLowerCase();
    // Windows 的 libmpv 嵌入模式可能只暴露 current-vo=libmpv，但已解析出的
    // D3D11 Feature Level 仍是后端给出的明确 GPU 能力证据，不能被误判为未检测。
    final rendererDetected = _available(d3d11FeatureLevel) ||
        (combined.contains('gpu') ||
            combined.contains('d3d11') ||
            combined.contains('vulkan') ||
            combined.contains('angle'));
    final gamma = (values['video-params/gamma'] ?? '').toLowerCase();
    return PlayerGpuCapabilitySnapshot(
      outputDriver: output,
      gpuApi: api,
      gpuContext: context,
      d3d11FeatureLevel: d3d11FeatureLevel,
      hwdecCurrent: values['hwdec-current'] ?? 'unavailable',
      rendererDetected: rendererDetected,
      vulkanDetected: combined.contains('vulkan'),
      // 当前 PlayerBackend 没有 Compute Shader 能力位；必须保持 false，禁止猜测。
      computeShaderVerified: false,
      hdrSourceDetected: gamma.contains('pq') ||
          gamma.contains('hlg') ||
          gamma.contains('st2084'),
    );
  }

  static bool _available(String value) =>
      value.isNotEmpty && value != 'empty' && value != 'unavailable';
}
