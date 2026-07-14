import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/main.dart' as app;
import 'package:local_tag_player/src/app.dart' as ltp;

// ignore_for_file: slash_for_doc_comments

/**
 * 使用隔离 SQLite profile 与真实 X:\test-media 执行十轮媒体库增删和播放器压力测试。
 *
 * 目录添加/移除复用媒体库页面的真实 Application/Repository 链路；滚动、快速点击、
 * seek、诊断和退出只通过 Flutter Finder/VM Service 驱动，不创建 Windows UIA
 * 客户端，也不会删除 X:\test-media 下的本地文件。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实目录十轮增删、缩略图、媒体详情与播放器压力测试', (tester) async {
    final profilePath = _requiredEnvironment('LOCAL_TAG_PLAYER_DATA_DIR');
    final stressRoot =
        _requiredEnvironment('LOCAL_TAG_PLAYER_LIBRARY_STRESS_ROOT');
    final outputPath = _requiredEnvironment('LOCAL_TAG_PLAYER_STRESS_OUTPUT');
    final cycles = int.tryParse(
          Platform.environment['LOCAL_TAG_PLAYER_LIBRARY_STRESS_CYCLES'] ?? '',
        ) ??
        10;
    final seed = int.tryParse(
          Platform.environment['LOCAL_TAG_PLAYER_STRESS_SEED'] ?? '',
        ) ??
        20260714;
    final releaseTailSeconds = int.tryParse(
          Platform.environment['LOCAL_TAG_PLAYER_RELEASE_TAIL_SECONDS'] ?? '',
        ) ??
        0;
    if (!Directory(stressRoot).existsSync()) {
      throw StateError('专项压测目录不存在');
    }
    final outputDirectory = Directory(outputPath)..createSync(recursive: true);
    final statusFile = File('${outputDirectory.path}\\library-status.jsonl');
    final frameFile = File('${outputDirectory.path}\\frame-timings.jsonl');
    statusFile.writeAsStringSync('');
    frameFile.writeAsStringSync('');
    final random = Random(seed);
    final frameSampler = _PhaseFrameSampler(frameFile);
    WidgetsBinding.instance.addTimingsCallback(frameSampler.onTimings);
    addTearDown(() {
      frameSampler.flush();
      ltp.LibraryCardUiDiagnostics.flush();
      WidgetsBinding.instance.removeTimingsCallback(frameSampler.onTimings);
    });

    await app.main();
    await _pumpUntil(
      tester,
      () => ltp.LibraryStressControl.isAvailable,
      const Duration(minutes: 3),
      '媒体库 hydration 或专项控制注册超时',
    );
    await _pumpUntilFound(tester, _visibleLibraryPlayButtons());

    // 复制的真实 profile 可能已经包含目标 root；先通过同一事务链路恢复“待添加”基线。
    final initial = ltp.LibraryStressControl.snapshot();
    if (initial.roots.any((root) => _samePath(root, stressRoot))) {
      frameSampler.begin('baseline_remove', 0);
      await _setStressPhase(outputDirectory, 'baseline_remove', 0);
      await _awaitWithPumping(
        tester,
        ltp.LibraryStressControl.removeConfiguredRoot(),
      );
      await _waitForUiCount(tester);
      await _pumpContinuously(tester, const Duration(milliseconds: 500));
      frameSampler.flush();
    }
    final baseline = ltp.LibraryStressControl.snapshot();
    if (baseline.roots.any((root) => _samePath(root, stressRoot))) {
      throw StateError('专项压测基线仍包含目标 root');
    }
    _writeStatus(
      statusFile,
      profilePath: profilePath,
      phase: 'baseline_ready',
      cycle: 0,
      elapsed: Duration.zero,
      snapshot: baseline,
    );

    // 基线准备完成后才通知外部录屏器，避免 profile 清理吞掉正式录像时长。
    File('${outputDirectory.path}\\recorder-start-request.ready')
        .writeAsStringSync('ready');
    await _waitForRecorder(tester, outputDirectory);
    await _signalDesktopCapture(outputDirectory, 'cycle-00-baseline');

    for (var cycle = 1; cycle <= cycles; cycle++) {
      frameSampler.begin('add_scan', cycle);
      await _setStressPhase(outputDirectory, 'add_scan', cycle);
      final addWatch = Stopwatch()..start();
      final addResult = await _awaitWithPumping(
        tester,
        ltp.LibraryStressControl.addConfiguredRoot(),
      );
      addWatch.stop();
      final addUiLatency = await _waitForUiCount(tester);
      await _pumpContinuously(tester, const Duration(milliseconds: 500));
      final added = ltp.LibraryStressControl.snapshot();
      _writeStatus(
        statusFile,
        profilePath: profilePath,
        phase: 'added',
        cycle: cycle,
        elapsed: addWatch.elapsed,
        uiLatency: addUiLatency,
        snapshot: added,
        scanResult: addResult,
        visibleImages: _visibleImageCount(),
      );
      frameSampler.flush();
      if (added.videoCount <= baseline.videoCount ||
          added.visibleCount != added.videoCount) {
        throw StateError('第 $cycle 轮添加后 UI 总量未同步');
      }
      await _signalDesktopCapture(
        outputDirectory,
        'cycle-${cycle.toString().padLeft(2, '0')}-added',
      );

      frameSampler.begin('added_library_scroll', cycle);
      await _setStressPhase(outputDirectory, 'added_library_scroll', cycle);
      await _rapidlyScrollLibrary(tester, random);
      await _pumpContinuously(tester, const Duration(seconds: 2));
      final afterAddedScroll = ltp.LibraryStressControl.snapshot();
      _writeStatus(
        statusFile,
        profilePath: profilePath,
        phase: 'added_scroll_settled',
        cycle: cycle,
        elapsed: Duration.zero,
        snapshot: afterAddedScroll,
        visibleImages: _visibleImageCount(),
      );
      frameSampler.flush();

      await _playRandomVideo(
        tester,
        random,
        outputDirectory,
        cycle: cycle,
        phasePrefix: 'added_player',
        frameSampler: frameSampler,
      );

      frameSampler.begin('remove_root', cycle);
      await _setStressPhase(outputDirectory, 'remove_root', cycle);
      final removeWatch = Stopwatch()..start();
      final removedCount = await _awaitWithPumping(
        tester,
        ltp.LibraryStressControl.removeConfiguredRoot(),
      );
      removeWatch.stop();
      final removeUiLatency = await _waitForUiCount(tester);
      await _pumpContinuously(tester, const Duration(milliseconds: 500));
      final removed = ltp.LibraryStressControl.snapshot();
      _writeStatus(
        statusFile,
        profilePath: profilePath,
        phase: 'removed',
        cycle: cycle,
        elapsed: removeWatch.elapsed,
        uiLatency: removeUiLatency,
        snapshot: removed,
        removedCount: removedCount,
        visibleImages: _visibleImageCount(),
      );
      frameSampler.flush();
      if (removed.videoCount != baseline.videoCount ||
          removed.visibleCount != removed.videoCount) {
        throw StateError('第 $cycle 轮移除后 UI 总量未恢复基线');
      }
      await _signalDesktopCapture(
        outputDirectory,
        'cycle-${cycle.toString().padLeft(2, '0')}-removed',
      );

      frameSampler.begin('removed_library_scroll', cycle);
      await _setStressPhase(outputDirectory, 'removed_library_scroll', cycle);
      await _rapidlyScrollLibrary(tester, random);
      await _pumpContinuously(tester, const Duration(seconds: 1));
      frameSampler.flush();
      await _playRandomVideo(
        tester,
        random,
        outputDirectory,
        cycle: cycle,
        phasePrefix: 'removed_player',
        frameSampler: frameSampler,
      );

      // ignore: avoid_print
      print('LIBRARY_STRESS cycle=$cycle/$cycles seed=$seed '
          'added=${addResult.addedCount} removed=$removedCount');
    }

    if (releaseTailSeconds > 0) {
      frameSampler.begin('final_release_tail', cycles);
      await _setStressPhase(outputDirectory, 'final_release_tail', cycles);
      await ltp.PlayerMemoryDiagnostics.logStage('release_tail_0s');
      const checkpoints = <int>{5, 15, 30, 60};
      for (var second = 1; second <= releaseTailSeconds; second++) {
        await _pumpContinuously(tester, const Duration(seconds: 1));
        if (checkpoints.contains(second) || second == releaseTailSeconds) {
          await ltp.PlayerMemoryDiagnostics.logStage(
            'release_tail_${second}s',
          );
        }
      }
      frameSampler.flush();
    }

    frameSampler.begin('complete', cycles);
    await _setStressPhase(outputDirectory, 'complete', cycles);
    await _signalDesktopCapture(outputDirectory, 'cycle-10-complete');
    expect(ltp.LibraryStressControl.snapshot().videoCount, baseline.videoCount);
  }, timeout: const Timeout(Duration(minutes: 30)));
}

/** 播放当前视口随机视频，执行三次随机 seek、持续诊断和确定性退出。 */
Future<void> _playRandomVideo(
  WidgetTester tester,
  Random random,
  Directory outputDirectory, {
  required int cycle,
  required String phasePrefix,
  required _PhaseFrameSampler frameSampler,
}) async {
  final buttons = _visibleLibraryPlayButtons();
  if (buttons.evaluate().isEmpty) {
    throw StateError('第 $cycle 轮 $phasePrefix 没有可点击视频');
  }
  frameSampler.begin('${phasePrefix}_startup', cycle);
  await _setStressPhase(outputDirectory, '${phasePrefix}_startup', cycle);
  final candidates = buttons.evaluate().toList(growable: false);
  final firstIndex = random.nextInt(candidates.length);
  var opened = false;
  for (var attempt = 0; attempt < candidates.length; attempt++) {
    final candidate = candidates[(firstIndex + attempt) % candidates.length];
    await tester.tap(find.byWidget(candidate.widget), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 50));
    opened = await _waitForPlayerSurface(
      tester,
      outputDirectory,
      captureName:
          'cycle-${cycle.toString().padLeft(2, '0')}-${phasePrefix}_hwdec-blocked',
    );
    if (opened) {
      break;
    }
  }
  if (!opened) {
    throw StateError('第 $cycle 轮 $phasePrefix 可见视频均被兼容性保护阻止');
  }
  await _pumpContinuously(tester, const Duration(seconds: 3));
  frameSampler.flush();

  frameSampler.begin('${phasePrefix}_seek', cycle);
  await _setStressPhase(outputDirectory, '${phasePrefix}_seek', cycle);
  final surface = find.byKey(const ValueKey('player.video.surface'));
  for (var index = 0; index < 3; index++) {
    await _randomlySeek(tester, random, surface);
  }
  frameSampler.flush();

  frameSampler.begin('${phasePrefix}_diagnostics', cycle);
  await _setStressPhase(outputDirectory, '${phasePrefix}_diagnostics', cycle);
  await _samplePlaybackDiagnostics(tester, surface, cycle, phasePrefix);
  frameSampler.flush();
  await _signalDesktopCapture(
    outputDirectory,
    'cycle-${cycle.toString().padLeft(2, '0')}-$phasePrefix',
  );

  frameSampler.begin('${phasePrefix}_release', cycle);
  await _setStressPhase(outputDirectory, '${phasePrefix}_release', cycle);
  final back = find.byKey(const ValueKey('player.back')).hitTestable();
  if (back.evaluate().isEmpty) {
    throw StateError('第 $cycle 轮 $phasePrefix 返回按钮不可点击');
  }
  await tester.tap(back);
  await _pumpContinuously(tester, const Duration(seconds: 3));
  await _pumpUntil(
    tester,
    () => ltp.LibraryStressControl.isAvailable,
    const Duration(seconds: 10),
    '播放器退出后媒体库未恢复',
  );
  await ltp.LibraryStressControl.waitForPlayerRelease().timeout(
    const Duration(seconds: 12),
    onTimeout: () => throw StateError('播放器原生资源释放超时'),
  );
  frameSampler.flush();
}

