import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/application/library_facet_count_controller.dart';
import 'package:local_tag_player/src/features/library/domain/library_query_snapshot.dart';
import 'package:local_tag_player/src/models/platform_models.dart';
import 'package:local_tag_player/src/services/library/library_count_refresh_coordinator.dart';

void main() {
  test('候选计数与全库稳定计数保持独立只读快照', () {
    final controller = LibraryFacetCountController();
    final seed = <String, int>{'tag-a': 1};

    controller.seedVisible(seed);
    seed['tag-a'] = 9;
    controller.refreshStableNow(
      query: const FilterQuery(),
      compute: (_) => <String, int>{'tag-a': 4},
    );

    expect(controller.visibleCounts, <String, int>{'tag-a': 1});
    expect(controller.stableCounts, <String, int>{'tag-a': 4});
    expect(
      () => controller.visibleCounts['tag-b'] = 2,
      throwsUnsupportedError,
    );
  });

  test('facet owner 只接受最后一个空闲计数请求', () async {
    final controller = LibraryFacetCountController(
      coordinator: LibraryCountRefreshCoordinator(
        idleDelay: Duration.zero,
      ),
    );
    const oldQuery = FilterQuery(keyword: 'old');
    const currentQuery = FilterQuery(keyword: 'current');
    final oldEpoch = LibraryCountEpoch.fromQuery(
      dataRevision: 1,
      tagDefinitionRevision: 1,
      query: oldQuery,
    );
    final currentEpoch = LibraryCountEpoch.fromQuery(
      dataRevision: 1,
      tagDefinitionRevision: 1,
      query: currentQuery,
    );
    final published = <LibraryCountEpoch>[];

    controller.scheduleVisible(
      epoch: oldEpoch,
      query: oldQuery,
      compute: (_) => <String, int>{'tag-old': 1},
      isStillCurrent: (_) => true,
      onAccepted: (epoch, _) => published.add(epoch),
    );
    controller.scheduleVisible(
      epoch: currentEpoch,
      query: currentQuery,
      compute: (_) => <String, int>{'tag-current': 2},
      isStillCurrent: (epoch) => epoch == currentEpoch,
      onAccepted: (epoch, _) => published.add(epoch),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(published, <LibraryCountEpoch>[currentEpoch]);
    expect(
      controller.visibleCounts,
      <String, int>{'tag-current': 2},
    );
    expect(controller.stableCounts, isEmpty);

    controller.dispose();
    controller.scheduleStable(
      epoch: currentEpoch,
      query: currentQuery,
      compute: (_) => <String, int>{'tag-current': 8},
      isStillCurrent: (_) => true,
      onAccepted: (_, __) {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.stableCounts, isEmpty);
  });
}
