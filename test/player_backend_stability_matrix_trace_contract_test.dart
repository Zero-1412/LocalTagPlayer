import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter Windows 隔离门禁排除用户文件并消费完整 seek baseline', () {
    final compatibility = File(
      'tool/run_flutter_windows_compatibility_gate.ps1',
    ).readAsStringSync();
    final baseline = File(
      'tool/prepare_player_seek_latency_baseline.ps1',
    ).readAsStringSync();
    final seekMatrix = File(
      'tool/run_player_seek_latency_matrix.ps1',
    ).readAsStringSync();

    // 隔离门禁不得在当前工作树运行 pub/build；除本任务的两个门禁脚本外，
    // 用户未跟踪文件不能进入副本。
    expect(compatibility, contains('git -C \$repositoryRoot ls-files'));
    expect(compatibility, contains('untrackedUserFilesExcluded = \$true'));
    expect(compatibility, contains('includedUntrackedGateFiles = \$gateFiles'));
    expect(compatibility, contains('workspace.Length -gt 55'));
    expect(compatibility, contains('ExpectedFrameworkRevision'));
    expect(compatibility, contains("'build', 'windows', '--debug'"));
    expect(compatibility, contains("'build', 'windows', '--release'"));
    expect(compatibility, contains('-Backend mediaKit'));
    expect(
        compatibility, contains("releaseTexturePerformance = 'not-measured'"));
    expect(compatibility, contains('VerifiedDependencyCache'));
    expect(compatibility, contains('Get-FileHash -LiteralPath \$source'));
    expect(compatibility, contains("'mpv.7z' = '72b1b348"));

    // 本机路径只留在 ignored manifest；可提交脚本和摘要必须保留路径脱敏与身份复核。
    expect(baseline, contains("status = 'complete'"));
    expect(baseline, contains('stdoutOmitsMediaPaths = \$true'));
    expect(baseline, contains('lastWriteUnixMilliseconds'));
    expect(baseline, contains('explicit-local-calibration'));
    expect(baseline, contains('calibratedBudgetOverrides'));
    expect(seekMatrix, contains('sampleIdentity'));
    expect(seekMatrix, contains('manifestSha256'));
    expect(seekMatrix, contains('samplePathsOmitted = \$true'));
    expect(seekMatrix, contains('PreflightOnly'));
    expect(seekMatrix, contains('MaxAttemptsPerCase'));
    expect(seekMatrix, contains('CaseCooldownSeconds'));
    expect(seekMatrix, contains('existingMetric.budgetMs'));
    expect(seekMatrix,
        contains('if (\$Resume -and (Test-Path -LiteralPath \$logPath'));
    expect(seekMatrix, contains('\$case.id).attempt-\$attempt.log'));
    expect(seekMatrix, contains('Copy-Item -LiteralPath \$attemptLogPath'));
    expect(seekMatrix, contains('attempts = \$attemptCount'));
  });

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
