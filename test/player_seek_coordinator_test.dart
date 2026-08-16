import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/player/application/player_seek_coordinator.dart';

void main() {
  test('后端 seek 已超过节流窗口时不会再追加一个完整间隔', () async {
    final submitted = <Duration>[];
    final delays = <Duration>[];
    var first = true;
    final coordinator = PlayerSeekCoordinator(
      submit: (target) async {
        submitted.add(target);
        if (first) {
          first = false;
          // 模拟长 GOP 的一次交互式 seek；命令本身已覆盖 64ms 节流窗口。
          await Future<void>.delayed(const Duration(milliseconds: 90));
        }
      },
      readPosition: () => Duration.zero,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
      minimumDispatchInterval: const Duration(milliseconds: 64),
      confirmationTimeout: Duration.zero,
      delay: (duration) async {
        delays.add(duration);
        await Future<void>.delayed(duration);
      },
    );

    final worker = coordinator.request(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    coordinator.request(const Duration(seconds: 20));
    await worker;

    expect(
      submitted,
      const <Duration>[Duration(seconds: 10), Duration(seconds: 20)],
    );
    expect(delays, isEmpty);
  });

  test('长 GOP 代理仅降低当前会话预览频率并放宽最终新帧阈值', () {
    final throttle = PlayerSeekGopAdaptiveThrottle();

    expect(throttle.minimumDispatchInterval, const Duration(milliseconds: 64));
    expect(
      throttle.finalPresentationTimeout,
      const Duration(milliseconds: 750),
    );

    throttle.recordPreviewLatency(200);
    expect(throttle.minimumDispatchInterval, const Duration(milliseconds: 96));
    expect(
      throttle.finalPresentationTimeout,
      const Duration(milliseconds: 1200),
    );

    throttle.recordPreviewLatency(400);
    expect(throttle.minimumDispatchInterval, const Duration(milliseconds: 125));
    expect(
      throttle.finalPresentationTimeout,
      const Duration(milliseconds: 1800),
    );
  });

  test('长按重复步长低档保持细腻且高档限制为 5 秒', () {
    expect(playerKeyboardSeekRepeatStepSeconds(1), 1);
    expect(playerKeyboardSeekRepeatStepSeconds(5), 2);
    expect(playerKeyboardSeekRepeatStepSeconds(10), 4);
    expect(playerKeyboardSeekRepeatStepSeconds(30), 5);
    expect(
      PlayerSeekCoordinator.defaultMinimumDispatchInterval,
      const Duration(milliseconds: 64),
    );
  });

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

  test('鼠标快速连续点击只保留正在执行目标之后的最新落点', () async {
    final firstSubmission = Completer<void>();
    final submitted = <Duration>[];
    var first = true;
    final coordinator = PlayerSeekCoordinator(
      submit: (target) async {
        submitted.add(target);
        if (first) {
          first = false;
          await firstSubmission.future;
        }
      },
      readPosition: () => Duration.zero,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
      minimumDispatchInterval: Duration.zero,
      confirmationTimeout: Duration.zero,
    );

    final firstClick = coordinator.request(const Duration(seconds: 10));
    coordinator.request(const Duration(seconds: 20));
    coordinator.request(const Duration(seconds: 30));

    expect(submitted, const <Duration>[Duration(seconds: 10)]);
    firstSubmission.complete();
    await firstClick;

    expect(
      submitted,
      const <Duration>[Duration(seconds: 10), Duration(seconds: 30)],
    );
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

  test('键盘长按只预览累计目标并在 KeyUp 后精确收敛一次', () async {
    final previews = <Duration>[];
    var position = Duration.zero;
    final coordinator = PlayerSeekCoordinator(
      submit: (target) async => previews.add(target),
      readPosition: () => position,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
      minimumDispatchInterval: Duration.zero,
      confirmationTimeout: Duration.zero,
    );
    final keyboard = PlayerKeyboardSeekController(
      coordinator: coordinator,
      readPosition: () => position,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
    );

    expect(
      keyboard.requestRelative(const Duration(seconds: 5)),
      const Duration(seconds: 5),
    );
    expect(
      keyboard.requestRelative(const Duration(seconds: 5)),
      const Duration(seconds: 10),
    );
    expect(
      keyboard.requestRelative(const Duration(seconds: 5)),
      const Duration(seconds: 15),
    );
    expect(keyboard.target, const Duration(seconds: 15));
    await keyboard.settlePreview();

    expect(
      previews,
      const <Duration>[
        Duration(seconds: 5),
        Duration(seconds: 15),
      ],
    );
    expect(keyboard.isActive, isFalse);
  });

  test('键盘短按不发送预览并只在 KeyUp 精确 seek 一次', () async {
    final previews = <Duration>[];
    var position = const Duration(seconds: 20);
    final coordinator = PlayerSeekCoordinator(
      submit: (target) async => previews.add(target),
      readPosition: () => position,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
      minimumDispatchInterval: Duration.zero,
      confirmationTimeout: Duration.zero,
    );
    final keyboard = PlayerKeyboardSeekController(
      coordinator: coordinator,
      readPosition: () => position,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
    );

    expect(
      keyboard.requestRelative(
        const Duration(seconds: 5),
        mutePreview: false,
      ),
      const Duration(seconds: 25),
    );
    await keyboard.settlePreview();

    expect(previews, const <Duration>[Duration(seconds: 25)]);
    expect(position, const Duration(seconds: 20));
  });

  test('短按关键帧预览落回原关键帧后由 KeyUp 精确收敛', () async {
    final previews = <Duration>[];
    final exactTargets = <Duration>[];
    var position = const Duration(seconds: 20);
    final coordinator = PlayerSeekCoordinator(
      submit: (target) async {
        previews.add(target);
        // 模拟长 GOP：25 秒的交互式关键帧预览仍落在 20 秒关键帧。
        position = Duration(seconds: (target.inSeconds ~/ 10) * 10);
      },
      readPosition: () => position,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
      minimumDispatchInterval: Duration.zero,
      confirmationTimeout: Duration.zero,
    );
    final keyboard = PlayerKeyboardSeekController(
      coordinator: coordinator,
      readPosition: () => position,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
      exactSubmit: (target) async {
        exactTargets.add(target);
        position = target;
      },
    );

    expect(
      keyboard.requestRelative(
        const Duration(seconds: 5),
        isRepeat: false,
        mutePreview: false,
      ),
      const Duration(seconds: 25),
    );
    await keyboard.settlePreview();

    expect(previews, const <Duration>[Duration(seconds: 25)]);
    expect(exactTargets, const <Duration>[Duration(seconds: 25)]);
    expect(position, const Duration(seconds: 25));
  });

  test('键盘长按从短按累积目标开始提交关键帧预览', () async {
    final previews = <Duration>[];
    final exactTargets = <Duration>[];
    var position = Duration.zero;
    final coordinator = PlayerSeekCoordinator(
      submit: (target) async => previews.add(target),
      readPosition: () => position,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
      minimumDispatchInterval: Duration.zero,
      confirmationTimeout: Duration.zero,
    );
    final keyboard = PlayerKeyboardSeekController(
      coordinator: coordinator,
      readPosition: () => position,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
      exactSubmit: (target) async => exactTargets.add(target),
    );

    keyboard.requestRelative(
      const Duration(seconds: 5),
      isRepeat: false,
      mutePreview: false,
    );
    keyboard.requestRelative(
      const Duration(seconds: 2),
      isRepeat: true,
      mutePreview: true,
    );
    await keyboard.settlePreview();

    expect(
        previews, const <Duration>[Duration(seconds: 5), Duration(seconds: 7)]);
    expect(exactTargets, isEmpty);
  });

  test('新会话取消会阻止上一轮迟到 KeyUp 覆盖位置', () async {
    final firstPreview = Completer<void>();
    var first = true;
    final coordinator = PlayerSeekCoordinator(
      submit: (_) async {
        if (first) {
          first = false;
          await firstPreview.future;
        }
      },
      readPosition: () => Duration.zero,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
      minimumDispatchInterval: Duration.zero,
      confirmationTimeout: Duration.zero,
    );
    final keyboard = PlayerKeyboardSeekController(
      coordinator: coordinator,
      readPosition: () => Duration.zero,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
    );

    keyboard.requestRelative(const Duration(seconds: 5));
    final oldKeyUp = keyboard.settlePreview();
    keyboard.cancel();
    firstPreview.complete();
    await oldKeyUp;

    expect(keyboard.target, isNull);
  });
  test('播放中精确 seek 在落点完成后才恢复音频', () async {
    final commands = <String>[];
    final gate = PlayerSeekAudioGate(
      readDesiredVolume: () => 80,
      setVolume: (value) async => commands.add('volume:$value'),
      readPresentedFrame: () async {
        commands.add('capture-final-baseline');
        return 10;
      },
      waitForNewFrame: (_, __) async {
        commands.add('frame-presented');
        return true;
      },
      framePresentationTimeout: () => const Duration(milliseconds: 750),
      isExiting: () => false,
    );

    await gate.run<void>(() async => commands.add('seek-confirmed'));

    expect(
      commands,
      <String>[
        'volume:0.0',
        'seek-confirmed',
        'capture-final-baseline',
        'frame-presented',
        'volume:80.0'
      ],
    );
    expect(gate.isActive, isFalse);
  });

  test('精确落点没有新视频帧证据时保持临时静音', () async {
    final commands = <String>[];
    final gate = PlayerSeekAudioGate(
      readDesiredVolume: () => 80,
      setVolume: (value) async => commands.add('volume:$value'),
      readPresentedFrame: () async {
        commands.add('capture-final-baseline');
        return 10;
      },
      waitForNewFrame: (_, __) async => false,
      framePresentationTimeout: () => const Duration(milliseconds: 750),
      isExiting: () => false,
    );

    await gate.run<void>(() async => commands.add('seek-confirmed'));

    expect(
      commands,
      <String>['volume:0.0', 'seek-confirmed', 'capture-final-baseline'],
    );
  });

  test('用户原本暂停时 seek 不得静默自动播放', () async {
    final commands = <String>[];
    final gate = PlayerSeekAudioGate(
      readDesiredVolume: () => 0,
      setVolume: (value) async => commands.add('volume:$value'),
      readPresentedFrame: () async {
        commands.add('capture-final-baseline');
        return 10;
      },
      waitForNewFrame: (_, __) async => true,
      framePresentationTimeout: () => const Duration(milliseconds: 750),
      isExiting: () => false,
    );

    await gate.run<void>(() async => commands.add('seek-confirmed'));

    expect(commands, <String>['seek-confirmed']);
  });

  test('键盘长按临时静音后预览，精确落点新帧交付后再恢复声音', () async {
    final commands = <String>[];
    var position = Duration.zero;
    final gate = PlayerSeekAudioGate(
      readDesiredVolume: () => 35,
      setVolume: (value) async => commands.add('volume:$value'),
      readPresentedFrame: () async {
        commands.add('capture-final-baseline');
        return 10;
      },
      waitForNewFrame: (_, __) async {
        commands.add('frame-presented');
        return true;
      },
      framePresentationTimeout: () => const Duration(milliseconds: 750),
      isExiting: () => false,
    );
    final coordinator = PlayerSeekCoordinator(
      submit: (target) async {
        commands.add('preview:${target.inSeconds}');
        position = target;
      },
      readPosition: () => position,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
      minimumDispatchInterval: Duration.zero,
      confirmationTimeout: Duration.zero,
    );
    final keyboard = PlayerKeyboardSeekController(
      coordinator: coordinator,
      readPosition: () => position,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
      previewAudioGate: gate,
    );

    keyboard.requestRelative(const Duration(seconds: 5));
    await keyboard.settlePreview();

    expect(
      commands,
      <String>[
        'volume:0.0',
        'preview:5',
        'capture-final-baseline',
        'frame-presented',
        'volume:35.0',
      ],
    );
  });

  test('KeyUp、精确 seek、新视频帧和音频恢复共用单调 trace', () async {
    final lines = <String>[];
    final trace = PlayerSeekTraceLogger(
      output: lines.add,
      wallClock: () => DateTime.utc(2026, 8, 4),
    );
    final gate = PlayerSeekAudioGate(
      readDesiredVolume: () => 35,
      setVolume: (_) async {},
      readPresentedFrame: () async => 10,
      waitForNewFrame: (_, __) async => true,
      framePresentationTimeout: () => const Duration(milliseconds: 750),
      isExiting: () => false,
      readFrameEvidence: () => 'native-rendered-texture',
      trace: trace,
    );
    final coordinator = PlayerSeekCoordinator(
      submit: (_) async {},
      readPosition: () => Duration.zero,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
      minimumDispatchInterval: Duration.zero,
      confirmationTimeout: Duration.zero,
    );
    final keyboard = PlayerKeyboardSeekController(
      coordinator: coordinator,
      readPosition: () => Duration.zero,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
      previewAudioGate: gate,
      trace: trace,
    );

    keyboard.requestRelative(const Duration(seconds: 5));
    await keyboard.settlePreview();

    expect(
      lines.map((line) => RegExp(r'stage=([^ ]+)').firstMatch(line)!.group(1)),
      <String>[
        'key_up',
        'keyframe_seek_complete',
        'new_video_frame',
        'audio_restore_start',
        'audio_restore_complete',
      ],
    );
    for (final line in lines) {
      expect(line, contains('PLAYER_SEEK_TRACE trace=1 mono_us='));
      expect(line, contains('wall_utc_ms=1785801600000'));
      if (line.contains('stage=new_video_frame')) {
        expect(line, contains('frame_evidence=native-rendered-texture'));
      }
    }
  });

  test('进度条 seek 记录同一单调时钟下的首个原生渲染帧', () async {
    final lines = <String>[];
    final trace = PlayerSeekTraceLogger(
      output: lines.add,
      wallClock: () => DateTime.utc(2026, 8, 7),
    );
    var frameReadCount = 0;
    final coordinator = PlayerSeekCoordinator(
      submit: (_) async {},
      readPosition: () => Duration.zero,
      readDuration: () => const Duration(minutes: 2),
      isExiting: () => false,
      onLatency: (_) {},
      minimumDispatchInterval: Duration.zero,
      confirmationTimeout: Duration.zero,
      trace: trace,
      readPresentedFrame: () async {
        frameReadCount++;
        return frameReadCount == 1 ? 20 : 21;
      },
      readFrameEvidence: () => 'native-rendered-texture',
    );

    await coordinator.request(const Duration(seconds: 12));
    await Future<void>.delayed(const Duration(milliseconds: 1));

    expect(
      lines.map((line) => RegExp(r'stage=([^ ]+)').firstMatch(line)!.group(1)),
      <String>[
        'seek_submit_start',
        'seek_command_complete',
        'native_rendered_frame',
      ],
    );
    final frameLine = lines.singleWhere(
      (line) => line.contains('stage=native_rendered_frame'),
    );
    expect(frameLine, contains('frame_number=21'));
    expect(frameLine, contains('frame_evidence=native-rendered-texture'));
    expect(frameLine, contains('seek_to_frame_us='));
  });
}
