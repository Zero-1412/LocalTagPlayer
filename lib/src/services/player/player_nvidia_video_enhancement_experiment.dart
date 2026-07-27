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
 * 该快照描述 mpv `d3d11vpp` 的 `scaling-mode=nvidia` 驱动路径，不代表
 * RTX Video SDK 已接入，也不把显卡型号或普通 D3D11 输出误判为 AI 正在工作。
 */
class PlayerNvidiaVideoEnhancementCapability {
  const PlayerNvidiaVideoEnhancementCapability({
    required this.status,
    required this.mpvVersion,
    required this.hasD3d11vpp,
    required this.hasNvidiaScalingMode,
    this.filterChainIntegrated = false,
  });

  /** 后端属性仍在查询时使用的稳定初始状态。 */
  const PlayerNvidiaVideoEnhancementCapability.probing()
      : status = PlayerNvidiaVideoEnhancementStatus.probing,
        mpvVersion = null,
        hasD3d11vpp = false,
        hasNvidiaScalingMode = false,
        filterChainIntegrated = false;

  /** 当前能力判定结果。 */
  final PlayerNvidiaVideoEnhancementStatus status;

  /** 从实际后端读取或由项目固定依赖回退得到的 mpv 版本。 */
  final String? mpvVersion;

  /** 当前内嵌构建是否包含 D3D11 视频处理滤镜。 */
  final bool hasD3d11vpp;

  /** 当前内嵌构建是否包含 NVIDIA 专用缩放模式。 */
  final bool hasNvidiaScalingMode;

  /**
   * 当前播放器 `vf` 与解码纹理链是否已完成该模式的接入验证。
   *
   * 即使用户本机替换为新版 mpv，也不能仅按版本号开放开关；否则
   * `d3d11va-copy` 或现有 CPU 画质滤镜可能让 D3D11 视频处理链失效。
   */
  final bool filterChainIntegrated;

  /** 只有 mpv 能力和播放器滤镜链都完成验证时才允许实验开关响应点击。 */
  bool get canEnable =>
      status == PlayerNvidiaVideoEnhancementStatus.available &&
      filterChainIntegrated;

  /** 面向设置页的边界说明，不把驱动扩展描述成 RTX Video SDK。 */
  String get helperText => switch (status) {
        PlayerNvidiaVideoEnhancementStatus.probing => '正在检查内嵌 mpv 能力',
        PlayerNvidiaVideoEnhancementStatus.available => filterChainIntegrated
            ? 'mpv $mpvVersion：d3d11vpp NVIDIA 模式可用；非 RTX Video SDK'
            : 'mpv $mpvVersion 支持该模式，但纹理/滤镜链尚未验证',
        PlayerNvidiaVideoEnhancementStatus.unsupportedPlatform =>
          '仅支持 Windows D3D11；非 RTX Video SDK',
        PlayerNvidiaVideoEnhancementStatus.missingNvidiaScalingMode =>
          'mpv $mpvVersion：有 d3d11vpp；无 NVIDIA scaling-mode',
        PlayerNvidiaVideoEnhancementStatus.unavailable =>
          '无法确认内嵌 mpv 能力，实验入口保持关闭',
      };
}

/**
 * 检测 mpv NVIDIA 驱动视频增强路径，不写播放器属性或插件 ABI。
 *
 * 项目固定的 0.36.0 二进制已通过字符串检查确认含 `d3d11vpp`，但 NVIDIA
 * scaling mode 从 mpv 0.39.0 才提供。实际后端暂时无法读取版本时回退固定依赖
 * 版本，确保原生 A/B 后端与默认 MediaKit 都不会展示可点击的假开关。
 */
class PlayerNvidiaVideoEnhancementExperiment {
  const PlayerNvidiaVideoEnhancementExperiment._();

  /** 当前 Windows 构建脚本固定下载的 mpv 版本。 */
  static const bundledMpvVersion = '0.36.0';

  /** `scaling-mode=nvidia` 首次进入 mpv 正式版本的最低版本。 */
  static const minimumNvidiaScalingModeVersion = '0.39.0';

  /** 查询当前后端 mpv 版本并返回不会修改播放状态的能力快照。 */
  static Future<PlayerNvidiaVideoEnhancementCapability> probe(
    PlayerBackend backend, {
    bool? isWindows,
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
    // 本项目已对固定的 0.36.0 DLL 做过二进制检查；后续更高版本沿用同一滤镜能力。
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
    );
  }

  /** 从 `mpv 0.36.0-...` 或 `0.39.0` 中提取可比较的三段版本号。 */
  static List<int>? parseVersion(String rawValue) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(rawValue);
    if (match == null) return null;
    return <int>[
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
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
