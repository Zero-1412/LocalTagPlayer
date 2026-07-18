import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 交互表面可选择的材质；默认实色，透明只用于小范围浮层。 */
enum AppSurfaceMaterial {
  solid,
  translucent,
}

/**
 * 统一 press、hover、focus 与键盘激活反馈的轻量交互表面。
 *
 * 组件保留 [InkWell] 的鼠标、键盘、焦点和语义链路。reduced motion 下
 * 不执行缩放位移，高对比度下透明材质自动回退为实色并强化描边。
 */
class AppInteractionSurface extends StatefulWidget {
  const AppInteractionSurface({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.padding = const EdgeInsets.all(AppSpacing.sm),
    this.borderRadius = AppRadius.control,
    this.backgroundColor,
    this.material = AppSurfaceMaterial.solid,
    this.autofocus = false,
  });

  /** 表面承载的内容。 */
  final Widget child;

  /** 点击或键盘激活回调；为 null 时表面自动进入禁用状态。 */
  final VoidCallback? onTap;

  /** 提供给辅助技术的动作名称。 */
  final String? semanticLabel;

  /** 内容与可点击边界之间的间距。 */
  final EdgeInsetsGeometry padding;

  /** 表面、墨水反馈和焦点轮廓共享的圆角。 */
  final double borderRadius;

  /** 可覆盖当前主题 surface 的显式背景色。 */
  final Color? backgroundColor;

  /** 小范围浮层可显式请求透明材质，结构表面应保留默认实色。 */
  final AppSurfaceMaterial material;

  /** 是否在首次显示时请求键盘焦点。 */
  final bool autofocus;

  @override
  State<AppInteractionSurface> createState() => _AppInteractionSurfaceState();
}

/** 管理仅属于视觉反馈的瞬时状态，不保存任何业务状态。 */
class _AppInteractionSurfaceState extends State<AppInteractionSurface> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  /** 根据当前交互状态生成克制且可逆的表面颜色。 */
  Color _surfaceColor(
    BuildContext context,
    AppAccessibilityData accessibility,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final solid = widget.backgroundColor ?? scheme.surface;
    final base = widget.material == AppSurfaceMaterial.translucent &&
            !accessibility.highContrast
        ? solid.withValues(alpha: AppMaterialOpacity.floating)
        : solid;
    if (_pressed) {
      return Color.alphaBlend(scheme.primary.withValues(alpha: 0.13), base);
    }
    if (_focused) {
      return Color.alphaBlend(scheme.primary.withValues(alpha: 0.10), base);
    }
    if (_hovered) {
      return Color.alphaBlend(scheme.primary.withValues(alpha: 0.07), base);
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onTap != null;
    final radius = BorderRadius.circular(widget.borderRadius);
    final outline = accessibility.highContrast
        ? scheme.primary
        : _focused
            ? scheme.primary.withValues(alpha: 0.76)
            : scheme.outlineVariant;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: AnimatedScale(
        scale: enabled && _pressed && !accessibility.reduceMotion ? 0.985 : 1,
        duration: accessibility.motionDuration(AppMotion.press),
        curve: AppMotion.standardCurve,
        child: AnimatedContainer(
          duration: accessibility.fadeDuration(AppMotion.hover),
          curve: AppMotion.standardCurve,
          decoration: BoxDecoration(
            color: _surfaceColor(context, accessibility),
            borderRadius: radius,
            border: Border.all(
              color: outline,
              width: accessibility.highContrast || _focused ? 1.5 : 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              autofocus: widget.autofocus,
              canRequestFocus: enabled,
              borderRadius: radius,
              onTap: widget.onTap,
              onHover: (value) {
                if (_hovered != value) {
                  setState(() => _hovered = value);
                }
              },
              onFocusChange: (value) {
                if (_focused != value) {
                  setState(() => _focused = value);
                }
              },
              onHighlightChanged: (value) {
                if (_pressed != value) {
                  setState(() => _pressed = value);
                }
              },
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              child: Padding(
                padding: widget.padding,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
