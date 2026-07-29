import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'player_diagnostics_dialog.dart';
import 'player_dialog_content.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 展示播放器上下文菜单、视频信息与诊断入口。
 *
 * 这里只承载 [PlayerPageState] 的实现细节；播放会话、过滤队列与资源生命周期所有权
 * 仍保留在页面状态对象中。
 */
extension PlayerStateDialogs on PlayerPageState {
  Future<void> showPlayerContextMenu(TapDownDetails details) async {
    final infoItemKey = GlobalKey();
    final diagnosticsItemKey = GlobalKey();
    final viewSize = MediaQuery.sizeOf(context);
    await withPlayerOverlaySurfaceOccluded(() async {
      final actionFuture = showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          details.globalPosition.dx,
          details.globalPosition.dy,
          math.max(0.0, viewSize.width - details.globalPosition.dx),
          math.max(0.0, viewSize.height - details.globalPosition.dy),
        ),
        items: [
          PopupMenuItem(
            key: infoItemKey,
            value: 'info',
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.info_outline),
              title: Text('\u89c6\u9891\u4fe1\u606f'),
            ),
          ),
          PopupMenuItem(
            key: diagnosticsItemKey,
            value: 'diagnostics',
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.monitor_heart_outlined),
              title: Text('\u8bca\u65ad\u68c0\u67e5'),
            ),
          ),
        ],
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
        builder: (context) => AlertDialog(
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
                          value: formatBytes(stat?.size ?? item.fileSize ?? 0),
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
                      title: '异常',
                      icon: Icons.warning_amber_rounded,
                      child: Column(
                        children: [
                          if (item.mediaDetailsError != null)
                            PlayerDialogInfoRow(
                                label: '媒体信息', value: item.mediaDetailsError!),
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
