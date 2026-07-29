import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 根据结果区是否处于绝对顶部收起或恢复媒体库顶部信息区。
 *
 * 动画只包裹顶部 chrome，不读取筛选结果，也不驱动视频逐项动画；[visibleListenable]
 * 由结果滚动组件仅在跨越顶部边界时更新，避免逐像素重建页面。
 */
class LibraryScrollResponsiveHeader extends StatefulWidget {
  const LibraryScrollResponsiveHeader({
    super.key,
    required this.visibleListenable,
    required this.child,
  });

  /** 顶部信息区的目标可见状态。 */
  final ValueListenable<bool> visibleListenable;

  /** 保留原有搜索、筛选、排序和动作语义的顶部内容。 */
  final Widget child;

  @override
  State<LibraryScrollResponsiveHeader> createState() =>
      _LibraryScrollResponsiveHeaderState();
}

/** 管理可打断的顶部尺寸、透明度和短距离位移动画。 */
class _LibraryScrollResponsiveHeaderState
    extends State<LibraryScrollResponsiveHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _visibilityAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
      value: widget.visibleListenable.value ? 1 : 0,
    );
    _visibilityAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.045),
      end: Offset.zero,
    ).animate(_visibilityAnimation);
    widget.visibleListenable.addListener(_handleVisibilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animateToTarget();
  }

  @override
  void didUpdateWidget(covariant LibraryScrollResponsiveHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibleListenable != widget.visibleListenable) {
      oldWidget.visibleListenable.removeListener(_handleVisibilityChanged);
      widget.visibleListenable.addListener(_handleVisibilityChanged);
    }
    _animateToTarget();
  }

  /** 响应轻量可见性通知，并从当前动画进度直接反向。 */
  void _handleVisibilityChanged() {
    if (mounted) {
      _animateToTarget();
    }
  }

  /** 根据无障碍策略平滑抵达目标；reduced motion 下立即完成结构变化。 */
  void _animateToTarget() {
    final visible = widget.visibleListenable.value;
    final accessibility = AppAccessibilityScope.of(context);
    if (accessibility.reduceMotion) {
      _controller.value = visible ? 1 : 0;
      return;
    }
    if (visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    widget.visibleListenable.removeListener(_handleVisibilityChanged);
    _visibilityAnimation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final targetVisible = widget.visibleListenable.value;
        return ExcludeFocus(
          excluding: !targetVisible,
          child: ExcludeSemantics(
            excluding: !targetVisible,
            child: IgnorePointer(
              ignoring: !targetVisible,
              child: SizeTransition(
                sizeFactor: _visibilityAnimation,
                alignment: Alignment.topCenter,
                child: FadeTransition(
                  opacity: _visibilityAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
