import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/layout_size.dart';
import '../../core/tag_rules.dart';
import '../../models/library_sort.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../app_theme_tokens.dart';
import 'library_result_view_toggle.dart';
import 'library_smoke_keys.dart';
import 'library_sort_control.dart';
import 'library_top_bar_filter_status.dart';
import 'library_top_bar_search_surface.dart';

/** 顶栏搜索框在主布局或窄行中占据剩余宽度，防止动作按钮溢出。 */
bool referenceTopBarSearchShouldFillRow(
  LayoutSize layoutSize,
  double rowWidth,
) {
  return layoutSize != LayoutSize.expanded || rowWidth < 1120;
}

/**
 * 顶栏与首行视频卡片之间的垂直留白。
 *
 * 搜索、筛选状态和结果卡片属于不同视觉层级，保留明确间距可以避免首行缩略图紧贴
 * 搜索表面；该值只影响布局，不改变搜索输入或筛选刷新链路。
 */
const double libraryTopBarBottomSpacing = 18;

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

Color libraryGroupColor(String groupId) {
  return switch (groupId) {
    'folder.primary' => appAccentViolet,
    'folder.child' => const Color(0xff6366f1),
    'manual' => const Color(0xff0f766e),
    _ => const Color(0xff64748b),
  };
}

String formatCount(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index += 1) {
    final remaining = text.length - index;
    buffer.write(text[index]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

Map<String, List<TagItem>> childTagItemsByParentId(
  Iterable<TagItem> tags,
  TagQueryContext context,
) {
  final primaryByName = <String, TagItem>{};
  for (final tag in tags) {
    if (_isFolderPrimaryDiscoveryTag(tag)) {
      primaryByName[tag.name] = tag;
      if (tag.displayName != null) {
        primaryByName[tag.displayName!] = tag;
      }
    }
  }

  final grouped = <String, List<TagItem>>{};
  for (final tag in tags) {
    if (!_isFolderChildDiscoveryTag(tag)) {
      continue;
    }
    final parentKey = tag.parentId?.trim();
    if (parentKey == null || parentKey.isEmpty) {
      continue;
    }
    final parent = context.tagsById[parentKey] ?? primaryByName[parentKey];
    if (parent == null) {
      continue;
    }
    grouped.putIfAbsent(parent.id, () => <TagItem>[]).add(tag);
  }
  for (final entry in grouped.entries) {
    entry.value.sort((a, b) {
      final byCount = b.usageCount.compareTo(a.usageCount);
      if (byCount != 0) {
        return byCount;
      }
      return (a.displayName ?? a.name).compareTo(b.displayName ?? b.name);
    });
  }
  return grouped;
}

List<TagItem> strictChildItemsForParent(
  TagItem parent,
  Map<String, List<TagItem>> childItemsByParent,
) {
  return childItemsByParent[parent.id] ?? const <TagItem>[];
}

List<TagItem> displayChildItemsForPrimary(
  TagItem parent,
  Map<String, List<TagItem>> childItemsByParent,
) {
  return strictChildItemsForParent(parent, childItemsByParent)
      .where((child) => !TagRules.sameTag(
            child.displayName ?? child.name,
            TagRules.defaultAlbumTag,
          ))
      .toList();
}

String? secondaryTagParentLabel(
  TagItem tag, {
  required bool showParentLabel,
}) {
  if (!showParentLabel) {
    return null;
  }
  final parentLabel = tag.parentId?.trim();
  return parentLabel == null || parentLabel.isEmpty ? null : parentLabel;
}

bool secondaryTagNameHasConflict(
  TagItem tag,
  Iterable<TagItem> allSecondaryTags,
) {
  final name = (tag.displayName ?? tag.name).trim().toLowerCase();
  if (name.isEmpty) {
    return false;
  }
  var matches = 0;
  for (final candidate in allSecondaryTags) {
    final candidateName =
        (candidate.displayName ?? candidate.name).trim().toLowerCase();
    if (candidateName != name) {
      continue;
    }
    matches += 1;
    if (matches > 1) {
      return true;
    }
  }
  return false;
}

/**
 * 判断标签是否可作为右侧发现面板的一级文件夹标签。
 *
 * 一级标签只能来自本地媒体库 root 下第一层目录；历史数据里如果有二级或 manual 标签被错误写入
 * `folder.primary` 组，这里会在展示层过滤掉，避免破坏文件树层级。
 */
bool _isFolderPrimaryDiscoveryTag(TagItem tag) {
  return tag.source == TagSource.folder &&
      tag.groupId == 'folder.primary' &&
      tag.parentId == null &&
      tag.id.startsWith('folder.primary:');
}

/**
 * 判断标签是否可作为右侧发现面板的二级文件夹标签。
 *
 * 二级标签必须有父级一级目录，且只在一级展开卡或“全部二级标签”页签中展示。
 */
bool _isFolderChildDiscoveryTag(TagItem tag) {
  final parentId = tag.parentId?.trim();
  return tag.source == TagSource.folder &&
      tag.groupId == 'folder.child' &&
      parentId != null &&
      parentId.isNotEmpty &&
      tag.id.startsWith('folder.child:');
}

/**
 * 从真实本地媒体库路径派生右侧发现面板的文件夹标签。
 *
 * 该函数不信任历史 `tags` 表里的 folder.primary / folder.child 记录，而是按当前视频路径相对
 * 媒体库 root 的层级重新计算：root 下一层是一级，下一层是二级。多个 root 命中时优先使用最上层
 * root，避免 `X:\test-media\崩坏三` 这样的子 root 把 `李素裳` 误当一级。
 */
List<TagGroup> folderTagGroupsFromLibraryPaths({
  required Iterable<VideoItem> videos,
  required Iterable<String> roots,
  required Iterable<TagGroup> templates,
}) {
  final primaryCounts = <String, int>{};
  final childCounts = <String, int>{};
  final childParents = <String, String>{};
  for (final item in videos) {
    final segments = TagRules.relativeFolderSegmentsForBestRoot(
      item.path,
      roots: roots,
      fallbackRoot: item.rootPath,
    );
    if (segments.isEmpty) {
      continue;
    }
    final primary = segments.first;
    final primaryId = TagRules.tagIdFor(
      name: primary,
      groupId: 'folder.primary',
    );
    primaryCounts[primaryId] = (primaryCounts[primaryId] ?? 0) + 1;
    final child = segments.length > 1 ? segments[1] : TagRules.defaultAlbumTag;
    final childId = TagRules.tagIdFor(
      name: child,
      groupId: 'folder.child',
      parentId: primary,
    );
    childCounts[childId] = (childCounts[childId] ?? 0) + 1;
    childParents[childId] = primary;
  }

  final templateById = {for (final group in templates) group.id: group};
  final primaryTemplate = templateById['folder.primary'] ??
      const TagGroup(id: 'folder.primary', name: 'folder.primary', items: []);
  final childTemplate = templateById['folder.child'] ??
      const TagGroup(id: 'folder.child', name: 'folder.child', items: []);

  TagGroup copyTemplate(TagGroup template, List<TagItem> items) => TagGroup(
        id: template.id,
        name: template.name,
        displayName: template.displayName,
        sortOrder: template.sortOrder,
        allowMultiSelect: template.allowMultiSelect,
        defaultLogic: template.defaultLogic,
        items: items,
        excludedItems: template.excludedItems,
      );

  final primaryItems = [
    for (final entry in primaryCounts.entries)
      TagItem(
        id: entry.key,
        name: entry.key.split(':').last,
        displayName: entry.key.split(':').last,
        groupId: 'folder.primary',
        source: TagSource.folder,
        usageCount: entry.value,
      ),
  ]..sort((a, b) {
      final byCount = b.usageCount.compareTo(a.usageCount);
      if (byCount != 0) {
        return byCount;
      }
      return (a.displayName ?? a.name).compareTo(b.displayName ?? b.name);
    });

  final childItems = [
    for (final entry in childCounts.entries)
      TagItem(
        id: entry.key,
        name: entry.key.split(':').last,
        displayName: entry.key.split(':').last,
        groupId: 'folder.child',
        parentId: childParents[entry.key],
        source: TagSource.folder,
        usageCount: entry.value,
      ),
  ]..sort((a, b) {
      final byCount = b.usageCount.compareTo(a.usageCount);
      if (byCount != 0) {
        return byCount;
      }
      return (a.displayName ?? a.name).compareTo(b.displayName ?? b.name);
    });

  return [
    copyTemplate(primaryTemplate, primaryItems),
    copyTemplate(childTemplate, childItems),
  ];
}

List<TagGroup> primaryTagGroupsForDiscovery(List<TagGroup> groups) {
  return [
    for (final group in groups)
      if (group.id == 'folder.primary')
        TagGroup(
          id: group.id,
          name: group.name,
          displayName: group.displayName,
          sortOrder: group.sortOrder,
          allowMultiSelect: group.allowMultiSelect,
          defaultLogic: group.defaultLogic,
          items: [
            for (final tag in group.items)
              if (_isFolderPrimaryDiscoveryTag(tag)) tag,
          ],
          excludedItems: group.excludedItems,
        ),
  ];
}

List<TagItem> secondaryTagsForDiscovery(
  List<TagGroup> groups,
  Map<String, int> resultCounts,
) {
  final tags = <TagItem>[
    for (final group in groups)
      if (group.id == 'folder.child')
        for (final tag in group.items)
          if (_isFolderChildDiscoveryTag(tag) &&
              !TagRules.sameTag(
                tag.displayName ?? tag.name,
                TagRules.defaultAlbumTag,
              ))
            tag,
  ];
  tags.sort((a, b) {
    final byCount = (resultCounts[b.id] ?? b.usageCount)
        .compareTo(resultCounts[a.id] ?? a.usageCount);
    if (byCount != 0) {
      return byCount;
    }
    return (a.displayName ?? a.name).compareTo(b.displayName ?? b.name);
  });
  return tags;
}

/** 多选状态只替换搜索框右侧区域，搜索输入和关键词保持可见。 */
class _LibrarySelectionToolbar extends StatelessWidget {
  const _LibrarySelectionToolbar({
    required this.selectedCount,
    required this.allSelected,
    required this.onToggleSelectAll,
    required this.onDeleteSelected,
    required this.onCancel,
  });

  /** 当前完整结果范围内已选择的视频数量。 */
  final int selectedCount;

  /** 当前完整结果是否已全部选择。 */
  final bool allSelected;

  /** 圆形复选框承担全选/取消全选入口。 */
  final VoidCallback? onToggleSelectAll;

  /** 删除已选视频；未选择时由页面传入 null。 */
  final VoidCallback? onDeleteSelected;

  /** 退出多选并清空临时选择。 */
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: LibrarySmokeKeys.selectionStatusArea,
      width: double.infinity,
      height: 50,
      child: Row(
        children: [
          InkWell(
            key: LibrarySmokeKeys.librarySelectAll,
            borderRadius: BorderRadius.circular(8),
            onTap: onToggleSelectAll,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  Checkbox(
                    value: allSelected,
                    onChanged: onToggleSelectAll == null
                        ? null
                        : (_) => onToggleSelectAll!(),
                    shape: const CircleBorder(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 6),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        color: libraryText,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                      children: [
                        const TextSpan(text: '\u5df2\u9009\u62e9 '),
                        TextSpan(
                          text: '$selectedCount',
                          style: const TextStyle(
                            color: appAccentViolet,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const TextSpan(text: ' \u9879'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            key: LibrarySmokeKeys.libraryDeleteSelected,
            onPressed: onDeleteSelected,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('\u5220\u9664'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xffe26573),
              disabledForegroundColor: libraryTextMuted.withValues(alpha: 0.45),
              backgroundColor: onDeleteSelected == null
                  ? Colors.transparent
                  : const Color(0x24e26573),
              minimumSize: const Size(68, 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: LibrarySmokeKeys.libraryCancelSelection,
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: libraryTextMuted,
              minimumSize: const Size(56, 34),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('\u53d6\u6d88'),
          ),
        ],
      ),
    );
  }
}

class SmartListDraftDialog extends StatefulWidget {
  const SmartListDraftDialog({
    required this.suggestedName,
    required this.querySummary,
    required this.queryExpression,
    required this.resultCount,
    required this.totalCount,
    required this.onConfirmDraft,
  });

  final String suggestedName;
  final String querySummary;
  final String queryExpression;
  final int resultCount;
  final int totalCount;
  final VoidCallback onConfirmDraft;

  @override
  State<SmartListDraftDialog> createState() => SmartListDraftDialogState();
}

class SmartListDraftDialogState extends State<SmartListDraftDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.suggestedName);
  var _autoRefreshPreview = true;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _confirmDraft() {
    Navigator.of(context).pop();
    widget.onConfirmDraft();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
      actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xfff5f3ff),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xffd8d4ff)),
            ),
            child: const Icon(Icons.bookmark_add_outlined,
                color: appAccentViolet, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '\u4fdd\u5b58\u7b5b\u9009\u8349\u6848',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '\u7b5b\u9009\u540d\u79f0',
                prefixIcon: Icon(Icons.edit_outlined),
              ),
            ),
            const SizedBox(height: 14),
            _SmartListPreviewPanel(
              querySummary: widget.querySummary,
              queryExpression: widget.queryExpression,
              resultCount: widget.resultCount,
              totalCount: widget.totalCount,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _autoRefreshPreview,
              onChanged: (value) {
                setState(() => _autoRefreshPreview = value);
              },
              contentPadding: EdgeInsets.zero,
              title: const Text('\u81ea\u52a8\u5237\u65b0\u9884\u89c8'),
              subtitle: const Text(
                  '\u4ec5\u9a8c\u8bc1 UI \u6d41\u7a0b\uff0c\u4e0d\u5199\u5165 SQLite'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('\u53d6\u6d88'),
        ),
        FilledButton.icon(
          onPressed: _confirmDraft,
          icon: const Icon(Icons.check_rounded),
          label: const Text('\u786e\u8ba4\u8349\u6848'),
        ),
      ],
    );
  }
}

