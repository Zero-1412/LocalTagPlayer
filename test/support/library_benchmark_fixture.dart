import 'package:local_tag_player/src/models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 生成确定性的媒体库基准数据。
 *
 * 数据量、稳定身份、目录层级和标签分布均不依赖文件系统或随机数，使架构测试能在任意
 * 开发机复现 11,000 项查询输入。该 fixture 不访问 SQLite，不替代真实数据库基准。
 */
List<VideoItem> buildDeterministicLibraryFixture({
  int itemCount = 11000,
}) {
  return List<VideoItem>.generate(itemCount, (index) {
    final primary = '一级_${index % 20}';
    final child = '二级_${index % 100}';
    final extension = index.isEven ? 'mp4' : 'mkv';
    return VideoItem(
      videoId: 'fixture-video-${index.toString().padLeft(5, '0')}',
      path: 'C:/fixture/$primary/$child/video_$index.$extension',
      title: 'video_$index',
      folder: 'C:/fixture/$primary/$child',
      tags: <String>{
        primary,
        if (index % 3 == 0) 'manual_${index % 12}',
      },
      childTags: <String, Set<String>>{
        primary: <String>{child},
      },
      rootPath: 'C:/fixture',
      relativePath: '$primary/$child/video_$index.$extension',
      fileSize: 1000000 + index,
      modifiedMs: 1700000000000 + index,
      isFavorite: index % 17 == 0,
      addedAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: index)),
    );
  }, growable: false);
}
