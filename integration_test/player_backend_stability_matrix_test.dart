import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/src/app.dart';
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
        ? WindowsNativePlayerBackend(mode: 'hwnd')
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
    final originalQueue =
        playerKey.currentState!.buildStabilitySnapshotForTest().sourceVideoIds;

    final fullscreen = await _runFullscreenScenario(
      tester,
      playerKey,
      backend,
    );
    final dpi = await _runDpiScenario(
      tester,
      playerKey,
      backend,
      usesMpv: usesMpv,
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
      'sampleCount': items.length,
      'automatedPass': automatedPass,
      'releaseGate': automatedPass && physicalDpiPassed
          ? 'passed'
          : automatedPass
              ? 'pending-physical-cross-dpi'
              : 'failed',
      'scenarios': <String, Object?>{
        'fullscreen': fullscreen,
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
  const cycles = 2;
  for (var index = 0; index < cycles; index++) {
    await state.toggleWindowFullscreenForStressTest();
    await _pumpContinuously(tester, const Duration(milliseconds: 700));
    expect(state.buildStabilitySnapshotForTest().windowFullscreen, isTrue);
    expect(
      find.byKey(const ValueKey<String>('player.video.surface')),
      findsOneWidget,
    );
    await state.toggleWindowFullscreenForStressTest();
    await _pumpContinuously(tester, const Duration(milliseconds: 700));
    expect(state.buildStabilitySnapshotForTest().windowFullscreen, isFalse);
  }
  final after = backend.state.position.inMilliseconds;
  final snapshot = state.buildStabilitySnapshotForTest();
  final pass = !snapshot.windowFullscreen &&
      !snapshot.hasOpenFailure &&
      snapshot.openedVideoId == snapshot.currentVideoId;
  return <String, Object?>{
    'automatedPass': pass,
    'cycles': cycles,
    'finalFullscreen': snapshot.windowFullscreen,
    'positionBeforeMs': before,
    'positionAfterMs': after,
    'sessionPreserved': snapshot.openedVideoId == snapshot.currentVideoId,
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
  required bool usesMpv,
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
      if (usesMpv)
        'nativeSurfaceVisible':
            await backend.getProperty('native-surface-visible'),
      if (usesMpv)
        'nativeSurfaceWidth': await backend.getProperty('native-surface-width'),
      if (usesMpv)
        'nativeSurfaceHeight':
            await backend.getProperty('native-surface-height'),
      if (!usesMpv) 'textureReady': backend.textureId.value != null,
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
    if (!usesMpv) return observation['textureReady'] == true;
    final width =
        int.tryParse(observation['nativeSurfaceWidth']?.toString() ?? '') ?? 0;
    final height =
        int.tryParse(observation['nativeSurfaceHeight']?.toString() ?? '') ?? 0;
    return observation['nativeSurfaceVisible'] == 'true' &&
        width >= 64 &&
        height >= 64;
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
