import 'dart:async';
import 'dart:typed_data';

import '../models/library_scan_models.dart';
import '../models/data_backup_models.dart';
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

  /**
   * 批量持久化用户播放状态，并把对应稳定 videoId 加入独立备份队列。
   *
   * 该入口与只写媒体详情的 [upsertVideos] 分离，避免 FFprobe 缓存更新误触发大量
   * 用户依赖备份，同时保证继续观看清理/撤销不会漏掉备份同步。
   */
  Future<void> upsertPlaybackStates(Iterable<VideoItem> items);

  Future<VideoItem?> deleteVideo(String path);

  /** 只移除数据库中的 missing/不可读记录；临时离线路径和磁盘内容必须保留。 */
  Future<int> removeMissingOrUnreadableVideos();

  Future<LibraryScanCommitResult> addRootAndScanWithChanges(
    String rootPath, {
    LibraryScanProgressCallback? onProgress,
  });

  /** 批量注册媒体库 root，并在全部配置落盘后只执行一轮扫描。 */
  Future<LibraryScanCommitResult> addRootsAndScanWithChanges(
      Iterable<String> rootPaths,
      {LibraryScanProgressCallback? onProgress});

  /** 解除 root 管理并返回本轮转为 detached 的视频，不删除稳定身份或用户数据。 */
  Future<List<VideoItem>> removeRoot(String rootPath);

  Future<LibraryScanCommitResult> scanWithChanges({
    LibraryScanProgressCallback? onProgress,
  });

  /** 播放期间暂停/恢复只读扫描，避免机械盘读取与视频解码争抢。 */
  Future<void> setScanPaused(bool paused);

  /**
   * 取消当前扫描代次，并唤醒可能处于暂停状态的后端使其尽快退出。
   *
   * 取消只放弃尚未提交的扫描结果，不删除现有视频、标签或播放记录。
   */
  Future<void> cancelActiveScan();

  /** 当前视频依赖备份状态。 */
  DataBackupStatus get dataBackupStatus;

  /** 设置页订阅的无隐私进度流。 */
  Stream<DataBackupStatus> get dataBackupStatusStream;

  /** 切换后台备份；关闭时保留既有快照。 */
  Future<void> setDataBackupEnabled(bool enabled);

  /** 从头启动一轮独立备份核对。 */
  Future<void> runDataBackupNow();

  /** 用户显式检查独立备份的结构和当前数据覆盖情况。 */
  Future<DataBackupIntegrityReport> checkDataBackupIntegrity();

  /** 创建不含本地路径和媒体文件内容的便携导出。 */
  Future<Uint8List> createDataBackupExport();

  /** 播放前等待当前小批次结束并暂停。 */
  Future<void> pauseDataBackupForPlayback();

  /** 播放器释放后恢复未完成任务。 */
  void resumeDataBackupAfterPlayback();

  Future<int> countUntrackedVideos();

  Set<String> childTagsFor(String parentTag);

  /**
   * 在物理文件已完成同目录重命名后，把同一稳定 videoId 提交到 [newPath]。
   *
   * 该动作只更新 mutable path、标题和兼容 path 索引，不改变标签来源或用户数据。
   */
  Future<void> renameVideoPath(VideoItem item, String newPath);

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
