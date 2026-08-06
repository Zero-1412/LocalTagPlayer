import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';
import 'player_control_slider.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 构建视频控制条与传输控制区域。
 *
 * 这里只承载 [PlayerPageState] 的实现细节；播放会话、过滤队列与资源生命周期所有权
 * 仍保留在页面状态对象中。
 */
extension PlayerStateControls on PlayerPageState {
  Widget buildVideoControls() {
    final accessibility = AppAccessibilityScope.of(context);
    // 进入稍慢以建立层级，退出更短以快速让出画面；无障碍模式由 token 自动降级。
    final fadeDuration = accessibility.fadeDuration(
      controlsVisible ? AppMotion.popover : AppMotion.hover,
    );
    final motionDuration = accessibility.motionDuration(
      controlsVisible ? AppMotion.popover : AppMotion.hover,
    );
    final controlsOffset = accessibility.reduceMotion || controlsVisible
        ? Offset.zero
        : const Offset(0, 0.025);
    return MouseRegion(
      key: videoControlsRegionKey,
      onEnter: handleVideoControlsPointer,
      onHover: handleVideoControlsPointer,
      onExit: (_) {
        setPointerInControlBar(false);
      },
      child: Stack(children: [
        // 隐藏态进度提示必须独立于控制条树常驻；如果放进下方透明控制条，
        // 控制条收起时它会一起消失，用户也会失去当前播放位置的最低限度反馈。
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: StreamBuilder<Duration>(
            stream: playerService.positionChanges,
            initialData: playerService.state.position,
            builder: (context, positionSnapshot) {
              final livePosition = positionSnapshot.data ?? Duration.zero;
              final position = optimisticProgressPosition ?? livePosition;
              return AnimatedOpacity(
                key: const ValueKey('player.controls.hiddenProgress'),
                duration: fadeDuration,
                opacity: controlsVisible ? 0 : 1,
                child: PlayerHiddenProgressBar(
                  position: position,
                  duration: playerService.state.duration,
                ),
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedSlide(
            duration: motionDuration,
            curve: AppMotion.standardCurve,
            offset: controlsOffset,
            child: AnimatedOpacity(
              key: const ValueKey('player.controls.opacity'),
              duration: fadeDuration,
              opacity: controlsVisible ? 1 : 0,
              child: IgnorePointer(
                ignoring: !controlsVisible,
                child: StreamBuilder<Duration>(
                  stream: playerService.positionChanges,
                  initialData: playerService.state.position,
                  builder: (context, positionSnapshot) {
                    final livePosition = positionSnapshot.data ?? Duration.zero;
                    final position = optimisticProgressPosition ?? livePosition;
                    final duration = playerService.state.duration;
                    final maxMs =
                        math.max(1, duration.inMilliseconds).toDouble();
                    return Container(
                      padding: EdgeInsets.fromLTRB(
                        isWindowFullscreen ? 24 : 14,
                        32,
                        isWindowFullscreen ? 24 : 14,
                        isWindowFullscreen ? 18 : 12,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xb8000000)],
                        ),
                      ),
                      child: DecoratedBox(
                        key: const ValueKey('player.controls.chrome'),
                        decoration: BoxDecoration(
                          color: playerSurface.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(color: playerBorder),
                          boxShadow: playerSoftShadow,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                          child: IconTheme(
                            data: const IconThemeData(color: playerText),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PlayerProgressSlider(
                                    sliderKey:
                                        const ValueKey('player.progress'),
                                    isFullscreen: isWindowFullscreen,
                                    value: position.inMilliseconds
                                        .clamp(0, maxMs.toInt())
                                        .toDouble(),
                                    max: maxMs,
                                    previewIdentity: currentItem.path,
                                    loadPreview: (target) => widget
                                        .thumbnailService
                                        .previewFrameFor(currentItem, target),
                                    onSeekTargetChanged: (value) =>
                                        setOptimisticProgressPosition(
                                      value == null
                                          ? null
                                          : Duration(
                                              milliseconds: value.round()),
                                    ),
                                    onCommitted: (value) =>
                                        seekFromProgressBarWithDiagnostics(
                                      Duration(milliseconds: value.round()),
                                    ),
                                  ),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final textScaler =
                                          MediaQuery.textScalerOf(context);
                                      final textScaleFactor =
                                          textScaler.scale(12) / 12;
                                      final showTime = playerControlsShowTime(
                                        availableWidth: constraints.maxWidth,
                                        textScaleFactor: textScaleFactor,
                                      );
                                      final volumeWidth =
                                          constraints.maxWidth >= 780
                                              ? 112.0
                                              : constraints.maxWidth >= 520
                                                  ? 76.0
                                                  : 54.0;
                                      final leadingControls =
                                          buildLeadingPlayerControls(
                                        position: position,
                                        duration: duration,
                                        showTime: showTime,
                                        volumeWidth: volumeWidth,
                                      );
                                      final transportControls =
                                          buildTransportControls(
                                        accessibility,
                                      );
                                      final trailingControls =
                                          buildTrailingPlayerControls();
                                      if (playerControlsUseCompactStack(
                                          constraints.maxWidth)) {
                                        // 紧窄视频表面不能继续把三组动作压进同一 Row；
                                        // 三行仍保留全部入口，并让中央传输组保持视觉中心。
                                        return Column(
                                          key: const ValueKey(
                                            'player.controls.compactLayout',
                                          ),
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            KeyedSubtree(
                                              key: const ValueKey(
                                                'player.controls.compact.transport',
                                              ),
                                              child: transportControls,
                                            ),
                                            const SizedBox(height: 2),
                                            KeyedSubtree(
                                              key: const ValueKey(
                                                'player.controls.compact.leading',
                                              ),
                                              child: leadingControls,
                                            ),
                                            const SizedBox(height: 2),
                                            KeyedSubtree(
                                              key: const ValueKey(
                                                'player.controls.compact.trailing',
                                              ),
                                              child: trailingControls,
                                            ),
                                          ],
                                        );
                                      }
                                      return Row(
                                        children: [
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: leadingControls,
                                            ),
                                          ),
                                          transportControls,
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: trailingControls,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ]),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /** 构建文件、音量与可选时间文本；紧窄布局会整组移到独立一行。 */
  Widget buildLeadingPlayerControls({
    required Duration position,
    required Duration duration,
    required bool showTime,
    required double volumeWidth,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerRevealFileButton(
          onPressed: () => unawaited(revealCurrentFile()),
        ),
        const SizedBox(width: 2),
        PlayerVolumeButton(
          volume: volume,
          onPressed: togglePlayerMute,
        ),
        SizedBox(
          width: volumeWidth,
          child: PlayerControlSlider(
            sliderKey: const ValueKey('player.volume'),
            value: volume,
            max: 100,
            trackHeight: 3,
            thumbRadius: 4.5,
            overlayRadius: 11,
            onChanged: setPlayerVolume,
          ),
        ),
        if (showTime) ...[
          const SizedBox(width: 14),
          Text(
            '${formatControlDuration(position)} / '
            '${formatControlDuration(duration)}',
            style: const TextStyle(
              color: playerTextMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }

  /** 构建截图、设置、全屏和队列动作；任何响应式分支都不得删除这些既有入口。 */
  Widget buildTrailingPlayerControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerChromeButton(
          key: const ValueKey('player.screenshot'),
          tooltip: '当前帧截图',
          icon: Icons.photo_camera_outlined,
          onPressed: () => unawaited(saveCurrentFrameScreenshot()),
        ),
        PlayerChromeButton(
          key: const ValueKey('player.mediaControls'),
          tooltip: '音轨、字幕与章节',
          icon: Icons.tune_rounded,
          onPressed: () => unawaited(showMediaControlsDialog()),
        ),
        KeyedSubtree(
          key: settingsButtonAnchorKey,
          child: PlayerChromeButton(
            key: const ValueKey('player.settings'),
            tooltip: '播放设置',
            icon: Icons.settings_outlined,
            onPressed: () => unawaited(showControlSettingsDialog()),
          ),
        ),
        PlayerChromeButton(
          key: const ValueKey('player.fullscreen.toggle'),
          tooltip: isWindowFullscreen ? '退出全屏' : '全屏',
          icon: isWindowFullscreen
              ? Icons.fullscreen_exit_rounded
              : Icons.fullscreen_rounded,
          onPressed: () => unawaited(toggleWindowFullscreen()),
        ),
        PlayerChromeButton(
          key: const ValueKey('player.queue.toggle'),
          tooltip: isWindowFullscreen
              ? '播放列表'
              : playerHasWideQueueSidebar(MediaQuery.sizeOf(context).width)
                  ? queueSidebarCollapsed
                      ? '展开筛选结果队列'
                      : '折叠筛选结果队列'
                  : fullscreenQueueVisible
                      ? '关闭筛选结果队列'
                      : '展开筛选结果队列',
          icon: Icons.playlist_play_rounded,
          onPressed: toggleQueueVisibility,
        ),
      ],
    );
  }

  /** 构建视觉上始终居中的上一条、播放/暂停与下一条传输控制。 */
  Widget buildTransportControls(AppAccessibilityData accessibility) {
    final playing = playerService.state.playing;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerChromeButton(
          tooltip: '上一条',
          icon: Icons.skip_previous_rounded,
          onPressed: playback.previousIndex == null
              ? null
              : () => jumpTo(
                    playback.previousIndex!,
                    ignoreFollowUpSelection: true,
                  ),
        ),
        const SizedBox(width: 6),
        PlayerChromeButton(
          tooltip: playing ? '暂停' : '播放',
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          primary: true,
          size: 46,
          iconSize: 27,
          onPressed: () {
            unawaited(playerService.playOrPause());
            showVideoControls();
          },
          iconChild: AnimatedSwitcher(
            duration: accessibility.fadeDuration(AppMotion.press),
            transitionBuilder: (child, animation) {
              final scale = accessibility.reduceMotion
                  ? animation
                  : Tween<double>(begin: 0.92, end: 1).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: scale, child: child),
              );
            },
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(playing),
            ),
          ),
        ),
        const SizedBox(width: 6),
        PlayerChromeButton(
          tooltip: '下一条',
          icon: Icons.skip_next_rounded,
          onPressed: playback.nextIndex == null
              ? null
              : () => jumpTo(
                    playback.nextIndex!,
                    ignoreFollowUpSelection: true,
                  ),
        ),
      ],
    );
  }

  /** 切换常规侧栏或全屏同层队列，不改变 filtered queue 与当前播放索引。 */
}
