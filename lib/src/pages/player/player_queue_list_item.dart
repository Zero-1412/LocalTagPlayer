import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/media_details.dart';
import '../../models/video_item.dart';
import '../../services/media/media_details_service.dart';
import '../../services/media/thumbnail_service.dart';
import '../../widgets/app_theme_tokens.dart';
import 'player_queue_metadata_widgets.dart';
import 'player_queue_list_item_actions.dart';
import 'player_queue_sidebar.dart';

// ignore_for_file: slash_for_doc_comments

class QueueListItem extends StatefulWidget {
  const QueueListItem({
    super.key,
    required this.item,
    required this.index,
    required this.playing,
    required this.selected,
    required this.thumbnailService,
    required this.detailsService,
    required this.onTap,
    required this.onDoubleTap,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  /**
   * 队列项对应的视频，不改变播放队列顺序。
   */
  final VideoItem item;

  /**
   * 当前项在筛选结果队列中的零基序号。
   */
  final int index;

  /**
   * 该项是否为播放器正在消费的视频。
   */
  final bool playing;

  /**
   * 该项是否为键盘或鼠标当前选中的队列项。
   */
  final bool selected;

  /**
   * 缩略图服务，仅用于队列项预览。
   */
  final ThumbnailService thumbnailService;

  /**
   * 媒体详情服务，仅用于显示编码和分辨率摘要。
   */
  final MediaDetailsService detailsService;

  /**
   * 单击队列项时只更新选中位置。
   */
  final VoidCallback onTap;

  /**
   * 双击队列项时切换实际播放位置。
   */
  final VoidCallback onDoubleTap;

  /** 左滑操作区中的收藏切换动作。 */
  final VoidCallback onToggleFavorite;

  /** 左滑操作区中的删除动作。 */
  final VoidCallback onDelete;

  @override
  State<QueueListItem> createState() => QueueListItemState();
}

class QueueListItemState extends State<QueueListItem>
    with SingleTickerProviderStateMixin {
  static const _actionRevealWidth = 106.0;
  late Future<File?> _thumbnailFuture;
  late Future<MediaDetails> _detailsFuture;
  late final AnimationController _actionController;
  var _hovered = false;

  @override
  void initState() {
    super.initState();
    _actionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _loadItemFutures();
  }

  @override
  void didUpdateWidget(covariant QueueListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.path != widget.item.path) {
      _actionController.value = 0;
      _loadItemFutures();
      return;
    }
    if (!oldWidget.playing && widget.playing) {
      // 条目成为当前播放项时必须清除之前保留的左滑进度；否则隐藏操作层会与播放徽标重叠。
      // 这里只复位视觉状态，用户随后仍可主动左滑当前项执行收藏或删除。
      _actionController.value = 0;
    }
  }

  @override
  void dispose() {
    _actionController.dispose();
    super.dispose();
  }

  /** 把水平拖动距离映射为稳定的 0..1 展开进度。 */
  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    _actionController.value =
        (_actionController.value - details.delta.dx / _actionRevealWidth)
            .clamp(0.0, 1.0);
  }

