import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_tag_player/src/pages/player/player_hardware_decode_fallback_banner.dart';

void main() {
  test('软件解码确认向用户提供安全的重新打开恢复动作', () {
    final source = File('lib/src/pages/player/player_state_health.dart')
        .readAsStringSync();
    final viewSource =
        File('lib/src/pages/player/player_state_view.dart').readAsStringSync();
    final bannerSource = File(
      'lib/src/pages/player/player_hardware_decode_fallback_banner.dart',
    ).readAsStringSync();

    expect(source, contains('_showSoftwareDecodeRecoveryNotice'));
    expect(source, contains('当前视频已回退为软件解码'));
    expect(source, contains('retryAfterSoftwareDecodeFallback'));
    expect(source, contains("label: '重新打开'"));
    // 恢复必须重新进入已有 latest-only open worker，而不是对当前 NativePlayer 热切换。
    expect(source, contains('requestOpenCurrent();'));
    expect(source, contains('不在正在播放的 NativePlayer 上热改'));
    expect(source, isNot(contains("setMpvProperty('hwdec'")));
    // Snackbar 会自动消失；页面必须把确认状态固定挂载到视频表面，并保留只读诊断入口。
    expect(source, contains('rebuild(() {});'));
    expect(viewSource,
        contains('softwareDecodeConfirmed && !openRequests.isOpening'));
    expect(viewSource, contains('PlayerHardwareDecodeFallbackBanner'));
    final diagnosticsSource =
        File('lib/src/pages/player/player_state_diagnostics.dart')
            .readAsStringSync();
    expect(diagnosticsSource, contains('framePresentationEvidenceKind'));
    expect(diagnosticsSource, contains('softwareDecodeConfirmed'));
    expect(diagnosticsSource, contains('consecutiveSoftwareDecodeSamples/3'));
    expect(bannerSource, contains('player.hardwareDecodeFallback.banner'));
    expect(bannerSource, contains('player.hardwareDecodeFallback.retry'));
    expect(bannerSource, contains('player.hardwareDecodeFallback.diagnostics'));
    expect(bannerSource, contains(r'请求 $requestedHwdec'));
    expect(bannerSource, contains('confirmedSamples'));
    expect(source, contains('LOCAL_TAG_PLAYER_QA_AUTO_RETRY_SOFTWARE_DECODE'));
    expect(source, contains('softwareDecodeAutoRetryTriggered'));
  });

  test('Debug QA 强制软件解码与自动恢复只留在隔离入口', () {
    final qaSource =
        File('lib/src/qa/player_real_page_pixel_qa_app.dart').readAsStringSync();
    final gateSource = File(
      'tool/run_player_desktop_pixel_latency_gate.ps1',
    ).readAsStringSync();
    expect(qaSource, contains('LOCAL_TAG_PLAYER_QA_FORCE_SOFTWARE_DECODE'));
    expect(qaSource, contains('forceSoftwareDecodeForQa'));
    expect(qaSource, contains('forcedSoftwareDecodeQa'));
    expect(gateSource, contains('ForceSoftwareDecode'));
    expect(gateSource, contains('AutoRetrySoftwareDecode'));
  });

  testWidgets('持久降级条挂载安全恢复与诊断动作', (tester) async {
    var retryCount = 0;
    var diagnosticsCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: PlayerHardwareDecodeFallbackBanner(
                onRetry: () => retryCount++,
                onDiagnostics: () => diagnosticsCount++,
                requestedHwdec: 'd3d11va-copy',
                actualHwdec: 'no',
                confirmedSamples: 3,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('player.hardwareDecodeFallback.banner')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('player.hardwareDecodeFallback.retry')),
    );
    await tester.tap(
      find.byKey(
        const ValueKey('player.hardwareDecodeFallback.diagnostics'),
      ),
    );
    expect(retryCount, 1);
    expect(diagnosticsCount, 1);
  });
}
