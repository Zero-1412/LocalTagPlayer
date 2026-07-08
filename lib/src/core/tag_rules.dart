part of '../app.dart';

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

  // Keep folder-derived tag rules in one place so scanning, filtering, and player queues stay consistent.
  static List<String> sortedChildTags(Iterable<String> tags) {
    final values = tags.where((tag) => tag.trim().isNotEmpty).toSet().toList()
      ..sort();
    if (values.remove(defaultAlbumTag)) {
      values.insert(0, defaultAlbumTag);
    }
    return values;
  }

  static bool matchesChildTag(VideoItem item, String parentTag, String childTag) {
    final children = item.childTags[parentTag];
    if (childTag == defaultAlbumTag) {
      return children == null || children.isEmpty || children.contains(defaultAlbumTag);
    }
    return children?.contains(childTag) ?? false;
  }

  static bool isVideoPath(String path) {
    return videoExtensions.contains(p.extension(path).toLowerCase());
  }

  static String normalizeRootPath(String path) {
    return p.normalize(path.trim());
  }

  // Windows paths are case-insensitive; keep display paths unchanged but compare with a stable key.
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
      (token) => haystack.contains(token) || tagItems.any((tag) => tag.matchesNameOrAlias(token)),
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
}
