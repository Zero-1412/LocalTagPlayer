import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';
import '../design_system/app_interaction_surface.dart';
import 'library_smoke_keys.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 不遮挡结果滚动条的右下角回到顶部入口。
 *
 * 可见性与滚动命令均由网格 State owner 提供；组件只负责无障碍显隐和短动画。
 */
class LibraryVideoGridReturnToTop extends StatelessWidget {
  const LibraryVideoGridReturnToTop({
    super.key,
    required this.visible,
    required this.onTap,
  });

  /** 是否已经越过首个结果视口。 */
  final bool visible;

  /** 请求网格使用既有滚动控制器返回绝对顶部。 */
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    final motionDuration =
        accessibility.motionDuration(const Duration(milliseconds: 180));
    final fadeDuration =
        accessibility.fadeDuration(const Duration(milliseconds: 160));
    return Positioned(
      right: 20,
      bottom: 20,
      child: ExcludeFocus(
        excluding: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 0.28),
              duration: motionDuration,
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: fadeDuration,
                curve: Curves.easeOutCubic,
                child: Tooltip(
                  message: '回到顶部',
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: librarySoftShadow,
                    ),
                    child: AppInteractionSurface(
                      key: LibrarySmokeKeys.returnToTopButton,
                      onTap: onTap,
                      semanticLabel: '回到媒体库顶部',
                      padding: EdgeInsets.zero,
                      borderRadius: 22,
                      backgroundColor: librarySurface,
                      showBorder: false,
                      child: const SizedBox.square(
                        dimension: 44,
                        child: Icon(
                          Icons.keyboard_arrow_up_rounded,
                          size: 28,
                          color: libraryAccent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