  /** 根据拖动速度和过半阈值平滑吸附到展开或折叠状态。 */
  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final shouldOpen = playerQueueActionShouldOpen(
      progress: _actionController.value,
      horizontalVelocity: velocity,
    );
    _settleActionPanel(shouldOpen);
  }

  /** 按剩余距离计算吸附时长；下一次拖动可直接改写 controller 进度。 */
  void _settleActionPanel(bool open) {
    final accessibility = AppAccessibilityScope.of(context);
    final target = open ? 1.0 : 0.0;
    final remaining = (target - _actionController.value).abs();
    if (accessibility.reduceMotion) {
      _actionController.value = target;
      return;
    }
    final milliseconds = (60 + 160 * remaining).round();
    _actionController.animateTo(
      target,
      duration: Duration(milliseconds: milliseconds),
      curve: AppMotion.standardCurve,
    );
  }

  /** 执行动作前先收回操作区，避免弹窗返回后队列项仍停在半展开状态。 */
  void _runAction(VoidCallback action) {
    _settleActionPanel(false);
    action();
  }

  void _loadItemFutures() {
    if (widget.item.isMissing) {
      // missing 条目不再派发文件 I/O，避免大队列对失效路径反复探测。
      _thumbnailFuture = Future<File?>.value(null);
      _detailsFuture = Future<MediaDetails>.value(const MediaDetails());
      return;
    }
    // 完整队列项只会在滚动负载允许时挂载，因此这里代表真实可视/近可视区域。
    // 缩略图复用共享缓存；缺失时进入播放期单并发优先队列，不唤醒后台补全。
    _thumbnailFuture = widget.thumbnailService.ensureThumbnailFor(widget.item);
    // 已持久化详情立即返回；未命中时把当前可视项提升到扫描后台任务之前。
    _detailsFuture =
        widget.detailsService.detailsFor(widget.item, priority: true);
  }

  @override
  Widget build(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    final emphasis = widget.playing
        ? 3
        : widget.selected
            ? 2
            : _hovered
                ? 1
                : 0;
    final infoColor = emphasis >= 2
        ? playerTextMuted
        : _hovered
            ? playerTextMuted
            : playerTextMuted.withValues(alpha: 0.72);
    final titleColor = widget.playing
        ? playerText
        : widget.selected
            ? playerText
            : _hovered
                ? playerText
                : playerText.withValues(alpha: 0.76);
    final backgroundColor = widget.playing
        ? appAccentViolet.withValues(alpha: 0.18)
        : widget.selected
            ? playerSurfaceRaised
            : _hovered
                ? playerSurfaceRaised.withValues(alpha: 0.82)
                : playerSurfaceAlt;
    final borderColor = widget.playing
        ? appAccentViolet
        : widget.selected
            ? playerTextMuted.withValues(alpha: 0.55)
            : _hovered
                ? playerTextMuted.withValues(alpha: 0.38)
                : playerBorder;
    final accentColor = widget.playing
        ? appAccentViolet
        : widget.selected
            ? playerText
            : _hovered
                ? playerTextMuted
                : playerTextMuted.withValues(alpha: 0.44);
    final showHoverAction = _hovered && !widget.playing;
    final stateBadgeLabel = widget.item.isMissing
        ? '缺失'
        : widget.playing
            ? '播放中'
            : widget.selected
                ? '已选中'
                : null;
    final stateBadgeIcon = widget.item.isMissing
        ? Icons.link_off_rounded
        : widget.playing
            ? Icons.play_arrow_rounded
            : widget.selected
                ? Icons.center_focus_strong_rounded
                : null;
    final stateBadgeColor = widget.item.isMissing
        ? playerDanger
        : widget.playing
            ? appAccentViolet
            : playerTextMuted;
    final shadow = widget.selected || _hovered
        ? const [
            BoxShadow(
              color: Color(0x2e000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ]
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) {
          setState(() => _hovered = false);
          _actionController.reverse();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: AnimatedBuilder(
            animation: _actionController,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: widget.onTap,
              onDoubleTap: widget.onDoubleTap,
              child: AnimatedContainer(
                key: ValueKey(
                  'player.queue.card.${widget.item.videoId}',
                ),
                duration: accessibility.fadeDuration(AppMotion.hover),
                curve: AppMotion.standardCurve,
                // 队列宽度有限，优先把横向空间留给标题与状态；垂直留白仍保证点击目标舒适。
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: borderColor),
                  boxShadow: shadow,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: accessibility.fadeDuration(AppMotion.hover),
                      width: 3,
                      height: 60,
                      decoration: BoxDecoration(
                        color: widget.playing || widget.selected || _hovered
                            ? accentColor
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.capsule),
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 104,
                      height: 60,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FutureBuilder<File?>(
                              future: _thumbnailFuture,
                              initialData:
                                  widget.thumbnailService.cachedThumbnailFor(
                                widget.item,
                              ),
                              builder: (context, snapshot) {
                                final file = snapshot.data;
                                // 缓存有效性由 ThumbnailService 负责，Widget 不再同步访问磁盘。
                                if (file != null) {
                                  return Image.file(
                                    file,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.low,
                                    cacheWidth: 160,
                                    gaplessPlayback: true,
                                  );
                                }
                                return const ColoredBox(
                                  color: playerSurfaceRaised,
                                  child: Center(
                                    child: Icon(Icons.movie_outlined,
                                        color: playerTextMuted, size: 22),
                                  ),
                                );
                              },
                            ),
                            AnimatedOpacity(
                              duration:
                                  accessibility.fadeDuration(AppMotion.hover),
                              opacity: showHoverAction ? 1 : 0,
                              child: const ColoredBox(
                                color: Color(0x66000000),
                                child: Center(
                                  child: Icon(Icons.play_arrow_rounded,
                                      color: Colors.white, size: 24),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: FutureBuilder<MediaDetails>(
                        future: _detailsFuture,
                        initialData:
                            widget.detailsService.cachedDetailsFor(widget.item),
                        builder: (context, snapshot) {
                          final details = snapshot.data;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    width: 24,
                                    child: Text(
                                      (widget.index + 1)
                                          .toString()
                                          .padLeft(2, '0'),
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      style: TextStyle(
                                        color: accentColor,
                                        fontSize: 12,
                                        fontWeight: emphasis >= 2
                                            ? FontWeight.w900
                                            : FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      widget.item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: titleColor,
                                        fontSize: 14,
                                        height: 1.15,
                                        fontWeight: emphasis >= 2
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Semantics(
                                    label:
                                        widget.item.isFavorite ? '已收藏' : '未收藏',
                                    child: SizedBox(
                                      width: 15,
                                      height: 15,
                                      child: widget.item.isFavorite
                                          ? Icon(
                                              Icons.favorite_rounded,
                                              key: ValueKey(
                                                'player.queue.'
                                                'favoriteIndicator.'
                                                '${widget.item.videoId}',
                                              ),
                                              size: 15,
                                              color: playerDanger,
                                            )
                                          : null,
                                    ),
                                  ),
                                  if (stateBadgeLabel != null &&
                                      stateBadgeIcon != null) ...[
                                    const SizedBox(width: 6),
                                    QueueStateBadge(
                                      label: stateBadgeLabel,
                                      icon: stateBadgeIcon,
                                      color: stateBadgeColor,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                queueListItemDetailsLine(widget.item, details),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: infoColor,
                                    fontSize: 11,
                                    height: 1.1),
                              ),
                              AnimatedOpacity(
                                duration:
                                    accessibility.fadeDuration(AppMotion.hover),
                                opacity: showHoverAction ? 1 : 0,
                                child: const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Text(
                                    '单击选中 · 双击播放',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: playerTextMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            builder: (context, front) {
              final revealProgress = _actionController.value;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (revealProgress > 0.001)
                    // 完全收起时卸载隐藏操作层，避免真实窗口的像素舍入让图标从卡片右缘泄出。
                    QueueListItemActionBackground(
                      item: widget.item,
                      width: _actionRevealWidth,
                      onToggleFavorite: () =>
                          _runAction(widget.onToggleFavorite),
                      onDelete: () => _runAction(widget.onDelete),
                    ),
                  Transform.translate(
                    offset: Offset(
                      -_actionRevealWidth * revealProgress,
                      0,
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (_) => widget.onTap(),
                      onHorizontalDragUpdate: _handleHorizontalDragUpdate,
                      onHorizontalDragEnd: _handleHorizontalDragEnd,
                      onHorizontalDragCancel: () => _settleActionPanel(false),
                      child: front,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
