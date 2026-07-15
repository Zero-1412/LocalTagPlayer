import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../models/video_item.dart';
import 'player_queue_sidebar.dart';

// ignore_for_file: slash_for_doc_comments

/** 统一播放器侧栏当前展示的一级视图。 */
enum PlayerSidePanelView {
  /** 当前筛选结果列表。 */
  queue,

  /** 当前正在播放视频的详情。 */
  details,
}

/**
 * 播放器右侧统一侧栏。
 *
 * “列表”和“详情”处于同一层级，切换只替换右侧内容，不重建播放会话、filtered
 * queue 或视频画面。原画面下方的信息与操作全部迁入详情视图。
 */
class PlayerSidePanel extends StatefulWidget {
  const PlayerSidePanel({
    super.key,
    required this.queuePanel,
    required this.item,
    required this.queueEndReached,
    required this.onToggleFavorite,
    required this.onEditManualTags,
    required this.onRevealFile,
    required this.onVideoInfo,
  });

  /** 原有 filtered queue 内容；隐藏详情时才挂载，避免离屏列表继续构建。 */
  final Widget queuePanel;

  /** 当前实际正在播放的视频，而不是队列中仅被单击选中的视频。 */
  final VideoItem item;

  /** 当前筛选队列是否已经顺序播放到末尾。 */
  final bool queueEndReached;

  /** 收藏或取消收藏当前视频。 */
  final VoidCallback onToggleFavorite;

  /** 打开当前视频的手动标签编辑器。 */
  final VoidCallback onEditManualTags;

  /** 通过平台文件系统边界打开当前文件位置。 */
  final VoidCallback onRevealFile;

  /** 打开保留的完整视频信息弹窗。 */
  final VoidCallback onVideoInfo;

  @override
  State<PlayerSidePanel> createState() => _PlayerSidePanelState();
}

/** 只维护侧栏视图选择；播放、队列和标签状态继续由 PlayerPage 持有。 */
class _PlayerSidePanelState extends State<PlayerSidePanel> {
  PlayerSidePanelView _view = PlayerSidePanelView.queue;

  /** 切换一级侧栏视图，不触发媒体读取或队列重算。 */
  void _selectView(PlayerSidePanelView view) {
    if (_view == view) {
      return;
    }
    setState(() => _view = view);
  }

  @override
  Widget build(BuildContext context) {
    final sidebarWidth = playerQueueSidebarWidthForWindow(
      MediaQuery.sizeOf(context).width,
    );
    return Container(
      width: sidebarWidth,
      margin: const EdgeInsets.fromLTRB(0, 18, 14, 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xff0d1528),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xff202c46)),
      ),
      child: Column(
        children: [
          _PlayerSidePanelTabs(
            selected: _view,
            onSelected: _selectView,
          ),
          Expanded(
            child: _view == PlayerSidePanelView.queue
                ? KeyedSubtree(
                    key: const ValueKey('player.sidebar.queue'),
                    child: widget.queuePanel,
                  )
                : PlayerVideoDetailsPanel(
                    key: const ValueKey('player.sidebar.details'),
                    item: widget.item,
                    queueEndReached: widget.queueEndReached,
                    onToggleFavorite: widget.onToggleFavorite,
                    onEditManualTags: widget.onEditManualTags,
                    onRevealFile: widget.onRevealFile,
                    onVideoInfo: widget.onVideoInfo,
                  ),
          ),
        ],
      ),
    );
  }
}

/** “列表/详情”同级切换栏，不把详情伪装成队列内部的次级动作。 */
class _PlayerSidePanelTabs extends StatelessWidget {
  const _PlayerSidePanelTabs({
    required this.selected,
    required this.onSelected,
  });

  /** 当前展示的一级侧栏视图。 */
  final PlayerSidePanelView selected;

