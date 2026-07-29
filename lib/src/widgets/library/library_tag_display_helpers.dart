import 'package:flutter/material.dart';

import '../../core/tag_rules.dart';
import '../../models/platform_models.dart';
import '../app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 按标签分组返回媒体库 UI 的稳定语义色。 */
Color libraryGroupColor(String groupId) {
  return switch (groupId) {
    'folder.primary' => appAccentViolet,
    'folder.child' => const Color(0xff6366f1),
    'manual' => const Color(0xff0f766e),
    _ => const Color(0xff64748b),
  };
}

/** 为结果数量增加千分位，避免展示层重复格式化规则。 */
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

/** 按规范化一级标签 id 聚合可展示的二级 folder 标签。 */
Map<String, List<TagItem>> childTagItemsByParentId(
  Iterable<TagItem> tags,
  TagQueryContext context,
) {
  final primaryByName = <String, TagItem>{};
  for (final tag in tags) {
    if (isFolderPrimaryDiscoveryTag(tag)) {
      primaryByName[tag.name] = tag;
      if (tag.displayName != null) {
        primaryByName[tag.displayName!] = tag;
      }
    }
  }

  final grouped = <String, List<TagItem>>{};
  for (final tag in tags) {
    if (!isFolderChildDiscoveryTag(tag)) {
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

/** 返回严格属于当前一级标签的二级标签，不做跨父级回退。 */
List<TagItem> strictChildItemsForParent(
  TagItem parent,
  Map<String, List<TagItem>> childItemsByParent,
) {
  return childItemsByParent[parent.id] ?? const <TagItem>[];
}

/** 一级标签展开时隐藏虚拟“默认专辑”，保留真实二级目录。 */
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

/** 同名二级标签冲突时返回父级路径标签。 */
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

/** 判断归一化后的二级标签名是否出现在多个父级下。 */
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
 * 一级标签只能来自本地媒体库 root 下第一层目录；历史数据里错误写入该组的二级或
 * manual 标签会在展示层被过滤，避免破坏文件树层级。
 */
bool isFolderPrimaryDiscoveryTag(TagItem tag) {
  return tag.source == TagSource.folder &&
      tag.groupId == 'folder.primary' &&
      tag.parentId == null &&
      tag.id.startsWith('folder.primary:');
}

/**
 * 判断标签是否可作为右侧发现面板的二级文件夹标签。
 *
 * 二级标签必须有父级一级目录，且只在所属一级展开卡或二级标签页中展示。
 */
bool isFolderChildDiscoveryTag(TagItem tag) {
  final parentId = tag.parentId?.trim();
  return tag.source == TagSource.folder &&
      tag.groupId == 'folder.child' &&
      parentId != null &&
      parentId.isNotEmpty &&
      tag.id.startsWith('folder.child:');
}
