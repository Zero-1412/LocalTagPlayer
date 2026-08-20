import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/player_media_controls.dart';
import '../../widgets/app_theme_tokens.dart';
import 'player_media_controls_widgets.dart';

/// 当前会话的媒体控制面板；操作完成后只刷新自己的快照，不触发播放队列重建。
class PlayerMediaControlsDialog extends StatefulWidget {
  const PlayerMediaControlsDialog({
    super.key,
    required this.read,
    required this.selectAudio,
    required this.selectSubtitle,
    required this.seekChapter,
    required this.adjustSubtitleDelay,
    required this.adjustAudioDelay,
    this.loadExternalSubtitle,
    this.stepFrameBackward,
    this.stepFrameForward,
    this.setAbLoopStart,
    this.setAbLoopEnd,
    this.clearAbLoop,
  });

  final Future<PlayerMediaControlsSnapshot> Function() read;
  final Future<void> Function(String trackId) selectAudio;
  final Future<void> Function(String trackId) selectSubtitle;
  final Future<void> Function(int chapterIndex) seekChapter;
  final Future<void> Function(Duration delta) adjustSubtitleDelay;
  final Future<void> Function(Duration delta) adjustAudioDelay;
  final Future<void> Function()? loadExternalSubtitle;
  final Future<void> Function()? stepFrameBackward;
  final Future<void> Function()? stepFrameForward;
  final Future<void> Function()? setAbLoopStart;
  final Future<void> Function()? setAbLoopEnd;
  final Future<void> Function()? clearAbLoop;

  @override
  State<PlayerMediaControlsDialog> createState() =>
      _PlayerMediaControlsDialogState();
}

class _PlayerMediaControlsDialogState extends State<PlayerMediaControlsDialog> {
  late Future<PlayerMediaControlsSnapshot> _snapshot = widget.read();

