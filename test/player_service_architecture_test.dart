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
    expect(source, contains('await seekCoordinator.request(target);'));
    // 鼠标连续点击不得进入等待新帧/恢复音量的串行门禁；精确恢复路径仍单独保留。
    expect(
      source,
      isNot(contains('seekAudioGate.run(() => playerService.seekInteractive')),
    );
    expect(source, contains('PlayerKeyboardSeekController('));
    expect(source, contains('exactSubmit: seekExactlyWithDiagnostics'));
    expect(source, contains('isRepeat: isRepeat'));
    // 进度条走交互式 latest-only；键盘只有短按 KeyUp 才补一次绝对 seek，长按不重复。
    expect(source, isNot(contains('settle: seekExactlyWithDiagnostics')));
    expect(source, contains('confirmationTimeout: Duration.zero'));
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
