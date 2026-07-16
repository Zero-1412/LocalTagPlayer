import 'dart:io';
import 'dart:math';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/main.dart' as app;
import 'package:local_tag_player/src/app.dart' as ltp;

// ignore_for_file: slash_for_doc_comments

/**
 * 使用真实媒体库执行播放器长时间随机压力测试。
 *
 * 测试仅通过 Flutter Finder 与手势驱动应用，不创建 Windows UIA 客户端；
 * 外部脚本只根据 marker 做窗口像素截图与进程指标采样。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实媒体库播放器随机压力测试', (tester) async {
    final durationSeconds = int.tryParse(
          Platform.environment['LOCAL_TAG_PLAYER_STRESS_SECONDS'] ?? '',
        ) ??
        1800;
    final seed = int.tryParse(
          Platform.environment['LOCAL_TAG_PLAYER_STRESS_SEED'] ?? '',
        ) ??
        20260713;
    final targetMediaPath =
        Platform.environment['LOCAL_TAG_PLAYER_STRESS_MEDIA_PATH']?.trim();
    final random = Random(seed);
    var cycle = 0;

    await app.main();
    await _waitForLibraryReady(tester);
    if (targetMediaPath != null && targetMediaPath.isNotEmpty) {
      await _filterToTargetMedia(tester, targetMediaPath);
    }
    await _setStressPhase('library_ready', 0);
    await _signalDesktopCapture('stress-00m-start');
    await _waitForScreenRecorder();
    // 压测时长从真实媒体库完成初始化后开始，避免大型数据库加载吞掉运行预算。
    final deadline = DateTime.now().add(Duration(seconds: durationSeconds));
    var nextCapture = DateTime.now().add(const Duration(minutes: 5));

    while (DateTime.now().isBefore(deadline)) {
      await _ensureLibraryPage(tester);
      if (targetMediaPath == null || targetMediaPath.isEmpty) {
        await _randomizeLibraryViewport(tester, random);
      }

      final playButtons = targetMediaPath == null || targetMediaPath.isEmpty
          ? _visibleLibraryPlayButtons()
          : _targetMediaPlayButtons(targetMediaPath);
      if (playButtons.isEmpty) {
        throw StateError('真实媒体库当前视口没有可播放视频按钮');
      }
      final selected = playButtons[random.nextInt(playButtons.length)];
      _logAction(cycle + 1, 'open_player');
      await _setStressPhase('player_startup', cycle + 1);
      await tester.tap(selected);
      await _pumpContinuously(tester, const Duration(seconds: 12));

      final videoSurface = find.byKey(const ValueKey('player.video.surface'));
      if (videoSurface.evaluate().isEmpty) {
        throw StateError('随机视频未进入播放器页面');
      }
      await _setStressPhase('player_stable', cycle + 1);

      _logAction(cycle + 1, 'queue_scroll_start');
      await _randomlyScrollQueue(tester, random);
      _logAction(cycle + 1, 'seek_1');
      await _randomlySeek(tester, random, videoSurface);
      _logAction(cycle + 1, 'fullscreen_roundtrip');
      await _toggleFullscreenRoundTrip(tester);
      _logAction(cycle + 1, 'seek_2');
      await _randomlySeek(tester, random, videoSurface);
      _logAction(cycle + 1, 'diagnostics');
      await _samplePlaybackDiagnostics(tester, videoSurface, cycle + 1);

      final back = find.byKey(const ValueKey('player.back')).hitTestable();
      if (back.evaluate().isEmpty) {
        throw StateError('播放器返回按钮当前不可点击');
      }
      _logAction(cycle + 1, 'exit_player');
      await _setStressPhase('player_release', cycle + 1);
      await tester.tap(back);
      await _pumpContinuously(tester, const Duration(seconds: 4));
      cycle++;
      await _setStressPhase('library_idle', cycle);

      final now = DateTime.now();
      if (!now.isBefore(nextCapture)) {
        final elapsedMinutes =
            ((durationSeconds - deadline.difference(now).inSeconds)
                    .clamp(0, durationSeconds) /
                60);
        final label = elapsedMinutes.floor().toString().padLeft(2, '0');
        await _signalDesktopCapture('stress-${label}m-cycle-$cycle');
        nextCapture = now.add(const Duration(minutes: 5));
      }
      // 只输出匿名循环状态，不把用户文件名或路径写入压力测试日志。
      // ignore: avoid_print
      print('PLAYER_STRESS cycle=$cycle seed=$seed remaining_s='
          '${deadline.difference(DateTime.now()).inSeconds.clamp(0, durationSeconds)}');
    }

    await _signalDesktopCapture('stress-30m-complete');
    expect(cycle, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 40)));
}

/**
 * 通过稳定搜索输入链路把真实媒体库收敛到指定样本，并只按匿名路径 key 验证命中。
 *
 * 路径只来自本机测试环境变量，不写入测试日志或压测产物。
 */
