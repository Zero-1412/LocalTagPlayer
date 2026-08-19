import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/playback_settings.dart';
import '../../features/player/application/player_seek_coordinator.dart';
import '../../models/video_item.dart';
import '../../widgets/player_shortcut_input.dart';
import 'player_input_qa_evidence.dart';
import 'player_page.dart';
import 'player_state_precision_controls.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 承载格式化、快捷键和指针输入等页面辅助逻辑。
 *
 * 这里只承载 [PlayerPageState] 的实现细节；播放会话、过滤队列与资源生命周期所有权
 * 仍保留在页面状态对象中。
 */
extension PlayerStateHelpers on PlayerPageState {
  String formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  /** 蓝图控制栏固定显示两位小时，避免时长跨小时后横向跳动。 */
  String formatControlDuration(Duration value) {
    final hours = value.inHours.toString().padLeft(2, '0');
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 2)} ${units[unit]}';
  }

  /** 显存预算和当前进程占用必须成对展示，缺失时不以 0 冒充真实读数。 */
  String formatGpuMemoryPair(int? budgetBytes, int? usageBytes) {
    if (budgetBytes == null || usageBytes == null) return '不可用';
    return '${formatBytes(budgetBytes)} / ${formatBytes(usageBytes)}';
  }

  String childTagSummary(VideoItem item) {
    final parts = <String>[];
    for (final entry in item.childTags.entries) {
      final values = entry.value.toList()..sort();
      parts.add('${entry.key}: ${values.join(', ')}');
    }
    return parts.isEmpty ? '\u65e0' : parts.join(' / ');
  }

  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent &&
        event is! KeyRepeatEvent &&
        event is! KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final pressedKey = playerShortcutIdFromEvent(event);
    final shortcuts = effectivePlaybackSettings.shortcuts;
    // 仅在显式 Debug QA 环境写匿名到达回执，便于区分 native WM_KEYDOWN、Flutter
    // KeyRepeat 与 PlayerPage 语义处理；action 只写 forward/backward/other，不记录
    // 实际按键、修饰键、媒体路径或用户身份。
    final qaAction = pressedKey == shortcuts[PlayerShortcutAction.seekForward]
        ? 'forward'
        : pressedKey == shortcuts[PlayerShortcutAction.seekBackward]
            ? 'backward'
            : 'other';
    final qaPhase = event is KeyRepeatEvent
        ? 'repeat'
        : event is KeyUpEvent
            ? 'up'
            : 'down';
    PlayerInputQaEvidence.playerKeyboardEventReceived(
      action: qaAction,
      phase: qaPhase,
    );
    bool matches(PlayerShortcutAction action) =>
        pressedKey != null && shortcuts[action] == pressedKey;

    // 即使按住期间弹窗或焦点状态改变，对应 KeyUp 仍必须结束当前预览会话。
    if (event is KeyUpEvent) {
      final activeAction = keyboardSeekAction;
      // KeyUp 可能发生在 Alt/修饰键先释放或用户修改快捷键之后；必须按实际物理
      // 逻辑键结束会话，不能再次用当前配置和 HardwareKeyboard 状态反推。
      if (activeAction != null && keyboardSeekLogicalKey == event.logicalKey) {
        keyboardSeekAction = null;
        keyboardSeekLogicalKey = null;
        settleKeyboardSeek();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (!shortcutGate.canHandle(
      settingsOpen: settingsDialogOpen,
      focusEditable: playerFocusIsEditable(primaryFocus),
      focusOnDifferentRoute: playerFocusIsOnDifferentRoute(
        playerContext: context,
        focus: primaryFocus,
      ),
      blockingOverlay: playerRouteHasBlockingOverlay(context),
    )) {
      // 输入框、弹窗、菜单和原生文件对话框统一暂停所有单键及组合播放器动作。
      return KeyEventResult.ignored;
    }
    if (isWindowFullscreen && event.logicalKey == LogicalKeyboardKey.escape) {
      // Escape 是桌面全屏的固定安全出口，必须先于页面返回逻辑消费。
      unawaited(toggleWindowFullscreen());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.insert &&
        HardwareKeyboard.instance.isAltPressed) {
      unawaited(toggleQueueFavorite(currentItem));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(currentItem.isFavorite
                ? '\u5df2\u6dfb\u52a0\u5230\u6211\u7684\u6536\u85cf'
                : '\u5df2\u53d6\u6d88\u6536\u85cf')),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete &&
        HardwareKeyboard.instance.isControlPressed &&
        HardwareKeyboard.instance.isShiftPressed) {
      unawaited(deleteQueueItem(selectedIndex));
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.navigateBack)) {
      if (isWindowFullscreen) {
        unawaited(toggleWindowFullscreen());
      } else {
        unawaited(exitPlayer());
      }
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.playPause)) {
      if (event is KeyRepeatEvent) {
        return KeyEventResult.handled;
      }
      togglePlaybackWithFeedback();
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.seekBackward)) {
      final isRepeat = event is KeyRepeatEvent;
      if (event is KeyDownEvent) {
        // 新 KeyDown 代表新一轮物理按键；若上一轮遗漏 KeyUp，不能继承旧累计目标。
        cancelKeyboardSeek();
        keyboardSeekLogicalKey = event.logicalKey;
      } else {
        keyboardSeekLogicalKey ??= event.logicalKey;
      }
      keyboardSeekAction = PlayerShortcutAction.seekBackward;
      final stepSeconds = isRepeat
          ? playerKeyboardSeekRepeatStepSeconds(seekStepSeconds)
          : seekStepSeconds;
      final target = seekRelative(
        Duration(seconds: -stepSeconds),
        // 短按在松键提交唯一关键帧；长按快退仍保持 latest-only 预览并临时静音。
        mutePreview: isRepeat,
        isRepeat: isRepeat,
      );
      showShortcutFeedback(
        isRepeat
            ? '连续快退（关键帧预览） · ${formatDuration(target)}'
            : '后退 $seekStepSeconds 秒 · 关键帧预览 · ${formatDuration(target)}',
        Icons.fast_rewind_rounded,
        minimumPublishInterval: isRepeat
            ? PlayerSeekCoordinator.defaultMinimumDispatchInterval
            : Duration.zero,
      );
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.seekForward)) {
      final isRepeat = event is KeyRepeatEvent;
      if (event is KeyDownEvent) {
        cancelKeyboardSeek();
        keyboardSeekLogicalKey = event.logicalKey;
      } else {
        keyboardSeekLogicalKey ??= event.logicalKey;
      }
      keyboardSeekAction = PlayerShortcutAction.seekForward;
      final stepSeconds = isRepeat
          ? playerKeyboardSeekRepeatStepSeconds(seekStepSeconds)
          : seekStepSeconds;
      final target = seekRelative(
        Duration(seconds: stepSeconds),
        // 物理长按前进由 controller 切到连续高速播放，短按仍保留唯一关键帧跳转。
        mutePreview: isRepeat,
        isRepeat: isRepeat,
      );
      showShortcutFeedback(
        keyboardSeek.isSmoothForwardScan
            ? '连续快进 · ${keyboardSeek.activeSmoothForwardScanRate}×'
            : isRepeat
                ? '连续快进（关键帧预览） · ${formatDuration(target)}'
                : '前进 $seekStepSeconds 秒 · 关键帧预览 · ${formatDuration(target)}',
        Icons.fast_forward_rounded,
        minimumPublishInterval: isRepeat
            ? PlayerSeekCoordinator.defaultMinimumDispatchInterval
            : Duration.zero,
      );
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.previous)) {
      if (index > 0) {
        jumpTo(index - 1, ignoreFollowUpSelection: true);
        showShortcutFeedback('上一条', Icons.skip_previous_rounded);
      } else {
        showShortcutFeedback('已到队列开头', Icons.first_page_rounded);
      }
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.next)) {
      if (index + 1 < queue.length) {
        jumpTo(index + 1, ignoreFollowUpSelection: true);
        showShortcutFeedback('下一条', Icons.skip_next_rounded);
      } else {
        showShortcutFeedback('已到队列末尾', Icons.last_page_rounded);
      }
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.editTags)) {
      unawaited(editManualTags());
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.screenshot)) {
      unawaited(saveCurrentFrameScreenshot());
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.fullscreen)) {
      if (event is KeyRepeatEvent) {
        return KeyEventResult.handled;
      }
      toggleFullscreenWithFeedback();
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.speedDown)) {
      stepPlaybackRate(-1);
      showShortcutFeedback('倍速 $playbackRate×', Icons.speed_rounded);
      return KeyEventResult.handled;
    }
    if (matches(PlayerShortcutAction.speedUp)) {
      stepPlaybackRate(1);
      showShortcutFeedback('倍速 $playbackRate×', Icons.speed_rounded);
      return KeyEventResult.handled;
    }
    // 保留 mpv 常见的逗号/句号逐帧入口；只消费 KeyDown，避免系统重复键把
    // 一次明确的逐帧动作放大成不可预测的连续命令。
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.comma) {
      unawaited(stepFrameWithFeedback(backward: true));
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.period) {
      unawaited(stepFrameWithFeedback(backward: false));
      return KeyEventResult.handled;
    }
    if (handleMpvMediaControlMenuShortcut(event)) {
      return KeyEventResult.handled;
    }
    // mpv 默认 `#`：循环音轨。现有可配置快捷键已先匹配，不能覆盖用户绑定。
    if (event.character == '#') {
      unawaited(cycleAudioTrack());
      return KeyEventResult.handled;
    }
    // 当前 J/L 已由项目占用为快退/快进，保留现有行为；其余不冲突的 mpv 字幕键按原义补齐。
    if (event.logicalKey == LogicalKeyboardKey.keyV) {
      unawaited(toggleSubtitleWithFeedback());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      unawaited(
        adjustSubtitleDelayWithFeedback(
          Duration(
            milliseconds: HardwareKeyboard.instance.isShiftPressed ? 100 : -100,
          ),
        ),
      );
      return KeyEventResult.handled;
    }
    // mpv 默认 Ctrl++ / Ctrl+-：调节音频延迟；不与项目现有可配置动作冲突。
    if (HardwareKeyboard.instance.isControlPressed &&
        (event.logicalKey == LogicalKeyboardKey.equal ||
            event.logicalKey == LogicalKeyboardKey.minus)) {
      unawaited(
        adjustAudioDelayWithFeedback(
          Duration(
            milliseconds:
                event.logicalKey == LogicalKeyboardKey.equal ? 100 : -100,
          ),
        ),
      );
      return KeyEventResult.handled;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        stepPlayerVolume(5);
        showShortcutFeedback(
          '音量 ${volume.round()}%',
          Icons.volume_up_rounded,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        stepPlayerVolume(-5);
        showShortcutFeedback(
          '音量 ${volume.round()}%',
          volume == 0 ? Icons.volume_off_rounded : Icons.volume_down_rounded,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        selectQueueIndex(0, center: true);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        selectQueueIndex(queue.length - 1, center: true);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        // 未被用户自定义快捷键消费的回车固定作为全屏快速开关。
        if (event is KeyRepeatEvent) {
          return KeyEventResult.handled;
        }
        toggleFullscreenWithFeedback();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /** 统一处理画面双击与键盘动作，保证播放状态反馈文案一致。 */
  void togglePlaybackWithFeedback() {
    final playing = playerService.state.playing;
    unawaited(playerService.playOrPause());
    showShortcutFeedback(
      playing ? '暂停' : '播放',
      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
    );
  }

  /** 统一处理回车与可配置全屏快捷键，保留既有窗口生命周期边界。 */
  void toggleFullscreenWithFeedback() {
    unawaited(toggleWindowFullscreen());
    showShortcutFeedback(
      isWindowFullscreen ? '退出全屏' : '进入全屏',
      isWindowFullscreen
          ? Icons.fullscreen_exit_rounded
          : Icons.fullscreen_rounded,
    );
  }

  /**
   * mpv 的 `g-a`、`g-s` 与 `g-c` 都打开当前媒体控制菜单。
   *
   * 页面先处理用户可配置动作，随后才识别此前未占用的组合键；因此不会改写任何
   * 已有快捷键。章节默认 PageUp/PageDown 已被来源队列占用，继续保留原行为。
   */
  bool handleMpvMediaControlMenuShortcut(KeyEvent event) {
    if (event is KeyRepeatEvent) return false;
    final key = event.logicalKey;
    if (mediaControlShortcutPrefixPending) {
      mediaControlShortcutPrefixTimer?.cancel();
      mediaControlShortcutPrefixTimer = null;
      mediaControlShortcutPrefixPending = false;
      if (key == LogicalKeyboardKey.keyA ||
          key == LogicalKeyboardKey.keyS ||
          key == LogicalKeyboardKey.keyC) {
        unawaited(showMediaControlsDialog());
        return true;
      }
      return false;
    }
    if (key != LogicalKeyboardKey.keyG ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return false;
    }
    mediaControlShortcutPrefixPending = true;
    mediaControlShortcutPrefixTimer = Timer(const Duration(seconds: 1), () {
      mediaControlShortcutPrefixPending = false;
      mediaControlShortcutPrefixTimer = null;
    });
    return true;
  }

  void handlePointerDown(PointerDownEvent event) {
    if (event.buttons == kBackMouseButton) {
      unawaited(exitPlayer());
    }
  }
}
