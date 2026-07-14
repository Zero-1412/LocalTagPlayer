part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

abstract interface class LibraryRepository {
  /** 当前受管理的媒体库根目录；具体集合由 Dart Repository 独占维护。 */
  List<String> get roots;

  /** 以内存 pathKey 索引保存的稳定视频记录。 */
  Map<String, VideoItem> get videos;

  /** 用户固定的常用标签名称。 */
  List<String> get favoriteTags;

  /** 当前标签组及其展示顺序。 */
  List<TagGroup> get tagGroups;

  /** tagId 到标签实体的规范化索引。 */
  Map<String, TagItem> get tagsById;

  /** 视频 pathKey 到 tagId 的兼容查询索引。 */
  Map<String, Set<String>> get videoTagIdsByPathKey;

  TagQueryContext get tagQueryContext;

  Iterable<TagItem> get allTagItems;

  Set<String> get allTags;

  Map<String, int> resultCounts(FilterQuery query);

  Future<Map<String, TagUsageSummary>> tagUsageSummaries();

  Future<void> replaceManualTags(
    VideoItem item, {
    String? parentTag,
  });

  Future<TagItem> createManualTag({
    required String name,
    required String groupId,
    String? displayName,
  });

  Future<void> updateTagDetails(
    TagItem tag, {
    String? displayName,
    Iterable<String>? aliases,
    String? groupId,
    bool? isHidden,
    bool? isFavorite,
    int? sortOrder,
  });

  Future<int> countTagReferences(TagItem tag);

  Future<int> batchAddManualTag(TagItem tag, Iterable<VideoItem> items);

  Future<int> batchRemoveManualTag(TagItem tag, Iterable<VideoItem> items);

  Future<void> saveMetadata();

  Future<void> upsertVideo(VideoItem item);

  Future<VideoItem?> deleteVideo(String path);

  Future<LibraryScanCommitResult> addRootAndScanWithChanges(String rootPath);

  Future<List<VideoItem>> removeRoot(String rootPath);

  Future<LibraryScanCommitResult> scanWithChanges();

  Future<int> countUntrackedVideos();

  Set<String> childTagsFor(String parentTag);

  Future<void> relinkMissingVideo(VideoItem item, String newPath);

  Future<Set<String>> relinkMissingVideosInBatch(
    Map<VideoItem, String> targets,
  );

  Future<void> close();
}

abstract interface class TagRepository {
  Future<List<TagGroup>> loadGroups();

  Future<List<TagItem>> loadTags({String? groupId});

  Future<void> saveTag(TagItem tag);

  Future<void> attachTag({
    required String videoPath,
    required String tagId,
    required TagSource source,
    bool locked = false,
  });

  Future<void> detachTag({
    required String videoPath,
    required String tagId,
    required TagSource source,
  });
}

abstract interface class CacheRepository {
  Future<CacheStatus> thumbnailStatus(String videoPath);

  Future<CacheStatus> mediaDetailsStatus(String videoPath);

  Future<void> saveThumbnailStatus(CacheStatus status);

  Future<void> saveMediaDetailsStatus(CacheStatus status);
}

abstract interface class PlaybackRepository {
  Future<void> saveSession(PlaybackSession session);

  Future<PlaybackSession?> loadLastSession();

  /**
   * 按稳定 [videoId] 保存位置、总时长和完成态；mutable path 不参与播放状态身份。
   */
  Future<void> savePlaybackPosition({
    required String videoId,
    required Duration position,
    required Duration duration,
    required bool completed,
    required DateTime updatedAt,
  });
}