/**
 * 持续等待播放器表面，并像真实用户一样处理异步出现的播放前确认弹窗。
 *
 * 高分辨率兼容性检查可能在快速点击后的媒体详情读取完成时才显示，不能只在固定
 * 50 ms 时点探测一次，否则会把正常的硬解风险提示误报为播放器启动超时。
 */
Future<bool> _waitForPlayerSurface(
  WidgetTester tester,
  Directory outputDirectory, {
  required String captureName,
}) async {
  final surface = find.byKey(const ValueKey('player.video.surface'));
  final hardwareCancel =
      find.byKey(const ValueKey('player.hwdecWarning.cancel')).hitTestable();
  final resumeContinue =
      find.byKey(const ValueKey('player.resume.continue')).hitTestable();
  final watch = Stopwatch()..start();
  while (surface.evaluate().isEmpty &&
      watch.elapsed < const Duration(seconds: 15)) {
    if (hardwareCancel.evaluate().isNotEmpty) {
      // 8K 软件解码保护不再允许压测自动放行；返回媒体库后换一个可播放样本。
      await _pumpContinuously(tester, const Duration(milliseconds: 500));
      await _signalDesktopCapture(outputDirectory, captureName);
      await tester.tap(hardwareCancel, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      return false;
    } else if (resumeContinue.evaluate().isNotEmpty) {
      // 重复随机命中已有进度的视频时，继续播放而不是让弹窗阻塞压力循环。
      await tester.tap(resumeContinue, warnIfMissed: false);
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (surface.evaluate().isEmpty) {
    throw StateError('等待播放器表面超时');
  }
  return true;
}

/** 快速交替拖动当前媒体库，模拟用户停止在随机位置后等待可见缩略图。 */
Future<void> _rapidlyScrollLibrary(WidgetTester tester, Random random) async {
  final grid = find.byType(GridView);
  if (grid.evaluate().isEmpty) {
    return;
  }
  for (var index = 0; index < 6; index++) {
    final direction = random.nextBool() ? 1.0 : -1.0;
    await tester.drag(
      grid.first,
      Offset(0, direction * (350 + random.nextInt(900))),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/** 随机点击播放器进度轨道，每次等待真实 seek worker 完成。 */
Future<void> _randomlySeek(
  WidgetTester tester,
  Random random,
  Finder videoSurface,
) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: tester.getCenter(videoSurface));
  await mouse.moveTo(tester.getCenter(videoSurface));
  await tester.pump(const Duration(milliseconds: 120));
  final progress = find.descendant(
    of: videoSurface,
    matching: find.byWidgetPredicate(
      (widget) => widget is Slider && widget.max > 1000,
    ),
  );
  if (progress.evaluate().isNotEmpty) {
    final rect = tester.getRect(progress.first);
    final fraction = 0.05 + random.nextDouble() * 0.9;
    await tester
        .tapAt(Offset(rect.left + rect.width * fraction, rect.center.dy));
    await _pumpContinuously(tester, const Duration(milliseconds: 900));
  }
  await mouse.removePointer();
}

/** 打开诊断页采样实际硬解、AV offset、两路推进和最近 seek 延迟。 */
Future<void> _samplePlaybackDiagnostics(
  WidgetTester tester,
  Finder videoSurface,
  int cycle,
  String phase,
) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: tester.getCenter(videoSurface));
  await mouse.moveTo(tester.getCenter(videoSurface));
  await tester.pump(const Duration(milliseconds: 150));
  await tester.tap(find.byKey(const ValueKey('player.settings')));
  await tester.pump(const Duration(milliseconds: 250));
  final open = find.byKey(const ValueKey('player.diagnostics.open'));
  if (open.evaluate().isEmpty) {
    await mouse.removePointer();
    throw StateError('播放器诊断入口不存在');
  }
  await tester.tap(open);
  await _pumpContinuously(tester, const Duration(seconds: 3));
  final prefixes = <String>[
    'mpv 请求硬解:',
    'mpv 实际硬解:',
    '估算单帧耗时:',
    'mpv AV 偏移:',
    '视频帧推进:',
    '视频停滞事件:',
    '音频播放头推进:',
    '音频停滞事件:',
    '最近 seek 耗时:',
    '媒体详情活动读取:',
    '媒体详情排队读取:',
  ];
  final metrics = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final data = (element.widget as Text).data;
    if (data == null) continue;
    for (final line in data.split('\n')) {
      if (prefixes.any(line.startsWith)) metrics.add(line);
    }
  }
  // ignore: avoid_print
  print('PLAYER_DIAGNOSTICS cycle=$cycle phase=$phase ${metrics.join(' | ')}');
  await tester.tap(find.byKey(const ValueKey('player.diagnostics.close')));
  await _pumpContinuously(tester, const Duration(milliseconds: 300));
  await mouse.removePointer();
}

/** 等待异步数据库/扫描任务时持续以 50 ms 驱动 Flutter 帧。 */
Future<T> _awaitWithPumping<T>(WidgetTester tester, Future<T> future) async {
  var completed = false;
  Object? failure;
  StackTrace? failureStack;
  T? value;
  future.then((result) {
    value = result;
    completed = true;
  }, onError: (Object error, StackTrace stack) {
    failure = error;
    failureStack = stack;
    completed = true;
  });
  while (!completed) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureStack!);
  }
  return value as T;
}

