import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/src/app.dart';
import 'package:local_tag_player/src/features/player/application/player_fullscreen_lifecycle_controller.dart';
import 'package:media_kit/media_kit.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 使用同一组匿名真实片源验证 MediaKit 与 Windows MPV 的稳定性矩阵。
 *
 * 本测试覆盖正式 PlayerPage 的全屏状态机、latest-request 快速切换链、DPI metrics
 * 重算和长播诊断；真实跨显示器移动由外层矩阵脚本单独标记，单显示器环境不能冒充通过。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('播放器后端稳定性矩阵', (tester) async {
    final backendName =
        Platform.environment['LOCAL_TAG_PLAYER_STABILITY_BACKEND']?.trim();
    final outputPath =
        Platform.environment['LOCAL_TAG_PLAYER_STABILITY_OUTPUT']?.trim();
    final samplePaths =
        (Platform.environment['LOCAL_TAG_PLAYER_STABILITY_SAMPLES'] ?? '')
            .split('|')
            .map((path) => path.trim())
            .where((path) => path.isNotEmpty)
            .toList(growable: false);
    final longPlaySeconds = int.tryParse(
          Platform.environment['LOCAL_TAG_PLAYER_STABILITY_LONG_SECONDS'] ?? '',
        ) ??
        1800;
    final rapidSwitchCount = int.tryParse(
          Platform.environment['LOCAL_TAG_PLAYER_STABILITY_SWITCHES'] ?? '',
        ) ??
        18;
    final maxDroppedFrames = int.tryParse(
          Platform.environment[
                  'LOCAL_TAG_PLAYER_STABILITY_MAX_DROPPED_FRAMES'] ??
              '',
        ) ??
        5;
    final physicalDpiStatus = Platform
            .environment['LOCAL_TAG_PLAYER_STABILITY_PHYSICAL_DPI_STATUS'] ??
        'not-run';

    if (backendName != 'mediaKit' && backendName != 'mpv') {
      throw StateError('稳定性矩阵后端必须是 mediaKit 或 mpv');
    }
    if (outputPath == null || outputPath.isEmpty) {
      throw StateError('稳定性矩阵缺少输出目录');
    }
    if (samplePaths.length < 3 ||
        samplePaths.any((path) => !File(path).existsSync())) {
      throw StateError('稳定性矩阵至少需要三段存在的匿名真实片源');
    }
    if (longPlaySeconds < 10 || rapidSwitchCount < 6) {
      throw StateError('稳定性矩阵的长播至少 10 秒，快速切换至少 6 次');
    }

    final usesMpv = backendName == 'mpv';
    if (!usesMpv) {
      MediaKit.ensureInitialized();
    }
    final outputDirectory = Directory(outputPath)..createSync(recursive: true);
    File('${outputDirectory.path}\\process.pid')
        .writeAsStringSync(pid.toString(), flush: true);
    final ffmpegBackend = DesktopFFmpegBackend();
    final thumbnailService = ThumbnailService.forDirectory(
      Directory('${outputDirectory.path}\\thumbnail-cache'),
      ffmpegBackend,
    );
    final items = <VideoItem>[
      for (var index = 0; index < samplePaths.length; index++)
        VideoItem(
          videoId: 'stability-${index + 1}',
          path: samplePaths[index],
          title: '匿名稳定性样本 ${index + 1}',
          folder: 'isolated-player-stability',
          tags: const <String>{'QA'},
          addedAt: DateTime.utc(2026, 7, 28),
        ),
    ];
    final settings = PlaybackSettings.defaults.copyWith(
      rendererPreference: usesMpv
          ? PlayerRendererPreference.windowsLibmpv
          : PlayerRendererPreference.mediaKit,
      hwdec: usesMpv ? 'd3d11va' : PlaybackSettings.defaults.hwdec,
      compressionEnhancementMode: PlayerCompressionEnhancementMode.off,
      darkSceneEnhancementEnabled: false,
      hdrDynamicToneMappingExperimentEnabled: false,
    );
    final backend = usesMpv
        ? WindowsNativePlayerBackend(mode: 'mpv')
        : MediaKitPlayerBackend(
            hwdec: PlayerHardwareAcceleration.resolve(settings.hwdec),
            enableHardwareAcceleration: settings.hardwareDecodingEnabled,
          );
    final playerKey = GlobalKey<PlayerPageState>();
    final disposalCompleter = Completer<void>();

    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          key: playerKey,
          initialItem: items.first,
          playlist: items,
          thumbnailService: thumbnailService,
          playbackSettings: settings,
          onPlaybackSettingsChanged: (_) async {},
          activeTags: const <String>['QA'],
          activeChildTag: null,
          queueTitle: '双后端稳定性矩阵',
          onDeleteVideo: (_, __) async {},
          onToggleFavorite: (_) async {},
          onRenameFile: (_, __) async {},
          onEditManualTags: (_) async {},
          onRelinkMissing: (_) async => false,
          onPlaybackProgressUpdated: (_, __, ___, ____) async {},
          onMediaDetailsUpdated: (_, __, ___) async {},
          disposalCompleter: disposalCompleter,
          fileSystem: const DesktopFileSystemAdapter(),
          playerServiceFactory: ({
            required String hwdec,
            required bool enableHardwareAcceleration,
            required PlayerRendererPreference rendererPreference,
          }) =>
              PlayerService(backend: backend),
          mediaProbeBackendFactory: () =>
              createMediaProbeBackend(ffmpegBackend),
          fullscreenSessionController: PlayerFullscreenSessionController(),
        ),
      ),
    );

    await _waitForOpenedVideo(
      tester,
      playerKey,
      items.first.videoId,
      const Duration(seconds: 45),
    );
    await backend.setProperty('loop-file', 'inf');
    await _pumpContinuously(tester, const Duration(seconds: 2));
    if (usesMpv) {
      await _waitForBackendProperty(
        tester,
        backend,
        'hwdec-current',
        'd3d11va-copy',
        const Duration(seconds: 15),
      );
    }
    // 在任何队列切换前锁定首个真实片源的色彩链，避免后续样本覆盖用户关心的
    // source/output 范围；只记录枚举属性，不记录媒体路径或其它隐私信息。
    final initialColorPipeline = <String, Object?>{
      'sourceLevels': await backend.getProperty('video-params/colorlevels'),
      'sourceMatrix': await backend.getProperty('video-params/colormatrix'),
      'outputLevels': await backend.getProperty('video-output-levels'),
      'targetLevels':
          await backend.getProperty('video-target-params/colorlevels'),
    };
    final originalQueue =
        playerKey.currentState!.buildStabilitySnapshotForTest().sourceVideoIds;

    final fullscreen = await _runFullscreenScenario(
      tester,
      playerKey,
      backend,
    );
    final queueComposition = await _runQueueCompositionScenario(
      tester,
      playerKey,
      backend,
    );
    final interactionPerformance = await _runInteractionPerformanceScenario(
      tester,
      playerKey,
      backend,
    );
    final dpi = await _runDpiScenario(
      tester,
      playerKey,
      backend,
      physicalStatus: physicalDpiStatus,
    );
    final rapidSwitch = await _runRapidSwitchScenario(
      tester,
      playerKey,
      items,
      rapidSwitchCount,
      originalQueue,
    );
    await backend.setProperty('loop-file', 'inf');
    final longPlay = await _runLongPlayScenario(
      tester,
      playerKey,
      backend,
      seconds: longPlaySeconds,
      maxDroppedFrames: maxDroppedFrames,
      originalQueue: originalQueue,
    );

    final automatedPass = <Map<String, Object?>>[
      fullscreen,
      queueComposition,
      interactionPerformance,
      dpi,
      rapidSwitch,
      longPlay,
    ].every((scenario) => scenario['automatedPass'] == true);
    final physicalDpiPassed = physicalDpiStatus == 'passed';
    final report = <String, Object?>{
      'schemaVersion': 1,
      'platform': 'windows',
      'playerBackend': backendName,
      'rendererPreference': settings.rendererPreference.name,
      'actualHwdec': await backend.getProperty('hwdec-current'),
      'initialColorPipeline': initialColorPipeline,
      'sampleCount': items.length,
      'automatedPass': automatedPass,
      'releaseGate': automatedPass && physicalDpiPassed
          ? 'passed'
          : automatedPass
              ? 'pending-physical-cross-dpi'
              : 'failed',
      'scenarios': <String, Object?>{
        'fullscreen': fullscreen,
        'queueComposition': queueComposition,
        'interactionPerformance': interactionPerformance,
        'crossDpi': dpi,
        'rapidSwitch': rapidSwitch,
        'longPlayback': longPlay,
      },
    };
    await File('${outputDirectory.path}\\$backendName-stability.json')
        .writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );

    expect(automatedPass, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await disposalCompleter.future.timeout(const Duration(seconds: 15));
  }, timeout: const Timeout(Duration(minutes: 40)));
}

