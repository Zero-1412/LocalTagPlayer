import '../../core/tag_rules.dart';
import '../../models/library_scan_models.dart';
import '../../models/video_item.dart';
import '../resources/resource_scheduler.dart';
import 'library_repository_context.dart';
import 'library_scan_coordinator.dart';
import 'library_store_access.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * LibraryStore 的 root、扫描和 relink 协调 owner。
 *
 * 该服务只维护扫描代次，不复制媒体索引；SQLite 写入仍通过 [LibraryStoreAccess] 的
 * persistence helper 与同一 context 完成。Store 因而只保留组合和兼容端口，不再拥有
 * root 生命周期、取消唤醒和扫描协调的业务分支。
 */
class LibraryStoreCoordinatorService {
  LibraryStoreCoordinatorService({
    required LibraryStoreAccess repository,
    required LibraryRepositoryContext context,
    ResourceScheduler? resourceScheduler,
  })  : _repository = repository,
        _context = context,
        _resourceScheduler = resourceScheduler;

  final LibraryStoreAccess _repository;
  final LibraryRepositoryContext _context;
  final ResourceScheduler? _resourceScheduler;
  var _scanGeneration = 0;

  int get scanGeneration => _scanGeneration;

  Future<int> addRootAndScan(String rootPath) async =>
      (await addRootAndScanWithChanges(rootPath)).addedCount;

  Future<LibraryScanCommitResult> addRootAndScanWithChanges(
    String rootPath, {
    LibraryScanProgressCallback? onProgress,
  }) =>
      addRootsAndScanWithChanges(<String>[rootPath], onProgress: onProgress);

  /** 批量规范化 root，只保存一次 metadata，再进入一轮 latest-only 扫描。 */
  Future<LibraryScanCommitResult> addRootsAndScanWithChanges(
    Iterable<String> rootPaths, {
    LibraryScanProgressCallback? onProgress,
  }) async {
    final normalizedRoots = <String>[];
    final pendingKeys = <String>{};
    for (final rootPath in rootPaths) {
      final normalizedRoot = TagRules.normalizeRootPath(rootPath);
      if (normalizedRoot.isEmpty) {
        continue;
      }
      if (pendingKeys.add(TagRules.pathKey(normalizedRoot))) {
        normalizedRoots.add(normalizedRoot);
      }
    }
    if (normalizedRoots.isEmpty) {
      return LibraryScanCommitResult.cancelled(_scanGeneration);
    }

    var metadataChanged = false;
    final existingKeys = _repository.roots.map(TagRules.pathKey).toSet();
    for (final normalizedRoot in normalizedRoots) {
      if (existingKeys.add(TagRules.pathKey(normalizedRoot))) {
        _repository.roots.add(normalizedRoot);
        metadataChanged = true;
      }
    }
    if (metadataChanged) {
      await _context.metadataPersistence.save(
        roots: _repository.roots,
        favoriteTags: _repository.favoriteTags,
      );
      _context.markDataChanged();
    }
    return scanWithChanges(onProgress: onProgress);
  }

  /**
   * 移除 root 只改变 active/detached 可见性，不删除稳定身份、标签、收藏或播放记录。
   */
  Future<List<VideoItem>> removeRoot(String rootPath) async {
    final normalizedRoot = TagRules.normalizeRootPath(rootPath);
    final rootKey = TagRules.pathKey(normalizedRoot);
    if (!_repository.roots.any((root) => TagRules.pathKey(root) == rootKey)) {
      return const <VideoItem>[];
    }
    await cancelActiveScan();
    final remainingRoots = <String>[
      for (final root in _repository.roots)
        if (TagRules.pathKey(root) != rootKey) root,
    ];
    final removedVideos = <VideoItem>[
      for (final item in _repository.videos.values)
        if (TagRules.rootContainsFile(normalizedRoot, item.path) &&
            !remainingRoots.any(
              (root) => TagRules.rootContainsFile(root, item.path),
            ))
          item,
    ];

    final batch = _repository.database.batch();
    _repository.metadataPersistence.saveInBatch(
      batch,
      roots: remainingRoots,
      favoriteTags: _repository.favoriteTags,
    );
    for (final item in removedVideos) {
      _repository.videoPersistence.markDetachedInBatch(batch, item.videoId, true);
    }
    await batch.commit(noResult: true);

    _repository.roots
      ..clear()
      ..addAll(remainingRoots);
    for (final item in removedVideos) {
      final pathKey = TagRules.pathKey(item.path);
      _repository.videos.remove(pathKey);
      _repository.detachedVideos[pathKey] = item;
    }
    _context.markDataChanged();
    return List<VideoItem>.unmodifiable(removedVideos);
  }

  Future<int> scan() async => (await scanWithChanges()).addedCount;

  /** 取消上一代后只允许当前 generation 进入扫描提交协调器。 */
  Future<LibraryScanCommitResult> scanWithChanges({
    LibraryScanProgressCallback? onProgress,
  }) async {
    final previousGeneration = _scanGeneration;
    if (previousGeneration > 0) {
      _repository.scanBackend.cancelGeneration(previousGeneration);
    }
    final generation = ++_scanGeneration;
    final result = await LibraryScanCoordinator(
      _repository,
      resourceScheduler: _resourceScheduler,
    ).scan(
      generationId: generation,
      onProgress: onProgress,
    );
    _context.markDataChanged();
    return result;
  }

  Future<void> setScanPaused(bool paused) =>
      _repository.scanBackend.setPaused(paused);

  /** 取消时推进代次并解除后端暂停，避免等待播放让渡的旧任务永久挂起。 */
  Future<void> cancelActiveScan() async {
    final generation = _scanGeneration;
    if (generation <= 0) {
      return;
    }
    _repository.scanBackend.cancelGeneration(generation);
    _scanGeneration++;
    await _repository.scanBackend.setPaused(false);
  }

  Future<void> relinkMissingVideo(VideoItem item, String newPath) async {
    await LibraryScanCoordinator(
      _repository,
      resourceScheduler: _resourceScheduler,
    ).relinkMissingVideo(item, newPath);
    _context.markDataChanged();
  }

  Future<Set<String>> relinkMissingVideosInBatch(
    Map<VideoItem, String> targets,
  ) async {
    final failed = await LibraryScanCoordinator(
      _repository,
      resourceScheduler: _resourceScheduler,
    ).relinkMissingVideosInBatch(targets);
    _context.markDataChanged();
    return failed;
  }
}
