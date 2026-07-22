// ignore_for_file: slash_for_doc_comments

/** 单个物理显卡适配器的只读能力快照。 */
class PlayerGpuAdapterCapabilities {
  const PlayerGpuAdapterCapabilities({
    required this.name,
    required this.luid,
    required this.vendorId,
    required this.deviceId,
    required this.enumerationIndex,
    required this.isSoftware,
    required this.dedicatedVideoMemoryBytes,
    required this.sharedSystemMemoryBytes,
    required this.localMemoryBudgetBytes,
    required this.localMemoryUsageBytes,
    required this.nonLocalMemoryBudgetBytes,
    required this.nonLocalMemoryUsageBytes,
    required this.d3dFeatureLevel,
    required this.computeShaderSupported,
    required this.vulkanSupported,
    required this.vulkanApiVersion,
    required this.vulkanDeviceName,
  });

  /** DXGI 返回的适配器名称。 */
  final String name;

  /** 当前 Windows 会话内稳定的 DXGI LUID；不得跨机器持久化。 */
  final String luid;

  /** PCI / ACPI 厂商标识。 */
  final int vendorId;

  /** PCI / ACPI 设备标识。 */
  final int deviceId;

  /** DXGI 枚举顺序，只用于矩阵展示，不代表播放器一定选择该设备。 */
  final int enumerationIndex;

  /** 是否为软件适配器。 */
  final bool isSoftware;

  /** 不与 CPU 共享的专用显存字节数。 */
  final int dedicatedVideoMemoryBytes;

  /** 允许显卡使用的共享系统内存上限。 */
  final int sharedSystemMemoryBytes;

  /** 操作系统当前分配给本进程的本地显存预算。 */
  final int? localMemoryBudgetBytes;

  /** 本进程在该适配器上的当前本地显存使用量。 */
  final int? localMemoryUsageBytes;

  /** 非本地显存预算，独显上通常对应共享系统内存。 */
  final int? nonLocalMemoryBudgetBytes;

  /** 本进程当前非本地显存使用量。 */
  final int? nonLocalMemoryUsageBytes;

  /** 为该适配器真实创建设备后获得的 D3D Feature Level。 */
  final String d3dFeatureLevel;

  /** D3D11 设备是否明确支持 Compute Shader。 */
  final bool computeShaderSupported;

  /** Vulkan loader 是否枚举到 vendor/device 匹配的物理设备。 */
  final bool vulkanSupported;

  /** 匹配物理设备报告的 Vulkan API 版本。 */
  final String? vulkanApiVersion;

  /** Vulkan 物理设备名称，仅用于核对 DXGI 匹配结果。 */
  final String? vulkanDeviceName;

  /** 从 StandardMethodCodec 的平台 Map 安全解析单个适配器。 */
  factory PlayerGpuAdapterCapabilities.fromPlatformMap(
    Map<Object?, Object?> value,
  ) =>
      PlayerGpuAdapterCapabilities(
        name: _string(value['name']),
        luid: _string(value['luid']),
        vendorId: _int(value['vendorId']),
        deviceId: _int(value['deviceId']),
        enumerationIndex: _int(value['enumerationIndex']),
        isSoftware: value['isSoftware'] == true,
        dedicatedVideoMemoryBytes: _int(value['dedicatedVideoMemoryBytes']),
        sharedSystemMemoryBytes: _int(value['sharedSystemMemoryBytes']),
        localMemoryBudgetBytes: _nullableInt(value['localMemoryBudgetBytes']),
        localMemoryUsageBytes: _nullableInt(value['localMemoryUsageBytes']),
        nonLocalMemoryBudgetBytes:
            _nullableInt(value['nonLocalMemoryBudgetBytes']),
        nonLocalMemoryUsageBytes:
            _nullableInt(value['nonLocalMemoryUsageBytes']),
        d3dFeatureLevel: _string(value['d3dFeatureLevel']),
        computeShaderSupported: value['computeShaderSupported'] == true,
        vulkanSupported: value['vulkanSupported'] == true,
        vulkanApiVersion: _nullableString(value['vulkanApiVersion']),
        vulkanDeviceName: _nullableString(value['vulkanDeviceName']),
      );

