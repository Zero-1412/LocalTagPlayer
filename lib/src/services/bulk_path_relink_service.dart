part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/** 批量路径替换预览中的安全分类。 */
enum BulkRelinkStatus {
  ready,
  targetMissing,
  pathConflict,
  fingerprintMismatch
}

/** 单个 missing 条目的旧路径、新路径和只读校验结果。 */
class BulkPathRelinkPreview {
  const BulkPathRelinkPreview({
    required this.item,
    required this.newPath,
    required this.status,
  });

  final VideoItem item;
  final String newPath;
  final BulkRelinkStatus status;
}

/**
 * 批量路径前缀替换服务。
 *
 * 预览阶段只读取目标文件和 fingerprint，不修改数据库；执行阶段仍逐条复用安全 relink 事务，
 * 因此路径占用、指纹不符或目标缺失都不会静默覆盖用户数据。
 */
class BulkPathRelinkService {
  const BulkPathRelinkService();

  /** 构建仅包含 oldPrefix 下 missing 条目的安全预览。 */
  Future<List<BulkPathRelinkPreview>> preview({
    required LibraryStore store,
    required String oldPrefix,
    required String newPrefix,
  }) async {
    final rawOldRoot = oldPrefix.trim();
    final rawNewRoot = newPrefix.trim();
    if (rawOldRoot.isEmpty || rawNewRoot.isEmpty) {
      return const <BulkPathRelinkPreview>[];
    }
    final oldRoot = p.normalize(rawOldRoot);
    final newRoot = p.normalize(rawNewRoot);
    final previews = <BulkPathRelinkPreview>[];
    for (final item in store.videos.values.where((video) => video.isMissing)) {
      if (!_isWithinOrEqual(oldRoot, item.path)) {
        continue;
      }
      final relative = p.relative(item.path, from: oldRoot);
      final newPath = p.normalize(p.join(newRoot, relative));
      final occupied = store.videos[TagRules.pathKey(newPath)];
      if (occupied != null && !identical(occupied, item)) {
        previews.add(BulkPathRelinkPreview(
          item: item,
          newPath: newPath,
          status: BulkRelinkStatus.pathConflict,
        ));
        continue;
      }
      if (!await File(newPath).exists()) {
        previews.add(BulkPathRelinkPreview(
          item: item,
          newPath: newPath,
          status: BulkRelinkStatus.targetMissing,
        ));
        continue;
      }
      final fingerprint = await LibraryStore.mediaFingerprintFor(newPath);
      previews.add(BulkPathRelinkPreview(
        item: item,
        newPath: newPath,
        status: fingerprint != null && fingerprint == item.mediaFingerprint
            ? BulkRelinkStatus.ready
            : BulkRelinkStatus.fingerprintMismatch,
      ));
    }
    return previews;
  }

  /** 执行预览中仍标记 ready 的条目，并返回成功数量。 */
  Future<int> execute({
    required LibraryStore store,
    required Iterable<BulkPathRelinkPreview> previews,
    required String oldPrefix,
    required String newPrefix,
  }) async {
    var updated = 0;
    for (final preview in previews) {
      if (preview.status != BulkRelinkStatus.ready) {
        continue;
      }
      try {
        // 执行时再次走单条校验；预览后发生的文件变化只跳过该条，不中断其它安全项。
        await store.relinkMissingVideo(preview.item, preview.newPath);
        updated++;
      } catch (_) {
        continue;
      }
    }
    final oldKey = TagRules.pathKey(TagRules.normalizeRootPath(oldPrefix));
    final normalizedNewRoot = TagRules.normalizeRootPath(newPrefix);
    final rootIndex = store.roots.indexWhere(
      (root) => TagRules.pathKey(root) == oldKey,
    );
    if (updated > 0 && rootIndex >= 0 && normalizedNewRoot.isNotEmpty) {
      // 仅精确匹配已配置 root 时同步迁移扫描入口；子目录前缀替换不改变 root 配置。
      store.roots[rootIndex] = normalizedNewRoot;
      await store.saveMetadata();
    }
    return updated;
  }

  /** Windows 使用大小写不敏感比较，其它平台遵循原生路径大小写。 */
  bool _isWithinOrEqual(String root, String candidate) {
    final comparableRoot = Platform.isWindows ? root.toLowerCase() : root;
    final comparableCandidate =
        Platform.isWindows ? candidate.toLowerCase() : candidate;
    return TagRules.pathKey(root) == TagRules.pathKey(candidate) ||
        p.isWithin(comparableRoot, comparableCandidate);
  }
}
