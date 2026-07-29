// ignore_for_file: slash_for_doc_comments

import 'package:path/path.dart' as p;

import '../../core/tag_rules.dart';

export '../../features/library/domain/library_sorting.dart'
    show compareLibraryVideosForSort, sortedLibraryVideos;

/** 选择器或桌面拖放返回的单个本地实体。 */
typedef LibraryImportPath = ({String path, bool isDirectory});

/**
 * 把用户选择/拖入的文件和目录归并为最小媒体库 root 集合。
 *
 * 视频文件使用所在目录作为 root；已被现有 root 覆盖的项目只需要触发重新扫描，不重复加入
 * 侧栏。多个候选目录按最上层路径去重，避免一次拖入同目录多个文件造成重复全库扫描。
 */
List<String> libraryImportRoots({
  required Iterable<LibraryImportPath> imports,
  required Iterable<String> existingRoots,
}) {
  final normalizedExisting = existingRoots
      .map(TagRules.normalizeRootPath)
      .where((root) => root.isNotEmpty)
      .toList();
  final candidates = <String>[];
  final candidateKeys = <String>{};
  for (final item in imports) {
    final normalizedPath = p.normalize(item.path.trim());
    if (normalizedPath.isEmpty ||
        (!item.isDirectory && !TagRules.isVideoPath(normalizedPath))) {
      continue;
    }
    if (normalizedExisting
        .any((root) => TagRules.rootContainsFile(root, normalizedPath))) {
      continue;
    }
    final candidate = item.isDirectory
        ? TagRules.normalizeRootPath(normalizedPath)
        : TagRules.normalizeRootPath(p.dirname(normalizedPath));
    if (candidate.isNotEmpty &&
        candidateKeys.add(TagRules.pathKey(candidate))) {
      candidates.add(candidate);
    }
  }
  candidates.sort((a, b) => p.split(a).length.compareTo(p.split(b).length));
  final roots = <String>[];
  for (final candidate in candidates) {
    // 同批候选优先保留最上层 root，继续维护“root 下一层才是一级标签”的硬规则。
    if (roots.any((root) => TagRules.rootContainsFile(root, candidate))) {
      continue;
    }
    roots.add(candidate);
  }
  return List<String>.unmodifiable(roots);
}
