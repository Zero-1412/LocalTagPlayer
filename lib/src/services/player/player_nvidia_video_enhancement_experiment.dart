import 'dart:io';

import '../../platform/platform_interfaces.dart';

// ignore_for_file: slash_for_doc_comments

/** 内嵌 mpv 的 NVIDIA 驱动视频增强能力状态。 */
enum PlayerNvidiaVideoEnhancementStatus {
  probing,
  available,
  unsupportedPlatform,
  missingNvidiaScalingMode,
  unavailable,
}

/**
 * 播放器齿轮消费的 NVIDIA 驱动视频增强只读能力快照。
 *
 * 该路径使用 mpv `d3d11vpp` 的 `scaling-mode=nvidia`，不是 RTX Video SDK。
 * 版本与零拷贝解码链属于硬门禁；CPU 滤镜冲突由播放器在当前会话自动暂停。
 */
class PlayerNvidiaVideoEnhancementCapability {
  const PlayerNvidiaVideoEnhancementCapability({
    required this.status,
    required this.mpvVersion,
    required this.hasD3d11vpp,
    required this.hasNvidiaScalingMode,
    this.hasNvidiaTrueHdr = false,
    this.hwdecCurrent,
    this.currentVo,
    this.runtimeState = 'inactive',
    this.hdrRuntimeState = 'inactive',
    this.sourcePrimaries,
    this.sourceGamma,
    this.filterChainIntegrated = false,
    this.conflictingCpuFilters = false,
  });

  /** 后端属性仍在查询时使用的稳定初始状态。 */
  const PlayerNvidiaVideoEnhancementCapability.probing()
      : status = PlayerNvidiaVideoEnhancementStatus.probing,
        mpvVersion = null,
        hasD3d11vpp = false,
        hasNvidiaScalingMode = false,
        hasNvidiaTrueHdr = false,
        hwdecCurrent = null,
        currentVo = null,
        runtimeState = 'inactive',
        hdrRuntimeState = 'inactive',
        sourcePrimaries = null,
        sourceGamma = null,
        filterChainIntegrated = false,
        conflictingCpuFilters = false;

  /** 当前能力判定结果。 */
  final PlayerNvidiaVideoEnhancementStatus status;

  /** 从实际后端读取或由项目固定依赖回退得到的 mpv 版本。 */
  final String? mpvVersion;

  /** 当前内嵌构建是否包含 D3D11 视频处理滤镜。 */
  final bool hasD3d11vpp;

  /** 当前内嵌构建是否包含 NVIDIA 专用缩放模式。 */
  final bool hasNvidiaScalingMode;

  /** 当前固定 mpv 构建是否包含 `nvidia-true-hdr` 驱动扩展选项。 */
  final bool hasNvidiaTrueHdr;

  /** 当前媒体实际使用的硬解器；只有 `d3d11va` 代表非 copy 纹理链。 */
  final String? hwdecCurrent;

  /** 当前实际视频输出；产品开关只允许原生 `gpu-next/D3D11` child HWND。 */
  final String? currentVo;

  /**
   * 原生层根据固定 mpv 日志归一化的驱动状态。
   *
   * 只接受 `inactive/requested/active/rejected`，不携带原始日志或媒体路径。
   */
  final String runtimeState;

  /**
   * 原生层根据固定 mpv 日志归一化的 RTX Video HDR 状态。
   *
   * `ignored-source-hdr` 表示请求被安全忽略，因为源视频本身已经是 HDR。
   */
  final String hdrRuntimeState;

  /** 当前源视频的色彩原色，仅用于诊断，不单独作为 HDR 判据。 */
  final String? sourcePrimaries;

  /** 当前源视频的传递函数；PQ/HLG 才会被识别为 HDR 源。 */
  final String? sourceGamma;

  /** 多片源 A/B、掉帧与回滚验证是否已覆盖当前滤镜接入。 */
  final bool filterChainIntegrated;

  /** 压缩增强或暗场增强是否正在占用 CPU `lavfi` 滤镜链。 */
  final bool conflictingCpuFilters;

  /** 当前媒体是否真实运行在 D3D11VA 非 copy 解码链。 */
  bool get usesNonCopyD3d11 => hwdecCurrent == 'd3d11va';

  /** 当前会话是否绕过 Flutter Texture 并由 libmpv 直接拥有 D3D11 输出。 */
  bool get usesNativeD3d11Output => currentVo == 'gpu-next-d3d11-child-hwnd';

