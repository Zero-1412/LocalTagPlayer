import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/app_theme_tokens.dart';
import 'player_queue_sidebar.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放器队列头部，在紧凑操作区内按需展开搜索输入。
 *
 * 搜索默认收起，避免持续占用列表高度；播放序号后的操作按钮使用固定尺寸和
 * 明确间距，保证搜索和删除入口在不同队列数量下仍保持稳定布局；离屏定位只在列表底部
 * 按需出现，避免与标题栏形成重复入口。
 */
class PlayerQueueHeader extends StatefulWidget {
  const PlayerQueueHeader({
    super.key,
    required this.playlistLength,
    required this.playingIndex,
    required this.onDeleteSelected,
    required this.onSearch,
    this.onSearchVisibilityChanged,
  });

  /** 当前播放器实际消费的队列数量。 */
  final int playlistLength;

  /** 正在播放的视频在当前队列中的零基序号。 */
  final int playingIndex;

  /** 删除当前视频的入口；为 null 时禁用按钮。 */
  final VoidCallback? onDeleteSelected;

  /** 在当前队列内查找并播放下一条匹配视频，不重新查询媒体库。 */
  final PlayerQueueSearchCallback onSearch;

  /** 搜索输入展开/收起通知，供播放器恢复快捷键焦点。 */
  final ValueChanged<bool>? onSearchVisibilityChanged;

  @override
  State<PlayerQueueHeader> createState() => _PlayerQueueHeaderState();
}

/** 维护队列搜索框的临时展开状态，不污染播放器会话状态。 */
class _PlayerQueueHeaderState extends State<PlayerQueueHeader> {
  bool _searchVisible = false;

  /** 切换搜索框；重新展开时由输入框自动获得焦点。 */
  void _toggleSearch() {
    final visible = !_searchVisible;
    setState(() => _searchVisible = visible);
    widget.onSearchVisibilityChanged?.call(visible);
  }

  @override
  void dispose() {
    if (_searchVisible) {
      // 全屏队列自动隐藏会直接卸载头部；仍需通知播放器恢复稳定焦点。
      widget.onSearchVisibilityChanged?.call(false);
    }
    super.dispose();
  }

  /** 构建统一尺寸的紧凑操作按钮，避免图标随默认约束产生不规则间距。 */
  Widget _actionButton({
    required Key key,
    required String tooltip,
    required VoidCallback? onPressed,
    required IconData icon,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        child: IconButton(
          key: key,
          onPressed: onPressed,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
          icon: Icon(icon, size: 18),
          color: playerTextMuted,
          disabledColor: playerTextMuted.withValues(alpha: 0.32),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: const BoxDecoration(
        color: playerSurface,
        border: Border(
          bottom: BorderSide(color: playerBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.filter_alt_outlined,
                color: appAccentViolet,
                size: 21,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '筛选结果队列',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: playerText,
                    fontSize: 14,
                    fontWeight: AppTypography.strong,
                  ),
                ),
              ),
              Text(
                '${widget.playingIndex + 1} / ${widget.playlistLength}',
                key: const ValueKey('player.queue.position'),
                style: const TextStyle(
                  color: playerTextMuted,
                  fontSize: 12,
                  fontWeight: AppTypography.strong,
                ),
              ),
              const SizedBox(width: 8),
              _actionButton(
                key: const ValueKey('player.queue.search.toggle'),
                tooltip: _searchVisible ? '收起搜索' : '搜索队列',
                onPressed: _toggleSearch,
                icon:
                    _searchVisible ? Icons.close_rounded : Icons.search_rounded,
              ),
              const SizedBox(width: 4),
              _actionButton(
                key: const ValueKey('player.queue.delete.selected'),
                tooltip: '删除当前视频',
                onPressed: widget.onDeleteSelected,
                icon: Icons.delete_outline,
              ),
            ],
          ),
          if (_searchVisible) ...[
            const SizedBox(height: 8),
            QueueSearchField(
              autofocus: true,
              onSearch: widget.onSearch,
              onClose: _toggleSearch,
            ),
          ],
        ],
      ),
    );
  }
}

