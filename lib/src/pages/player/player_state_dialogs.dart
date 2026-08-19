import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/player_media_controls.dart';
import '../../widgets/app_theme_tokens.dart';
import 'player_context_menu_items.dart';
import 'player_diagnostics_dialog.dart';
import 'player_dialog_content.dart';
import 'player_media_controls_widgets.dart';
import 'player_page.dart';
import 'player_state_precision_controls.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 展示播放器上下文菜单、视频信息与诊断入口。
 *
 * 这里只承载 [PlayerPageState] 的实现细节；播放会话、过滤队列与资源生命周期所有权
 * 仍保留在页面状态对象中。
 */
extension PlayerStateDialogs on PlayerPageState {
  /**
   * 显示仅属于当前媒体会话的音轨、字幕、同步与章节控制。
   *
   * 轨道 ID 和章节位置绝不写入播放设置或 filtered queue；每次打开面板均重新读取，
   * 防止快速切换媒体时误操作上一文件的轨道。
   */
  Future<void> showMediaControlsDialog() async {
    if (!mounted) return;
    await withPlayerOverlaySurfaceOccluded(
      () => showDialog<void>(
        context: context,
        builder: (dialogContext) => PlayerMediaControlsDialog(
          read: playerService.readMediaControls,
          selectAudio: playerService.selectAudioTrack,
          selectSubtitle: playerService.selectSubtitleTrack,
          seekChapter: playerService.seekChapter,
          adjustSubtitleDelay: playerService.adjustSubtitleDelay,
          adjustAudioDelay: playerService.adjustAudioDelay,
          loadExternalSubtitle: playerService.supportsExternalSubtitle
              ? loadExternalSubtitleWithFeedback
              : null,
          stepFrameBackward: playerService.supportsPrecisionControls
              ? () => stepFrameWithFeedback(backward: true)
              : null,
          stepFrameForward: playerService.supportsPrecisionControls
              ? () => stepFrameWithFeedback(backward: false)
              : null,
          setAbLoopStart: playerService.supportsPrecisionControls
              ? setAbLoopStartWithFeedback
              : null,
          setAbLoopEnd: playerService.supportsPrecisionControls
              ? setAbLoopEndWithFeedback
              : null,
          clearAbLoop: playerService.supportsPrecisionControls
              ? clearAbLoopWithFeedback
              : null,
        ),
      ),
    );
  }

  Future<void> cycleAudioTrack() async {
    final snapshot = await playerService.readMediaControls();
    if (!snapshot.supported || snapshot.audioTracks.isEmpty) {
      showShortcutFeedback('当前媒体没有可切换的音轨', Icons.audiotrack_outlined);
      return;
    }
    final current = snapshot.audioTracks.indexWhere((track) => track.selected);
    final target =
        snapshot.audioTracks[(current + 1) % snapshot.audioTracks.length];
    await playerService.selectAudioTrack(target.id);
    showShortcutFeedback('音轨：${target.label('音轨')}', Icons.audiotrack_rounded);
  }

  Future<void> cycleSubtitleTrack({required bool reverse}) async {
    final snapshot = await playerService.readMediaControls();
    if (!snapshot.supported || snapshot.subtitleTracks.isEmpty) {
      showShortcutFeedback('当前媒体没有字幕轨', Icons.subtitles_off_rounded);
      return;
    }
    final current =
        snapshot.subtitleTracks.indexWhere((track) => track.selected);
    final base = current < 0 ? (reverse ? 0 : -1) : current;
    final offset = reverse ? -1 : 1;
    final target = snapshot.subtitleTracks[
        (base + offset + snapshot.subtitleTracks.length) %
            snapshot.subtitleTracks.length];
    await playerService.selectSubtitleTrack(target.id);
    showShortcutFeedback('字幕：${target.label('字幕')}', Icons.subtitles_rounded);
  }

  Future<void> toggleSubtitleWithFeedback() async {
    await playerService.toggleSubtitle();
    final snapshot = await playerService.readMediaControls();
    final visible = snapshot.subtitleTracks.any((track) => track.selected);
    showShortcutFeedback(
      visible ? '已显示字幕' : '已关闭字幕',
      visible ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
    );
  }

  Future<void> adjustSubtitleDelayWithFeedback(Duration delta) async {
    await playerService.adjustSubtitleDelay(delta);
    final snapshot = await playerService.readMediaControls();
    showShortcutFeedback(
      '字幕延迟 ${_formatMediaDelay(snapshot.subtitleDelay)}',
      Icons.subtitles_rounded,
    );
  }

  Future<void> adjustAudioDelayWithFeedback(Duration delta) async {
    await playerService.adjustAudioDelay(delta);
    final snapshot = await playerService.readMediaControls();
    showShortcutFeedback(
      '音频延迟 ${_formatMediaDelay(snapshot.audioDelay)}',
      Icons.graphic_eq_rounded,
    );
  }

