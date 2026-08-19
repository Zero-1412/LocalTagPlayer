import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('稳定性矩阵消费当前首帧阶段并保留反向运行态 trace', () {
    final script =
        File('tool/run_player_backend_stability_matrix.ps1').readAsStringSync();
    final docs =
        File('docs/qa/player_seek_latency_matrix.md').readAsStringSync();

    // 当前 coordinator 的首帧阶段不再只有历史 new_video_frame；报告必须覆盖实际
    // Texture 复制证据、兼容回退证据和超时，否则矩阵会把真实样本统计成零。
    expect(script, contains('native_rendered_frame'));
    expect(script, contains('presented_frame_fallback'));
    expect(script, contains('native_rendered_frame_timeout'));
    final gate = File(
      'integration_test/player_seek_latency_gate_test.dart',
    ).readAsStringSync();
    expect(gate, contains('native-rendered-child-hwnd'));
    expect(gate, contains('native-rendered-texture'));
    expect(gate, contains('usesChildHwnd'));
    final interfaces =
        File('lib/src/platform/platform_interfaces.dart').readAsStringSync();
    final service =
        File('lib/src/services/player/player_service.dart').readAsStringSync();
    final transport = File('lib/src/pages/player/player_state_transport.dart')
        .readAsStringSync();
    expect(interfaces, contains('PlayerFramePresentationEvidenceBoundary'));
    expect(service, contains('framePresentationEvidenceKind'));
    expect(transport, contains('native-rendered-output-unknown'));
    expect(script, contains('Get-SeekLatencyTrace'));
    expect(script, contains('Get-ReverseDirectionExperiment'));
    expect(script, contains('qaReverseKeyframeTrace'));
    expect(script, contains('qaReverseDirectionExperiment'));
    expect(script, contains('reverseKeyframeTrace'));
    expect(gate, contains('segmentTrace'));
    expect(gate, contains('unavailable-in-integration-test'));
    expect(gate, contains('requiresDesktopPixelCorrelation'));
    expect(gate, contains('smoothScanTrace'));
    expect(gate, contains('_summarizeSmoothScanTrace'));
    expect(gate, contains('maxCacheDurationAtStopCompleteS'));
    expect(gate, contains('maxTotalDropFramesAtStopComplete'));
    expect(gate, contains('readScanTraceSnapshot'));
    expect(gate, contains('backend-runtime-snapshot-not-desktop-pixels'));
    expect(gate, contains('LOCAL_TAG_PLAYER_REVERSE_DIRECTION_QA'));
    expect(gate, contains('reverseDirectionExperiment'));
    expect(gate, contains('play-direction'));
    expect(gate, contains('decreasing-position-observed'));
    expect(gate, contains('restoredDirectionMatches'));
    expect(script, contains(r'Set-Content -LiteralPath $reportPath'));
    expect(script, contains('Get-StabilityFailureCategory'));
    expect(script, contains("status = 'failed-no-report'"));
    expect(script, contains('failureCategory'));
    // 矩阵必须把当前显示器的原生分辨率、刷新率和逻辑 DPI 写入证据，
    // 但同时明确这只是 inventory，不能替代真实跨屏移动。
    expect(script, contains('Get-DisplayInventory'));
    expect(script, contains('refreshRateHz'));
    expect(script, contains('logicalDpi'));
    expect(script, contains('display-inventory-only'));
    expect(script, contains('physicalWindowMoveConfirmed'));
    expect(script, contains('displayInventory'));
    final integration = File(
      'integration_test/player_backend_stability_matrix_test.dart',
    ).readAsStringSync();
    expect(integration, contains('Future.wait<void>(pendingSeeks'));
    expect(integration, contains('seekFailureCount'));
    expect(integration, contains('立即挂接错误处理'));
    expect(integration, contains('duration > const Duration(seconds: 2)'));
    expect(docs, contains('qaReverseKeyframeTrace'));
    expect(docs, contains('runtimeDeltas.cache'));
    expect(docs, contains('segmentTrace'));
  });
}
