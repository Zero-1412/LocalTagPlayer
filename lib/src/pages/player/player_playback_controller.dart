import '../../core/tag_rules.dart';
import '../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放页的队列与选中状态协调器。
 *
 * 该 controller 只维护“来源队列、当前二级标签、正在播放索引、键盘选中索引”，不直接
 * 打开播放器，也不触碰 `PlayerBackend`/mpv 状态，确保播放队列仍来自媒体库当前过滤结果。
 */
class PlayerPlaybackController {
  /**
   * 创建播放状态协调器。
   *
   * [sourcePlaylist] 是媒体库传入的过滤后来源队列；[activeParentTag] 用于二级标签队列
   * 再过滤；[initialPath] 用于定位首次播放的视频。
   */
  PlayerPlaybackController({
    required Iterable<VideoItem> sourcePlaylist,
    required this.activeParentTag,
    required String initialPath,
    String? initialChildTag,
  }) : sourcePlaylist = List<VideoItem>.of(sourcePlaylist) {
    setPlaylistForChildTag(initialChildTag, preferredPath: initialPath);
  }

  /** 媒体库当前过滤结果传入播放器后的原始来源队列。 */
  final List<VideoItem> sourcePlaylist;

  /** 当前一级标签；为空时二级标签筛选不生效。 */
  final String? activeParentTag;

  /** 当前播放器实际消费的队列。 */
  final List<VideoItem> queue = <VideoItem>[];

  /** 当前在播放器队列中叠加的二级标签。 */
  String? selectedChildTag;

  /** 正在播放的视频在 [queue] 中的位置。 */
  var playingIndex = 0;

  /** 键盘或鼠标当前选中的队列位置。 */
  var selectedIndex = 0;

  /** 当前正在播放的视频。 */
  VideoItem get currentItem => queue[playingIndex];

  /** 当前播放项之前是否还有可播放视频。 */
  bool get hasPrevious => queue.isNotEmpty && playingIndex > 0;

  /** 当前播放项之后是否还有可播放视频。 */
  bool get hasNext =>
      queue.isNotEmpty && playingIndex >= 0 && playingIndex < queue.length - 1;

  /** 上一条视频索引；队首返回 null，避免页面层重复边界判断。 */
  int? get previousIndex => hasPrevious ? playingIndex - 1 : null;

  /** 下一条视频索引；队尾返回 null，确保连续播放不会默认循环。 */
  int? get nextIndex => hasNext ? playingIndex + 1 : null;

  /**
   * 按二级标签生成候选播放队列。
   *
   * 如果没有一级标签上下文或二级标签为空，返回完整来源队列，避免播放器退回全局媒体库。
   */
  List<VideoItem> playlistForChildTag(String? childTag) {
    final parent = activeParentTag;
    if (parent == null || childTag == null) {
      return List<VideoItem>.of(sourcePlaylist);
    }
    return sourcePlaylist
        .where((item) => TagRules.matchesChildTag(item, parent, childTag))
        .toList();
  }

  /**
   * 切换当前二级标签队列，并尽量保留 [preferredPath] 对应的视频位置。
   *
   * 当二级标签无结果时回退来源队列，这是为了保证播放器不会进入空队列导致页面崩溃。
   */
  void setPlaylistForChildTag(String? childTag,
      {required String preferredPath}) {
    selectedChildTag = childTag;
    final next = playlistForChildTag(childTag);
    queue
      ..clear()
      ..addAll(next.isEmpty ? sourcePlaylist : next);
    playingIndex = queue.indexWhere((item) => item.path == preferredPath);
    if (playingIndex < 0) {
      playingIndex = 0;
    }
    selectedIndex = playingIndex;
  }

  /**
   * 切换同一个二级标签时取消叠加筛选，切换新标签时应用对应子队列。
   */
  void toggleChildTag(String tag, {required String preferredPath}) {
    final nextTag = selectedChildTag == tag ? null : tag;
    setPlaylistForChildTag(nextTag, preferredPath: preferredPath);
  }

  /**
   * 更新键盘/鼠标选中的队列项。
   *
   * 返回 `false` 表示索引越界，调用方无需触发滚动或重绘。
   */
  bool select(int index) {
    if (index < 0 || index >= queue.length) {
      return false;
    }
    selectedIndex = index;
    return true;
  }

  /**
   * 基于当前选中项移动选择位置。
   */
  int moveSelection(int delta) {
    if (queue.isEmpty) {
      return selectedIndex;
    }
    selectedIndex = (selectedIndex + delta).clamp(0, queue.length - 1);
    return selectedIndex;
  }

  /**
   * 将选择位置移动到指定索引，越界时夹紧到队列范围内。
   */
  int selectQueueIndex(int index) {
    if (queue.isEmpty) {
      return selectedIndex;
    }
    selectedIndex = index.clamp(0, queue.length - 1);
    return selectedIndex;
  }

  /**
   * 跳转播放到指定队列项。
   *
   * 返回 `false` 表示索引越界，调用方不应触发播放器打开。
   */
  bool jumpTo(int index) {
    if (index < 0 || index >= queue.length) {
      return false;
    }
    playingIndex = index;
    selectedIndex = index;
    return true;
  }

  /**
   * 从来源队列和当前队列中移除指定索引的视频。
   *
   * 非播放项位于当前播放项之前时只回退播放索引，保证播放器仍指向同一个视频；
   * 只有删除正在播放项时，调用方才需要停止后端并打开新的当前项。
   * 返回值表示被移除项是否正在播放。
   */
  bool removeItemAt(int index) {
    if (index < 0 || index >= queue.length) {
      return false;
    }
    final item = queue[index];
    final removedPlayingItem = index == playingIndex;
    final removedSelectedItem = index == selectedIndex;
    sourcePlaylist.removeWhere((video) => video.path == item.path);
    queue.removeAt(index);
    if (queue.isEmpty) {
      playingIndex = 0;
      selectedIndex = 0;
      return removedPlayingItem;
    }

    if (index < playingIndex) {
      playingIndex--;
    } else if (playingIndex >= queue.length) {
      playingIndex = queue.length - 1;
    }
    if (index < selectedIndex) {
      selectedIndex--;
    } else if (selectedIndex >= queue.length) {
      selectedIndex = queue.length - 1;
    }
    if (removedPlayingItem || removedSelectedItem) {
      selectedIndex = playingIndex;
    }
    return removedPlayingItem;
  }
}