  /** 输出不含路径和用户数据的设备矩阵 JSON。 */
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'luid': luid,
        'vendorId': vendorId,
        'deviceId': deviceId,
        'enumerationIndex': enumerationIndex,
        'isSoftware': isSoftware,
        'dedicatedVideoMemoryBytes': dedicatedVideoMemoryBytes,
        'sharedSystemMemoryBytes': sharedSystemMemoryBytes,
        'localMemoryBudgetBytes': localMemoryBudgetBytes,
        'localMemoryUsageBytes': localMemoryUsageBytes,
        'nonLocalMemoryBudgetBytes': nonLocalMemoryBudgetBytes,
        'nonLocalMemoryUsageBytes': nonLocalMemoryUsageBytes,
        'd3dFeatureLevel': d3dFeatureLevel,
        'computeShaderSupported': computeShaderSupported,
        'vulkanSupported': vulkanSupported,
        'vulkanApiVersion': vulkanApiVersion,
        'vulkanDeviceName': vulkanDeviceName,
      };
}

/** PlayerBackend 返回的显卡设备矩阵；未知能力始终保持显式未知。 */
class PlayerGpuCapabilityMatrix {
  const PlayerGpuCapabilityMatrix({
    required this.platformSupported,
    required this.probeStatus,
    required this.detectionSource,
    required this.vulkanLoaderAvailable,
    required this.vulkanInstanceAvailable,
    required this.adapters,
    this.errorCode,
  });

  const PlayerGpuCapabilityMatrix.unsupported()
      : platformSupported = false,
        probeStatus = 'unsupported',
        detectionSource = 'unavailable',
        vulkanLoaderAvailable = false,
        vulkanInstanceAvailable = false,
        adapters = const <PlayerGpuAdapterCapabilities>[],
        errorCode = null;

  /** 当前平台是否实现真实设备探测。 */
  final bool platformSupported;

  /** `ready`、`probing`、`failed` 或 `unsupported`。 */
  final String probeStatus;

  /** 能力来源；Windows 当前固定为 DXGI + D3D11 + Vulkan loader。 */
  final String detectionSource;

  /** 系统是否存在可加载的 Vulkan loader。 */
  final bool vulkanLoaderAvailable;

  /** Vulkan loader 是否成功创建实例并完成物理设备枚举。 */
  final bool vulkanInstanceAvailable;

  /** 按 DXGI 顺序返回的全部适配器。 */
  final List<PlayerGpuAdapterCapabilities> adapters;

  /** 不包含本地路径或驱动原始消息的稳定错误码。 */
  final String? errorCode;

  bool get ready => probeStatus == 'ready';

  /** 从 Windows 原生通道解析完整矩阵。 */
  factory PlayerGpuCapabilityMatrix.fromPlatformMap(
    Map<Object?, Object?> value,
  ) {
    final rawAdapters = value['adapters'];
    final adapters = rawAdapters is List
        ? rawAdapters
            .whereType<Map<Object?, Object?>>()
            .map(PlayerGpuAdapterCapabilities.fromPlatformMap)
            .toList(growable: false)
        : const <PlayerGpuAdapterCapabilities>[];
    return PlayerGpuCapabilityMatrix(
      platformSupported: value['platformSupported'] == true,
      probeStatus: _string(value['probeStatus']),
      detectionSource: _string(value['detectionSource']),
      vulkanLoaderAvailable: value['vulkanLoaderAvailable'] == true,
      vulkanInstanceAvailable: value['vulkanInstanceAvailable'] == true,
      adapters: adapters,
      errorCode: _nullableString(value['errorCode']),
    );
  }

  /** 输出可由 QA 脚本保存的隐私安全矩阵。 */
  Map<String, Object?> toJson() => <String, Object?>{
        'platformSupported': platformSupported,
        'probeStatus': probeStatus,
        'detectionSource': detectionSource,
        'vulkanLoaderAvailable': vulkanLoaderAvailable,
        'vulkanInstanceAvailable': vulkanInstanceAvailable,
        'errorCode': errorCode,
        'adapters':
            adapters.map((item) => item.toJson()).toList(growable: false),
      };
}

String _string(Object? value) => value?.toString().trim() ?? '';

String? _nullableString(Object? value) {
  final text = _string(value);
  return text.isEmpty ? null : text;
}

int _int(Object? value) => value is num ? value.toInt() : 0;

int? _nullableInt(Object? value) => value is num ? value.toInt() : null;
