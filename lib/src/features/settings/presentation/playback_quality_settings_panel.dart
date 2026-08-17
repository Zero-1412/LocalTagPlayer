import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/playback_settings.dart';
import '../../../widgets/app_theme_tokens.dart';
import 'settings_workspace_theme.dart';

// ignore_for_file: slash_for_doc_comments

/** 视频画质与增强工作区；只保存播放会话参数，不在设置页启动解码或媒体库重算。 */
class PlaybackQualitySettingsPanel extends StatelessWidget {
  const PlaybackQualitySettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
  });
  /** 当前播放设置快照。 */
  final PlaybackSettings settings;
  /** 保存完整设置快照，确保连续修改不会丢失其它字段。 */
  final ValueChanged<PlaybackSettings> onChanged;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('settings.playbackQuality.card'),
      container: true,
      label: '视频画质与增强工作区',
      child: Material(
        key: const ValueKey('settings.playbackQuality.workspaceSurface'),
        color: librarySurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.panel)),
          side: BorderSide(color: libraryBorder),
        ),
        // 保留 Material 状态层，让下拉、开关和确认反馈继续提供 focus/ink 反馈。
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '视频质量与渲染',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                '第一阶段能力默认以流畅播放为边界；高开销增强不在 UI 线程处理视频帧。',
                style: TextStyle(color: libraryTextMuted, height: 1.45),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<PlayerVideoAspectMode>(
                key: const ValueKey('settings.playbackQuality.aspect'),
                initialValue: settings.videoAspectMode,
                decoration: const InputDecoration(labelText: '画面比例'),
                items: [
                  for (final mode in PlayerVideoAspectMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(PlaybackSettings.videoAspectLabelFor(mode)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onChanged(settings.copyWith(videoAspectMode: value));
                  }
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<PlayerVideoScaler>(
                key: const ValueKey('settings.playbackQuality.scaler'),
                initialValue: settings.videoScaler,
                decoration: const InputDecoration(labelText: '高质量缩放'),
                items: [
                  for (final scaler in PlayerVideoScaler.values)
                    DropdownMenuItem(
                      value: scaler,
                      child: Text(PlaybackSettings.videoScalerLabelFor(scaler)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onChanged(settings.copyWith(videoScaler: value));
                  }
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<PlayerVideoOutputRange>(
                key: const ValueKey('settings.playbackQuality.outputRange'),
                initialValue: settings.videoOutputRange,
                decoration: const InputDecoration(labelText: '输出色彩范围'),
                items: [
                  for (final range in PlayerVideoOutputRange.values)
                    DropdownMenuItem(
                      value: range,
                      child: Text(
                          PlaybackSettings.videoOutputRangeLabelFor(range)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onChanged(settings.copyWith(videoOutputRange: value));
                  }
                },
              ),
              const SizedBox(height: 16),
              PlaybackSmoothMotionDropdown(
                settings: settings,
                onChanged: onChanged,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<PlayerCompressionEnhancementMode>(
                key: const ValueKey(
                  'settings.playbackQuality.automaticEnhancement',
                ),
                initialValue: settings.compressionEnhancementMode,
                decoration: const InputDecoration(
                  labelText: '压缩画质增强',
                  helperText: '自动按播放余量逐级增强；清晰增强优先请求当前设备的最高安全档',
                ),
                items: [
                  for (final mode in PlayerCompressionEnhancementMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(
                        PlaybackSettings.compressionEnhancementLabelFor(mode),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onChanged(
                      settings.copyWith(compressionEnhancementMode: value),
                    );
                  }
                },
              ),
              const Divider(height: 20),
              SwitchListTile.adaptive(
                key: const ValueKey(
                  'settings.playbackQuality.darkSceneEnhancement',
                ),
                contentPadding: EdgeInsets.zero,
                value: settings.darkSceneEnhancementEnabled,
                title: const Text('暗部细节增强'),
                subtitle: const Text(
                  '仅对已确认的 SDR、1080p 及以下硬解视频启用保守暗部曲线；出现播放压力时当前会话自动回滚',
                ),
                onChanged: (value) => onChanged(
                  settings.copyWith(darkSceneEnhancementEnabled: value),
                ),
              ),
              const Divider(height: 20),
              SwitchListTile.adaptive(
                key: const ValueKey(
                  'settings.playbackQuality.hdrMappingExperiment',
                ),
                contentPadding: EdgeInsets.zero,
                value: settings.hdrDynamicToneMappingExperimentEnabled,
                title: const Text('HDR 转 SDR 色调映射（兼容显示）'),
                subtitle: const Text(
                  '把 HDR 视频映射到兼容显示输出；不会开启 Windows HDR 或 NVIDIA RTX Video HDR，播放压力出现时自动回滚',
                ),
                onChanged: (value) async {
                  if (!value) {
                    onChanged(
                      settings.copyWith(
                        hdrDynamicToneMappingExperimentEnabled: false,
                      ),
                    );
                    return;
                  }
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('开启 HDR 转 SDR 色调映射？'),
                      content: const Text(
                        '该功能会为通过能力门槛的 HDR 视频启用 Hable 映射与逐帧峰值检测，以适配兼容显示输出。它不会开启 Windows HDR，也不是 NVIDIA RTX Video HDR；若出现掉帧或观感异常，可关闭并恢复 mpv 自动值。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          key: const ValueKey(
                            'settings.playbackQuality.hdrMappingConfirm',
                          ),
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: const Text('确认开启'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    onChanged(
                      settings.copyWith(
                        hdrDynamicToneMappingExperimentEnabled: true,
                      ),
                    );
                  }
                },
              ),
              const Divider(height: 20),
              const _PlaybackCapabilityRow(
                icon: Icons.analytics_outlined,
                title: '视频质量信息解析',
                subtitle: 'FFprobe 缓存解析编码、分辨率、时长；播放诊断读取实时色彩参数',
                status: '已启用',
              ),
              const _PlaybackCapabilityRow(
                icon: Icons.monitor_heart_outlined,
                title: '解码与丢帧诊断',
                subtitle: '播放器诊断可核验实际硬解、缓存、解码/输出/总丢帧及色彩范围',
                status: '已启用',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/**
 * 需要确认和可撤销路径的流畅度增强选择器。
 *
 * 启用只保存类型化偏好，下次进入播放器后由 PlayerService 配置具体后端；弹窗等待
 * 期间组件若被移除，不得再更新旧 Route 或触发持久化。
 */
class PlaybackSmoothMotionDropdown extends StatefulWidget {
  const PlaybackSmoothMotionDropdown({
    super.key,
    required this.settings,
    required this.onChanged,
  });
  /** 当前应用级播放设置快照。 */
  final PlaybackSettings settings;
  /** 把确认后的完整设置交还设置页统一持久化。 */
  final ValueChanged<PlaybackSettings> onChanged;
  @override
  State<PlaybackSmoothMotionDropdown> createState() =>
      _PlaybackSmoothMotionDropdownState();
}

/** 管理确认弹窗生命周期与撤销动作，不持有播放器后端。 */
class _PlaybackSmoothMotionDropdownState
    extends State<PlaybackSmoothMotionDropdown> {
  /** 处理用户选择；只有确认启用后才修改应用级设置。 */
  Future<void> _changeMode(PlayerSmoothMotionMode mode) async {
    final previous = widget.settings;
    if (mode == previous.smoothMotionMode) return;
    if (mode == PlayerSmoothMotionMode.displayInterpolation) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('启用显示同步插值？'),
          content: const Text(
            '它会用相邻原始帧缓解帧率与屏幕刷新率不匹配的顿挫，'
            '不是 NVIDIA 或其它 AI 生成中间帧。播放压力出现时只回滚当前视频。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('启用'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    final next = previous.copyWith(smoothMotionMode: mode);
    widget.onChanged(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '流畅度提升已设为 ${PlaybackSettings.smoothMotionLabelFor(mode)}，'
            '下次进入播放器生效',
          ),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => widget.onChanged(previous),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.settings.smoothMotionMode;
    return DropdownButtonFormField<PlayerSmoothMotionMode>(
      key: ValueKey('settings.playbackQuality.smoothMotion.${mode.name}'),
      initialValue: mode,
      decoration: InputDecoration(
        labelText: '流畅度提升',
        helperText: PlaybackSettings.smoothMotionDescriptionFor(mode),
      ),
      items: [
        for (final option in PlayerSmoothMotionMode.values)
          DropdownMenuItem(
            value: option,
            child: Text(PlaybackSettings.smoothMotionLabelFor(option)),
          ),
      ],
      onChanged: (value) {
        if (value != null) unawaited(_changeMode(value));
      },
    );
  }
}

/** 设置页中的只读能力状态行，避免尚未实现的能力伪装成可操作开关。 */
class _PlaybackCapabilityRow extends StatelessWidget {
  const _PlaybackCapabilityRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: appAccentViolet),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(
        status,
        style: const TextStyle(
          color: appAccentViolet,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/** 构建播放画质设置 focused test 容器，不创建播放器或运行 Compute 基线。 */
@visibleForTesting
Widget playbackQualitySettingsSmokeHarness({
  PlaybackSettings settings = PlaybackSettings.defaults,
  ValueChanged<PlaybackSettings>? onChanged,
}) {
  return MaterialApp(
    theme: settingsWorkspaceTheme(ThemeData(useMaterial3: true)),
    home: MediaQuery(
      data: const MediaQueryData(size: Size(900, 900)),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: PlaybackQualitySettingsPanel(
            settings: settings,
            onChanged: onChanged ?? (_) {},
          ),
        ),
      ),
    ),
  );
}
