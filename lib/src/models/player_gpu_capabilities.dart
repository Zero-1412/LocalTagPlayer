// ignore_for_file: slash_for_doc_comments

/** 当前 DXGI 桌面输出的真实色彩空间与亮度快照。 */
class PlayerGpuDisplayOutput {
  const PlayerGpuDisplayOutput({
    required this.deviceName,
    required this.attachedToDesktop,
    required this.desktopLeft,
    required this.desktopTop,
    required this.desktopWidth,
    required this.desktopHeight,
    required this.bitsPerColor,
    required this.colorSpace,
    required this.hdrSignalActive,
    required this.minLuminanceNits,
    required this.maxLuminanceNits,
    required this.maxFullFrameLuminanceNits,
  });

  final String deviceName;
  final bool attachedToDesktop;
  final int desktopLeft;
  final int desktopTop;
  final int desktopWidth;
  final int desktopHeight;
  final int? bitsPerColor;
  final String? colorSpace;
  final bool hdrSignalActive;
  final double? minLuminanceNits;
  final double? maxLuminanceNits;
  final double? maxFullFrameLuminanceNits;

  factory PlayerGpuDisplayOutput.fromPlatformMap(
    Map<Object?, Object?> value,
  ) =>
      PlayerGpuDisplayOutput(
        deviceName: _string(value['deviceName']),
        attachedToDesktop: value['attachedToDesktop'] == true,
        desktopLeft: _int(value['desktopLeft']),
        desktopTop: _int(value['desktopTop']),
        desktopWidth: _int(value['desktopWidth']),
        desktopHeight: _int(value['desktopHeight']),
        bitsPerColor: _nullableInt(value['bitsPerColor']),
        colorSpace: _nullableString(value['colorSpace']),
        hdrSignalActive: value['hdrSignalActive'] == true,
        minLuminanceNits: _nullableDouble(value['minLuminanceNits']),
        maxLuminanceNits: _nullableDouble(value['maxLuminanceNits']),
        maxFullFrameLuminanceNits:
            _nullableDouble(value['maxFullFrameLuminanceNits']),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'deviceName': deviceName,
        'attachedToDesktop': attachedToDesktop,
        'desktopLeft': desktopLeft,
        'desktopTop': desktopTop,
        'desktopWidth': desktopWidth,
        'desktopHeight': desktopHeight,
        'bitsPerColor': bitsPerColor,
        'colorSpace': colorSpace,
        'hdrSignalActive': hdrSignalActive,
        'minLuminanceNits': minLuminanceNits,
        'maxLuminanceNits': maxLuminanceNits,
        'maxFullFrameLuminanceNits': maxFullFrameLuminanceNits,
      };
}

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
    this.outputs = const <PlayerGpuDisplayOutput>[],
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

  /** 当前连接在该适配器上的 DXGI 桌面输出。 */
  final List<PlayerGpuDisplayOutput> outputs;

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
        outputs: value['outputs'] is List
            ? (value['outputs']! as List)
                .whereType<Map<Object?, Object?>>()
                .map(PlayerGpuDisplayOutput.fromPlatformMap)
                .toList(growable: false)
            : const <PlayerGpuDisplayOutput>[],
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
        'outputs': outputs.map((output) => output.toJson()).toList(),
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

/** 从实际视频纹理渲染设备返回的活动适配器证据。 */
class PlayerGpuActiveAdapter {
  const PlayerGpuActiveAdapter({
    required this.probeStatus,
    required this.detectionSource,
    this.adapterLuid,
    this.errorCode,
  });

  const PlayerGpuActiveAdapter.unsupported()
      : probeStatus = 'unsupported',
        detectionSource = 'unavailable',
        adapterLuid = null,
        errorCode = null;

  /** `ready`、`unavailable`、`ambiguous` 或 `unsupported`。 */
  final String probeStatus;

  /** LUID 的所有权边界，例如 MediaKit 实际 ANGLE D3D11 设备。 */
  final String detectionSource;

  /** 当前 Windows 会话内的 DXGI LUID；离开本次会话后不得持久化复用。 */
  final String? adapterLuid;

  /** 不含驱动原始文本和本地路径的稳定错误码。 */
  final String? errorCode;

  bool get ready => probeStatus == 'ready' && adapterLuid != null;

  factory PlayerGpuActiveAdapter.fromPlatformMap(
    Map<Object?, Object?> value,
  ) =>
      PlayerGpuActiveAdapter(
        probeStatus: _string(value['probeStatus']),
        detectionSource: _string(value['detectionSource']),
        adapterLuid: _nullableString(value['adapterLuid']),
        errorCode: _nullableString(value['errorCode']),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'probeStatus': probeStatus,
        'detectionSource': detectionSource,
        'adapterLuid': adapterLuid,
        'errorCode': errorCode,
      };
}

