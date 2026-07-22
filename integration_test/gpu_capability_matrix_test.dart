import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/src/app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 通过真实 PlayerBackend 和 Windows runner 保存显卡能力矩阵。
 *
 * 测试不打开媒体，也不读取用户媒体库；输出只包含设备能力和当前进程显存预算。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows PlayerBackend reports a verifiable GPU device matrix',
      (tester) async {
    final backend = WindowsNativePlayerBackend();
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
          const JsonEncoder.withIndent('  ').convert(matrix.toJson()),
          flush: true,
        );
      }
    } finally {
      await backend.dispose();
      await backend.released;
    }
  });
}
