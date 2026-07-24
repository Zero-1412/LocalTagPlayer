import 'dart:collection';
import 'dart:async';
import 'dart:typed_data';

import '../../models/library_scan_models.dart';
import '../../models/data_backup_models.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../repositories/repository_interfaces.dart';

// ignore_for_file: slash_for_doc_comments, annotate_overrides

/**
 * 媒体库页面使用的应用服务门面。
 *
 * 页面只通过该对象发起用例并读取不可替换的领域索引，不再知道 SQLite、扫描后端或
 * `LibraryStore` 的具体类型。标签筛选、stable identity 与 SQLite 单写仍留在 Dart
 * Repository 内部，不下沉到 Rust/C++。
 */
class LibraryApplicationFacade implements LibraryRelinkRepository {
  LibraryApplicationFacade({
    required LibraryRepository libraryRepository,
    required TagRepository tagRepository,
    required CacheRepository cacheRepository,
    required PlaybackRepository playbackRepository,
  })  : _repository = libraryRepository,
        _tagRepository = tagRepository,
        _cacheRepository = cacheRepository,
        _playbackRepository = playbackRepository,
        roots = UnmodifiableListView<String>(libraryRepository.roots),
        videos =
            UnmodifiableMapView<String, VideoItem>(libraryRepository.videos),
        favoriteTags =
            UnmodifiableListView<String>(libraryRepository.favoriteTags),
        tagGroups = UnmodifiableListView<TagGroup>(libraryRepository.tagGroups),
        tagsById =
            UnmodifiableMapView<String, TagItem>(libraryRepository.tagsById);

  /** 由组合根注入的 Dart Repository。 */
  final LibraryRepository _repository;
  final TagRepository _tagRepository;
  final CacheRepository _cacheRepository;
  final PlaybackRepository _playbackRepository;

  /** 反映 repository 最新内容、但禁止页面增删的 root 视图。 */
  final List<String> roots;
  /** 反映 repository 最新索引、但禁止页面替换条目的视频视图。 */
  final Map<String, VideoItem> videos;
  /** 只能通过明确命令修改的收藏标签视图。 */
  final List<String> favoriteTags;
  /** 禁止页面改写顺序或成员的标签组视图。 */
  final List<TagGroup> tagGroups;
  /** 禁止页面替换标签实体的 tagId 索引视图。 */
  final Map<String, TagItem> tagsById;

  /** 返回同时冻结外层索引和每个 tagId 集合的只读快照。 */
  Map<String, Set<String>> get videoTagIdsByPathKey => Map.unmodifiable(
        _repository.videoTagIdsByPathKey.map(
          (key, value) => MapEntry(key, Set<String>.unmodifiable(value)),
        ),
      );
  TagQueryContext get tagQueryContext => TagQueryContext(
        tagsById: tagsById,
        videoTagIdsByPathKey: videoTagIdsByPathKey,
      );
  Iterable<TagItem> get allTagItems => tagsById.values;
  Set<String> get allTags => Set<String>.unmodifiable(_repository.allTags);

  Map<String, int> resultCounts(FilterQuery query) =>
      _repository.resultCounts(query);

  Future<Map<String, TagUsageSummary>> tagUsageSummaries() =>
      _repository.tagUsageSummaries();

  Future<void> replaceManualTags(
    VideoItem item, {
    String? parentTag,
  }) =>
      _repository.replaceManualTags(item, parentTag: parentTag);

  Future<TagItem> createManualTag({
    required String name,
    required String groupId,
    String? displayName,
  }) =>
      _repository.createManualTag(
        name: name,
        groupId: groupId,
        displayName: displayName,
      );

  Future<void> updateTagDetails(
    TagItem tag, {
    String? displayName,
    Iterable<String>? aliases,
    String? groupId,
    bool? isHidden,
    bool? isFavorite,
    int? sortOrder,
  }) =>
      _repository.updateTagDetails(
        tag,
        displayName: displayName,
        aliases: aliases,
        groupId: groupId,
        isHidden: isHidden,
        isFavorite: isFavorite,
        sortOrder: sortOrder,
      );

  Future<int> countTagReferences(TagItem tag) =>
      _repository.countTagReferences(tag);

  Future<int> batchAddManualTag(TagItem tag, Iterable<VideoItem> items) =>
      _repository.batchAddManualTag(tag, items);

  Future<int> batchRemoveManualTag(TagItem tag, Iterable<VideoItem> items) =>
      _repository.batchRemoveManualTag(tag, items);

  Future<void> saveMetadata() => _repository.saveMetadata();
  Future<void> addFavoriteTag(String tag) => _repository.addFavoriteTag(tag);
  Future<void> removeFavoriteTag(String tag) =>
      _repository.removeFavoriteTag(tag);
  Future<void> replaceRoot(String oldRoot, String newRoot) =>
      _repository.replaceRoot(oldRoot, newRoot);

