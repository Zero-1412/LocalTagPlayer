part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

abstract interface class LibraryRepository {
  Future<List<String>> loadRoots();

  Future<void> saveRoots(List<String> roots);

  Future<List<VideoItem>> loadVideos(
      {FilterQuery filter = const FilterQuery()});

  Future<void> upsertVideo(VideoItem item);

  Future<void> markMissing(String path);
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