/** 单个分辨率下的 D3D11 Compute GPU 时间戳统计。 */
class PlayerGpuComputeResolutionBudget {
  const PlayerGpuComputeResolutionBudget({
    required this.width,
    required this.height,
    required this.probeStatus,
    required this.sampleCount,
    required this.medianGpuMs,
    required this.p95GpuMs,
    required this.maxGpuMs,
    required this.frameBudgetMs,
    required this.computeSliceMs,
    required this.p95WithinComputeSlice,
    this.errorCode,
  });

  final int width;
  final int height;
  final String probeStatus;
  final int sampleCount;
  final double? medianGpuMs;
  final double? p95GpuMs;
  final double? maxGpuMs;
  final double? frameBudgetMs;
  final double? computeSliceMs;
  final bool p95WithinComputeSlice;
  final String? errorCode;

  String get resolutionLabel => '${width}x$height';

  factory PlayerGpuComputeResolutionBudget.fromPlatformMap(
    Map<Object?, Object?> value,
  ) =>
      PlayerGpuComputeResolutionBudget(
        width: _int(value['width']),
        height: _int(value['height']),
        probeStatus: _string(value['probeStatus']),
        sampleCount: _int(value['sampleCount']),
        medianGpuMs: _nullableDouble(value['medianGpuMs']),
        p95GpuMs: _nullableDouble(value['p95GpuMs']),
        maxGpuMs: _nullableDouble(value['maxGpuMs']),
        frameBudgetMs: _nullableDouble(value['frameBudgetMs']),
        computeSliceMs: _nullableDouble(value['computeSliceMs']),
        p95WithinComputeSlice: value['p95WithinComputeSlice'] == true,
        errorCode: _nullableString(value['errorCode']),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'width': width,
        'height': height,
        'probeStatus': probeStatus,
        'sampleCount': sampleCount,
        'medianGpuMs': medianGpuMs,
        'p95GpuMs': p95GpuMs,
        'maxGpuMs': maxGpuMs,
        'frameBudgetMs': frameBudgetMs,
        'computeSliceMs': computeSliceMs,
        'p95WithinComputeSlice': p95WithinComputeSlice,
        'errorCode': errorCode,
      };
}

/** 绑定一个实际活动 LUID 的 1080p/4K Compute 帧预算报告。 */
class PlayerGpuComputeFrameBudget {
  const PlayerGpuComputeFrameBudget({
    required this.probeStatus,
    required this.adapterLuid,
    required this.detectionSource,
    required this.targetFrameRate,
    required this.computeSliceRatio,
    required this.samples,
    this.errorCode,
  });

  final String probeStatus;
  final String adapterLuid;
  final String detectionSource;
  final double targetFrameRate;
  final double computeSliceRatio;
  final List<PlayerGpuComputeResolutionBudget> samples;
  final String? errorCode;

  bool get ready => probeStatus == 'ready';

  /** 两个目标分辨率都在预留切片内才允许本机进入第三阶段实验。 */
  bool get phaseThreeEligible =>
      ready &&
      samples.length == 2 &&
      samples.every((sample) => sample.p95WithinComputeSlice);

  factory PlayerGpuComputeFrameBudget.fromPlatformMap(
    Map<Object?, Object?> value,
  ) {
    final rawSamples = value['samples'];
    final samples = rawSamples is List
        ? rawSamples
            .whereType<Map<Object?, Object?>>()
            .map(PlayerGpuComputeResolutionBudget.fromPlatformMap)
            .toList(growable: false)
        : const <PlayerGpuComputeResolutionBudget>[];
    return PlayerGpuComputeFrameBudget(
      probeStatus: _string(value['probeStatus']),
      adapterLuid: _string(value['adapterLuid']),
      detectionSource: _string(value['detectionSource']),
      targetFrameRate: _double(value['targetFrameRate']),
      computeSliceRatio: _double(value['computeSliceRatio']),
      samples: samples,
      errorCode: _nullableString(value['errorCode']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'probeStatus': probeStatus,
        'adapterLuid': adapterLuid,
        'detectionSource': detectionSource,
        'targetFrameRate': targetFrameRate,
        'computeSliceRatio': computeSliceRatio,
        'errorCode': errorCode,
        'phaseThreeEligible': phaseThreeEligible,
        'samples': samples.map((sample) => sample.toJson()).toList(),
      };
}

String _string(Object? value) => value?.toString().trim() ?? '';

String? _nullableString(Object? value) {
  final text = _string(value);
  return text.isEmpty ? null : text;
}

int _int(Object? value) => value is num ? value.toInt() : 0;

int? _nullableInt(Object? value) => value is num ? value.toInt() : null;

double _double(Object? value) => value is num ? value.toDouble() : 0;

double? _nullableDouble(Object? value) =>
    value is num ? value.toDouble() : null;