  /** 以 stable videoId 建立来源明确的标签关联。 */
  Future<void> attachTag({
    required String videoId,
    required String tagId,
    required TagSource source,
    bool locked = false,
  }) =>
      _tagRepository.attachTag(
        videoId: videoId,
        tagId: tagId,
        source: source,
        locked: locked,
      );

  Future<CacheStatus> thumbnailStatus(String videoId) =>
      _cacheRepository.thumbnailStatus(videoId);

  Future<void> savePlaybackPosition({
    required String videoId,
    required Duration position,
    required Duration duration,
    required bool completed,
    required DateTime updatedAt,
  }) =>
      _playbackRepository.savePlaybackPosition(
        videoId: videoId,
        position: position,
        duration: duration,
        completed: completed,
        updatedAt: updatedAt,
      );
  Future<void> upsertVideo(VideoItem item) => _repository.upsertVideo(item);

  /** 把后台媒体解析产生的多条视频字段更新合并为一次 Repository 批量写入。 */
  Future<void> upsertVideos(Iterable<VideoItem> items) =>
      _repository.upsertVideos(items);

  /** 批量保存用户播放状态，并同步排入稳定身份备份。 */
  Future<void> upsertPlaybackStates(Iterable<VideoItem> items) =>
      _repository.upsertPlaybackStates(items);
  Future<VideoItem?> deleteVideo(String path) => _repository.deleteVideo(path);
  /** 执行设置页授权的数据库清理，不向 UI 暴露 SQLite 或文件删除能力。 */
  Future<int> removeMissingOrUnreadableVideos() =>
      _repository.removeMissingOrUnreadableVideos();

  Future<LibraryScanCommitResult> addRootAndScanWithChanges(
    String rootPath, {
    LibraryScanProgressCallback? onProgress,
  }) =>
      _repository.addRootAndScanWithChanges(
        rootPath,
        onProgress: onProgress,
      );

  /** 批量添加文件所在目录或拖入目录，并合并为一次后台扫描。 */
  Future<LibraryScanCommitResult> addRootsAndScanWithChanges(
          Iterable<String> rootPaths,
          {LibraryScanProgressCallback? onProgress}) =>
      _repository.addRootsAndScanWithChanges(
        rootPaths,
        onProgress: onProgress,
      );

  Future<List<VideoItem>> removeRoot(String rootPath) =>
      _repository.removeRoot(rootPath);

  Future<LibraryScanCommitResult> scanWithChanges({
    LibraryScanProgressCallback? onProgress,
  }) =>
      _repository.scanWithChanges(onProgress: onProgress);

  /** 播放器进入/退出时只通过 Repository 协调扫描让盘，不暴露具体 sidecar。 */
  Future<void> setScanPaused(bool paused) => _repository.setScanPaused(paused);

  /** 用户从进度区取消当前扫描；已持久化的媒体库数据保持不变。 */
  Future<void> cancelActiveScan() => _repository.cancelActiveScan();

  /** 当前独立备份状态快照。 */
  DataBackupStatus get dataBackupStatus => _repository.dataBackupStatus;

  /** 设置页订阅的独立备份状态流。 */
  Stream<DataBackupStatus> get dataBackupStatusStream =>
      _repository.dataBackupStatusStream;

  Future<void> setDataBackupEnabled(bool enabled) =>
      _repository.setDataBackupEnabled(enabled);

  Future<void> runDataBackupNow() => _repository.runDataBackupNow();

  Future<DataBackupIntegrityReport> checkDataBackupIntegrity() =>
      _repository.checkDataBackupIntegrity();

  Future<Uint8List> createDataBackupExport() =>
      _repository.createDataBackupExport();

  Future<void> pauseDataBackupForPlayback() =>
      _repository.pauseDataBackupForPlayback();

  void resumeDataBackupAfterPlayback() =>
      _repository.resumeDataBackupAfterPlayback();

  Future<int> countUntrackedVideos() => _repository.countUntrackedVideos();

  Set<String> childTagsFor(String parentTag) =>
      _repository.childTagsFor(parentTag);

  /** 提交同一稳定视频在物理重命名后的 mutable path。 */
  Future<void> renameVideoPath(VideoItem item, String newPath) =>
      _repository.renameVideoPath(item, newPath);

  Future<void> relinkMissingVideo(VideoItem item, String newPath) =>
      _repository.relinkMissingVideo(item, newPath);

  Future<Set<String>> relinkMissingVideosInBatch(
    Map<VideoItem, String> targets,
  ) =>
      _repository.relinkMissingVideosInBatch(targets);

  Future<void> close() => _repository.close();
}
