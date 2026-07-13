part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * Application 层提交扫描差量后的不可变结果。
 *
 * [changedVideos] 供 UI 做差量失效，[probeCandidates] 只包含新增或内容变化的视频；
 * 两者都引用提交成功后的稳定 `VideoItem`，不会包含已取消代次的部分结果。
 */
class LibraryScanCommitResult {
  LibraryScanCommitResult({
    required this.generationId,
    required this.addedCount,
    required this.modifiedCount,
    required this.missingCount,
    required this.relinkedCount,
    required Iterable<VideoItem> changedVideos,
    required Iterable<VideoItem> probeCandidates,
    this.cancelled = false,
  })  : changedVideos = List<VideoItem>.unmodifiable(changedVideos),
        probeCandidates = List<VideoItem>.unmodifiable(probeCandidates);

  /** 扫描代次。 */
  final int generationId;

  /** 新建稳定记录数量。 */
  final int addedCount;

  /** 已有路径内容或索引发生变化的数量。 */
  final int modifiedCount;

  /** 本轮新标记为 missing 的数量。 */
  final int missingCount;

  /** 通过唯一 fingerprint 保留稳定身份的移动数量。 */
  final int relinkedCount;

  /** 事务提交后需要刷新 UI 的稳定对象。 */
  final List<VideoItem> changedVideos;

  /** 只允许送入缩略图或 MediaProbe 队列的新增/内容变化对象。 */
  final List<VideoItem> probeCandidates;

  /** 代次是否在提交前取消。 */
  final bool cancelled;