Future<void> _filterToTargetMedia(
  WidgetTester tester,
  String targetPath,
) async {
  final search = find.byKey(ltp.LibrarySmokeKeys.searchField);
  if (search.evaluate().isEmpty) {
    throw StateError('媒体库稳定搜索输入不存在');
  }
  final fileName = targetPath.split(Platform.pathSeparator).last;
  final extension = fileName.lastIndexOf('.');
  final query = extension > 0 ? fileName.substring(0, extension) : fileName;
  await tester.enterText(search, query);
  final stopwatch = Stopwatch()..start();
  while (_targetMediaPlayButtons(targetPath).isEmpty &&
      stopwatch.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (_targetMediaPlayButtons(targetPath).isEmpty) {
    throw StateError('指定真实媒体样本未进入可见结果');
  }
}

/** 等待外部像素录屏器就绪后才开始三分钟压力计时。 */
Future<void> _waitForScreenRecorder() async {
  if (Platform.environment['LOCAL_TAG_PLAYER_RECORDING_HANDSHAKE'] != '1') {
    return;
  }
  final outputPath = Platform.environment['LOCAL_TAG_PLAYER_STRESS_OUTPUT'];
  if (outputPath == null || outputPath.isEmpty) {
    throw StateError('录屏握手缺少压力测试输出目录');
  }
  final ready = File('$outputPath\\recorder-ready.ready');
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready.existsSync() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (!ready.existsSync()) {
    throw StateError('像素录屏器未在 30 秒内就绪');
  }
  _logAction(0, 'recording_started');
}

/** 输出不包含文件名和路径的操作时间标记，供逐帧分析对齐。 */
void _logAction(int cycle, String action) {
  // ignore: avoid_print
  print('PLAYER_ACTION timestamp=${DateTime.now().toIso8601String()} '
      'cycle=$cycle action=$action');
}

/** 确保循环从媒体库页面开始；播放器残留时通过页面内返回按钮退出。 */
Future<void> _ensureLibraryPage(WidgetTester tester) async {
  // 路由反向动画会短暂保留 offstage 播放器；只点击当前真正可命中的返回按钮。
  final back = find.byKey(const ValueKey('player.back')).hitTestable();
  if (back.evaluate().isNotEmpty) {
    await tester.tap(back);
    await _pumpContinuously(tester, const Duration(seconds: 4));
  }
  if (_visibleLibraryPlayButtons().isEmpty) {
    await _waitForLibraryReady(
      tester,
      timeout: const Duration(seconds: 30),
    );
  }
}

/** 持续驱动帧直到媒体库真实播放入口出现，不用固定大步 pump 猜测初始化耗时。 */
Future<void> _waitForLibraryReady(
  WidgetTester tester, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  final stopwatch = Stopwatch()..start();
  while (_visibleLibraryPlayButtons().isEmpty && stopwatch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (_visibleLibraryPlayButtons().isEmpty) {
    throw StateError('真实媒体库未在 ${timeout.inSeconds} 秒内完成可播放入口加载');
  }
}

/** 在媒体库结果中随机上下拖动，扩大实际样本覆盖范围。 */
Future<void> _randomizeLibraryViewport(
  WidgetTester tester,
  Random random,
) async {
  final grid = find.byType(GridView);
  if (grid.evaluate().isEmpty) {
    return;
  }
  final direction = random.nextBool() ? 1.0 : -1.0;
  final distance = 250.0 + random.nextDouble() * 700.0;
  await tester.drag(grid.first, Offset(0, direction * distance));
  await _pumpContinuously(tester, const Duration(seconds: 2));
}

/** 返回当前视口已经构建且命中播放 key 协议的媒体库按钮。 */
List<Finder> _visibleLibraryPlayButtons() {
  final finder = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        (key.value.startsWith('smoke.card.open:') ||
            key.value.startsWith('smoke.list.play:'));
  }).hitTestable();
  return <Finder>[
    for (var index = 0; index < finder.evaluate().length; index++)
      finder.at(index),
  ];
}

/** 返回指定真实媒体的网格或列表播放入口，不暴露本地路径。 */
List<Finder> _targetMediaPlayButtons(String targetPath) {
  final candidates = <Finder>[
    find.byKey(ltp.LibrarySmokeKeys.cardOpen(targetPath)).hitTestable(),
    find.byKey(ltp.LibrarySmokeKeys.listPlay(targetPath)).hitTestable(),
  ];
  return [
    for (final candidate in candidates)
      if (candidate.evaluate().isNotEmpty) candidate
  ];
}

/** 在当前 filtered queue 内执行多次随机方向拖动，不改变队列来源。 */
Future<void> _randomlyScrollQueue(
  WidgetTester tester,
  Random random,
) async {
  final sidebar = find.byKey(const ValueKey('player.queue.sidebar'));
  if (sidebar.evaluate().isEmpty) {
    return;
  }
  final scrollables = find.descendant(
    of: sidebar,
    matching: find.byType(Scrollable),
  );
  if (scrollables.evaluate().isEmpty) {
    return;
  }
  final queue = scrollables.last;
  final count = 3 + random.nextInt(6);
  for (var index = 0; index < count; index++) {
    final direction = random.nextBool() ? 1.0 : -1.0;
    await tester.drag(
        queue, Offset(0, direction * (300 + random.nextInt(700))));
    await tester.pump(const Duration(milliseconds: 180));
  }
}

