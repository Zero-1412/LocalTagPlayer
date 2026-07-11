part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 单次媒体库扫描发现的视频条目。
 *
 * 该对象只描述文件系统发现结果，不负责写 SQLite，也不决定标签索引如何同步。
 */
class LibraryScannedVideo {
  const LibraryScannedVideo({
    required this.path,
    required this.title,
    required this.folder,
    required this.rootPath,
    required this.relativePath,
    required this.tags,
    required this.childTags,
    required this.fileSize,
    required this.modifiedMs,
    required this.mediaFingerprint,
  });

  /** 视频文件的当前绝对路径。 */
  final String path;

  /** 由文件名派生的展示标题。 */
  final String title;

  /** 视频所在目录，用于兼容旧的列表展示字段。 */
  final String folder;

  /** 命中的媒体库根目录。 */
  final String rootPath;

  /** 视频相对根目录的路径，用于后续 stable identity / relink。 */
  final String relativePath;

  /** 从根目录第一层派生的 folder 来源一级标签。 */
  final Set<String> tags;

  /** 从根目录第二层派生的 folder 来源二级标签。 */
  final Map<String, Set<String>> childTags;

  /** 文件大小，参与稳定内容指纹并用于增量缓存判断。 */
  final int fileSize;

  /** 文件修改时间毫秒值，仅用于变更检测，不作为稳定身份本身。 */
  final int modifiedMs;

  /** 基于大小与首尾小样本内容生成、与路径和修改时间无关的媒体指纹。 */
  final String mediaFingerprint;
}

/**
 * 一次扫描的完整结果。
 *
 * `seenPathKeys` 包含本轮能枚举到的视频路径 key，即使 stat 失败也保留，
 * 避免临时文件系统异常导致已有记录被误判为应删除。
 */
class LibraryScanResult {
  const LibraryScanResult({
    required this.entries,
    required this.seenPathKeys,
    required this.scannedRootKeys,
  });

  /** 可安全写入媒体库的视频扫描条目。 */
  final List<LibraryScannedVideo> entries;

  /** 本轮扫描见过的视频路径 key。 */
  final Set<String> seenPathKeys;

  /** 本轮确认可访问并完成枚举的根目录，用于安全标记 missing。 */
  final Set<String> scannedRootKeys;
}

/**
 * 媒体库文件系统扫描服务。
 *
 * 该服务只负责遍历目录、识别视频文件、读取 stat、派生 folder 标签和轻量指纹；
 * 它不接触 SQLite，不修改 `VideoItem`，也不处理 manual 标签维护。
 */
class LibraryScanService {
  const LibraryScanService();

  /**
   * 扫描多个媒体库根目录，返回文件系统发现结果。
   *
   * 不存在或不可访问的目录会被跳过，单个目录的 `FileSystemException` 不会中断其它 root。
   */
  Future<LibraryScanResult> scanRoots(List<String> roots) async {
    final entries = <LibraryScannedVideo>[];
    final seen = <String>{};
    final scannedRootKeys = <String>{};
    for (final root in roots) {
      final dir = Directory(root);
      if (!await _directoryExists(dir)) {
        continue;
      }
      try {
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File || !TagRules.isVideoPath(entity.path)) {
            continue;
          }
          final videoKey = TagRules.pathKey(entity.path);
          seen.add(videoKey);
          final stat = await _fileStat(entity);
          if (stat == null || stat.type != FileSystemEntityType.file) {
            continue;
          }
          entries.add(await _entryFor(root: root, file: entity, stat: stat));
        }
        scannedRootKeys.add(TagRules.pathKey(root));
      } on FileSystemException {
        continue;
      }
    }
    return LibraryScanResult(
      entries: entries,
      seenPathKeys: seen,
      scannedRootKeys: scannedRootKeys,
    );
  }

  /**
   * 统计磁盘中尚未写入媒体库索引的视频数量。
   */
  Future<int> countUntrackedVideos(
    List<String> roots,
    Set<String> trackedPathKeys,
  ) async {
    var count = 0;
    for (final root in roots) {
      final dir = Directory(root);
      if (!await _directoryExists(dir)) {
        continue;
      }
      try {
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File || !TagRules.isVideoPath(entity.path)) {
            continue;
          }
          if (!trackedPathKeys.contains(TagRules.pathKey(entity.path))) {
            count++;
          }
        }
      } on FileSystemException {
        continue;
      }
    }
    return count;
  }

  /**
   * 读取单个路径当前轻量媒体指纹。
   */
  static Future<String?> mediaFingerprintFor(String path) async {
    try {
      final file = File(path);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        return null;
      }
      return _mediaFingerprintForFile(file, stat);
    } catch (_) {
      return null;
    }
  }

  /**
   * 读取首尾各 4KB 生成轻量内容指纹。
   *
   * 自动 relink 仍要求两侧唯一，因此小样本碰撞只会拒绝自动合并，不会静默串档。
   */
  static Future<String> _mediaFingerprintForFile(
    File file,
    FileStat stat,
  ) async {
    const sampleSize = 4096;
    final handle = await file.open();
    try {
      final first = await handle.read(math.min(sampleSize, stat.size));
      final tailStart = math.max(first.length, stat.size - sampleSize);
      await handle.setPosition(tailStart);
      final last =
          await handle.read(math.min(sampleSize, stat.size - tailStart));
      var hash = 0xcbf29ce484222325;
      for (final byte in <int>[...first, ...last]) {
        hash ^= byte;
        hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
      }
      return 'v2:${stat.size}:${hash.toRadixString(16).padLeft(16, '0')}';
    } finally {
      await handle.close();
    }
  }

  Future<LibraryScannedVideo> _entryFor({
    required String root,
    required File file,
    required FileStat stat,
  }) async {
    return LibraryScannedVideo(
      path: file.path,
      title: p.basenameWithoutExtension(file.path),
      folder: p.dirname(file.path),
      rootPath: root,
      relativePath: p.relative(file.path, from: root),
      tags: TagRules.parentTagsFor(root, file.path),
      childTags: TagRules.childTagsFor(root, file.path),
      fileSize: stat.size,
      modifiedMs: stat.modified.millisecondsSinceEpoch,
      mediaFingerprint: await _mediaFingerprintForFile(file, stat),
    );
  }

  static Future<bool> _directoryExists(Directory directory) async {
    try {
      return await directory.exists();
    } catch (_) {
      return false;
    }
  }

  static Future<FileStat?> _fileStat(File file) async {
    try {
      return await file.stat();
    } catch (_) {
      return null;
    }
  }
}
