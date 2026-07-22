import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/src/app.dart';
import 'package:media_kit/media_kit.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 通过真实 PlayerBackend 和 Windows runner 保存显卡能力矩阵。
 *
 * 测试不打开媒体，也不读取用户媒体库；MediaKit 只创建真实渲染纹理以返回活动
 * adapter LUID，随后显式运行绑定该 LUID 的 1080p/4K Compute 帧预算。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows PlayerBackend reports a verifiable GPU device matrix',
      (tester) async {
    MediaKit.ensureInitialized();
    final backend = MediaKitPlayerBackend(
      hwdec: 'auto-safe',
      enableHardwareAcceleration: true,
    );
    try {
      final matrix = await backend.queryGpuCapabilities();
      expect(matrix.platformSupported, isTrue);
      expect(matrix.probeStatus, 'ready', reason: matrix.errorCode);
      expect(matrix.adapters, isNotEmpty);
      expect(
          matrix.adapters.where((adapter) => !adapter.isSoftware), isNotEmpty);
      for (final adapter in matrix.adapters) {
        expect(adapter.name, isNotEmpty);
        expect(adapter.vendorId, greaterThan(0));
        expect(adapter.deviceId, greaterThan(0));
        expect(adapter.dedicatedVideoMemoryBytes, greaterThanOrEqualTo(0));
        expect(adapter.sharedSystemMemoryBytes, greaterThanOrEqualTo(0));
        expect(adapter.d3dFeatureLevel, isNot('unavailable'));
      }

      PlayerGpuActiveAdapter active =
          const PlayerGpuActiveAdapter.unsupported();
      for (var attempt = 0; attempt < 100; attempt++) {
        active = await backend.queryActiveGpuAdapter();
        if (active.ready) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(active.probeStatus, 'ready', reason: active.errorCode);
      final selected = matrix.adapters
          .where((adapter) => adapter.luid == active.adapterLuid)
          .toList(growable: false);
      expect(selected, hasLength(1));

      final computeBudget =
          await backend.benchmarkGpuComputeFrameBudget(active.adapterLuid!);
      expect(computeBudget.probeStatus, 'ready',
          reason: computeBudget.errorCode);
      expect(computeBudget.samples, hasLength(2));
      expect(
        computeBudget.samples.map((sample) => sample.resolutionLabel),
        containsAll(<String>['1920x1080', '3840x2160']),
      );

      await PlayerHdrMappingExperiment.apply(
        backend: backend,
        enabled: true,
      );
      expect(await backend.getProperty('tone-mapping'), 'hable');
      expect(await backend.getProperty('hdr-compute-peak'), 'yes');
      await PlayerHdrMappingExperiment.apply(
        backend: backend,
        enabled: false,
      );
      expect(await backend.getProperty('tone-mapping'), 'auto');
      expect(await backend.getProperty('hdr-compute-peak'), 'auto');

      const definedOutputPath = String.fromEnvironment(
        'LTP_GPU_MATRIX_OUTPUT',
      );
      final outputPath = definedOutputPath.isNotEmpty
          ? definedOutputPath
          : Platform.environment['LOCAL_TAG_PLAYER_GPU_MATRIX_OUTPUT'];
      if (outputPath != null && outputPath.trim().isNotEmpty) {
        final output = File(outputPath);
        await output.parent.create(recursive: true);
        await output.writeAsString(
          const JsonEncoder.withIndent('  ').convert(<String, Object?>{
            'matrix': matrix.toJson(),
            'activeAdapter': active.toJson(),
            'computeFrameBudget': computeBudget.toJson(),
            'hdrExperimentRollbackVerified': true,
          }),
          flush: true,
        );
      }
    } finally {
      await backend.dispose();
      await backend.released;
    }
  });
}
