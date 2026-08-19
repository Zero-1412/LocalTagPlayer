import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/core/playback_settings.dart';
import 'package:local_tag_player/src/models/player_gpu_capabilities.dart';
import 'package:local_tag_player/src/models/player_motion_interpolation_capability.dart';
import 'package:local_tag_player/src/models/player_media_controls.dart';
import 'package:local_tag_player/src/platform/platform_interfaces.dart';
import 'package:local_tag_player/src/services/player/player_service.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 记录 PlayerService 转发结果的最小后端，避免测试依赖 MediaKit 或 Windows runner。
 */
class _RecordingPlayerBackend implements PlayerBackend {
  final ValueNotifier<int?> _textureId = ValueNotifier<int?>(7);
  final Map<String, String> properties = <String, String>{};
  final List<String> commands = <String>[];
  double? appliedRate;

  @override
  PlayerBackendState get state => const PlayerBackendState(
        position: Duration(seconds: 3),
        duration: Duration(minutes: 1),
        playing: true,
        buffering: false,
        volume: 75,
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
  Future<void> openPath(String path) async => commands.add('open');

  @override
  Future<void> play() async => commands.add('play');

  @override
  Future<void> pause() async => commands.add('pause');

  @override
  Future<void> stop() async => commands.add('stop');

  @override
  Future<void> seek(Duration position) async => commands.add('seek');

  @override
  Future<void> setRate(double rate) async {
    appliedRate = rate;
    commands.add('rate');
  }

  @override
  Future<void> setVolume(double volume) async => commands.add('volume');

  @override
  Future<void> playOrPause() async => commands.add('toggle');

  @override
  Future<void> setProperty(String property, String value) async {
    properties[property] = value;
  }

  @override
  Future<String> getProperty(String property) async =>
      properties[property] ?? 'unavailable';

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
  Future<void> dispose() async {
    commands.add('dispose');
    _textureId.dispose();
  }

  @override
  Future<void> get released => Future<void>.value();
}

/**
 * 记录强类型插帧调用的可选后端，验证页面服务不会传递 DLL 或脚本路径。
 */
class _RecordingMotionBackend extends _RecordingPlayerBackend
    implements PlayerMotionInterpolationBoundary {
  bool enabled = false;

  @override
  Future<PlayerMotionInterpolationCapability>
      queryMotionInterpolationCapability() async =>
          PlayerMotionInterpolationCapability(
            status: enabled
                ? PlayerMotionInterpolationStatus.requested
                : PlayerMotionInterpolationStatus.ready,
            backend: 'recording-native',
            runtimeState: enabled ? 'requested' : 'ready',
            enabled: enabled,
            nvidiaDriverState: 'available',
            nvidiaDriverError: '',
            nvidiaOpticalFlowApiVersion: 0x50,
            nvidiaD3D11Available: true,
          );

  @override
  Future<PlayerMotionInterpolationApplyResult> setMotionInterpolationEnabled(
    bool enabled,
  ) async {
    this.enabled = enabled;
    return PlayerMotionInterpolationApplyResult(
      applied: true,
      capability: await queryMotionInterpolationCapability(),
    );
  }
}

/** 记录 PlayerService 是否优先走一次批量属性事务。 */
class _BatchRecordingPlayerBackend extends _RecordingPlayerBackend
    implements PlayerPropertyBatchBoundary {
  final List<Map<String, String>> batches = <Map<String, String>>[];

  @override
  Future<void> setProperties(Map<String, String> properties) async {
    batches.add(Map<String, String>.from(properties));
    this.properties.addAll(properties);
  }
}

/** 记录低延迟随机跳转是否命中可选后端边界。 */
class _InteractiveSeekRecordingBackend extends _RecordingPlayerBackend
    implements PlayerInteractiveSeekBoundary {
  @override
  Future<void> seekInteractive(Duration position) async =>
      commands.add('seek-interactive');
}

/** 记录专用快进扫描边界，确保服务不会把恢复操作拆成普通 setRate。 */
class _FastForwardScanRecordingBackend extends _RecordingPlayerBackend
    implements PlayerFastForwardScanBoundary {
  @override
  Future<void> beginFastForwardScan(double rate) async =>
      commands.add('scan-begin:$rate');

  @override
  Future<void> endFastForwardScan() async => commands.add('scan-end');
}

/** 记录逐帧、A-B loop 与外挂字幕边界，验证服务不把高级控制降级为普通 seek。 */
class _PrecisionControlsRecordingBackend extends _RecordingPlayerBackend
    implements PlayerPrecisionControlsBoundary, PlayerExternalSubtitleBoundary {
  final List<String> precisionCommands = <String>[];

  @override
  Future<void> stepFrame({required bool backward}) async =>
      precisionCommands.add(backward ? 'frame-backward' : 'frame-forward');

  @override
  Future<void> setAbLoopPoint({
    required PlayerAbLoopPoint point,
    required Duration position,
  }) async {
    precisionCommands.add(
      '${point == PlayerAbLoopPoint.start ? 'a' : 'b'}:${position.inMilliseconds}',
    );
  }

  @override
  Future<void> clearAbLoop() async => precisionCommands.add('ab-clear');

  @override
  Future<void> addExternalSubtitle(String path) async =>
      precisionCommands.add('subtitle-add');
}

/** 用门闩制造跨命令竞争，验证 PlayerService 不会让 open 越过 in-flight seek。 */
class _SerializedCommandBackend extends _RecordingPlayerBackend {
  _SerializedCommandBackend(this.seekEntered, this.releaseSeek);

