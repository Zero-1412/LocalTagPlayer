part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 画面下方的精简视频身份与筛选上下文。
 *
 * 播放控制已经统一进入画面底部，本面板只保留标题、队列位置、标签特色入口和低频更多菜单。
 */
class _PlayerContextPanel extends StatelessWidget {
  const _PlayerContextPanel({
    required this.item,
    required this.queueTitle,
    required this.index,
    required this.total,
    required this.queueEndReached,
    required this.playbackMode,
    required this.onToggleFavorite,
    required this.onEditManualTags,
    required this.onRevealFile,
    required this.onVideoInfo,
    required this.onDiagnostics,
    required this.onPlaybackModeChanged,
  });

  final VideoItem item;
  final String queueTitle;
  final int index;
  final int total;
  final bool queueEndReached;
  final PlayerPlaybackMode playbackMode;
  final VoidCallback onToggleFavorite;
  final VoidCallback onEditManualTags;
  final VoidCallback onRevealFile;
  final VoidCallback onVideoInfo;
  final VoidCallback onDiagnostics;
  final ValueChanged<PlayerPlaybackMode> onPlaybackModeChanged;

  @override
  Widget build(BuildContext context) {
    final conciseQueueTitle = queueTitle.replaceAll('个结果', '项');
    final details = item.mediaDetails;
    final extension =
        p.extension(item.path).replaceFirst('.', '').toUpperCase();
    final metadata = <String>[
      if (item.playbackDuration > Duration.zero)
        _formatPanelDuration(item.playbackDuration),
      if (item.fileSize != null) _formatPanelBytes(item.fileSize!),
      if (extension.isNotEmpty) extension,
      if (details?.videoCodec?.trim().isNotEmpty ?? false)
        details!.videoCodec!.toUpperCase(),
      if (details?.audioCodec?.trim().isNotEmpty ?? false)
        details!.audioCodec!.toUpperCase(),
      if (details?.width != null && details?.height != null)
        '${details!.width}x${details.height}',
    ];
    final visibleTags = item.tags.toList()..sort();
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff101722),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xff243044)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xff211b50),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.video_library_outlined,
                  color: Color(0xff8b73ff), size: 27),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: item.title,
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Tooltip(
                    message: item.path,
                    child: Text(
                      item.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xff7f8ba0), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                '${index + 1} / $total',
                style: const TextStyle(
                  color: Color(0xffc4b5fd),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(metadata.join('  ·  '),
                  style:
                      const TextStyle(color: Color(0xff8996ab), fontSize: 11)),
            ]),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Wrap(
                spacing: 7,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(conciseQueueTitle,
                      style: const TextStyle(
                          color: Color(0xffaebbd0),
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  for (final tag in visibleTags.take(4))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xff151e36),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xff2b3856)),
                      ),
                      child: Text(tag,
                          style: const TextStyle(
                              color: Color(0xffaab6d0), fontSize: 11)),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: item.isFavorite ? '取消收藏' : '收藏',
              onPressed: onToggleFavorite,
              icon: Icon(
                  item.isFavorite ? Icons.favorite : Icons.favorite_border),
              color: item.isFavorite ? const Color(0xfffb7185) : Colors.white70,
              visualDensity: VisualDensity.compact,
            ),
            OutlinedButton.icon(
              key: const ValueKey('player.editManualTags'),
              onPressed: onEditManualTags,
              icon: const Icon(Icons.sell_outlined, size: 17),
              label: const Text('编辑标签'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xffd3ccff),
                side: const BorderSide(color: Color(0xff39486b)),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onRevealFile,
              icon: const Icon(Icons.folder_open_outlined, size: 17),
              label: const Text('打开文件位置'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xffc4cee0),
                side: const BorderSide(color: Color(0xff2b3856)),
              ),
            ),
            PopupMenuButton<Object>(
              key: const ValueKey('player.more'),
              tooltip: '更多',
              color: const Color(0xff17202c),
              icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
              onSelected: (value) {
                if (value == 'info') onVideoInfo();
                if (value == 'diagnostics') onDiagnostics();
                if (value is PlayerPlaybackMode) onPlaybackModeChanged(value);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'info', child: Text('视频信息')),
                const PopupMenuItem(value: 'diagnostics', child: Text('播放诊断')),
                const PopupMenuDivider(),
                for (final mode in PlayerPlaybackMode.values)
                  PopupMenuItem(
                    value: mode,
                    child: Row(children: [
                      Icon(mode.icon, size: 18),
                      const SizedBox(width: 8),
                      Text(mode.label),
                      if (mode == playbackMode) ...[
                        const Spacer(),
                        const Icon(Icons.check_rounded, size: 18),
                      ],
                    ]),
                  ),
              ],
            ),
          ]),
          if (queueEndReached)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '当前筛选队列已播放完毕',
                style: TextStyle(
                  color: Color(0xffbbf7d0),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _formatPanelDuration(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return value.inHours > 0
      ? '${value.inHours}:$minutes:$seconds'
      : '$minutes:$seconds';
}

String _formatPanelBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
