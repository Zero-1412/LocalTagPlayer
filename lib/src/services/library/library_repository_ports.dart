import 'dart:typed_data';

import '../../models/data_backup_models.dart';
import '../../models/library_scan_models.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../repositories/repository_interfaces.dart';

// ignore_for_file: slash_for_doc_comments, annotate_overrides

/**
 * LibraryStore 的查询能力适配器。
 *
 * 这是 Phase 3 的过渡性拆分：数据库、索引和事务仍由一个 Store/Context 拥有，
 * 但页面组合根拿到的只读对象不再同时暴露命令接口。后续查询编译器可以替换该
 * 适配器，而不改变页面和 [LibraryApplicationFacade] 的契约。
 */
class LibraryStoreQueryRepository implements LibraryQueryRepository {
  const LibraryStoreQueryRepository(this._source);

  final LibraryQueryRepository _source;

  @override
  List<String> get roots => _source.roots;
  @override
  Map<String, VideoItem> get videos => _source.videos;
  @override
  Map<String, VideoItem> get videosById => _source.videosById;
  @override
  List<String> get favoriteTags => _source.favoriteTags;
  @override
  List<TagGroup> get tagGroups => _source.tagGroups;
  @override
  Map<String, TagItem> get tagsById => _source.tagsById;
  @override
  Map<String, Set<String>> get videoTagIdsByPathKey =>
      _source.videoTagIdsByPathKey;
  @override
  Map<String, Set<String>> get videoTagIdsByVideoId =>
      _source.videoTagIdsByVideoId;
  @override
  TagQueryContext get tagQueryContext => _source.tagQueryContext;
  @override
  Iterable<TagItem> get allTagItems => _source.allTagItems;
  @override
  Set<String> get allTags => _source.allTags;
  @override
  Map<String, int> resultCounts(FilterQuery query) =>
      _source.resultCounts(query);
  @override
  Future<Map<String, TagUsageSummary>> tagUsageSummaries() =>
      _source.tagUsageSummaries();
  @override
  Future<int> countTagReferences(TagItem tag) =>
      _source.countTagReferences(tag);
  @override
  DataBackupStatus get dataBackupStatus => _source.dataBackupStatus;
  @override
  Stream<DataBackupStatus> get dataBackupStatusStream =>
      _source.dataBackupStatusStream;
  @override
  Future<DataBackupIntegrityReport> checkDataBackupIntegrity() =>
      _source.checkDataBackupIntegrity();
  @override
  Future<Uint8List> createDataBackupExport() =>
      _source.createDataBackupExport();
  @override
  Future<int> countUntrackedVideos() => _source.countUntrackedVideos();
  @override
  Set<String> childTagsFor(String parentTag) => _source.childTagsFor(parentTag);
}

/**
 * LibraryStore 的命令能力适配器。
 *
 * 命令仍由 Store 的统一事务边界实现；这个对象只负责能力隔离，不复制内存状态，
 * 因而不会产生第二套 videoId/path 索引或改变既有事务顺序。
 */
class LibraryStoreCommandRepository implements LibraryCommandRepository {
  const LibraryStoreCommandRepository(this._source);

  final LibraryCommandRepository _source;