  /** 用户切换视图时的轻量状态回调。 */
  final ValueChanged<PlayerSidePanelView> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Color(0xff0b1324),
        border: Border(bottom: BorderSide(color: Color(0xff243044))),
      ),
      child: SizedBox(
        key: const ValueKey('player.sidebar.tabs.segment'),
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xff0a1324),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xff2b3853), width: 1.2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Row(
              children: [
                Expanded(
                  child: _PlayerSidePanelTab(
                    key: const ValueKey('player.sidebar.tab.queue'),
                    surfaceKey: const ValueKey(
                      'player.sidebar.tab.queue.surface',
                    ),
                    label: '列表',
                    icon: Icons.playlist_play_rounded,
                    selected: selected == PlayerSidePanelView.queue,
                    position: _PlayerSidePanelTabPosition.leading,
                    onPressed: () => onSelected(PlayerSidePanelView.queue),
                  ),
                ),
                Expanded(
                  child: _PlayerSidePanelTab(
                    key: const ValueKey('player.sidebar.tab.details'),
                    surfaceKey: const ValueKey(
                      'player.sidebar.tab.details.surface',
                    ),
                    label: '详情',
                    icon: Icons.info_outline_rounded,
                    selected: selected == PlayerSidePanelView.details,
                    position: _PlayerSidePanelTabPosition.trailing,
                    onPressed: () => onSelected(PlayerSidePanelView.details),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/** 标识标签位于连续分段控件的左半区或右半区。 */
enum _PlayerSidePanelTabPosition { leading, trailing }

/** 单个侧栏一级标签，使用稳定按钮输入链路支持鼠标和键盘。 */
class _PlayerSidePanelTab extends StatelessWidget {
  const _PlayerSidePanelTab({
    super.key,
    required this.surfaceKey,
    required this.label,
    required this.icon,
    required this.selected,
    required this.position,
    required this.onPressed,
  });

  /** 供视觉回归测试稳定读取选中背景的表面标识。 */
  final Key surfaceKey;

  /** 标签文字。 */
  final String label;

  /** 标签语义图标。 */
  final IconData icon;

  /** 是否为当前一级视图。 */
  final bool selected;

  /** 当前标签在连续分段控件中的位置，用于只保留外侧圆角。 */
  final _PlayerSidePanelTabPosition position;

  /** 切换视图的回调。 */
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final outerRadius = position == _PlayerSidePanelTabPosition.leading
        ? const BorderRadius.horizontal(left: Radius.circular(9))
        : const BorderRadius.horizontal(right: Radius.circular(9));
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        key: surfaceKey,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? null : Colors.transparent,
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xff5c3bb3), Color(0xff7447c8)],
                )
              : null,
          borderRadius: outerRadius,
          border: selected
              ? Border.all(color: const Color(0xff8066ff), width: 1.2)
              : null,
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x405c45d8),
                    blurRadius: 12,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: outerRadius,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 23,
                  color: selected
                      ? const Color(0xfff5f2ff)
                      : const Color(0xff8793a8),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xfff5f2ff)
                        : const Color(0xff8793a8),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/**
 * 当前播放视频详情。
 *
 * 面板只读取 `VideoItem` 已有字段，不在切换详情时启动 FFprobe、缩略图或文件 stat。
 */
class PlayerVideoDetailsPanel extends StatelessWidget {
  const PlayerVideoDetailsPanel({
    super.key,
    required this.item,
    required this.queueEndReached,
    required this.onToggleFavorite,
    required this.onEditManualTags,
    required this.onRevealFile,
    required this.onVideoInfo,
  });

  /** 当前实际正在播放的视频。 */
  final VideoItem item;

  /** 当前 filtered queue 是否已经播放到末尾。 */
  final bool queueEndReached;

  /** 收藏或取消收藏当前视频。 */
  final VoidCallback onToggleFavorite;

  /** 编辑当前视频手动标签。 */
  final VoidCallback onEditManualTags;

  /** 打开当前文件位置。 */
  final VoidCallback onRevealFile;

  /** 打开完整视频信息弹窗。 */
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
    final visibleTags = item.tags.toList()..sort();
    final codecSummary = <String>[
      if (details?.videoCodec?.trim().isNotEmpty ?? false)
        details!.videoCodec!.toUpperCase(),
      if (details?.audioCodec?.trim().isNotEmpty ?? false)
        details!.audioCodec!.toUpperCase(),
    ].join(' / ');

