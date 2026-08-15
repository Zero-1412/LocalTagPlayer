import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 保护相似视频页的返回时序：Route 弹回后先恢复行级动作状态，原生播放器资源释放和
 * 播放进度刷盘仍由既有 openVideo 尾部完成，避免用户看到不必要的长时间占位。
 */
void main() {
  test('视觉复核期间已有候选仍可播放和删除', () {
    final page = File(
      'lib/src/pages/library/video_similarity_page.dart',
    ).readAsStringSync();
    final groupWidgets = File(
      'lib/src/widgets/library/video_similarity_group_widgets.dart',
    ).readAsStringSync();
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
    final page = File(
      'lib/src/pages/library/video_similarity_page.dart',
    ).readAsStringSync();

    expect(page, contains('EdgeInsets.only(right: 18, bottom: 12)'));
  });

  test('相似视频页首帧后再启动视觉扫描', () {
    final page = File(
      'lib/src/pages/library/video_similarity_page.dart',
    ).readAsStringSync();

    expect(page, contains('_scheduleVisualScan();'));
    expect(page, contains('WidgetsBinding.instance.addPostFrameCallback'));
  });

  test('相似视频扫描把候选构建和画面对比进度传到页面', () {
    final page = File(
      'lib/src/pages/library/video_similarity_page.dart',
    ).readAsStringSync();
    final status = File(
      'lib/src/widgets/library/video_similarity_status_widgets.dart',
    ).readAsStringSync();

    expect(page, contains('visualProgressPhase: _visualProgressPhase'));
    expect(page, contains('onProgress: (progress)'));
    expect(status, contains('VideoVisualScanPhase.buildingCandidates'));
    expect(status, contains('LinearProgressIndicator('));
    expect(status, contains('_visualPhaseShortLabel(visualProgressPhase)'));
  });

  test('相似视频播放返回后先清除动作占位再等待资源释放', () {
    final playback = File(
      'lib/src/pages/library/library_page_playback_mixin.dart',
    ).readAsStringSync();
    final page = File(
      'lib/src/pages/library/video_similarity_page.dart',
    ).readAsStringSync();

    final routeReturned = playback.indexOf('onPlayerRouteReturned?.call();');
    final disposalWait =
        playback.indexOf('await playerDisposed.future.timeout(');
    expect(routeReturned, greaterThanOrEqualTo(0));
    expect(disposalWait, greaterThan(routeReturned));
    expect(page, contains('onRouteReturned: ()'));
    expect(page, contains('_actingVideoIds.remove(item.videoId)'));
  });

  test('播放器删除后相似候选按 stable ID 局部对账', () {
    final page = File(
      'lib/src/pages/library/video_similarity_page.dart',
    ).readAsStringSync();

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

  test('相似视频删除取消旧视觉任务且不自动重启全库复核', () {
    final page = File(
      'lib/src/pages/library/video_similarity_page.dart',
    ).readAsStringSync();
    final start = page.indexOf('Future<void> _delete(');
    final end = page.indexOf('  @override\n  Widget build', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final deleteMethod = page.substring(start, end);

    expect(deleteMethod, contains('_cancelVisualScan();'));
    expect(deleteMethod, contains('_visualScanStale = true;'));
    expect(deleteMethod, isNot(contains('_scheduleVisualScan();')));
  });

  test('播放器播放期间让视觉复核让渡取帧并在返回后恢复', () {
    final page = File(
      'lib/src/pages/library/video_similarity_page.dart',
    ).readAsStringSync();

    expect(page, contains('_visualPlaybackActive = true;'));
    expect(page, contains('setSimilarityScanForeground(false)'));
    expect(page, contains('shouldYield: () => _visualPlaybackActive'));
    expect(page, contains('_visualPlaybackActive = false;'));
    expect(page, contains('setSimilarityScanForeground(true)'));
  });
}
