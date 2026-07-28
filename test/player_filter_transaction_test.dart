import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/models/player_filter_transaction.dart';
import 'package:local_tag_player/src/models/player_gpu_capabilities.dart';
import 'package:local_tag_player/src/platform/platform_interfaces.dart';
import 'package:local_tag_player/src/services/player/player_service.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 在内存中模拟同一个播放器实例的属性读写，用于验证事务不会依赖第二个后端。
 */
class _FilterTransactionBackend
    implements PlayerBackend, PlayerPropertyBatchBoundary {
  _FilterTransactionBackend({
    Map<String, String>? initialProperties,
    this.rejectedProperty,
    this.rejectedValue,
    this.normalizeMpvReadback = false,
  }) : properties = <String, String>{...?initialProperties};

  /** 当前唯一后端实例持有的属性。 */
  final Map<String, String> properties;

  /** 可选的故障注入属性。 */
  final String? rejectedProperty;

  /** 仅拒绝该目标值，允许事务恢复旧值。 */
  final String? rejectedValue;

  /** 是否模拟 libmpv 对数值与 lavfi 图的规范化输出。 */
  final bool normalizeMpvReadback;

  /** 记录批量提交顺序，验证去色带主开关最后恢复。 */
  final List<Map<String, String>> batches = <Map<String, String>>[];

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
  Stream<Duration> get positionChanges => const Stream<Duration>.empty();

  @override
  Stream<bool> get playingChanges => const Stream<bool>.empty();

  @override
  Stream<bool> get completedChanges => const Stream<bool>.empty();

  @override
  Stream<String> get errorChanges => const Stream<String>.empty();

  @override
  ValueListenable<int?> get textureId => _textureId;

  @override
  Future<void> setProperties(Map<String, String> properties) async {
    batches.add(Map<String, String>.from(properties));
    for (final entry in properties.entries) {
      await setProperty(entry.key, entry.value);
    }
  }

  @override
  Future<void> setProperty(String property, String value) async {
    if (property == rejectedProperty && value == rejectedValue) {
      return;
    }
    properties[property] = value;
  }

  @override
  Future<String> getProperty(String property) async {
    final value = properties[property];
    if (value == null) return 'unavailable';
    if (normalizeMpvReadback) {
      final number = double.tryParse(value);
      if (number != null &&
          const <String>{
            'deband-threshold',
            'deband-range',
            'deband-grain',
          }.contains(property)) {
        return number.toStringAsFixed(6);
      }
      if (property == 'vf' &&
          value.startsWith('lavfi=[') &&
          value.endsWith(']')) {
        final graph = value.substring(7, value.length - 1);
        return 'lavfi=graph=%${graph.length}%$graph';
      }
    }
    return value.isEmpty ? 'empty' : value;
  }

  @override
  Future<void> openPath(String path) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> playOrPause() async {}

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

  @override
  Future<void> dispose() async => _textureId.dispose();

  @override
  Future<void> get released => Future<void>.value();
}

void main() {
  test('同一后端滤镜快照写入后完成逐项读回验证', () async {
    final backend = _FilterTransactionBackend(
      initialProperties: const <String, String>{
        'deband': 'no',
        'deband-threshold': '16',
        'vf': '',
      },
      normalizeMpvReadback: true,
    );
    final service = PlayerService(backend: backend);

    final result = await service.applyFilterProperties(
      label: 'cpu-filter-snapshot',
      properties: const <String, String>{
        'deband-threshold': '24',
        'vf': 'lavfi=[deblock]',
        'deband': 'yes',
      },
    );

    expect(result.phase, PlayerFilterTransactionPhase.applied);
    expect(result.verifiedPropertyCount, 3);
    expect(result.mismatchedProperties, isEmpty);
    expect(result.rollbackAttempted, isFalse);
    expect(backend.properties['vf'], 'lavfi=[deblock]');
    expect(service.filterTransaction.sequence, 1);
  });

  test('滤镜读回不一致时恢复旧快照并验证回滚', () async {
    final backend = _FilterTransactionBackend(
      initialProperties: const <String, String>{
        'deband': 'yes',
        'deband-threshold': '16',
        'vf': 'lavfi=[old]',
      },
      rejectedProperty: 'vf',
      rejectedValue: 'lavfi=[broken]',
    );
    final service = PlayerService(backend: backend);

    final result = await service.applyFilterProperties(
      label: 'nvidia-filter-snapshot',
      properties: const <String, String>{
        'deband-threshold': '24',
        'vf': 'lavfi=[broken]',
        'deband': 'no',
      },
    );

    expect(result.phase, PlayerFilterTransactionPhase.rolledBack);
    expect(result.mismatchedProperties, const <String>['vf']);
    expect(result.rollbackAttempted, isTrue);
    expect(result.rollbackVerified, isTrue);
    expect(result.failureCode, 'filter_readback_mismatch');
    expect(backend.properties['vf'], 'lavfi=[old]');
    expect(backend.properties['deband-threshold'], '16');
    expect(backend.properties['deband'], 'yes');
    expect(backend.batches[1], const <String, String>{'deband': 'no'});
    expect(backend.batches.last, const <String, String>{'deband': 'yes'});
  });
}
