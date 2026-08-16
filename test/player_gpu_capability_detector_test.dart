import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/models/player_gpu_capabilities.dart';
import 'package:local_tag_player/src/platform/platform_interfaces.dart';
import 'package:local_tag_player/src/services/player/player_gpu_capability_detector.dart';

class _BlockingGpuRuntime implements PlayerRuntimeAccess {
  final ValueNotifier<int?> _textureId = ValueNotifier<int?>(1);
  final Completer<String> propertyResult = Completer<String>();

  @override
  PlayerBackendState get state => const PlayerBackendState(
        position: Duration.zero,
        duration: Duration(minutes: 1),
        playing: true,
        buffering: false,
        volume: 100,
        videoTrackCount: 1,
        audioTrackCount: 1,
      );

  @override
  Future<String> getProperty(String property) => propertyResult.future;

  @override
  Future<PlayerGpuCapabilityMatrix> queryGpuCapabilities() async =>
      const PlayerGpuCapabilityMatrix.unsupported();

  @override
  Future<void> setProperty(String property, String value) async {}

  @override
  ValueListenable<int?> get textureId => _textureId;
}

class _ImmediateGpuRuntime implements PlayerRuntimeAccess {
  var propertyCalls = 0;
  final ValueNotifier<int?> _textureId = ValueNotifier<int?>(1);

  @override
  PlayerBackendState get state => const PlayerBackendState(
        position: Duration.zero,
        duration: Duration(minutes: 1),
        playing: true,
        buffering: false,
        volume: 100,
        videoTrackCount: 1,
        audioTrackCount: 1,
      );

  @override
  Future<String> getProperty(String property) async {
    propertyCalls++;
    return 'unavailable';
  }

  @override
  Future<PlayerGpuCapabilityMatrix> queryGpuCapabilities() async =>
      const PlayerGpuCapabilityMatrix.unsupported();

  @override
  Future<void> setProperty(String property, String value) async {}

  @override
  ValueListenable<int?> get textureId => _textureId;
}

void main() {
  test('GPU 探测有总超时，不让单个原生属性查询永久阻塞调用方', () async {
    final runtime = _BlockingGpuRuntime();
    addTearDown(runtime._textureId.dispose);

    await expectLater(
      const PlayerGpuCapabilityDetector().detect(
        runtime,
        timeout: Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('GPU 探测在稳定身份失效后停止继续读取后续属性', () async {
    final runtime = _ImmediateGpuRuntime();
    addTearDown(runtime._textureId.dispose);

    await expectLater(
      const PlayerGpuCapabilityDetector().detect(
        runtime,
        shouldCancel: () => runtime.propertyCalls > 0,
      ),
      throwsA(isA<PlayerGpuCapabilityProbeCancelled>()),
    );
    expect(runtime.propertyCalls, 1);
  });
}
