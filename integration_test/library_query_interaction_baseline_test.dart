import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/main.dart' as app;
import 'package:local_tag_player/src/pages/library/library_page.dart';
import 'package:local_tag_player/src/pages/library/library_page_state_host.dart';
import 'package:local_tag_player/src/pages/player/player_page.dart';
import 'package:local_tag_player/src/widgets/library/library_smoke_keys.dart';
import 'support/phase_frame_recorder.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 隔离真实库上的页面级交互基线。Finder 驱动生产页面，不代表原生鼠标/选择器验收。
 * 必须显式提供带标记的可丢弃 profile；结果只保存数量、时延和帧统计，不输出媒体文本。
 */
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // 让生产动画自然逐帧运行；默认 fadePointers/onlyPumps 会把测试等待误作长帧。
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('隔离大库查询、排序、标签和播放返回基线', (tester) async {
    // integration_test 默认不注册模拟输入；显式接入后才可用 enterText 驱动 TextField。
    // 这仍是 Flutter 输入协议注入，不声称覆盖原生 IME 或硬件键盘。
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final profile = Platform.environment['LOCAL_TAG_PLAYER_DATA_DIR'];
    if (profile == null ||
        !File('$profile/.query-baseline-profile').existsSync()) {
      throw StateError('必须提供带 .query-baseline-profile 标记的隔离 profile');
    }
    final output = Directory('$profile/evidence')..createSync();
    final samples = <String, List<double>>{};
    final recorder = PhaseFrameRecorder();
    final startupOnly =
        Platform.environment['LOCAL_TAG_PLAYER_BASELINE_STARTUP_ONLY'] == '1';
    final scanOnly =
        Platform.environment['LOCAL_TAG_PLAYER_BASELINE_SCAN_ONLY'] == '1';
    final repeats = int.tryParse(
            Platform.environment['LOCAL_TAG_PLAYER_BASELINE_REPEATS'] ?? '') ??
        20;
    final eventGaps = <double>[];
    final eventGapsByMode = <String, List<double>>{};
    Timer? eventTimer;
    final unavailable = <String>[];
    var scanActiveSearches = 0;
    var completed = false;
    final startedAt = DateTime.now().toUtc().toIso8601String();
    WidgetsBinding.instance.addTimingsCallback(recorder.collect);
    final startup = Stopwatch()..start();
    try {
      await app.main();
      await _until(
          tester, () => find.byType(LibraryPage).evaluate().isNotEmpty);
      final host =
          tester.state(find.byType(LibraryPage)) as LibraryPageStateHost;
      final runtime = host.runtime;
      await _until(
          tester,
          () =>
              runtime.queryController.state != null &&
              find
                  .byKey(LibrarySmokeKeys.searchField)
                  .hitTestable()
                  .evaluate()
                  .isNotEmpty);
      samples['startup_profile'] = [startup.elapsedMicroseconds / 1000];
      stdout.writeln('LTP_BASELINE_ACTIONABLE');
      expect(runtime.store!.videos.length, greaterThanOrEqualTo(2000));
      recorder.enter('idle');
      await tester.pump(const Duration(milliseconds: 600));

      Future<void> measure(String name, Future<void> Function() action,
          bool Function() completed) async {
        await _dismissDiscoveryPrompt(tester);
        stdout.writeln(
            'LTP_PHASE action=$name sample=${samples[name]?.length ?? 0}');
        recorder.enter(name);
        final dataBefore =
            host.resultEpoch(host.currentFilterQuery()).dataRevision;
        final requestBefore = runtime.queryController.revision;
        final watch = Stopwatch()..start();
        await action();
        try {
          await _until(tester, completed);
        } on Object {
          recorder.failCurrentPhase();
          recorder.enter('failure_capture');
          await File('${output.path}/failure-state.json')
              .writeAsString(jsonEncode({
            'stage': name,
            'dataRevisionBefore': dataBefore,
            'dataRevisionAfter':
                host.resultEpoch(host.currentFilterQuery()).dataRevision,
            'requestRevisionBefore': requestBefore,
            'requestRevisionAfter': runtime.queryController.revision,
            'inputLength': runtime.searchController.text.length,
            'requestedLength':
                runtime.queryController.requestedQuery?.keyword?.length,
            'acceptedLength':
                runtime.queryController.state?.query.keyword?.length,
            'inputObserved':
                runtime.searchController.text == runtime.lastObservedSearchText,
            'refreshing': runtime.isRefreshingVideos,
            'queuedInput': runtime.searchControllerChangeQueued,
            'epochCurrent': runtime.queryController.state?.epoch ==
                host.resultEpoch(host.currentFilterQuery()),
          }));
          await _capture(tester, '${output.path}/failure.png');
          rethrow;
        }
        // 结果发布后再经过一帧，避免把仅 controller 完成误报为可见结果。
        await tester.pump();
        samples
            .putIfAbsent(name, () => [])
            .add(watch.elapsedMicroseconds / 1000);
        // 本次计时结束后等待布局稳定，避免下一次点击命中退场控件。
        await tester.pump(const Duration(milliseconds: 600));
        recorder.enter('idle');
      }

      final search = find.byKey(LibrarySmokeKeys.searchField);
      for (var n = 0;
          n <
              (startupOnly
                  ? 1
                  : scanOnly
                      ? 2
                      : 30);
          n++) {
        final query = n.isEven ? '不存在的基准词xyz' : '';
        await measure(
            n == 0 ? 'search_first' : 'search_warm',
            () => tester.enterText(search, query),
            () =>
                runtime.queryController.state?.query.keyword?.trim() == query &&
                !runtime.isRefreshingVideos);
      }
      if (startupOnly) {
        completed = true;
        return;
      }
      if (!scanOnly) {
        for (var n = 0; n < 20; n++) {
          final previous = runtime.sortController.fingerprint;
          await _dismissDiscoveryPrompt(tester);
          final sortButton = find.descendant(
              of: find.byKey(LibrarySmokeKeys.topSortDirectionButton),
              matching: find.byType(IconButton));
          if (n == 0) {
            final rect = tester.getRect(sortButton);
            await File('${output.path}/sort-hit-test.json')
                .writeAsString(jsonEncode({
              'center': [rect.center.dx, rect.center.dy],
              'size': [rect.width, rect.height],
              'view': [
                tester.view.physicalSize.width,
                tester.view.physicalSize.height
              ],
              'dpr': tester.view.devicePixelRatio,
              'hit': sortButton.hitTestable().evaluate().isNotEmpty,
            }));
          }
          await measure(
              'sort_warm',
              () => tester.tap(sortButton),
              () =>
                  runtime.sortController.fingerprint != previous &&
                  !runtime.isRefreshingVideos);
        }
        Future<void> openTags() async {
          if (!runtime.isTagDiscoveryPanelOpen) {
            final rail =
                find.byKey(LibrarySmokeKeys.collapsedTagRail).hitTestable();
            if (rail.evaluate().isNotEmpty) {
              await tester.tap(rail);
              await tester.pump(const Duration(milliseconds: 300));
            }
          }
        }

        // 展开/收起单列阶段，不能把动画准备工作混入标签查询的可见结果延迟。
        for (var n = 0; n < repeats; n++) {
          recorder.enter('tag_panel_animation');
          await openTags();
          final collapse =
              find.byKey(LibrarySmokeKeys.tagPanelCollapseHeader).hitTestable();
          await tester.tap(collapse);
          await tester.pump(const Duration(milliseconds: 600));
          recorder.enter('idle');
        }
        // 展开/收起的页面截图单列，截图开销不混入动画或查询分位数。
        recorder.enter('evidence_capture');
        await _capture(tester, '${output.path}/tag-panel-closed.png');
        await openTags();
        await _capture(tester, '${output.path}/tag-panel-open.png');
        recorder.enter('idle');
        final chips = find
            .byWidgetPredicate((w) =>
                w.key is ValueKey<String> &&
                ((w.key as ValueKey<String>)
                        .value
                        .startsWith('smoke.tag.primary-row:') ||
                    (w.key as ValueKey<String>)
                        .value
                        .startsWith('smoke.tag.primary-header:')))
            .hitTestable();
        final tagIds = chips
            .evaluate()
            .map((element) {
              final key = element.widget.key! as ValueKey<String>;
              return key.value.substring(key.value.indexOf(':') + 1);
            })
            .toSet()
            .take(2)
            .toList();
        if (tagIds.length < 2) {
          unavailable.add('tag_click: fewer than two visible primary groups');
        } else {
          for (var n = 0; n < 20; n++) {
            await openTags();
            final tagId = tagIds[n % tagIds.length];
            // 一级标题只展开分类；“默认专辑”才执行真实一级筛选，交替两组确保查询变化。
            final collapsed =
                find.byKey(LibrarySmokeKeys.primaryRow(tagId)).hitTestable();
            if (collapsed.evaluate().isNotEmpty) {
              recorder.enter('tag_group_animation');
              await tester.tap(collapsed);
              await tester.pump(const Duration(milliseconds: 600));
              recorder.enter('idle');
            }
            final old = runtime.queryController.state;
            final tagEntry = find
                .byKey(LibrarySmokeKeys.tagChip('$tagId::default-album'))
                .hitTestable();
            await measure(
                'tag_warm',
                () => tester.tap(tagEntry.first),
                () =>
                    runtime.queryController.state != old &&
                    !runtime.isRefreshingVideos);
          }
        }

        if (runtime.isMainSidebarCollapsed) {
          await tester.tap(find.byKey(LibrarySmokeKeys.sidebarCollapseToggle));
          await tester.pump(const Duration(milliseconds: 300));
        }
        for (var navigationRun = 0; navigationRun < repeats; navigationRun++) {
          final roots = find
              .byWidgetPredicate((w) =>
                  w.key is ValueKey<String> &&
                  (w.key as ValueKey<String>)
                      .value
                      .startsWith('smoke.local.root:'))
              .hitTestable();
          if (roots.evaluate().isEmpty) {
            unavailable.add('root_navigation: no visible root');
          } else {
            await measure('root_enter', () => tester.tap(roots.first),
                () => runtime.localLibraryPath != null);
            final rootPath = runtime.localLibraryPath;
            final folders = find
                .byWidgetPredicate((w) =>
                    w.key is ValueKey<String> &&
                    (w.key as ValueKey<String>)
                        .value
                        .startsWith('smoke.local.folder:'))
                .hitTestable();
            if (folders.evaluate().isNotEmpty) {
              await measure('folder_enter', () => tester.tap(folders.first),
                  () => runtime.localLibraryPath != rootPath);
            }
            final back =
                find.byKey(LibrarySmokeKeys.localBackButton).hitTestable();
            if (back.evaluate().isNotEmpty &&
                runtime.sourceNavigation.canGoBack) {
              await measure('root_back', () => tester.tap(back),
                  () => runtime.localLibraryPath == rootPath);
            } else {
              unavailable.add('root_back: no visible back button');
            }
            final library = find.byIcon(Icons.grid_view_rounded).first;
            await tester.ensureVisible(library);
            await measure('library_return', () => tester.tap(library),
                () => runtime.localLibraryPath == null);
          }
        }

        for (var playerRun = 0; playerRun < repeats; playerRun++) {
          Finder? play;
          for (final video in runtime.queryController.state!.filteredVideos) {
            final candidate =
                find.byKey(LibrarySmokeKeys.cardOpen(video.path)).hitTestable();
            if (candidate.evaluate().isNotEmpty &&
                await File(video.path).exists()) {
              play = candidate;
              break;
            }
          }
          if (play == null || runtime.localLibraryPath != null) {
            unavailable.add('filtered_playback_return: no library play entry');
          } else {
            final before = runtime.queryController.state!;
            final ids = before.filteredVideos.map((v) => v.videoId).toList();
            await measure('player_enter', () => tester.tap(play!.first),
                () => find.byType(PlayerPage).evaluate().isNotEmpty);
            final player = tester.widget<PlayerPage>(find.byType(PlayerPage));
            expect(player.playlist.map((v) => v.videoId).toList(), ids);
            await tester.pump(const Duration(seconds: 1));
            await measure(
                'player_return',
                () => tester.tap(
                    find.byKey(const ValueKey('player.back')).hitTestable()),
                () => find.byType(PlayerPage).evaluate().isEmpty);
            expect(runtime.queryController.state!.query.keyword,
                before.query.keyword);
          }
        }
      }
      if (Platform.environment['LOCAL_TAG_PLAYER_BASELINE_SCAN'] == '1') {
        // 先测纯扫描，再测扫描期间输入；热差量扫描很短，重复独立扫描补足样本。
        for (var scanRun = 0; scanRun < repeats; scanRun++) {
          final passive = scanRun.isEven;
          final scanPhase = passive ? 'scan_passive' : 'scan_with_input';
          stdout.writeln('LTP_PHASE scan=$scanPhase repeat=$scanRun');
          final retainedIds =
              runtime.store!.videos.values.map((v) => v.videoId).toSet();
          final scan = find.byKey(LibrarySmokeKeys.rescanButton);
          await tester.ensureVisible(scan);
          recorder.enter(scanPhase);
          final scanWatch = Stopwatch()..start();
          int? scanCompletedUs;
          var scanObserved = false;
          var lastTick = DateTime.now().microsecondsSinceEpoch;
          eventTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
            final now = DateTime.now().microsecondsSinceEpoch;
            // 只采扫描确实活动期间的间隙，不能让输入后的稳定等待稀释扫描长尾。
            if (runtime.isScanning) {
              scanObserved = true;
              eventGaps.add((now - lastTick) / 1000);
              eventGapsByMode
                  .putIfAbsent(scanPhase, () => [])
                  .add((now - lastTick) / 1000);
            } else if (scanObserved && scanCompletedUs == null) {
              scanCompletedUs = scanWatch.elapsedMicroseconds;
              // 包含阻塞到本次回调的尾部间隙，避免漏掉扫描完成时的长任务。
              eventGaps.add((now - lastTick) / 1000);
              eventGapsByMode
                  .putIfAbsent(scanPhase, () => [])
                  .add((now - lastTick) / 1000);
            }
            lastTick = now;
          });
          await tester.tap(scan);
          await _until(tester, () => runtime.isScanning);
          for (var n = 0; !passive && n < 10 && runtime.isScanning; n++) {
            final query = n.isEven ? '不存在的并发基准词xyz' : '';
            await measure(
                'search_during_scan',
                () => tester.enterText(search, query),
                () => runtime.queryController.state?.query.keyword == query);
            scanActiveSearches++;
            recorder.enter(scanPhase);
          }
          await _until(tester, () => !runtime.isScanning);
          samples
              .putIfAbsent('${scanPhase}_observed_total', () => [])
              .add((scanCompletedUs ?? scanWatch.elapsedMicroseconds) / 1000);
          eventTimer.cancel();
          recorder.enter('idle');
          expect(runtime.store!.videos.values.map((v) => v.videoId).toSet(),
              containsAll(retainedIds));
          await tester.enterText(search, '');
          await _until(
              tester, () => runtime.queryController.state?.query.keyword == '');
          await tester.pump(const Duration(milliseconds: 600));
        }
      }
      await _capture(tester, '${output.path}/library.png');
      completed = true;
    } finally {
      eventTimer?.cancel();
      recorder.enter('drain');
      // 引擎批量发送 FrameTiming；保留尾部等待，归属使用帧时间而非回调到达时间。
      await tester.pump(const Duration(seconds: 2));
      recorder.enter('finished');
      WidgetsBinding.instance.removeTimingsCallback(recorder.collect);
      final records = recorder.records();
      final timings = recorder.frames
          .map((f) => f.totalSpan.inMicroseconds / 1000)
          .toList();
      await File('${output.path}/interaction-summary.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert({
        'evidence': 'Flutter Finder, production page, profile build',
        'startedAt': startedAt,
        'completed': completed,
        'framePolicy': 'fullyLive',
        'startupScope':
            'Dart app.main to actionable LibraryPage; excludes process/engine bootstrap',
        'startupOnly': startupOnly,
        'scanOnly': scanOnly,
        'cacheState': Platform.environment['LOCAL_TAG_PLAYER_BASELINE_CACHE'] ??
            'uncontrolled',
        'actions':
            samples.map((key, values) => MapEntry(key, sampleStats(values))),
        'rawSamplesMs': samples,
        'framesAllPhases': sampleStats(timings),
        'framesByPhase': {
          for (final phase in records.map((r) => r['phase']).toSet())
            phase:
                frameStats(records.where((r) => r['phase'] == phase).toList()),
        },
        'phaseWindows': recorder.windows,
        'rawFrames': records,
        'scanEventLoopGapMs': sampleStats(eventGaps),
        'scanEventLoopGapByMode': eventGapsByMode
            .map((key, value) => MapEntry(key, sampleStats(value))),
        'slowFramesOver33ms': timings.where((ms) => ms > 33.3).length,
        'unavailable': unavailable,
        'nativeMouseVerified': false,
        'scanConcurrencyVerified': scanActiveSearches > 0,
        'searchesStartedDuringScan': scanActiveSearches,
      }));
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}

