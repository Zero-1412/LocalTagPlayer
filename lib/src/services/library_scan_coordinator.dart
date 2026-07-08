part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库扫描状态协调器。
 *
 * 目录遍历由 `LibraryScanService` 负责；本类负责把扫描结果合并进 `LibraryStore`
 * 的内存状态、视频表、folder 标签索引和 metadata，不改变 folder/manual 标签语义。
 */
class LibraryScanCoordinator {
  /**
   * 创建一次围绕当前 store 的扫描协调器。
   *
   * [_store] 持有数据库连接、内存视频索引和标签索引，本类不拥有这些资源生命周期。
   */
  const LibraryScanCoordinator(this._store);

  /** 当前媒体库 store。 */
  final LibraryStore _store;

  /**
   * 扫描所有根目录，并把变化增量写入数据库。
   *
   * 返回新增视频数量；已有视频的索引刷新、缺失文件清理和 metadata 保存会在同一 batch 中提交。
   */
  Future<int> scan() async {
    final scanResult = await const LibraryScanService().scanRoots(_store.roots);
    final batch = _store._db.batch();
    var added = 0;

    for (final scanned in scanResult.entries) {
      final videoKey = TagRules.pathKey(scanned.path);
      final existing = _store.videos[videoKey];
      if (existing == null) {
        _insertNewScannedVideo(batch, scanned, videoKey);
        added++;
      } else {
        _mergeExistingScannedVideo(batch, existing, scanned);
      }
    }

    _removeMissingVideos(batch, scanResult.seenPathKeys);
    _store._metadataPersistence.saveInBatch(
      batch,
      roots: _store.roots,
      favoriteTags: _store.favoriteTags,
    );
    await batch.commit(noResult: true);
    return added;
  }

  /**
   * 把新发现的视频加入内存索引、视频表和 folder 标签索引。
   */
  void _insertNewScannedVideo(
    Batch batch,
    LibraryScannedVideo scanned,
    String videoKey,
  ) {
    final item = VideoItem(
      path: scanned.path,
      title: scanned.title,
      folder: scanned.folder,
      tags: scanned.tags,
      childTags: scanned.childTags,
      rootPath: scanned.rootPath,
      relativePath: scanned.relativePath,
      fileSize: scanned.fileSize,
      modifiedMs: scanned.modifiedMs,
      mediaFingerprint: scanned.mediaFingerprint,
      addedAt: DateTime.now(),
    );
    _store.videos[videoKey] = item;
    _store._videoPersistence.insertInBatch(batch, item);
    _store._tagMaintenance.syncFolderTagsInBatch(batch, item);
  }

  /**
   * 合并已有视频的扫描结果。
   *
   * 只刷新扫描派生字段；收藏、播放时间、手动标签、媒体详情等用户或缓存数据保持原样。
   */
  void _mergeExistingScannedVideo(
    Batch batch,
    VideoItem existing,
    LibraryScannedVideo scanned,
  ) {
    final tagsChanged = !LibraryStore._setEquals(existing.tags, scanned.tags);
    final childTagsChanged =
        !LibraryStore._childTagsEquals(existing.childTags, scanned.childTags);
    final contentChanged = existing.mediaFingerprint != null &&
        existing.mediaFingerprint != scanned.mediaFingerprint;
    final indexChanged = existing.rootPath != scanned.rootPath ||
        existing.relativePath != scanned.relativePath ||
        existing.fileSize != scanned.fileSize ||
        existing.modifiedMs != scanned.modifiedMs ||
        existing.mediaFingerprint != scanned.mediaFingerprint;
    existing.tags
      ..clear()
      ..addAll(scanned.tags);
    existing.childTags
      ..clear()
      ..addAll(scanned.childTags
          .map((key, value) => MapEntry(key, <String>{...value})));
    existing.rootPath = scanned.rootPath;
    existing.relativePath = scanned.relativePath;
    existing.fileSize = scanned.fileSize;
    existing.modifiedMs = scanned.modifiedMs;
    existing.mediaFingerprint = scanned.mediaFingerprint;
    if (contentChanged) {
      existing.mediaDetails = null;
      existing.mediaDetailsError = null;
      existing.thumbnailError = null;
    }
    if (tagsChanged || childTagsChanged || indexChanged) {
      _store._videoPersistence.insertInBatch(batch, existing);
      if (tagsChanged || childTagsChanged) {
        _store._tagMaintenance.syncFolderTagsInBatch(batch, existing);
      }
    }
  }

  /**
   * 清理扫描根目录内已经不存在的旧视频记录。
   *
   * 现阶段仍按旧行为删除不存在的记录；stable identity / missing-relink 阶段再改为 missing 标记。
   */
  void _removeMissingVideos(Batch batch, Set<String> seenPathKeys) {
    final removedPaths = <String>[];
    _store.videos.removeWhere((pathKey, item) {
      final shouldRemove =
          !seenPathKeys.contains(pathKey) && !File(item.path).existsSync();
      if (shouldRemove) {
        removedPaths.add(item.path);
      }
      return shouldRemove;
    });
    for (final path in removedPaths) {
      _store._tagPersistence.deleteVideoLinksInBatch(batch, path);
      _store._videoPersistence.deleteInBatch(batch, path);
    }
  }
}
