import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';
import '../design_system/app_interaction_surface.dart';
import 'library_smoke_keys.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

class LibrarySidebarBrand extends StatelessWidget {
  const LibrarySidebarBrand({this.onToggleCollapsed});

  /** 通过品牌图标收起主功能栏；为 null 时保持只读品牌头。 */
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        LibrarySidebarBrandToggle(
          collapsed: false,
          dimension: 36,
          onToggleCollapsed: onToggleCollapsed,
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '\u672c\u5730\u6807\u7b7e\u64ad\u653e\u5668',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'LOCAL LIBRARY',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xff95a3b8),
                  fontSize: 9,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/**
 * 品牌区与主功能栏折叠状态共用的唯一切换入口。
 *
 * 展开态三角向右，折叠态三角向下；按钮使用克制的紫色品牌底，
 * 不依赖发光阴影表达可点击性，也不额外占用侧栏横向空间。
 */
class LibrarySidebarBrandToggle extends StatelessWidget {
  const LibrarySidebarBrandToggle({
    required this.collapsed,
    required this.dimension,
    required this.onToggleCollapsed,
  });

  /** true 表示当前仅显示图标轨道。 */
  final bool collapsed;

  /** 展开和折叠布局各自使用的品牌方块尺寸。 */
  final double dimension;

  /** 切换主功能栏状态；为空时品牌图标保持只读。 */
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final tooltip = collapsed ? '展开功能栏' : '折叠功能栏';
    final accessibility = AppAccessibilityScope.of(context);
    return Tooltip(
      message: tooltip,
      child: AppInteractionSurface(
        key: LibrarySmokeKeys.sidebarCollapseToggle,
        onTap: onToggleCollapsed,
        semanticLabel: tooltip,
        padding: EdgeInsets.zero,
        borderRadius: AppRadius.control,
        backgroundColor: appAccentViolet,
        showBorder: false,
        child: SizedBox(
          width: dimension,
          height: dimension,
          child: AnimatedRotation(
            turns: collapsed ? 0.25 : 0,
            duration: accessibility.motionDuration(appMotionDuration),
            curve: appMotionCurve,
            child: Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: collapsed ? 28 : 29,
            ),
          ),
        ),
      ),
    );
  }
}
