import '../../core/tag_rules.dart';

// ignore_for_file: slash_for_doc_comments

/** 按平台路径规则规范化并去重媒体库根目录。 */
List<String> dedupeLibraryRoots(Iterable<String> rawRoots) {
  final seen = <String>{};
  final roots = <String>[];
  for (final raw in rawRoots) {
    final root = TagRules.normalizeRootPath(raw);
    if (root.isNotEmpty && seen.add(TagRules.pathKey(root))) roots.add(root);
  }
  return roots;
}

/** 按大小写不敏感标签名规范化并去重。 */
List<String> dedupeLibraryTags(Iterable<String> rawTags) {
  final seen = <String>{};
  final tags = <String>[];
  for (final raw in rawTags) {
    final tag = TagRules.normalizeTag(raw);
    if (tag.isNotEmpty && seen.add(tag.toLowerCase())) tags.add(tag);
  }
  return tags;
}

/** 比较两个标签集合，不依赖迭代顺序。 */
bool libraryTagSetsEqual(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/** 比较父标签到子标签集合的完整映射。 */
bool libraryChildTagsEqual(
  Map<String, Set<String>> a,
  Map<String, Set<String>> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null || !libraryTagSetsEqual(entry.value, other)) return false;
  }
  return true;
}