/** 等待 UI 差量结果追平内存总量，并返回添加/移除后的可见刷新延迟。 */
Future<Duration> _waitForUiCount(WidgetTester tester) async {
  final watch = Stopwatch()..start();
  await _pumpUntil(
    tester,
    () {
      final snapshot = ltp.LibraryStressControl.snapshot();
      return snapshot.visibleCount == snapshot.videoCount;
    },
    const Duration(seconds: 15),
    '媒体库 UI 结果数未追平 SQLite 内存索引',
  );
  watch.stop();
  return watch.elapsed;
}

/** 返回当前可命中的媒体库播放按钮。 */
Finder _visibleLibraryPlayButtons() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          (key.value.startsWith('smoke.card.play:') ||
              key.value.startsWith('smoke.list.play:'));
    }).hitTestable();

/** 统计当前已构建 Image 数量，作为可见缩略图填充的轻量观测值。 */
/** 统计惰性列表当前已构建的缩略图；Image 本身不接收点击，不能用 hitTestable 过滤。 */
int _visibleImageCount() => find.byType(Image).evaluate().length;

/** 持续驱动帧直到 Finder 出现。 */
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) =>
    _pumpUntil(
      tester,
      () => finder.evaluate().isNotEmpty,
      timeout,
      '等待目标 UI 超时',
    );

