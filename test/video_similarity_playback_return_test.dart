import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: slash_for_doc_comments

String _source(String relativePath) =>
    File('${Directory.current.path}/$relativePath')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

/**
 * 保护相似视频页的返回时序：Route 弹回后先恢复行级动作状态，原生播放器资源释放和
 * 播放进度刷盘仍由既有 openVideo 尾部完成，避免用户看到不必要的长时间占位。
 */
void main() {
  test('视觉复核期间已有候选仍可播放和删除', () {
    final page = _source('lib/src/pages/library/video_similarity_page.dart');
    final groupWidgets =
        _source('lib/src/widgets/library/video_similarity_group_widgets.dart');
    final source = '$page\n$groupWidgets';

    expect(source, contains('onPressed: () => onPlay(item, playlist)'));
    expect(source, contains('onPressed: () => onDelete(item, playlist)'));
    expect(
      source,
      isNot(
        contains(
          'onPressed: visualScanning ? null : () => onPlay(item, playlist)',
        ),
      ),
    );
    expect(
      source,
      isNot(
        contains(
          'onPressed: visualScanning ? null : () => onDelete(item, playlist)',
        ),
      ),
    );
  });

  test('相似视频滚动内容为滚动条预留右侧安全区', () {
    final page = _source('lib/src/pages/library/video_similarity_page.dart');

    expect(page, contains('EdgeInsets.only('));
    expect(page, contains('right: 18'));
    expect(page, contains('bottom: 12'));
  });

  test('相似视频页挂载维护工作区外壳并限制内容宽度', () {
    final page = _source('lib/src/pages/library/video_similarity_page.dart');

    expect(page, contains('maintenanceFeedbackTheme(Theme.of(context))'));
    expect(page, contains('MaintenanceWorkspaceAppBar('));
    expect(page, contains("title: '相似视频'"));
    expect(
        page, contains("actionKey: const ValueKey('videoSimilarity.refresh')"));
    expect(page, contains('BoxConstraints(maxWidth: 1120)'));
  });

  test('相似视频页首帧后再启动视觉扫描', () {
    final page = _source('lib/src/pages/library/video_similarity_page.dart');

    expect(page, contains('_scheduleVisualScan();'));
    expect(page, contains('WidgetsBinding.instance.addPostFrameCallback'));
  });

  test('相似视频扫描把候选构建和画面对比进度传到页面', () {
    final page = _source('lib/src/pages/library/video_similarity_page.dart');
    final status =
        _source('lib/src/widgets/library/video_similarity_status_widgets.dart');
    final controller = _source(
      'lib/src/services/library/video_similarity_scan_controller.dart',
    );

    expect(page, contains('visualProgressPhase: _visualProgressPhase'));
    expect(controller, contains('onProgress: (progress)'));
    expect(controller, contains('_progress = progress;'));
    expect(status, contains('VideoVisualScanPhase.buildingCandidates'));
    expect(status, contains('LinearProgressIndicator('));
    expect(status, contains('_visualPhaseShortLabel(visualProgressPhase)'));
  });

  test('相似视频播放返回后先清除动作占位再等待资源释放', () {
    final playback =
        _source('lib/src/pages/library/library_page_playback_mixin.dart');
    final page = _source('lib/src/pages/library/video_similarity_page.dart');

    final routeReturned = playback.indexOf('onPlayerRouteReturned?.call();');
    final disposalWait =
        playback.indexOf('await playerDisposed.future.timeout(');
    expect(routeReturned, greaterThanOrEqualTo(0));
    expect(disposalWait, greaterThan(routeReturned));
    expect(page, contains('onRouteReturned: ()'));
    expect(page, contains('_actingVideoIds.remove(item.videoId)'));
  });

  test('播放器删除差量在资源释放尾部前发布到主界面', () {
    final playback =
        _source('lib/src/pages/library/library_page_playback_mixin.dart');

    final refresh = playback.indexOf(
      '_applyPlayerScopedLibraryChangesAfterRouteReturn();',
    );
    final disposalWait =
        playback.indexOf('await playerDisposed.future.timeout(');
    expect(refresh, greaterThanOrEqualTo(0));
    expect(disposalWait, greaterThan(refresh));
    expect(
      playback,
      contains(
          'removedVideoIds: removedVideoIds.isEmpty ? null : removedVideoIds'),
    );
  });

  test('播放器删除后相似候选按 stable ID 局部对账', () {
    final page = _source('lib/src/pages/library/video_similarity_page.dart');

    expect(page, contains('_reconcileAfterPlayerReturn'));
    expect(
      page,
      contains('_reconcileAfterPlayerReturn(activeVideoId: item.videoId)'),
    );
    expect(page, contains('_report = _report.withoutVideo(item);'));
    expect(page, contains('for (final item in removedById.values)'));
    expect(page, contains('WidgetsBinding.instance.addPostFrameCallback'));
    expect(page, contains('_deletedVideoIds.addAll(removedById.keys)'));
  });

  test('相似视频删除使旧视觉任务失效且不自动重启全库复核', () {
    final page = _source('lib/src/pages/library/video_similarity_page.dart');
    final start = page.indexOf('Future<void> _delete(');
    final end = page.indexOf('  @override\n  Widget build', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final deleteMethod = page.substring(start, end);

    expect(deleteMethod, contains('_cancelVisualScan();'));
    expect(deleteMethod, contains('_visualScanStale = true;'));
    expect(deleteMethod, isNot(contains('_scheduleVisualScan();')));
    expect(page, contains('invalidateForDataChange()'));
  });

  test('播放器播放期间让视觉复核让渡取帧并在返回后恢复', () {
    final page = _source('lib/src/pages/library/video_similarity_page.dart');
    final playback =
        _source('lib/src/pages/library/library_page_playback_mixin.dart');
    final controller = _source(
      'lib/src/services/library/video_similarity_scan_controller.dart',
    );

    expect(page, contains('setPlaybackActive(true)'));
    expect(page, contains('setPlaybackActive(false)'));
    expect(
      playback,
      contains('similarityScanController: runtime.similarityScanController'),
    );
    expect(playback, contains('backgroundGate.restore()'));
    expect(controller, contains('shouldYield: () => _playbackActive'));
    expect(controller, contains('_pageForeground && !_playbackActive'));
  });

  test('相似视频扫描由媒体库 Route 持有，离开页面不取消且仅首次自动执行', () {
    final page = _source('lib/src/pages/library/video_similarity_page.dart');
    final runtime = _source('lib/src/pages/library/library_page_runtime.dart');
    final routes =
        _source('lib/src/pages/library/library_page_routes_mixin.dart');
    final controller = _source(
      'lib/src/services/library/video_similarity_scan_controller.dart',
    );

    expect(runtime,
        contains('VideoSimilarityScanController? similarityScanController'));
    expect(routes, contains('scanController: similarityScanController'));
    expect(page, contains('setPageForeground(false)'));
    expect(page,
        isNot(contains('widget.thumbnailService.cancelSimilarityScan()')));
    expect(controller, contains('Future<void> startIfNeeded()'));
    expect(controller, contains('if (_activeTask != null)'));
    expect(controller, contains('if (_hasRun)'));
    expect(controller, contains('Future<void> refresh()'));
    expect(
        controller, contains('isCancelled: () => generation != _generation'));
    expect(controller, isNot(contains('isCancelled: () => !mounted')));
  });

  test('播放器会话同时暂停媒体详情后台探测并尊重进入前暂停状态', () {
    final playback =
        _source('lib/src/pages/library/library_page_playback_mixin.dart');
    final gate = _source(
      'lib/src/services/library/library_playback_background_gate.dart',
    );

    expect(playback, contains('LibraryPlaybackBackgroundGate'));
    expect(playback, contains('backgroundGate.restore()'));
    expect(gate, contains('final MediaDetailsService? _mediaDetailsService'));
    expect(gate, contains('_mediaDetailsService?.pause()'));
    expect(gate, contains('_mediaDetailsService?.resume()'));
    expect(gate, contains('if (!_mediaDetailsWasPaused)'));
  });
}
