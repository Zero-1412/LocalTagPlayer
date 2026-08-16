import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/player/application/player_backend_event_bridge.dart';
import 'package:local_tag_player/src/features/player/application/player_open_request_controller.dart';

void main() {
  test('更新 stable-ID 请求拒绝旧 open 成功和失败结果', () {
    final controller = PlayerOpenRequestController();

    expect(
      controller.request((videoId: 'video-1', path: 'old.mp4')),
      isTrue,
    );
    controller.beginDrain();
    final oldRequest = controller.takePending()!;

    expect(
      controller.request((videoId: 'video-2', path: 'new.mp4')),
      isFalse,
    );
    expect(controller.hasSuperseded(oldRequest), isTrue);
    expect(controller.markSuccess(oldRequest), isFalse);
    expect(
      controller.markFailure(oldRequest, code: 'old_error'),
      isFalse,
    );
    expect(controller.hasFailure, isFalse);

    final latestRequest = controller.takePending()!;
    expect(latestRequest.videoId, 'video-2');
    expect(latestRequest.path, 'new.mp4');
    expect(controller.markSuccess(latestRequest), isTrue);
  });

  test('即时 missing 失败使运行中的旧请求失效并可按稳定身份重试', () {
    final controller = PlayerOpenRequestController();

    controller.request((videoId: 'video-old', path: 'old.mp4'));
    controller.beginDrain();
    final oldRequest = controller.takePending()!;
    controller.markImmediateFailure(
      (videoId: 'video-missing', path: 'missing.mp4'),
      code: 'missing_media',
    );

    expect(controller.hasSuperseded(oldRequest), isTrue);
    expect(controller.hasPending, isFalse);
    expect(controller.failedVideoId, 'video-missing');
    expect(controller.failureCode, 'missing_media');
    controller.finishDrain(keepOpening: false);
    expect(controller.retryFailure(), isTrue);
    final retry = controller.takePending()!;
    expect(retry.videoId, 'video-missing');
    expect(retry.path, 'missing.mp4');
  });

  test('取消推进请求代次并清理页面状态', () {
    final controller = PlayerOpenRequestController();
    controller.request((videoId: 'video-1', path: 'one.mp4'));
    controller.beginDrain();
    final request = controller.takePending()!;

    controller.cancel();

    expect(controller.hasSuperseded(request), isTrue);
    expect(controller.isOpening, isFalse);
    expect(controller.hasPending, isFalse);
    expect(controller.hasFailure, isFalse);
  });

  test('backend event bridge 统一转发并幂等取消四类订阅', () async {
    final completed = StreamController<bool>.broadcast();
    final errors = StreamController<String>.broadcast();
    final positions = StreamController<Duration>.broadcast();
    final playing = StreamController<bool>.broadcast();
    addTearDown(() async {
      await completed.close();
      await errors.close();
      await positions.close();
      await playing.close();
    });
    final received = <Object>[];
    final bridge = PlayerBackendEventBridge(
      completedChanges: completed.stream,
      errorChanges: errors.stream,
      positionChanges: positions.stream,
      playingChanges: playing.stream,
      onCompleted: (value) => received.add(value),
      onError: (value) => received.add(value),
      onPosition: (value) => received.add(value),
      onPlayingChanged: (value) => received.add(value),
    );

    completed.add(true);
    errors.add('safe_error');
    positions.add(const Duration(seconds: 3));
    playing.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(
      received,
      <Object>[
        true,
        'safe_error',
        const Duration(seconds: 3),
        false,
      ],
    );

    final firstDispose = bridge.dispose();
    final secondDispose = bridge.dispose();
    expect(identical(firstDispose, secondDispose), isTrue);
    await firstDispose;
    expect(bridge.isDisposed, isTrue);

    completed.add(false);
    errors.add('late_error');
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(4));
  });

  test('backend event bridge 重绑后只转发带指定 generation 的媒体事件', () async {
    final completed = StreamController<bool>.broadcast();
    final errors = StreamController<String>.broadcast();
    final positions = StreamController<Duration>.broadcast();
    final playing = StreamController<bool>.broadcast();
    addTearDown(() async {
      await completed.close();
      await errors.close();
      await positions.close();
      await playing.close();
    });
    final received = <String>[];
    final bridge = PlayerBackendEventBridge(
      completedChanges: completed.stream,
      errorChanges: errors.stream,
      positionChanges: positions.stream,
      playingChanges: playing.stream,
      onCompleted: (_) {},
      onError: (_) {},
      onPosition: (_) {},
      onPlayingChanged: (_) {},
      onCompletedWithGeneration: (value, generation) =>
          received.add('completed:$value:$generation'),
      onErrorWithGeneration: (value, generation) =>
          received.add('error:$value:$generation'),
      onPositionWithGeneration: (value, generation) =>
          received.add('position:${value.inSeconds}:$generation'),
    );

    await bridge.rebind(generation: 7);
    completed.add(true);
    errors.add('late-safe-error');
    positions.add(const Duration(seconds: 9));
    await Future<void>.delayed(Duration.zero);

    expect(
      received,
      <String>[
        'completed:true:7',
        'error:late-safe-error:7',
        'position:9:7',
      ],
    );
    await bridge.dispose();
  });
}
