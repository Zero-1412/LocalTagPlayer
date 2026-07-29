import 'package:flutter/material.dart';

import '../app_theme_tokens.dart';
import 'library_smoke_keys.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * expanded 主界面标题区里的标签浏览入口。
 *
 * 横向按钮用同一入口承担展开与收起；筛选数量只作状态提示，不复制过滤计算。
 */
class LibraryTagDiscoveryHeaderButton extends StatelessWidget {
  const LibraryTagDiscoveryHeaderButton({
    super.key,
    required this.expanded,
    required this.activeFilterCount,
    required this.onPressed,
  });

  /** 右侧标签发现面板当前是否展开。 */
  final bool expanded;

  /** 当前已生效标签条件数量，用于入口上的轻量状态提示。 */
  final int activeFilterCount;

  /** 切换右侧标签发现面板。 */
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tooltip = expanded ? '折叠标签筛选' : '展开标签筛选';
    return Tooltip(
      message: tooltip,
      child: Semantics(
        key: LibrarySmokeKeys.collapsedTagRail,
        button: true,
        label: tooltip,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(
            expanded ? Icons.view_sidebar_rounded : Icons.sell_outlined,
            size: 18,
          ),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('标签'),
              if (activeFilterCount > 0) ...[
                const SizedBox(width: 7),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: appAccentViolet.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.capsule),
                  ),
                  child: Text(
                    '$activeFilterCount',
                    style: const TextStyle(
                      color: appAccentViolet,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: expanded ? libraryText : libraryTextMuted,
            backgroundColor: expanded ? librarySurfaceAlt : Colors.transparent,
            side: BorderSide(
              color: expanded
                  ? appAccentViolet.withValues(alpha: 0.44)
                  : libraryBorder,
            ),
            minimumSize: const Size(88, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
        ),
      ),
    );
  }
}
