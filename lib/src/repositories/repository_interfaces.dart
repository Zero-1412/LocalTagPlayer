import '../models/library_scan_models.dart';
import '../models/platform_models.dart';
import '../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/** 批量 relink 只需要的最小应用契约。 */
abstract interface class LibraryRelinkRepository {
  Map<String, VideoItem> get videos;
  List<String> get roots;
  Future<Set<String>> relinkMissingVideosInBatch(
    Map<VideoItem, String> targets,
  );
  Future<void> replaceRoot(String oldRoot, String newRoot);
}

abstract interface class LibraryRepository implements LibraryRelinkRepository {
  /** 当前受管理的媒体库根目录；具体集合由 Dart Repository 独占维护。 */
  @override
  List<String> get roots;

  /** 以内存 pathKey 索引保存的稳定视频记录。 */
  @override
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

  /** 将标签加入用户收藏，并由 repository 负责持久化。 */
  Future<void> addFavoriteTag(String tag);

  /** 从用户收藏移除标签，并由 repository 负责持久化。 */
  Future<void> removeFavoriteTag(String tag);

  Future<void> upsertVideo(VideoItem item);

  /**
   * 批量写入仅视频行字段，供媒体信息等后台任务合并 SQLite 提交。
   *
   * 调用方必须保证条目仍属于当前媒体库；该方法不重建标签关系，也不改变
   * folder/manual 标签来源语义。
   */
  Future<void> upsertVideos(Iterable<VideoItem> items);

  Future<VideoItem?> deleteVideo(String path);

  Future<LibraryScanCommitResult> addRootAndScanWithChanges(String rootPath);

  /** 批量注册媒体库 root，并在全部配置落盘后只执行一轮扫描。 */
  Future<LibraryScanCommitResult> addRootsAndScanWithChanges(
    Iterable<String> rootPaths,
  );

  Future<List<VideoItem>> removeRoot(String rootPath);

  Future<LibraryScanCommitResult> scanWithChanges();

  Future<int> countUntrackedVideos();

  Set<String> childTagsFor(String parentTag);

  Future<void> relinkMissingVideo(VideoItem item, String newPath);

  @override
  Future<Set<String>> relinkMissingVideosInBatch(
    Map<VideoItem, String> targets,
  );

  @override
  Future<void> replaceRoot(String oldRoot, String newRoot);

  Future<void> close();
}

abstract interface class TagRepository {
  Future<List<TagGroup>> loadGroups();

  Future<List<TagItem>> loadTags({String? groupId});

  Future<void> saveTag(TagItem tag);

  Future<void> attachTag({
    required String videoId,
    required String tagId,
    required TagSource source,
    bool locked = false,
  });

  Future<void> detachTag({
    required String videoId,
    required String tagId,
    required TagSource source,
  });
}

abstract interface class CacheRepository {
  Future<CacheStatus> thumbnailStatus(String videoId);

  Future<CacheStatus> mediaDetailsStatus(String videoId);

  Future<void> saveThumbnailStatus(String videoId, CacheStatus status);

  Future<void> saveMediaDetailsStatus(String videoId, CacheStatus status);
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
