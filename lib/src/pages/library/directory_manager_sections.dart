import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 页面顶部的资料库状态与数据保留说明。 */
class DirectoryOverview extends StatelessWidget {
  const DirectoryOverview({
    super.key,
    required this.rootCount,
    required this.scanning,
  });

  final int rootCount;
  final bool scanning;

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
        spacing: 20,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(
            Icons.folder_copy_outlined,
            size: 30,
            color: appAccentViolet,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$rootCount 个受管理目录',
                  style: const TextStyle(
                    color: libraryText,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  '目录决定当前媒体库的扫描范围。解除管理只隐藏对应内容，不会删除磁盘文件或用户整理数据。',
                  style: TextStyle(
                    color: libraryTextMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          _DirectoryStatusBadge(
            icon: scanning ? Icons.sync_rounded : Icons.check_circle_rounded,
            label: scanning ? '正在处理' : '资料库就绪',
            active: scanning,
          ),
        ],
      ),
    );
  }
}

/** 目录列表结构表面，空状态与列表共享同一空间锚点。 */
class DirectoryRootList extends StatelessWidget {
  const DirectoryRootList({
    super.key,
    required this.roots,
    required this.busy,
    required this.onRemove,
    required this.onAdd,
  });

  final List<String> roots;
  final bool busy;
  final ValueChanged<String> onRemove;
  final VoidCallback onAdd;

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
                    '本地媒体目录',
                    style: TextStyle(
                      color: libraryText,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${roots.length} 项',
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
            child: roots.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.create_new_folder_outlined,
                          size: 34,
                          color: libraryTextMuted,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '还没有添加本地视频目录',
                          style: TextStyle(
                            color: libraryText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '添加目录后，播放器会扫描并建立标签索引。',
                          style: TextStyle(color: libraryTextMuted),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: busy ? null : onAdd,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('添加第一个目录'),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: roots.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final root = roots[index];
                      return _DirectoryRootCard(
                        root: root,
                        busy: busy,
                        onRemove: () => onRemove(root),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/** 单个受管理 root 的内容优先卡片。 */
class _DirectoryRootCard extends StatelessWidget {
  const _DirectoryRootCard({
    required this.root,
    required this.busy,
    required this.onRemove,
  });

  final String root;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('directoryManager.root.$root'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: libraryBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final identity = Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: appAccentViolet.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: const Icon(
                  Icons.folder_rounded,
                  color: appAccentViolet,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Tooltip(
                  message: root,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '受管理目录',
                        style: TextStyle(
                          color: libraryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        root,
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: libraryTextMuted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
          final action = OutlinedButton.icon(
            key: ValueKey('directoryManager.remove.$root'),
            onPressed: busy ? null : onRemove,
            icon: const Icon(Icons.folder_off_outlined, size: 18),
            label: const Text('解除管理'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xffe07280),
              side: const BorderSide(color: Color(0x66e07280)),
            ),
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

/** 扫描状态角标使用文字和图标共同编码，不只依赖颜色。 */
class _DirectoryStatusBadge extends StatelessWidget {
  const _DirectoryStatusBadge({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? appAccentViolet.withValues(alpha: 0.12)
            : librarySurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.capsule),
        border: Border.all(
          color:
              active ? appAccentViolet.withValues(alpha: 0.42) : libraryBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: active ? appAccentViolet : libraryText),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: active ? appAccentViolet : libraryText,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/** 确认弹窗中的稳定身份数据保留说明。 */
class DirectoryDataPolicy extends StatelessWidget {
  const DirectoryDataPolicy({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 18, color: appAccentViolet),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            '标签关系、收藏、播放进度、媒体详情和稳定视频身份都会保留；以后重新添加同一目录或匹配到相同文件时会自动恢复。',
            style: TextStyle(
              color: libraryTextMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
