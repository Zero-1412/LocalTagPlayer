import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_theme_tokens.dart';
import 'library_smoke_keys.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

/** 侧栏分组标题；只表达导航层级，不持有筛选或页面状态。 */
class LibrarySidebarSectionLabel extends StatelessWidget {
  const LibrarySidebarSectionLabel({required this.label});

  /** 当前导航分组名称。 */
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xff7f8ca1),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.45,
      ),
    );
  }
}

/** 侧栏资料库统计行；数值由页面计算，本组件不触发查询。 */
class LibrarySidebarLibraryStat extends StatelessWidget {
  const LibrarySidebarLibraryStat({
    required this.label,
    required this.value,
  });

  /** 统计指标名称。 */
  final String label;

  /** 调用方已经格式化的统计值。 */
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xff8ea0b8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xffcbd5e1),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

/**
 * 本地媒体库 root 的侧栏条目。
 *
 * 点击只转交路径选择，移除只转交管理动作；组件不直接修改目录或媒体数据。
 */
class LibrarySidebarLocalLibraryItem extends StatelessWidget {
  const LibrarySidebarLocalLibraryItem({
    required this.path,
    required this.selected,
    required this.onTap,
    required this.onRemove,
  });

  /** 标签库中显示的标签名。 */
  final String path;

  /** 当前标签是否已参与筛选，用于给列表项提供选中态。 */
  final bool selected;

  /** 点击标签后切换媒体库筛选。 */
  final VoidCallback onTap;

  /** 从快捷列表移除；不删除真实标签或视频关联。 */
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final label = p.basename(path).isEmpty ? path : p.basename(path);
    return Semantics(
      button: true,
      selected: selected,
      label: LibrarySmokeSemantics.localRoot(path),
      value: path,
      child: Material(
        key: LibrarySmokeKeys.localRoot(path),
        color: selected ? const Color(0xff263244) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(left: 10, right: 2),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 17,
                  color: selected ? appAccentViolet : const Color(0xff94a3b8),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xffcbd5e1),
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '\u79fb\u9664\u672c\u5730\u5e93\u8def\u5f84',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: const Color(0xff94a3b8),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/** 侧栏普通导航条目；只呈现选中态并转发点击意图。 */
class LibrarySidebarNavItem extends StatelessWidget {
  const LibrarySidebarNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    this.trailing,
    this.onTap,
  });

  /** 导航入口图标。 */
  final IconData icon;

  /** 导航入口名称，同时作为无障碍标签。 */
  final String label;

  /** 当前入口是否代表页面正在展示的来源。 */
  final bool selected;

  /** 可选的数量或简短状态。 */
  final String? trailing;

  /** 点击意图；为空时保持禁用语义。 */
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        button: onTap != null,
        selected: selected,
        label: label,
        child: Material(
          color: selected
              ? appAccentViolet.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: onTap,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? appAccentViolet : libraryTextMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? libraryText : const Color(0xffb8c3d3),
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
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
          ),
        ),
      ),
    );
  }
}