class _SmartListPreviewPanel extends StatelessWidget {
  const _SmartListPreviewPanel({
    required this.querySummary,
    required this.queryExpression,
    required this.resultCount,
    required this.totalCount,
  });

  final String querySummary;
  final String queryExpression;
  final int resultCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: libraryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.manage_search_rounded,
                  size: 18, color: appAccentViolet),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  querySummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: libraryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$resultCount / $totalCount',
                style: const TextStyle(
                  color: appAccentViolet,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            queryExpression,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: libraryTextMuted,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

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

class ReferenceTopBar extends StatelessWidget {
  const ReferenceTopBar({
    required this.controller,
    required this.searchFocusNode,
    required this.videoCount,
    this.resultCountLabel,
    required this.keyword,
    required this.selectedTags,
    required this.selectedChildTags,
    required this.selectedGroupTags,
    required this.excludedTags,
    required this.defaultChipLabel,
    required this.showFavoritesOnly,
    required this.refreshing,
    required this.progressLabel,
    required this.progressValue,
    required this.sortMode,
    required this.sortDirection,
    required this.layoutSize,
    required this.hasActiveFilters,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onSortDirectionToggle,
    required this.denseResultGrid,
    required this.onResultViewChanged,
    required this.onOpenTagManager,
    required this.onOpenFilters,
    this.tagPanelOpen = false,
    this.onToggleTagPanel,
    required this.onRemovePrimaryTag,
    required this.onRemoveChildTag,
    required this.onRemoveGroupTag,
    required this.onRemoveExcludedTag,
    required this.onClearKeyword,
    required this.onClearFavoritesOnly,
    required this.onClearAll,
    this.progressPaused = false,
    this.onToggleProgressPaused,
    this.onCancelProgress,
    this.selectionMode = false,
    this.selectedCount = 0,
    this.allSelected = false,
    this.onEnterSelectionMode,
    this.onToggleSelectAll,
    this.onDeleteSelected,
    this.onCancelSelectionMode,
  });

  final TextEditingController controller;

  /**
   * 主搜索框焦点节点。
   *
   * 顶部栏内部处理 `Ctrl+K` 时只请求该节点焦点，不直接改写搜索业务状态；
   * 文本变化仍统一从 TextField 的 controller / onChanged 进入筛选链路。
   */
  final FocusNode searchFocusNode;

  /** 当前可见结果数量；与搜索和 chips 同处一个结果状态区域。 */
  final int videoCount;

  /** 本地目录等混合来源的精确统计文案。 */
  final String? resultCountLabel;

  /** 当前关键词只保留在真实输入框中，不重复渲染为 chip。 */
  final String keyword;

  /** 当前一级 folder 标签筛选。 */
  final List<String> selectedTags;

  /** 当前二级 folder 标签筛选。 */
  final List<String> selectedChildTags;

  /** 当前分组标签筛选。 */
  final List<TagItem> selectedGroupTags;

  /** 当前排除标签筛选。 */
  final List<TagItem> excludedTags;

  /** 最近播放、本地收藏或本地目录等非全库结果来源名称。 */
  final String defaultChipLabel;

  /** 是否启用收藏筛选。 */
  final bool showFavoritesOnly;

  /** 当前结果或标签计数是否正在后台刷新。 */
  final bool refreshing;

  /** 扫描或媒体解析时替代普通结果数量的状态。 */
  final String? progressLabel;

  /** 已知总量任务的进度值。 */
  final double? progressValue;

  final SortMode sortMode;

  final SortDirection sortDirection;

  final LayoutSize layoutSize;

  final bool hasActiveFilters;

  final ValueChanged<String> onSearchChanged;

  final ValueChanged<SortMode> onSortChanged;

  final VoidCallback onSortDirectionToggle;

  final bool denseResultGrid;

  final ValueChanged<bool> onResultViewChanged;

  final VoidCallback onOpenTagManager;

  final VoidCallback onOpenFilters;

  /** expanded 桌面布局中的标签浏览面板是否已经展开。 */
  final bool tagPanelOpen;

  /** 从页面标题区展开或收起标签浏览面板；中小布局继续使用底部筛选面板。 */
  final VoidCallback? onToggleTagPanel;

  final ValueChanged<String> onRemovePrimaryTag;

  final ValueChanged<String> onRemoveChildTag;

  final ValueChanged<TagItem> onRemoveGroupTag;

  final ValueChanged<TagItem> onRemoveExcludedTag;

  final VoidCallback onClearKeyword;

  final VoidCallback onClearFavoritesOnly;

  final VoidCallback? onClearAll;

  /** true 时暂停按钮切换为继续图标。 */
  final bool progressPaused;

  /** 后台媒体解析存在时提供暂停/继续入口。 */
  final VoidCallback? onToggleProgressPaused;

  /** 扫描期间提供取消入口；其它后台任务保持为空。 */
  final VoidCallback? onCancelProgress;

  /** true 时整条顶栏替换为批量选择状态。 */
  final bool selectionMode;

  /** 当前完整结果范围内已选择的视频数量。 */
  final int selectedCount;

  /** 当前完整结果是否已全部选择。 */
  final bool allSelected;

  /** 进入多选模式；为空时当前结果来源不支持批量删除。 */
  final VoidCallback? onEnterSelectionMode;

  /** 切换完整当前结果的全选状态。 */
  final VoidCallback? onToggleSelectAll;

  /** 删除已选视频；未选择时页面传入 null。 */
  final VoidCallback? onDeleteSelected;

  /** 退出多选并清空临时选择。 */
  final VoidCallback? onCancelSelectionMode;

  @override
  Widget build(BuildContext context) {
    final compact = layoutSize == LayoutSize.compact;
    final accessibility = AppAccessibilityScope.of(context);
    // 只在非紧凑桌面工具栏扩展结果状态宽度；125%/150% 下完整保留
    // “11163 个视频”这类关键反馈，同时不改变筛选、排序或搜索语义。
    final resultTextScaleAllowance = compact
        ? 0.0
        : (accessibility.textScaler.scale(1).clamp(1.0, 1.5) - 1) * 160;
    final keywordActive = keyword.trim().isNotEmpty;
    final activeFilters = <LibraryFilterToolbarEntry>[
      if (showFavoritesOnly)
        LibraryFilterToolbarEntry(
          label: '\u672c\u5730\u6536\u85cf',
          icon: Icons.favorite_rounded,
          onRemove: onClearFavoritesOnly,
        ),
      for (final tag in selectedTags)
        LibraryFilterToolbarEntry(
          label: tag,
          onRemove: () => onRemovePrimaryTag(tag),
        ),
      for (final tag in selectedChildTags)
        LibraryFilterToolbarEntry(
          label: tag,
          onRemove: () => onRemoveChildTag(tag),
        ),
      for (final tag in selectedGroupTags)
        LibraryFilterToolbarEntry(
          label: tag.displayName ?? tag.name,
          onRemove: () => onRemoveGroupTag(tag),
        ),
      for (final tag in excludedTags)
        LibraryFilterToolbarEntry(
          label: 'NOT ${tag.displayName ?? tag.name}',
          onRemove: () => onRemoveExcludedTag(tag),
        ),
    ];
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            const FocusLibrarySearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          FocusLibrarySearchIntent: CallbackAction<FocusLibrarySearchIntent>(
            onInvoke: (_) {
              searchFocusNode.requestFocus();
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
              // 顶部栏单独作为 smoke 宿主时也补一次下一帧聚焦，保持与真实页面一致。
              WidgetsBinding.instance.addPostFrameCallback((_) {
                searchFocusNode.requestFocus();
                controller.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: controller.text.length,
                );
              });
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                layoutSize == LayoutSize.expanded ? 20 : 12,
                12,
                layoutSize == LayoutSize.expanded ? 20 : 12,
                libraryTopBarBottomSpacing,
              ),
              child: DecoratedBox(
                key: LibrarySmokeKeys.libraryResultToolbar,
                decoration: BoxDecoration(
                  color: layoutSize == LayoutSize.expanded
                      ? Colors.transparent
                      : librarySurface,
                  borderRadius: BorderRadius.circular(AppRadius.panel),
                  border: layoutSize == LayoutSize.expanded
                      ? null
                      : Border.all(color: libraryBorder),
                ),
                child: Padding(
                  // expanded 主界面改用“标题 + 操作 + 状态”的分层结构，不再把所有功能
                  // 塞进一个后台工具条式容器；中小布局仍保留紧凑单行，避免占用结果空间。
                  padding: layoutSize == LayoutSize.expanded
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrowMedium = layoutSize == LayoutSize.medium &&
                          constraints.maxWidth < 620;
                      final proportionalDesktop =
                          layoutSize == LayoutSize.expanded &&
                              constraints.maxWidth >= 1180;
                      final searchSurface = LibrarySearchSurface(
                        controller: controller,
                        searchFocusNode: searchFocusNode,
                        compact: compact,
                        keywordActive: keywordActive,
                        onSearchChanged: onSearchChanged,
                        onClearKeyword: onClearKeyword,
                      );
                      final filterStatus = LibraryFilterStatusArea(
                        compact: compact || narrowMedium,
                        defaultLabel: defaultChipLabel,
                        filters: activeFilters,
                        resultCount: videoCount,
                        resultCountLabel: resultCountLabel,
                        refreshing: refreshing,
                        progressLabel: progressLabel,
                        progressValue: progressValue,
                        progressPaused: progressPaused,
                        onToggleProgressPaused: onToggleProgressPaused,
                        onCancelProgress: onCancelProgress,
                        onClearAll: onClearAll,
                        showResultStatus: !proportionalDesktop,
                      );
                      final resultStatus = SizedBox(
                        key: LibrarySmokeKeys.toolbarResultStatus,
                        width: progressLabel == null
                            ? (resultCountLabel == null ? 92 : 200) +
                                resultTextScaleAllowance
                            : 224,
                        child: LibraryFilterResultLine(
                          resultCount: videoCount,
                          resultCountLabel: resultCountLabel,
                          refreshing: refreshing,
                          progressLabel: progressLabel,
                          progressValue: progressValue,
                          progressPaused: progressPaused,
                          onToggleProgressPaused: onToggleProgressPaused,
                          onCancelProgress: onCancelProgress,
                        ),
                      );
                      final selectionStatus = _LibrarySelectionToolbar(
                        selectedCount: selectedCount,
                        allSelected: allSelected,
                        onToggleSelectAll: onToggleSelectAll,
                        onDeleteSelected: onDeleteSelected,
                        onCancel: onCancelSelectionMode,
                      );
                      final sortControl = _CompactTopSortControl(
                        sortMode: sortMode,
                        sortDirection: sortDirection,
                        showCurrentField: layoutSize == LayoutSize.expanded,
                        onChanged: onSortChanged,
                        onDirectionToggle: onSortDirectionToggle,
                      );
                      final normalActions = SizedBox(
                        key: LibrarySmokeKeys.toolbarActions,
                        height: 48,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (onEnterSelectionMode != null)
                              if (compact || narrowMedium)
                                _ReferenceIconButton(
                                  key: LibrarySmokeKeys.libraryEnterSelection,
                                  tooltip: '\u591a\u9009',
                                  icon: Icons.checklist_rounded,
                                  onPressed: onEnterSelectionMode!,
                                )
                              else
                                _TopToolbarTextButton(
                                  key: LibrarySmokeKeys.libraryEnterSelection,
                                  onPressed: onEnterSelectionMode!,
                                  label: '\u591a\u9009',
                                ),
                            if (onEnterSelectionMode != null &&
                                !compact &&
                                !narrowMedium)
                              const SizedBox(width: 8),
                            if (!compact && !narrowMedium)
                              ResultViewToggle(
                                dense: denseResultGrid,
                                onChanged: onResultViewChanged,
                              ),
                          ],
                        ),
                      );
                      if (layoutSize == LayoutSize.expanded) {
                        final pageTitle = defaultChipLabel == '全部视频'
                            ? '媒体库'
                            : defaultChipLabel;
                        final resultStatusWidth = progressLabel == null
                            ? (resultCountLabel == null ? 104.0 : 200.0) +
                                resultTextScaleAllowance
                            : 224.0;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          pageTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: libraryText,
                                            fontSize: 24,
                                            height: 1.12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          defaultChipLabel == '全部视频'
                                              ? '全部视频 · 浏览、搜索并整理你的本地视频'
                                              : '当前资料库视图',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: libraryTextMuted,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    key: LibrarySmokeKeys.toolbarResultStatus,
                                    width: resultStatusWidth,
                                    child: LibraryFilterResultLine(
                                      resultCount: videoCount,
                                      resultCountLabel: resultCountLabel,
                                      refreshing: refreshing,
                                      progressLabel: progressLabel,
                                      progressValue: progressValue,
                                      progressPaused: progressPaused,
                                      onToggleProgressPaused:
                                          onToggleProgressPaused,
                                      onCancelProgress: onCancelProgress,
                                    ),
                                  ),
                                  if (onToggleTagPanel != null) ...[
                                    const SizedBox(width: 12),
                                    _TagDiscoveryHeaderButton(
                                      expanded: tagPanelOpen,
                                      activeFilterCount: activeFilters.length,
                                      onPressed: onToggleTagPanel!,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // 搜索和动作直接落在画布上，各自用自身 surface 表达可交互性；
                            // 不再用大圆角容器包裹一组已经带边框的控件，避免“容器套容器”。
                            SizedBox(
                              key: LibrarySmokeKeys.headerActionLane,
                              height: 50,
                              child: Row(
                                children: [
                                  Expanded(child: searchSurface),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 380,
                                    child: selectionMode
                                        ? selectionStatus
                                        : Row(
                                            children: [
                                              // 桌面动作带保留固定宽度以避免进入多选时搜索框跳动；
                                              // 排序字段使用紧凑稳定宽度，余量只作为方向与低频动作的分组间距。
                                              SizedBox(
                                                width:
                                                    _expandedSortControlWidth,
                                                child: sortControl,
                                              ),
                                              const SizedBox(width: 12),
                                              // 把少量响应式余量留在动作分组之间，保持视图切换与右边界对齐。
                                              const Spacer(),
                                              normalActions,
                                            ],
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            if (!selectionMode && activeFilters.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              KeyedSubtree(
                                key: LibrarySmokeKeys.filterStatusArea,
                                child: LibraryFilterStatusArea(
                                  compact: false,
                                  defaultLabel: defaultChipLabel,
                                  filters: activeFilters,
                                  resultCount: videoCount,
                                  resultCountLabel: resultCountLabel,
                                  refreshing: refreshing,
                                  progressLabel: progressLabel,
                                  progressValue: progressValue,
                                  progressPaused: progressPaused,
                                  onToggleProgressPaused:
                                      onToggleProgressPaused,
                                  onCancelProgress: onCancelProgress,
                                  onClearAll: onClearAll,
                                  showResultStatus: false,
                                ),
                              ),
                            ],
                          ],
                        );
                      }
                      if (proportionalDesktop) {
                        return SizedBox(
                          height: 50,
                          child: Row(
                            children: [
                              // 搜索从 60% 收敛到 50%，把标签浏览和媒体库状态提升为同级主场景。
                              Expanded(flex: 5, child: searchSurface),
                              const SizedBox(width: 12),
                              if (selectionMode) ...[
                                Expanded(flex: 5, child: selectionStatus),
                                // 与常态区域保留相同总间距，进入多选时搜索框宽度不会跳动。
                                const SizedBox(width: 8),
                              ] else ...[
                                Expanded(
                                  flex: 4,
                                  child: KeyedSubtree(
                                    key: LibrarySmokeKeys.filterStatusArea,
                                    child: Row(
                                      children: [
                                        Expanded(child: filterStatus),
                                        const SizedBox(width: 8),
                                        sortControl,
                                        const SizedBox(width: 10),
                                        resultStatus,
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(flex: 1, child: normalActions),
                              ],
                            ],
                          ),
                        );
                      }
                      return Row(
                        children: [
                          if (layoutSize != LayoutSize.expanded) ...[
                            _ReferenceIconButton(
                              tooltip: '\u6253\u5f00\u667a\u80fd\u7b5b\u9009',
                              icon: hasActiveFilters
                                  ? Icons.filter_alt_rounded
                                  : Icons.filter_alt_outlined,
                              onPressed: onOpenFilters,
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(child: searchSurface),
                          const SizedBox(width: 8),
                          if (selectionMode)
                            SizedBox(width: 280, child: selectionStatus)
                          else ...[
                            SizedBox(
                              key: LibrarySmokeKeys.filterStatusArea,
                              width: progressLabel != null
                                  ? math.min(
                                      360,
                                      math.max(
                                          224, constraints.maxWidth * 0.42),
                                    )
                                  : activeFilters.isNotEmpty
                                      ? narrowMedium
                                          ? 82
                                          : math.min(
                                              220,
                                              math.max(
                                                142,
                                                constraints.maxWidth * 0.24,
                                              ),
                                            )
                                      : narrowMedium
                                          ? 82
                                          : resultCountLabel != null
                                              ? 200 + resultTextScaleAllowance
                                              : 118 + resultTextScaleAllowance,
                              child: filterStatus,
                            ),
                            if (!compact &&
                                !(progressLabel != null &&
                                    constraints.maxWidth < 700)) ...[
                              const SizedBox(width: 8),
                              sortControl,
                            ],
                            if (compact) ...[
                              const SizedBox(width: 8),
                              _ReferenceIconButton(
                                tooltip: '标签中心',
                                icon: Icons.sell_outlined,
                                onPressed: onOpenTagManager,
                              ),
                            ],
                            if (!(progressLabel != null &&
                                constraints.maxWidth < 700)) ...[
                              const SizedBox(width: 8),
                              normalActions,
                            ],
                          ],
                        ],
                      );
                    },
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

/**
 * 顶部搜索框聚焦意图。
 *
 * 独立 intent 让快捷键层只负责焦点转移，不复制搜索和筛选逻辑。
 */
class FocusLibrarySearchIntent extends Intent {
  const FocusLibrarySearchIntent();
}

/**
 * 顶部搜索栏 smoke test 入口。
 *
 * 只暴露真实顶部栏里的搜索输入链路，避免测试复制一份搜索 UI 后漏掉桌面输入问题。
 */
@visibleForTesting
Widget referenceTopBarSearchSmokeHarness({
  required TextEditingController controller,
  required ValueChanged<String> onSearchChanged,
  FocusNode? searchFocusNode,
  int videoCount = 0,
  String? resultCountLabel,
  String? keyword,
  List<String> selectedTags = const <String>[],
  List<String> selectedChildTags = const <String>[],
  List<TagItem> selectedGroupTags = const <TagItem>[],
  List<TagItem> excludedTags = const <TagItem>[],
  String defaultChipLabel = '\u5168\u90e8\u89c6\u9891',
  bool showFavoritesOnly = false,
  bool refreshing = false,
  String? progressLabel,
  double? progressValue,
  bool progressPaused = false,
  VoidCallback? onToggleProgressPaused,
  VoidCallback? onCancelProgress,
  LayoutSize layoutSize = LayoutSize.expanded,
  SortDirection sortDirection = SortDirection.descending,
  ValueChanged<SortMode>? onSortChanged,
  VoidCallback? onSortDirectionToggle,
  ValueChanged<String>? onRemovePrimaryTag,
  ValueChanged<String>? onRemoveChildTag,
  ValueChanged<TagItem>? onRemoveGroupTag,
  ValueChanged<TagItem>? onRemoveExcludedTag,
  VoidCallback? onClearKeyword,
  VoidCallback? onClearFavoritesOnly,
  VoidCallback? onClearAll,
  bool selectionMode = false,
  int selectedCount = 0,
  bool allSelected = false,
  AppAccessibilityData? accessibility,
  VoidCallback? onEnterSelectionMode,
  VoidCallback? onToggleSelectAll,
  VoidCallback? onDeleteSelected,
  VoidCallback? onCancelSelectionMode,
  bool tagPanelOpen = false,
  VoidCallback? onToggleTagPanel,
}) {
  final app = MaterialApp(
    builder: accessibility == null
        ? null
        : (context, child) {
            // focused test 必须让文字缩放同时进入 MediaQuery 和设计策略作用域，
            // 避免只扩大宽度预算却没有真实放大文字的假验收。
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(textScaler: accessibility.textScaler),
              child: child!,
            );
          },
    home: Scaffold(
      body: ReferenceTopBar(
        controller: controller,
        searchFocusNode:
            searchFocusNode ?? FocusNode(debugLabel: 'search-smoke-field'),
        videoCount: videoCount,
        resultCountLabel: resultCountLabel,
        keyword: keyword ?? controller.text,
        selectedTags: selectedTags,
        selectedChildTags: selectedChildTags,
        selectedGroupTags: selectedGroupTags,
        excludedTags: excludedTags,
        defaultChipLabel: defaultChipLabel,
        showFavoritesOnly: showFavoritesOnly,
        refreshing: refreshing,
        progressLabel: progressLabel,
        progressValue: progressValue,
        progressPaused: progressPaused,
        onToggleProgressPaused: onToggleProgressPaused,
        onCancelProgress: onCancelProgress,
        sortMode: SortMode.recent,
        sortDirection: sortDirection,
        layoutSize: layoutSize,
        hasActiveFilters: (keyword ?? controller.text).trim().isNotEmpty ||
            showFavoritesOnly ||
            selectedTags.isNotEmpty ||
            selectedChildTags.isNotEmpty ||
            selectedGroupTags.isNotEmpty ||
            excludedTags.isNotEmpty,
        onSearchChanged: onSearchChanged,
        onSortChanged: onSortChanged ?? (_) {},
        onSortDirectionToggle: onSortDirectionToggle ?? () {},
        denseResultGrid: false,
        onResultViewChanged: (_) {},
        onOpenTagManager: () {},
        onOpenFilters: () {},
        tagPanelOpen: tagPanelOpen,
        onToggleTagPanel: onToggleTagPanel,
        onRemovePrimaryTag: onRemovePrimaryTag ?? (_) {},
        onRemoveChildTag: onRemoveChildTag ?? (_) {},
        onRemoveGroupTag: onRemoveGroupTag ?? (_) {},
        onRemoveExcludedTag: onRemoveExcludedTag ?? (_) {},
        onClearKeyword: onClearKeyword ?? () {},
        onClearFavoritesOnly: onClearFavoritesOnly ?? () {},
        onClearAll: onClearAll,
        selectionMode: selectionMode,
        selectedCount: selectedCount,
        allSelected: allSelected,
        onEnterSelectionMode: onEnterSelectionMode,
        onToggleSelectAll: onToggleSelectAll,
        onDeleteSelected: onDeleteSelected,
        onCancelSelectionMode: onCancelSelectionMode,
      ),
    ),
  );
  if (accessibility == null) {
    return app;
  }
  return AppAccessibilityScope(data: accessibility, child: app);
}

/**
 * 顶部搜索到结果列表的 smoke test 入口。
 *
 * 该 harness 只验证输入链路会驱动结果数量和可见列表变化；真实业务过滤仍由
 * `LibraryPage` / `TagQueryService` 负责，测试里不复制完整标签筛选语义。
 */
@visibleForTesting
class ReferenceTopBarSearchResultSmokeHarness extends StatefulWidget {
  const ReferenceTopBarSearchResultSmokeHarness({
    super.key,
    required this.items,
  });

  /**
   * 用于 smoke 的可搜索标题列表。
   *
   * 只使用字符串能避免测试依赖真实媒体库或数据库。
   */
  final List<String> items;

  @override
  State<ReferenceTopBarSearchResultSmokeHarness> createState() =>
      ReferenceTopBarSearchResultSmokeHarnessState();
}

class ReferenceTopBarSearchResultSmokeHarnessState
    extends State<ReferenceTopBarSearchResultSmokeHarness> {
  /**
   * smoke harness 自己持有 controller，模拟真实页面中的单一输入源。
   */
  final _controller = TextEditingController();

  /**
   * smoke harness 自己持有焦点节点，验证 `Ctrl+K` 能把焦点转给 TextField。
   */
  final _focusNode = FocusNode(debugLabel: 'search-result-smoke-field');

  var _keyword = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = _keyword.trim().toLowerCase();
    final filtered = token.isEmpty
        ? widget.items
        : widget.items
            .where((item) => item.toLowerCase().contains(token))
            .toList();
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ReferenceTopBar(
              controller: _controller,
              searchFocusNode: _focusNode,
              videoCount: filtered.length,
              keyword: _keyword,
              selectedTags: const <String>[],
              selectedChildTags: const <String>[],
              selectedGroupTags: const <TagItem>[],
              excludedTags: const <TagItem>[],
              defaultChipLabel: '\u5168\u90e8\u89c6\u9891',
              showFavoritesOnly: false,
              refreshing: false,
              progressLabel: null,
              progressValue: null,
              sortMode: SortMode.recent,
              sortDirection: SortDirection.descending,
              layoutSize: LayoutSize.expanded,
              hasActiveFilters: token.isNotEmpty,
              onSearchChanged: (value) => setState(() => _keyword = value),
              onSortChanged: (_) {},
              onSortDirectionToggle: () {},
              denseResultGrid: false,
              onResultViewChanged: (_) {},
              onOpenTagManager: () {},
              onOpenFilters: () {},
              onRemovePrimaryTag: (_) {},
              onRemoveChildTag: (_) {},
              onRemoveGroupTag: (_) {},
              onRemoveExcludedTag: (_) {},
              onClearKeyword: () {
                _controller.clear();
                setState(() => _keyword = '');
              },
              onClearFavoritesOnly: () {},
              onClearAll: null,
            ),
            Text('结果 ${filtered.length}/${widget.items.length}'),
            Expanded(
              child: ListView(
                children: [
                  for (final item in filtered) Text(item),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/**
 * 顶栏低频文字动作。
 *
 * 保留 48px 命中高度与相邻控件对齐，但使用透明背景和无边框文字视觉，
 * 让低频“多选”入口不再与高频排序、视图切换争夺同等权重。
 */
class _TopToolbarTextButton extends StatelessWidget {
  const _TopToolbarTextButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  /** 按钮短文案。 */
  final String label;

  /** 点击动作。 */
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? libraryText
              : libraryTextMuted;
        }),
        overlayColor: WidgetStatePropertyAll(
          appAccentViolet.withValues(alpha: 0.10),
        ),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/**
 * expanded 主界面标题区里的标签浏览入口。
 *
 * 横向按钮取代右侧竖排窄条，并用同一个入口承担展开与收起，避免内容区边缘出现
 * 与视频卡片无关的强视觉噪声；筛选数量只作状态提示，不复制过滤计算。
 */
class _TagDiscoveryHeaderButton extends StatelessWidget {
  const _TagDiscoveryHeaderButton({
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

/** 宽桌面排序字段的视觉宽度，同时约束触发入口与弹层。 */
const double _expandedSortFieldWidth = 168;

/** 排序字段、6px 间距和 48px 方向命中区组成的稳定动作宽度。 */
const double _expandedSortControlWidth = _expandedSortFieldWidth + 6 + 48;

/**
 * 媒体库顶部的响应式排序控件。
 *
 * 宽桌面以紧凑固定宽度显示当前字段；中等窗口压缩成图标，
 * 两种形态仍分别回调页面已有排序状态，不复制排序逻辑。
 */
class _CompactTopSortControl extends StatelessWidget {
  const _CompactTopSortControl({
    required this.sortMode,
    required this.sortDirection,
    required this.showCurrentField,
    required this.onChanged,
    required this.onDirectionToggle,
  });

  /** 当前排序字段。 */
  final SortMode sortMode;

  /** 当前排序方向。 */
  final SortDirection sortDirection;

  /** 是否在宽桌面布局中展示当前排序字段。 */
  final bool showCurrentField;

  /** 选择排序字段后交给页面已有轻量重排入口。 */
  final ValueChanged<SortMode> onChanged;

  /** 切换排序方向。 */
  final VoidCallback onDirectionToggle;

  @override
  Widget build(BuildContext context) {
    final ascending = sortDirection == SortDirection.ascending;
    final fieldButton = PopupMenuButton<SortMode>(
      key: LibrarySmokeKeys.topSortFieldButton,
      tooltip: '\u6392\u5e8f\u5b57\u6bb5\uff1a${sortModeLabel(sortMode)}',
      onSelected: onChanged,
      color: librarySurface,
      initialValue: sortMode,
      // 强制从按钮下方展开，避免默认行为把当前选中项对齐到按钮并遮挡触发入口。
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      // 宽桌面入口与弹层共享同一几何宽度，避免触发按钮和菜单各自伸缩造成割裂。
      constraints: showCurrentField
          ? const BoxConstraints.tightFor(width: _expandedSortFieldWidth)
          : null,
      itemBuilder: (context) => [
        for (final mode in SortMode.values)
          PopupMenuItem<SortMode>(
            key: LibrarySmokeKeys.topSortMenuItem(mode),
            value: mode,
            child: Semantics(
              label: LibrarySmokeSemantics.sortMenuItem(mode),
              selected: mode == sortMode,
              // 自动化入口使用稳定标签，菜单可见文字不再合并进 UIA 名称。
              excludeSemantics: true,
              child: Row(
                children: [
                  Icon(
                    mode == sortMode
                        ? Icons.check_rounded
                        : Icons.circle_outlined,
                    size: 17,
                    color:
                        mode == sortMode ? appAccentViolet : libraryTextMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(sortModeLabel(mode)),
                ],
              ),
            ),
          ),
      ],
      borderRadius: BorderRadius.circular(AppRadius.control),
      style: showCurrentField
          ? IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )
          : IconButton.styleFrom(
              backgroundColor: librarySurface,
              foregroundColor: libraryTextMuted,
              fixedSize: const Size(38, 38),
              side: const BorderSide(color: libraryBorder),
            ),
      icon: showCurrentField ? null : const Icon(Icons.sort_rounded, size: 20),
      child: showCurrentField
          ? SizedBox(
              width: _expandedSortFieldWidth,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: librarySurface,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: libraryBorder),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sort_rounded,
                      size: 19,
                      color: appAccentViolet,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        sortModeLabel(sortMode),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: libraryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: libraryTextMuted,
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: LibrarySmokeSemantics.sortFieldButton,
          value: sortModeLabel(sortMode),
          child: fieldButton,
        ),
        const SizedBox(width: 6),
        Semantics(
          key: LibrarySmokeKeys.topSortDirectionButton,
          button: true,
          label: LibrarySmokeSemantics.sortDirectionButton,
          value: ascending ? '\u6b63\u5e8f' : '\u5012\u5e8f',
          child: _ReferenceIconButton(
            tooltip: ascending
                ? '\u5207\u6362\u4e3a\u5012\u5e8f'
                : '\u5207\u6362\u4e3a\u6b63\u5e8f',
            icon: ascending
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            onPressed: onDirectionToggle,
          ),
        ),
      ],
    );
  }
}

class _ReferenceIconButton extends StatelessWidget {
  const _ReferenceIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;

  final IconData icon;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: librarySurface,
        foregroundColor: libraryTextMuted,
        fixedSize: const Size(38, 38),
        side: const BorderSide(color: libraryBorder),
      ),
    );
  }
}