/**
 * 当前播放队列的轻量搜索框，同时支持键盘提交和可见按钮提交。
 */
class QueueSearchField extends StatefulWidget {
  const QueueSearchField({
    super.key,
    this.autofocus = false,
    required this.onSearch,
    required this.onClose,
  });

  /** 展开后是否立即接管键盘输入焦点。 */
  final bool autofocus;

  /** 仅在播放器已持有的队列中查找并播放，不访问媒体库或触发重新扫描。 */
  final PlayerQueueSearchCallback onSearch;

  /** Escape 或关闭动作只收起搜索，不让同一按键继续冒泡成播放器退出。 */
  final VoidCallback onClose;

  @override
  State<QueueSearchField> createState() => QueueSearchFieldState();
}

/** 维护搜索输入，避免把临时查询状态提升到播放器或媒体库控制器。 */
class QueueSearchFieldState extends State<QueueSearchField> {
  final TextEditingController _controller = TextEditingController();
  String _status = 'Enter 查找并播放下一条匹配视频';

  /** 提交当前查询，并把实际播放结果反馈在输入框下方的固定状态区。 */
  void _submit() {
    final outcome = widget.onSearch(_controller.text);
    setState(() {
      _status = switch (outcome) {
        PlayerQueueSearchOutcome.played => '已切换到下一条匹配视频',
        PlayerQueueSearchOutcome.noMatch => '当前筛选队列没有匹配项',
        PlayerQueueSearchOutcome.emptyQuery => '请先输入关键词',
      };
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('player.queueSearch'),
            controller: _controller,
            autofocus: widget.autofocus,
            style: const TextStyle(color: playerText, fontSize: 12),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: '查找并播放下一条',
              hintStyle: const TextStyle(color: playerTextMuted),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 18,
                color: playerTextMuted,
              ),
              filled: true,
              fillColor: playerSurfaceAlt,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide: const BorderSide(color: playerBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide:
                    const BorderSide(color: appAccentViolet, width: 1.5),
              ),
              suffixIcon: IconButton(
                key: const ValueKey('player.queueSearchSubmit'),
                tooltip: '播放下一条匹配视频',
                onPressed: _submit,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
              ),
            ),
            onChanged: (_) {
              if (_status != 'Enter 查找并播放下一条匹配视频') {
                setState(() => _status = 'Enter 查找并播放下一条匹配视频');
              }
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 5),
          Semantics(
            liveRegion: true,
            child: Text(
              _status,
              key: const ValueKey('player.queueSearch.status'),
              style: const TextStyle(
                color: playerTextSecondary,
                fontSize: 11,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/** 判断目标队列项是否仍位于当前视口，供离屏定位入口和 focused tests 共用。 */
bool playerQueueIndexIsVisible({
  required int index,
  required double scrollOffset,
  required double viewportExtent,
  required double itemExtent,
  double tolerance = 12,
}) {
  if (index < 0 || viewportExtent <= 0 || itemExtent <= 0) {
    return true;
  }
  final top = scrollOffset;
  final bottom = top + viewportExtent;
  final itemTop = index * itemExtent;
  final itemBottom = itemTop + itemExtent;
  return itemBottom > top + tolerance && itemTop < bottom - tolerance;
}

/**
 * 计算队列索引的稳定滚动位置。
 *
 * [topPadding] 必须与 ListView 顶部 padding 一致；集中计算可避免大队列定位因忽略
 * padding 或视口居中偏移而落到相邻视频。
 */
double playerQueueScrollOffsetForIndex({
  required int index,
  required double viewportExtent,
  required double itemExtent,
  required double minScrollExtent,
  required double maxScrollExtent,
  required bool center,
  double topPadding = 6,
}) {
  final itemTop = topPadding + index * itemExtent;
  final target = center
      ? itemTop - (viewportExtent - itemExtent) / 2
      : itemTop - itemExtent;
  return target.clamp(minScrollExtent, maxScrollExtent).toDouble();
}
