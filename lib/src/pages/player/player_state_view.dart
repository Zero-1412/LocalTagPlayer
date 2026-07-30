import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';
import 'player_compact_queue_overlay.dart';
import 'player_open_failure_panel.dart';
import 'player_video_aspect_mode.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 构建播放器页面视图树。
 *
 * 本区域只读取页面快照并绑定已有回调，不拥有播放队列或业务状态。
 */
extension PlayerStateView on PlayerPageState {
  Widget buildPlayerPage(BuildContext context) {
    final windowWidth = MediaQuery.sizeOf(context).width;
    // 中窄窗口改用右侧覆盖队列，避免侧栏挤压蓝图式横向控制层。
    final hasWideQueueSidebar = playerHasWideQueueSidebar(windowWidth);
    final accessibility = AppAccessibilityScope.of(context);
    final queueSidebar =
        hasWideQueueSidebar ? buildQueueSidebar() : const SizedBox.shrink();
    final fullscreenQueueWidth =
        playerFullscreenQueueWidth(MediaQuery.sizeOf(context).width);
    final windowQueueCollapsed = hasWideQueueSidebar && queueSidebarCollapsed;
    final windowTopBarVisible = playerWindowTopBarShouldShow(
      isFullscreen: isWindowFullscreen,
      queueCollapsed: windowQueueCollapsed,
      pointerInTopBarRegion: pointerInWindowTopBarRegion,
      accessibleNavigation: accessibility.accessibleNavigation,
    );
    final page = Theme(
      data: playerWorkspaceTheme(
        Theme.of(context),
        highContrast: accessibility.highContrast,
      ),
      child: Focus(
        focusNode: focusNode,
        autofocus: true,
        onKeyEvent: handleKey,
        child: Listener(
          onPointerDown: handlePointerDown,
          child: Scaffold(
            backgroundColor: playerCanvas,
            body: MouseRegion(
              onHover: handlePlayerPointerHover,
              onExit: (_) {
                if (isWindowFullscreen && fullscreenQueueVisible) {
                  scheduleFullscreenQueueHide();
                } else if (!isWindowFullscreen) {
                  hideWindowTopBarFromPointer();
                }
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      children: [
                        if (playerWindowTopBarShouldMount(
                          isFullscreen: isWindowFullscreen,
                          fullscreenTransitionInProgress:
                              fullscreenTransitionInProgress,
                        ))
                          AnimatedSize(
                            key: const ValueKey(
                              'player.windowTopBar.visibility',
                            ),
                            alignment: Alignment.topCenter,
                            duration: accessibility.motionDuration(
                              AppMotion.popover,
                            ),
                            curve: appMotionCurve,
                            child: ClipRect(
                              child: Align(
                                alignment: Alignment.topCenter,
                                heightFactor: windowTopBarVisible ? 1 : 0,
                                child: MouseRegion(
                                  onEnter: (_) => showWindowTopBarFromPointer(),
                                  onExit: (_) => hideWindowTopBarFromPointer(),
                                  child: PlayerTopBar(
                                    currentFileName: playerTopBarFileName(
                                      currentItem.path,
                                    ),
                                    contextLabel:
                                        '${index + 1} / ${queue.length} · $filterSummary',
                                    onBack: () => unawaited(exitPlayer()),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        key: const ValueKey(
                                            'player.video.surface'),
                                        margin: isWindowFullscreen
                                            ? EdgeInsets.zero
                                            : const EdgeInsets.fromLTRB(
                                                16, 12, 16, 16),
                                        decoration: BoxDecoration(
                                          color: Colors.black,
                                          borderRadius: BorderRadius.circular(
                                            AppRadius.panel,
                                          ),
                                          border: Border.all(
                                            color: playerBorder,
                                          ),
                                          boxShadow: playerSoftShadow,
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Stack(
                                          children: [
                                            Positioned.fill(
                                              child: Listener(
                                                onPointerSignal:
                                                    handleVideoPointerSignal,
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTapDown: (_) =>
                                                      focusNode.requestFocus(),
                                                  onSecondaryTapDown:
                                                      showPlayerContextMenu,
                                                  child: Center(
                                                    child: playerService
                                                        .buildVideoSurface(
                                                      controls:
                                                          buildVideoControls(),
                                                      fit: videoAspectMode
                                                          .surfaceFit,
                                                      aspectRatio: videoAspectMode
                                                          .surfaceAspectRatio,
                                                      mirror: mirrorVideo,
                                                      // 默认 MPV 与 MediaKit 都在 Flutter
                                                      // 容器内合成；显式 HWND QA 也不再
                                                      // 为已删除的全屏顶部语境预留黑区。
                                                      reserveBottomControlArea:
                                                          controlsVisible,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Positioned.fill(
                                              child: PlayerOpeningPoster(
                                                // 首次 build 时 open worker 尚未把 isOpening
                                                // 提交到树中；路径未确认也必须立即显示占位。
                                                opening:
                                                    openRequests.isOpening ||
                                                        openedPath !=
                                                            currentItem.path,
                                                file: openingPosterPath ==
                                                        currentItem.path
                                                    ? openingPosterFile
                                                    : null,
                                              ),
                                            ),
                                            Positioned.fill(
                                              child: PlayerOpeningOverlay(
                                                opening: openRequests.isOpening,
                                              ),
                                            ),
                                            if (!openRequests.isOpening &&
                                                openRequests.hasFailure)
                                              Positioned.fill(
                                                child: PlayerOpenFailurePanel(
                                                  failureCode: openRequests
                                                          .failureCode ??
                                                      'unknown',
                                                  canSkip: playback.hasNext,
                                                  onRetry: retryFailedOpen,
                                                  onSkip: skipFailedOpen,
                                                  onDiagnostics: () {
                                                    unawaited(
                                                        showDiagnosticsDialog());
                                                  },
                                                  onRelink:
                                                      currentItem.isMissing
                                                          ? () {
                                                              unawaited(
                                                                  relinkCurrentMissing());
                                                            }
                                                          : null,
                                                ),
                                              ),
                                            if (shortcutFeedbackLabel != null)
                                              if (shortcutFeedbackIsSeekWatermark)
                                                Positioned(
                                                  left: 16,
                                                  top: 16,
                                                  child:
                                                      PlayerSeekFeedbackWatermark(
                                                    visible:
                                                        shortcutFeedbackVisible,
                                                    label:
                                                        shortcutFeedbackLabel!,
                                                  ),
                                                )
                                              else
                                                Positioned.fill(
                                                  child: Center(
                                                    child:
                                                        PlayerShortcutFeedback(
                                                      visible:
                                                          shortcutFeedbackVisible,
                                                      label:
                                                          shortcutFeedbackLabel!,
                                                      icon:
                                                          shortcutFeedbackIcon,
                                                    ),
                                                  ),
                                                ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isWindowFullscreen && hasWideQueueSidebar)
                                AnimatedSize(
                                  duration: accessibility.motionDuration(
                                    AppMotion.panel,
                                  ),
                                  curve: appMotionCurve,
                                  child: ClipRect(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      widthFactor:
                                          queueSidebarCollapsed ? 0 : 1,
                                      child: IgnorePointer(
                                        ignoring: queueSidebarCollapsed,
                                        child: RepaintBoundary(
                                          child: queueSidebar,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isWindowFullscreen && !hasWideQueueSidebar)
                    Positioned.fill(
                      top: playerTopBarHeight,
                      child: IgnorePointer(
                        ignoring: !fullscreenQueueVisible,
                        child: AnimatedSwitcher(
                          key: const ValueKey(
                            'player.compactQueue.overlayMotion',
                          ),
                          duration: accessibility.motionDuration(
                            AppMotion.panel,
                          ),
                          reverseDuration: accessibility.motionDuration(
                            AppMotion.popover,
                          ),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final begin = accessibility.reduceMotion
                                ? Offset.zero
                                : const Offset(0.04, 0);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: begin,
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: fullscreenQueueVisible
                              ? PlayerCompactQueueOverlay(
                                  key: const ValueKey(
                                    'player.compactQueue.overlay',
                                  ),
                                  sidebarWidth: playerCompactQueueSidebarWidth(
                                    windowWidth,
                                  ),
                                  onDismiss: () => rebuild(
                                    () => fullscreenQueueVisible = false,
                                  ),
                                  sidebar: buildQueueSidebar(
                                    key: const ValueKey(
                                      'player.compactQueue.sidebar',
                                    ),
                                    edgeToEdge: true,
                                    width: playerCompactQueueSidebarWidth(
                                      windowWidth,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey(
                                    'player.compactQueue.hidden',
                                  ),
                                ),
                        ),
                      ),
                    ),
                  if (isWindowFullscreen)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !fullscreenQueueVisible,
                        child: AnimatedSwitcher(
                          key: const ValueKey(
                            'player.fullscreenQueue.overlayMotion',
                          ),
                          duration: accessibility.motionDuration(
                            AppMotion.panel,
                          ),
                          reverseDuration: accessibility.motionDuration(
                            AppMotion.popover,
                          ),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (currentChild, previousChildren) {
                            return Stack(
                              alignment: Alignment.centerRight,
                              children: [
                                ...previousChildren,
                                if (currentChild != null) currentChild,
                              ],
                            );
                          },
                          transitionBuilder: (child, animation) {
                            // 覆盖层只做合成位移与短淡入，不改变视频纹理或大队列宽度。
                            final begin = accessibility.reduceMotion
                                ? Offset.zero
                                : const Offset(0.06, 0);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: begin,
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: fullscreenQueueVisible
                              ? Align(
                                  key: const ValueKey(
                                    'player.fullscreenQueue.overlay',
                                  ),
                                  alignment: Alignment.centerRight,
                                  child: RepaintBoundary(
                                    child: MouseRegion(
                                      onEnter: (_) =>
                                          showFullscreenQueueSidebar(),
                                      child: buildQueueSidebar(
                                        key: const ValueKey(
                                          'player.fullscreenQueue.sidebar',
                                        ),
                                        scrollController:
                                            fullscreenQueueScrollController,
                                        edgeToEdge: true,
                                        width: fullscreenQueueWidth,
                                      ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey(
                                    'player.fullscreenQueue.hidden',
                                  ),
                                ),
                        ),
                      ),
                    ),
                  if (isWindowFullscreen &&
                      pageWidget
                          .playbackSettings.fullscreenQueueEdgeHoverEnabled &&
                      !fullscreenQueueVisible)
                    Positioned(
                      key: const ValueKey('player.fullscreenQueue.edge'),
                      top: 0,
                      right: 0,
                      bottom: 0,
                      width: playerFullscreenQueueEdgeActivationWidth,
                      child: MouseRegion(
                        opaque: true,
                        onEnter: (_) => showFullscreenQueueSidebar(),
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return PlayerRouteSemantics(child: page);
  }
}
