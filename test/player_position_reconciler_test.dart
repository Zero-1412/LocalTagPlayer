import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:local_tag_player/src/models/player_gpu_capabilities.dart';
import 'package:local_tag_player/src/platform/platform_interfaces.dart';
import 'package:local_tag_player/src/services/player/player_position_reconciler.dart';
import 'package:local_tag_player/src/services/player/player_service.dart';

class _PositionBackend implements PlayerBackend, PlayerInteractiveSeekBoundary {
  _PositionBackend()
      : _positionChanges = StreamController<Duration>.broadcast(sync: true),
        _state = const PlayerBackendState(
          position: Duration.zero,
          duration: Duration(minutes: 2),
          playing: true,
          buffering: false,
          volume: 100,
          videoTrackCount: 1,
          audioTrackCount: 1,
        );

  final StreamController<Duration> _positionChanges;
  PlayerBackendState _state;
  final List<String> commands = <String>[];
  final Completer<void> firstSeekRelease = Completer<void>();
  var blockFirstSeek = true;

  @override
  PlayerBackendState get state => _state;

  @override
  Stream<Duration> get positionChanges => _positionChanges.stream;

  @override
  Stream<bool> get playingChanges => const Stream<bool>.empty();

  @override
  Stream<bool> get completedChanges => const Stream<bool>.empty();

  @override
  Stream<String> get errorChanges => const Stream<String>.empty();

  @override
  ValueListenable<int?> get textureId => ValueNotifier<int?>(null);

  @override
  Future<void> openPath(String path) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {
    commands.add('seek:${position.inSeconds}');
    if (blockFirstSeek) {
      blockFirstSeek = false;
      await firstSeekRelease.future;
    }
  }

  @override
  Future<void> seekInteractive(Duration position) async {
    commands.add('interactive:${position.inSeconds}');
    if (blockFirstSeek) {
      blockFirstSeek = false;
      await firstSeekRelease.future;
    }
  }

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> playOrPause() async {}

  @override
  Future<void> setProperty(String property, String value) async {}

  @override
  Future<String> getProperty(String property) async => 'unavailable';

  @override
  Future<PlayerGpuCapabilityMatrix> queryGpuCapabilities() async =>
      const PlayerGpuCapabilityMatrix.unsupported();

  @override
  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) async => null;

  @override
  Widget buildVideoSurface({
    required Widget controls,
    BoxFit fit = BoxFit.contain,
    double? aspectRatio,
    bool mirror = false,
    bool reserveTopControlArea = false,
    bool reserveBottomControlArea = false,
  }) =>
      controls;

  void emitPosition(Duration position) {
    _state = PlayerBackendState(
      position: position,
      duration: _state.duration,
      playing: _state.playing,
      buffering: _state.buffering,
      volume: _state.volume,
      videoTrackCount: _state.videoTrackCount,
      audioTrackCount: _state.audioTrackCount,
    );
    _positionChanges.add(position);
  }

  @override
  Future<void> dispose() async {
    await _positionChanges.close();
  }

  @override
  Future<void> get released => Future<void>.value();
}

void main() {
  test('seek 目标确认后仍会屏蔽紧随其后的旧位置事件', () {
    var now = DateTime.utc(2026, 8, 16);
    final reconciler = PlayerPositionReconciler(now: () => now);

    reconciler.beginSeek(
      target: const Duration(seconds: 30),
      current: const Duration(seconds: 20),
    );
    expect(reconciler.reconcile(const Duration(seconds: 20)),
        const Duration(seconds: 30));
    expect(reconciler.reconcile(const Duration(seconds: 30)),
        const Duration(seconds: 30));

    now = now.add(const Duration(milliseconds: 500));
    expect(reconciler.reconcile(const Duration(seconds: 20)),
        const Duration(seconds: 30));

    now = now.add(const Duration(seconds: 2));
    expect(reconciler.reconcile(const Duration(seconds: 20)),
        const Duration(seconds: 20));
    expect(reconciler.isPending, isFalse);
  });

  test('PlayerService 串行执行精确与交互式 seek，且位置流不回写旧落点', () async {
    final backend = _PositionBackend();
    final service = PlayerService(backend: backend);
    final positions = <Duration>[];
    final subscription = service.positionChanges.listen(positions.add);
    addTearDown(() async {
      await subscription.cancel();
      await service.dispose();
    });

    final first = service.seekInteractive(const Duration(seconds: 30));
    final second = service.seek(const Duration(seconds: 40));
    await Future<void>.delayed(Duration.zero);
    expect(backend.commands, <String>['interactive:30']);

    backend.firstSeekRelease.complete();
    await first;
    await second;
    expect(
      backend.commands,
      <String>['interactive:30', 'seek:40'],
    );

    backend.emitPosition(const Duration(seconds: 40));
    backend.emitPosition(const Duration(seconds: 30));
    expect(positions,
        <Duration>[const Duration(seconds: 40), const Duration(seconds: 40)]);
    expect(service.state.position, const Duration(seconds: 40));
  });
}
