import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/playback_settings.dart'
    show PlaybackSettings, PlayerCompressionEnhancementMode;
import '../../widgets/app_theme_tokens.dart';
import 'player_playback_mode.dart';
import 'player_video_aspect_mode.dart';
import 'player_settings_advanced_list.dart';
import 'player_settings_option_list.dart';
import 'player_settings_primary_list.dart';

export 'player_settings_advanced_list.dart';
export 'player_settings_option_list.dart';
export 'player_settings_primary_list.dart';

// ignore_for_file: slash_for_doc_comments

/** 播放设置浮层的固定内容宽度。 */
const double playerSettingsPanelWidth = 300;

/**
 * 计算设置浮层距窗口右边缘的位置，并保证整个固定宽度面板留在可视区。
 *
 * 紧凑控制条会把齿轮移到靠左的第三行；只对齐齿轮右边缘会产生负 left，
 * 因此这里同时限制右侧偏移的上界。
 */
double playerSettingsPanelRight({
  required double availableWidth,
  required Rect anchorRect,
}) {
  const margin = 12.0;
  final anchoredRight = availableWidth - anchorRect.right;
  final maximumRight = math.max(
    margin,
    availableWidth - playerSettingsPanelWidth - margin,
  );
  return anchoredRight.clamp(margin, maximumRight);
}

/**
 * 显示桌面播放器设置浮层。
 *
 * 使用独立路由而不是把复杂列表塞入系统 Menu，避免 Windows 上菜单获得点击
 * 高亮但自定义内容未挂载。一级只保留循环开关与“更多”入口，二级承担镜像、
 * GPU 缩放、压缩增强、比例/倍速导航和离散快进档位。正式 MediaKit Texture
 * 不宣称或自动协商 NVIDIA VSR/HDR；原生 D3D11 能力只留在隔离 QA 后端。
 */
