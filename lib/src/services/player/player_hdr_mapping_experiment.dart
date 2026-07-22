import '../../platform/platform_interfaces.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 第三阶段唯一启用的可回滚实验：HDR 动态映射。
 *
 * 实验复用 mpv GPU renderer 的 Hable 曲线和逐帧峰值 Compute；关闭时逐项恢复
 * `auto` / `no`，不修改视频文件、显示器系统设置或其它画质增强档位。
 */
class PlayerHdrMappingExperiment {
  const PlayerHdrMappingExperiment._();

  /** 把实验开关完整应用到当前播放会话。 */
  static Future<void> apply({
    required PlayerBackend backend,
    required bool enabled,
  }) async {
    final values = enabled
        ? const <String, String>{
            'tone-mapping': 'hable',
            'hdr-compute-peak': 'yes',
            // 高级缩放已经存在间接 pass 时允许延后一帧读取峰值，降低同步开销。
            'allow-delayed-peak-detect': 'yes',
          }
        : const <String, String>{
            'tone-mapping': 'auto',
            'hdr-compute-peak': 'auto',
            'allow-delayed-peak-detect': 'no',
          };
    for (final entry in values.entries) {
      await backend.setProperty(entry.key, entry.value);
    }
  }
}
