import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/models/player_gpu_capabilities.dart';
import 'package:local_tag_player/src/platform/platform_interfaces.dart';
import 'package:local_tag_player/src/services/player/player_property_verifier.dart';

// ignore_for_file: slash_for_doc_comments

/** 属性验证测试使用的最小运行时，不创建播放器或原生纹理。 */
class _PropertyRuntime implements PlayerRuntimeAccess {
  final ValueNotifier<int?> _textureId = ValueNotifier<int?>(null);
  final Map<String, String> properties = <String, String>{};

  /** 指定写入异常；其它属性仍可用于确认部分写入没有被冒充成完整成功。 */
  String? throwingWrite;

  /** 指定读回异常，模拟原生属性查询失败。 */
  String? throwingRead;

  /** 指定读回覆盖值，模拟 libmpv 未接受目标属性。 */
  final Map<String, String> readOverrides = <String, String>{};

  @override
  PlayerBackendState get state => const PlayerBackendState(
        position: Duration.zero,
        duration: Duration.zero,
        playing: false,
        buffering: false,
        volume: 100,
        videoTrackCount: 0,
        audioTrackCount: 0,
      );

  @override
  ValueListenable<int?> get textureId => _textureId;

  @override
  Future<void> setProperty(String property, String value) async {
    if (property == throwingWrite) throw StateError('write');
    properties[property] = value;
  }

  @override
  Future<String> getProperty(String property) async {
    if (property == throwingRead) throw StateError('read');
    return readOverrides[property] ?? properties[property] ?? 'unavailable';
  }

  @override
  Future<PlayerGpuCapabilityMatrix> queryGpuCapabilities() async =>
      const PlayerGpuCapabilityMatrix.unsupported();
}

void main() {
  test('全部属性写入并读回一致才报告已生效', () async {
    final runtime = _PropertyRuntime();
    final result = await PlayerPropertyVerifier.apply(
      backend: runtime,
      label: 'test-feature',
      properties: const <String, String>{
        'scale': 'lanczos',
        'scaler-resizes-only': 'yes',
      },
    );

    expect(result.applied, isTrue);
    expect(result.verifiedPropertyCount, 2);
    expect(result.statusLabel, '属性已读回确认');
  });

  test('读回不一致保留属性名且不冒充成功', () async {
    final runtime = _PropertyRuntime()..readOverrides['scale'] = 'bilinear';
    final result = await PlayerPropertyVerifier.apply(
      backend: runtime,
      label: 'test-feature',
      properties: const <String, String>{'scale': 'lanczos'},
    );

    expect(result.applied, isFalse);
    expect(result.failureCode, 'property_readback_mismatch');
    expect(result.mismatchedProperties, const <String>['scale']);
  });

  test('原生读回异常被归一为功能失败而不逃逸到播放流程', () async {
    final runtime = _PropertyRuntime()..throwingRead = 'scale';
    final result = await PlayerPropertyVerifier.apply(
      backend: runtime,
      label: 'test-feature',
      properties: const <String, String>{'scale': 'lanczos'},
    );

    expect(result.applied, isFalse);
    expect(result.supported, isFalse);
    expect(result.failureCode, 'property_unavailable');
  });
}