/** 等待真实后端属性达到目标值，避免把配置请求误当成硬解已经生效。 */
Future<void> _waitForBackendProperty(
  WidgetTester tester,
  PlayerBackend backend,
  String property,
  String expected,
  Duration timeout,
) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 100));
    if (await backend.getProperty(property) == expected) return;
  }
  throw StateError(
    '等待 $property=$expected 超时，实际 ${await backend.getProperty(property)}',
  );
}

/**
 * 通过正式窗口状态机完成两次全屏往返，并确认后端会话与 filtered queue 均未丢失。
 */
Future<Map<String, Object?>> _runFullscreenScenario(
  WidgetTester tester,
  GlobalKey<PlayerPageState> playerKey,
  PlayerBackend backend,
) async {
  final state = playerKey.currentState!;
  final before = backend.state.position.inMilliseconds;
  const cycles = 6;
  for (var index = 0; index < cycles; index++) {
    await state.toggleWindowFullscreenForStressTest();
    await _pumpContinuously(tester, const Duration(milliseconds: 250));
    expect(state.buildStabilitySnapshotForTest().windowFullscreen, isTrue);
    expect(
      find.byKey(const ValueKey<String>('player.video.surface')),
      findsOneWidget,
    );
    await state.toggleWindowFullscreenForStressTest();
    await _pumpContinuously(tester, const Duration(milliseconds: 250));
    expect(state.buildStabilitySnapshotForTest().windowFullscreen, isFalse);
  }
  await state.toggleWindowFullscreenForStressTest();
  await _pumpContinuously(tester, const Duration(milliseconds: 350));
  state.toggleQueueVisibilityForStressTest();
  await _pumpContinuously(tester, const Duration(milliseconds: 350));
  final fullscreenQueueVisible = find
      .byKey(const ValueKey<String>('player.fullscreenQueue.overlay'))
      .evaluate()
      .isNotEmpty;
  final fullscreenQueueHitTestable = find
      .byKey(const ValueKey<String>('player.fullscreenQueue.sidebar'))
      .hitTestable()
      .evaluate()
      .isNotEmpty;
  state.toggleQueueVisibilityForStressTest();
  await _pumpContinuously(tester, const Duration(milliseconds: 180));
  await state.toggleWindowFullscreenForStressTest();
  await _pumpContinuously(tester, const Duration(milliseconds: 350));
  final after = backend.state.position.inMilliseconds;
  final snapshot = state.buildStabilitySnapshotForTest();
  final pass = !snapshot.windowFullscreen &&
      !snapshot.hasOpenFailure &&
      snapshot.openedVideoId == snapshot.currentVideoId &&
      fullscreenQueueVisible &&
      fullscreenQueueHitTestable;
  return <String, Object?>{
    'automatedPass': pass,
    'cycles': cycles,
    'finalFullscreen': snapshot.windowFullscreen,
    'positionBeforeMs': before,
    'positionAfterMs': after,
    'sessionPreserved': snapshot.openedVideoId == snapshot.currentVideoId,
    'fullscreenQueueVisible': fullscreenQueueVisible,
    'fullscreenQueueHitTestable': fullscreenQueueHitTestable,
  };
}

