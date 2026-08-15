import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 保护删除后的列表差量边界：业务层只发布 stable ID 差量，结果组件用 stable key 复用
 * 未变化项并保留滚动锚点；播放器队列仍使用自己的 stable key。
 */
void main() {
  test('所有视频列表删除入口走差量查询与 stable key 复用', () {
    final commands = File(
      'lib/src/pages/library/library_page_commands_mixin.dart',
    ).readAsStringSync();
    final routes = File(
      'lib/src/pages/library/library_page_routes_mixin.dart',
    ).readAsStringSync();
    final lifecycle = File(
      'lib/src/pages/library/library_page_lifecycle_mixin.dart',
    ).readAsStringSync();
    final recent = File(
      'lib/src/pages/library/library_page_recent_mixin.dart',
    ).readAsStringSync();
    final page =
        File('lib/src/pages/library/library_page.dart').readAsStringSync();
    final grid = File('lib/src/widgets/library/library_video_grid.dart')
        .readAsStringSync();
    final gridResults = File(
      'lib/src/widgets/library/library_video_grid_results_view.dart',
    ).readAsStringSync();
    final local = File('lib/src/widgets/library/library_local_view.dart')
        .readAsStringSync();
    final recentView = File(
      'lib/src/widgets/library/library_recent_playback_view.dart',
    ).readAsStringSync();
    final similarity = File(
      'lib/src/pages/library/video_similarity_page.dart',
    ).readAsStringSync();
    final playerQueue = File(
      'lib/src/pages/player/player_queue_sidebar.dart',
    ).readAsStringSync();

    expect(commands, contains('removedVideoIds: <String>[item.videoId]'));
    expect(commands, contains('removedVideoIds: result.deletedVideoIds'));
    expect(routes, contains('videoIdsBeforeSettings'));
    expect(lifecycle, contains('videoIdsBeforeCleanup'));
    expect(recent, contains('changedVideos: targets'));
    expect(page, contains('preserveScrollOnResultDelta'));
    expect(grid, contains('_preserveResultDelta'));
    expect(gridResults, contains('ValueKey<String>(item.videoId)'));
    expect(local, contains('findChildIndexCallback'));
    expect(recentView, contains('findChildIndexCallback'));
    expect(similarity, contains('videoSimilarity.group.'));
    expect(playerQueue, contains('player.queue.item.\${item.videoId}'));
  });
}
