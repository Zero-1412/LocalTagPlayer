import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放器当前媒体已确认从硬解回退到软件解码时的持久提示。
 *
 * 该组件不主动切换解码器，也不改变播放队列或持久化设置；它只把健康采样得到的
 * 会话状态固定展示在视频表面上，并把安全的“重新打开”和只读诊断动作交还页面。
 */
class PlayerHardwareDecodeFallbackBanner extends StatelessWidget {
  const PlayerHardwareDecodeFallbackBanner({
    super.key,
    required this.onRetry,
    required this.onDiagnostics,
    required this.requestedHwdec,
    required this.actualHwdec,
    required this.confirmedSamples,
  });

  /** 按当前硬解偏好重新进入已有 latest-only open worker。 */
  final VoidCallback onRetry;

  /** 打开当前播放器的只读诊断快照。 */
  final VoidCallback onDiagnostics;

  /** 用户请求的硬解档位，只读展示，不在此组件修改设置。 */
  final String requestedHwdec;

  /** mpv 实际回报的解码器；为空时保留“no/未知”语义，不猜测硬解。 */
  final String? actualHwdec;

  /** 连续确认软件解码的健康采样数，阈值由页面健康采样器控制。 */
  final int confirmedSamples;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '当前视频已回退为软件解码，实际解码器 ${actualHwdec ?? 'no'}，'
          '画面可能不够流畅',
      child: Material(
        color: Colors.transparent,
        child: Container(
          key: const ValueKey('player.hardwareDecodeFallback.banner'),
          constraints: const BoxConstraints(maxWidth: 430),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: playerSurfaceRaised.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(AppRadius.floating),
            border: Border.all(color: playerDanger.withValues(alpha: 0.82)),
            boxShadow: playerSoftShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.memory_rounded,
                size: 20,
                color: playerDanger,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '已回退为软件解码，画面可能卡顿',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: playerText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '请求 $requestedHwdec · 实际 ${actualHwdec ?? 'no'} · '
                      '确认 $confirmedSamples/3',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: playerTextMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('player.hardwareDecodeFallback.retry'),
                onPressed: onRetry,
                child: const Text('重新打开'),
              ),
              IconButton(
                key: const ValueKey(
                  'player.hardwareDecodeFallback.diagnostics',
                ),
                tooltip: '诊断详情',
                onPressed: onDiagnostics,
                icon: const Icon(Icons.monitor_heart_outlined),
                color: playerTextMuted,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
