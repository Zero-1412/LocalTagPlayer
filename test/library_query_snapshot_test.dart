import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/domain/library_query_snapshot.dart';
import 'package:local_tag_player/src/models/platform_models.dart';
import 'package:local_tag_player/src/services/tags/tag_query_service.dart';

import 'support/library_benchmark_fixture.dart';
import 'support/library_query_trace.dart';

void main() {
  const manualA = TagItem(
    id: 'manual-a',
    name: 'A',
    source: TagSource.manual,
    groupId: 'manual',
  );
  const manualB = TagItem(
    id: 'manual-b',
    name: 'B',
    source: TagSource.manual,
    groupId: 'manual',
  );

  test('查询指纹与集合和分组的插入顺序无关', () {
    const first = FilterQuery(
      includeTagIds: <String>{'manual-b', 'manual-a'},
      selectedGroupTagIds: <String, Set<String>>{
        'manual': <String>{'manual-b', 'manual-a'},
      },
      groups: <TagGroup>[
        TagGroup(
          id: 'manual',
          name: '手动标签',
          items: <TagItem>[manualB, manualA],
        ),
      ],
    );
    const second = FilterQuery(
      includeTagIds: <String>{'manual-a', 'manual-b'},
      selectedGroupTagIds: <String, Set<String>>{
        'manual': <String>{'manual-a', 'manual-b'},
      },
      groups: <TagGroup>[
        TagGroup(
          id: 'manual',
          name: '手动标签',
          items: <TagItem>[manualA, manualB],
        ),
      ],
    );

    expect(
      LibraryQueryFingerprint.filter(first),
      LibraryQueryFingerprint.filter(second),
    );
  });

  test('排序只改变结果版本，不改变计数版本', () {
    const query = FilterQuery(keyword: '  FireFly  ');
    final titleResult = LibraryResultEpoch.fromQuery(
      dataRevision: 7,
      query: query,
      presentationSort: 'title:ascending',
    );
    final dateResult = LibraryResultEpoch.fromQuery(
      dataRevision: 7,
      query: query,
      presentationSort: 'addedAt:descending',
    );
    final firstCount = LibraryCountEpoch.fromQuery(
      dataRevision: 7,
      tagDefinitionRevision: 3,
      query: query,
    );
    final secondCount = LibraryCountEpoch.fromQuery(
      dataRevision: 7,
      tagDefinitionRevision: 3,
      query: query,
    );

    expect(titleResult, isNot(dateResult));
    expect(firstCount, secondCount);
    expect(titleResult.searchFingerprint, 'firefly');
  });

  test('结果与队列快照复制稳定身份并保持不可变', () {
    final sourceIds = <String>['video-2', 'video-1'];
    final epoch = LibraryResultEpoch.fromQuery(
      dataRevision: 1,
      query: const FilterQuery(),
      presentationSort: 'title:ascending',
    );
    final result = LibraryResultSnapshot(
      epoch: epoch,
      orderedVideoIds: sourceIds,
      totalCount: 2,
    );
    final queue = LibraryQueueSnapshot.fromResult(result);
    sourceIds.add('video-3');

    expect(result.orderedVideoIds, <String>['video-2', 'video-1']);
    expect(queue.orderedVideoIds, <String>['video-2', 'video-1']);
    expect(queue.resultEpoch, epoch);
    expect(
      () => queue.orderedVideoIds.add('video-4'),
      throwsUnsupportedError,
    );
  });

  test('查询追踪器拒绝旧结果和旧计数版本', () {
    final recorder = LibraryQueryTraceRecorder();
    final oldResult = LibraryResultEpoch.fromQuery(
      dataRevision: 1,
      query: const FilterQuery(keyword: 'old'),
      presentationSort: 'title:ascending',
    );
    final currentResult = LibraryResultEpoch.fromQuery(
      dataRevision: 2,
      query: const FilterQuery(keyword: 'new'),
      presentationSort: 'title:ascending',
    );
    final oldCount = LibraryCountEpoch.fromQuery(
      dataRevision: 1,
      tagDefinitionRevision: 1,
      query: const FilterQuery(keyword: 'old'),
    );
    final currentCount = LibraryCountEpoch.fromQuery(
      dataRevision: 2,
      tagDefinitionRevision: 2,
      query: const FilterQuery(keyword: 'new'),
    );

    expect(
      recorder.publishResult(
        expected: currentResult,
        candidate: oldResult,
        itemCount: 10,
      ),
      isFalse,
    );
    expect(
      recorder.publishCounts(
        expected: currentCount,
        candidate: oldCount,
        itemCount: 4,
      ),
      isFalse,
    );
    expect(
      recorder.events.map((event) => event.kind),
      <LibraryQueryTraceKind>[
        LibraryQueryTraceKind.resultDiscarded,
        LibraryQueryTraceKind.countDiscarded,
      ],
    );
  });

  test('11,000 项 fixture 可重复生成并执行真实筛选', () {
    final first = buildDeterministicLibraryFixture();
    final second = buildDeterministicLibraryFixture();
    final service = TagQueryService(
      videos: first,
      tagContext: const TagQueryContext(),
    );
    final recorder = LibraryQueryTraceRecorder();
    const query = FilterQuery(keyword: 'video_10999');
    final epoch = LibraryResultEpoch.fromQuery(
      dataRevision: 1,
      query: query,
      presentationSort: 'title:ascending',
    );
    final result = recorder.computeResult(
      service: service,
      query: query,
      epoch: epoch,
    );

    expect(first, hasLength(11000));
    expect(second, hasLength(11000));
    expect(first.first.videoId, second.first.videoId);
    expect(first.last.path, second.last.path);
    expect(result.single.videoId, 'fixture-video-10999');
  });
}
