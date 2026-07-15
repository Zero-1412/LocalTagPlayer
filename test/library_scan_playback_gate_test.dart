import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/services/library/library_scan_playback_gate.dart';

void main() {
  test('播放动作开始前暂停扫描并在退出后恢复', () async {
    final events = <String>[];
    await const LibraryScanPlaybackGate().run<void>(
      scanActive: true,
      scanAlreadyPaused: false,
      setPaused: (paused) async => events.add(paused ? 'pause' : 'resume'),
      onPauseChanged: (paused) =>
          events.add(paused ? 'ui-paused' : 'ui-resumed'),
      action: () async => events.add('play'),
    );
    expect(
        events, <String>['ui-paused', 'pause', 'play', 'resume', 'ui-resumed']);
  });

  test('用户已手动暂停时播放结束不会擅自恢复扫描', () async {
    final events = <String>[];
    await const LibraryScanPlaybackGate().run<void>(
      scanActive: true,
      scanAlreadyPaused: true,
      setPaused: (paused) async => events.add(paused.toString()),
      action: () async => events.add('play'),
    );
    expect(events, <String>['play']);
  });

  test('播放器抛出异常仍恢复自动暂停的扫描', () async {
    final pausedStates = <bool>[];
    await expectLater(
      const LibraryScanPlaybackGate().run<void>(
        scanActive: true,
        scanAlreadyPaused: false,
        setPaused: (paused) async => pausedStates.add(paused),
        action: () async => throw StateError('player failed'),
      ),
      throwsStateError,
    );
    expect(pausedStates, <bool>[true, false]);
  });
}
