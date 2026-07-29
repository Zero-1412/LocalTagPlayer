import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/core/playback_settings.dart';
import 'package:local_tag_player/src/features/settings/application/playback_settings_controller.dart';

void main() {
  test('普通播放设置立即发布并按调用顺序持久化', () async {
    final writes = <PlaybackSettings>[];
    final firstGate = Completer<void>();
    final controller = PlaybackSettingsController(
      initialSettings: PlaybackSettings.defaults,
      save: (settings) async {
        writes.add(settings);
        if (writes.length == 1) {
          await firstGate.future;
        }
      },
    );
    addTearDown(controller.dispose);
    final first =
        controller.settings.copyWith(fullscreenQueueEdgeHoverEnabled: false);
    final second =
        first.copyWith(resumeBehavior: PlaybackResumeBehavior.restart);

    final firstWrite = controller.update(first);
    final secondWrite = controller.update(second);

    expect(controller.settings, same(second));
    await Future<void>.delayed(Duration.zero);
    expect(writes, <PlaybackSettings>[first]);
    firstGate.complete();
    await Future.wait(<Future<void>>[firstWrite, secondWrite]);
    expect(writes, <PlaybackSettings>[first, second]);
  });

  test('当前写入失败会回滚，旧写入失败不会覆盖较新设置', () async {
    final firstGate = Completer<void>();
    var writeCount = 0;
    final controller = PlaybackSettingsController(
      initialSettings: PlaybackSettings.defaults,
      save: (_) async {
        writeCount += 1;
        if (writeCount == 1) {
          await firstGate.future;
          throw StateError('旧写入失败');
        }
      },
    );
    addTearDown(controller.dispose);
    final first = controller.settings.copyWith(hwdec: 'no');
    final second = first.copyWith(hwdec: 'auto');

    final staleWrite = controller.update(first);
    final latestWrite = controller.update(second);
    firstGate.complete();
    await expectLater(staleWrite, throwsStateError);
    await latestWrite;

    expect(controller.settings, same(second));
  });

  test('没有后续修改时写入失败恢复上一快照', () async {
    final initial = PlaybackSettings.defaults;
    final controller = PlaybackSettingsController(
      initialSettings: initial,
      save: (_) async => throw StateError('保存失败'),
    );
    addTearDown(controller.dispose);
    final next = initial.copyWith(hwdec: 'no');

    await expectLater(controller.update(next), throwsStateError);

    expect(controller.settings, same(initial));
  });

  test('连续写入失败时恢复最后一次成功持久化快照', () async {
    final initial = PlaybackSettings.defaults;
    final controller = PlaybackSettingsController(
      initialSettings: initial,
      save: (_) async => throw StateError('保存失败'),
    );
    addTearDown(controller.dispose);
    final first = initial.copyWith(hwdec: 'no');
    final second = first.copyWith(hwdec: 'auto');

    final firstWrite = controller.update(first);
    final secondWrite = controller.update(second);
    await expectLater(firstWrite, throwsStateError);
    await expectLater(secondWrite, throwsStateError);

    expect(controller.settings, same(initial));
  });
}