/**
 * 在普通窗口折叠/展开右侧队列，验证 Texture 视频与列表由同一 Flutter 容器布局。
 *
 * child HWND 曾因独立窗口矩形滞后一帧而压住列表；本门禁要求视频宽度随动画完成
 * 后立即扩大并恢复，同时播放头持续推进、队列身份不变。
 */
Future<Map<String, Object?>> _runQueueCompositionScenario(
  WidgetTester tester,
  GlobalKey<PlayerPageState> playerKey,
  PlayerBackend backend,
) async {
  final state = playerKey.currentState!;
  final surface = find.byKey(const ValueKey<String>('player.video.surface'));
  final initialWidth = tester.getSize(surface).width;
  final positionBefore = backend.state.position.inMilliseconds;
  final frameTimings = <ui.FrameTiming>[];
  void collectFrames(List<ui.FrameTiming> timings) =>
      frameTimings.addAll(timings);
  WidgetsBinding.instance.addTimingsCallback(collectFrames);
  final resizeBefore =
      int.tryParse(await backend.getProperty('native-surface-resizes'));
  state.toggleQueueVisibilityForStressTest();
  await _pumpContinuously(tester, const Duration(milliseconds: 450));
  final collapsedWidth = tester.getSize(surface).width;
  state.toggleQueueVisibilityForStressTest();
  await _pumpContinuously(tester, const Duration(milliseconds: 450));
  final restoredWidth = tester.getSize(surface).width;
  const cycles = 6;
  for (var cycle = 1; cycle < cycles; cycle++) {
    state.toggleQueueVisibilityForStressTest();
    await _pumpContinuously(tester, const Duration(milliseconds: 450));
    state.toggleQueueVisibilityForStressTest();
    await _pumpContinuously(tester, const Duration(milliseconds: 450));
  }
  WidgetsBinding.instance.removeTimingsCallback(collectFrames);
  final resizeAfter =
      int.tryParse(await backend.getProperty('native-surface-resizes'));
  final resizeDelta = resizeBefore == null || resizeAfter == null
      ? null
      : resizeAfter - resizeBefore;
  final positionAfter = backend.state.position.inMilliseconds;
  final snapshot = state.buildStabilitySnapshotForTest();
  final pass = collapsedWidth > initialWidth &&
      (restoredWidth - initialWidth).abs() <= 1 &&
      positionAfter > positionBefore &&
      backend.textureId.value != null &&
      !snapshot.hasOpenFailure &&
      snapshot.openedVideoId == snapshot.currentVideoId;
  return <String, Object?>{
    'automatedPass': pass,
    'initialSurfaceWidth': initialWidth.round(),
    'collapsedSurfaceWidth': collapsedWidth.round(),
    'restoredSurfaceWidth': restoredWidth.round(),
    'cycles': cycles,
    'frameTiming': _summarizeFrameTimings(frameTimings),
    'nativeSurfaceResizeDelta': resizeDelta,
    'positionBeforeMs': positionBefore,
    'positionAfterMs': positionAfter,
    'textureReady': backend.textureId.value != null,
    'queuePreserved': snapshot.openedVideoId == snapshot.currentVideoId,
  };
}

