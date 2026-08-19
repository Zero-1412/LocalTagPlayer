import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('桌面像素探针保留实际合成、输入与匿名证据合同', () {
    final source =
        File('tool/invoke_player_desktop_pixel_probe.ps1').readAsStringSync();

    // 必须取最终桌面合成像素，不能退化为 Flutter RepaintBoundary 或 mpv 帧号代理。
    expect(source, contains('Win32 GetDC'));
    expect(source, contains('desktop-composited-pixel-change'));
    expect(source, contains('GetPixel'));
    expect(source, contains('StretchBlt'));
    // 输入与采样共用 QPC，并分别保留按下/松开到实际像素变化的延迟。
    expect(source, contains('SendInput'));
    expect(source, contains('SendKeyboardScan'));
    expect(source, contains('inputDownToFirstChangedPixelMs'));
    expect(source, contains('inputUpToFirstChangedPixelMs'));
    // 真实 PlayerPage 拖动必须经 Win32 Down/Move/Up，且在控制条 hover 稳定后才记时。
    expect(source, contains("'progressDrag'"));
    expect(source, contains('PrepareProgressDrag'));
    expect(source, contains('SendProgressDrag'));
    expect(source, contains('PreparePlayerKeyboardFocus'));
    expect(source, contains('FocusPlayerKeyboard'));
    expect(source, contains("'virtualKey'"));
    expect(source, contains('SendKeyboardVirtualKey'));
    // 长按自动化对照只通过显式 HoldMilliseconds 注入；实体 manualLong* 仍不注入。
    expect(source, contains('HoldMilliseconds'));
    // SendInput 未进入 Flutter 键盘链时，不得把超时当作播放器时延。实体模式由
    // FLUTTERVIEW 原生消息记录同一 QPC 锚点，且仍要求 PlayerPage 匿名回执。
    expect(source, contains("'manualForward'"));
    expect(source, contains("'manualLongForward'"));
    expect(source, contains('TryReadNativeKeyboardUpQpc'));
    expect(source, contains('manualHoldSatisfied'));
    expect(source, contains('manual-keyboard-native-qpc'));
    expect(source, contains('WaitForNativeKeyboardDownQpc'));
    // 原生侧车现在同时写 qpcUs/utcUs，探针必须按字段边界解析 qpcUs，不能把后续
    // utcUs 拼进 Int64；否则有真实 WM_KEYDOWN 也会被误报为“未收到实体输入”。
    expect(source, contains('TryReadQpcUs'));
    expect(source, contains('line.IndexOf(\',\', start)'));
    expect(source, contains('manualInputWaitStartedUs'));
    expect(source, contains('excludedIdleUs += Math.Max'));
    expect(source, contains('player_keyboard_semantic_evidence_timeout'));
    expect(source, contains('GetDpiForWindow'));
    expect(source, contains('windowDpi'));
    expect(source, contains(r'windowDpi = $report.windowDpi'));
    expect(source, contains('底部约 90–110 个逻辑 px'));
    expect(source, contains('win32-mouse-drag-progress-track'));
    expect(source, contains('progress_slider_semantic_evidence_timeout'));
    // 播放中自然画面变化不能被误当成 seek 呈现，且采样不足不得静默通过。
    expect(source, contains('RequireStaticBaseline'));
    expect(source, contains('captureRatePassed'));
    expect(source, contains('TryCapture'));
    expect(source, contains('captureReadFailures'));
    expect(source, contains('pixel_capture_unavailable'));
    expect(source, contains('keyboardSemanticRequired'));
    expect(source, contains('player_keyboard_event'));
    expect(source, contains('pixel_change_timeout'));
    // 不得把私有媒体图像或路径写进 QA 证据。
    expect(source, contains('no screenshots retained'));
    expect(source, isNot(contains('Save(')));
  });

  test('专用 QA 对 4K 独立会话保留匿名生命周期分段', () {
    final source =
        File('lib/src/qa/player_desktop_pixel_qa_app.dart').readAsStringSync();

    // ready 前退出必须能区分窗口、Flutter 与 MediaKit 打开阶段，不能由成功样本掩盖。
    expect(source, contains('qa-lifecycle.jsonl'));
    expect(source, contains('bootstrap_started'));
    expect(source, contains('media_open_started'));
    expect(source, contains('paused_baseline_ready'));
    expect(source, contains('paused_surface_baseline_ready'));
    expect(source, contains('shutdown_requested'));
  });

  test('独立矩阵在任一 4K 会话失效时拒绝生成混杂 p95', () {
    final source = File('tool/run_player_desktop_pixel_latency_matrix.ps1')
        .readAsStringSync();

    expect(source, contains('qa-lifecycle.jsonl'));
    expect(source, contains('p95Eligible'));
    expect(source, contains('failedRuns'));
    expect(source, contains('不得生成 p95 结论'));
    expect(source, contains("'progressDrag'"));
    expect(source, contains("'manualForward'"));
    expect(source, contains("'manualLongBackward'"));
    expect(source, contains('manualLongKeyboardAction'));
    expect(source, contains('product-player-page'));
    expect(source, contains('win32-mouse-drag-progress-track'));
    expect(source, contains('manual-keyboard-native-qpc'));
    expect(source, contains('waiting_for_physical_key=true'));
    expect(source, contains('松键并非 seek 提交边界'));
    expect(source, contains('ManualInputTimeoutMilliseconds'));
    expect(source, contains('windowDpi'));
    expect(source, contains('Get-QaRuntimeEvidence'));
    expect(source, contains('backend-runtime-snapshot-not-desktop-pixels'));
    expect(source, contains('voDropFramesMax'));
    expect(source, contains('hwdecCurrentFinal'));
    expect(source, contains('firstFrameEvidence'));
    expect(source, contains('textureGenerationDelta'));
    expect(source, contains('textureRebuildEventCount'));
    expect(source, contains('adaptiveTextureSizingEnabled'));
  });

  test('真实 PlayerPage 动作启动独立页面并要求 Slider 语义回执', () {
    final gate = File('tool/run_player_desktop_pixel_latency_gate.ps1')
        .readAsStringSync();
    final initialization =
        File('lib/src/pages/player/player_state_initialization.dart')
            .readAsStringSync();

    expect(gate, contains("'progressDrag'"));
    expect(gate, contains("'playerFullscreen'"));
    expect(gate, contains("'forward'"));
    expect(gate, contains("'backward'"));
    expect(gate, contains("'manualForward'"));
    expect(gate, contains("'manualLongForward'"));
    expect(gate, contains('LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_HOLD_MODE'));
    expect(gate, contains('ManualLongHoldMinimumMilliseconds'));
    expect(gate, contains('LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_QA'));
    expect(gate, contains('LOCAL_TAG_PLAYER_SEEK_SEGMENT_TRACE_QA'));
    expect(gate, contains('LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_ACTION'));
    expect(gate, contains('LOCAL_TAG_PLAYER_QA_DISABLE_ADAPTIVE_TEXTURE'));
    expect(gate, contains('DisableAdaptiveTextureSizing'));
    expect(gate, contains('NativeKeyboardEvidencePath'));
    expect(gate, contains('ManualInputTimeoutMilliseconds'));
    expect(gate, contains('HoldMilliseconds'));
    expect(gate, contains('LOCAL_TAG_PLAYER_REAL_PAGE_PIXEL_QA'));
    expect(gate, contains("ready.surface -ne 'product-player-page'"));
    expect(gate, contains('ExpectedInputEvidencePath'));
    expect(gate, contains("Join-Path \$Output 'player-input-events.jsonl'"));
    expect(gate, contains('PixelChangeThresholdPercent'));
    expect(gate, contains('player-input-events.jsonl'));
    expect(gate, contains('Write-DesktopPixelTraceCorrelation'));
    expect(gate, contains('desktop-pixel-trace-correlation.json'));
    expect(gate, contains('PlayerInputEvidencePath'));
    expect(gate, contains('playerInputEvents'));
    expect(gate, contains("-like '*keyboard*'"));
    expect(gate, contains('player-page-input-events-in-action-window'));
    expect(gate, contains('traceLinkEvidence'));
    expect(gate, contains('nativeDownQpcUs'));
    expect(gate, contains('native-qpc+player-semantic+unique-trace'));
    expect(gate, contains('trace-correlation-parse-failed'));
    expect(gate, contains('failureLine'));
    expect(gate, contains('桌面像素探针失败：\$probeFailure'));
    expect(gate, contains('desktop-pixel-probe-failure.txt'));
    expect(gate, contains('wall_utc_us'));
    expect(gate, contains('traceWallUtcPrecision'));
    expect(gate, contains('actionTraceSummaries'));
    expect(gate, contains('actionTraceSummaries = @()'));
    expect(gate, contains('\$selectedEvents = @()'));
    expect(gate, contains('先固定为'));
    expect(
      gate,
      contains("StartsWith('snapshot_', [StringComparison]::Ordinal)"),
    );
    expect(gate, contains('runtimeSnapshot'));
    expect(initialization, contains('readSeekTraceRuntimeSnapshot'));
    expect(initialization, contains("'cache_duration_s'"));
    expect(initialization, contains("'texture_generation'"));
    expect(gate, contains('ambiguous-multiple-traces-in-input-window'));
    expect(gate, contains('commandCompleteToFirstChangedPixelMs'));
    expect(gate, contains('utc-input-window-correlation-only'));
    expect(gate, contains('available-native-qpc-utc-window'));
    expect(gate, contains('outside-pixel-action-input-window'));
    expect(gate, contains('ambiguous-overlapping-pixel-action-windows'));
    expect(gate, contains('renderer-events.jsonl'));
    expect(gate, contains('candidateActionCount'));
    expect(gate, contains('causalOrder'));
    expect(gate, contains('PlayerPageInitialWindowWidth = 960'));
    expect(gate, contains('避免右侧常驻队列压缩视频表面'));
  });

  test('Windows runner 的实体键盘 QPC 锚点只在 Debug QA 子窗口记录匿名动作', () {
    final evidence = File('windows/runner/player_qa_keyboard_qpc_evidence.cpp')
        .readAsStringSync();
    final qaSource = File('lib/src/pages/player/player_input_qa_evidence.dart')
        .readAsStringSync();
    final helperSource = File('lib/src/pages/player/player_state_helpers.dart')
        .readAsStringSync();
    final window = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();

    expect(evidence, contains('LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_QA'));
    expect(evidence, contains('LOCAL_TAG_PLAYER_PIXEL_OUTPUT'));
    expect(evidence, contains('SetWindowSubclass'));
    expect(evidence, contains('GetParent(flutter_view_window_)'));
    expect(evidence, contains('kRunnerSubclassId'));
    expect(evidence, contains('WM_KEYDOWN'));
    expect(evidence, contains('QueryPerformanceCounter'));
    expect(evidence, contains('system_clock'));
    expect(evidence, contains('utcUs'));
    expect(evidence, contains('native_keyboard_message'));
    expect(evidence, contains('native_keyboard_observer_ready'));
    expect(qaSource, contains("'phase': safePhase"));
    expect(qaSource, contains("'action': safeAction"));
    expect(helperSource, contains('phase: qaPhase'));
    expect(helperSource, contains('qaAction'));
    expect(evidence, contains('installed'));
    expect(evidence, contains('topLevelActive'));
    expect(evidence, contains('ObserveTopLevelWindowMessage'));
    expect(evidence, contains('lParam'));
    expect(evidence, contains('if (!active_)'));
    expect(evidence, isNot(contains('samplePath')));
    expect(window, contains('PlayerQaKeyboardQpcEvidence'));
    expect(window, contains('ObserveTopLevelWindowMessage'));
    expect(cmake, contains('player_qa_keyboard_qpc_evidence.cpp'));
    final attachIndex = window.indexOf('SetChildContent(');
    final observerIndex = window.indexOf('PlayerQaKeyboardQpcEvidence>');
    expect(attachIndex, greaterThanOrEqualTo(0));
    expect(observerIndex, greaterThan(attachIndex));
  });

  test('真实 PlayerPage Slider 的 QA 回执只在显式 Windows Debug 环境写入', () {
    final evidence = File('lib/src/pages/player/player_input_qa_evidence.dart')
        .readAsStringSync();
    final slider = File('lib/src/pages/player/player_progress_slider.dart')
        .readAsStringSync();

    expect(evidence, contains('kDebugMode'));
    expect(evidence, contains('LOCAL_TAG_PLAYER_PLAYERPAGE_INPUT_QA'));
    expect(evidence, contains('progress_slider_committed'));
    expect(evidence, contains('progress_preview_seek_submitted'));
    expect(evidence, contains('progress_exact_seek_confirmed'));
    expect(evidence, contains('player_keyboard_event'));
    expect(evidence, isNot(contains('previewIdentity')));
    expect(slider, contains('progressSliderDragStarted'));
    expect(slider, contains('progressSliderDragCommitted'));
  });

  test('真实 PlayerPage 像素 QA 只在显式 Debug 入口挂载产品页面且不写用户数据', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final qaSource = File('lib/src/qa/player_real_page_pixel_qa_app.dart')
        .readAsStringSync();

    expect(mainSource, contains('shouldRunPlayerRealPagePixelQa'));
    expect(qaSource, contains('LOCAL_TAG_PLAYER_REAL_PAGE_PIXEL_QA'));
    expect(qaSource, contains("'surface': 'product-player-page'"));
    expect(qaSource, contains('LOCAL_TAG_PLAYER_QA_PROGRESS_DRAG_SEEK_MODE'));
    expect(qaSource, contains('progressDragSeekMode'));
    expect(qaSource, contains('manualKeyboardQa'));
    expect(qaSource, contains('manualKeyboardAction'));
    expect(qaSource, contains('manualKeyboardHoldMode'));
    expect(qaSource, contains('automatedLongHoldQa'));
    expect(qaSource, contains('manual_keyboard_input_waiting'));
    expect(qaSource, contains('manual_long_forward_play_started'));
    expect(qaSource, contains('automated_long_forward_play_started'));
    expect(qaSource, contains('native-keyboard-qpc-events.jsonl'));
    expect(qaSource, contains('manualForwardResumeTimer'));
    expect(qaSource, contains("widget.manualKeyboardHoldMode == 'long'"));
    expect(qaSource, contains("widget.manualKeyboardAction == 'backward'"));
    expect(qaSource, contains('PlayerPage('));
    expect(qaSource,
        contains('onPlaybackProgressUpdated: (_, __, ___, ____) async {}'));
    expect(qaSource, isNot(contains('progress_slider_committed')));
    expect(qaSource, contains('shutdown.request'));
    expect(qaSource, contains('player_resources_released'));
  });

  test('只读 QA 样本选择器优先解析 Windows application-support 目录', () {
    final selector =
        File('tool/select_player_qa_sample.dart').readAsStringSync();

    // 真实应用数据位于 Flutter package 层级时，选择器不能递归扫描整个 AppData
    // 才偶然找到库；该工具仍必须以只读方式打开媒体数据库。
    expect(selector, contains('com.example'));
    expect(selector, contains('local_tag_player'));
    expect(selector, contains('LocalTagPlayer'));
    expect(selector, contains('directCandidate.existsSync()'));
    expect(selector, contains('readOnly: true'));
  });

  test('正式两阶段拖动默认启用，QA 仍可回退为单次精确基线且保持最终精确定位', () {
    final page =
        File('lib/src/pages/player/player_page.dart').readAsStringSync();
    final transport = File('lib/src/pages/player/player_state_transport.dart')
        .readAsStringSync();
    final gate = File('tool/run_player_desktop_pixel_latency_gate.ps1')
        .readAsStringSync();

    expect(page, contains('fastPreviewThenExact,'));
    expect(page, contains('PlayerProgressDragSeekMode progressDragSeekMode;'));
    expect(page, contains('exactOnly,'));
    expect(page, contains('PlayerProgressDragSeekMode.fastPreviewThenExact,'));
    expect(transport, contains('_seekProgressWithFastPreviewThenExact'));
    expect(transport, contains('playerService.seekInteractive(target)'));
    expect(transport, contains('seekExactlyWithDiagnostics(target)'));
    expect(transport, contains('const Duration(milliseconds: 600)'));
    expect(gate, contains('ProgressDragSeekMode'));
    expect(gate, contains('LOCAL_TAG_PLAYER_QA_PROGRESS_DRAG_SEEK_MODE'));
    expect(gate, contains('progress_preview_seek_submitted'));
    expect(gate, contains('progress_exact_seek_confirmed'));
  });
}
