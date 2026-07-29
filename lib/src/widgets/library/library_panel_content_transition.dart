import 'package:flutter/material.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

/**
 * 左右侧栏共用的内容进入与离开动画。
 *
 * 宽度变化由外层布局负责；这里只组合淡入、横向位移和轻微缩放，让面板状态切换
 * 更容易被感知，同时保持子树身份和业务状态不变。
 */
class LibraryPanelContentTransition extends StatelessWidget {
  const LibraryPanelContentTransition({
    super.key,
    required this.animation,
    required this.horizontalOffset,
    required this.alignment,
    required this.child,
  });

  /** AnimatedSwitcher 提供的进入或离开进度。 */
  final Animation<double> animation;

  /** 内容起始位置相对自身宽度的横向偏移。 */
  final double horizontalOffset;

  /** 缩放锚点；左栏固定左侧，右栏固定右侧。 */
  final Alignment alignment;

  /** 不参与额外重建的侧栏内容。 */
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = animation.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: motion,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(horizontalOffset, 0),
          end: Offset.zero,
        ).animate(motion),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.965, end: 1).animate(motion),
          alignment: alignment,
          child: child,
        ),
      ),
    );
  }
}
