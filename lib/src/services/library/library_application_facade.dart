part of '../../app.dart';

// ignore_for_file: slash_for_doc_comments, annotate_overrides

/**
 * 媒体库页面使用的应用服务门面。
 *
 * 页面只通过该对象发起用例并读取不可替换的领域索引，不再知道 SQLite、扫描后端或
 * `LibraryStore` 的具体类型。标签筛选、stable identity 与 SQLite 单写仍留在 Dart
 * Repository 内部，不下沉到 Rust/C++。
 */
class LibraryApplicationFacade implements LibraryRepository {
  const LibraryApplicationFacade(this._repository);

  /** 由组合根注入的 Dart Repository。 */
  final LibraryRepository _repository;

  List<String> get roots => _repository.roots;
  Map<String, VideoItem> get videos => _repository.videos;
  List<String> get favoriteTags => _repository.favoriteTags;
  List<TagGroup> get tagGroups => _repository.tagGroups;
  Map<String, TagItem> get tagsById => _repository.tagsById;
  Map<String, Set<String>> get videoTagIdsByPathKey =>
      _repository.videoTagIdsByPathKey;
  TagQueryContext get tagQueryContext => _repository.tagQueryContext;
  Iterable<TagItem> get allTagItems => _repository.allTagItems;
  Set<String> get allTags => _repository.allTags;

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
  Future<void> upsertVideo(VideoItem item) => _repository.upsertVideo(item);
  Future<VideoItem?> deleteVideo(String path) => _repository.deleteVideo(path);

  Future<LibraryScanCommitResult> addRootAndScanWithChanges(String rootPath) =>
      _repository.addRootAndScanWithChanges(rootPath);

  Future<List<VideoItem>> removeRoot(String rootPath) =>
      _repository.removeRoot(rootPath);

  Future<LibraryScanCommitResult> scanWithChanges() =>
      _repository.scanWithChanges();

  Future<int> countUntrackedVideos() => _repository.countUntrackedVideos();

  Set<String> childTagsFor(String parentTag) =>
      _repository.childTagsFor(parentTag);

  Future<void> relinkMissingVideo(VideoItem item, String newPath) =>
      _repository.relinkMissingVideo(item, newPath);

  Future<Set<String>> relinkMissingVideosInBatch(
    Map<VideoItem, String> targets,
  ) =>
      _repository.relinkMissingVideosInBatch(targets);

  Future<void> close() => _repository.close();
}
