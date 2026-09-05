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

// ignore_for_file: slash_for_doc_comments

/**
 * 隔离真实库上的页面级交互基线。Finder 驱动生产页面，不代表原生鼠标/选择器验收。
 * 必须显式提供带标记的可丢弃 profile；结果只保存数量、时延和帧统计，不输出媒体文本。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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
    final frames = <ui.FrameTiming>[];
    final unavailable = <String>[];
    var scanActiveSearches = 0;
    var completed = false;
    final startedAt = DateTime.now().toUtc().toIso8601String();
    void collect(List<ui.FrameTiming> values) => frames.addAll(values);
    WidgetsBinding.instance.addTimingsCallback(collect);
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
      expect(runtime.store!.videos.length, greaterThanOrEqualTo(2000));

      Future<void> measure(String name, Future<void> Function() action,
          bool Function() completed) async {
        await _dismissDiscoveryPrompt(tester);
        final watch = Stopwatch()..start();
        await action();
        try {
          await _until(tester, completed);
        } on Object {
          await File('${output.path}/failure-state.json')
              .writeAsString(jsonEncode({
            'stage': name,
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
        await tester.pump(const Duration(milliseconds: 300));
      }

      final search = find.byKey(LibrarySmokeKeys.searchField);
      for (var n = 0; n < 30; n++) {
        final query = n.isEven ? '不存在的基准词xyz' : '';
        await measure(
            n == 0 ? 'search_first' : 'search_warm',
            () => tester.enterText(search, query),
            () =>
                runtime.queryController.state?.query.keyword?.trim() == query &&
                !runtime.isRefreshingVideos);
      }
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

      await openTags();
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
            await tester.tap(collapsed);
            await tester.pump(const Duration(milliseconds: 300));
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
      final roots = find
          .byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('smoke.local.root:'))
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
        final back = find.byKey(LibrarySmokeKeys.localBackButton).hitTestable();
        if (back.evaluate().isNotEmpty && runtime.sourceNavigation.canGoBack) {
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
        await tester.tap(play.first);
        await _until(
            tester, () => find.byType(PlayerPage).evaluate().isNotEmpty);
        final player = tester.widget<PlayerPage>(find.byType(PlayerPage));
        expect(player.playlist.map((v) => v.videoId).toList(), ids);
        await tester.pump(const Duration(seconds: 1));
        await measure(
            'player_return',
            () => tester
                .tap(find.byKey(const ValueKey('player.back')).hitTestable()),
            () => find.byType(PlayerPage).evaluate().isEmpty);
        expect(
            runtime.queryController.state!.query.keyword, before.query.keyword);
      }
      if (Platform.environment['LOCAL_TAG_PLAYER_BASELINE_SCAN'] == '1') {
        final retainedIds =
            runtime.store!.videos.values.map((v) => v.videoId).toSet();
        final scan = find.byKey(LibrarySmokeKeys.rescanButton);
        await tester.ensureVisible(scan);
        await tester.tap(scan);
        await _until(tester, () => runtime.isScanning);
        for (var n = 0; n < 10 && runtime.isScanning; n++) {
          final query = n.isEven ? '不存在的并发基准词xyz' : '';
          await measure(
              'search_during_scan',
              () => tester.enterText(search, query),
              () => runtime.queryController.state?.query.keyword == query);
          scanActiveSearches++;
        }
        await _until(tester, () => !runtime.isScanning);
        expect(runtime.store!.videos.values.map((v) => v.videoId).toSet(),
            containsAll(retainedIds));
        await tester.enterText(search, '');
        await _until(
            tester, () => runtime.queryController.state?.query.keyword == '');
      }
      await _capture(tester, '${output.path}/library.png');
      completed = true;
    } finally {
      WidgetsBinding.instance.removeTimingsCallback(collect);
      final timings =
          frames.map((f) => f.totalSpan.inMicroseconds / 1000).toList();
      await File('${output.path}/interaction-summary.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert({
        'evidence': 'Flutter Finder, production page, profile build',
        'startedAt': startedAt,
        'completed': completed,
        'cacheState': Platform.environment['LOCAL_TAG_PLAYER_BASELINE_CACHE'] ??
            'uncontrolled',
        'actions': samples.map((key, values) => MapEntry(key, _stats(values))),
        'rawSamplesMs': samples,
        'framesAllPhases': _stats(timings),
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

Map<String, Object?> _stats(List<double> values) {
  if (values.isEmpty) return {'n': 0};
  final sorted = [...values]..sort();
  double percentile(double p) => sorted[(sorted.length * p).ceil() - 1];
  return {
    'n': sorted.length,
    'p50Ms': percentile(.5),
    'p95Ms': percentile(.95),
    'p99Ms': percentile(.99),
    'maxMs': sorted.last
  };
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
