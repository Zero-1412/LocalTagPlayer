import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';
import '../design_system/app_interaction_surface.dart';
import 'library_reference_icon_button.dart';
import 'library_smoke_keys.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

/**
 * 顶栏左侧独立搜索表面。
 *
 * 搜索区域只表达“输入查询”的意图，不再混入已生效标签或结果数量；
 * 真实 [TextField] / controller 输入链路保持不变，标签状态由右侧低对比度区域单独展示。
 */
class LibrarySearchSurface extends StatefulWidget {
  const LibrarySearchSurface({
    required this.controller,
    required this.searchFocusNode,
    required this.compact,
    required this.keywordActive,
    required this.onSearchChanged,
    required this.onClearKeyword,
  });

  /** 页面持有的唯一搜索文本控制器。 */
  final TextEditingController controller;

  /** 与 `Ctrl+K`、真实键盘和自动化输入共享的焦点节点。 */
  final FocusNode searchFocusNode;

  /** 紧凑布局使用更短提示并降低内部留白。 */
  final bool compact;

  /** 关键词存在时强调边框，并提供独立清除入口。 */
  final bool keywordActive;

  /** 搜索文本变化统一进入页面已有的筛选刷新链路。 */
  final ValueChanged<String> onSearchChanged;

  /** 只清除关键词，不改变其它标签条件。 */
  final VoidCallback onClearKeyword;

  @override
  State<LibrarySearchSurface> createState() => _LibrarySearchSurfaceState();
}

/** 只保存搜索表面的 hover/focus 视觉状态，不介入关键词和筛选业务状态。 */
class _LibrarySearchSurfaceState extends State<LibrarySearchSurface> {
  /** 鼠标是否停留在搜索表面；只用于轻量颜色反馈。 */
  var _hovered = false;

  /** 真实搜索输入是否持有键盘焦点。 */
  var _focused = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.searchFocusNode.hasFocus;
    widget.searchFocusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant LibrarySearchSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchFocusNode == widget.searchFocusNode) {
      return;
    }
    oldWidget.searchFocusNode.removeListener(_handleFocusChanged);
    _focused = widget.searchFocusNode.hasFocus;
    widget.searchFocusNode.addListener(_handleFocusChanged);
  }

  /** 同步真实 TextField 焦点，让边框反馈与键盘焦点保持一致。 */
  void _handleFocusChanged() {
    if (mounted && _focused != widget.searchFocusNode.hasFocus) {
      setState(() => _focused = widget.searchFocusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    widget.searchFocusNode.removeListener(_handleFocusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    final compact = widget.compact;
    final keywordActive = widget.keywordActive;
    final outline = accessibility.highContrast
        ? appAccentViolet
        : _focused
            ? appAccentViolet
            : keywordActive
                ? appAccentViolet.withValues(alpha: 0.62)
                : _hovered
                    ? libraryTextMuted.withValues(alpha: 0.64)
                    : libraryBorder;
    final surface = _hovered && !_focused
        ? Color.alphaBlend(
            appAccentViolet.withValues(alpha: 0.045),
            librarySurface,
          )
        : librarySurface;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        key: LibrarySmokeKeys.searchSurface,
        height: compact ? 44 : libraryTopBarControlHeight,
        duration: accessibility.fadeDuration(AppMotion.hover),
        curve: AppMotion.standardCurve,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: outline,
            width: accessibility.highContrast || _focused ? 1.5 : 1,
          ),
          boxShadow: _focused
              ? <BoxShadow>[
                  BoxShadow(
                    color: appAccentViolet.withValues(alpha: 0.10), // 焦点光晕保持克制。
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : librarySoftShadow,
        ),
        child: Row(
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: compact ? AppSpacing.sm : AppSpacing.md,
                right: AppSpacing.xs,
              ),
              child: Icon(
                Icons.search_rounded,
                size: compact ? 20 : 22,
                color: _focused || keywordActive
                    ? appAccentViolet
                    : libraryTextMuted,
              ),
            ),
            Expanded(
              child: SizedBox(
                key: LibrarySmokeKeys.searchInputLane,
                /**
               * 必须保持为 TextField，而不是把输入模拟成 GestureDetector 或 SearchBar；
               * 真实键盘、自动化输入和 controller 改写因此继续触发同一条 onChanged 链路。
               */
                child: TextField(
                  key: LibrarySmokeKeys.searchField,
                  controller: widget.controller,
                  focusNode: widget.searchFocusNode,
                  textInputAction: TextInputAction.search,
                  onChanged: widget.onSearchChanged,
                  onSubmitted: widget.onSearchChanged,
                  cursorColor: appAccentViolet,
                  style: const TextStyle(
                    color: libraryText,
                    fontSize: AppTypography.body,
                    fontWeight: AppTypography.medium,
                  ),
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: compact ? 12 : 15,
                    ),
                    hintText: compact
                        ? '\u641c\u7d22\u6587\u4ef6\u0020\u002f\u0020\u6807\u7b7e'
                        : '\u641c\u7d22\u6587\u4ef6\u540d\u002f\u6807\u7b7e\u002f\u8def\u5f84\u002e\u002e\u002e',
                    hintStyle: const TextStyle(
                      color: libraryTextMuted,
                      fontSize: AppTypography.body,
                      fontWeight: AppTypography.medium,
                    ),
                  ),
                ),
              ),
            ),
            if (keywordActive)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xxs),
                child: LibraryStatusIconAction(
                  tooltip: '\u6e05\u9664\u641c\u7d22\u5173\u952e\u8bcd',
                  icon: Icons.close_rounded,
                  onPressed: widget.onClearKeyword,
                ),
              )
            else
              const SizedBox(width: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

/** 搜索与筛选状态共用的 40 像素图标动作，保留 tooltip、焦点和按压反馈。 */
class LibraryStatusIconAction extends StatelessWidget {
  const LibraryStatusIconAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  /** 鼠标悬停和辅助技术读取的动作名称。 */
  final String tooltip;

  /** 与动作语义对应的 Material 图标。 */
  final IconData icon;

  /** 点击或键盘激活回调。 */
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 40,
      child: Tooltip(
        message: tooltip,
        child: AppInteractionSurface(
          semanticLabel: tooltip,
          onTap: onPressed,
          padding: EdgeInsets.zero,
          borderRadius: AppRadius.control,
          backgroundColor: Colors.transparent,
          child: Center(
            child: Icon(icon, size: 17, color: libraryTextMuted),
          ),
        ),
      ),
    );
  }
}
