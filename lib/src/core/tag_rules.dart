import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/platform_models.dart';
import '../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

class TagRules {
  const TagRules._();

  static const defaultAlbumTag = '\u9ed8\u8ba4\u4e13\u8f91';
  static const videoExtensions = {
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.wmv',
    '.flv',
    '.webm',
    '.m4v',
    '.ts',
  };

  // 文件夹派生标签规则集中在这里，保证扫描、筛选和播放器队列使用同一套语义。
  static List<String> sortedChildTags(Iterable<String> tags) {
    final values = tags.where((tag) => tag.trim().isNotEmpty).toSet().toList()
      ..sort();
    if (values.remove(defaultAlbumTag)) {
      values.insert(0, defaultAlbumTag);
    }
    return values;
  }

  static bool matchesChildTag(
      VideoItem item, String parentTag, String childTag) {
    final children = item.childTags[parentTag];
    if (childTag == defaultAlbumTag) {
      return children == null ||
          children.isEmpty ||
          children.contains(defaultAlbumTag);
    }
    return children?.contains(childTag) ?? false;
  }

  /**
   * 按当前媒体库 root 重新派生文件夹层级并匹配一级/二级标签。
   *
   * 扫描历史里可能存在 `X:\test-media` 与 `X:\test-media\鸣潮` 同时作为 root 的情况，旧记录会把
   * `尤诺` 当作一级；筛选时必须以当前最上层 root 重新计算，保证右侧 UI 和真实结果一致。
   */
  static bool matchesFolderPath(
    VideoItem item,
    Iterable<String> roots, {
    required String primaryTag,
    String? childTag,
  }) {
    final segments = relativeFolderSegmentsForBestRoot(
      item.path,
      roots: roots,
      fallbackRoot: item.rootPath,
    );
    if (segments.isEmpty || !sameTag(segments.first, primaryTag)) {
      return false;
    }
    if (childTag == null) {
      return true;
    }
    final derivedChild = segments.length > 1 ? segments[1] : defaultAlbumTag;
    return sameTag(derivedChild, childTag);
  }

  static bool isVideoPath(String path) {
    return videoExtensions.contains(p.extension(path).toLowerCase());
  }

  static String normalizeRootPath(String path) {
    return p.normalize(path.trim());
  }

  // Windows 路径比较不区分大小写；展示路径保持原样，比较时使用稳定 key。
  static String pathKey(String path) {
    final normalized = p.normalize(path.trim());
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static String normalizeTag(String tag) {
    return tag.trim();
  }

  static bool sameTag(String a, String b) {
    return a.trim().toLowerCase() == b.trim().toLowerCase();
  }

  static bool matchesSearch(
    VideoItem item,
    String rawQuery, {
    Iterable<TagItem> tagItems = const <TagItem>[],
  }) {
    final tokens = rawQuery
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      return true;
    }
    final childTags = item.childTags.entries
        .expand((entry) => <String>[entry.key, ...entry.value]);
    final haystack = <String>[
      item.title,
      p.basename(item.path),
      item.path,
      item.relativePath ?? '',
      item.folder,
      ...item.tags,
      ...childTags,
      for (final tag in tagItems) ...<String>[
        tag.id,
        tag.name,
        tag.displayName ?? '',
        ...tag.aliases,
      ],
    ].join('\n').toLowerCase();
    return tokens.every(
      (token) =>
          haystack.contains(token) ||
          tagItems.any((tag) => tag.matchesNameOrAlias(token)),
    );
  }

  static Set<String> parentTagsFor(String root, String filePath) {
    final segments = relativeFolderSegments(root, filePath);
    if (segments.isEmpty) {
      return <String>{};
    }
    return <String>{segments.first};
  }

  static Map<String, Set<String>> childTagsFor(String root, String filePath) {
    final segments = relativeFolderSegments(root, filePath);
    if (segments.isEmpty) {
      return const <String, Set<String>>{};
    }
    final child = segments.length > 1 ? segments[1] : defaultAlbumTag;
    return <String, Set<String>>{
      segments.first: <String>{child},
    };
  }

  /**
   * 使用命中文件的最上层媒体库 root 计算相对文件夹层级。
   *
   * 多 root 命中时选路径段最少的 root，避免子 root 把原本的二级目录提升成一级标签。
   */
  static List<String> relativeFolderSegmentsForBestRoot(
    String filePath, {
    required Iterable<String> roots,
    String? fallbackRoot,
  }) {
    final root = bestRootForFilePath(
      filePath,
      roots: roots,
      fallbackRoot: fallbackRoot,
    );
    return root == null
        ? const <String>[]
        : relativeFolderSegments(root, filePath);
  }

  /**
   * 查找包含文件的最上层媒体库 root。
   */
  static String? bestRootForFilePath(
    String filePath, {
    required Iterable<String> roots,
    String? fallbackRoot,
  }) {
    final candidates = <String>[
      for (final root in roots)
        if (rootContainsFile(root, filePath)) normalizeRootPath(root),
    ];
    if (candidates.isEmpty) {
      final fallback = fallbackRoot?.trim();
      return fallback == null || fallback.isEmpty
          ? null
          : normalizeRootPath(fallback);
    }
    candidates.sort((a, b) => p.split(a).length.compareTo(p.split(b).length));
    return candidates.first;
  }

  /**
   * 判断 root 是否包含 filePath，并避免简单 startsWith 误匹配相似路径前缀。
   */
  static bool rootContainsFile(String root, String filePath) {
    final normalizedRoot = normalizeRootPath(root);
    final normalizedFile = p.normalize(filePath);
    return pathKey(normalizedFile) == pathKey(normalizedRoot) ||
        p.isWithin(normalizedRoot, normalizedFile);
  }

  static List<String> relativeFolderSegments(String root, String filePath) {
    final relativeFolder = p.relative(p.dirname(filePath), from: root);
    if (relativeFolder == '.' || relativeFolder.trim().isEmpty) {
      return const <String>[];
    }
    return p
        .split(relativeFolder)
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList();
  }

  /**
   * 生成稳定的规范化 tagId。
   *
   * 展示层、标签维护和 Repository 必须共享同一算法，避免页面依赖具体 Store 的
   * 私有实现；不同父级下同名二级 folder 标签通过 [parentId] 保持隔离。
   */
  static String tagIdFor({
    required String name,
    required String groupId,
    String? parentId,
  }) {
    final parent = parentId == null ? '' : ':${parentId.trim().toLowerCase()}';
    return '$groupId$parent:${name.trim().toLowerCase()}';
  }
}