    return ListView(
      key: const ValueKey('player.sidebar.details.scroll'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '当前视频详情',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (item.isMissing)
              const _PlayerDetailStatus(label: '文件缺失', warning: true)
            else
              const _PlayerDetailStatus(label: '正在播放'),
          ],
        ),
        if (queueEndReached) ...[
          const SizedBox(height: 10),
          const _PlayerQueueEndNotice(),
        ],
        const SizedBox(height: 12),
        _PlayerDetailCard(
          title: '文件名',
          trailing: IconButton(
            tooltip: '编辑标签',
            onPressed: onEditManualTags,
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: const Color(0xffa9b8ff),
            visualDensity: VisualDensity.compact,
          ),
          child: SelectableText(
            displayTitle,
            style: const TextStyle(
              color: Color(0xffe7ecf7),
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _PlayerDetailCard(
          title: '标签',
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final tag in visibleTags) _PlayerDetailTagChip(label: tag),
              ActionChip(
                onPressed: onEditManualTags,
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: Text(visibleTags.isEmpty ? '添加标签' : '继续添加'),
                side: const BorderSide(color: Color(0xff39486b)),
                backgroundColor: const Color(0xff151e36),
                labelStyle: const TextStyle(
                  color: Color(0xffb9c4dc),
                  fontSize: 11,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _PlayerDetailCard(
          title: '文件信息',
          child: Column(
            children: [
              _PlayerDetailRow(
                label: '时长',
                value: item.playbackDuration > Duration.zero
                    ? _formatPanelDuration(item.playbackDuration)
                    : '未知',
              ),
              _PlayerDetailRow(
                label: '大小',
                value: item.fileSize == null
                    ? '未知'
                    : _formatPanelBytes(item.fileSize!),
              ),
              _PlayerDetailRow(
                label: '分辨率',
                value: details?.width != null && details?.height != null
                    ? '${details!.width}×${details.height}'
                    : '未知',
              ),
              _PlayerDetailRow(
                label: '格式',
                value: extension.isEmpty ? '未知' : extension,
              ),
              _PlayerDetailRow(
                label: '编码',
                value: codecSummary.isEmpty ? '未知' : codecSummary,
                showDivider: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _PlayerDetailCard(
          title: '文件路径',
          child: SelectableText(
            item.path,
            style: const TextStyle(
              color: Color(0xffaab6d0),
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('player.editManualTags'),
                onPressed: onEditManualTags,
                icon: const Icon(Icons.sell_outlined, size: 17),
                label: const Text('编辑标签'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onRevealFile,
                icon: const Icon(Icons.folder_open_outlined, size: 17),
                label: const Text('打开位置'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PopupMenuButton<String>(
          key: const ValueKey('player.more'),
          tooltip: '更多操作',
          color: const Color(0xff17202c),
          position: PopupMenuPosition.under,
          onSelected: (value) {
            if (value == 'favorite') {
              onToggleFavorite();
            } else if (value == 'info') {
              onVideoInfo();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'favorite',
              child: Text(item.isFavorite ? '取消收藏' : '收藏'),
            ),
            const PopupMenuItem(value: 'info', child: Text('完整视频信息')),
          ],
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xff2b3856)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.more_horiz_rounded, size: 18),
                SizedBox(width: 8),
                Text('更多操作'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/** 详情分区卡片，统一标题、边框和内部留白。 */
class _PlayerDetailCard extends StatelessWidget {
  const _PlayerDetailCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  /** 分区标题。 */
  final String title;

  /** 分区主要内容。 */
  final Widget child;

  /** 标题右侧的可选操作。 */
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xff101a2c),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xff25334e)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xff929fba),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/** 文件信息中的单行键值。 */
class _PlayerDetailRow extends StatelessWidget {
  const _PlayerDetailRow({
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  /** 属性名称。 */
  final String label;

  /** 当前视频对应的属性值。 */
  final String value;

  /** 是否在本行下方显示分隔线。 */
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: Color(0xff202c43)))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: Color(0xff9aa7bd), fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xffd3d9e7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/** 当前视频标签胶囊。 */
class _PlayerDetailTagChip extends StatelessWidget {
  const _PlayerDetailTagChip({required this.label});

  /** 标签名称。 */
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xff272052),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xff4a3f87)),
      ),
      child: Text(label,
          style: const TextStyle(color: Color(0xffc9c1ff), fontSize: 11)),
    );
  }
}

/** 当前视频状态徽标。 */
class _PlayerDetailStatus extends StatelessWidget {
  const _PlayerDetailStatus({required this.label, this.warning = false});

  /** 状态文字。 */
  final String label;

  /** 是否使用警告配色。 */
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: warning ? const Color(0xff442229) : const Color(0xff25204f),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: warning ? const Color(0xffffb4b4) : const Color(0xffc9c1ff),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/** 队尾状态从旧底部信息卡迁入详情，避免静默丢失反馈。 */
class _PlayerQueueEndNotice extends StatelessWidget {
  const _PlayerQueueEndNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xff173328),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xff285d48)),
      ),
      child: const Text(
        '当前筛选队列已播放完毕',
        style: TextStyle(
          color: Color(0xffbbf7d0),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/** 把媒体时长格式化为详情面板的紧凑文本。 */
String _formatPanelDuration(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return value.inHours > 0
      ? '${value.inHours}:$minutes:$seconds'
      : '$minutes:$seconds';
}

/** 把文件字节数格式化为用户可读大小。 */
String _formatPanelBytes(int bytes) {
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
