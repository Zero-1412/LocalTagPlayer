part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

class _PlayerContextPanel extends StatelessWidget {
  const _PlayerContextPanel({
    required this.item,
    required this.queueTitle,
    required this.index,
    required this.total,
    required this.activeTags,
    required this.activeChildTag,
    required this.previousIndex,
    required this.nextIndex,
    required this.queueEndReached,
    required this.onEditManualTags,
    required this.onRevealFile,
    required this.onPlayIndex,
  });

  final VideoItem item;
  final String queueTitle;
  final int index;
  final int total;
  final List<String> activeTags;
  final String? activeChildTag;

  /** 可播放的上一条索引；为 null 时按钮禁用。 */
  final int? previousIndex;

  /** 可播放的下一条索引；为 null 时按钮禁用。 */
  final int? nextIndex;

  /** 当前筛选队列是否已经自然播放到末尾。 */
  final bool queueEndReached;

  /** 打开当前视频的 manual 标签快速编辑器。 */
  final VoidCallback onEditManualTags;

  /** 在系统文件管理器中定位当前视频。 */
  final VoidCallback onRevealFile;

  /** 用户通过显式前后项按钮请求切换播放的位置。 */
  final ValueChanged<int> onPlayIndex;

  @override
  Widget build(BuildContext context) {
    final tags = item.tags.toList()..sort();
    final visibleTags = [
      ...activeTags,
      if (activeChildTag != null) activeChildTag!,
      ...tags.where((tag) => !activeTags.contains(tag)).take(8),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff101722),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xff243044)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff94a3b8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('player.previous'),
                      onPressed: previousIndex == null
                          ? null
                          : () => onPlayIndex(previousIndex!),
                      icon: const Icon(Icons.skip_previous_rounded, size: 18),
                      label: const Text('上一条'),
                      style: _secondaryPlayerActionStyle,
                    ),
                    FilledButton.icon(
                      key: const ValueKey('player.next'),
                      onPressed: nextIndex == null
                          ? null
                          : () => onPlayIndex(nextIndex!),
                      icon: const Icon(Icons.skip_next_rounded, size: 18),
                      label: const Text('下一条'),
                      style: _primaryPlayerActionStyle,
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('player.editManualTags'),
                      onPressed: onEditManualTags,
                      icon: const Icon(Icons.sell_outlined, size: 18),
                      label: const Text('编辑标签'),
                      style: _secondaryPlayerActionStyle,
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('player.revealFile'),
                      onPressed: onRevealFile,
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: const Text('打开文件位置'),
                      style: _secondaryPlayerActionStyle,
                    ),
                  ],
                ),
                if (queueEndReached) ...[
                  const SizedBox(height: 10),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 17,
                        color: Color(0xff86efac),
                      ),
                      SizedBox(width: 6),
                      Flexible(
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
                ],
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 2,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                _PlayerMetaChip(
                  icon: Icons.playlist_play_rounded,
                  label: '${index + 1} / $total',
                  emphasized: true,
                ),
                _PlayerMetaChip(
                  icon: Icons.account_tree_outlined,
                  label: queueTitle,
                  emphasized: false,
                ),
                for (final tag in visibleTags)
                  _PlayerMetaChip(
                    icon: Icons.sell_outlined,
                    label: tag,
                    emphasized:
                        activeTags.contains(tag) || activeChildTag == tag,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/** 暗色播放器中普通操作的高对比度边框样式。 */
final ButtonStyle _secondaryPlayerActionStyle = OutlinedButton.styleFrom(
  foregroundColor: const Color(0xfff1f5f9),
  disabledForegroundColor: const Color(0xff94a3b8),
  side: const BorderSide(color: Color(0xff64748b)),
).copyWith(
  side: WidgetStateProperty.resolveWith((states) => BorderSide(
        color: states.contains(WidgetState.disabled)
            ? const Color(0xff475569)
            : const Color(0xff94a3b8),
      )),
);

/** 高频“下一条”使用主色填充，并保留可辨识的禁用状态。 */
final ButtonStyle _primaryPlayerActionStyle = FilledButton.styleFrom(
  backgroundColor: const Color(0xff6d5dfc),
  foregroundColor: Colors.white,
  disabledBackgroundColor: const Color(0xff334155),
  disabledForegroundColor: const Color(0xff94a3b8),
);

class _PlayerMetaChip extends StatelessWidget {
  const _PlayerMetaChip({
    required this.icon,
    required this.label,
    required this.emphasized,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: emphasized ? const Color(0xff312e81) : const Color(0xff17202c),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: emphasized ? const Color(0xff7c73ff) : const Color(0xff2d3a4d),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: emphasized ? Colors.white : const Color(0xff94a3b8),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: emphasized ? Colors.white : const Color(0xffcbd5e1),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
