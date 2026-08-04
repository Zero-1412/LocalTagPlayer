import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/playback_settings.dart';
import '../../features/player/application/player_seek_coordinator.dart';
import '../../models/video_item.dart';
import '../../widgets/player_shortcut_input.dart';
import 'player_page.dart';

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
    bool matches(PlayerShortcutAction action) =>
        pressedKey != null && shortcuts[action] == pressedKey;

    // 即使按住期间弹窗或焦点状态改变，对应 KeyUp 仍必须结束预览并精确落到最终目标。
    if (event is KeyUpEvent) {
      final activeAction = keyboardSeekAction;
      if (activeAction != null && matches(activeAction)) {
        keyboardSeekAction = null;
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
      }
      keyboardSeekAction = PlayerShortcutAction.seekBackward;
      final stepSeconds = isRepeat
          ? playerKeyboardSeekRepeatStepSeconds(seekStepSeconds)
          : seekStepSeconds;
      final target = seekRelative(
        Duration(seconds: -stepSeconds),
        // 每次按下立即预览关键帧；只有 KeyRepeat 才静音，避免短按人为打断声音。
        mutePreview: isRepeat,
      );
      showShortcutFeedback(
        isRepeat
            ? '连续快退 · ${formatDuration(target)}'
            : '后退 $seekStepSeconds 秒 · ${formatDuration(target)}',
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
      }
      keyboardSeekAction = PlayerShortcutAction.seekForward;
      final stepSeconds = isRepeat
          ? playerKeyboardSeekRepeatStepSeconds(seekStepSeconds)
          : seekStepSeconds;
      final target = seekRelative(
        Duration(seconds: stepSeconds),
        // 与后退保持相同会话语义，避免方向不同导致延迟门禁不可比较。
        mutePreview: isRepeat,
      );
      showShortcutFeedback(
        isRepeat
            ? '连续快进 · ${formatDuration(target)}'
            : '前进 $seekStepSeconds 秒 · ${formatDuration(target)}',
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

  void handlePointerDown(PointerDownEvent event) {
    if (event.buttons == kBackMouseButton) {
      unawaited(exitPlayer());
    }
  }
}
