import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/playback_settings.dart'
    show PlaybackSettings, PlayerCompressionEnhancementMode;
import '../../widgets/app_theme_tokens.dart';
import 'player_settings_option_list.dart';
import 'player_settings_primary_list.dart';
import 'player_video_aspect_mode.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 更多播放设置的二级导航列表。
 *
 * 低频画面选项与比例、倍速集中在该页；三个迁移入口保留原键、回调和状态，
 * 只改变页级挂载。比例、倍速和压缩增强进入各自三级列表；快进档位直接使用
 * 离散滑杆，调整时只回传一个固定秒数，不触发播放或队列计算。
 */
class PlayerSettingsAdvancedList extends StatelessWidget {
  const PlayerSettingsAdvancedList({
    super.key,
    required this.videoAspectMode,
    required this.playbackRate,
    required this.seekStepSeconds,
    required this.seekStepOptions,
    required this.mirrorVideo,
    required this.mpvEnhancementsAvailable,
    required this.videoSuperResolutionEnabled,
    required this.compressionEnhancementMode,
    required this.onMirrorVideoChanged,
    required this.onVideoSuperResolutionChanged,
    required this.onShowCompressionEnhancement,
    required this.onShowVideoAspect,
    required this.onShowPlaybackRate,
    required this.onSeekStepChanged,
  });

  /** 当前全局画面比例。 */
  final PlayerVideoAspectMode videoAspectMode;

  /** 当前全局播放倍速。 */
  final double playbackRate;

  /** 当前快进与快退共用的秒数。 */
  final int seekStepSeconds;

  /** 滑杆允许选择的稳定快进档位。 */
  final List<int> seekStepOptions;

  /** 是否仅水平翻转视频画面。 */
  final bool mirrorVideo;

  /** 当前正式后端是否提供同实例 libmpv 高级属性。 */
  final bool mpvEnhancementsAvailable;

  /** 是否使用仅在画面放大时运行的 libmpv GPU 高质量缩放；该能力不是 NVIDIA AI。 */
  final bool videoSuperResolutionEnabled;

  /** 当前压缩画质增强档位。 */
  final PlayerCompressionEnhancementMode compressionEnhancementMode;

  /** 镜像画面开关变化回调。 */
  final ValueChanged<bool> onMirrorVideoChanged;

  /** GPU 高质量缩放开关变化回调；保留既有设置键和持久化语义。 */
  final ValueChanged<bool> onVideoSuperResolutionChanged;

  /** 打开压缩画质增强档位列表。 */
  final VoidCallback onShowCompressionEnhancement;

  /** 进入画面比例三级列表的回调。 */
  final VoidCallback onShowVideoAspect;

  /** 进入播放倍速三级列表的回调。 */
  final VoidCallback onShowPlaybackRate;

  /** 用户在离散滑杆上选择新档位后的回调。 */
  final ValueChanged<int> onSeekStepChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerSettingsToggleRow(
            key: const ValueKey('player.settings.mirror'),
            label: '镜像画面',
            value: mirrorVideo,
            onChanged: onMirrorVideoChanged,
          ),
          if (mpvEnhancementsAvailable)
            PlayerSettingsToggleRow(
              key: const ValueKey('player.settings.superResolution'),
              label: 'GPU 高质量缩放（非 NVIDIA AI）',
              subtitle: 'libmpv 缩放，仅在画面放大时生效',
              value: videoSuperResolutionEnabled,
              onChanged: onVideoSuperResolutionChanged,
            ),
          PlayerSettingsNavigationRow(
            key: const ValueKey('player.settings.compression.open'),
            label: '压缩画质增强',
            value: PlaybackSettings.compressionEnhancementLabelFor(
              compressionEnhancementMode,
            ),
            onTap: onShowCompressionEnhancement,
          ),
          PlayerSettingsNavigationRow(
            key: const ValueKey('player.settings.aspect.open'),
            label: '视频比例',
            value: videoAspectMode.label,
            onTap: onShowVideoAspect,
          ),
          PlayerSettingsNavigationRow(
            key: const ValueKey('player.settings.rate.open'),
            label: '播放速度',
            value: '${playbackRate}x',
            onTap: onShowPlaybackRate,
          ),
          PlayerSeekStepSlider(
            selectedSeconds: seekStepSeconds,
            options: seekStepOptions,
            onChanged: onSeekStepChanged,
          ),
        ],
      ),
    );
  }
}

/**
 * 更多播放设置中的离散快进档位滑杆。
 *
 * 滑杆内部使用档位索引而不是任意秒数，确保拖动期间只产生五个稳定值；语义标签
 * 同时报告当前秒数，便于键盘和屏幕阅读器确认真实生效状态。
 */
class PlayerSeekStepSlider extends StatelessWidget {
  const PlayerSeekStepSlider({
    super.key,
    required this.selectedSeconds,
    required this.options,
    required this.onChanged,
  });

  /** 当前已经生效的跳转秒数。 */
  final int selectedSeconds;

  /** 由播放设置公开的有序固定档位。 */
  final List<int> options;

  /** 新档位即时生效并持久化的回调。 */
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeOptions = options.isEmpty ? const <int>[5] : options;
    final selectedIndex = safeOptions.indexOf(selectedSeconds);
    final value = (selectedIndex < 0 ? 0 : selectedIndex).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '快进 / 快退时间',
                  style: TextStyle(
                    color: playerText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$selectedSeconds 秒',
                key: const ValueKey('player.settings.seekStep.value'),
                style: const TextStyle(
                  color: playerTextMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Semantics(
            label: '快进和快退时间，当前 $selectedSeconds 秒',
            child: Slider(
              key: const ValueKey('player.settings.seekStep.slider'),
              value: value,
              min: 0,
              max: math.max(1, safeOptions.length - 1).toDouble(),
              divisions: safeOptions.length > 1 ? safeOptions.length - 1 : 1,
              label: '$selectedSeconds 秒',
              onChanged: safeOptions.length <= 1
                  ? null
                  : (rawValue) {
                      final index = rawValue.round().clamp(
                            0,
                            safeOptions.length - 1,
                          );
                      onChanged(safeOptions[index]);
                    },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final seconds in safeOptions)
                Text(
                  '$seconds',
                  style: const TextStyle(
                    color: playerTextMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