/** 以小步泵帧等待任意状态条件，避免人为制造阶梯帧。 */
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
  Duration timeout,
  String error,
) async {
  final watch = Stopwatch()..start();
  while (!condition() && watch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (!condition()) throw StateError(error);
}

/** 长等待继续以 50 ms 小步驱动真实 Flutter 帧。 */
Future<void> _pumpContinuously(
  WidgetTester tester,
  Duration duration,
) async {
  const step = Duration(milliseconds: 50);
  final watch = Stopwatch()..start();
  while (watch.elapsed < duration) {
    final remaining = duration - watch.elapsed;
    await tester.pump(remaining < step ? remaining : step);
  }
}

/** 写入不包含本地媒体路径的数据库、缓存和解析状态。 */
void _writeStatus(
  File file, {
  required String profilePath,
  required String phase,
  required int cycle,
  required Duration elapsed,
  required ltp.LibraryStressSnapshot snapshot,
  Duration? uiLatency,
  ltp.LibraryScanCommitResult? scanResult,
  int? removedCount,
  int? visibleImages,
}) {
  final database = File('$profilePath\\library.db');
  final wal = File('$profilePath\\library.db-wal');
  final row = <String, Object?>{
    'timestamp': DateTime.now().toIso8601String(),
    'phase': phase,
    'cycle': cycle,
    'elapsedMs': elapsed.inMicroseconds / 1000,
    'uiLatencyMs': uiLatency?.inMicroseconds == null
        ? null
        : uiLatency!.inMicroseconds / 1000,
    'videoCount': snapshot.videoCount,
    'visibleCount': snapshot.visibleCount,
    'rootCount': snapshot.roots.length,
    'thumbnailQueued': snapshot.thumbnailQueued,
    'thumbnailActive': snapshot.thumbnailActive,
    'probeQueued': snapshot.probeQueued,
    'probeActive': snapshot.probeActive,
    'probeCompleted': snapshot.probeCompleted,
    'probeFailed': snapshot.probeFailed,
    'visibleImages': visibleImages,
    'databaseBytes': database.existsSync() ? database.lengthSync() : 0,
    'walBytes': wal.existsSync() ? wal.lengthSync() : 0,
    'addedCount': scanResult?.addedCount,
    'modifiedCount': scanResult?.modifiedCount,
    'relinkedCount': scanResult?.relinkedCount,
    'missingCount': scanResult?.missingCount,
    'removedCount': removedCount,
  };
  file.writeAsStringSync('${jsonEncode(row)}\n', mode: FileMode.append);
}

/** 通知外部监控器当前阶段。 */
Future<void> _setStressPhase(
  Directory outputDirectory,
  String phase,
  int cycle,
) async {
  File('${outputDirectory.path}\\phase.current')
      .writeAsStringSync('$phase|$cycle');
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

/** 通知外部像素截图器保存关键阶段。 */
Future<void> _signalDesktopCapture(
  Directory outputDirectory,
  String name,
) async {
  File('${outputDirectory.path}\\$name.ready').writeAsStringSync('ready');
  await Future<void>.delayed(const Duration(milliseconds: 250));
}

/** 等待外部 gdigrab 录屏器真正启动后再开始十轮计时。 */
Future<void> _waitForRecorder(
  WidgetTester tester,
  Directory outputDirectory,
) =>
    _pumpUntil(
      tester,
      () => File('${outputDirectory.path}\\recorder-ready.ready').existsSync(),
      const Duration(seconds: 30),
      '像素录屏器未在 30 秒内就绪',
    );

/** 读取必需环境变量，避免误用真实 profile 或错误 root。 */
String _requiredEnvironment(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) throw StateError('缺少环境变量 $name');
  return value;
}

/** Windows root 比较只用于测试前后断言，不改变业务路径规则。 */
bool _samePath(String left, String right) =>
    left.replaceAll('/', '\\').toLowerCase() ==
    right.replaceAll('/', '\\').toLowerCase();

/** 按阶段汇总真实 Flutter 帧 build/raster/总耗时与慢帧数量。 */
class _PhaseFrameSampler {
  _PhaseFrameSampler(this.output) {
    ltp.LibraryCardUiDiagnostics.beginPhase(_phase, _cycle);
  }

  final File output;
  final List<ui.FrameTiming> _frames = [];
  String _phase = 'startup';
  int _cycle = 0;

  /** Flutter 引擎回调只追加轻量不可变帧样本。 */
  void onTimings(List<ui.FrameTiming> timings) => _frames.addAll(timings);

  /** 开始新的业务阶段；先提交上一阶段，避免跨阶段混合样本。 */
  void begin(String phase, int cycle) {
    flush();
    ltp.LibraryCardUiDiagnostics.beginPhase(phase, cycle);
    _phase = phase;
    _cycle = cycle;
  }

  /** 将当前阶段帧统计写入 JSONL，并清空内存样本。 */
  void flush() {
    if (_frames.isEmpty) return;
    final builds = _frames
        .map((frame) => frame.buildDuration.inMicroseconds / 1000)
        .toList();
    final rasters = _frames
        .map((frame) => frame.rasterDuration.inMicroseconds / 1000)
        .toList();
    final totals =
        _frames.map((frame) => frame.totalSpan.inMicroseconds / 1000).toList();
    final row = <String, Object?>{
      'timestamp': DateTime.now().toIso8601String(),
      'phase': _phase,
      'cycle': _cycle,
      'frames': _frames.length,
      'buildP95Ms': _percentile(builds, 0.95),
      'buildMaxMs': builds.reduce(max),
      'rasterP95Ms': _percentile(rasters, 0.95),
      'rasterMaxMs': rasters.reduce(max),
      'totalP95Ms': _percentile(totals, 0.95),
      'totalMaxMs': totals.reduce(max),
      'over16ms': totals.where((value) => value > 16.7).length,
      'over33ms': totals.where((value) => value > 33.3).length,
    };
    output.writeAsStringSync('${jsonEncode(row)}\n', mode: FileMode.append);
    _frames.clear();
  }

  /** 使用最近秩计算小样本 P95，避免插值掩盖单次卡顿。 */
  double _percentile(List<double> values, double percentile) {
    final sorted = List<double>.of(values)..sort();
    final index = ((sorted.length - 1) * percentile).round();
    return sorted[index.clamp(0, sorted.length - 1)];
  }
}