  @override
  Future<void> replaceManualTags(
    VideoItem item, {
    String? parentTag,
    Iterable<String>? manualTags,
  }) =>
      _source.replaceManualTags(
        item,
        parentTag: parentTag,
        manualTags: manualTags,
      );
  @override
  Future<TagItem> createManualTag({
    required String name,
    required String groupId,
    String? displayName,
  }) =>
      _source.createManualTag(
        name: name,
        groupId: groupId,
        displayName: displayName,
      );
  @override
  Future<void> updateTagDetails(
    TagItem tag, {
    String? displayName,
    Iterable<String>? aliases,
    String? groupId,
    bool? isHidden,
    bool? isFavorite,
    int? sortOrder,
  }) =>
      _source.updateTagDetails(
        tag,
        displayName: displayName,
        aliases: aliases,
        groupId: groupId,
        isHidden: isHidden,
        isFavorite: isFavorite,
        sortOrder: sortOrder,
      );
  @override
  Future<int> batchAddManualTag(TagItem tag, Iterable<VideoItem> items) =>
      _source.batchAddManualTag(tag, items);
  @override
  Future<int> batchRemoveManualTag(TagItem tag, Iterable<VideoItem> items) =>
      _source.batchRemoveManualTag(tag, items);
  @override
  Future<void> saveMetadata() => _source.saveMetadata();
  @override
  Future<void> addFavoriteTag(String tag) => _source.addFavoriteTag(tag);
  @override
  Future<void> removeFavoriteTag(String tag) => _source.removeFavoriteTag(tag);
  @override
  Future<void> upsertVideo(VideoItem item) => _source.upsertVideo(item);
  @override
  Future<void> upsertVideos(Iterable<VideoItem> items) =>
      _source.upsertVideos(items);
  @override
  Future<void> upsertPlaybackStates(Iterable<VideoItem> items) =>
      _source.upsertPlaybackStates(items);
  @override
  Future<VideoItem?> deleteVideo(String path) => _source.deleteVideo(path);
  @override
  Future<VideoItem?> deleteVideoById(String videoId) =>
      _source.deleteVideoById(videoId);
  @override
  Future<VideoItem?> deleteVideoAndMergeUserData({
    required VideoItem source,
    required VideoItem target,
  }) =>
      _source.deleteVideoAndMergeUserData(source: source, target: target);
  @override
  Future<VideoItem?> deleteVideoAndMergeUserDataById({
    required String sourceVideoId,
    required String targetVideoId,
  }) =>
      _source.deleteVideoAndMergeUserDataById(
        sourceVideoId: sourceVideoId,
        targetVideoId: targetVideoId,
      );
  @override
  Future<int> removeMissingOrUnreadableVideos() =>
      _source.removeMissingOrUnreadableVideos();
  @override
  Future<LibraryScanCommitResult> addRootAndScanWithChanges(
    String rootPath, {
    LibraryScanProgressCallback? onProgress,
  }) =>
      _source.addRootAndScanWithChanges(rootPath, onProgress: onProgress);
  @override
  Future<LibraryScanCommitResult> addRootsAndScanWithChanges(
    Iterable<String> rootPaths, {
    LibraryScanProgressCallback? onProgress,
  }) =>
      _source.addRootsAndScanWithChanges(rootPaths, onProgress: onProgress);
  @override
  Future<List<VideoItem>> removeRoot(String rootPath) =>
      _source.removeRoot(rootPath);
  @override
  Future<LibraryScanCommitResult> scanWithChanges({
    LibraryScanProgressCallback? onProgress,
  }) =>
      _source.scanWithChanges(onProgress: onProgress);
  @override
  Future<void> setScanPaused(bool paused) => _source.setScanPaused(paused);
  @override
  Future<void> cancelActiveScan() => _source.cancelActiveScan();
  @override
  Future<void> setDataBackupEnabled(bool enabled) =>
      _source.setDataBackupEnabled(enabled);
  @override
  Future<void> runDataBackupNow() => _source.runDataBackupNow();
  @override
  Future<void> pauseDataBackupForPlayback() =>
      _source.pauseDataBackupForPlayback();
  @override
  void resumeDataBackupAfterPlayback() =>
      _source.resumeDataBackupAfterPlayback();
  @override
  Future<void> renameVideoPath(VideoItem item, String newPath) =>
      _source.renameVideoPath(item, newPath);
  @override
  Future<void> renameVideoPathById(String videoId, String newPath) =>
      _source.renameVideoPathById(videoId, newPath);
  @override
  Future<void> relinkMissingVideo(VideoItem item, String newPath) =>
      _source.relinkMissingVideo(item, newPath);
  @override
  Future<void> relinkMissingVideoById(String videoId, String newPath) =>
      _source.relinkMissingVideoById(videoId, newPath);
  @override
  Future<Set<String>> relinkMissingVideosInBatch(
    Map<VideoItem, String> targets,
  ) =>
      _source.relinkMissingVideosInBatch(targets);
  @override
  Future<void> replaceRoot(String oldRoot, String newRoot) =>
      _source.replaceRoot(oldRoot, newRoot);
  @override
  Future<void> close() => _source.close();
}
