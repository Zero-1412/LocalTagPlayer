import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/player/application/player_seek_coordinator.dart';

void main() {
  test('连续 seek 首次立即提交并按节流周期追踪最新累计目标', () async {
    final firstSubmission = Completer<void>();
    final submitted = <Duration>[];
    final delays = <Duration>[];
    var position = Duration.zero;
    var first = true;
    final coordinator = PlayerSeekCoordinator(
      submit: (target) async {
        submitted.add(target);
        if (first) {
          first = false;
          await firstSubmission.future;
        }
        position = target;
      },
      readPosition: () => position,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
      delay: (duration) async => delays.add(duration),
    );

    final worker = coordinator.request(const Duration(seconds: 5));
    expect(submitted, const <Duration>[Duration(seconds: 5)]);

    coordinator.request(const Duration(seconds: 10));
    coordinator.request(const Duration(seconds: 15));
    coordinator.requestRelative(const Duration(seconds: 5));
    expect(
      coordinator.latestRequestedTarget,
      const Duration(seconds: 20),
    );

    firstSubmission.complete();
    await worker;

    expect(
      submitted,
      const <Duration>[
        Duration(seconds: 5),
        Duration(seconds: 20),
      ],
    );
    expect(
      delays.where((duration) => duration > Duration.zero),
      isNotEmpty,
    );
    expect(coordinator.isRunning, isFalse);
    expect(coordinator.latestRequestedTarget, isNull);
  });

  test('seek 目标始终约束在当前媒体时长内', () async {
    final submitted = <Duration>[];
    var position = Duration.zero;
    final coordinator = PlayerSeekCoordinator(
      submit: (target) async {
        submitted.add(target);
        position = target;
      },
      readPosition: () => position,
      readDuration: () => const Duration(seconds: 30),
      isExiting: () => false,
      onLatency: (_) {},
      minimumDispatchInterval: Duration.zero,
    );

    await coordinator.request(const Duration(seconds: -4));
    await coordinator.request(const Duration(seconds: 45));

    expect(
      submitted,
      const <Duration>[
        Duration.zero,
        Duration(seconds: 30),
      ],
    );
  });

  test('长按快进跨短工作器持续节流并提交最终累计目标', () async {
    final submitted = <Duration>[];
    final submittedAt = <Duration>[];
    final clock = Stopwatch()..start();
    var position = Duration.zero;
    final coordinator = PlayerSeekCoordinator(
      submit: (target) async {
        submitted.add(target);
        submittedAt.add(clock.elapsed);
        position = target;
      },
      readPosition: () => position,
      readDuration: () => const Duration(minutes: 3),
      isExiting: () => false,
      onLatency: (_) {},
      minimumDispatchInterval: const Duration(milliseconds: 60),
    );

    Future<void> latest =
        coordinator.requestRelative(const Duration(seconds: 5));
    for (var index = 1; index < 10; index++) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      latest = coordinator.requestRelative(const Duration(seconds: 5));
    }
    await latest;

    expect(submitted.first, const Duration(seconds: 5));
    expect(submitted.last, const Duration(seconds: 50));
    expect(submitted.length, lessThan(10));
    for (var index = 1; index < submittedAt.length; index++) {
      expect(
        submittedAt[index] - submittedAt[index - 1],
        greaterThanOrEqualTo(const Duration(milliseconds: 50)),
      );
    }
  });
}