/**
 * 反复打开设置浮层并连续提交 seek，记录用户最容易感知的交互帧耗时与掉帧变化。
 *
 * 该阶段只采样正式 Route、正式 latest-seek 和真实后端属性；修改前后的报告可以直接
 * 对比，避免用单次肉眼观察替代可重复的性能证据。
 */
Future<Map<String, Object?>> _runInteractionPerformanceScenario(
  WidgetTester tester,
  GlobalKey<PlayerPageState> playerKey,
  PlayerBackend backend,
) async {
  final state = playerKey.currentState!;
  final settingsFrames = <ui.FrameTiming>[];
  void collectSettingsFrames(List<ui.FrameTiming> timings) =>
      settingsFrames.addAll(timings);
  WidgetsBinding.instance.addTimingsCallback(collectSettingsFrames);
  const settingsCycles = 6;
  for (var cycle = 0; cycle < settingsCycles; cycle++) {
    final dialogFuture = state.showControlSettingsForStressTest();
    await _pumpContinuously(tester, const Duration(milliseconds: 260));
    final dialog = find.byKey(const ValueKey<String>('player.settings.dialog'));
    expect(dialog, findsOneWidget);
    Navigator.of(tester.element(dialog)).pop();
    await _pumpContinuously(tester, const Duration(milliseconds: 260));
    await dialogFuture;
  }
  WidgetsBinding.instance.removeTimingsCallback(collectSettingsFrames);

  final seekFrames = <ui.FrameTiming>[];
  void collectSeekFrames(List<ui.FrameTiming> timings) =>
      seekFrames.addAll(timings);
  final droppedBefore =
      int.tryParse(await backend.getProperty('frame-drop-count')) ?? 0;
  WidgetsBinding.instance.addTimingsCallback(collectSeekFrames);
  final duration = backend.state.duration;
  final safeDuration = duration > const Duration(seconds: 20)
      ? duration
      : const Duration(minutes: 2);
  Future<void>? activeSeek;
  const seekRequests = 18;
  for (var index = 0; index < seekRequests; index++) {
    final fraction = 0.12 + (index % 8) * 0.09;
    final target = Duration(
      milliseconds: (safeDuration.inMilliseconds * fraction).round(),
    );
    activeSeek ??= state.seekForStressTest(target);
    if (index > 0) {
      unawaited(state.seekForStressTest(target));
    }
    await tester.pump(const Duration(milliseconds: 40));
  }
  await activeSeek;
  await _pumpContinuously(tester, const Duration(seconds: 2));
  WidgetsBinding.instance.removeTimingsCallback(collectSeekFrames);
  final droppedAfter =
      int.tryParse(await backend.getProperty('frame-drop-count')) ??
          droppedBefore;
  final snapshot = state.buildStabilitySnapshotForTest();
  final pass = find
          .byKey(const ValueKey<String>('player.settings.dialog'))
          .evaluate()
          .isEmpty &&
      !snapshot.hasOpenFailure &&
      snapshot.openedVideoId == snapshot.currentVideoId;
  return <String, Object?>{
    'automatedPass': pass,
    'settingsCycles': settingsCycles,
    'settingsFrameTiming': _summarizeFrameTimings(settingsFrames),
    'seekRequests': seekRequests,
    'seekFrameTiming': _summarizeFrameTimings(seekFrames),
    'droppedFramesDelta': droppedAfter - droppedBefore,
    'queuePreserved': snapshot.openedVideoId == snapshot.currentVideoId,
  };
}