/** 随机点击播放器进度轨道，覆盖向前与向后跳转。 */
Future<void> _randomlySeek(
  WidgetTester tester,
  Random random,
  Finder videoSurface,
) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: tester.getCenter(videoSurface));
  await mouse.moveTo(tester.getCenter(videoSurface));
  await tester.pump(const Duration(milliseconds: 250));
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

/** 进入并退出桌面全屏，保证每轮结束时回到普通播放器布局。 */
Future<void> _toggleFullscreenRoundTrip(WidgetTester tester) async {
  final toggle = find.byKey(const ValueKey('player.fullscreen.toggle'));
  if (toggle.evaluate().isEmpty) {
    throw StateError('播放器全屏按钮不存在');
  }
  await tester.tap(toggle);
  await _pumpContinuously(tester, const Duration(seconds: 1));
  await tester.tap(toggle);
  await _pumpContinuously(tester, const Duration(seconds: 1));
}

/**
 * 打开真实诊断弹窗持续采样，并把不含本地路径的关键指标写入测试日志。
 */
Future<void> _samplePlaybackDiagnostics(
  WidgetTester tester,
  Finder videoSurface,
  int cycle,
) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: tester.getCenter(videoSurface));
  await mouse.moveTo(tester.getCenter(videoSurface));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.tap(find.byKey(const ValueKey('player.settings')));
  await tester.pump(const Duration(milliseconds: 300));
  final open = find.byKey(const ValueKey('player.diagnostics.open'));
  if (open.evaluate().isEmpty) {
    await mouse.removePointer();
    throw StateError('播放器诊断菜单项不存在');
  }
  await tester.tap(open);
  await _pumpContinuously(tester, const Duration(seconds: 4));

  final metricPrefixes = <String>[
    'mpv 请求硬解:',
    'mpv 实际硬解:',
    '估算单帧耗时:',
    'mpv AV 偏移:',
    '最近 seek 耗时:',
    '媒体详情活动读取:',
    '媒体详情排队读取:',
    '原生渲染请求:',
    '原生实际渲染帧:',
    '原生跳过渲染:',
    '原生纹理复制:',
    '原生表面重建:',
    '原生表面尺寸:',
    '视频帧推进:',
    '视频当前帧号:',
    '视频停滞事件:',
    '音频播放头推进:',
    '音频当前 PTS:',
    '音频停滞事件:',
    '退出请求时间:',
    '暂停确认时间:',
    '路由退出请求时间:',
  ];
  final metricLines = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final data = (element.widget as Text).data;
    if (data == null) {
      continue;
    }
    for (final line in data.split('\n')) {
      if (metricPrefixes.any(line.startsWith)) {
        metricLines.add(line);
      }
    }
  }
  // ignore: avoid_print
  print('PLAYER_DIAGNOSTICS cycle=$cycle ${metricLines.join(' | ')}');
  if (cycle == 1 || cycle % 5 == 0) {
    await _signalDesktopCapture('stress-diagnostics-cycle-$cycle');
  }
  await tester.tap(find.byKey(const ValueKey('player.diagnostics.close')));
  await _pumpContinuously(tester, const Duration(milliseconds: 500));
  await mouse.removePointer();
}

/**
 * 以 50 ms 小步持续驱动 Flutter 帧，等待期间仍允许原生视频纹理和点击反馈刷新。
 *
 * `pumpAndSettle(Duration)` 的位置参数是单次 pump 步长而不是超时；传入数秒会人为制造
 * 数秒只提交一帧的假卡顿，因此压力测试的长等待必须统一走该方法。
 */
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

/** 通知外部纯像素捕获器保存当前真实窗口，不读取 Windows 语义树。 */
Future<void> _signalDesktopCapture(String name) async {
  final outputPath = Platform.environment['LOCAL_TAG_PLAYER_STRESS_OUTPUT'];
  if (outputPath == null || outputPath.isEmpty) {
    return;
  }
  final outputDirectory = Directory(outputPath)..createSync(recursive: true);
  File('${outputDirectory.path}\\$name.ready').writeAsStringSync('ready');
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

/**
 * 把当前生命周期阶段写给外部只读进程采样器，用于区分启动、稳定播放和释放区间。
 */
Future<void> _setStressPhase(String phase, int cycle) async {
  final outputPath = Platform.environment['LOCAL_TAG_PLAYER_STRESS_OUTPUT'];
  if (outputPath == null || outputPath.isEmpty) {
    return;
  }
  File('$outputPath\\phase.current').writeAsStringSync('$phase|$cycle');
  await Future<void>.delayed(const Duration(milliseconds: 50));
}
