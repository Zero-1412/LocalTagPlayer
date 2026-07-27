import 'dart:io';

import '../../platform/platform_interfaces.dart';

// ignore_for_file: slash_for_doc_comments

/** 内嵌 mpv 的 NVIDIA 驱动视频增强实验能力状态。 */
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
 * 开关只有在版本、零拷贝解码链和滤镜互斥条件同时满足时才可用。
 */
class PlayerNvidiaVideoEnhancementCapability {
  const PlayerNvidiaVideoEnhancementCapability({
    required this.status,
    required this.mpvVersion,
    required this.hasD3d11vpp,
    required this.hasNvidiaScalingMode,
    this.hwdecCurrent,
    this.currentVo,
    this.runtimeState = 'inactive',
    this.filterChainIntegrated = false,
    this.conflictingCpuFilters = false,
  });

  /** 后端属性仍在查询时使用的稳定初始状态。 */
  const PlayerNvidiaVideoEnhancementCapability.probing()
      : status = PlayerNvidiaVideoEnhancementStatus.probing,
        mpvVersion = null,
        hasD3d11vpp = false,
        hasNvidiaScalingMode = false,
        hwdecCurrent = null,
        currentVo = null,
        runtimeState = 'inactive',
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

  /** 多片源 A/B、掉帧与回滚验证是否已覆盖当前滤镜接入。 */
  final bool filterChainIntegrated;

  /** 压缩增强或暗场增强是否正在占用 CPU `lavfi` 滤镜链。 */
  final bool conflictingCpuFilters;

  /** 当前媒体是否真实运行在 D3D11VA 非 copy 解码链。 */
  bool get usesNonCopyD3d11 => hwdecCurrent == 'd3d11va';

  /** 当前会话是否绕过 Flutter Texture 并由 libmpv 直接拥有 D3D11 输出。 */
  bool get usesNativeD3d11Output => currentVo == 'gpu-next-d3d11-child-hwnd';

  /** 所有可验证门槛同时满足时才允许实验开关响应点击。 */
  bool get canEnable =>
      status == PlayerNvidiaVideoEnhancementStatus.available &&
      filterChainIntegrated &&
      usesNonCopyD3d11 &&
      usesNativeD3d11Output &&
      !conflictingCpuFilters;

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
    if (conflictingCpuFilters) {
      return '请先关闭压缩画质增强和暗场增强；两类滤镜不能安全串联';
    }
    if (!usesNativeD3d11Output) {
      return '需使用 Windows 原生 libmpv D3D11 渲染器';
    }
    if (!usesNonCopyD3d11) {
      return '需在解码设置中选择 D3D11VA（非 copy），并重新打开视频';
    }
    if (runtimeState == 'active') {
      return 'NVIDIA RTX Super Resolution 已由驱动确认';
    }
    if (runtimeState == 'requested') {
      return '已请求 NVIDIA RTX Super Resolution，等待驱动确认';
    }
    if (runtimeState == 'rejected') {
      return 'libmpv 拒绝 NVIDIA 滤镜，已保持关闭';
    }
    return 'mpv $mpvVersion · 原生 D3D11VA 零拷贝';
  }
}

/**
 * 检测 mpv NVIDIA 驱动视频增强路径，不改插件 ABI 或播放器属性。
 *
 * 固定版本仅用于后端尚未就绪时的保守回退；实际媒体打开后必须再次读取
 * `hwdec-current`，不能用用户选择的解码器名称代替真实纹理链证据。
 */
class PlayerNvidiaVideoEnhancementExperiment {
  const PlayerNvidiaVideoEnhancementExperiment._();

  /** 当前 Windows 构建脚本固定下载的 mpv 版本。 */
  static const bundledMpvVersion = '0.41.0';

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
    final version = parseVersion(reportedVersion) ??
        parseVersion(PlayerNvidiaVideoEnhancementExperiment.bundledMpvVersion);
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
    return PlayerNvidiaVideoEnhancementCapability(
      status: hasD3d11vpp && hasNvidiaScalingMode
          ? PlayerNvidiaVideoEnhancementStatus.available
          : hasD3d11vpp
              ? PlayerNvidiaVideoEnhancementStatus.missingNvidiaScalingMode
              : PlayerNvidiaVideoEnhancementStatus.unavailable,
      mpvVersion: normalizedVersion,
      hasD3d11vpp: hasD3d11vpp,
      hasNvidiaScalingMode: hasNvidiaScalingMode,
      hwdecCurrent: _normalizeProperty(reportedHwdec),
      currentVo: _normalizeProperty(reportedVo),
      runtimeState: _normalizeRuntimeState(reportedRuntimeState),
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
  static String _normalizeRuntimeState(String rawValue) {
    final normalized = rawValue.trim().toLowerCase();
    return const <String>{
      'inactive',
      'requested',
      'active',
      'rejected',
    }.contains(normalized)
        ? normalized
        : 'inactive';
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