  Future<void> showPlayerContextMenu(TapDownDetails details) async {
    final infoItemKey = GlobalKey();
    final diagnosticsItemKey = GlobalKey();
    final viewSize = MediaQuery.sizeOf(context);
    final popupMenuTheme = playerDialogTheme(context).popupMenuTheme;
    await withPlayerOverlaySurfaceOccluded(() async {
      final actionFuture = showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          details.globalPosition.dx,
          details.globalPosition.dy,
          math.max(0.0, viewSize.width - details.globalPosition.dx),
          math.max(0.0, viewSize.height - details.globalPosition.dy),
        ),
        color: popupMenuTheme.color,
        elevation: popupMenuTheme.elevation,
        shape: popupMenuTheme.shape,
        semanticLabel: '播放器上下文菜单',
        items: buildPlayerContextMenuItems(
          infoItemKey: infoItemKey,
          diagnosticsItemKey: diagnosticsItemKey,
          includePrecisionControls: playerService.supportsPrecisionControls,
          includeExternalSubtitle: playerService.supportsExternalSubtitle,
        ),
      );
      scheduleContextMenuBoundsUpdate(
        <GlobalKey>[infoItemKey, diagnosticsItemKey],
      );
      final action = await actionFuture;
      if (!mounted) {
        return;
      }
      switch (action) {
        case 'info':
          await showVideoInfoDialog();
        case 'diagnostics':
          await showDiagnosticsDialog();
        case 'frame-backward':
          await stepFrameWithFeedback(backward: true);
        case 'frame-forward':
          await stepFrameWithFeedback(backward: false);
        case 'ab-loop-start':
          await setAbLoopStartWithFeedback();
        case 'ab-loop-end':
          await setAbLoopEndWithFeedback();
        case 'ab-loop-clear':
          await clearAbLoopWithFeedback();
        case 'external-subtitle':
          await loadExternalSubtitleWithFeedback();
      }
    }, overlayRect: estimatedContextMenuOverlayRect(details.globalPosition));
  }

  Future<void> showVideoInfoDialog() async {
    final item = currentItem;
    final stat = await pageWidget.fileSystem.statFile(item.path);
    final details = await detailsService.detailsFor(item);
    if (!mounted) {
      return;
    }
    await withPlayerOverlaySurfaceOccluded(
      () => showDialog<void>(
        context: context,
        builder: (context) => playerDialogThemeSurface(
          context: context,
          child: AlertDialog(
            key: const ValueKey('player.info.dialog'),
            title: const Row(
              children: [
                Icon(Icons.info_outline_rounded),
                SizedBox(width: 10),
                Text('视频信息'),
              ],
            ),
            content: SizedBox(
              width: 700,
              height: math.min(590, MediaQuery.sizeOf(context).height * 0.72),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    PlayerDialogSectionCard(
                      key: const ValueKey('player.info.fileSection'),
                      title: '文件',
                      icon: Icons.insert_drive_file_outlined,
                      child: Column(
                        children: [
                          PlayerDialogInfoRow(
                              label: '文件名', value: item.title, emphasize: true),
                          PlayerDialogInfoRow(label: '路径', value: item.path),
                          PlayerDialogInfoRow(label: '目录', value: item.folder),
                          PlayerDialogInfoRow(
                            label: '大小',
                            value:
                                formatBytes(stat?.size ?? item.fileSize ?? 0),
                          ),
                          PlayerDialogInfoRow(
                            label: '修改时间',
                            value: stat?.modifiedAt?.toString() ?? '未知',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    PlayerDialogSectionCard(
                      key: const ValueKey('player.info.mediaSection'),
                      title: '媒体',
                      icon: Icons.movie_outlined,
                      child: Column(
                        children: [
                          PlayerDialogInfoRow(
                              label: '视频', value: details.videoLabel),
                          PlayerDialogInfoRow(
                              label: '音频', value: details.audioLabel),
                          PlayerDialogInfoRow(
                              label: '媒体指纹',
                              value: item.mediaFingerprint ?? '未读取'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    PlayerDialogSectionCard(
                      key: const ValueKey('player.info.organizationSection'),
                      title: '整理状态',
                      icon: Icons.sell_outlined,
                      child: Column(
                        children: [
                          PlayerDialogInfoRow(
                              label: '标签',
                              value: item.tags.isEmpty
                                  ? '未添加'
                                  : (item.tags.toList()..sort()).join('、')),
                          PlayerDialogInfoRow(
                              label: '二级标签', value: childTagSummary(item)),
                          PlayerDialogInfoRow(
                              label: '收藏', value: item.isFavorite ? '是' : '否'),
                        ],
                      ),
                    ),
                    if (item.mediaDetailsError != null ||
                        item.thumbnailError != null) ...[
                      const SizedBox(height: 12),
                      PlayerDialogSectionCard(
                        key: const ValueKey('player.info.errorSection'),
                        title: '异常',
                        icon: Icons.warning_amber_rounded,
                        child: Column(
                          children: [
                            if (item.mediaDetailsError != null)
                              PlayerDialogInfoRow(
                                  label: '媒体信息',
                                  value: item.mediaDetailsError!),
                            if (item.thumbnailError != null)
                              PlayerDialogInfoRow(
                                  label: '缩略图', value: item.thumbnailError!),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> showDiagnosticsDialog() async {
    if (!mounted) {
      return;
    }
    await withPlayerOverlaySurfaceOccluded(
      () => showDialog<void>(
        context: context,
        builder: (context) => PlaybackDiagnosticsDialog(
          playingChanges: playerService.playingChanges,
          sample: buildDiagnosticsSnapshot,
          title: '\u64ad\u653e\u8bca\u65ad',
        ),
      ),
    );
  }

  /** 打开当前视频的 manual 标签编辑器，并在保存后刷新播放器上下文。 */
}

String _formatMediaDelay(Duration value) {
  final milliseconds = value.inMilliseconds;
  final sign = milliseconds >= 0 ? '+' : '-';
  return '$sign${(milliseconds.abs() / 1000).toStringAsFixed(1)} 秒';
}

/** 当前会话的媒体控制面板；操作完成后只刷新自己的快照，不触发播放队列重建。 */
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
                        value: _formatMediaDelay(snapshot.subtitleDelay),
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
                        value: _formatMediaDelay(snapshot.audioDelay),
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
