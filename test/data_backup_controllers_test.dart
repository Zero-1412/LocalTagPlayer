import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/settings/application/data_backup_controllers.dart';

void main() {
  test('备份状态 controller 发布最新事件并在 dispose 后停止通知', () async {
    final statuses = StreamController<int>();
    final controller = DataBackupStatusController<int>(
      initialStatus: 0,
      statuses: statuses.stream,
    );
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    statuses.add(1);
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, 1);
    expect(notifications, 1);

    controller.dispose();
    statuses.add(2);
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, 1);
    expect(notifications, 1);
    await statuses.close();
  });

  test('备份维护命令互斥并在立即备份完成后恢复', () async {
    final gate = Completer<void>();
    var checkCalls = 0;
    final controller = DataBackupMaintenanceController<String>(
      runNow: () => gate.future,
      checkIntegrity: () async {
        checkCalls += 1;
        return 'healthy';
      },
      export: () async => 'backup.json',
    );
    addTearDown(controller.dispose);

    final running = controller.runNow();
    expect(controller.busy, isTrue);
    expect(await controller.checkIntegrity(), isNull);
    expect(checkCalls, 0);

    gate.complete();
    expect(await running, isTrue);
    expect(controller.busy, isFalse);
    expect(await controller.checkIntegrity(), 'healthy');
  });

  test('导出取消与未启动保持不同结果且异常会释放互斥', () async {
    var shouldThrow = false;
    final controller = DataBackupMaintenanceController<String>(
      runNow: () async {},
      checkIntegrity: () async => 'healthy',
      export: () async {
        if (shouldThrow) {
          throw StateError('导出失败');
        }
        return null;
      },
    );
    addTearDown(controller.dispose);

    final cancelled = await controller.export();
    expect(cancelled, isNotNull);
    expect(cancelled?.path, isNull);

    shouldThrow = true;
    await expectLater(controller.export(), throwsStateError);
    expect(controller.busy, isFalse);
  });
}
