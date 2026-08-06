import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models/video_item.dart';
import '../../widgets/app_theme_tokens.dart';
import 'player_queue_sidebar.dart';

// ignore_for_file: slash_for_doc_comments

/** 为队列可视区域维护“滚动中/已停稳”状态，确保程序化定位后恢复完整卡片。 */
class QueueListViewport extends StatefulWidget {
  const QueueListViewport({
    super.key,
    required this.controller,
    required this.playlist,
    required this.itemBuilder,
  });

  /** 当前布局实例独占的滚动控制器。 */
  final ScrollController controller;

  /** 当前播放器实际消费的 filtered queue。 */
  final List<VideoItem> playlist;

  /** 滚动负载允许时构建完整队列项的回调。 */
  final Widget Function(BuildContext context, int index, VideoItem item)
      itemBuilder;

  @override
  State<QueueListViewport> createState() => QueueListViewportState();
}

/** 只协调占位生命周期，不持有或修改队列、选择和播放状态。 */
class QueueListViewportState extends State<QueueListViewport> {
  var _scrollSettled = true;

  /** 某些 Windows 滚轮/程序化跳转不会稳定发送结束通知，使用短防抖兜底。 */
  Timer? _settleFallbackTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerScroll);
  }

  @override
  void didUpdateWidget(covariant QueueListViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_handleControllerScroll);
    widget.controller.addListener(_handleControllerScroll);
  }

  /**
   * 用控制器变化补齐 Windows 滚轮和程序化定位缺少 ScrollEndNotification 的情况。
   * 只在第一次进入滚动态时重建，避免高频滚轮事件把整个可视队列反复 rebuild。
   */
  void _handleControllerScroll() {
    if (!mounted) {
      return;
    }
    if (_scrollSettled) {
      setState(() => _scrollSettled = false);
    }
    _scheduleSettledFallback();
  }

  /**
   * 记录滚动生命周期；结束通知必须触发重建，修复 `jumpTo` 后占位残留。
   */
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    final settled = notification is ScrollEndNotification ||
        notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle;
    final active = notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification ||
        notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle;
    if (settled) {
      _settleFallbackTimer?.cancel();
      if (!_scrollSettled) {
        setState(() => _scrollSettled = true);
      }
    } else if (active) {
      if (_scrollSettled) {
        setState(() => _scrollSettled = false);
      }
      _scheduleSettledFallback();
    }
    // 通知继续冒泡，保留外层滚动监听和桌面滚轮行为。
    return false;
  }

  /**
   * 最后一个滚动事件后恢复完整卡片，兼容只发送更新通知的 Windows 滚轮链路。
   */
  void _scheduleSettledFallback() {
    _settleFallbackTimer?.cancel();
    _settleFallbackTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _scrollSettled) {
        return;
      }
      setState(() => _scrollSettled = true);
    });
  }

  @override
  void dispose() {
    _settleFallbackTimer?.cancel();
    widget.controller.removeListener(_handleControllerScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: ListView.builder(
        controller: widget.controller,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        itemExtent: playerQueueItemExtent,
        // 只预建邻近两项，避免大队列滚动时提前触发大量文件校验与 FFprobe。
        scrollCacheExtent: const ScrollCacheExtent.pixels(208),
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemCount: widget.playlist.length,
        itemBuilder: (context, index) {
          final item = widget.playlist[index];
          return DeferredQueueListItem(
            item: item,
            scrollSettled: _scrollSettled,
            // 占位期间不创建完整卡片，避免缩略图/媒体详情 Future 在快速滚动时提前启动。
            childBuilder: () => widget.itemBuilder(context, index, item),
          );
        },
      ),
    );
  }
}

/**
 * 快速滚动期间用轻量占位保护视频解码线程，滚动减速后再创建会访问磁盘的队列项。
 */
class DeferredQueueListItem extends StatelessWidget {
  const DeferredQueueListItem({
    super.key,
    required this.item,
    required this.scrollSettled,
    required this.childBuilder,
  });

  /** 当前队列项，仅用于在占位状态展示稳定标题。 */
  final VideoItem item;

  /** 当前滚动是否已经结束；停稳后必须恢复完整队列项。 */
  final bool scrollSettled;

  /** 滚动负载允许时才创建的完整队列项。 */
  final Widget Function() childBuilder;

  @override
  Widget build(BuildContext context) {
    final shouldDefer = playerQueueShouldDeferItem(
      scrollSettled: scrollSettled,
      recommendsDeferredLoading:
          Scrollable.recommendDeferredLoadingForContext(context),
    );
    if (!shouldDefer) {
      return childBuilder();
    }
    // 快速滚动期间不启动缩略图校验或媒体详情读取，只保留可辨认的标题反馈。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: playerSurfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: playerBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: playerTextMuted, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

/**
 * 按桌面窗口宽度计算播放队列栏宽度。
 *
 * 队列栏在宽屏下保持接近蓝图的三成占比，同时通过上下限避免窄窗挤压
 * 播放画面，或在超宽屏上让单行队列信息变得过度松散。
 */
double playerQueueSidebarWidthForWindow(double windowWidth) {
  return (windowWidth * 0.28).clamp(360.0, 460.0).toDouble();
}
