import 'dart:io';
import 'dart:math';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/main.dart' as app;

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
    final random = Random(seed);
    var cycle = 0;

    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 15));
    await _signalDesktopCapture('stress-00m-start');
    // 压测时长从真实媒体库完成初始化后开始，避免大型数据库加载吞掉运行预算。
    final deadline = DateTime.now().add(Duration(seconds: durationSeconds));
    var nextCapture = DateTime.now().add(const Duration(minutes: 5));

    while (DateTime.now().isBefore(deadline)) {
      await _ensureLibraryPage(tester);
      await _randomizeLibraryViewport(tester, random);

      final playButtons = _visibleLibraryPlayButtons();
      if (playButtons.isEmpty) {
        throw StateError('真实媒体库当前视口没有可播放视频按钮');
      }
      final selected = playButtons[random.nextInt(playButtons.length)];
      await tester.tap(selected);
      await tester.pumpAndSettle(const Duration(seconds: 12));

      final videoSurface = find.byKey(const ValueKey('player.video.surface'));
      if (videoSurface.evaluate().isEmpty) {
        throw StateError('随机视频未进入播放器页面');
      }

      await _randomlyScrollQueue(tester, random);
      await _randomlySeek(tester, random, videoSurface);
      await _toggleFullscreenRoundTrip(tester);
      await _randomlySeek(tester, random, videoSurface);
      await _samplePlaybackDiagnostics(tester, videoSurface, cycle + 1);

      final back = find.byKey(const ValueKey('player.back')).hitTestable();
      if (back.evaluate().isEmpty) {
        throw StateError('播放器返回按钮当前不可点击');
      }
      await tester.tap(back);
      await tester.pump(const Duration(seconds: 4));
      cycle++;

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

/** 确保循环从媒体库页面开始；播放器残留时通过页面内返回按钮退出。 */
Future<void> _ensureLibraryPage(WidgetTester tester) async {
  // 路由反向动画会短暂保留 offstage 播放器；只点击当前真正可命中的返回按钮。
  final back = find.byKey(const ValueKey('player.back')).hitTestable();
  if (back.evaluate().isNotEmpty) {
    await tester.tap(back);
    await tester.pump(const Duration(seconds: 4));
  }
  if (_visibleLibraryPlayButtons().isEmpty) {
    await tester.pump(const Duration(seconds: 3));
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
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/** 返回当前视口已经构建且命中播放 key 协议的媒体库按钮。 */
List<Finder> _visibleLibraryPlayButtons() {
  final finder = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        (key.value.startsWith('smoke.card.play:') ||
            key.value.startsWith('smoke.list.play:'));
  }).hitTestable();
  return <Finder>[
    for (var index = 0; index < finder.evaluate().length; index++)
      finder.at(index),
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
    await tester.pump(const Duration(milliseconds: 900));
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
  await tester.pump(const Duration(seconds: 1));
  await tester.tap(toggle);
  await tester.pump(const Duration(seconds: 1));
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
  await tester.pump(const Duration(seconds: 4));

  final metricPrefixes = <String>[
    'mpv 请求硬解:',
    'mpv 实际硬解:',
    '估算单帧耗时:',
    'mpv AV 偏移:',
    '最近 seek 耗时:',
    '媒体详情活动读取:',
    '媒体详情排队读取:',
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
  await tester.pump(const Duration(milliseconds: 500));
  await mouse.removePointer();
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
