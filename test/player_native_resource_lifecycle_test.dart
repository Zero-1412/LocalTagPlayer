import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/player/application/player_fullscreen_lifecycle_controller.dart';
import 'package:local_tag_player/src/services/player/player_resource_lifecycle_coordinator.dart';

void main() {
  test('播放器资源只沿一条固定顺序释放且重复调用共享 Future', () async {
    final calls = <String>[];
    final textureId = ValueNotifier<int?>(null);
    var textureReadyCount = 0;
    var releasedCount = 0;
    final coordinator = PlayerResourceLifecycleCoordinator(
      textureId: textureId,
      cancelBackendEvents: () async => calls.add('cancel-events'),
      stop: () async => calls.add('stop'),
      disposeResource: () async => calls.add('dispose'),
      awaitReleased: () async => calls.add('released'),
      logStage: (
        stage, {
        required readEngineProperties,
      }) async =>
          calls.add('log:$stage:$readEngineProperties'),
      onTextureReady: () => textureReadyCount++,
      onReleased: (_) => releasedCount++,
    );

    textureId.value = 7;
    textureId.value = 9;
    expect(textureReadyCount, 1);

    final first = coordinator.release();
    final second = coordinator.release();
    expect(identical(first, second), isTrue);
    await first;

    expect(
      calls,
      <String>[
        'log:dispose_started:true',
        'cancel-events',
        'stop',
        'log:stop_acknowledged:true',
        'dispose',
        'released',
        'log:player_disposed:false',
      ],
    );
    expect(releasedCount, 1);

    // listener 已由 coordinator 解绑，释放后纹理变化不能再发布诊断。
    textureId.value = 11;
    expect(textureReadyCount, 1);
    textureId.dispose();
  });

  test('stop 失败仍继续 dispose/released 并完成 Route 协调信号', () async {
    final calls = <String>[];
    final textureId = ValueNotifier<int?>(1);
    final coordinator = PlayerResourceLifecycleCoordinator(
      textureId: textureId,
      cancelBackendEvents: () async => calls.add('cancel-events'),
      stop: () async {
        calls.add('stop-failed');
        throw StateError('expected');
      },
      disposeResource: () async => calls.add('dispose'),
      awaitReleased: () async => calls.add('released'),
      logStage: (
        stage, {
        required readEngineProperties,
      }) async =>
          calls.add('log:$stage'),
      onTextureReady: () {},
      onStopFailed: (_) => calls.add('stop-error-reported'),
      onReleased: (_) => calls.add('route-released'),
    );

    await coordinator.release();

    expect(
      calls,
      containsAllInOrder(<String>[
        'cancel-events',
        'stop-failed',
        'stop-error-reported',
        'dispose',
        'released',
        'log:player_release_failed',
        'route-released',
      ]),
    );
    expect(coordinator.releaseFailed, isTrue);
    expect(coordinator.releaseFailureStage, 'stop');
    textureId.dispose();
  });

  test('dispose 抛错仍等待 released、报告失败并发送最终 Route 信号', () async {
    final calls = <String>[];
    final textureId = ValueNotifier<int?>(1);
    final coordinator = PlayerResourceLifecycleCoordinator(
      textureId: textureId,
      cancelBackendEvents: () async => calls.add('cancel-events'),
      stop: () async => calls.add('stop'),
      disposeResource: () async {
        calls.add('dispose-failed');
        throw StateError('expected');
      },
      awaitReleased: () async => calls.add('released'),
      logStage: (
        stage, {
        required readEngineProperties,
      }) async =>
          calls.add('log:$stage'),
      onTextureReady: () {},
      onReleaseFailed: (stage, _) => calls.add('release-error:$stage'),
      onReleased: (_) => calls.add('route-released'),
    );

    await coordinator.release();

    expect(
      calls,
      containsAllInOrder(<String>[
        'dispose-failed',
        'release-error:dispose',
        'released',
        'log:player_release_failed',
        'route-released',
      ]),
    );
    textureId.dispose();
  });

  test('释放 dispose/released 各自超时并保留失败阶段，不永久挂起', () async {
    final calls = <String>[];
    final failures = <String>[];
    final textureId = ValueNotifier<int?>(1);
    final coordinator = PlayerResourceLifecycleCoordinator(
      textureId: textureId,
      cancelBackendEvents: () async => calls.add('cancel-events'),
      stop: () async => calls.add('stop'),
      disposeResource: () async {
        calls.add('dispose-started');
        await Completer<void>().future;
      },
      awaitReleased: () async {
        calls.add('released-wait');
        await Completer<void>().future;
      },
      disposeTimeout: const Duration(milliseconds: 10),
      releasedTimeout: const Duration(milliseconds: 10),
      logStage: (
        stage, {
        required readEngineProperties,
      }) async =>
          calls.add('log:$stage'),
      onTextureReady: () {},
      onReleaseFailed: (stage, _) => failures.add(stage),
      onReleased: (_) => calls.add('route-released'),
    );

    await coordinator.release();

    expect(failures, <String>['dispose', 'released']);
    expect(calls, contains('log:player_release_failed'));
    expect(calls, contains('route-released'));
    textureId.dispose();
  });

  test('事件取消和诊断日志卡住时也有界并继续完成释放', () async {
    final calls = <String>[];
    final failures = <String>[];
    final textureId = ValueNotifier<int?>(1);
    final never = Completer<void>().future;
    final coordinator = PlayerResourceLifecycleCoordinator(
      textureId: textureId,
      cancelBackendEvents: () => never,
      stop: () async => calls.add('stop'),
      disposeResource: () async => calls.add('dispose'),
      awaitReleased: () async => calls.add('released'),
      stageTimeout: const Duration(milliseconds: 10),
      logStage: (
        stage, {
        required readEngineProperties,
      }) async {
        if (stage == 'dispose_started') {
          await never;
        }
        calls.add('log:$stage');
      },
      onTextureReady: () {},
      onReleaseFailed: (stage, _) => failures.add(stage),
      onReleased: (_) => calls.add('route-released'),
    );

    await coordinator.release();

    expect(failures, contains('diagnostic:dispose_started'));
    expect(failures, contains('cancel-events'));
    expect(
        calls,
        containsAllInOrder(<String>[
          'stop',
          'dispose',
          'released',
          'route-released',
        ]));
    expect(coordinator.releaseFailed, isTrue);
    textureId.dispose();
  });

  test('全屏切换先发布过渡帧再执行窗口命令并更新会话', () async {
    final calls = <String>[];
    final session = PlayerFullscreenSessionController();
    late PlayerFullscreenLifecycleController controller;
    controller = PlayerFullscreenLifecycleController(
      session: session,
      onChanged: () => calls.add(
        'changed:${controller.transitionInProgress}:'
        '${controller.isFullscreen}',
      ),
    );

    await controller.toggle(
      beforeWindowCommand: () async => calls.add('end-of-frame'),
      canExecuteWindowCommand: () => true,
      setFullscreen: (fullscreen) async =>
          calls.add('set-fullscreen:$fullscreen'),
    );

    expect(
      calls,
      <String>[
        'changed:true:false',
        'end-of-frame',
        'set-fullscreen:true',
        'changed:false:true',
      ],
    );
    expect(session.shouldOpenFullscreen, isTrue);
  });

  test('Route 卸载后拒绝迟到全屏命令且不污染会话偏好', () async {
    final calls = <String>[];
    final session = PlayerFullscreenSessionController();
    final controller = PlayerFullscreenLifecycleController(
      session: session,
      onChanged: () => calls.add('changed'),
    );

    await controller.toggle(
      beforeWindowCommand: () async => calls.add('end-of-frame'),
      canExecuteWindowCommand: () => false,
      setFullscreen: (_) async => calls.add('unexpected-window-command'),
    );

    expect(calls, <String>['changed', 'end-of-frame', 'changed']);
    expect(controller.transitionInProgress, isFalse);
    expect(controller.isFullscreen, isFalse);
    expect(session.shouldOpenFullscreen, isFalse);
  });

  test('全屏恢复幂等且失败会清除跨 Route 偏好', () async {
    final session = PlayerFullscreenSessionController()
      ..recordPlayerFullscreen(true);
    var attempts = 0;
    final errors = <String>[];
    final controller = PlayerFullscreenLifecycleController(
      session: session,
      onChanged: () {},
    );

    final first = controller.restoreSession(
      enterFullscreen: () async {
        attempts++;
        throw StateError('expected');
      },
      reportError: (code, _) => errors.add(code),
    );
    final second = controller.restoreSession(
      enterFullscreen: () async => attempts++,
      reportError: (code, _) => errors.add(code),
    );
    expect(identical(first, second), isTrue);
    await first;

    expect(attempts, 1);
    expect(errors, <String>['restore_failed']);
    expect(controller.isFullscreen, isFalse);
    expect(session.shouldOpenFullscreen, isFalse);
  });

  test('退出全屏保留会话偏好并按 windowed 后 maximize 的顺序恢复', () async {
    final calls = <String>[];
    final session = PlayerFullscreenSessionController()
      ..recordPlayerFullscreen(true);
    final controller = PlayerFullscreenLifecycleController(
      session: session,
      onChanged: () => calls.add('changed'),
    );
    await controller.restoreSession(
      enterFullscreen: () async => calls.add('restore-fullscreen'),
      reportError: (_, __) {},
    );

    await controller.prepareForExit(
      queryFullscreen: () async {
        calls.add('query');
        return true;
      },
      setWindowed: () async => calls.add('windowed'),
      maximize: () async => calls.add('maximize'),
      reportError: (_, __) {},
    );

    expect(
      calls,
      <String>[
        'restore-fullscreen',
        'windowed',
        'maximize',
        'changed',
      ],
    );
    expect(controller.isFullscreen, isFalse);
    expect(session.shouldOpenFullscreen, isTrue);
  });
}
