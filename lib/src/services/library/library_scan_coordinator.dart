import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/tag_rules.dart';
import '../../models/data_backup_models.dart';
import '../../models/library_scan_models.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import 'library_collection_rules.dart';
import 'library_scan_service.dart';
import 'library_store_access.dart';
import 'library_tag_maintenance.dart';

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
  final LibraryStoreAccess _store;

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
    final batch = _store.database.batch();
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
    final batch = _store.database.batch();
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
  Future<LibraryScanCommitResult> scan({
    required int generationId,
    LibraryScanProgressCallback? onProgress,
  }) async {
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
    final scanDelta = await _store.scanBackend.scan(
      generationId: generationId,
      roots: List<String>.unmodifiable(_store.roots),
      knownMetadata: knownMetadata,
      onProgress: onProgress,
    );
    if (scanDelta.cancelled || generationId != _store.scanGeneration) {
      return LibraryScanCommitResult.cancelled(generationId);
    }
    final batch = _store.database.batch();
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
    for (final item in _store.detachedVideos.values) {
      final fingerprint = item.mediaFingerprint;
      if (fingerprint == null) {
        continue;
      }
      // detached 视频不再受旧 root 管理；新 root 中的唯一 fingerprint 可以认领原身份。
      (relocationCandidates[fingerprint] ??= <VideoItem>[]).add(item);
    }

    final changedEntries = scanDelta.changedEntries.toList(growable: false);
    onProgress?.call(LibraryScanProgress(
      generationId: generationId,
      phase: LibraryScanPhase.committing,
      processed: 0,
      discovered: scanDelta.seenPathKeys.length,
      total: changedEntries.length,
    ));
    for (var index = 0; index < changedEntries.length; index += 1) {
      final scanned = changedEntries[index];
      final videoKey = TagRules.pathKey(scanned.path);
      final activeExisting = _store.videos[videoKey];
      final detachedExisting = _store.detachedVideos[videoKey];
      final existing = activeExisting ?? detachedExisting;
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
          DataBackupRestoreRecord? backup;
          if (candidates.isEmpty &&
              scannedFingerprintCounts[scanned.mediaFingerprint] == 1) {
            final candidate = await _store.dataBackupService
                .findUniqueRestore(scanned.mediaFingerprint);
            if (candidate != null && !_containsVideoId(candidate.videoId)) {
              // 主库、扫描侧和备份侧同时唯一时才允许恢复，避免重复文件串档。
              backup = candidate;
            }
          }
          // 指纹任一侧不唯一时只建立新身份，不猜测恢复用户数据。
          final newItem = _insertNewScannedVideo(
            batch,
            scanned,
            videoKey,
            backup: backup,
          );
          changedById[newItem.videoId] = newItem;
          probeById[newItem.videoId] = newItem;
          added++;
        }
      } else {
        if (detachedExisting != null) {
          // 同一路径重新加入时直接恢复原 videoId，不要求再次依赖 fingerprint 猜测身份。
          _store.detachedVideos.remove(videoKey);
          _store.videos[videoKey] = detachedExisting;
        }
        final contentChanged = _mergeExistingScannedVideo(
          batch,
          existing,
          scanned,
          forcePersist: detachedExisting != null,
        );
        changedById[existing.videoId] = existing;
        if (contentChanged) {
          probeById[existing.videoId] = existing;
        }
        modified++;
      }
      final processed = index + 1;
      if (processed == changedEntries.length || processed % 256 == 0) {
        onProgress?.call(LibraryScanProgress(
          generationId: generationId,
          phase: LibraryScanPhase.committing,
          processed: processed,
          discovered: scanDelta.seenPathKeys.length,
          total: changedEntries.length,
        ));
        // 大差量合并不能连续独占 UI isolate；让路由、进度和播放输入获得调度机会。
        await Future<void>.delayed(Duration.zero);
        if (generationId != _store.scanGeneration) {
          return LibraryScanCommitResult.cancelled(generationId);
        }
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
    _store.metadataPersistence.saveInBatch(
      batch,
      roots: _store.roots,
      favoriteTags: _store.favoriteTags,
    );
    await batch.commit(noResult: true);
    await _store.dataBackupService.enqueueVideos(changedById.keys);
    onProgress?.call(LibraryScanProgress(
      generationId: generationId,
      phase: LibraryScanPhase.committing,
      processed: changedEntries.length,
      discovered: scanDelta.seenPathKeys.length,
      total: changedEntries.length,
    ));
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
    String videoKey, {
    DataBackupRestoreRecord? backup,
  }) {
    final item = VideoItem(
      videoId: backup?.videoId,
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
      isFavorite: backup?.isFavorite ?? false,
      lastPlayedAt: backup?.lastPlayedAt,
      playbackPosition: backup?.playbackPosition ?? Duration.zero,
      playbackDuration: backup?.playbackDuration ?? Duration.zero,
      playbackCompleted: backup?.playbackCompleted ?? false,
      playbackPositionUpdatedAt: backup?.playbackPositionUpdatedAt,
    );
    _store.videos[videoKey] = item;
    _store.videoPersistence.insertInBatch(batch, item);
    LibraryTagMaintenance(_store).syncFolderTagsInBatch(batch, item);
    if (backup != null) {
      _restoreBackedUpTagLinks(batch, item, backup.links);
    }
    return item;
  }

  /** 主库已有同 videoId 时拒绝备份恢复，避免覆盖另一个稳定身份。 */
  bool _containsVideoId(String videoId) =>
      _store.videos.values.any((item) => item.videoId == videoId) ||
      _store.detachedVideos.values.any((item) => item.videoId == videoId);

  /** 在扫描事务内恢复非 folder 标签定义、分组和关联。 */
  void _restoreBackedUpTagLinks(
    Batch batch,
    VideoItem item,
    Iterable<DataBackupTagLink> links,
  ) {
    for (final link in links) {
      final group = link.group;
      if (group != null &&
          !_store.tagGroups.any((existing) => existing.id == group.id)) {
        batch.insert(
          'tag_groups',
          <String, Object?>{
            'id': group.id,
            'name': group.name,
            'display_name': group.displayName,
            'sort_order': group.sortOrder,
            'allow_multi_select': group.allowMultiSelect ? 1 : 0,
            'default_logic': group.defaultLogic.name,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        _store.tagGroups.add(group);
      }
      final tag = _store.tagsById[link.tag.id] ?? link.tag;
      _store.tagsById.putIfAbsent(tag.id, () => tag);
      _store.tagPersistence.attachTagInBatch(
        batch,
        item,
        tag,
        source: link.source,
        locked: link.locked,
      );
    }
  }

  /**
   * 合并已有视频的扫描结果。
   *
   * 只刷新扫描派生字段；收藏、播放时间、手动标签、媒体详情等用户或缓存数据保持原样。
   */
  bool _mergeExistingScannedVideo(
      Batch batch, VideoItem existing, LibraryScannedVideo scanned,
      {bool forcePersist = false}) {
    final tagsChanged = !libraryTagSetsEqual(existing.tags, scanned.tags);
    final childTagsChanged =
        !libraryChildTagsEqual(existing.childTags, scanned.childTags);
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
    if (forcePersist || tagsChanged || childTagsChanged || indexChanged) {
      _store.videoPersistence.insertInBatch(batch, existing);
      if (tagsChanged || childTagsChanged) {
        LibraryTagMaintenance(_store).syncFolderTagsInBatch(batch, existing);
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
    _store.detachedVideos.remove(oldKey);
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
    _store.videoPersistence.relinkInBatch(batch, oldPath, existing);
    _store.tagPersistence.relinkVideoPathInBatch(batch, existing);
    LibraryTagMaintenance(_store).syncFolderTagsInBatch(batch, existing);
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
      _store.videoPersistence.insertInBatch(batch, item);
      changed.add(item);
    }
    return changed;
  }
}