  /** VSR 与 TrueHDR 共用的 D3D11 非 copy 和产品验证门禁。 */
  bool get _passesHardwareGate =>
      status == PlayerNvidiaVideoEnhancementStatus.available &&
      filterChainIntegrated &&
      usesNonCopyD3d11 &&
      usesNativeD3d11Output;

  /** 实际写入 NVIDIA 滤镜前，CPU 滤镜必须已由播放器暂停。 */
  bool get _passesCommonGate => _passesHardwareGate && !conflictingCpuFilters;

  /** CPU 滤镜已经释放且硬门禁通过时，才允许实际写入 NVIDIA 滤镜。 */
  bool get canEnable => _passesCommonGate;

  /**
   * 用户是否可以请求 VSR。
   *
   * 压缩与暗场滤镜冲突可由播放器在当前会话自动暂停，因此不应把开关永久禁用；
   * D3D11VA、原生输出或版本缺失仍属于不可自动修复的硬门禁。
   */
  bool get canRequest => _passesHardwareGate;

  /**
   * 当前源是否明确为 HDR。
   *
   * 属性尚未就绪时返回 null，入口保持禁用，避免把未知源误送入 SDR→HDR 扩展。
   */
  bool? get sourceIsHdr {
    final gamma = sourceGamma?.toLowerCase();
    if (gamma == null) return null;
    return const <String>{'pq', 'hlg', 'st2084', 'smpte2084'}.contains(gamma);
  }

  /** TrueHDR 只允许固定实现版本、SDR 源和共同 D3D11 门禁全部通过时开启。 */
  bool get canEnableHdr =>
      _passesCommonGate && hasNvidiaTrueHdr && sourceIsHdr == false;

  /** TrueHDR 请求允许播放器先自动暂停冲突滤镜，但不猜测未知或 HDR 源。 */
  bool get canRequestHdr =>
      _passesHardwareGate && hasNvidiaTrueHdr && sourceIsHdr == false;

  /** 面向设置页的边界说明，不把驱动扩展描述成 RTX Video SDK。 */
  String get helperText {
    if (status == PlayerNvidiaVideoEnhancementStatus.probing) {
      return '正在检查内嵌 mpv 与当前纹理链';
    }
    if (status == PlayerNvidiaVideoEnhancementStatus.unsupportedPlatform) {
      return '仅支持 Windows D3D11；非 RTX Video SDK';
    }
    if (status == PlayerNvidiaVideoEnhancementStatus.missingNvidiaScalingMode) {
      return 'mpv $mpvVersion：有 d3d11vpp；无 NVIDIA scaling-mode';
    }
    if (status == PlayerNvidiaVideoEnhancementStatus.unavailable) {
      return '无法确认内嵌 mpv 能力，实验入口保持关闭';
    }
    if (!filterChainIntegrated) {
      return 'mpv $mpvVersion 支持该模式，但纹理/滤镜链尚未验证';
    }
    if (!usesNativeD3d11Output) {
      return '需使用 Windows 原生 libmpv D3D11 渲染器';
    }
    if (!usesNonCopyD3d11) {
      return '需在解码设置中选择 D3D11VA（非 copy），并重新打开视频';
    }
    if (conflictingCpuFilters) {
      return '开启时会在当前会话暂时停用压缩画质增强和暗场增强';
    }
    if (runtimeState == 'active') {
      return '驱动已启用；低码率画面放大时建议按需开启';
    }
    if (runtimeState == 'requested') {
      return '已请求 NVIDIA RTX Super Resolution，等待驱动确认';
    }
    if (runtimeState == 'rejected') {
      return 'libmpv 拒绝 NVIDIA 滤镜，已保持关闭';
    }
    return 'mpv $mpvVersion · 默认关闭，低码率画面放大时可按需开启';
  }

