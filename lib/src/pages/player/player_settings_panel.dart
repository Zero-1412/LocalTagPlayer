import 'package:flutter/material.dart';

import 'player_playback_mode.dart';
import 'player_video_aspect_mode.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 显示桌面播放器设置浮层。
 *
 * 使用独立路由而不是把复杂网格塞入系统 Menu，避免 Windows 上菜单获得点击
 * 高亮但自定义内容未挂载。浮层按 [anchorRect] 锚定齿轮并本地维护选中态，
 * 同时把每次变更立即回传播放器。
 */
Future<void> showPlayerSettingsDialog(
  BuildContext context, {
  required Rect anchorRect,
  required bool mirrorVideo,
  required PlayerPlaybackMode playbackMode,
  required PlayerVideoAspectMode videoAspectMode,
  required double playbackRate,
  required List<double> playbackRates,
  required ValueChanged<bool> onMirrorVideoChanged,
  required ValueChanged<PlayerPlaybackMode> onPlaybackModeChanged,
  required ValueChanged<PlayerVideoAspectMode> onVideoAspectModeChanged,
  required ValueChanged<double> onPlaybackRateChanged,
  required VoidCallback onShowShortcuts,
  required VoidCallback onShowDiagnostics,
}) async {
  var localMirrorVideo = mirrorVideo;
  var localPlaybackMode = playbackMode;
  var localVideoAspectMode = videoAspectMode;
  var localPlaybackRate = playbackRate;
  var showAdvancedSettings = false;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭播放设置',
    barrierColor: const Color(0x33000000),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, routeAnimation, secondaryAnimation) {
      return StatefulBuilder(
        builder: (context, setDialogState) => LayoutBuilder(
          builder: (context, constraints) {
            // 浮层右边缘与齿轮右边缘对齐，并限制高度以兼容超宽矮屏全屏布局。
            final anchoredRight = constraints.maxWidth - anchorRect.right;
            final right = anchoredRight.clamp(12.0, constraints.maxWidth - 220);
            final anchoredBottom = constraints.maxHeight - anchorRect.top + 8;
            final bottom =
                anchoredBottom.clamp(12.0, constraints.maxHeight - 220);
            final maxPanelHeight =
                (constraints.maxHeight - bottom - 16).clamp(220.0, 560.0);
            final revealAnimation = CurvedAnimation(
              parent: routeAnimation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return Stack(
              children: [
                Positioned(
                  right: right,
                  bottom: bottom,
                  child: FadeTransition(
                    key: const ValueKey('player.settings.open.fade'),
                    opacity: revealAnimation,
                    child: ScaleTransition(
                      key: const ValueKey('player.settings.open.scale'),
                      alignment: Alignment.bottomRight,
                      scale: Tween<double>(begin: 0.94, end: 1).animate(
                        revealAnimation,
                      ),
                      child: Material(
                        key: const ValueKey('player.settings.dialog'),
                        color: const Color(0xf2161d29),
                        surfaceTintColor: Colors.transparent,
                        elevation: 24,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: Color(0xff34415a)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: AnimatedContainer(
                          key: const ValueKey('player.settings.shell'),
                          width: showAdvancedSettings ? 400 : 300,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: maxPanelHeight,
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      8,
                                      8,
                                      0,
                                    ),
                                    child: Row(
                                      children: [
                                        if (showAdvancedSettings)
                                          IconButton(
                                            key: const ValueKey(
                                              'player.settings.back',
                                            ),
                                            tooltip: '返回播放设置',
                                            onPressed: () => setDialogState(
                                              () =>
                                                  showAdvancedSettings = false,
                                            ),
                                            icon: const Icon(
                                              Icons.arrow_back_ios_new_rounded,
                                              size: 17,
                                            ),
                                          )
                                        else
                                          const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            showAdvancedSettings
                                                ? '更多播放设置'
                                                : '播放设置',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    key: const ValueKey(
                                      'player.settings.page.switcher',
                                    ),
                                    duration: const Duration(milliseconds: 180),
                                    transitionBuilder: (child, animation) {
                                      final enteringAdvanced = child.key ==
                                          const ValueKey(
                                            'player.settings.advanced.page',
                                          );
                                      final offsetAnimation = Tween<Offset>(
                                        begin: Offset(
                                          enteringAdvanced ? 0.12 : -0.12,
                                          0,
                                        ),
                                        end: Offset.zero,
                                      ).animate(
                                        CurvedAnimation(
                                          parent: animation,
                                          curve: Curves.easeOutCubic,
                                        ),
                                      );
                                      return FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position: offsetAnimation,
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: showAdvancedSettings
                                        ? Column(
                                            key: const ValueKey(
                                              'player.settings.advanced.page',
                                            ),
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              PlayerSettingsPanel(
                                                playbackMode: localPlaybackMode,
                                                videoAspectMode:
                                                    localVideoAspectMode,
                                                playbackRate: localPlaybackRate,
                                                playbackRates: playbackRates,
                                                onPlaybackModeChanged: (mode) {
                                                  setDialogState(
                                                    () => localPlaybackMode =
                                                        mode,
                                                  );
                                                  onPlaybackModeChanged(mode);
                                                },
                                                onVideoAspectModeChanged:
                                                    (mode) {
                                                  setDialogState(
                                                    () => localVideoAspectMode =
                                                        mode,
                                                  );
                                                  onVideoAspectModeChanged(
                                                      mode);
                                                },
                                                onPlaybackRateChanged: (rate) {
                                                  setDialogState(
                                                    () => localPlaybackRate =
                                                        rate,
                                                  );
                                                  onPlaybackRateChanged(rate);
                                                },
                                              ),
                                              const Divider(
                                                height: 1,
                                                color: Color(0xff34415a),
                                              ),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      child: TextButton.icon(
                                                        onPressed: () {
                                                          Navigator.of(
                                                            dialogContext,
                                                          ).pop();
                                                          onShowShortcuts();
                                                        },
                                                        icon: const Icon(
                                                          Icons
                                                              .keyboard_alt_outlined,
                                                          size: 18,
                                                        ),
                                                        label: const Text(
                                                          '快捷键',
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: TextButton.icon(
                                                        key: const ValueKey(
                                                          'player.diagnostics.open',
                                                        ),
                                                        onPressed: () {
                                                          Navigator.of(
                                                            dialogContext,
                                                          ).pop();
                                                          onShowDiagnostics();
                                                        },
                                                        icon: const Icon(
                                                          Icons
                                                              .monitor_heart_outlined,
                                                          size: 18,
                                                        ),
                                                        label: const Text(
                                                          '播放诊断',
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          )
                                        : PlayerSettingsPrimaryList(
                                            key: const ValueKey(
                                              'player.settings.primary.page',
                                            ),
                                            mirrorVideo: localMirrorVideo,
                                            playbackMode: localPlaybackMode,
                                            onMirrorVideoChanged: (enabled) {
                                              setDialogState(
                                                () =>
                                                    localMirrorVideo = enabled,
                                              );
                                              onMirrorVideoChanged(enabled);
                                            },
                                            onPlaybackModeChanged: (mode) {
                                              setDialogState(
                                                () => localPlaybackMode = mode,
                                              );
                                              onPlaybackModeChanged(mode);
                                            },
                                            onShowAdvancedSettings: () =>
                                                setDialogState(
                                              () => showAdvancedSettings = true,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

/**
 * 播放设置一级列表。
 *
 * 高频的镜像与循环开关保持单行可达；比例、倍速和低频入口收进二级页，避免
 * 打开设置时立即呈现大块按钮网格。循环开关互斥，关闭当前模式会回到顺序播放。
 */
class PlayerSettingsPrimaryList extends StatelessWidget {
  const PlayerSettingsPrimaryList({
    super.key,
    required this.mirrorVideo,
    required this.playbackMode,
    required this.onMirrorVideoChanged,
    required this.onPlaybackModeChanged,
    required this.onShowAdvancedSettings,
  });

  /** 是否仅水平翻转视频画面。 */
  final bool mirrorVideo;

  /** 当前队列播放方式，用于计算两个循环开关的互斥状态。 */
  final PlayerPlaybackMode playbackMode;

  /** 镜像画面开关变化回调。 */
  final ValueChanged<bool> onMirrorVideoChanged;

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
          _PlayerSettingsToggleRow(
            key: const ValueKey('player.settings.mirror'),
            label: '镜像画面',
            value: mirrorVideo,
            onChanged: onMirrorVideoChanged,
          ),
          _PlayerSettingsToggleRow(
            key: const ValueKey('player.settings.repeatOne'),
            label: '单曲循环',
            value: playbackMode == PlayerPlaybackMode.repeatOne,
            onChanged: (enabled) => onPlaybackModeChanged(
              enabled
                  ? PlayerPlaybackMode.repeatOne
                  : PlayerPlaybackMode.sequential,
            ),
          ),
          _PlayerSettingsToggleRow(
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
              borderRadius: BorderRadius.circular(7),
              child: const SizedBox(
                height: 44,
                child: Row(
                  children: [
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '更多播放设置',
                        style: TextStyle(
                          color: Color(0xfff0f3fa),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 21,
                      color: Color(0xffaeb8cc),
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
class _PlayerSettingsToggleRow extends StatelessWidget {
  const _PlayerSettingsToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  /** 设置名称。 */
  final String label;

  /** 当前开关状态。 */
  final bool value;

  /** 用户切换后的回调。 */
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xfff0f3fa),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IgnorePointer(
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: Colors.white,
                  activeTrackColor: const Color(0xff7047dc),
                  inactiveThumbColor: const Color(0xffeef1f7),
                  inactiveTrackColor: const Color(0xff596273),
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

/**
 * 播放控制条的紧凑设置面板。
 *
 * 面板只展示已经接通的播放方式、画面比例和速度，避免把未实现的解码策略或
 * 音量均衡按钮做成不可操作占位。所有选择继续由 PlayerPage 持有会话状态。
 */
class PlayerSettingsPanel extends StatelessWidget {
  const PlayerSettingsPanel({
    super.key,
    required this.playbackMode,
    required this.videoAspectMode,
    required this.playbackRate,
    required this.playbackRates,
    required this.onPlaybackModeChanged,
    required this.onVideoAspectModeChanged,
    required this.onPlaybackRateChanged,
  });

  /** 当前队列播放方式。 */
  final PlayerPlaybackMode playbackMode;

  /** 当前画面比例模式。 */
  final PlayerVideoAspectMode videoAspectMode;

  /** 当前播放倍速。 */
  final double playbackRate;

  /** 播放器允许选择的稳定倍速档位。 */
  final List<double> playbackRates;

  /** 用户选择播放方式后的回调。 */
  final ValueChanged<PlayerPlaybackMode> onPlaybackModeChanged;

  /** 用户选择画面比例后的回调。 */
  final ValueChanged<PlayerVideoAspectMode> onVideoAspectModeChanged;

  /** 用户选择倍速后的回调。 */
  final ValueChanged<double> onPlaybackRateChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('player.settings.panel'),
      width: 372,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PlayerSettingsSectionLabel('播放方式'),
            const SizedBox(height: 7),
            _PlayerSettingsChoiceGrid<PlayerPlaybackMode>(
              values: PlayerPlaybackMode.values,
              selected: playbackMode,
              columns: 2,
              labelFor: (mode) => mode.label,
              iconFor: (mode) => mode.icon,
              keyFor: (mode) => ValueKey('player.settings.mode.${mode.name}'),
              onSelected: onPlaybackModeChanged,
            ),
            const SizedBox(height: 14),
            const _PlayerSettingsSectionLabel('视频比例'),
            const SizedBox(height: 7),
            _PlayerSettingsChoiceGrid<PlayerVideoAspectMode>(
              values: PlayerVideoAspectMode.values,
              selected: videoAspectMode,
              columns: 4,
              labelFor: (mode) => mode.label,
              iconFor: (mode) => mode.icon,
              keyFor: (mode) => ValueKey('player.settings.aspect.${mode.name}'),
              onSelected: onVideoAspectModeChanged,
            ),
            const SizedBox(height: 14),
            const _PlayerSettingsSectionLabel('播放速度'),
            const SizedBox(height: 7),
            _PlayerSettingsChoiceGrid<double>(
              values: playbackRates,
              selected: playbackRate,
              columns: 3,
              labelFor: (rate) => '${rate}x',
              keyFor: (rate) => ValueKey('player.settings.rate.$rate'),
              onSelected: onPlaybackRateChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/** 设置分组标题，保持参考面板的清晰层级。 */
class _PlayerSettingsSectionLabel extends StatelessWidget {
  const _PlayerSettingsSectionLabel(this.label);

  /** 分组名称。 */
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xfff3f5fb),
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

/**
 * 可复用的设置按钮网格。
 *
 * [columns] 决定每行按钮数；使用 Wrap 而不是滚动列表，保证弹出菜单高度稳定，
 * 并让选中态立即反馈而不触发播放器主体重建以外的昂贵工作。
 */
class _PlayerSettingsChoiceGrid<T> extends StatelessWidget {
  const _PlayerSettingsChoiceGrid({
    required this.values,
    required this.selected,
    required this.columns,
    required this.labelFor,
    required this.keyFor,
    required this.onSelected,
    this.iconFor,
  });

  /** 当前分组可选择的值。 */
  final List<T> values;

  /** 当前选中的值。 */
  final T selected;

  /** 单行按钮数量。 */
  final int columns;

  /** 把值转换为按钮文案。 */
  final String Function(T value) labelFor;

  /** 为自动化与 focused test 提供稳定键。 */
  final Key Function(T value) keyFor;

  /** 可选图标映射；倍速等紧凑值不需要图标。 */
  final IconData Function(T value)? iconFor;

  /** 用户选择新值后的回调。 */
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    const spacing = 7.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final value in values)
              SizedBox(
                width: width,
                height: 36,
                child: _PlayerSettingsChoiceButton(
                  key: keyFor(value),
                  label: labelFor(value),
                  icon: iconFor?.call(value),
                  selected: value == selected,
                  onPressed: () => onSelected(value),
                ),
              ),
          ],
        );
      },
    );
  }
}

/** 单个设置选项，使用整块填充表达当前选择。 */
class _PlayerSettingsChoiceButton extends StatelessWidget {
  const _PlayerSettingsChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.icon,
  });

  /** 按钮文案。 */
  final String label;

  /** 是否为当前生效值。 */
  final bool selected;

  /** 点击选择回调。 */
  final VoidCallback onPressed;

  /** 可选的辅助图标。 */
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : const Color(0xffaeb8cc);
    return Material(
      color: selected ? const Color(0xff7047dc) : const Color(0xff263044),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: foreground),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
