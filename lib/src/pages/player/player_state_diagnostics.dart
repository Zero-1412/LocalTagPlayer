import 'dart:async';
import 'dart:io';

import '../../core/playback_settings.dart';
import '../../models/media_details.dart';
import '../../services/player/player_adaptive_quality.dart';
import 'player_diagnostics_dialog.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 生成只读播放诊断快照。
 *
 * 这里只承载 [PlayerPageState] 的实现细节；播放会话、过滤队列与资源生命周期所有权
 * 仍保留在页面状态对象中。
 */
extension PlayerStateDiagnostics on PlayerPageState {
  Future<PlaybackDiagnosticsSnapshot> buildDiagnosticsSnapshot() async {
    final before = playerService.state.position;
    final wasPlaying = playerService.state.playing;
    final wasBuffering = playerService.state.buffering;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final after = playerService.state.position;
    final progressMs = after.inMilliseconds - before.inMilliseconds;
    final expectedMs = wasPlaying && !wasBuffering ? 900 : 0;
    final smooth = expectedMs == 0 || progressMs >= expectedMs;
    // 播放诊断只读已有详情，打开弹窗不能为兜底探测再创建一个 media_kit Player。
    final details =
        detailsService.cachedDetailsFor(currentItem) ?? const MediaDetails();
    final mpv = <String, String>{};
    for (final property in <String>[
      'hwdec-current',
      'current-vo',
      'video-codec',
      'audio-codec',
      'container-fps',
      'estimated-vf-fps',
      'display-fps',
      'video-sync',
      'interpolation',
      'tscale',
      'display-sync-active',
      'vf',
      'deband',
      'deband-iterations',
      'deband-threshold',
      'deband-range',
      'deband-grain',
      'scale',
      'cscale',
      'dscale',
      'scaler-resizes-only',
      'correct-downscaling',
      'video-output-levels',
      'video-params/colorlevels',
      'video-params/colormatrix',
      'video-params/primaries',
      'video-params/gamma',
      'video-target-params/colorlevels',
      'tone-mapping',
      'hdr-compute-peak',
      'allow-delayed-peak-detect',
      'gpu-api',
      'gpu-context',
      'd3d11-feature-level',
      'avsync',
      'total-avsync-change',
      'mistimed-frame-count',
      'vo-delayed-frame-count',
      'vo-drop-frame-count',
      'decoder-frame-drop-count',
      'frame-drop-count',
      'demuxer-cache-duration',
      'cache-buffering-state',
      'estimated-frame-number',
      'audio-pts',
      'native-render-requests',
      'native-rendered-frames',
      'native-skipped-renders',
      'native-texture-copies',
      'native-surface-resizes',
      'native-surface-width',
      'native-surface-height',
      'native-video-plugin-state',
      'native-video-plugin-name',
      'native-video-plugin-frames',
      'native-video-plugin-fallbacks',
      'native-video-plugin-error',
      if (playerService.supportsNativeNvidiaVideoEnhancement)
        'native-nvidia-vsr-state',
      if (playerService.supportsNativeNvidiaVideoEnhancement)
        'native-nvidia-hdr-state',
    ]) {
      mpv[property] = await getMpvProperty(property);
    }
    final sampledHwdec = mpv['hwdec-current'];
    if (sampledHwdec != null &&
        sampledHwdec != 'empty' &&
        sampledHwdec != 'unavailable') {
      lastHwdecCurrent = sampledHwdec;
    }
    final estimatedFps = parseMpvNumber(mpv['estimated-vf-fps']);
    final frameDurationMs =
        estimatedFps == null || estimatedFps <= 0 ? null : 1000 / estimatedFps;
    final backendTelemetry = playerService.telemetry;
    final videoSurface = playerService.videoSurfaceDiagnostics;
    final filterTransaction = playerService.filterTransaction;
    final lines = <String>[
      '\u5f53\u524d\u89c6\u9891: ${currentItem.title}',
      '后端遥测: ${backendTelemetry.backendName}',
      '媒体打开代次: ${backendTelemetry.openGeneration}',
      '首帧耗时: ${backendTelemetry.firstFrameLatency?.inMilliseconds ?? -1} ms',
      '首帧证据: ${backendTelemetry.firstFrameEvidence ?? 'unavailable'}',
      '遥测实际硬解: ${backendTelemetry.hwdecCurrent ?? 'unavailable'}',
      '遥测视频编码: ${backendTelemetry.videoCodec ?? 'unavailable'}',
      '后端错误事件/失败打开: ${backendTelemetry.errorEventCount} / '
          '${backendTelemetry.failedOpenCount}',
      '原生 Texture 尺寸: ${formatDiagnosticSize(videoSurface.textureWidthPx, videoSurface.textureHeightPx, 'px')}',
      '视频 Widget 逻辑尺寸: ${formatDiagnosticSize(videoSurface.widgetLogicalWidth, videoSurface.widgetLogicalHeight, 'dp')}',
      '窗口 DPR: ${videoSurface.devicePixelRatio?.toStringAsFixed(2) ?? 'unavailable'}',
      '视频 Widget 物理尺寸: ${formatDiagnosticSize(videoSurface.widgetPhysicalWidthPx, videoSurface.widgetPhysicalHeightPx, 'px')}',
      'BoxFit 视频物理目标: ${formatDiagnosticSize(videoSurface.fittedVideoPhysicalWidthPx, videoSurface.fittedVideoPhysicalHeightPx, 'px')}',
      'Texture 合成倍率: ${formatDiagnosticScale(videoSurface.horizontalScale, videoSurface.verticalScale)}',
      'Flutter Texture 采样: ${videoSurface.filterQuality ?? 'unavailable'}',
      '连续切换失败率: '
          '${(backendTelemetry.openFailureRate * 100).toStringAsFixed(2)}%',
      '资源释放阶段: ${backendTelemetry.releasePhase.name}',
      '滤镜事务: #${filterTransaction.sequence} · ${filterTransaction.label}',
      '滤镜事务结果: ${filterTransaction.phase.name} · '
          '${filterTransaction.verifiedPropertyCount}/'
          '${filterTransaction.requestedPropertyCount}',
      '滤镜读回不一致: '
          '${filterTransaction.mismatchedProperties.isEmpty ? '无' : filterTransaction.mismatchedProperties.join(',')}',
      '滤镜事务回滚: '
          '${filterTransaction.rollbackAttempted ? (filterTransaction.rollbackVerified ? '已验证' : '失败') : '未触发'}',
      '滤镜事务错误: ${filterTransaction.failureCode ?? '无'}',
      '\u64ad\u653e\u4f4d\u7f6e: ${formatDuration(after)} / ${formatDuration(playerService.state.duration)}',
      '\u64ad\u653e\u72b6\u6001: ${playerService.state.playing ? '\u64ad\u653e\u4e2d' : '\u6682\u505c'}',
      '\u7f13\u51b2\u72b6\u6001: ${playerService.state.buffering ? '\u7f13\u51b2\u4e2d' : '\u6b63\u5e38'}',
      '\u91c7\u6837\u63a8\u8fdb: $progressMs ms / 1200 ms',
      '\u6d41\u7545\u63a8\u65ad: ${smooth ? '\u6b63\u5e38' : '\u53ef\u80fd\u5361\u987f\u6216\u89e3\u7801\u8ddf\u4e0d\u4e0a'}',
      '\u8bbe\u7f6e\u786c\u89e3: ${pageWidget.playbackSettings.hwdec}',
      'mpv 请求硬解: $requestedHwdec',
      'mpv \u5b9e\u9645\u786c\u89e3: ${mpv['hwdec-current']}',
      'mpv \u8f93\u51fa\u9a71\u52a8: ${mpv['current-vo']}',
      'mpv \u89c6\u9891\u7f16\u7801: ${mpv['video-codec']}',
      'mpv \u97f3\u9891\u7f16\u7801: ${mpv['audio-codec']}',
      'mpv \u5bb9\u5668 FPS: ${mpv['container-fps']}',
      'mpv \u4f30\u7b97\u89c6\u9891 FPS: ${mpv['estimated-vf-fps']}',
      '估算单帧耗时: ${frameDurationMs?.toStringAsFixed(2) ?? 'unavailable'} ms',
      'mpv \u663e\u793a FPS: ${mpv['display-fps']}',
      'mpv \u89c6\u9891\u540c\u6b65: ${mpv['video-sync']}',
      'mpv 插值请求: ${mpv['interpolation']}',
      'mpv 时间缩放器: ${mpv['tscale']}',
      'mpv 显示同步活动: ${mpv['display-sync-active']}',
      '流畅度提升设置: ${PlaybackSettings.smoothMotionLabelFor(smoothMotionMode)}',
      '显示同步插值配置: ${smoothMotionActive ? '属性已确认' : '未启用'} · $smoothMotionApplyReason',
      '显示同步插值压力保护: ${smoothMotionSafetyCoordinator.reason}',
      '显示同步插值回滚原因: ${smoothMotionRollbackReason ?? '无'}',
      '显示同步插值回滚时间: ${smoothMotionRollbackAt?.toIso8601String() ?? 'none'}',
      '压缩画质增强设置: ${PlaybackSettings.compressionEnhancementLabelFor(compressionEnhancementMode)}',
      '自动画质基线: ${adaptiveQualityCoordinator.profile.label}',
      '自动画质档位: ${playerAdaptiveQualityLevelLabel(adaptiveQualityLevel)}',
      '自动画质属性状态: ${adaptiveQualityApplyResult.statusLabel}',
      '自动画质判断: ${adaptiveQualityCoordinator.reason}',
      'mpv 视频滤镜: ${mpv['vf']}',
      'mpv 去色带: ${mpv['deband']}',
      'mpv 去色带参数: iterations=${mpv['deband-iterations']} · threshold=${mpv['deband-threshold']} · range=${mpv['deband-range']} · grain=${mpv['deband-grain']}',
      'GPU 高质量缩放（非 NVIDIA AI）设置: ${videoSuperResolutionEnabled ? '开启' : '关闭'}',
      'GPU 高质量缩放会话: ${videoSuperResolutionActive ? '属性已读回确认' : videoSuperResolutionApplyResult.statusLabel}',
      '播放后端: MediaKit Texture',
      if (playerService.supportsNativeNvidiaVideoEnhancement) ...<String>[
        '原生 QA · NVIDIA RTX 视频超分: ${nvidiaVideoEnhancementExperimentEnabled ? '会话已请求' : '关闭'} · ${nvidiaVideoEnhancementCapability.helperText}',
        '原生 QA · NVIDIA RTX Video HDR: ${nvidiaVideoHdrExperimentEnabled ? '会话已请求' : '关闭'} · ${nvidiaVideoEnhancementCapability.hdrHelperText}',
        '原生 QA · NVIDIA 自动策略: $nvidiaVideoAutomaticReason',
        '原生 QA · NVIDIA 滤镜互斥处理: ${nvidiaCpuEnhancementsSuspended ? '已在当前会话暂时停用压缩画质增强和暗场增强' : '未触发'}',
        '原生 QA · NVIDIA VSR 驱动确认: ${mpv['native-nvidia-vsr-state']}',
        '原生 QA · NVIDIA HDR 驱动确认: ${mpv['native-nvidia-hdr-state']}',
        '原生 QA · NVIDIA 压力保护: ${nvidiaVideoSafetyCoordinator.reason}',
        '原生 QA · NVIDIA 自动回滚原因: ${nvidiaVideoEnhancementRollbackReason ?? '无'}',
        '原生 QA · NVIDIA 自动回滚时间: ${nvidiaVideoEnhancementRollbackAt?.toIso8601String() ?? 'none'}',
      ],
      'mpv GPU 缩放器: ${mpv['scale']}',
      'mpv GPU 色度缩放器: ${mpv['cscale']}',
      'mpv GPU 缩小器: ${mpv['dscale']}',
      'mpv 仅缩放时增强: ${mpv['scaler-resizes-only']}',
      'mpv 缩小校正: ${mpv['correct-downscaling']}',
      'mpv 输出电平设置: ${mpv['video-output-levels']}',
      '源色彩范围: ${mpv['video-params/colorlevels']}',
      '源色彩矩阵: ${mpv['video-params/colormatrix']}',
      '源色彩原色: ${mpv['video-params/primaries']}',
      '源传递函数: ${mpv['video-params/gamma']}',
      '实际输出色彩范围: ${mpv['video-target-params/colorlevels']}',
      'GPU 输出驱动: ${gpuCapabilitySnapshot?.outputDriver ?? mpv['current-vo']}',
      'GPU 渲染 API: ${gpuCapabilitySnapshot?.gpuApi ?? mpv['gpu-api']}',
      'GPU 渲染上下文: ${gpuCapabilitySnapshot?.gpuContext ?? mpv['gpu-context']}',
      'D3D11 Feature Level: ${gpuCapabilitySnapshot?.d3d11FeatureLevel ?? mpv['d3d11-feature-level']}',
      '原生 GPU 探测: ${gpuCapabilitySnapshot?.capabilityMatrix.probeStatus ?? '等待检测'}',
      'GPU 设备数量: ${gpuCapabilitySnapshot?.capabilityMatrix.adapters.length ?? 0}',
      '活动 GPU: ${gpuCapabilitySnapshot?.selectedAdapter?.name ?? '未唯一确认'}',
      '活动 GPU 判定: ${gpuCapabilitySnapshot?.adapterSelectionSource ?? '等待检测'}',
      '活动 GPU 专用显存: ${gpuCapabilitySnapshot?.selectedAdapter == null ? '未确认' : formatBytes(gpuCapabilitySnapshot!.selectedAdapter!.dedicatedVideoMemoryBytes)}',
      '活动 GPU 本地显存预算/占用: ${formatGpuMemoryPair(gpuCapabilitySnapshot?.selectedAdapter?.localMemoryBudgetBytes, gpuCapabilitySnapshot?.selectedAdapter?.localMemoryUsageBytes)}',
      'Vulkan loader / 实例: ${gpuCapabilitySnapshot?.capabilityMatrix.vulkanLoaderAvailable == true ? '是' : '否'} / ${gpuCapabilitySnapshot?.capabilityMatrix.vulkanInstanceAvailable == true ? '是' : '否'}',
      'Vulkan 已检测: ${gpuCapabilitySnapshot?.vulkanDetected == true ? '是' : '否 / 未验证'}',
      'Compute Shader 已验证: ${gpuCapabilitySnapshot?.computeShaderVerified == true ? '是' : '否'}',
      'HDR 源信号: ${gpuCapabilitySnapshot?.hdrSourceDetected == true ? '已检测' : '未检测'}',
      'SDR 源信号: ${gpuCapabilitySnapshot?.sdrSourceDetected == true ? '已检测' : '未检测 / 未确认'}',
      '暗部细节增强设置: ${effectivePlaybackSettings.darkSceneEnhancementEnabled ? '开启' : '关闭'}',
      '暗部细节增强会话: ${darkSceneEnhancementActive ? '滤镜属性已读回确认' : darkSceneEnhancementApplyResult.statusLabel}',
      '暗部增强压力保护: ${darkSceneSafetyCoordinator.reason}',
      '暗部增强自动回滚原因: ${darkSceneEnhancementRollbackReason ?? '无'}',
      '暗部增强自动回滚时间: ${darkSceneEnhancementRollbackAt?.toIso8601String() ?? 'none'}',
      'HDR 转 SDR 色调映射设置: ${effectivePlaybackSettings.hdrDynamicToneMappingExperimentEnabled ? '开启' : '关闭'}',
      'HDR 转 SDR 色调映射会话: ${hdrMappingExperimentActive ? '属性已读回确认' : hdrMappingApplyResult.statusLabel}',
      'HDR 转 SDR 压力保护: ${hdrMappingSafetyCoordinator.reason}',
      'HDR 转 SDR 自动回滚原因: ${hdrMappingRollbackReason ?? '无'}',
      'HDR 转 SDR 自动回滚时间: ${hdrMappingRollbackAt?.toIso8601String() ?? 'none'}',
      'mpv HDR 映射曲线: ${mpv['tone-mapping']}',
      'mpv HDR 动态峰值: ${mpv['hdr-compute-peak']}',
      '第三阶段能力状态: ${gpuCapabilitySnapshot?.readinessLabel ?? '等待当前媒体能力检测'}',
      ...?gpuCapabilitySnapshot?.capabilityMatrix.adapters.expand(
        (adapter) => <String>[
          'GPU[${adapter.enumerationIndex}]: ${adapter.name} · '
              'VID ${adapter.vendorId.toRadixString(16).padLeft(4, '0')} '
              'DID ${adapter.deviceId.toRadixString(16).padLeft(4, '0')} · '
              'VRAM ${formatBytes(adapter.dedicatedVideoMemoryBytes)} · '
              'D3D ${adapter.d3dFeatureLevel} · '
              'Compute ${adapter.computeShaderSupported ? '是' : '否'} · '
              'Vulkan ${adapter.vulkanSupported ? adapter.vulkanApiVersion ?? '是' : '否'}',
          for (final output in adapter.outputs)
            '显示输出 ${output.deviceName}: '
                '${output.desktopWidth}x${output.desktopHeight} · '
                '${output.bitsPerColor ?? 0} bit · '
                '${output.colorSpace ?? 'unavailable'} · '
                'HDR 信号 ${output.hdrSignalActive ? '活动' : '未活动'} · '
                '峰值 ${output.maxLuminanceNits?.toStringAsFixed(1) ?? 'unknown'} nits',
        ],
      ),
      'mpv AV \u504f\u79fb: ${mpv['avsync']}',
      'mpv AV \u7d2f\u8ba1\u4fee\u6b63: ${mpv['total-avsync-change']}',
      'mpv \u65f6\u5e8f\u5f02\u5e38\u5e27: ${mpv['mistimed-frame-count']}',
      'mpv VO \u5ef6\u8fdf\u5e27: ${mpv['vo-delayed-frame-count']}',
      'mpv VO \u6389\u5e27: ${mpv['vo-drop-frame-count']}',
      'mpv \u89e3\u7801\u6389\u5e27: ${mpv['decoder-frame-drop-count']}',
      'mpv \u603b\u6389\u5e27: ${mpv['frame-drop-count']}',
      'mpv \u7f13\u5b58\u65f6\u957f: ${mpv['demuxer-cache-duration']}',
      'mpv \u7f13\u5b58\u72b6\u6001: ${mpv['cache-buffering-state']}',
      '原生渲染请求: ${mpv['native-render-requests']}',
      '原生实际渲染帧: ${mpv['native-rendered-frames']}',
      '原生跳过渲染: ${mpv['native-skipped-renders']}',
      '原生纹理复制: ${mpv['native-texture-copies']}',
      '原生表面重建: ${mpv['native-surface-resizes']}',
      '原生表面尺寸: ${mpv['native-surface-width']}x${mpv['native-surface-height']}',
      if (mpv['native-video-plugin-state'] != 'unavailable')
        '本机增强插件: ${mpv['native-video-plugin-name']} · '
            '${mpv['native-video-plugin-state']}',
      if (mpv['native-video-plugin-state'] != 'unavailable')
        '本机增强插件帧: ${mpv['native-video-plugin-frames']} · '
            '原帧回退 ${mpv['native-video-plugin-fallbacks']}',
      if (mpv['native-video-plugin-error'] != null &&
          mpv['native-video-plugin-error']!.isNotEmpty &&
          mpv['native-video-plugin-error'] != 'unavailable')
        '本机增强插件错误: ${mpv['native-video-plugin-error']}',
      '视频帧推进: $videoProgressState',
      '视频当前帧号: ${lastVideoFrameNumber ?? -1}',
      '视频停滞事件: $videoStallEvents',
      '音频播放头推进: $audioProgressState',
      '音频当前 PTS: ${lastAudioPts?.toStringAsFixed(3) ?? 'unavailable'}',
      '音频停滞事件: $audioStallEvents',
      '独立推进采样时间: ${lastHealthSampleAt?.toIso8601String() ?? 'none'}',
      '退出请求时间: ${exitRequestedAt?.toIso8601String() ?? 'none'}',
      '暂停确认时间: ${pauseAcknowledgedAt?.toIso8601String() ?? 'none'}',
      '路由退出请求时间: ${routePopRequestedAt?.toIso8601String() ?? 'none'}',
      '最近 seek 耗时: ${lastSeekLatencyMs ?? -1} ms',
      '最近 seek 时间: ${lastSeekAt?.toIso8601String() ?? 'none'}',
      '媒体详情活动读取: ${detailsService.activeReads}',
      '媒体详情排队读取: ${detailsService.queuedReads}',
      '\u89c6\u9891\u4fe1\u606f: ${details.videoLabel}',
      '\u97f3\u9891\u4fe1\u606f: ${details.audioLabel}',
      '\u5df2\u8bc6\u522b\u89c6\u9891\u8f68: ${playerService.state.videoTrackCount}',
      '\u5df2\u8bc6\u522b\u97f3\u9891\u8f68: ${playerService.state.audioTrackCount}',
      '\u97f3\u91cf: ${playerService.state.volume.toStringAsFixed(0)}',
      '\u7f29\u7565\u56fe\u961f\u5217: ${pageWidget.thumbnailService.isPaused ? '\u5df2\u6682\u505c' : '\u8fd0\u884c\u4e2d'}',
      '\u7f29\u7565\u56fe\u6d3b\u8dc3\u4efb\u52a1: ${pageWidget.thumbnailService.activeJobs} / ${pageWidget.thumbnailService.maxConcurrentJobs}',
      '\u7f29\u7565\u56fe\u540e\u53f0\u4efb\u52a1: ${pageWidget.thumbnailService.activeBackgroundJobs} / ${pageWidget.thumbnailService.maxBackgroundJobs}',
      '\u7f29\u7565\u56fe\u6392\u961f: ${pageWidget.thumbnailService.queuedJobs}',
      '\u8fdb\u7a0b\u5185\u5b58: ${formatBytes(ProcessInfo.currentRss)}',
      '\u5904\u7406\u5668\u6838\u5fc3: ${Platform.numberOfProcessors}',
      if (openRequests.hasFailure)
        '最近打开错误类型: ${openRequests.failureCode ?? 'unknown'}',
    ];
    return PlaybackDiagnosticsSnapshot(
      lines: lines,
      sampledAt: DateTime.now(),
      wasPlaying: wasPlaying,
      wasBuffering: wasBuffering,
      progressMs: progressMs,
      expectedMs: expectedMs,
      smooth: smooth,
      avSync: parseMpvNumber(mpv['avsync']),
      mistimedFrames: parseMpvInt(mpv['mistimed-frame-count']),
      voDelayedFrames: parseMpvInt(mpv['vo-delayed-frame-count']),
      voDroppedFrames: parseMpvInt(mpv['vo-drop-frame-count']),
      decoderDroppedFrames: parseMpvInt(mpv['decoder-frame-drop-count']),
      totalDroppedFrames: parseMpvInt(mpv['frame-drop-count']),
      cacheDuration: parseMpvNumber(mpv['demuxer-cache-duration']),
      cacheBufferingState: parseMpvNumber(mpv['cache-buffering-state']),
      hwdecCurrent: lastHwdecCurrent,
      videoCodec:
          mpv['video-codec'] == 'empty' || mpv['video-codec'] == 'unavailable'
              ? details.videoCodec
              : mpv['video-codec'],
      videoWidth: details.width,
      videoHeight: details.height,
      seekLatencyMs: lastSeekLatencyMs,
      detailsQueued: detailsService.queuedReads,
      frameDurationMs: frameDurationMs,
      videoStalled: videoProgressState == '视频帧停滞',
      audioStalled: audioProgressState == '音频播放头停滞',
    );
  }
}

/** 把诊断尺寸统一格式化为整数像素或两位逻辑像素，缺失值保持明确占位。 */
String formatDiagnosticSize(
  double? width,
  double? height,
  String unit,
) {
  if (width == null || height == null) {
    return 'unavailable';
  }
  final formattedWidth =
      unit == 'px' ? width.round().toString() : width.toStringAsFixed(2);
  final formattedHeight =
      unit == 'px' ? height.round().toString() : height.toStringAsFixed(2);
  return '$formattedWidth×$formattedHeight $unit';
}

/** 把 Texture 到物理目标的横纵倍率保留三位，避免把轻微 DPI 差异隐藏为 1.0。 */
String formatDiagnosticScale(double? horizontal, double? vertical) {
  if (horizontal == null || vertical == null) {
    return 'unavailable';
  }
  return '${horizontal.toStringAsFixed(3)}×'
      '${vertical.toStringAsFixed(3)}';
}