  /** 面向设置页的 RTX Video HDR 边界说明。 */
  String get hdrHelperText {
    if (status == PlayerNvidiaVideoEnhancementStatus.probing) {
      return '正在检查 TrueHDR、源色彩与 D3D11 纹理链';
    }
    if (status == PlayerNvidiaVideoEnhancementStatus.unsupportedPlatform) {
      return '仅支持 Windows NVIDIA D3D11 驱动扩展';
    }
    if (!hasNvidiaTrueHdr) {
      return '当前 mpv 构建不含 nvidia-true-hdr';
    }
    if (!filterChainIntegrated) {
      return 'TrueHDR 滤镜链尚未通过本机验证';
    }
    if (!usesNativeD3d11Output) {
      return '需使用 Windows 原生 libmpv D3D11 渲染器';
    }
    if (!usesNonCopyD3d11) {
      return '需使用 D3D11VA（非 copy）并重新打开视频';
    }
    if (conflictingCpuFilters) {
      return '开启时会在当前会话暂时停用压缩画质增强和暗场增强';
    }
    if (sourceIsHdr == null) {
      return '等待当前视频的 SDR/HDR 色彩信息';
    }
    if (sourceIsHdr!) {
      return '源视频已经是 HDR，驱动会安全忽略 SDR→HDR';
    }
    if (hdrRuntimeState == 'active') {
      return '驱动已启用；最终 HDR 显示还需 Windows HDR 与 10-bit 输出';
    }
    if (hdrRuntimeState == 'requested') {
      return '已请求 NVIDIA RTX Video HDR，等待驱动确认';
    }
    if (hdrRuntimeState == 'rejected') {
      return '驱动不支持或拒绝 TrueHDR，已保持关闭';
    }
    if (hdrRuntimeState == 'ignored-source-hdr') {
      return '源视频已是 HDR，本次请求未使用';
    }
    return 'SDR 源已确认；开启后仍需 Windows HDR 才能看到最终效果';
  }
}

/**
 * 检测 mpv NVIDIA 驱动视频增强路径，不改插件 ABI 或播放器属性。
 *
 * 版本必须来自当前后端实例；实际媒体打开后还必须读取 `hwdec-current`，
 * 不能用其它固定构建或用户选择的解码器名称代替真实纹理链证据。
 */
class PlayerNvidiaVideoEnhancementExperiment {
  const PlayerNvidiaVideoEnhancementExperiment._();

  /** `scaling-mode=nvidia` 首次进入 mpv 正式版本的最低版本。 */
  static const minimumNvidiaScalingModeVersion = '0.39.0';

  /**
   * 隔离候选构建完成真人、动画渐变和暗场 A/B 后设置的产品门禁。
   *
   * 该常量只证明本项目的互斥滤镜接入已验证，不代表所有 NVIDIA 驱动都会启用
   * RTX Super Resolution；最终驱动状态仍需由诊断日志和用户观感确认。
   */
  static const filterChainValidated = true;

  /** NVIDIA 视频处理滤镜占用的完整 `vf` 快照。 */
  static const filterGraph = 'd3d11vpp=scale=2:scaling-mode=nvidia:format=nv12';

  /** TrueHDR 单独启用时不强制 8-bit 格式，由 mpv 选择 X2BGR10。 */
  static const hdrFilterGraph = 'd3d11vpp=nvidia-true-hdr=yes';

  /**
   * 原子生成唯一的 NVIDIA `d3d11vpp` 滤镜。
   *
   * TrueHDR 与 VSR 联合启用时不能沿用 VSR 单独模式的 `format=nv12`，否则会
   * 覆盖 mpv 为 TrueHDR 自动选择的 10-bit 输出格式。
   */
  static String buildFilterGraph({
    required bool videoSuperResolutionEnabled,
    required bool videoHdrEnabled,
  }) {
    if (videoSuperResolutionEnabled && videoHdrEnabled) {
      return 'd3d11vpp=scale=2:scaling-mode=nvidia:nvidia-true-hdr=yes';
    }
    if (videoHdrEnabled) return hdrFilterGraph;
    if (videoSuperResolutionEnabled) return filterGraph;
    return '';
  }

