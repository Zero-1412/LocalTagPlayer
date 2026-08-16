import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../platform/platform_interfaces.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放器跨 Flutter、media_kit 与原生纹理边界的轻量内存阶段记录器。
 *
 * 记录内容不包含媒体路径；外部压力脚本可用时间戳把阶段与 Windows GPU Process Memory
 * 计数器对齐，从而区分 Flutter 图片缓存、libmpv 缓存和 D3D 纹理驻留。
 */
class PlayerMemoryDiagnostics {
  const PlayerMemoryDiagnostics._();

  /** 诊断属性单次读取上限；日志不能反向阻塞播放器释放尾链。 */
  static const propertyReadTimeout = Duration(seconds: 2);

  /**
   * 记录一个阶段。
   *
   * [readEngineProperties] 在播放器已释放后应为 false，仍可通过 [backend] 读取最终
   * 结构化遥测，但不再触碰已销毁的 libmpv 属性。
   */
  static Future<void> logStage(
    String stage, {
    PlayerRuntimeAccess? backend,
    bool readEngineProperties = true,
  }) async {
    final imageCache = PaintingBinding.instance.imageCache;
    var demuxSeconds = 'unavailable';
    var demuxState = 'unavailable';
    if (backend != null && readEngineProperties) {
      try {
        demuxSeconds = await backend
            .getProperty('demuxer-cache-duration')
            .timeout(propertyReadTimeout);
      } catch (_) {
        // 文件尚未打开或 Player 正在释放时，mpv 属性允许暂时不可用。
      }
      try {
        demuxState = await backend
            .getProperty('demuxer-cache-state')
            .timeout(propertyReadTimeout);
      } catch (_) {
        // 复杂 node 属性在部分构建中不可转换为字符串，保留 unavailable。
      }
    }
    final telemetryBoundary = backend is PlayerBackendTelemetryBoundary
        ? backend as PlayerBackendTelemetryBoundary
        : null;
    final telemetry = telemetryBoundary?.telemetry;
    debugPrint(
      'PLAYER_MEMORY_STAGE timestamp=${DateTime.now().toIso8601String()} '
      'stage=$stage rss_bytes=${ProcessInfo.currentRss} '
      'image_cache_bytes=${imageCache.currentSizeBytes} '
      'image_cache_count=${imageCache.currentSize} '
      'image_cache_live=${imageCache.liveImageCount} '
      'image_cache_pending=${imageCache.pendingImageCount} '
      'texture_id=${readEngineProperties ? backend?.textureId.value ?? -1 : -1} '
      'demux_seconds=$demuxSeconds demux_state=$demuxState '
      'backend=${telemetry?.backendName ?? 'unsupported'} '
      'open_generation=${telemetry?.openGeneration ?? 0} '
      'first_frame_ms=${telemetry?.firstFrameLatency?.inMilliseconds ?? -1} '
      'first_frame_evidence=${telemetry?.firstFrameEvidence ?? 'unavailable'} '
      'hwdec_current=${telemetry?.hwdecCurrent ?? 'unavailable'} '
      'video_codec=${telemetry?.videoCodec ?? 'unavailable'} '
      'error_events=${telemetry?.errorEventCount ?? 0} '
      'failed_opens=${telemetry?.failedOpenCount ?? 0} '
      'release_phase=${telemetry?.releasePhase.name ?? 'unsupported'} '
      'player_dispose_ms=${telemetry?.playerDisposeDuration?.inMilliseconds ?? -1} '
      'native_release_wait_ms=${telemetry?.nativeReleaseWait?.inMilliseconds ?? -1} '
      'release_total_ms=${telemetry?.totalReleaseDuration?.inMilliseconds ?? -1}',
    );
  }
}
