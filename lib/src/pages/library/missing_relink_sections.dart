import 'package:flutter/material.dart';

import '../../models/video_item.dart';
import '../../widgets/app_theme_tokens.dart';
import '../../widgets/maintenance_feedback.dart';

// ignore_for_file: slash_for_doc_comments

/** 页面顶部说明 missing 只代表路径失效，稳定身份与用户数据仍然保留。 */
class MissingRelinkOverview extends StatelessWidget {
  const MissingRelinkOverview({
    super.key,
    required this.missingCount,
  });

  final int missingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: librarySurface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: libraryBorder),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: missingCount == 0
                  ? const Color(0x203fc487)
                  : appAccentViolet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Icon(
              missingCount == 0
                  ? Icons.check_circle_outline_rounded
                  : Icons.link_off_rounded,
              color:
                  missingCount == 0 ? const Color(0xff61d49a) : appAccentViolet,
              size: 26,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 240, maxWidth: 660),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  missingCount == 0 ? '所有视频路径均可访问' : '$missingCount 个视频路径失效',
                  style: const TextStyle(
                    color: libraryText,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  '缺失记录不会被自动删除。重新关联只更新 mutable path，并通过 fingerprint 防止选错文件。',
                  style: TextStyle(
                    color: libraryTextMuted,
                    fontSize: 13,
                    height: 1.42,
                  ),
                ),
              ],
            ),
          ),
          const _RelinkDataBadge(
            icon: Icons.shield_outlined,
            label: '标签与播放记录已保留',
          ),
        ],
      ),
    );
  }
}

/** 缺失条目列表结构表面；空态与有数据状态共享稳定布局。 */
class MissingVideoList extends StatelessWidget {
  const MissingVideoList({
    super.key,
    required this.missing,
    required this.relinkingVideoIds,
    required this.onRelink,
  });

  final List<VideoItem> missing;
  final Set<String> relinkingVideoIds;
  final ValueChanged<VideoItem> onRelink;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: librarySurface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: libraryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '待处理视频',
                    style: TextStyle(
                      color: libraryText,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${missing.length} 项',
                  style: const TextStyle(
                    color: libraryTextMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: missing.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          color: Color(0xff61d49a),
                          size: 36,
                        ),
                        SizedBox(height: 12),
                        Text(
                          '当前没有缺失视频',
                          style: TextStyle(
                            color: libraryText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '扫描发现路径失效时，记录会安全保留在这里。',
                          style: TextStyle(color: libraryTextMuted),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    key: const ValueKey('missingRelink.list'),
                    padding: const EdgeInsets.all(12),
                    itemCount: missing.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = missing[index];
                      return _MissingVideoRow(
                        item: item,
                        busy: relinkingVideoIds.contains(item.videoId),
                        onRelink: () => onRelink(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/** 单个 missing 条目的内容优先行，窄宽与大文字下动作自然换到下一行。 */
class _MissingVideoRow extends StatelessWidget {
  const _MissingVideoRow({
    required this.item,
    required this.busy,
    required this.onRelink,
  });

  final VideoItem item;
  final bool busy;
  final VoidCallback onRelink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: libraryBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final compact = constraints.maxWidth < 620 || textScale > 1.3;
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x20e0a24c),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: const Icon(
                  Icons.link_off_rounded,
                  color: Color(0xffe4aa58),
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: libraryText,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    MaintenanceTooltip(
                      message: item.path,
                      child: Text(
                        item.path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: libraryTextMuted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final action = FilledButton.icon(
            key: ValueKey('missingRelink.${item.videoId}'),
            onPressed: busy ? null : onRelink,
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.find_in_page_outlined, size: 18),
            label: Text(busy ? '校验中' : '重新关联'),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 16),
              action,
            ],
          );
        },
      ),
    );
  }
}

/** missing 数据保留角标使用图标与文字双重编码。 */
class _RelinkDataBadge extends StatelessWidget {
  const _RelinkDataBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.capsule),
        border: Border.all(color: libraryBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: appAccentViolet),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: libraryText,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
