import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';
import 'app_interaction_surface.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 统一侧栏、工具栏和紧凑导航中的单个入口。
 *
 * 展开与折叠只改变内容密度，不改变点击、选中、焦点、禁用和辅助技术语义，
 * 让调用方只负责传递导航意图，避免为每种布局重复创建 Material/InkWell。
 */
class AppNavigationItem extends StatelessWidget {
  const AppNavigationItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.collapsed = false,
    this.tooltip,
  });

  /** 导航入口图标。 */
  final IconData icon;

  /** 展开态文字，同时作为辅助技术标签。 */
  final String label;

  /** 当前入口是否代表正在展示的来源。 */
  final bool selected;

  /** 点击或键盘激活意图；为空时保持禁用状态。 */
  final VoidCallback? onTap;

  /** 展开态右侧的数量或简短状态。 */
  final String? trailing;

  /** 是否只展示图标。 */
  final bool collapsed;

  /** 折叠态的悬浮提示；为空时沿用无提示的紧凑入口。 */
  final String? tooltip;

  Color get _iconColor {
    if (selected) {
      return appAccentViolet;
    }
    if (onTap == null) {
      return const Color(0xff526077);
    }
    return collapsed ? const Color(0xffa7b4c6) : libraryTextMuted;
  }

  Color get _labelColor => selected ? libraryText : const Color(0xffb8c3d3);

  @override
  Widget build(BuildContext context) {
    final expandedContent = SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _labelColor,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: const TextStyle(
                  color: Color(0xff94a3b8),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    );
    final content = collapsed
        ? SizedBox.square(
            dimension: 46,
            child: Icon(icon, size: 21, color: _iconColor),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? appAccentViolet : Colors.transparent,
                  width: 2,
                ),
              ),
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: expandedContent,
          );

    final surface = AppInteractionSurface(
      onTap: onTap,
      semanticLabel: label,
      selected: selected,
      padding: EdgeInsets.zero,
      borderRadius: AppRadius.control,
      backgroundColor: selected
          ? (collapsed
              ? const Color(0xff2b3650)
              : appAccentViolet.withValues(alpha: 0.10))
          : Colors.transparent,
      showBorder: false,
      child: content,
    );

    final withTooltip = collapsed && tooltip != null
        ? Tooltip(message: tooltip!, child: surface)
        : surface;
    return Padding(
      padding: EdgeInsets.only(bottom: collapsed ? 6 : 4),
      child: withTooltip,
    );
  }
}
