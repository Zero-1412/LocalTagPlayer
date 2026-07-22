import '../../platform/platform_interfaces.dart';
import 'player_adaptive_quality.dart';

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

/** HDR 实验会话安全协调器的一次判定。 */
class PlayerHdrMappingSafetyDecision {
  const PlayerHdrMappingSafetyDecision({
    required this.shouldRollback,
    required this.reason,
    required this.consecutivePressureSamples,
  });

  /** 是否立即把当前会话恢复为 mpv 自动映射。 */
  final bool shouldRollback;

  /** 面向诊断的匿名原因，不包含媒体路径或驱动原始消息。 */
  final String reason;

  /** 当前连续轻度压力样本数。 */
  final int consecutivePressureSamples;
}

/**
 * 复用播放器两秒健康样本，为 HDR 动态映射提供一次会话内的压力熔断。
 *
 * 新增掉帧、缓冲或音视频停滞会立即回滚；轻度 FPS、缓存或帧推进压力需要连续
 * 两个样本才回滚，避免 seek 后的短暂波动误触发。回滚一旦发生会锁存到下一媒体，
 * 但不会改写用户的全局实验开关。
 */
class PlayerHdrMappingSafetyCoordinator {
  PlayerHdrMappingSafetyCoordinator({
    this.pressureSamplesToRollback = 2,
  });

  /** 轻度压力触发回滚所需的连续样本数。 */
  final int pressureSamplesToRollback;

  int? _previousDecoderDrops;
  int? _previousOutputDrops;
  int? _previousTotalDrops;
  var _consecutivePressureSamples = 0;
  var _rollbackLatched = false;
  var _reason = '等待 HDR 播放健康样本';

  bool get rollbackLatched => _rollbackLatched;
  String get reason => _reason;
  int get consecutivePressureSamples => _consecutivePressureSamples;

  /** 打开新媒体时清除上一条视频的计数器和回滚锁存。 */
  void reset() {
    _previousDecoderDrops = null;
    _previousOutputDrops = null;
    _previousTotalDrops = null;
    _consecutivePressureSamples = 0;
    _rollbackLatched = false;
    _reason = '等待 HDR 播放健康样本';
  }

  /** 评估一次只读播放样本；本类不直接访问 PlayerBackend 或 UI。 */
  PlayerHdrMappingSafetyDecision evaluate(PlayerAdaptiveQualitySample sample) {
    final decoderDelta = _counterDelta(
      sample.decoderDroppedFrames,
      _previousDecoderDrops,
    );
    final outputDelta = _counterDelta(
      sample.outputDroppedFrames,
      _previousOutputDrops,
    );
    final totalDelta = _counterDelta(
      sample.totalDroppedFrames,
      _previousTotalDrops,
    );
    _previousDecoderDrops = sample.decoderDroppedFrames;
    _previousOutputDrops = sample.outputDroppedFrames;
    _previousTotalDrops = sample.totalDroppedFrames;

    if (_rollbackLatched) {
      return _decision(shouldRollback: false);
    }
    if (!sample.playing || sample.recentSeek) {
      _consecutivePressureSamples = 0;
      _reason = sample.recentSeek ? 'seek 后等待 HDR 会话重新稳定' : '暂停时不评估 HDR 压力';
      return _decision(shouldRollback: false);
    }

    final fpsRatio = sample.sourceFps == null ||
            sample.sourceFps! <= 0 ||
            sample.estimatedFps == null
        ? null
        : sample.estimatedFps! / sample.sourceFps!;
    final severePressure = sample.buffering ||
        sample.videoStalled ||
        sample.audioStalled ||
        decoderDelta > 0 ||
        outputDelta > 0 ||
        totalDelta > 0;
    if (severePressure) {
      _rollbackLatched = true;
      _consecutivePressureSamples = 0;
      _reason = '检测到新增掉帧、缓冲或音视频停滞，HDR 会话已自动回滚';
      return _decision(shouldRollback: true);
    }

    final moderatePressure = !sample.videoAdvanced ||
        (sample.cacheDuration != null && sample.cacheDuration! < 2) ||
        (fpsRatio != null && fpsRatio < 0.95);
    if (!moderatePressure) {
      _consecutivePressureSamples = 0;
      _reason = 'HDR 会话实时余量正常';
      return _decision(shouldRollback: false);
    }
    _consecutivePressureSamples++;
    _reason =
        'HDR 会话轻度压力 $_consecutivePressureSamples / $pressureSamplesToRollback';
    if (_consecutivePressureSamples < pressureSamplesToRollback) {
      return _decision(shouldRollback: false);
    }
    _rollbackLatched = true;
    _reason = '连续 FPS、缓存或帧推进压力，HDR 会话已自动回滚';
    return _decision(shouldRollback: true);
  }

  PlayerHdrMappingSafetyDecision _decision({
    required bool shouldRollback,
  }) =>
      PlayerHdrMappingSafetyDecision(
        shouldRollback: shouldRollback,
        reason: _reason,
        consecutivePressureSamples: _consecutivePressureSamples,
      );

  static int _counterDelta(int? current, int? previous) {
    if (current == null || previous == null || current < previous) return 0;
    return current - previous;
  }
}
