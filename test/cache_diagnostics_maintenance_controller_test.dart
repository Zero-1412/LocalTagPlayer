import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/settings/application/cache_diagnostics_maintenance_controller.dart';

class _FailureItem {
  _FailureItem(this.reason);

  String? reason;
}

void main() {
  CacheFailureCommandTarget<_FailureItem> target(_FailureItem item) =>
      CacheFailureCommandTarget<_FailureItem>(
        item: item,
        reason: item.reason!,
      );

  test('缓存维护命令互斥且重试只持久化已清除标记的条目', () async {
    final gate = Completer<void>();
    final first = _FailureItem('失败一');
    final second = _FailureItem('失败二');
    final persisted = <_FailureItem>[];
    var clearCalls = 0;
    final controller = CacheDiagnosticsMaintenanceController<_FailureItem>(
      retryFailures: (items) async {
        await gate.future;
        first.reason = null;
        return 1;
      },
      clearFailures: (_) {
        clearCalls += 1;
        return 0;
      },
      persistChanges: (items) async => persisted.addAll(items),
      isFailureResolved: (item) => item.reason == null,
      restoreFailure: (item, reason) => item.reason = reason,
    );
    addTearDown(controller.dispose);

    final retry = controller.retry(<CacheFailureCommandTarget<_FailureItem>>[
      target(first),
      target(second),
    ]);
    expect(controller.busy, isTrue);
    expect(
      await controller.clear(<CacheFailureCommandTarget<_FailureItem>>[
        target(second),
      ]),
      isNull,
    );
    expect(clearCalls, 0);

    gate.complete();
    final outcome = await retry;
    expect(outcome?.requested, 2);
    expect(outcome?.retried, 1);
    expect(persisted, <_FailureItem>[first]);
    expect(controller.busy, isFalse);
  });

  test('清除持久化失败会恢复全部原失败原因并释放互斥', () async {
    final first = _FailureItem('失败一');
    final second = _FailureItem('失败二');
    final controller = CacheDiagnosticsMaintenanceController<_FailureItem>(
      retryFailures: (_) async => 0,
      clearFailures: (items) {
        for (final item in items) {
          item.reason = null;
        }
        return 2;
      },
      persistChanges: (_) async => throw StateError('写入失败'),
      isFailureResolved: (item) => item.reason == null,
      restoreFailure: (item, reason) => item.reason = reason,
    );
    addTearDown(controller.dispose);

    await expectLater(
      controller.clear(<CacheFailureCommandTarget<_FailureItem>>[
        target(first),
        target(second),
      ]),
      throwsStateError,
    );

    expect(first.reason, '失败一');
    expect(second.reason, '失败二');
    expect(controller.busy, isFalse);
  });

  test('dispose 后不再接受新维护命令', () async {
    var retryCalls = 0;
    final item = _FailureItem('失败');
    final controller = CacheDiagnosticsMaintenanceController<_FailureItem>(
      retryFailures: (_) async {
        retryCalls += 1;
        return 1;
      },
      clearFailures: (_) => 0,
      persistChanges: (_) async {},
      isFailureResolved: (_) => false,
      restoreFailure: (item, reason) => item.reason = reason,
    );
    controller.dispose();

    expect(
      await controller.retry(<CacheFailureCommandTarget<_FailureItem>>[
        target(item),
      ]),
      isNull,
    );
    expect(retryCalls, 0);
  });
}
