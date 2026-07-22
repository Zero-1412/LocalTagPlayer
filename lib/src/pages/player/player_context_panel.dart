import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../models/video_item.dart';
import '../../widgets/app_theme_tokens.dart';
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
 * queue 或视频画面。详情视图只保留媒体信息和就近标签维护入口，避免重复堆叠底部操作。
 */
class PlayerSidePanel extends StatefulWidget {
  const PlayerSidePanel({
    super.key,
    required this.queuePanel,
    required this.item,
    required this.queueEndReached,
    required this.onRenameFile,
    required this.onEditManualTags,
    this.edgeToEdge = false,
    this.width,
  });

  /** 原有 filtered queue 内容；隐藏详情时才挂载，避免离屏列表继续构建。 */
  final Widget queuePanel;

  /** 当前实际正在播放的视频，而不是队列中仅被单击选中的视频。 */
  final VideoItem item;

  /** 当前筛选队列是否已经顺序播放到末尾。 */
  final bool queueEndReached;

  /** 打开当前视频的文件重命名流程。 */
  final VoidCallback onRenameFile;

  /** 打开当前视频的手动标签编辑器。 */
  final VoidCallback onEditManualTags;

  /** 全屏覆盖侧栏是否铺满可用高度并取消外围留白。 */
  final bool edgeToEdge;

  /** 可选固定宽度；全屏覆盖层用于保持动画边界与阅读密度稳定。 */
  final double? width;

  @override
  State<PlayerSidePanel> createState() => _PlayerSidePanelState();
}

/** 只维护侧栏视图选择；播放、队列和标签状态继续由 PlayerPage 持有。 */
class _PlayerSidePanelState extends State<PlayerSidePanel> {
  PlayerSidePanelView _view = PlayerSidePanelView.queue;

  /** 最近一次切换方向；正值向详情推进，负值返回队列。 */
  var _transitionDirection = 1;

  /** 切换一级侧栏视图，不触发媒体读取或队列重算。 */
  void _selectView(PlayerSidePanelView view) {
    if (_view == view) {
      return;
    }
    setState(() {
      _transitionDirection = view == PlayerSidePanelView.details ? 1 : -1;
      _view = view;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    final sidebarWidth = widget.width ??
        playerQueueSidebarWidthForWindow(MediaQuery.sizeOf(context).width);
    return Container(
      width: sidebarWidth,
      margin: widget.edgeToEdge
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(0, 12, 16, 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: playerSurface,
        borderRadius: widget.edgeToEdge
            ? BorderRadius.zero
            : BorderRadius.circular(AppRadius.panel),
        border: widget.edgeToEdge
            ? const Border(left: BorderSide(color: playerBorder))
            : Border.all(color: playerBorder),
        boxShadow: widget.edgeToEdge ? null : playerSoftShadow,
      ),
      child: Column(
        children: [
          _PlayerSidePanelTabs(
            selected: _view,
            onSelected: _selectView,
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: accessibility.fadeDuration(AppMotion.hover),
              switchInCurve: AppMotion.standardCurve,
              switchOutCurve: AppMotion.standardCurve,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                fit: StackFit.expand,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              transitionBuilder: (child, animation) {
                final begin = accessibility.reduceMotion
                    ? Offset.zero
                    : Offset(0.025 * _transitionDirection, 0);
                return AppSequentialTransition(
                  animation: animation,
                  beginOffset: begin,
                  reduceMotion: accessibility.reduceMotion,
                  child: child,
                );
              },
              child: _view == PlayerSidePanelView.queue
                  ? KeyedSubtree(
                      key: const ValueKey('player.sidebar.queue'),
                      child: widget.queuePanel,
                    )
                  : PlayerVideoDetailsPanel(
                      key: const ValueKey('player.sidebar.details'),
                      item: widget.item,
                      queueEndReached: widget.queueEndReached,
                      onRenameFile: widget.onRenameFile,
                      onEditManualTags: widget.onEditManualTags,
                    ),
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
      // 侧栏顶部只承担视图切换，压缩高度让队列内容与播放器主体保持同一视觉密度。
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: const BoxDecoration(
        color: playerSurface,
        border: Border(bottom: BorderSide(color: playerBorder)),
      ),
      child: SizedBox(
        key: const ValueKey('player.sidebar.tabs.segment'),
        height: 36,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: playerSurfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: playerBorder),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.control - 1),
            child: Row(
              // 两个分段必须填满外框高度，避免选中渐变只包住图标和文字。
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
        ? const BorderRadius.horizontal(
            left: Radius.circular(AppRadius.control - 1),
          )
        : const BorderRadius.horizontal(
            right: Radius.circular(AppRadius.control - 1),
          );
    final accessibility = AppAccessibilityScope.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        key: surfaceKey,
        duration: accessibility.fadeDuration(AppMotion.hover),
        curve: AppMotion.standardCurve,
        decoration: BoxDecoration(
          color: selected
              ? appAccentViolet.withValues(alpha: 0.24)
              : Colors.transparent,
          borderRadius: outerRadius,
          border:
              selected ? Border.all(color: appAccentViolet, width: 1.2) : null,
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
                  size: 18,
                  color: selected ? playerText : playerTextMuted,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? playerText : playerTextMuted,
                    fontSize: 14,
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
    required this.onRenameFile,
    required this.onEditManualTags,
  });

  /** 当前实际正在播放的视频。 */
  final VideoItem item;

  /** 当前 filtered queue 是否已经播放到末尾。 */
  final bool queueEndReached;

  /** 修改当前本地文件的 basename，不承担标签维护。 */
  final VoidCallback onRenameFile;

  /** 编辑当前视频手动标签。 */
  final VoidCallback onEditManualTags;

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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '当前视频详情',
                style: TextStyle(
                  color: playerText,
                  fontSize: 16,
                  fontWeight: AppTypography.strong,
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
            key: const ValueKey('player.details.renameFile'),
            tooltip: '重命名文件',
            onPressed: onRenameFile,
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: appAccentViolet,
            visualDensity: VisualDensity.compact,
          ),
          child: SelectableText(
            displayTitle,
            style: const TextStyle(
              color: playerText,
              fontSize: 14,
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
                key: const ValueKey('player.details.editTags'),
                onPressed: onEditManualTags,
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: Text(visibleTags.isEmpty ? '添加标签' : '继续添加'),
                side: const BorderSide(color: playerBorder),
                backgroundColor: playerSurfaceRaised,
                labelStyle: const TextStyle(
                  color: playerTextMuted,
                  fontSize: 12,
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
              color: playerTextSecondary,
              fontSize: 13,
              height: 1.45,
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
        color: playerSurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: playerBorder),
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
                    color: playerTextMuted,
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
            ? const Border(bottom: BorderSide(color: playerBorder))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: playerTextMuted, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: playerText,
                fontSize: 13,
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
        color: appAccentViolet.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.capsule),
        border: Border.all(color: appAccentViolet.withValues(alpha: 0.48)),
      ),
      child:
          Text(label, style: const TextStyle(color: playerText, fontSize: 12)),
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
        color: warning
            ? playerDanger.withValues(alpha: 0.16)
            : appAccentViolet.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.capsule),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: warning ? playerDanger : playerText,
          fontSize: 11,
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
        color: playerPositive.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: playerPositive.withValues(alpha: 0.45)),
      ),
      child: const Text(
        '当前筛选队列已播放完毕',
        style: TextStyle(
          color: playerPositive,
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
