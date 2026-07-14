import 'package:flutter/material.dart';

import '../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/** 用户再次打开有有效进度的视频时选择的起播方式。 */
enum PlayerResumeChoice { continueWatching, restart }

/** 格式化恢复位置，避免弹窗暴露底层 Duration 表示。 */
String _resumeTimeLabel(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/**
 * 询问用户继续上次位置还是从头播放；关闭弹窗默认继续，避免无意丢弃稳定进度。
 */
Future<PlayerResumeChoice> showPlayerResumeDialog(
  BuildContext context, {
  required VideoItem item,
  required Duration position,
  required Duration duration,
}) async {
  final choice = await showDialog<PlayerResumeChoice>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('继续观看？'),
      content: Text(
        '${item.title}\n上次看到 ${_resumeTimeLabel(position)} / ${_resumeTimeLabel(duration)}',
      ),
      actions: [
        OutlinedButton(
          key: const ValueKey('player.resume.restart'),
          onPressed: () =>
              Navigator.of(dialogContext).pop(PlayerResumeChoice.restart),
          child: const Text('从头播放'),
        ),
        FilledButton(
          key: const ValueKey('player.resume.continue'),
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext)
              .pop(PlayerResumeChoice.continueWatching),
          child: const Text('从上次位置继续'),
        ),
      ],
    ),
  );
  return choice ?? PlayerResumeChoice.continueWatching;
}
