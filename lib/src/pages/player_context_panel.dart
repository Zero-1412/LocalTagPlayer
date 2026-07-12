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
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xff101722),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xff243044)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: Tooltip(
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
            ),
            const SizedBox(width: 12),
            Text(
              '${index + 1} / $total',
              style: const TextStyle(
                color: Color(0xffc4b5fd),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(
                conciseQueueTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xffaebbd0),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
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
            TextButton.icon(
              key: const ValueKey('player.editManualTags'),
              onPressed: onEditManualTags,
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: const Text('标签'),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xffc4b5fd)),
            ),
            PopupMenuButton<Object>(
              key: const ValueKey('player.more'),
              tooltip: '更多',
              color: const Color(0xff17202c),
              icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
              onSelected: (value) {
                if (value == 'reveal') onRevealFile();
                if (value == 'info') onVideoInfo();
                if (value == 'diagnostics') onDiagnostics();
                if (value is PlayerPlaybackMode) onPlaybackModeChanged(value);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'reveal', child: Text('打开文件位置')),
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
            const Text(
              '当前筛选队列已播放完毕',
              style: TextStyle(
                color: Color(0xffbbf7d0),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}
