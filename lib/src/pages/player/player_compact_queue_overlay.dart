import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 中窄窗口的右侧队列覆盖层。
 *
 * 组件只负责遮罩、右侧定位和关闭入口；filtered queue、选择与播放命令仍由播放器
 * 页面持有。关闭按钮放在侧栏左侧遮罩区，避免改变统一列表/详情头部的几何。
 */
class PlayerCompactQueueOverlay extends StatelessWidget {
  const PlayerCompactQueueOverlay({
    super.key,
    required this.sidebar,
    required this.sidebarWidth,
    required this.onDismiss,
  });

  /** 页面按当前 filtered queue 构建的统一侧栏。 */
  final Widget sidebar;

  /** 由当前窗口宽度计算出的侧栏固定宽度。 */
  final double sidebarWidth;

  /** 点击遮罩或显式关闭按钮时隐藏覆盖层。 */
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('player.compactQueue.dismiss'),
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.34),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: RepaintBoundary(child: sidebar),
        ),
        Positioned(
          top: AppSpacing.xs,
          right: sidebarWidth + AppSpacing.xs,
          child: Tooltip(
            message: '关闭播放队列',
            child: IconButton(
              key: const ValueKey('player.compactQueue.close'),
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 20),
              color: playerText,
              style: IconButton.styleFrom(
                backgroundColor: playerSurface.withValues(alpha: 0.96),
                side: const BorderSide(color: playerBorder),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
