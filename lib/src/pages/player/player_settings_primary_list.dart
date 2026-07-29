import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';
import 'player_playback_mode.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放设置一级列表。
 *
 * 一级页只保留循环方式和“更多”入口。NVIDIA VSR/HDR 由 Windows 原生后端
 * 自动协商；循环开关互斥，关闭当前模式会回到顺序播放。
 */
class PlayerSettingsPrimaryList extends StatelessWidget {
  const PlayerSettingsPrimaryList({
    super.key,
    required this.playbackMode,
    required this.onPlaybackModeChanged,
    required this.onShowAdvancedSettings,
  });

  /** 当前队列播放方式，用于计算两个循环开关的互斥状态。 */
  final PlayerPlaybackMode playbackMode;

  /** 循环方式变化回调。 */
  final ValueChanged<PlayerPlaybackMode> onPlaybackModeChanged;

  /** 进入二级播放设置的回调。 */
  final VoidCallback onShowAdvancedSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerSettingsToggleRow(
            key: const ValueKey('player.settings.repeatOne'),
            label: '单曲循环',
            value: playbackMode == PlayerPlaybackMode.repeatOne,
            onChanged: (enabled) => onPlaybackModeChanged(
              enabled
                  ? PlayerPlaybackMode.repeatOne
                  : PlayerPlaybackMode.sequential,
            ),
          ),
          PlayerSettingsToggleRow(
            key: const ValueKey('player.settings.repeatAll'),
            label: '列表循环',
            value: playbackMode == PlayerPlaybackMode.repeatAll,
            onChanged: (enabled) => onPlaybackModeChanged(
              enabled
                  ? PlayerPlaybackMode.repeatAll
                  : PlayerPlaybackMode.sequential,
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('player.settings.advanced.open'),
              onTap: onShowAdvancedSettings,
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: const SizedBox(
                height: 44,
                child: Row(
                  children: [
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '更多播放设置',
                        style: TextStyle(
                          color: playerText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 21,
                      color: playerTextMuted,
                    ),
                    SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/** 一级列表中的整行开关，整行均可点击以扩大操作范围。 */
class PlayerSettingsToggleRow extends StatelessWidget {
  const PlayerSettingsToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  /** 设置名称。 */
  final String label;

  /** 可选的性能边界说明；不提供时保持原有紧凑行高。 */
  final String? subtitle;

  /** 当前开关状态。 */
  final bool value;

  /** 用户切换后的回调。 */
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: SizedBox(
          // 带说明的长能力名称允许自然换行；72px 可完整容纳两行名称和一行边界说明。
          height: subtitle == null ? 44 : 72,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: playerText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: playerTextMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              IgnorePointer(
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: Colors.white,
                  activeTrackColor: appAccentViolet,
                  inactiveThumbColor: playerText,
                  inactiveTrackColor: playerTextMuted,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