Future<void> showPlayerSettingsDialog(
  BuildContext context, {
  required Rect anchorRect,
  required bool mirrorVideo,
  required PlayerPlaybackMode playbackMode,
  required PlayerVideoAspectMode videoAspectMode,
  required double playbackRate,
  required int seekStepSeconds,
  required bool mpvEnhancementsAvailable,
  required bool videoSuperResolutionEnabled,
  required PlayerCompressionEnhancementMode compressionEnhancementMode,
  required List<double> playbackRates,
  required List<int> seekStepOptions,
  required ValueChanged<bool> onMirrorVideoChanged,
  required ValueChanged<PlayerPlaybackMode> onPlaybackModeChanged,
  required ValueChanged<PlayerVideoAspectMode> onVideoAspectModeChanged,
  required ValueChanged<double> onPlaybackRateChanged,
  required ValueChanged<int> onSeekStepChanged,
  required ValueChanged<bool> onVideoSuperResolutionChanged,
  required ValueChanged<PlayerCompressionEnhancementMode>
      onCompressionEnhancementModeChanged,
  ValueChanged<Rect>? onBoundsChanged,
}) async {
  final accessibility = AppAccessibilityScope.of(context);
  Rect? lastReportedBounds;
  /** 把真实动画后面板矩形回传给原生 airspace，避免用估算尺寸裁掉实时视频。 */
  void reportPanelBounds(BuildContext rootContext) {
    if (onBoundsChanged == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RenderBox? renderObject;
      void findPanel(Element element) {
        if (renderObject != null) return;
        if (element.widget.key ==
            const ValueKey<String>('player.settings.dialog')) {
          renderObject = element.findRenderObject() as RenderBox?;
          return;
        }
        element.visitChildren(findPanel);
      }

      (rootContext as Element).visitChildren(findPanel);
      final panel = renderObject;
      if (panel == null || !panel.hasSize) return;
      final bounds = panel.localToGlobal(Offset.zero) & panel.size;
      if (bounds == lastReportedBounds) return;
      lastReportedBounds = bounds;
      onBoundsChanged(bounds);
    });
  }

  var localMirrorVideo = mirrorVideo;
  var localPlaybackMode = playbackMode;
  var localVideoAspectMode = videoAspectMode;
  var localPlaybackRate = playbackRate;
  var localSeekStepSeconds = seekStepSeconds;
  var localVideoSuperResolutionEnabled = videoSuperResolutionEnabled;
  var localCompressionEnhancementMode = compressionEnhancementMode;
  var currentPage = _PlayerSettingsPage.primary;
  var routeBoundsListenerInstalled = false;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭播放设置',
    barrierColor: const Color(0x33000000),
    transitionDuration: accessibility.motionDuration(AppMotion.popover),
    pageBuilder: (dialogContext, routeAnimation, secondaryAnimation) {
      if (!routeBoundsListenerInstalled) {
        routeBoundsListenerInstalled = true;
        routeAnimation.addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            reportPanelBounds(dialogContext);
          }
        });
      }
      return StatefulBuilder(
        builder: (context, setDialogState) => LayoutBuilder(
          builder: (context, constraints) {
            reportPanelBounds(context);
            // 浮层右边缘与齿轮右边缘对齐，并限制高度以兼容超宽矮屏全屏布局。
            final right = playerSettingsPanelRight(
              availableWidth: constraints.maxWidth,
              anchorRect: anchorRect,
            );
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
                          width: playerSettingsPanelWidth,
                          duration:
                              accessibility.motionDuration(AppMotion.popover),
                          curve: AppMotion.standardCurve,
                          onEnd: () => reportPanelBounds(context),
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
                                          playbackMode: localPlaybackMode,
                                          onPlaybackModeChanged: (mode) {
                                            setDialogState(
                                              () => localPlaybackMode = mode,
                                            );
                                            onPlaybackModeChanged(mode);
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
                                          mirrorVideo: localMirrorVideo,
                                          mpvEnhancementsAvailable:
                                              mpvEnhancementsAvailable,
                                          videoSuperResolutionEnabled:
                                              localVideoSuperResolutionEnabled,
                                          compressionEnhancementMode:
                                              localCompressionEnhancementMode,
                                          onMirrorVideoChanged: (enabled) {
                                            setDialogState(
                                              () => localMirrorVideo = enabled,
                                            );
                                            onMirrorVideoChanged(enabled);
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
                                          onShowCompressionEnhancement: () =>
                                              setDialogState(
                                            () => currentPage =
                                                _PlayerSettingsPage
                                                    .compressionEnhancement,
                                          ),
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
                                      _PlayerSettingsPage
                                            .compressionEnhancement =>
                                        PlayerSettingsOptionList<
                                            PlayerCompressionEnhancementMode>(
                                          key: const ValueKey(
                                            'player.settings.compression.page',
                                          ),
                                          values:
                                              PlayerCompressionEnhancementMode
                                                  .values,
                                          selected:
                                              localCompressionEnhancementMode,
                                          labelFor: PlaybackSettings
                                              .compressionEnhancementLabelFor,
                                          iconFor: (mode) => switch (mode) {
                                            PlayerCompressionEnhancementMode
                                                  .off =>
                                              Icons.block_rounded,
                                            PlayerCompressionEnhancementMode
                                                  .automatic =>
                                              Icons.auto_fix_high_rounded,
                                            PlayerCompressionEnhancementMode
                                                  .clarity =>
                                              Icons.hd_rounded,
                                          },
                                          keyFor: (mode) => ValueKey(
                                            'player.settings.compression.${mode.name}',
                                          ),
                                          onSelected: (mode) {
                                            setDialogState(
                                              () =>
                                                  localCompressionEnhancementMode =
                                                      mode,
                                            );
                                            onCompressionEnhancementModeChanged(
                                              mode,
                                            );
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
enum _PlayerSettingsPage {
  primary,
  advanced,
  aspect,
  rate,
  compressionEnhancement,
}

/** 播放设置页标题与返回目标，避免各分支复制导航规则。 */
extension on _PlayerSettingsPage {
  String get title => switch (this) {
        _PlayerSettingsPage.primary => '播放设置',
        _PlayerSettingsPage.advanced => '更多播放设置',
        _PlayerSettingsPage.aspect => '视频比例',
        _PlayerSettingsPage.rate => '播放速度',
        _PlayerSettingsPage.compressionEnhancement => '压缩画质增强',
      };

  _PlayerSettingsPage get parentPage => switch (this) {
        _PlayerSettingsPage.primary => _PlayerSettingsPage.primary,
        _PlayerSettingsPage.advanced => _PlayerSettingsPage.primary,
        _PlayerSettingsPage.aspect ||
        _PlayerSettingsPage.rate =>
          _PlayerSettingsPage.advanced,
        _PlayerSettingsPage.compressionEnhancement =>
          _PlayerSettingsPage.advanced,
      };

  String get parentTitle => switch (parentPage) {
        _PlayerSettingsPage.primary => '返回播放设置',
        _PlayerSettingsPage.advanced => '返回更多播放设置',
        _ => '返回',
      };
}
