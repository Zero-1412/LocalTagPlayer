import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/** 播放器可同时容纳视频与常驻右侧队列的最小逻辑宽度。 */
const playerWideQueueSidebarBreakpoint = 1100.0;

/** 判断当前窗口是否应使用常驻右侧队列，统一布局、按钮与指针热区的分支。 */
bool playerHasWideQueueSidebar(double windowWidth) =>
    windowWidth >= playerWideQueueSidebarBreakpoint;

/**
 * 计算中窄窗口右侧覆盖队列宽度。
 *
 * 保留至少 24 逻辑像素的画面退出命中区；极窄窗口则允许队列占满可用宽度，避免溢出。
 */
double playerCompactQueueSidebarWidth(double windowWidth) {
  if (windowWidth <= 320) {
    return windowWidth;
  }
  return (windowWidth - 24).clamp(320.0, 420.0).toDouble();
}

/**
 * 协调队列显隐、全屏状态与窗口顶栏反馈。
 *
 * 这里只承载 [PlayerPageState] 的实现细节；播放会话、过滤队列与资源生命周期所有权
 * 仍保留在页面状态对象中。
 */
extension PlayerStateChrome on PlayerPageState {
  void toggleQueueVisibility() {
    if (isWindowFullscreen) {
      if (fullscreenQueueVisible) {
        fullscreenQueueHideTimer?.cancel();
        fullscreenQueueHideTimer = null;
        rebuild(() => fullscreenQueueVisible = false);
      } else {
        showFullscreenQueueSidebar();
      }
      return;
    }
    if (!playerHasWideQueueSidebar(MediaQuery.sizeOf(context).width)) {
      rebuild(() => fullscreenQueueVisible = !fullscreenQueueVisible);
      return;
    }
    rebuild(() {
      queueSidebarCollapsed = !queueSidebarCollapsed;
      // 队列重新展开后顶栏改为常驻，不再保留临时 hover 状态。
      if (!queueSidebarCollapsed) {
        pointerInWindowTopBarRegion = false;
      }
    });
  }

  /** 切换桌面窗口全屏，并让页面布局与窗口状态同步更新。 */
  Future<void> toggleWindowFullscreen() async {
    fullscreenQueueHideTimer?.cancel();
    fullscreenQueueHideTimer = null;
    rebuild(() {
      pointerInWindowTopBarRegion = false;
    });
    await windowFullscreen.toggle(
      // child HWND 会在原生全屏命令返回前完成尺寸切换；先提交“顶栏已卸载”的帧，
      // 防止 D3D11 子窗口把旧摘要像素保留在全屏画面顶部。
      beforeWindowCommand: () => WidgetsBinding.instance.endOfFrame,
      canExecuteWindowCommand: () => mounted,
      setFullscreen: windowManager.setFullScreen,
    );
    if (mounted) {
      rebuild(() {
        fullscreenQueueVisible = false;
        pointerInWindowTopBarRegion = false;
      });
      showVideoControls();
    }
  }

  /**
   * 长时压力测试在控制栏自动收起时仍通过正式全屏状态机完成往返。
   *
   * 该入口不复制窗口命令或会话语义，只绕过瞬时不可见的按钮挂载；生产交互仍使用
   * `toggleWindowFullscreen` 的按钮、快捷键和会话恢复路径。
   */
  @visibleForTesting
  Future<void> toggleWindowFullscreenForStressTest() =>
      toggleWindowFullscreen();

  /**
   * 稳定性矩阵通过正式队列显隐入口验证播放器容器布局。
   *
   * 该入口只复用生产状态机，不改变 filtered queue、当前索引或全屏覆盖层语义。
   */
  @visibleForTesting
  void toggleQueueVisibilityForStressTest() => toggleQueueVisibility();

  /**
   * 交互性能矩阵通过正式齿轮入口打开设置浮层。
   *
   * 测试仍需从浮层 Route 正常关闭；该入口不复制设置状态，也不绕过原生 airspace
   * 协调，确保 Texture 与显式 HWND QA 路径接受同一组压力。
   */
  @visibleForTesting
  Future<void> showControlSettingsForStressTest() =>
      showControlSettingsDialog();

  /**
   * 交互性能矩阵通过正式 latest-seek 协调器提交目标位置。
   *
   * 该入口保留实际后端 seek、位置确认与延迟诊断，不允许测试直接调用后端绕过页面。
   */
  @visibleForTesting
  Future<void> seekForStressTest(Duration target) =>
      seekWithDiagnostics(target);

  /**
   * 在双后端快速切换门禁中走正式队列跳转与 latest-request 串行链。
   *
   * 该入口只选择现有 filtered queue 的索引；越界语义仍由正式 [jumpTo] 处理，
   * 测试不能直接调用后端 `open` 绕过页面协调器。
   */
  @visibleForTesting
  void jumpToQueueIndexForStabilityTest(int index) =>
      jumpTo(index, ignoreFollowUpSelection: true);

