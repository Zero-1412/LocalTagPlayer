import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/services/resources/resource_scheduler.dart';

void main() {
  test('per-kind budget blocks a second lease until the first releases',
      () async {
    final scheduler = ResourceScheduler(
      budgets: const {ResourceKind.probe: 1},
      totalBudget: 1,
    );
    final first = await scheduler.acquire(ResourceKind.probe);
    var secondStarted = false;
    final second = scheduler.acquire(ResourceKind.probe).then((lease) {
      secondStarted = true;
      return lease;
    });

    await Future<void>.delayed(Duration.zero);
    expect(secondStarted, isFalse);
    first.release();
    final secondLease = await second;
    expect(secondStarted, isTrue);
    secondLease.release();
    scheduler.dispose();
  });

  test('foreground work overtakes queued background work', () async {
    final scheduler = ResourceScheduler(totalBudget: 1);
    final active = await scheduler.acquire(ResourceKind.thumbnail);
    final order = <String>[];
    final background = scheduler.acquire(ResourceKind.thumbnail).then((lease) {
      order.add('background');
      return lease;
    });
    final foreground = scheduler
        .acquire(
      ResourceKind.thumbnail,
      priority: ResourcePriority.foreground,
      allowDuringPlayback: true,
    )
        .then((lease) {
      order.add('foreground');
      return lease;
    });

    active.release();
    final foregroundLease = await foreground;
    expect(order, <String>['foreground']);
    foregroundLease.release();
    final backgroundLease = await background;
    expect(order, <String>['foreground', 'background']);
    backgroundLease.release();
    scheduler.dispose();
  });

  test('playback blocks background but admits explicit foreground work',
      () async {
    final scheduler = ResourceScheduler(totalBudget: 1);
    scheduler.setPlaybackActive(true);
    var backgroundStarted = false;
    final background = scheduler.acquire(ResourceKind.visual).then((lease) {
      backgroundStarted = true;
      return lease;
    });
    await Future<void>.delayed(Duration.zero);
    expect(backgroundStarted, isFalse);

    final foreground = await scheduler.acquire(
      ResourceKind.visual,
      priority: ResourcePriority.foreground,
      allowDuringPlayback: true,
    );
    foreground.release();
    scheduler.setPlaybackActive(false);
    final backgroundLease = await background;
    expect(backgroundStarted, isTrue);
    backgroundLease.release();
    scheduler.dispose();
  });

  test('pending request can be cancelled without consuming a lease', () async {
    final scheduler = ResourceScheduler(totalBudget: 1);
    final active = await scheduler.acquire(ResourceKind.thumbnail);
    final pending = scheduler.acquireRequest(ResourceKind.thumbnail);

    pending.cancel();
    await expectLater(
      pending.future,
      throwsA(isA<ResourceRequestCancelled>()),
    );
    expect(scheduler.snapshot.queuedTotal, 0);
    expect(scheduler.snapshot.activeTotal, 1);

    active.release();
    expect(scheduler.snapshot.activeTotal, 0);
    scheduler.dispose();
  });

  test('默认缩略图预算允许三个后台 lease 且不突破总预算', () async {
    final scheduler = ResourceScheduler(totalBudget: 4);
    final first = await scheduler.acquire(ResourceKind.thumbnail);
    var started = 0;
    final second = scheduler.acquire(ResourceKind.thumbnail).then((lease) {
      started++;
      return lease;
    });
    final third = scheduler.acquire(ResourceKind.thumbnail).then((lease) {
      started++;
      return lease;
    });

    await Future<void>.delayed(Duration.zero);
    expect(started, 2);
    expect(scheduler.snapshot.activeTotal, 3);
    expect(scheduler.snapshot.activeByKind[ResourceKind.thumbnail], 3);

    first.release();
    (await second).release();
    (await third).release();
    expect(scheduler.snapshot.activeTotal, 0);
    scheduler.dispose();
  });
}
