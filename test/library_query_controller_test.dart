import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_query_controller.dart';
import 'package:local_tag_player/src/features/library/domain/library_query_snapshot.dart';
import 'package:local_tag_player/src/models/platform_models.dart';
import 'package:local_tag_player/src/models/video_item.dart';
import 'package:local_tag_player/src/services/tags/tag_query_service.dart';

VideoItem _video(String id, String title) {
  return VideoItem(
    videoId: id,
    path: 'D:\\library\\$title.mp4',
    title: title,
    folder: r'D:\library',
    tags: const <String>{},
    addedAt: DateTime.utc(2026),
  );
}

void main() {
  test('查询 owner 只发布最后一次搜索输入', () async {
    final alpha = _video('video-alpha', 'alpha');
    final bravo = _video('video-bravo', 'bravo');
    final controller = LibraryQueryController()
      ..configure(
        engine: TagQueryService(
          videos: <VideoItem>[alpha, bravo],
          tagContext: const TagQueryContext(),
        ),
        totalCount: 2,
        dataRevision: 1,
        sortFingerprint: 'name:ascending',
      );
    final accepted = <FilterState>[];
    const alphaQuery = FilterQuery(keyword: 'alpha');
    const bravoQuery = FilterQuery(keyword: 'bravo');

    controller.schedule(
      query: alphaQuery,
      expectedEpoch: LibraryResultEpoch.fromQuery(
        dataRevision: 1,
        query: alphaQuery,
        presentationSort: 'name:ascending',
      ),
      isStillCurrent: (_) => true,
      onAccepted: accepted.add,
    );
    controller.schedule(
      query: bravoQuery,
      expectedEpoch: LibraryResultEpoch.fromQuery(
        dataRevision: 1,
        query: bravoQuery,
        presentationSort: 'name:ascending',
      ),
      isStillCurrent: (_) => true,
      onAccepted: accepted.add,
    );
    expect(controller.requestedQuery, bravoQuery);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(accepted, hasLength(1));
    expect(accepted.single.query.keyword, 'bravo');
    expect(
      controller.state?.filteredVideos.map((item) => item.videoId),
      <String>['video-bravo'],
    );
  });

  test('查询 owner 拒绝 epoch 不匹配结果并在 dispose 后停止发布', () async {
    final controller = LibraryQueryController()
      ..configure(
        engine: TagQueryService(
          videos: <VideoItem>[_video('video-alpha', 'alpha')],
          tagContext: const TagQueryContext(),
        ),
        totalCount: 1,
        dataRevision: 2,
        sortFingerprint: 'name:ascending',
      );
    const query = FilterQuery(keyword: 'alpha');
    var publishes = 0;

    controller.schedule(
      query: query,
      expectedEpoch: LibraryResultEpoch.fromQuery(
        dataRevision: 1,
        query: query,
        presentationSort: 'name:ascending',
      ),
      isStillCurrent: (_) => true,
      onAccepted: (_) => publishes += 1,
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(publishes, 0);
    expect(controller.state, isNull);

    controller.schedule(
      query: query,
      expectedEpoch: LibraryResultEpoch.fromQuery(
        dataRevision: 2,
        query: query,
        presentationSort: 'name:ascending',
      ),
      isStillCurrent: (_) => true,
      onAccepted: (_) => publishes += 1,
    );
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(publishes, 0);
    expect(controller.isDisposed, isTrue);
  });

  test('删除差量只移除指定 stable ID 并保留未变化结果对象', () {
    final removed = _video('video-removed', 'removed');
    final retained = _video('video-retained', 'retained');
    final source = FilterStateSource()
      ..configure(
        engine: TagQueryService(
          videos: <VideoItem>[removed, retained],
          tagContext: const TagQueryContext(),
        ),
        totalCount: 2,
        dataRevision: 1,
        sortFingerprint: 'name:ascending',
      );
    const query = FilterQuery();
    final initial = source.update(query);

    source.configure(
      engine: TagQueryService(
        videos: <VideoItem>[retained],
        tagContext: const TagQueryContext(),
      ),
      totalCount: 1,
      dataRevision: 2,
      sortFingerprint: 'name:ascending',
    );
    final next = source.applyVideoDelta(
      query,
      const <VideoItem>[],
      removedVideoIds: <String>[removed.videoId],
    );

    expect(initial.filteredVideos, contains(removed));
    expect(next.filteredVideos, <VideoItem>[retained]);
    expect(next.filteredVideos.single, same(retained));
    expect(next.totalCount, 1);
  });

  test('候选查询只缩小输入集合，最终仍由完整 FilterQuery 校验', () async {
    final alpha = _video('video-alpha', 'alpha');
    final bravo = _video('video-bravo', 'bravo');
    final controller = LibraryQueryController()
      ..configure(
        engine: TagQueryService(
          videos: <VideoItem>[alpha, bravo],
          tagContext: const TagQueryContext(),
        ),
        totalCount: 2,
        dataRevision: 4,
        sortFingerprint: 'name:ascending',
        loadCandidates: (_) async => <VideoItem>[alpha, bravo],
      );
    final accepted = <FilterState>[];
    const query = FilterQuery(keyword: 'alpha');

    controller.schedule(
      query: query,
      expectedEpoch: LibraryResultEpoch.fromQuery(
        dataRevision: 4,
        query: query,
        presentationSort: 'name:ascending',
      ),
      isStillCurrent: (_) => true,
      onAccepted: accepted.add,
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(accepted, hasLength(1));
    expect(accepted.single.filteredVideos, <VideoItem>[alpha]);
    expect(accepted.single.totalCount, 2);
  });

  test('候选索引失败时回退完整内存查询', () async {
    final alpha = _video('video-alpha', 'alpha');
    final bravo = _video('video-bravo', 'bravo');
    final controller = LibraryQueryController()
      ..configure(
        engine: TagQueryService(
          videos: <VideoItem>[alpha, bravo],
          tagContext: const TagQueryContext(),
        ),
        totalCount: 2,
        dataRevision: 5,
        sortFingerprint: 'name:ascending',
        loadCandidates: (_) async => throw StateError('FTS unavailable'),
      );
    final accepted = <FilterState>[];
    const query = FilterQuery(keyword: 'bravo');

    controller.schedule(
      query: query,
      expectedEpoch: LibraryResultEpoch.fromQuery(
        dataRevision: 5,
        query: query,
        presentationSort: 'name:ascending',
      ),
      isStillCurrent: (_) => true,
      onAccepted: accepted.add,
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(accepted.single.filteredVideos, <VideoItem>[bravo]);
  });
}
