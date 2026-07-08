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
  });

  final VideoItem item;
  final String queueTitle;
  final int index;
  final int total;
  final List<String> activeTags;
  final String? activeChildTag;

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