  final Completer<void> seekEntered;
  final Completer<void> releaseSeek;

  @override
  Future<void> seek(Duration position) async {
    commands.add('seek-start');
    seekEntered.complete();
    await releaseSeek.future;
    commands.add('seek-end');
  }
}

/** 用永不自动返回的属性 Future 验证 PlayerService 的统一读取上限。 */
class _BlockingPropertyBackend extends _RecordingPlayerBackend {
  _BlockingPropertyBackend(this.blockedRead);

  final Future<String> blockedRead;

  @override
  Future<String> getProperty(String property) => blockedRead;
}

/** 验证媒体控制仍经由可选后端边界，不泄露具体播放器实现。 */
class _MediaControlsRecordingBackend extends _RecordingPlayerBackend
    implements PlayerMediaControlsBoundary {
  final List<String> mediaCommands = <String>[];

  @override
  Future<PlayerMediaControlsSnapshot> readMediaControls() async =>
      const PlayerMediaControlsSnapshot(
        supported: true,
        audioTracks: <PlayerMediaTrack>[
          PlayerMediaTrack(
            id: '1',
            title: '中文',
            language: 'zh',
            codec: 'aac',
            isDefault: true,
            selected: true,
          ),
        ],
        subtitleTracks: <PlayerMediaTrack>[],
        chapters: <PlayerMediaChapter>[
          PlayerMediaChapter(
            index: 0,
            position: Duration.zero,
            title: '开始',
          ),
        ],
        subtitleDelay: Duration.zero,
        audioDelay: Duration.zero,
      );

  @override
  Future<void> adjustAudioDelay(Duration delta) async =>
      mediaCommands.add('audio-delay:${delta.inMilliseconds}');

  @override
  Future<void> adjustSubtitleDelay(Duration delta) async =>
      mediaCommands.add('subtitle-delay:${delta.inMilliseconds}');

  @override
  Future<void> seekChapter(int chapterIndex) async =>
      mediaCommands.add('chapter:$chapterIndex');

  @override
  Future<void> selectAudioTrack(String trackId) async =>
      mediaCommands.add('audio:$trackId');

  @override
  Future<void> selectSubtitleTrack(String trackId) async =>
      mediaCommands.add('subtitle:$trackId');

  @override
  Future<void> toggleSubtitle() async => mediaCommands.add('subtitle-toggle');
}

/**
 * 读取播放器页面及其同库状态分区，确保服务边界契约覆盖真实 Route 挂载。
 */
String _readPlayerPageCluster() {
  final directory = Directory('lib/src/pages/player');
  final paths = <String>[
    'lib/src/pages/player/player_page.dart',
    ...directory
        .listSync()
        .whereType<File>()
        .map((file) => file.path.replaceAll(r'\', '/'))
        .where((path) => path.contains('/player_state_'))
        .toList()
      ..sort(),
  ];
  return paths.map((path) => File(path).readAsStringSync()).join('\n');
}

void main() {
  test('PlayerPage 只依赖 PlayerService 工厂，不导入具体播放器后端', () {
    final source = _readPlayerPageCluster();
    final seekGate = File(
      'integration_test/player_seek_latency_gate_test.dart',
    ).readAsStringSync();

    expect(
        source, contains('final PlayerServiceFactory playerServiceFactory;'));
    expect(source, isNot(contains('MediaKitPlayerBackend')));
    expect(source, isNot(contains('WindowsNativePlayerBackend')));
    expect(
        source, isNot(contains('PlayerBackendFactory playerBackendFactory')));
    expect(
      source,
      contains(
        'rendererPreference: pageWidget.playbackSettings.rendererPreference',
      ),
    );
    expect(source, contains('submit: playerService.seekInteractive'));
    expect(source, contains('exactSeekCoordinator = PlayerSeekCoordinator('));
    expect(source, contains('await seekWithDiagnostics(target);'));
    expect(source, contains('await exactSeekCoordinator.request(target);'));
    // 拖动过程不派发 seek；唯一的松手精确提交在新视频帧交付后才恢复音频。
    expect(
        source,
        contains(
            'seekAudioGate.run(() => seekExactlyWithDiagnostics(target))'));
    expect(source, contains('PlayerKeyboardSeekController('));
    expect(source, isNot(contains('exactSubmit: seekExactlyWithDiagnostics')));
    // 页面延后首个短按随机 seek；首个 KeyRepeat 的前进改为临时倍速，避免持续
    // 关键帧跳转反复中断解码。它不得写回全局播放设置。
    expect(source, contains('deferInitialPreviewUntilRelease: true'));
    expect(source, contains('setTemporaryPlaybackRate: playerService.setRate'));
    expect(source,
        contains('beginFastForwardScan: playerService.beginFastForwardScan'));
    expect(
        source,
        contains(
            'endFastForwardScan: () => playerService.endFastForwardScan('));
    expect(source, contains('isRepeat: isRepeat'));
    // 短按只提交一次关键帧；进度条松手与继续观看单独走准确落点。
    expect(source, isNot(contains('settle: seekExactlyWithDiagnostics')));
    expect(source, contains('confirmationTimeout: Duration.zero'));
    expect(source,
        contains('confirmationTolerance: const Duration(milliseconds: 100)'));
    // 基线门禁必须与正式短按/关键帧预览合同一致；否则长 GOP 后退会把
    // 逻辑位置等待误报成首个呈现帧延迟。
    expect(seekGate, contains('confirmationTimeout: Duration.zero'));
    expect(seekGate,
        isNot(contains('confirmationTimeout: const Duration(seconds: 3)')));
    expect(source, contains('PLAYER_EXACT_SEEK_UNCONFIRMED'));
    expect(source, contains('精确定位未在确认窗口内收敛'));
    expect(source, contains('await seekExactlyWithDiagnostics(start);'));
    expect(source, contains('submit: playerService.seek'));
  });

  test('PlayerService 统一转发播放命令并应用类型化打开偏好', () async {
    final backend = _RecordingPlayerBackend();
    final service = PlayerService(backend: backend);

    await service.openPath('ignored-local-path');
    await service.pause();
    await service.seek(const Duration(seconds: 12));
    final preferencesResult = await service.applyOpenPreferences(
      videoAspectOverride: '-1',
      panscan: '1.0',
      videoScaler: PlayerVideoScaler.bicubic,
      smoothMotionMode: PlayerSmoothMotionMode.displayInterpolation,
      videoOutputRange: PlayerVideoOutputRange.full,
      playbackRate: 1.5,
      videoSuperResolutionEnabled: false,
    );

    expect(
        backend.commands,
        containsAllInOrder(<String>[
          'open',
          'pause',
          'seek',
          'rate',
        ]));
    expect(backend.properties['video-aspect-override'], '-1');
    expect(backend.properties['panscan'], '1.0');
    expect(backend.properties['video-output-levels'], 'full');
    expect(backend.properties['scale'], 'bicubic');
    expect(backend.properties['video-sync'], 'display-resample');
    expect(backend.properties['tscale'], 'oversample');
    expect(backend.properties['interpolation'], 'yes');
    expect(preferencesResult.smoothMotion.active, isTrue);
    expect(preferencesResult.scaling.applied, isTrue);
    expect(backend.appliedRate, 1.5);
  });

  test('PlayerService 优先使用后端批量属性边界', () async {
    final backend = _BatchRecordingPlayerBackend();
    final service = PlayerService(backend: backend);

    await service.setProperties(const <String, String>{
      'hwdec': 'd3d11va-copy',
      'vf': '',
    });

    expect(backend.batches, hasLength(1));
    expect(
      backend.batches.single.keys,
      orderedEquals(<String>['hwdec', 'vf']),
    );
    expect(backend.properties['vf'], isEmpty);
  });

  test('PlayerService 交互式 seek 优先走低延迟边界并保留安全回退', () async {
    final interactiveBackend = _InteractiveSeekRecordingBackend();
    final interactiveService = PlayerService(backend: interactiveBackend);
    final fallbackBackend = _RecordingPlayerBackend();
    final fallbackService = PlayerService(backend: fallbackBackend);

    await interactiveService.seekInteractive(const Duration(seconds: 28));
    await fallbackService.seekInteractive(const Duration(seconds: 28));

    expect(interactiveBackend.commands, <String>['seek-interactive']);
    expect(fallbackBackend.commands, <String>['seek']);
  });

  test('PlayerService 优先使用可恢复快进扫描边界并保留倍速回退', () async {
    final scanBackend = _FastForwardScanRecordingBackend();
    final scanService = PlayerService(backend: scanBackend);
    final fallbackBackend = _RecordingPlayerBackend();
    final fallbackService = PlayerService(backend: fallbackBackend);

    await scanService.beginFastForwardScan(2);
    await scanService.endFastForwardScan(fallbackRate: 1);
    await fallbackService.beginFastForwardScan(2);
    await fallbackService.endFastForwardScan(fallbackRate: 1);

    expect(scanBackend.commands, <String>['scan-begin:2.0', 'scan-end']);
    expect(fallbackBackend.commands, <String>['rate', 'rate']);
    expect(fallbackBackend.appliedRate, 1);
  });

  test('PlayerService 转发逐帧、A-B loop 与外挂字幕并明确能力缺失', () async {
    final backend = _PrecisionControlsRecordingBackend();
    final service = PlayerService(backend: backend);
    expect(service.supportsPrecisionControls, isTrue);
    expect(service.supportsExternalSubtitle, isTrue);

    await service.stepFrame(backward: true);
    await service.stepFrame(backward: false);
    await service.setAbLoopPoint(
      point: PlayerAbLoopPoint.start,
      position: const Duration(seconds: 3),
    );
    await service.setAbLoopPoint(
      point: PlayerAbLoopPoint.end,
      position: const Duration(seconds: 8),
    );
    await service.clearAbLoop();
    await service.addExternalSubtitle('subtitle.srt');
    expect(
      backend.precisionCommands,
      <String>[
        'frame-backward',
        'frame-forward',
        'a:3000',
        'b:8000',
        'ab-clear',
        'subtitle-add',
      ],
    );

    final unsupported = PlayerService(backend: _RecordingPlayerBackend());
    expect(unsupported.supportsPrecisionControls, isFalse);
    expect(unsupported.supportsExternalSubtitle, isFalse);
    await expectLater(
      unsupported.stepFrame(backward: false),
      throwsUnsupportedError,
    );
    await expectLater(
      unsupported.addExternalSubtitle('subtitle.srt'),
      throwsUnsupportedError,
    );
  });

  test('MediaKit 快进扫描只使用可读回的输出端丢帧档位并在换片前恢复', () {
    final source = File(
      'lib/src/services/player/media_kit_player_backend.dart',
    ).readAsStringSync();

    expect(source, contains('PlayerFastForwardScanBoundary,'));
    expect(source, contains("'video-sync',\n            'audio'"));
    expect(source, contains("'interpolation',\n            'no'"));
    expect(source, contains("'framedrop',\n            'vo'"));
    expect(source, contains('_verifyFastForwardScanProfile(nativePlayer)'));
    expect(source, contains('_restoreFastForwardScanBeforeMediaTransition()'));
  });

  test('PlayerService 将 in-flight seek 与 open 串行化', () async {
    final seekEntered = Completer<void>();
    final releaseSeek = Completer<void>();
    final backend = _SerializedCommandBackend(seekEntered, releaseSeek);
    final service = PlayerService(backend: backend);

    final seekFuture = service.seek(const Duration(seconds: 12));
    await seekEntered.future;
    final openFuture = service.openPath('next.mp4');

    expect(backend.commands, <String>['seek-start']);
    releaseSeek.complete();
    await Future.wait<void>(<Future<void>>[seekFuture, openFuture]);
    expect(
      backend.commands,
      <String>['seek-start', 'seek-end', 'open'],
    );
    await service.dispose();
  });

  test('媒体命令超时会封锁排队命令但不会与旧 native seek 并发', () async {
    final seekEntered = Completer<void>();
    final releaseSeek = Completer<void>();
    final backend = _SerializedCommandBackend(seekEntered, releaseSeek);
    final service = PlayerService(
      backend: backend,
      mediaCommandTimeout: const Duration(milliseconds: 20),
      mediaCommandDisposeWaitTimeout: const Duration(milliseconds: 20),
    );

    final seekFuture = service.seek(const Duration(seconds: 12));
    await seekEntered.future;
    final openFuture = service.openPath('next.mp4');

    await expectLater(
      seekFuture,
      throwsA(isA<PlayerMediaCommandTimeout>()),
    );
    await expectLater(
      openFuture,
      throwsA(isA<PlayerMediaCommandInvalidated>()),
    );
    expect(backend.commands, <String>['seek-start']);

    // 释放唯一 in-flight native 命令后，尾链才能自然收尾；期间没有第二条
    // open/stop 进入后端，避免旧 seek 迟到覆盖新媒体。
    releaseSeek.complete();
    await service.dispose();
  });

  test('普通属性读取超时会返回明确的属性超时而不是永久等待', () async {
    final blockedRead = Completer<String>();
    final service = PlayerService(
      backend: _BlockingPropertyBackend(blockedRead.future),
      propertyReadTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      service.getProperty('demuxer-cache-duration'),
      throwsA(isA<PlayerPropertyReadTimeout>()),
    );
    blockedRead.complete('late');
    await service.dispose();
  });

  test('PlayerService 只通过可选边界转发媒体控制，普通后端明确不支持', () async {
    final fallback = PlayerService(backend: _RecordingPlayerBackend());
    final fallbackSnapshot = await fallback.readMediaControls();
    expect(fallbackSnapshot.supported, isFalse);
    expect(
      () => fallback.selectAudioTrack('1'),
      throwsUnsupportedError,
    );

    final backend = _MediaControlsRecordingBackend();
    final service = PlayerService(backend: backend);
    final snapshot = await service.readMediaControls();
    expect(snapshot.supported, isTrue);
    expect(snapshot.audioTracks.single.label('音轨'), '中文');
    await service.selectAudioTrack('1');
    await service.selectSubtitleTrack('no');
    await service.toggleSubtitle();
    await service.adjustSubtitleDelay(const Duration(milliseconds: 100));
    await service.adjustAudioDelay(const Duration(milliseconds: -100));
    await service.seekChapter(0);
    expect(
      backend.mediaCommands,
      <String>[
        'audio:1',
        'subtitle:no',
        'subtitle-toggle',
        'subtitle-delay:100',
        'audio-delay:-100',
        'chapter:0',
      ],
    );
  });

  test('不支持 Windows 可选能力的后端由 PlayerService 安全回退', () async {
    final service = PlayerService(backend: _RecordingPlayerBackend());

    expect(service.telemetry.supported, isFalse);
    expect(service.telemetry.backendName, 'unsupported');
    await expectLater(
      service.telemetryChanges,
      emitsDone,
    );
    expect((await service.queryActiveGpuAdapter()).probeStatus, 'unsupported');
    expect(
      (await service.benchmarkGpuComputeFrameBudget('qa-luid')).probeStatus,
      'unsupported',
    );
    await expectLater(service.setFlutterOverlayVisible(true), completes);
    final motion = await service.queryMotionInterpolationCapability();
    expect(motion.status, PlayerMotionInterpolationStatus.unsupported);
    expect(
      (await service.setMotionInterpolationEnabled(true)).applied,
      isFalse,
    );
  });

  test('PlayerService 只转发强类型插帧意图并读回原生状态', () async {
    final backend = _RecordingMotionBackend();
    final service = PlayerService(backend: backend);

    final before = await service.queryMotionInterpolationCapability();
    final enabled = await service.setMotionInterpolationEnabled(true);
    final disabled = await service.setMotionInterpolationEnabled(false);

    expect(before.status, PlayerMotionInterpolationStatus.ready);
    expect(enabled.applied, isTrue);
    expect(enabled.capability.enabled, isTrue);
    expect(enabled.capability.nvidiaDriverReady, isTrue);
    expect(enabled.capability.nvidiaOpticalFlowApiVersion, 0x50);
    expect(disabled.applied, isTrue);
    expect(disabled.capability.enabled, isFalse);
  });

  test('媒体控制入口挂载在正式播放器控制栏，并保持覆盖层生命周期', () {
    final source = _readPlayerPageCluster();
    final widgets = File(
      'lib/src/pages/player/player_media_controls_widgets.dart',
    ).readAsStringSync();

    expect(source, contains("ValueKey('player.mediaControls')"));
    expect(source, contains('showMediaControlsDialog'));
    expect(source, contains('withPlayerOverlaySurfaceOccluded'));
    expect(source, contains('readMediaControls'));
    expect(source, contains('seekChapter'));
    expect(widgets, contains('PlayerMediaControlSection'));
  });
}
