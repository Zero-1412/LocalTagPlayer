import 'dart:async';

import 'package:flutter/material.dart';

import '../../platform/platform_interfaces.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放器专业精确控制的页面协调层。
 *
 * 逐帧、A-B loop 与外挂字幕都只属于当前媒体会话；文件选择仍经过
 * [PlayerPage.fileSystem]，底层命令仍经过 [PlayerService]，不会触碰 filtered queue、
 * 用户设置或媒体库数据。
 */
extension PlayerStatePrecisionControls on PlayerPageState {
  /** 执行一帧原生命令；不支持时明确反馈，不能退回普通 seek。 */
  Future<void> stepFrameWithFeedback({required bool backward}) async {
    try {
      await playerService.stepFrame(backward: backward);
      showShortcutFeedback(
        backward ? '后退一帧' : '前进一帧',
        backward
            ? Icons.keyboard_double_arrow_left
            : Icons.keyboard_double_arrow_right,
      );
    } catch (_) {
      showShortcutFeedback('当前播放后端不支持逐帧', Icons.info_outline_rounded);
    }
  }

  /** 设置 A 点；若新 A 已越过旧 B，则先清除旧区间再建立新 A。 */
  Future<void> setAbLoopStartWithFeedback() async {
    final position = _clampedPrecisionPosition();
    final previousEnd = abLoopEnd;
    try {
      if (previousEnd != null && position >= previousEnd) {
        await playerService.clearAbLoop();
        await playerService.setAbLoopPoint(
          point: PlayerAbLoopPoint.start,
          position: position,
        );
        rebuild(() {
          abLoopStart = position;
          abLoopEnd = null;
        });
        showShortcutFeedback('A 点已更新，旧 B 点已清除', Icons.looks_one_rounded);
        return;
      }
      await playerService.setAbLoopPoint(
        point: PlayerAbLoopPoint.start,
        position: position,
      );
      rebuild(() => abLoopStart = position);
      showShortcutFeedback('已设置 A 点 ${formatControlDuration(position)}',
          Icons.looks_one_rounded);
    } catch (_) {
      showShortcutFeedback('当前播放后端不支持 A-B loop', Icons.info_outline_rounded);
    }
  }

  /** 设置 B 点；没有 A 或 B 不晚于 A 时拒绝，避免静默形成反向区间。 */
  Future<void> setAbLoopEndWithFeedback() async {
    final start = abLoopStart;
    final position = _clampedPrecisionPosition();
    if (start == null) {
      showShortcutFeedback('请先设置 A 点', Icons.looks_one_rounded);
      return;
    }
    if (position <= start) {
      showShortcutFeedback('B 点必须晚于 A 点', Icons.warning_amber_rounded);
      return;
    }
    try {
      await playerService.setAbLoopPoint(
        point: PlayerAbLoopPoint.end,
        position: position,
      );
      rebuild(() => abLoopEnd = position);
      showShortcutFeedback('已设置 B 点 ${formatControlDuration(position)}',
          Icons.looks_two_rounded);
    } catch (_) {
      showShortcutFeedback('当前播放后端不支持 A-B loop', Icons.info_outline_rounded);
    }
  }

  /** 清除当前媒体的 A/B 点，不改变播放位置或队列。 */
  Future<void> clearAbLoopWithFeedback() async {
    try {
      await playerService.clearAbLoop();
      rebuild(() {
        abLoopStart = null;
        abLoopEnd = null;
      });
      showShortcutFeedback('已清除 A-B loop', Icons.clear_rounded);
    } catch (_) {
      showShortcutFeedback('当前播放后端不支持 A-B loop', Icons.info_outline_rounded);
    }
  }

  /** 从平台文件选择器加载外挂字幕；选择结果不持久化。 */
  Future<void> loadExternalSubtitleWithFeedback() async {
    final task = currentMediaTaskContext;
    if (task == null || !playerService.supportsExternalSubtitle) {
      showShortcutFeedback('当前播放后端不支持外挂字幕', Icons.info_outline_rounded);
      return;
    }
    final path = await pageWidget.fileSystem.pickFile(
      dialogTitle: '选择外挂字幕',
      initialDirectory: currentItem.folder,
      allowedExtensions: const <String>[
        'srt',
        'ass',
        'ssa',
        'vtt',
        'sub',
        'sup',
      ],
    );
    if (path == null || !isCurrentMediaTask(task)) {
      return;
    }
    try {
      await playerService.addExternalSubtitle(path);
      if (mounted) {
        showShortcutFeedback('外挂字幕已加载', Icons.subtitles_rounded);
      }
    } catch (_) {
      if (mounted) {
        showShortcutFeedback('外挂字幕加载失败', Icons.warning_amber_rounded);
      }
    }
  }

  Duration _clampedPrecisionPosition() {
    final duration = playerService.state.duration;
    final position = playerService.state.position;
    if (duration <= Duration.zero) return position;
    return position < Duration.zero
        ? Duration.zero
        : position > duration
            ? duration
            : position;
  }
}