  /** 创建不产生任何数据库或 UI 副作用的取消结果。 */
  factory LibraryScanCommitResult.cancelled(int generationId) =>
      LibraryScanCommitResult(
        generationId: generationId,
        addedCount: 0,
        modifiedCount: 0,
        missingCount: 0,
        relinkedCount: 0,
        changedVideos: const <VideoItem>[],
        probeCandidates: const <VideoItem>[],
        cancelled: true,
      );
}

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
   * 将用户选择的新文件重新关联到一个 missing 条目。
   *
   * 只有新旧 fingerprint 完全一致且目标路径未被其它条目占用时才写入，避免手动误选造成
   * manual 标签、收藏和播放记录串档；folder 标签按新位置重新派生。
   */
  Future<void> relinkMissingVideo(VideoItem missing, String newPath) async {
    if (!missing.isMissing) {
      throw StateError('只能重新关联具有稳定身份的缺失视频');
    }
    final newKey = TagRules.pathKey(newPath);
    final occupied = _store.videos[newKey];
    if (occupied != null && !identical(occupied, missing)) {
      throw StateError('所选文件已经存在于媒体库');
    }
    final normalizedPath = p.normalize(newPath);
    final root = _rootForRelinkPath(normalizedPath);
    final scanned = await const LibraryScanService().inspectVideo(
      path: normalizedPath,
      root: root,
    );
    if (scanned == null) {
      throw StateError('所选路径不是可读取的视频文件');
    }
    if (missing.mediaFingerprint == null ||
        missing.mediaFingerprint != scanned.mediaFingerprint) {
      throw StateError('文件指纹不一致，已拒绝重新关联以避免串档');
    }
    final batch = _store._db.batch();
    _relinkScannedVideo(batch, missing, scanned, newKey);
    await batch.commit(noResult: true);
  }

  /**
   * 在一个 SQLite batch 中提交多条已预览 Relink。
   *
   * 返回执行前重新校验失败的 videoId；可提交项要么全部落库，要么在 batch 异常时全部回滚。
   */
  Future<Set<String>> relinkMissingVideosInBatch(
    Map<VideoItem, String> targets,
  ) async {
    final failedVideoIds = <String>{};
    final prepared = <({
      VideoItem original,
      VideoItem clone,
      LibraryScannedVideo scanned,
    })>[];
    final reservedNewKeys = <String>{};
    for (final entry in targets.entries) {
      final item = entry.key;
      final newPath = p.normalize(entry.value);
      final newKey = TagRules.pathKey(newPath);
      final occupied = _store.videos[newKey];
      if (!item.isMissing ||
          (occupied != null && !identical(occupied, item)) ||
          !reservedNewKeys.add(newKey)) {
        failedVideoIds.add(item.videoId);
        continue;
      }
      final root = _rootForRelinkPath(newPath);
      final scanned = await const LibraryScanService().inspectVideo(
        path: newPath,
        root: root,
      );
      if (scanned == null ||
          item.mediaFingerprint == null ||
          item.mediaFingerprint != scanned.mediaFingerprint) {
        failedVideoIds.add(item.videoId);
        continue;
      }
      prepared.add((
        original: item,
        clone: VideoItem.fromJson(item.toJson()),
        scanned: scanned,
      ));
    }
    if (prepared.isEmpty) {
      return failedVideoIds;
    }

    final videosSnapshot = Map<String, VideoItem>.of(_store.videos);
    final tagIdsSnapshot = {
      for (final entry in _store.videoTagIdsByPathKey.entries)
        entry.key: <String>{...entry.value},
    };
    final tagsSnapshot = Map<String, TagItem>.of(_store.tagsById);
    final batch = _store._db.batch();
    try {
      for (final target in prepared) {
        _relinkScannedVideo(
          batch,
          target.clone,
          target.scanned,
          TagRules.pathKey(target.scanned.path),
        );
      }
      await batch.commit(noResult: true);
    } catch (_) {
      _store.videos
        ..clear()
        ..addAll(videosSnapshot);
      _store.videoTagIdsByPathKey
        ..clear()
        ..addAll(tagIdsSnapshot);
      _store.tagsById
        ..clear()
        ..addAll(tagsSnapshot);
      failedVideoIds.addAll(prepared.map((target) => target.original.videoId));
    }
    return failedVideoIds;
  }

  /** 为新路径选择最具体的已配置 root；无匹配时使用文件所在目录。 */
  String _rootForRelinkPath(String normalizedPath) {
    final matchingRoots = _store.roots.where((root) {
      final comparableRoot = Platform.isWindows ? root.toLowerCase() : root;
      final comparablePath =
          Platform.isWindows ? normalizedPath.toLowerCase() : normalizedPath;
      return TagRules.pathKey(root) == TagRules.pathKey(normalizedPath) ||
          p.isWithin(comparableRoot, comparablePath);
    }).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return matchingRoots.isEmpty
        ? p.dirname(normalizedPath)
        : matchingRoots.first;
  }

  /**
   * 扫描所有根目录，并把变化增量写入数据库。
   *
   * 返回新增视频数量；已有视频的索引刷新、缺失文件清理和 metadata 保存会在同一 batch 中提交。
   */
  Future<LibraryScanCommitResult> scan({required int generationId}) async {
    final knownMetadata = <String, LibraryScanKnownMetadata>{
      for (final item in _store.videos.values)
        TagRules.pathKey(item.path): LibraryScanKnownMetadata(
          fileSize: item.fileSize,
          modifiedMs: item.modifiedMs,
          mediaFingerprint: item.mediaFingerprint,
          rootPath: item.rootPath,
          relativePath: item.relativePath,
          isMissing: item.isMissing,
        ),
    };
    final scanDelta = await _store._scanBackend.scan(
      generationId: generationId,
      roots: List<String>.unmodifiable(_store.roots),
      knownMetadata: knownMetadata,
    );
    if (scanDelta.cancelled || generationId != _store._scanGeneration) {
      return LibraryScanCommitResult.cancelled(generationId);
    }
    final batch = _store._db.batch();
    var added = 0;
    var modified = 0;
    var relinked = 0;
    final changedById = <String, VideoItem>{};
    final probeById = <String, VideoItem>{};
    final scannedFingerprintCounts = <String, int>{};
    for (final scanned in scanDelta.changedEntries) {
      scannedFingerprintCounts.update(
        scanned.mediaFingerprint,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final relocationCandidates = <String, List<VideoItem>>{};
    for (final item in _store.videos.values) {
      final fingerprint = item.mediaFingerprint;
      if (fingerprint == null ||
          scanDelta.seenPathKeys.contains(TagRules.pathKey(item.path)) ||
          File(item.path).existsSync()) {
        continue;
      }
      (relocationCandidates[fingerprint] ??= <VideoItem>[]).add(item);
    }

    for (final scanned in scanDelta.changedEntries) {
      final videoKey = TagRules.pathKey(scanned.path);
      final existing = _store.videos[videoKey];
      if (existing == null) {
        final candidates = relocationCandidates[scanned.mediaFingerprint] ??
            const <VideoItem>[];
        if (candidates.length == 1 &&
            scannedFingerprintCounts[scanned.mediaFingerprint] == 1) {
          final relinkedItem = candidates.single;
          _relinkScannedVideo(batch, relinkedItem, scanned, videoKey);
          changedById[relinkedItem.videoId] = relinkedItem;
          relinked++;
          relocationCandidates.remove(scanned.mediaFingerprint);
        } else {
          // 指纹任一侧不唯一时拒绝自动认领，防止相同大小/时间戳文件串档。
          final newItem = _insertNewScannedVideo(batch, scanned, videoKey);
          changedById[newItem.videoId] = newItem;
          probeById[newItem.videoId] = newItem;
          added++;
        }
      } else {
        final contentChanged =
            _mergeExistingScannedVideo(batch, existing, scanned);
        changedById[existing.videoId] = existing;
        if (contentChanged) {
          probeById[existing.videoId] = existing;
        }
        modified++;
      }
    }

    final missingVideos = _markMissingVideos(
      batch,
      scanDelta.seenPathKeys,
      scanDelta.scannedRootKeys,
    );
    for (final item in missingVideos) {
      changedById[item.videoId] = item;
    }
    _store._metadataPersistence.saveInBatch(
      batch,
      roots: _store.roots,
      favoriteTags: _store.favoriteTags,
    );
    await batch.commit(noResult: true);
    return LibraryScanCommitResult(
      generationId: generationId,
      addedCount: added,
      modifiedCount: modified,
      missingCount: missingVideos.length,
      relinkedCount: relinked,
      changedVideos: changedById.values,
      probeCandidates: probeById.values,
    );
  }

  /**
   * 把新发现的视频加入内存索引、视频表和 folder 标签索引。
   */
  VideoItem _insertNewScannedVideo(
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
    return item;
  }

  /**
   * 合并已有视频的扫描结果。
   *
   * 只刷新扫描派生字段；收藏、播放时间、手动标签、媒体详情等用户或缓存数据保持原样。
   */
  bool _mergeExistingScannedVideo(
    Batch batch,
    VideoItem existing,
    LibraryScannedVideo scanned,
  ) {
    final tagsChanged = !LibraryStore._setEquals(existing.tags, scanned.tags);
    final childTagsChanged =
        !LibraryStore._childTagsEquals(existing.childTags, scanned.childTags);
    final fingerprintChanged = existing.mediaFingerprint != null &&
        existing.mediaFingerprint != scanned.mediaFingerprint;
    final contentChanged = existing.fileSize != scanned.fileSize ||
        existing.modifiedMs != scanned.modifiedMs ||
        (existing.mediaFingerprint?.startsWith('v2:') == true &&
            fingerprintChanged);
    final indexChanged = existing.rootPath != scanned.rootPath ||
        existing.relativePath != scanned.relativePath ||
        existing.fileSize != scanned.fileSize ||
        existing.modifiedMs != scanned.modifiedMs ||
        existing.mediaFingerprint != scanned.mediaFingerprint ||
        existing.isMissing;
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
    existing.isMissing = false;
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
    return contentChanged;
  }

  /** 用唯一 fingerprint 将新路径认领给旧 videoId，并保留全部用户数据。 */
  void _relinkScannedVideo(
    Batch batch,
    VideoItem existing,
    LibraryScannedVideo scanned,
    String newVideoKey,
  ) {
    final oldPath = existing.path;
    final oldKey = TagRules.pathKey(oldPath);
    final linkedTagIds = _store.videoTagIdsByPathKey.remove(oldKey);
    _store.videos.remove(oldKey);
    existing
      ..path = scanned.path
      ..title = scanned.title
      ..folder = scanned.folder
      ..rootPath = scanned.rootPath
      ..relativePath = scanned.relativePath
      ..fileSize = scanned.fileSize
      ..modifiedMs = scanned.modifiedMs
      ..mediaFingerprint = scanned.mediaFingerprint
      ..isMissing = false;
    existing.tags
      ..clear()
      ..addAll(scanned.tags);
    existing.childTags
      ..clear()
      ..addAll(scanned.childTags
          .map((key, value) => MapEntry(key, <String>{...value})));
    _store.videos[newVideoKey] = existing;
    if (linkedTagIds != null) {
      _store.videoTagIdsByPathKey[newVideoKey] = linkedTagIds;
    }
    _store._videoPersistence.relinkInBatch(batch, oldPath, existing);
    _store._tagPersistence.relinkVideoPathInBatch(batch, existing);
    _store._tagMaintenance.syncFolderTagsInBatch(batch, existing);
  }

  /**
   * 只为本轮成功枚举的 root 更新 missing 状态。
   *
   * 不可访问 root 不参与判断，防止临时掉盘把整库误标；记录、标签和播放数据始终保留。
   */
  List<VideoItem> _markMissingVideos(
    Batch batch,
    Set<String> seenPathKeys,
    Set<String> scannedRootKeys,
  ) {
    final changed = <VideoItem>[];
    for (final item in _store.videos.values) {
      final rootPath = item.rootPath;
      final rootWasScanned = rootPath != null &&
          scannedRootKeys.contains(TagRules.pathKey(rootPath));
      final shouldBeMissing = rootWasScanned &&
          !seenPathKeys.contains(TagRules.pathKey(item.path)) &&
          !File(item.path).existsSync();
      if (item.isMissing == shouldBeMissing) {
        continue;
      }
      item.isMissing = shouldBeMissing;
      _store._videoPersistence.insertInBatch(batch, item);
      changed.add(item);
    }
    return changed;
  }
}
