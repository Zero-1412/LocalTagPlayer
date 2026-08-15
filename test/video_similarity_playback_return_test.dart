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

    expect(page, contains('onPressed: () => onPlay(item, playlist)'));
    expect(page, contains('onPressed: () => onDelete(item)'));
    expect(
      page,
      isNot(
        contains(
          'onPressed: visualScanning ? null : () => onPlay(item, playlist)',
        ),
      ),
    );
    expect(
      page,
      isNot(
        contains(
          'onPressed: visualScanning ? null : () => onDelete(item)',
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
}