/** 把原始 FrameTiming 压缩为可审查的分位数与超预算帧计数。 */
Map<String, Object?> _summarizeFrameTimings(List<ui.FrameTiming> frames) {
  if (frames.isEmpty) {
    return const <String, Object?>{'frames': 0};
  }
  final totals = frames
      .map((frame) => frame.totalSpan.inMicroseconds / 1000)
      .toList()
    ..sort();
  final builds = frames
      .map((frame) => frame.buildDuration.inMicroseconds / 1000)
      .toList()
    ..sort();
  final rasters = frames
      .map((frame) => frame.rasterDuration.inMicroseconds / 1000)
      .toList()
    ..sort();
  double percentile(List<double> values, double fraction) =>
      values[((values.length - 1) * fraction).round()];
  return <String, Object?>{
    'frames': frames.length,
    'buildP95Ms': percentile(builds, 0.95),
    'rasterP95Ms': percentile(rasters, 0.95),
    'totalP95Ms': percentile(totals, 0.95),
    'totalMaxMs': totals.last,
    'over16Ms': totals.where((value) => value > 16.7).length,
    'over33Ms': totals.where((value) => value > 33.3).length,
  };
}

/**
 * 模拟 Flutter metrics 的常见缩放变化，验证两种视频表面都保持有效。
 *
 * 该结果只属于自动布局门禁；真实跨显示器状态由 [physicalStatus] 单独记录。
 */
