import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'player_context_menu_items.dart';
import 'player_diagnostics_dialog.dart';
import 'player_dialog_content.dart';
import 'player_media_controls_dialog.dart' as media_controls;
import 'player_page.dart';
import 'player_state_precision_controls.dart';

export 'player_media_controls_dialog.dart';

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
        builder: (dialogContext) => media_controls.PlayerMediaControlsDialog(
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
      '字幕延迟 ${formatPlayerMediaDelay(snapshot.subtitleDelay)}',
      Icons.subtitles_rounded,
    );
  }

  Future<void> adjustAudioDelayWithFeedback(Duration delta) async {
    await playerService.adjustAudioDelay(delta);
    final snapshot = await playerService.readMediaControls();
    showShortcutFeedback(
      '音频延迟 ${formatPlayerMediaDelay(snapshot.audioDelay)}',
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
