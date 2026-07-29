import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_playback_queue_controller.dart';
import 'package:local_tag_player/src/features/library/domain/library_query_snapshot.dart';
import 'package:local_tag_player/src/models/platform_models.dart';
import 'package:local_tag_player/src/models/video_item.dart';

VideoItem _video(String videoId, String title) {
  return VideoItem(
    videoId: videoId,
    path: 'D:\\library\\$title.mp4',
    title: title,
    folder: r'D:\library',
    tags: const <String>{},
    addedAt: DateTime.utc(2026),
  );
}

void main() {
  test('播放队列只按已接受 ResultSnapshot 的 stable-ID 顺序生成', () {
    final alpha = _video('video-alpha', 'alpha');
    final bravo = _video('video-bravo', 'bravo');
    final epoch = LibraryResultEpoch.fromQuery(
      dataRevision: 4,
      query: const FilterQuery(keyword: 'a'),
      presentationSort: 'name:ascending',
    );
    final acceptedVideos = <VideoItem>[alpha, bravo];
    final controller = LibraryPlaybackQueueController();
    final result = controller.acceptDisplayedResult(
      source: LibraryResultSource.library,
      acceptedLibraryEpoch: epoch,
      displayedVideos: <VideoItem>[bravo, alpha],
      totalCount: 2,
      dataRevision: 4,
      playbackDataRevision: 0,
      sortFingerprint: 'name:ascending',
    );

    final queue = controller.prepare(
      result: result,
      acceptedVideos: acceptedVideos,
      selectedVideoId: bravo.videoId,
    );
    acceptedVideos.clear();

    expect(queue, isNotNull);
    expect(queue?.snapshot.resultEpoch, epoch);
    expect(
      queue?.snapshot.orderedVideoIds,
      <String>['video-bravo', 'video-alpha'],
    );
    expect(
      queue?.videos.map((item) => item.videoId),
      <String>['video-bravo', 'video-alpha'],
    );
    expect(queue?.indexOfVideoId(alpha.videoId), 1);
    expect(() => queue?.videos.add(alpha), throwsUnsupportedError);
  });

  test('成员缺失、重复或选中项越界时拒绝替代已成功队列', () {
    final alpha = _video('video-alpha', 'alpha');
    final bravo = _video('video-bravo', 'bravo');
    final result = LibraryResultSnapshot(
      epoch: LibraryResultEpoch.fromQuery(
        dataRevision: 1,
        query: const FilterQuery(),
        presentationSort: 'name:ascending',
      ),
      orderedVideoIds: <String>[alpha.videoId, bravo.videoId],
      totalCount: 2,
    );
    final controller = LibraryPlaybackQueueController();
    final accepted = controller.prepare(
      result: result,
      acceptedVideos: <VideoItem>[alpha, bravo],
      selectedVideoId: alpha.videoId,
    );

    expect(
      controller.prepare(
        result: result,
        acceptedVideos: <VideoItem>[alpha],
        selectedVideoId: alpha.videoId,
      ),
      isNull,
    );
    expect(
      controller.prepare(
        result: result,
        acceptedVideos: <VideoItem>[alpha, alpha],
        selectedVideoId: alpha.videoId,
      ),
      isNull,
    );
    expect(
      controller.prepare(
        result: result,
        acceptedVideos: <VideoItem>[alpha, bravo],
        selectedVideoId: 'video-missing',
      ),
      isNull,
    );
    expect(controller.queue, same(accepted));
  });

  test('邻近预热只消费已接受队列顺序并跳过 missing 项', () async {
    final alpha = _video('video-alpha', 'alpha');
    final bravo = _video('video-bravo', 'bravo')..isMissing = true;
    final charlie = _video('video-charlie', 'charlie');
    final controller = LibraryPlaybackQueueController();
    final result = controller.acceptDisplayedResult(
      source: LibraryResultSource.recent,
      acceptedLibraryEpoch: LibraryResultEpoch.fromQuery(
        dataRevision: 1,
        query: const FilterQuery(),
        presentationSort: 'unused',
      ),
      displayedVideos: <VideoItem>[alpha, bravo, charlie],
      totalCount: 3,
      dataRevision: 1,
      playbackDataRevision: 2,
      sortFingerprint: 'recent:descending',
    );
    final selection = controller.prepareSelection(
      result: result,
      acceptedVideos: <VideoItem>[alpha, bravo, charlie],
      selectedVideoId: charlie.videoId,
    );
    final warmedIds = <String>[];

    await controller.warmNearby<void>(
      queue: selection!.queue,
      selectedVideoId: charlie.videoId,
      load: (item) async => warmedIds.add(item.videoId),
    );

    expect(
      warmedIds,
      <String>['video-alpha', 'video-charlie'],
    );
    expect(selection.queue.snapshot.resultEpoch, result.epoch);
  });
}
