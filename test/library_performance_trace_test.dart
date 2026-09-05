import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/services/library/library_performance_trace.dart';

void main() {
  tearDown(LibraryPerformanceTrace.stop);

  test('默认关闭，观测不替换结果或异常', () async {
    LibraryPerformanceTrace.stop();
    expect(LibraryPerformanceTrace.begin('disabled'), isNull);
    expect(
        await LibraryPerformanceTrace.measure('disabled', () async => 42), 42);
    LibraryPerformanceTrace.start();
    final failure = StateError('controlled');
    await expectLater(
        LibraryPerformanceTrace.measure('failure', () async {
          throw failure;
        }),
        throwsA(same(failure)));
    final events = LibraryPerformanceTrace.snapshot()['events'] as List;
    expect(events.single['outcome'], 'error');
    expect(events.single.toString(), isNot(contains('controlled')));
  });

  test('分段关联跨 await 保留，会话更换或停止后拒绝晚到记录', () async {
    LibraryPerformanceTrace.start();
    final parent = LibraryPerformanceTrace.begin('request')!;
    parent.step('queued');
    await LibraryPerformanceTrace.within(parent, () async {
      await Future<void>.delayed(Duration.zero);
      await LibraryPerformanceTrace.measure('sql', () async => 1);
    });
    parent.finish('accepted');
    final events = LibraryPerformanceTrace.snapshot()['events'] as List;
    expect(events[1]['parentId'], parent.id);
    expect(events.every((dynamic e) => e['endUs'] >= e['startUs']), isTrue);
    final gate = Completer<void>();
    final lateChild = LibraryPerformanceTrace.within(parent, () async {
      await gate.future;
      await LibraryPerformanceTrace.measure('old.child', () async => 1);
    });
    LibraryPerformanceTrace.start();
    gate.complete();
    await lateChild;
    parent.finish('late');
    final pending = LibraryPerformanceTrace.begin('pending')!;
    LibraryPerformanceTrace.stop();
    pending.finish('late');
    expect(LibraryPerformanceTrace.snapshot()['events'], isEmpty);
  });

  test('采样达到上限只丢弃观测，不扩大内存或阻断操作', () async {
    LibraryPerformanceTrace.start(maxEvents: 2);
    for (var i = 0; i < 5; i++) {
      expect(await LibraryPerformanceTrace.measure('work', () async => i), i);
    }
    expect(LibraryPerformanceTrace.snapshot()['events'], hasLength(2));
    expect(LibraryPerformanceTrace.snapshot()['dropped'], 3);
  });
}