  /**
   * 查询当前后端版本和实际硬解链，返回不修改播放状态的能力快照。
   *
   * [conflictingCpuFilters] 由播放器根据压缩增强和暗场增强会话状态提供。
   */
  static Future<PlayerNvidiaVideoEnhancementCapability> probe(
    PlayerRuntimeAccess backend, {
    bool? isWindows,
    bool conflictingCpuFilters = false,
    bool filterChainIntegrated = filterChainValidated,
  }) async {
    final platformSupported = isWindows ?? Platform.isWindows;
    if (!platformSupported) {
      return const PlayerNvidiaVideoEnhancementCapability(
        status: PlayerNvidiaVideoEnhancementStatus.unsupportedPlatform,
        mpvVersion: null,
        hasD3d11vpp: false,
        hasNvidiaScalingMode: false,
      );
    }
    final reportedVersion = await backend.getProperty('mpv-version');
    final reportedHwdec = await backend.getProperty('hwdec-current');
    final reportedVo = await backend.getProperty('current-vo');
    final reportedRuntimeState =
        await backend.getProperty('native-nvidia-vsr-state');
    final reportedHdrRuntimeState =
        await backend.getProperty('native-nvidia-hdr-state');
    final reportedPrimaries =
        await backend.getProperty('video-params/primaries');
    final reportedGamma = await backend.getProperty('video-params/gamma');
    // MediaKit 与原生 QA 可能打包不同 libmpv，不能用原生固定版本替当前实例声明能力。
    final version = parseVersion(reportedVersion);
    if (version == null) {
      return const PlayerNvidiaVideoEnhancementCapability(
        status: PlayerNvidiaVideoEnhancementStatus.unavailable,
        mpvVersion: null,
        hasD3d11vpp: false,
        hasNvidiaScalingMode: false,
      );
    }
    final normalizedVersion = version.join('.');
    final hasD3d11vpp = _isAtLeast(version, const <int>[0, 36, 0]);
    final hasNvidiaScalingMode = _isAtLeast(version, const <int>[0, 39, 0]);
    // 固定提交先于下一个正式版本包含 TrueHDR；未来正式版本按版本门槛识别。
    final hasNvidiaTrueHdr =
        reportedVersion.toLowerCase().contains('g48e6c35c0') ||
            _isAtLeast(version, const <int>[0, 42, 0]);
    return PlayerNvidiaVideoEnhancementCapability(
      status: hasD3d11vpp && hasNvidiaScalingMode
          ? PlayerNvidiaVideoEnhancementStatus.available
          : hasD3d11vpp
              ? PlayerNvidiaVideoEnhancementStatus.missingNvidiaScalingMode
              : PlayerNvidiaVideoEnhancementStatus.unavailable,
      mpvVersion: normalizedVersion,
      hasD3d11vpp: hasD3d11vpp,
      hasNvidiaScalingMode: hasNvidiaScalingMode,
      hasNvidiaTrueHdr: hasNvidiaTrueHdr,
      hwdecCurrent: _normalizeProperty(reportedHwdec),
      currentVo: _normalizeProperty(reportedVo),
      runtimeState: _normalizeRuntimeState(reportedRuntimeState),
      hdrRuntimeState: _normalizeRuntimeState(
        reportedHdrRuntimeState,
        allowIgnoredSourceHdr: true,
      ),
      sourcePrimaries: _normalizeProperty(reportedPrimaries),
      sourceGamma: _normalizeProperty(reportedGamma),
      filterChainIntegrated: filterChainIntegrated,
      conflictingCpuFilters: conflictingCpuFilters,
    );
  }

  /** 从 `mpv 0.41.0-...` 或 `0.39.0` 中提取可比较的三段版本号。 */
  static List<int>? parseVersion(String rawValue) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(rawValue);
    if (match == null) return null;
    return <int>[
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
  }

  /** 把平台属性中的空值统一为 null，避免把 `unavailable` 当成解码器名称。 */
  static String? _normalizeProperty(String rawValue) {
    final normalized = rawValue.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized == 'empty' ||
        normalized == 'unavailable' ||
        normalized == 'no') {
      return null;
    }
    return normalized;
  }

  /** 把原生状态限制在无路径、可稳定展示的枚举集合。 */
  static String _normalizeRuntimeState(
    String rawValue, {
    bool allowIgnoredSourceHdr = false,
  }) {
    final normalized = rawValue.trim().toLowerCase();
    final allowed = <String>{
      'inactive',
      'requested',
      'active',
      'rejected',
      if (allowIgnoredSourceHdr) 'ignored-source-hdr',
    };
    return allowed.contains(normalized) ? normalized : 'inactive';
  }

  /** 按 major/minor/patch 比较版本，忽略提交后缀。 */
  static bool _isAtLeast(List<int> actual, List<int> minimum) {
    for (var index = 0; index < minimum.length; index++) {
      if (actual[index] != minimum[index]) {
        return actual[index] > minimum[index];
      }
    }
    return true;
  }
}
