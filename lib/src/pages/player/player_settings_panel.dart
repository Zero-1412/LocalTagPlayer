import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';
import 'player_playback_mode.dart';
import 'player_video_aspect_mode.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 显示桌面播放器设置浮层。
 *
 * 使用独立路由而不是把复杂列表塞入系统 Menu，避免 Windows 上菜单获得点击
 * 高亮但自定义内容未挂载。一级保留镜像、GPU 超分与循环开关，二级只承担
 * 比例/倍速导航和离散快进档位；具体选项进入三级列表或滑杆，每次变更立即回传播放器。
 */
Future<void> showPlayerSettingsDialog(
  BuildContext context, {
  required Rect anchorRect,
  required bool mirrorVideo,
  required PlayerPlaybackMode playbackMode,
  required PlayerVideoAspectMode videoAspectMode,
  required double playbackRate,
  required int seekStepSeconds,
  required bool videoSuperResolutionEnabled,
  required List<double> playbackRates,
  required List<int> seekStepOptions,
  required ValueChanged<bool> onMirrorVideoChanged,
  required ValueChanged<PlayerPlaybackMode> onPlaybackModeChanged,
  required ValueChanged<PlayerVideoAspectMode> onVideoAspectModeChanged,
  required ValueChanged<double> onPlaybackRateChanged,
  required ValueChanged<int> onSeekStepChanged,
  required ValueChanged<bool> onVideoSuperResolutionChanged,
}) async {
  final accessibility = AppAccessibilityScope.of(context);
  var localMirrorVideo = mirrorVideo;
  var localPlaybackMode = playbackMode;
  var localVideoAspectMode = videoAspectMode;
  var localPlaybackRate = playbackRate;
  var localSeekStepSeconds = seekStepSeconds;
  var localVideoSuperResolutionEnabled = videoSuperResolutionEnabled;
  var currentPage = _PlayerSettingsPage.primary;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭播放设置',
    barrierColor: const Color(0x33000000),
    transitionDuration: accessibility.motionDuration(AppMotion.popover),
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
                      scale: Tween<double>(
                        begin: accessibility.reduceMotion ? 1 : 0.97,
                        end: 1,
                      ).animate(
                        revealAnimation,
                      ),
                      child: Material(
                        key: const ValueKey('player.settings.dialog'),
                        color: playerSurface.withValues(
                          alpha: AppMaterialOpacity.floating,
                        ),
                        surfaceTintColor: Colors.transparent,
                        elevation: 18,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.floating),
                          side: const BorderSide(color: playerBorder),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: AnimatedContainer(
                          key: const ValueKey('player.settings.shell'),
                          width: 300,
                          duration:
                              accessibility.motionDuration(AppMotion.popover),
                          curve: AppMotion.standardCurve,
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
                                        if (currentPage !=
                                            _PlayerSettingsPage.primary)
                                          IconButton(
                                            key: const ValueKey(
                                              'player.settings.back',
                                            ),
                                            tooltip: currentPage.parentTitle,
                                            onPressed: () => setDialogState(() {
                                              currentPage =
                                                  currentPage.parentPage;
                                            }),
                                            icon: const Icon(
                                              Icons.arrow_back_ios_new_rounded,
                                              size: 17,
                                            ),
                                          )
                                        else
                                          const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            currentPage.title,
                                            style: const TextStyle(
                                              color: playerText,
                                              fontSize: 15,
                                              fontWeight: AppTypography.strong,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                    ),
                                  ),
                                  KeyedSubtree(
                                    key: const ValueKey(
                                      'player.settings.page.host',
                                    ),
                                    // Windows 播放纹理上叠加新旧设置页会偶发触发
                                    // Flutter engine 访问异常；页内导航直接换树，浮层
                                    // 本身的打开/关闭动画已足够表达空间连续性。
                                    child: switch (currentPage) {
                                      _PlayerSettingsPage.primary =>
                                        PlayerSettingsPrimaryList(
                                          key: const ValueKey(
                                            'player.settings.primary.page',
                                          ),
                                          mirrorVideo: localMirrorVideo,
                                          videoSuperResolutionEnabled:
                                              localVideoSuperResolutionEnabled,
                                          playbackMode: localPlaybackMode,
                                          onMirrorVideoChanged: (enabled) {
                                            setDialogState(
                                              () => localMirrorVideo = enabled,
                                            );
                                            onMirrorVideoChanged(enabled);
                                          },
                                          onPlaybackModeChanged: (mode) {
                                            setDialogState(
                                              () => localPlaybackMode = mode,
                                            );
                                            onPlaybackModeChanged(mode);
                                          },
                                          onVideoSuperResolutionChanged:
                                              (enabled) {
                                            setDialogState(
                                              () =>
                                                  localVideoSuperResolutionEnabled =
                                                      enabled,
                                            );
                                            onVideoSuperResolutionChanged(
                                              enabled,
                                            );
                                          },
                                          onShowAdvancedSettings: () =>
                                              setDialogState(
                                            () => currentPage =
                                                _PlayerSettingsPage.advanced,
                                          ),
                                        ),
                                      _PlayerSettingsPage.advanced =>
                                        PlayerSettingsAdvancedList(
                                          key: const ValueKey(
                                            'player.settings.advanced.page',
                                          ),
                                          videoAspectMode: localVideoAspectMode,
                                          playbackRate: localPlaybackRate,
                                          seekStepSeconds: localSeekStepSeconds,
                                          seekStepOptions: seekStepOptions,
                                          onShowVideoAspect: () =>
                                              setDialogState(
                                            () => currentPage =
                                                _PlayerSettingsPage.aspect,
                                          ),
                                          onShowPlaybackRate: () =>
                                              setDialogState(
                                            () => currentPage =
                                                _PlayerSettingsPage.rate,
                                          ),
                                          onSeekStepChanged: (seconds) {
                                            setDialogState(
                                              () => localSeekStepSeconds =
                                                  seconds,
                                            );
                                            onSeekStepChanged(seconds);
                                          },
                                        ),
                                      _PlayerSettingsPage.aspect =>
                                        PlayerSettingsOptionList<
                                            PlayerVideoAspectMode>(
                                          key: const ValueKey(
                                            'player.settings.aspect.page',
                                          ),
                                          values: PlayerVideoAspectMode.values,
                                          selected: localVideoAspectMode,
                                          labelFor: (mode) => mode.label,
                                          iconFor: (mode) => mode.icon,
                                          keyFor: (mode) => ValueKey(
                                            'player.settings.aspect.${mode.name}',
                                          ),
                                          onSelected: (mode) {
                                            setDialogState(
                                              () => localVideoAspectMode = mode,
                                            );
                                            onVideoAspectModeChanged(mode);
                                          },
                                        ),
                                      _PlayerSettingsPage.rate =>
                                        PlayerSettingsOptionList<double>(
                                          key: const ValueKey(
                                            'player.settings.rate.page',
                                          ),
                                          values: playbackRates,
                                          selected: localPlaybackRate,
                                          labelFor: (rate) => '${rate}x',
                                          keyFor: (rate) => ValueKey(
                                            'player.settings.rate.$rate',
                                          ),
                                          onSelected: (rate) {
                                            setDialogState(
                                              () => localPlaybackRate = rate,
                                            );
                                            onPlaybackRateChanged(rate);
                                          },
                                        ),
                                    },
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

/** 播放设置浮层的页级导航状态。 */
enum _PlayerSettingsPage { primary, advanced, aspect, rate }

/** 播放设置页标题与返回目标，避免各分支复制导航规则。 */
extension on _PlayerSettingsPage {
  String get title => switch (this) {
        _PlayerSettingsPage.primary => '播放设置',
        _PlayerSettingsPage.advanced => '更多播放设置',
        _PlayerSettingsPage.aspect => '视频比例',
        _PlayerSettingsPage.rate => '播放速度',
      };

  _PlayerSettingsPage get parentPage => switch (this) {
        _PlayerSettingsPage.primary => _PlayerSettingsPage.primary,
        _PlayerSettingsPage.advanced => _PlayerSettingsPage.primary,
        _PlayerSettingsPage.aspect ||
        _PlayerSettingsPage.rate =>
          _PlayerSettingsPage.advanced,
      };

  String get parentTitle => switch (parentPage) {
        _PlayerSettingsPage.primary => '返回播放设置',
        _PlayerSettingsPage.advanced => '返回更多播放设置',
        _ => '返回',
      };
}

/**
 * 播放设置一级列表。
 *
 * 高频的镜像与循环开关保持单行可达；比例、倍速和低频入口收进二级页，避免
 * 打开设置时立即呈现大块按钮网格。GPU 超分保留在一级，便于用户在播放中快速
 * 对比和关闭；循环开关互斥，关闭当前模式会回到顺序播放。
 */
class PlayerSettingsPrimaryList extends StatelessWidget {
  const PlayerSettingsPrimaryList({
    super.key,
    required this.mirrorVideo,
    required this.videoSuperResolutionEnabled,
    required this.playbackMode,
    required this.onMirrorVideoChanged,
    required this.onVideoSuperResolutionChanged,
    required this.onPlaybackModeChanged,
    required this.onShowAdvancedSettings,
  });

  /** 是否仅水平翻转视频画面。 */
  final bool mirrorVideo;

  /** 是否使用仅在画面放大时运行的本地 GPU 高质量超分。 */
  final bool videoSuperResolutionEnabled;

  /** 当前队列播放方式，用于计算两个循环开关的互斥状态。 */
  final PlayerPlaybackMode playbackMode;

  /** 镜像画面开关变化回调。 */
  final ValueChanged<bool> onMirrorVideoChanged;

  /** GPU 画质超分开关变化回调。 */
  final ValueChanged<bool> onVideoSuperResolutionChanged;

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
            key: const ValueKey('player.settings.superResolution'),
            label: 'GPU 画质超分',
            subtitle: '仅放大低分辨率画面',
            value: videoSuperResolutionEnabled,
            onChanged: onVideoSuperResolutionChanged,
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
class _PlayerSettingsToggleRow extends StatelessWidget {
  const _PlayerSettingsToggleRow({
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
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: SizedBox(
          height: subtitle == null ? 44 : 58,
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

/**
 * 更多播放设置的二级导航列表。
 *
 * 播放方式只保留在一级循环开关中；快捷键与播放诊断不再属于该浮层。比例和
 * 倍速只展示当前值，点击后进入各自独立的三级选择列表；快进档位直接使用离散
 * 滑杆，调整时只回传一个固定秒数，不触发播放或队列计算。
 */
class PlayerSettingsAdvancedList extends StatelessWidget {
  const PlayerSettingsAdvancedList({
    super.key,
    required this.videoAspectMode,
    required this.playbackRate,
    required this.seekStepSeconds,
    required this.seekStepOptions,
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
          _PlayerSettingsNavigationRow(
            key: const ValueKey('player.settings.aspect.open'),
            label: '视频比例',
            value: videoAspectMode.label,
            onTap: onShowVideoAspect,
          ),
          _PlayerSettingsNavigationRow(
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

/** 二级设置中的导航行，右侧同时展示当前已经生效的全局值。 */
class _PlayerSettingsNavigationRow extends StatelessWidget {
  const _PlayerSettingsNavigationRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  /** 设置名称。 */
  final String label;

  /** 当前生效值。 */
  final String value;

  /** 进入下一层列表的回调。 */
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: playerText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: playerTextMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 21,
                color: playerTextMuted,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/**
 * 单一设置项的三级选择列表。
 *
 * 选项数量很小，使用固定行高直接构建；选择只重绘浮层与视频表面，不触发
 * filtered queue、媒体详情或缩略图队列重算。
 */
class PlayerSettingsOptionList<T> extends StatelessWidget {
  const PlayerSettingsOptionList({
    super.key,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.keyFor,
    required this.onSelected,
    this.iconFor,
  });

  /** 当前列表允许选择的稳定值。 */
  final List<T> values;

  /** 当前已经生效的值。 */
  final T selected;

  /** 将设置值转换为用户可读文案。 */
  final String Function(T value) labelFor;

  /** 为 focused test 和自动化点击提供稳定键。 */
  final Key Function(T value) keyFor;

  /** 用户选择新值后的回调。 */
  final ValueChanged<T> onSelected;

  /** 可选的辅助图标映射；倍速列表无需图标。 */
  final IconData Function(T value)? iconFor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in values)
            _PlayerSettingsOptionRow(
              key: keyFor(value),
              label: labelFor(value),
              icon: iconFor?.call(value),
              selected: value == selected,
              onTap: () => onSelected(value),
            ),
        ],
      ),
    );
  }
}

/** 三级列表的单个选项；勾选标记明确表示当前真实生效状态。 */
class _PlayerSettingsOptionRow extends StatelessWidget {
  const _PlayerSettingsOptionRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  /** 选项文案。 */
  final String label;

  /** 是否为当前全局值。 */
  final bool selected;

  /** 点击选择回调。 */
  final VoidCallback onTap;

  /** 可选的比例模式图标。 */
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? playerText : playerTextMuted;
    return Material(
      color: selected
          ? appAccentViolet.withValues(alpha: 0.20)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 12),
              if (icon != null) ...[
                Icon(icon, size: 17, color: foreground),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  size: 19,
                  color: appAccentViolet,
                ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}
