import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/pages/player/player_page.dart';

// ignore_for_file: slash_for_doc_comments

/** 读取源文件，锁定共享 libmpv 实例的跨媒体写入顺序。 */
String _source(String relativePath) =>
    File('${Directory.current.path}/$relativePath')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

void main() {
  test('新媒体打开前有界等待旧 GPU 属性任务且允许稳定身份失效', () {
    final source = _source('lib/src/pages/player/player_state_opening.dart');
    final waitIndex = source.indexOf(
      'await previousGpuTask.timeout(playerGpuCapabilityDetectionTimeout);',
    );
    final openIndex = source.indexOf('await playerService.openPath(path);');

    expect(waitIndex, greaterThanOrEqualTo(0));
    expect(openIndex, greaterThan(waitIndex));
    expect(
      source,
      contains('if (openRequests.hasSuperseded(request)) continue;'),
    );
  });

  test('GPU 能力结果发布前绑定 stable ID、媒体代次和请求 revision', () {
    final source = _source(
      'lib/src/pages/player/player_state_gpu_capabilities.dart',
    );

    expect(
      source,
      contains(
        'Future<void> detectCurrentGpuCapabilities(\n'
        '    PlayerOpenRequest request,',
      ),
    );
    expect(
      RegExp(r'openRequests\.hasSuperseded\(request\)').allMatches(source),
      hasLength(greaterThanOrEqualTo(5)),
    );
    expect(source, contains('PlayerMediaTaskContext task'));
    expect(source, contains('isCurrentMediaTask(task)'));
  });

  test('媒体打开只应用一次引擎快照和一次媒体呈现快照', () {
    final source = _source('lib/src/pages/player/player_state_opening.dart');

    expect(
      RegExp(r'await applyPlaybackEngineProfile\(\);').allMatches(source),
      hasLength(1),
    );
    expect(
      RegExp(r'await applyMediaPresentationProfile\(\);').allMatches(source),
      hasLength(1),
    );
    expect(
      source.indexOf('await applyPlaybackEngineProfile();'),
      lessThan(source.indexOf('await playerService.openPath(path);')),
    );
    expect(
      source.indexOf('await applyMediaPresentationProfile();'),
      greaterThan(source.indexOf('await playerService.openPath(path);')),
    );
  });

  test('正式 MediaKit 打开保持暂停并在打开门禁后显式播放', () {
    final backend =
        _source('lib/src/services/player/media_kit_player_backend.dart');
    final opening = _source('lib/src/pages/player/player_state_opening.dart');

    expect(backend, contains('await _player.open(Media(path), play: false);'));
    expect(
      opening,
      contains(
        'if (mounted && openedVideoId == item.videoId) {\n'
        '        await playerService.play();',
      ),
    );
  });

  test('本地缓存暂停 A/B 默认采用 no 且保留 yes 对照开关', () {
    final source =
        _source('lib/src/pages/player/player_state_performance.dart');

    expect(source, contains("'cache-pause': localPlaybackCachePauseEnabled"));
    expect(source, contains("'LTP_LOCAL_CACHE_PAUSE'"));
    expect(
      source,
      contains("variant=\${localPlaybackCachePauseEnabled ? 'yes' : 'no'}"),
    );
  });

  test('旧媒体采样完成后切换新媒体时稳定身份拒绝迟到结果', () async {
    final oldTask = const PlayerMediaTaskContext(
      videoId: 'video-old',
      mediaGeneration: 4,
      requestRevision: 11,
    );
    var currentTask = oldTask;
    var staleSampleApplied = false;
    final sampleGate = Completer<void>();

    final delayedSample = Future<void>(() async {
      await sampleGate.future;
      if (oldTask.matches(
        currentVideoId: currentTask.videoId,
        currentMediaGeneration: currentTask.mediaGeneration,
        currentRequestRevision: currentTask.requestRevision,
      )) {
        staleSampleApplied = true;
      }
    });

    currentTask = const PlayerMediaTaskContext(
      videoId: 'video-new',
      mediaGeneration: 5,
      requestRevision: 12,
    );
    sampleGate.complete();
    await delayedSample;

    expect(staleSampleApplied, isFalse);
  });

  test('健康采样与 NVIDIA 异步方法都要求媒体任务上下文', () {
    final health = _source('lib/src/pages/player/player_state_health.dart');
    final nvidia = _source('lib/src/pages/player/player_state_nvidia.dart');

    expect(health, contains('required PlayerMediaTaskContext task'));
    expect(health, contains('sampleQualityMargin('));
    expect(health, contains('if (!isCurrentMediaTask(task)) return;'));
    expect(nvidia, contains('PlayerMediaTaskContext task'));
    expect(
        nvidia, contains('await probeNvidiaVideoEnhancementCapability(task)'));
    expect(nvidia,
        contains('await refreshNvidiaVideoEnhancementRuntimeState(task)'));
    expect(nvidia, contains('required PlayerMediaTaskContext task'));
  });
}
