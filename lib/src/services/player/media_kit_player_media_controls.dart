import 'package:media_kit/media_kit.dart';

import '../../models/player_media_controls.dart';

/// 读取当前 libmpv 会话的章节节点。
///
/// 章节只在控制面板显式打开时查询，不能进入播放状态高频更新链；本函数也不持有
/// Player，避免为读取元数据意外创建第二条播放器或解码链。
Future<List<PlayerMediaChapter>> readMediaKitChapters(
  NativePlayer? nativePlayer,
) async {
  if (nativePlayer == null) return const <PlayerMediaChapter>[];
  try {
    // chapter-list 是 libmpv 的 node 属性；不要依赖 node 转字符串后的格式。
    final count = int.tryParse(
      (await nativePlayer.getProperty('chapter-list/count')).trim(),
    );
    if (count == null || count <= 0) return const <PlayerMediaChapter>[];

    final chapters = <PlayerMediaChapter>[];
    // 防止异常媒体把章节节点伪造成巨量列表，控制面板无需无限读取。
    final safeCount = count.clamp(0, 500);
    for (var index = 0; index < safeCount; index++) {
      final seconds = double.tryParse(
        (await nativePlayer.getProperty('chapter-list/$index/time')).trim(),
      );
      if (seconds == null || !seconds.isFinite || seconds < 0) continue;
      final title = (await nativePlayer.getProperty(
        'chapter-list/$index/title',
      ))
          .trim();
      chapters.add(
        PlayerMediaChapter(
          index: index,
          position: Duration(
            microseconds: (seconds * Duration.microsecondsPerSecond).round(),
          ),
          title: title.isEmpty ? null : title,
        ),
      );
    }
    return chapters;
  } catch (_) {
    return const <PlayerMediaChapter>[];
  }
}