  /**
   * 返回不含本地路径的稳定性快照，供全屏、快速切换和长播矩阵验证队列未漂移。
   */
  @visibleForTesting
  PlayerStabilitySnapshot buildStabilitySnapshotForTest() {
    final openedVideoIdSnapshot = openedVideoId;
    final openedItem = openedVideoIdSnapshot == null
        ? null
        : itemForVideoId(openedVideoIdSnapshot);
    return PlayerStabilitySnapshot(
      sourceVideoIds:
          sourcePlaylist.map((item) => item.videoId).toList(growable: false),
      queueVideoIds: queue.map((item) => item.videoId).toList(growable: false),
      playingIndex: index,
      selectedIndex: selectedIndex,
      currentVideoId: currentItem.videoId,
      openedVideoId: openedItem?.videoId,
      opening: openRequests.isOpening,
      hasPendingOpen: openRequests.hasPending,
      hasOpenFailure: openRequests.hasFailure,
      windowFullscreen: isWindowFullscreen,
    );
  }

  /** 把全屏状态机的稳定错误码映射为既有桌面诊断，不泄漏窗口对象。 */
  void reportFullscreenLifecycleError(String code, Object error) {
    final stage = switch (code) {
      'restore_failed' => 'PLAYER_FULLSCREEN_RESTORE_FAILED',
      'exit_failed' => 'PLAYER_FULLSCREEN_EXIT_FAILED',
      'exit_maximize_failed' => 'PLAYER_FULLSCREEN_EXIT_MAXIMIZE_FAILED',
      _ => 'PLAYER_FULLSCREEN_LIFECYCLE_FAILED',
    };
    debugPrint('$stage error=$error');
  }

  /** 鼠标进入右侧热区或队列时展示全屏侧栏，并取消待执行的自动隐藏。 */
  void showFullscreenQueueSidebar() {
    fullscreenQueueHideTimer?.cancel();
    fullscreenQueueHideTimer = null;
    if (mounted && !fullscreenQueueVisible) {
      rebuild(() => fullscreenQueueVisible = true);
    }
  }

  /** 鼠标离开队列宽度后短延迟收回侧栏，避免边缘抖动导致反复闪烁。 */
  void scheduleFullscreenQueueHide() {
    if (fullscreenQueueHideTimer?.isActive ?? false) {
      return;
    }
    fullscreenQueueHideTimer = Timer(playerFullscreenQueueHideGrace, () {
      fullscreenQueueHideTimer = null;
      if (mounted && fullscreenQueueVisible) {
        rebuild(() => fullscreenQueueVisible = false);
      }
    });
  }

  /**
   * 在播放器根表面持续判断全屏队列右缘或非全屏顶栏热区。
   *
   * 根级坐标避免标题栏处于展开中间帧时丢失 MouseRegion exit；只有跨越热区边界才更新状态。
   */
  void handlePlayerPointerHover(PointerHoverEvent event) {
    if (!isWindowFullscreen) {
      final inTopBarZone = playerPointerInWindowTopBarActivationZone(
        localY: event.localPosition.dy,
        hasWideQueueSidebar:
            playerHasWideQueueSidebar(MediaQuery.sizeOf(context).width),
        queueCollapsed: queueSidebarCollapsed,
      );
      if (inTopBarZone) {
        showWindowTopBarFromPointer();
      } else {
        hideWindowTopBarFromPointer();
      }
      return;
    }
    final inActivationZone = playerPointerInFullscreenQueueActivationZone(
      localX: event.localPosition.dx,
      surfaceWidth: MediaQuery.sizeOf(context).width,
      queueVisible: fullscreenQueueVisible,
      edgeWidth: playerFullscreenQueueEdgeActivationWidth,
      queueWidth: playerFullscreenQueueWidth(MediaQuery.sizeOf(context).width),
    );
    if (inActivationZone) {
      if (fullscreenQueueVisible ||
          pageWidget.playbackSettings.fullscreenQueueEdgeHoverEnabled) {
        showFullscreenQueueSidebar();
      }
    } else if (fullscreenQueueVisible) {
      scheduleFullscreenQueueHide();
    }
  }

  /** 指针进入非全屏顶部热区时临时展示已随队列收起的标题栏。 */
  void showWindowTopBarFromPointer() {
    if (isWindowFullscreen ||
        !queueSidebarCollapsed ||
        pointerInWindowTopBarRegion) {
      return;
    }
    rebuild(() => pointerInWindowTopBarRegion = true);
  }

  /** 指针离开标题栏后收回临时层；队列展开时标题栏仍保持常驻。 */
  void hideWindowTopBarFromPointer() {
    if (!queueSidebarCollapsed || !pointerInWindowTopBarRegion) {
      return;
    }
    rebuild(() => pointerInWindowTopBarRegion = false);
  }

  /** 读取齿轮在当前普通/全屏布局中的全局矩形，供浮层实时对齐。 */
  Rect settingsButtonRect() {
    final renderBox = settingsButtonAnchorKey.currentContext?.findRenderObject()
        as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      return renderBox.localToGlobal(Offset.zero) & renderBox.size;
    }
    final size = MediaQuery.sizeOf(context);
    // 首帧极端竞态下回退到控制条右下区域，避免浮层退回窗口中心。
    return Rect.fromLTWH(size.width - 72, size.height - 64, 40, 40);
  }

  /** 打开齿轮锚定的分级设置，并在整个显示期间保持进度控制区可见。 */
}