  void _refresh() {
    // 先创建异步读取任务，再同步更新 State；setState 回调不能返回 Future。
    final snapshot = widget.read();
    setState(() {
      _snapshot = snapshot;
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      // 后端拒绝已过期的轨道或章节时只刷新当前会话；不把底层错误正文展示给用户。
    }
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    return Theme(
      data: playerWorkspaceTheme(
        Theme.of(context),
        highContrast: accessibility.highContrast,
      ),
      child: AlertDialog(
        key: const ValueKey('player.mediaControls.dialog'),
        title: const Row(
          children: [
            Icon(Icons.tune_rounded),
            SizedBox(width: 10),
            Text('媒体控制'),
          ],
        ),
        content: SizedBox(
          width: 620,
          height: math.min(560, MediaQuery.sizeOf(context).height * 0.7),
          child: FutureBuilder<PlayerMediaControlsSnapshot>(
            future: _snapshot,
            builder: (context, state) {
              final snapshot = state.data;
              if (state.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot == null || !snapshot.supported) {
                return const Center(child: Text('当前播放后端不支持媒体控制。'));
              }
              return ListView(
                key: const ValueKey('player.mediaControls.content'),
                children: [
                  PlayerMediaControlSection(
                    key: const ValueKey('player.mediaControls.audioTracks'),
                    title: '音轨',
                    icon: Icons.audiotrack_rounded,
                    emptyLabel: '当前媒体没有可选音轨',
                    children: snapshot.audioTracks
                        .map(
                          (track) => buildPlayerMediaTrackTile(
                            track: track,
                            fallback: '音轨 ${track.id}',
                            onTap: () =>
                                _run(() => widget.selectAudio(track.id)),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 12),
                  PlayerMediaControlSection(
                    key: const ValueKey('player.mediaControls.subtitles'),
                    title: '字幕',
                    icon: Icons.subtitles_rounded,
                    emptyLabel: '当前媒体没有内嵌字幕',
                    children: [
                      ListTile(
                        dense: true,
                        selected: !snapshot.subtitleTracks
                            .any((item) => item.selected),
                        leading: Icon(
                          snapshot.subtitleTracks.any((item) => item.selected)
                              ? Icons.radio_button_unchecked_rounded
                              : Icons.radio_button_checked_rounded,
                        ),
                        onTap: () => _run(() => widget.selectSubtitle('no')),
                        title: const Text('关闭字幕'),
                      ),
                      ...snapshot.subtitleTracks.map(
                        (track) => buildPlayerMediaTrackTile(
                          track: track,
                          fallback: '字幕 ${track.id}',
                          onTap: () =>
                              _run(() => widget.selectSubtitle(track.id)),
                        ),
                      ),
                      PlayerMediaDelayControlRow(
                        key: const ValueKey(
                          'player.mediaControls.subtitleDelay',
                        ),
                        label: '字幕延迟',
                        value: formatPlayerMediaDelay(snapshot.subtitleDelay),
                        onDecrease: () => _run(
                          () => widget.adjustSubtitleDelay(
                            const Duration(milliseconds: -100),
                          ),
                        ),
                        onIncrease: () => _run(
                          () => widget.adjustSubtitleDelay(
                            const Duration(milliseconds: 100),
                          ),
                        ),
                      ),
                      if (widget.loadExternalSubtitle != null)
                        ListTile(
                          key: const ValueKey(
                            'player.mediaControls.externalSubtitle',
                          ),
                          dense: true,
                          leading: const Icon(Icons.subtitles_rounded),
                          title: const Text('加载外挂字幕'),
                          subtitle: const Text('仅加入当前播放会话，不写入媒体库'),
                          onTap: () => _run(widget.loadExternalSubtitle!),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  PlayerMediaControlSection(
                    key: const ValueKey('player.mediaControls.sync'),
                    title: '音画同步',
                    icon: Icons.graphic_eq_rounded,
                    emptyLabel: '',
                    children: [
                      PlayerMediaDelayControlRow(
                        key: const ValueKey('player.mediaControls.audioDelay'),
                        label: '音频延迟',
                        value: formatPlayerMediaDelay(snapshot.audioDelay),
                        onDecrease: () => _run(
                          () => widget.adjustAudioDelay(
                            const Duration(milliseconds: -100),
                          ),
                        ),
                        onIncrease: () => _run(
                          () => widget.adjustAudioDelay(
                            const Duration(milliseconds: 100),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.stepFrameBackward != null ||
                      widget.stepFrameForward != null ||
                      widget.setAbLoopStart != null ||
                      widget.setAbLoopEnd != null ||
                      widget.clearAbLoop != null) ...[
                    const SizedBox(height: 12),
                    PlayerMediaControlSection(
                      key: const ValueKey('player.mediaControls.precision'),
                      title: '逐帧与 A-B loop',
                      icon: Icons.center_focus_strong_rounded,
                      emptyLabel: '',
                      children: [
                        if (widget.stepFrameBackward != null)
                          ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.keyboard_double_arrow_left,
                            ),
                            title: const Text('后退一帧'),
                            onTap: () => _run(widget.stepFrameBackward!),
                          ),
                        if (widget.stepFrameForward != null)
                          ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.keyboard_double_arrow_right,
                            ),
                            title: const Text('前进一帧'),
                            onTap: () => _run(widget.stepFrameForward!),
                          ),
                        if (widget.setAbLoopStart != null)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.looks_one_rounded),
                            title: const Text('设置 A 点'),
                            onTap: () => _run(widget.setAbLoopStart!),
                          ),
                        if (widget.setAbLoopEnd != null)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.looks_two_rounded),
                            title: const Text('设置 B 点'),
                            onTap: () => _run(widget.setAbLoopEnd!),
                          ),
                        if (widget.clearAbLoop != null)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.clear_rounded),
                            title: const Text('清除 A-B loop'),
                            onTap: () => _run(widget.clearAbLoop!),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  PlayerMediaControlSection(
                    key: const ValueKey('player.mediaControls.chapters'),
                    title: '章节',
                    icon: Icons.bookmarks_outlined,
                    emptyLabel: '当前媒体没有章节信息',
                    children: snapshot.chapters
                        .map(
                          (chapter) => ListTile(
                            dense: true,
                            leading: Text('${chapter.index + 1}'),
                            title: Text(
                              chapter.title ?? '章节 ${chapter.index + 1}',
                            ),
                            subtitle: Text(
                              formatPlayerMediaChapterPosition(
                                chapter.position,
                              ),
                            ),
                            onTap: () =>
                                _run(() => widget.seekChapter(chapter.index)),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: _refresh, child: const Text('刷新')),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

/// 格式化媒体控制延迟，供页面快捷反馈与媒体控制面板共享。
String formatPlayerMediaDelay(Duration value) {
  final milliseconds = value.inMilliseconds;
  final sign = milliseconds >= 0 ? '+' : '-';
  return '$sign${(milliseconds.abs() / 1000).toStringAsFixed(1)} 秒';
}