Future<Map<String, Object?>> _runDpiScenario(
  WidgetTester tester,
  GlobalKey<PlayerPageState> playerKey,
  PlayerBackend backend, {
  required String physicalStatus,
}) async {
  const scales = <double>[1, 1.25, 1.5, 2, 1];
  final observations = <Map<String, Object?>>[];
  for (final scale in scales) {
    tester.view.devicePixelRatio = scale;
    await _pumpContinuously(tester, const Duration(milliseconds: 350));
    final videoSurface =
        find.byKey(const ValueKey<String>('player.video.surface'));
    final observation = <String, Object?>{
      'requestedScale': scale,
      'surfaceMounted': videoSurface.evaluate().isNotEmpty,
      'surfaceWidth': videoSurface.evaluate().isEmpty
          ? 0
          : tester.getSize(videoSurface).width.round(),
      'surfaceHeight': videoSurface.evaluate().isEmpty
          ? 0
          : tester.getSize(videoSurface).height.round(),
      'textureReady': backend.textureId.value != null,
    };
    observations.add(observation);
  }
  tester.view.resetDevicePixelRatio();
  await _pumpContinuously(tester, const Duration(milliseconds: 350));

  bool observationPassed(Map<String, Object?> observation) {
    if (observation['surfaceMounted'] != true ||
        (observation['surfaceWidth'] as int) < 64 ||
        (observation['surfaceHeight'] as int) < 64) {
      return false;
    }
    return observation['textureReady'] == true;
  }

  final snapshot = playerKey.currentState!.buildStabilitySnapshotForTest();
  final pass = observations.every(observationPassed) &&
      !snapshot.hasOpenFailure &&
      snapshot.openedVideoId == snapshot.currentVideoId;
  return <String, Object?>{
    'automatedPass': pass,
    'automatedScope': 'simulated-flutter-metrics',
    'observations': observations,
    'physicalCrossDisplayStatus': physicalStatus,
    'physicalCrossDisplayRequiredForRelease': true,
  };
}

/**
 * 在短间隔内连续选择队列项，确认 latest-request 最终只打开最后一次选择。
 */
Future<Map<String, Object?>> _runRapidSwitchScenario(
  WidgetTester tester,
  GlobalKey<PlayerPageState> playerKey,
  List<VideoItem> items,
  int switchCount,
  List<String> originalQueue,
) async {
  var targetIndex = 0;
  for (var index = 0; index < switchCount; index++) {
    targetIndex = (index * 2 + 1) % items.length;
    playerKey.currentState!.jumpToQueueIndexForStabilityTest(targetIndex);
    await tester.pump(const Duration(milliseconds: 70));
  }
  final targetId = items[targetIndex].videoId;
  await _waitForOpenedVideo(
    tester,
    playerKey,
    targetId,
    const Duration(seconds: 45),
  );
  final snapshot = playerKey.currentState!.buildStabilitySnapshotForTest();
  final queuePreserved = _sameList(snapshot.sourceVideoIds, originalQueue) &&
      _sameList(snapshot.queueVideoIds, originalQueue);
  final pass = queuePreserved &&
      snapshot.currentVideoId == targetId &&
      snapshot.openedVideoId == targetId &&
      snapshot.playingIndex == targetIndex &&
      !snapshot.opening &&
      !snapshot.hasPendingOpen &&
      !snapshot.hasOpenFailure;
  return <String, Object?>{
    'automatedPass': pass,
    'requestCount': switchCount,
    'targetVideoId': targetId,
    'currentVideoId': snapshot.currentVideoId,
    'openedVideoId': snapshot.openedVideoId,
    'playingIndex': snapshot.playingIndex,
    'sourceQueuePreserved': queuePreserved,
    'openWorkerIdle': !snapshot.opening && !snapshot.hasPendingOpen,
  };
}

/**
 * 定时读取正式诊断快照，验证播放推进、停滞事件、掉帧预算与队列身份。
 */
