part of '../../app.dart';

// ignore_for_file: slash_for_doc_comments

/** 硬件解码兼容性预检结论。 */
enum HardwareDecodeCompatibilityStatus {
  /** 当前参考环境已经用真实媒体确认可硬解。 */
  verified,

  /** 当前 Windows 播放链路已经用真实媒体确认会回退软件解码。 */
  unsupported,

  /** 缺少媒体详情或不在已验证矩阵内，不做猜测性提示。 */
  unknown,
}

/**
 * 播放前使用的不可变硬解兼容性结果。
 *
 * 该对象只携带数据库已有的编解码与分辨率结论，不包含路径，也不会触发
 * FFprobe。UI 只对 [unsupported] 显示阻断式确认，其余状态继续正常播放。
 */
class HardwareDecodeCompatibilityAssessment {
  const HardwareDecodeCompatibilityAssessment({
    required this.status,
    required this.codec,
    required this.width,
    required this.height,
    this.reason,
  });

  /** 矩阵结论。 */
  final HardwareDecodeCompatibilityStatus status;

  /** 归一化后的主视频编码。 */
  final String codec;

  /** 已缓存的视频宽度。 */
  final int? width;

  /** 已缓存的视频高度。 */
  final int? height;

  /** 仅在已确认不支持时展示的原因。 */
  final String? reason;

  /** 供确认弹窗展示的紧凑规格。 */
  String get specification {
    final resolution =
        width == null || height == null ? '未知分辨率' : '$width×$height';
    return '${codec.isEmpty ? '未知编码' : codec} · $resolution';
  }
}

/**
 * Windows 播放前硬解兼容矩阵。
 *
 * 矩阵只收录当前应用实际用 `d3d11va-copy` 重复验证过的规格：4K H.264、
 * HEVC、AV1 可硬解；8K H.264 会回退软件解码。未验证组合保持 unknown，避免
 * 根据编码名称或文件大小臆测硬件能力。
 */
class PlayerHardwareCompatibility {
  const PlayerHardwareCompatibility._();

  /**
   * 使用数据库缓存详情评估一个视频，不读取文件系统，也不启动媒体探测。
   *
   * [isWindows] 只供跨平台单元测试注入；生产调用默认使用实际运行平台。
   */
  static HardwareDecodeCompatibilityAssessment assess({
    required MediaDetails? details,
    required PlaybackSettings settings,
    bool? isWindows,
  }) {
    final codec = _normalizeCodec(details?.videoCodec);
    final width = details?.width;
    final height = details?.height;
    final unknown = HardwareDecodeCompatibilityAssessment(
      status: HardwareDecodeCompatibilityStatus.unknown,
      codec: codec,
      width: width,
      height: height,
    );

    // 用户主动关闭硬解时不把设置选择误报为硬件不兼容。
    if (!settings.hardwareDecodingEnabled ||
        !(isWindows ?? Platform.isWindows)) {
      return unknown;
    }
    if (codec.isEmpty || width == null || height == null) {
      return unknown;
    }

    final longEdge = math.max(width, height);
    final shortEdge = math.min(width, height);
    if (codec == 'H.264' && longEdge >= 7680 && shortEdge >= 4320) {
      return HardwareDecodeCompatibilityAssessment(
        status: HardwareDecodeCompatibilityStatus.unsupported,
        codec: codec,
        width: width,
        height: height,
        reason:
            '当前 Windows D3D11VA 播放链路已确认该 8K H.264 规格会回退到 CPU 软件解码，可能持续高占用并出现掉帧或音画不同步。',
      );
    }

    // 只把真实样本覆盖到的标准 4K 三种编码标为已验证，不外推到 5K/8K。
    if (longEdge <= 4096 &&
        shortEdge <= 2304 &&
        const {'H.264', 'HEVC', 'AV1'}.contains(codec)) {
      return HardwareDecodeCompatibilityAssessment(
        status: HardwareDecodeCompatibilityStatus.verified,
        codec: codec,
        width: width,
        height: height,
      );
    }
    return unknown;
  }

  /** 把 FFprobe/数据库中常见的编码名称归一为矩阵键。 */
  static String _normalizeCodec(String? raw) {
    final value = raw?.trim().toLowerCase() ?? '';
    if (value == 'h264' || value == 'avc' || value.startsWith('avc1')) {
      return 'H.264';
    }
    if (value == 'hevc' || value == 'h265' || value.startsWith('hev1')) {
      return 'HEVC';
    }
    if (value == 'av1' || value.startsWith('av01')) {
      return 'AV1';
    }
    return value.toUpperCase();
  }
}
