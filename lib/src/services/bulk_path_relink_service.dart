part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/** 批量路径替换预览中的安全分类。 */
enum BulkRelinkStatus {
  ready,
  targetMissing,
  pathConflict,
  fingerprintMismatch,
  executionFailed,
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

/** 一次批事务执行结果；失败 videoId 可用于后续定向重试。 */
class BulkRelinkExecutionResult {
  const BulkRelinkExecutionResult({
    required this.succeededCount,
    required this.failedVideoIds,
    this.rootUpdateFailed = false,
  });

  final int succeededCount;
  final Set<String> failedVideoIds;
  /** 视频批事务已成功，但扫描 root 元数据未能同步保存。 */
  final bool rootUpdateFailed;
}

/** 仅在内存中过滤已有预览，不访问 SQLite 或文件系统。 */
List<BulkPathRelinkPreview> filterBulkRelinkPreviews(
  Iterable<BulkPathRelinkPreview> previews,
  String query,
) {
  final keywords = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((keyword) => keyword.isNotEmpty)
      .toList();
  if (keywords.isEmpty) {
    return previews.toList();
  }
  return previews.where((preview) {
    final searchable = '${preview.item.title}\n${preview.item.path}\n'
            '${preview.newPath}\n${_bulkRelinkStatusAuditLabel(preview.status)}'
        .toLowerCase();
    return keywords.every(searchable.contains);
  }).toList();
}

/** 生成不包含本地路径和标题的可复制审计摘要。 */
String bulkRelinkAuditSummary(
  Iterable<BulkPathRelinkPreview> previews, {
  BulkRelinkExecutionResult? result,
}) {
  final values = previews.toList();
  int count(BulkRelinkStatus status) =>
      values.where((preview) => preview.status == status).length;
  return <String>[
    'Local Tag Player 批量 Relink 审计摘要',
    '预览总数: ${values.length}',
    '可更新: ${count(BulkRelinkStatus.ready)}',
    '目标不存在: ${count(BulkRelinkStatus.targetMissing)}',
    '路径冲突: ${count(BulkRelinkStatus.pathConflict)}',
    '指纹不一致: ${count(BulkRelinkStatus.fingerprintMismatch)}',
    '执行失败: ${result?.failedVideoIds.length ?? count(BulkRelinkStatus.executionFailed)}',
    '执行成功: ${result?.succeededCount ?? 0}',
    '扫描 root 更新: ${result?.rootUpdateFailed == true ? '失败' : '正常'}',
    '本地路径与文件标题: 已隐藏',
  ].join('\n');
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
  Future<BulkRelinkExecutionResult> execute({
    required LibraryStore store,
    required Iterable<BulkPathRelinkPreview> previews,
    required String oldPrefix,
    required String newPrefix,
  }) async {
    final ready = previews
        .where((preview) => preview.status == BulkRelinkStatus.ready)
        .toList();
    final failedVideoIds = await store.relinkMissingVideosInBatch({
      for (final preview in ready) preview.item: preview.newPath,
    });
    final updated = ready.length - failedVideoIds.length;
    final oldKey = TagRules.pathKey(TagRules.normalizeRootPath(oldPrefix));
    final normalizedNewRoot = TagRules.normalizeRootPath(newPrefix);
    final rootIndex = store.roots.indexWhere(
      (root) => TagRules.pathKey(root) == oldKey,
    );
    var rootUpdateFailed = false;
    if (updated > 0 && rootIndex >= 0 && normalizedNewRoot.isNotEmpty) {
      // 仅精确匹配已配置 root 时同步迁移扫描入口；子目录前缀替换不改变 root 配置。
      final previousRoot = store.roots[rootIndex];
      store.roots[rootIndex] = normalizedNewRoot;
      try {
        await store.saveMetadata();
      } catch (_) {
        store.roots[rootIndex] = previousRoot;
        rootUpdateFailed = true;
      }
    }
    return BulkRelinkExecutionResult(
      succeededCount: updated,
      failedVideoIds: failedVideoIds,
      rootUpdateFailed: rootUpdateFailed,
    );
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

String _bulkRelinkStatusAuditLabel(BulkRelinkStatus status) => switch (status) {
      BulkRelinkStatus.ready => '可更新',
      BulkRelinkStatus.targetMissing => '目标不存在',
      BulkRelinkStatus.pathConflict => '路径冲突',
      BulkRelinkStatus.fingerprintMismatch => '指纹不一致',
      BulkRelinkStatus.executionFailed => '执行失败',
    };