Future<Map<String, Object?>> _runLongPlayScenario(
  WidgetTester tester,
  GlobalKey<PlayerPageState> playerKey,
  PlayerBackend backend, {
  required int seconds,
  required int maxDroppedFrames,
  required List<String> originalQueue,
}) async {
  final samples = <Map<String, Object?>>[];
  var stalledSamples = 0;
  var advancingSamples = 0;
  var maxObservedDroppedFrames = 0;
  var previousPosition = backend.state.position;
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    await _pumpContinuously(tester, const Duration(seconds: 2));
    final diagnostics =
        await playerKey.currentState!.buildDiagnosticsSnapshot();
    final currentPosition = backend.state.position;
    final advanced = currentPosition > previousPosition ||
        (previousPosition > const Duration(seconds: 2) &&
            currentPosition < previousPosition);
    if (advanced) advancingSamples++;
    if (diagnostics.videoStalled || diagnostics.audioStalled) {
      stalledSamples++;
    }
    final dropped = diagnostics.totalDroppedFrames ?? 0;
    if (dropped > maxObservedDroppedFrames) {
      maxObservedDroppedFrames = dropped;
    }
    samples.add(<String, Object?>{
      'positionMs': currentPosition.inMilliseconds,
      'playing': backend.state.playing,
      'buffering': backend.state.buffering,
      'videoStalled': diagnostics.videoStalled,
      'audioStalled': diagnostics.audioStalled,
      'totalDroppedFrames': diagnostics.totalDroppedFrames,
      'avSync': diagnostics.avSync,
    });
    previousPosition = currentPosition;
  }
  final snapshot = playerKey.currentState!.buildStabilitySnapshotForTest();
  final queuePreserved = _sameList(snapshot.sourceVideoIds, originalQueue) &&
      _sameList(snapshot.queueVideoIds, originalQueue);
  final minimumAdvancingSamples = (samples.length / 2).ceil();
  final pass = samples.isNotEmpty &&
      advancingSamples >= minimumAdvancingSamples &&
      stalledSamples == 0 &&
      maxObservedDroppedFrames <= maxDroppedFrames &&
      queuePreserved &&
      !snapshot.hasOpenFailure &&
      snapshot.openedVideoId == snapshot.currentVideoId;
  return <String, Object?>{
    'automatedPass': pass,
    'requestedSeconds': seconds,
    'sampleCount': samples.length,
    'advancingSamples': advancingSamples,
    'minimumAdvancingSamples': minimumAdvancingSamples,
    'stalledSamples': stalledSamples,
    'maxObservedDroppedFrames': maxObservedDroppedFrames,
    'maxAllowedDroppedFrames': maxDroppedFrames,
    'sourceQueuePreserved': queuePreserved,
    'samples': samples,
  };
}

/** 等待 PlayerPage 的串行 open worker 完成指定匿名视频身份。 */
Future<void> _waitForOpenedVideo(
  WidgetTester tester,
  GlobalKey<PlayerPageState> playerKey,
  String expectedVideoId,
  Duration timeout,
) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 100));
    final state = playerKey.currentState;
    if (state == null) continue;
    final snapshot = state.buildStabilitySnapshotForTest();
    if (!snapshot.opening &&
        !snapshot.hasPendingOpen &&
        !snapshot.hasOpenFailure &&
        snapshot.currentVideoId == expectedVideoId &&
        snapshot.openedVideoId == expectedVideoId) {
      return;
    }
  }
  final snapshot = playerKey.currentState?.buildStabilitySnapshotForTest();
  throw StateError(
    '等待匿名视频 $expectedVideoId 打开超时；'
    'current=${snapshot?.currentVideoId} opened=${snapshot?.openedVideoId}',
  );
}

/** 用短帧持续驱动 Flutter 与原生播放器轮询，避免长 pump 冻结真实窗口。 */
Future<void> _pumpContinuously(
  WidgetTester tester,
  Duration duration,
) async {
  const step = Duration(milliseconds: 50);
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < duration) {
    final remaining = duration - stopwatch.elapsed;
    await tester.pump(remaining < step ? remaining : step);
  }
}

/** 按顺序比较稳定身份列表，避免集合比较掩盖 filtered queue 顺序漂移。 */
bool _sameList(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
