part of '../../app.dart';

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
    required this.onToggleFavorite,
    required this.onEditManualTags,
    required this.onRevealFile,
    required this.onVideoInfo,
  });

  final VideoItem item;
  final String queueTitle;
  final int index;
  final int total;
  final bool queueEndReached;
  final VoidCallback onToggleFavorite;
  final VoidCallback onEditManualTags;
  final VoidCallback onRevealFile;
  final VoidCallback onVideoInfo;

  @override
  Widget build(BuildContext context) {
    final details = item.mediaDetails;
    final extension =
        p.extension(item.path).replaceFirst('.', '').toUpperCase();
    final displayTitle = extension.isNotEmpty &&
            !item.title.toLowerCase().endsWith('.${extension.toLowerCase()}')
        ? '${item.title}.${extension.toLowerCase()}'
        : item.title;
    final codecSummary = <String>[
      if (extension.isNotEmpty) extension,
      if (details?.videoCodec?.trim().isNotEmpty ?? false)
        details!.videoCodec!.toUpperCase(),
      if (details?.audioCodec?.trim().isNotEmpty ?? false)
        details!.audioCodec!.toUpperCase(),
    ].join('  ·  ');
    final visibleTags = item.tags.toList()..sort();
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xff101722),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xff243044)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xff211b50),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.video_library_outlined,
                  color: Color(0xff8b73ff), size: 31),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Tooltip(
                        message: displayTitle,
                        child: Text(
                          displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: '编辑标签',
                      onPressed: onEditManualTags,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined,
                          size: 18, color: Color(0xff9aa8c2)),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Tooltip(
                    message: item.path,
                    child: Text(
                      item.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xff8794ac), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (item.playbackDuration > Duration.zero)
                  _PlayerMetadataItem(
                    icon: Icons.schedule_rounded,
                    label: _formatPanelDuration(item.playbackDuration),
                  ),
                if (item.fileSize != null)
                  _PlayerMetadataItem(
                    icon: Icons.description_outlined,
                    label: _formatPanelBytes(item.fileSize!),
                  ),
                if (codecSummary.isNotEmpty)
                  _PlayerMetadataItem(
                    icon: Icons.center_focus_weak_rounded,
                    label: codecSummary,
                  ),
                if (details?.width != null && details?.height != null)
                  _PlayerResolutionBadge(
                    label: '${details!.width}x${details.height}',
                  ),
              ],
            ),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xff202b40)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Wrap(
                spacing: 7,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('标签',
                      style: TextStyle(color: Color(0xff8794ac), fontSize: 12)),
                  for (final tag in visibleTags.take(4))
                    _PlayerTagChip(label: tag),
                  ActionChip(
                    onPressed: onEditManualTags,
                    avatar: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('添加标签'),
                    side: const BorderSide(color: Color(0xff2b3856)),
                    backgroundColor: const Color(0xff151e36),
                    labelStyle: const TextStyle(
                      color: Color(0xffaab6d0),
                      fontSize: 11,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
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
              position: PopupMenuPosition.under,
              offset: const Offset(0, 6),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xff2b3856)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.more_horiz_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('更多', style: TextStyle(color: Color(0xffc4cee0))),
                ]),
              ),
              onSelected: (value) {
                if (value == 'favorite') onToggleFavorite();
                if (value == 'info') onVideoInfo();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'favorite',
                  child: Text(item.isFavorite ? '取消收藏' : '收藏'),
                ),
                const PopupMenuItem(value: 'info', child: Text('视频信息')),
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

/** 信息卡顶部的图标化媒体摘要。 */
class _PlayerMetadataItem extends StatelessWidget {
  const _PlayerMetadataItem({required this.icon, required this.label});

  /** 摘要类型图标。 */
  final IconData icon;

  /** 当前媒体的摘要值。 */
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 17, color: const Color(0xff7686a3)),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(color: Color(0xff8996ab), fontSize: 11)),
    ]);
  }
}

/** 蓝图中的独立分辨率徽标。 */
class _PlayerResolutionBadge extends StatelessWidget {
  const _PlayerResolutionBadge({required this.label});

  /** 视频像素尺寸。 */
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xff121b2e),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xff283550)),
      ),
      child: Text(label,
          style: const TextStyle(color: Color(0xff9ba8c2), fontSize: 11)),
    );
  }
}

/** 当前视频已关联标签的紧凑胶囊展示。 */
class _PlayerTagChip extends StatelessWidget {
  const _PlayerTagChip({required this.label});

  /** 标签名称。 */
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xff151e36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xff2b3856)),
      ),
      child: Text(label,
          style: const TextStyle(color: Color(0xffaab6d0), fontSize: 11)),
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
