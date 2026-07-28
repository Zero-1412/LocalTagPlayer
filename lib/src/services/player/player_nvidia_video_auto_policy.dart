import 'player_gpu_capability_detector.dart';
import 'player_nvidia_video_enhancement_experiment.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 当前媒体的 NVIDIA 自动增强决策。
 *
 * 决策只表达应用意图；驱动是否真正工作仍必须由原生 mpv 日志确认。
 */
class PlayerNvidiaVideoAutoDecision {
  const PlayerNvidiaVideoAutoDecision({
    required this.videoSuperResolutionEnabled,
    required this.videoHdrEnabled,
    required this.reason,
  });

  /** 当前媒体是否应请求 RTX 视频超分。 */
  final bool videoSuperResolutionEnabled;

  /** 当前 SDR 媒体是否应请求 RTX Video HDR。 */
  final bool videoHdrEnabled;

  /** 面向诊断的稳定中文原因，不包含路径或驱动原始日志。 */
  final String reason;

  /** 当前媒体是否至少请求一项 NVIDIA 视频增强。 */
  bool get enabled => videoSuperResolutionEnabled || videoHdrEnabled;
}

/**
 * 根据当前渲染设备、源信号和桌面输出决定 NVIDIA 自动增强。
 *
 * 未知能力一律保持关闭；VSR 只在源分辨率相对连接输出存在放大空间时请求，
 * TrueHDR 只在明确 SDR、Windows HDR 信号活动且输出至少 10 bit 时请求。
 */
class PlayerNvidiaVideoAutoPolicy {
  const PlayerNvidiaVideoAutoPolicy._();

  /** NVIDIA 的 PCI 厂商标识。 */
  static const _nvidiaVendorId = 0x10de;

  /**
   * 为已经完成媒体打开和 GPU 探测的会话生成一次自动决策。
   *
   * [snapshot] 必须来自当前播放后端的活动 LUID；[capability] 必须来自同一
   * 会话的固定 mpv/D3D11 探测，不能用系统显卡名称替代。
   */
  static PlayerNvidiaVideoAutoDecision evaluate({
    required PlayerGpuCapabilitySnapshot snapshot,
    required PlayerNvidiaVideoEnhancementCapability capability,
  }) {
    final adapter = snapshot.selectedAdapter;
    if (adapter == null || adapter.vendorId != _nvidiaVendorId) {
      return const PlayerNvidiaVideoAutoDecision(
        videoSuperResolutionEnabled: false,
        videoHdrEnabled: false,
        reason: '未检测到当前播放会话的 NVIDIA 渲染适配器',
      );
    }
    if (!capability.canRequest) {
      return const PlayerNvidiaVideoAutoDecision(
        videoSuperResolutionEnabled: false,
        videoHdrEnabled: false,
        reason: '当前播放后端未通过 NVIDIA 原生 D3D11 门禁',
      );
    }
    final sourceWidth = snapshot.sourceWidth;
    final sourceHeight = snapshot.sourceHeight;
    if (sourceWidth == null || sourceHeight == null) {
      return const PlayerNvidiaVideoAutoDecision(
        videoSuperResolutionEnabled: false,
        videoHdrEnabled: false,
        reason: '等待当前视频分辨率后再判断 NVIDIA 自动增强',
      );
    }
    final outputs = adapter.outputs
        .where((output) => output.attachedToDesktop)
        .toList(growable: false);
    if (outputs.isEmpty) {
      return const PlayerNvidiaVideoAutoDecision(
        videoSuperResolutionEnabled: false,
        videoHdrEnabled: false,
        reason: '未检测到 NVIDIA 适配器连接的桌面输出',
      );
    }

    // 请求只表示允许驱动接管；窗口实际没有放大时，驱动仍可自行保持未激活。
    final requestVsr = outputs.any(
      (output) =>
          output.desktopWidth > sourceWidth ||
          output.desktopHeight > sourceHeight,
    );
    final requestHdr = capability.canRequestHdr &&
        outputs.any(
          (output) =>
              output.hdrSignalActive && (output.bitsPerColor ?? 0) >= 10,
        );
    final reason = switch ((requestVsr, requestHdr)) {
      (true, true) => '已为当前低分辨率 SDR 视频自动请求 VSR + HDR',
      (true, false) => '已为当前存在放大空间的视频自动请求 VSR',
      (false, true) => '已为当前 SDR 视频自动请求 HDR',
      (false, false) => '当前视频无放大空间，且 HDR 输出或 SDR 源门禁未通过',
    };
    return PlayerNvidiaVideoAutoDecision(
      videoSuperResolutionEnabled: requestVsr,
      videoHdrEnabled: requestHdr,
      reason: reason,
    );
  }
}
