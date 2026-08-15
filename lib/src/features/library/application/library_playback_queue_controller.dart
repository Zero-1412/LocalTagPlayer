import 'dart:math' as math;

import '../../../models/platform_models.dart';
import '../../../models/video_item.dart';
import '../domain/library_query_snapshot.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 已接受结果解析出的播放器队列。
 *
 * [snapshot] 保留结果 epoch 与 stable-ID 顺序，[videos] 是按同一顺序解析出的不可变对象
 * 列表。播放器只能消费该配对，不能再从 Store 或当前页面状态重建成员。
 */
class LibraryPlaybackQueue {
  LibraryPlaybackQueue({
    required this.snapshot,
    required Iterable<VideoItem> videos,
  }) : videos = List<VideoItem>.unmodifiable(List<VideoItem>.of(videos));

  /** 从已接受结果单向转换出的队列身份。 */
  final LibraryQueueSnapshot snapshot;

  /** 与 [snapshot] stable-ID 顺序严格一致的不可变视频列表。 */
  final List<VideoItem> videos;

  /** 按 stable `videoId` 返回当前项位置；不存在时返回 -1。 */
  int indexOfVideoId(String videoId) =>
      videos.indexWhere((item) => item.videoId == videoId);
}

/** 一次通过快照校验的队列与当前选中项。 */
class LibraryPlaybackSelection {
  const LibraryPlaybackSelection({
    required this.queue,
    required this.selectedItem,
  });

  /** 与已接受结果严格同序的不可变队列。 */
  final LibraryPlaybackQueue queue;

  /** 通过 stable `videoId` 从队列中解析出的当前项。 */
  final VideoItem selectedItem;
}

/**
 * 已接受媒体库结果到播放器队列的唯一转换 owner。
 *
 * controller 不执行筛选、排序或 Repository 查询，只验证 [LibraryResultSnapshot] 与页面
 * 已展示视频的一一对应关系，再调用 `LibraryQueueSnapshot.fromResult`。缺失、额外或重复
 * stable ID 会拒绝转换，防止旧 Widget 回调或原始 Store 绕过已接受结果边界。
 */
class LibraryPlaybackQueueController {
  /** 最近一次成功转换的不可变队列，供诊断与回归核对来源 epoch。 */
  LibraryPlaybackQueue? _queue;

  /** 最近一次成功转换的队列；尚未打开视频时为空。 */
  LibraryPlaybackQueue? get queue => _queue;

  /**
   * 把页面实际渲染的 [displayedVideos] 固化为已接受结果快照。
   *
   * 主媒体库必须复用 [acceptedLibraryEpoch]；其它同步来源使用显式 [source]、本地路径、
   * 播放数据代次和排序指纹构造独立 epoch，避免旧来源 Widget 冒充当前筛选结果。
   */
  LibraryResultSnapshot acceptDisplayedResult({
    required LibraryResultSource source,
    required LibraryResultEpoch acceptedLibraryEpoch,
    required Iterable<VideoItem> displayedVideos,
    required int totalCount,
    required int dataRevision,
    required int playbackDataRevision,
    required String sortFingerprint,
    String? localPath,
  }) {
    final sourceQuery = switch (source) {
      LibraryResultSource.library => const FilterQuery(),
      LibraryResultSource.favorites => const FilterQuery(favoriteOnly: true),
      LibraryResultSource.local => FilterQuery(
          folderRoots:
              localPath == null ? const <String>[] : <String>[localPath],
        ),
      LibraryResultSource.recent => const FilterQuery(unplayedOnly: true),
      // 相似候选页是显式的页面来源；它只播放页面传入的候选组，不冒充全库筛选结果。
      LibraryResultSource.similarity => const FilterQuery(),
    };
    final epoch = source == LibraryResultSource.library
        ? acceptedLibraryEpoch
        : LibraryResultEpoch.fromQuery(
            dataRevision: dataRevision,
            query: sourceQuery,
            presentationSort: '${source.name}:$sortFingerprint:'
                'playback=$playbackDataRevision',
          );
    return LibraryResultSnapshot(
      epoch: epoch,
      orderedVideoIds: displayedVideos.map((item) => item.videoId),
      totalCount: totalCount,
    );
  }

  /**
   * 从 [result] 和对应的 [acceptedVideos] 准备播放器队列。
   *
   * [selectedVideoId] 必须属于结果成员；任何成员或顺序不一致都会返回 null，并保留上一份
   * 成功队列，避免一次过期点击破坏正在使用的诊断快照。
   */
  LibraryPlaybackQueue? prepare({
    required LibraryResultSnapshot result,
    required Iterable<VideoItem> acceptedVideos,
    required String selectedVideoId,
  }) {
    final videos = acceptedVideos.toList(growable: false);
    if (videos.length != result.orderedVideoIds.length) {
      return null;
    }
    final byId = <String, VideoItem>{};
    for (final video in videos) {
      if (byId.containsKey(video.videoId)) {
        return null;
      }
      byId[video.videoId] = video;
    }
    final resolved = <VideoItem>[];
    for (final videoId in result.orderedVideoIds) {
      final video = byId[videoId];
      if (video == null) {
        return null;
      }
      resolved.add(video);
    }
    if (!byId.containsKey(selectedVideoId)) {
      return null;
    }
    final prepared = LibraryPlaybackQueue(
      snapshot: LibraryQueueSnapshot.fromResult(result),
      videos: resolved,
    );
    _queue = prepared;
    return prepared;
  }

  /** 准备队列并同时解析选中项，任一校验失败时返回 null。 */
  LibraryPlaybackSelection? prepareSelection({
    required LibraryResultSnapshot result,
    required Iterable<VideoItem> acceptedVideos,
    required String selectedVideoId,
  }) {
    final prepared = prepare(
      result: result,
      acceptedVideos: acceptedVideos,
      selectedVideoId: selectedVideoId,
    );
    final selectedIndex = prepared?.indexOfVideoId(selectedVideoId) ?? -1;
    if (prepared == null || selectedIndex < 0) {
      return null;
    }
    return LibraryPlaybackSelection(
      queue: prepared,
      selectedItem: prepared.videos[selectedIndex],
    );
  }

  /**
   * 在进入播放器前预热选中项前两项和后六项。
   *
   * [load] 由页面注入可见缩略图读取边界；controller 只按已接受队列顺序选择邻近成员。
   */
  Future<void> warmNearby<T>({
    required LibraryPlaybackQueue queue,
    required String selectedVideoId,
    required Future<T> Function(VideoItem item) load,
  }) async {
    final initialIndex = queue.indexOfVideoId(selectedVideoId);
    if (initialIndex < 0) {
      return;
    }
    final warmStart = math.max(0, initialIndex - 2);
    final warmEnd = math.min(queue.videos.length, initialIndex + 7);
    await Future.wait<T>(
      queue.videos
          .sublist(warmStart, warmEnd)
          .where((video) => !video.isMissing)
          .map(load),
    );
  }

  /** 页面释放或测试结束时清除诊断引用，不影响已经传给播放器的不可变列表。 */
  void clear() {
    _queue = null;
  }
}

/** 页面可渲染并转换为播放器队列的四种既有结果来源。 */
enum LibraryResultSource {
  library,
  recent,
  favorites,
  local,
  similarity;

  /** 从页面结果模式的稳定名称恢复公开来源枚举。 */
  static LibraryResultSource fromName(String name) =>
      LibraryResultSource.values.firstWhere((source) => source.name == name);
}