/** 有界等待真实事件循环，不用 pumpAndSettle 等待持续运行的媒体后台任务。 */
Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final watch = Stopwatch()..start();
  await _dismissDiscoveryPrompt(tester);
  while (!ready()) {
    if (watch.elapsed > const Duration(seconds: 45)) {
      throw StateError('页面状态等待超时');
    }
    await tester.pump(const Duration(milliseconds: 20));
    await _dismissDiscoveryPrompt(tester);
  }
}

/** 历史副本可能发现未入库文件；只通过生产“稍后”按钮关闭提示，不自动启动扫描。 */
Future<void> _dismissDiscoveryPrompt(WidgetTester tester) async {
  if (find.text('发现新增视频').evaluate().isNotEmpty) {
    final later = find.widgetWithText(TextButton, '稍后').hitTestable();
    if (later.evaluate().isNotEmpty) {
      await tester.tap(later);
      await tester.pump(const Duration(milliseconds: 300));
    }
  }
}

/** 截取 Flutter surface；不包含系统窗口边框和原生选择器。 */
Future<void> _capture(WidgetTester tester, String path) async {
  await tester.pump();
  final boundaries = find
      .byType(RepaintBoundary)
      .evaluate()
      .map((e) => e.renderObject)
      .whereType<RenderRepaintBoundary>()
      .toList()
    ..sort((a, b) =>
        (b.size.width * b.size.height).compareTo(a.size.width * a.size.height));
  final image = await boundaries.first.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  await File(path).writeAsBytes(bytes!.buffer.asUint8List());
}
