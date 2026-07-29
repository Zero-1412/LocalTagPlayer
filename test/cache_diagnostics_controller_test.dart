import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/settings/application/cache_diagnostics_controller.dart';

void main() {
  test('缓存统计只发布最新刷新代次', () async {
    final first = Completer<int>();
    final second = Completer<int>();
    var calls = 0;
    final controller = CacheDiagnosticsController<int>(
      load: () => calls++ == 0 ? first.future : second.future,
    );
    addTearDown(controller.dispose);

    final firstRefresh = controller.refresh();
    final secondRefresh = controller.refresh();
    second.complete(8);
    await secondRefresh;
    first.complete(2);
    await firstRefresh;

    expect(controller.loading, isFalse);
    expect(controller.stats, 8);
    expect(controller.error, isNull);
  });

  test('最新读取失败发布安全错误状态并允许重试', () async {
    var calls = 0;
    final controller = CacheDiagnosticsController<int>(
      load: () async {
        if (calls++ == 0) {
          throw StateError('读取失败');
        }
        return 7;
      },
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.loading, isFalse);
    expect(controller.stats, isNull);
    expect(controller.error, isA<StateError>());

    await controller.refresh();
    expect(controller.stats, 7);
    expect(controller.error, isNull);
  });

  test('dispose 后在途读取不得发布或通知', () async {
    final pending = Completer<int>();
    final controller =
        CacheDiagnosticsController<int>(load: () => pending.future);
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    final refresh = controller.refresh();
    expect(notifications, 1);
    controller.dispose();
    pending.complete(9);
    await refresh;

    expect(notifications, 1);
    expect(controller.stats, isNull);
  });
}
