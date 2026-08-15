import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 保护相似视频页的返回时序：Route 弹回后先恢复行级动作状态，原生播放器资源释放和
 * 播放进度刷盘仍由既有 openVideo 尾部完成，避免用户看到不必要的长时间占位。
 */
void main() {
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
