import 'dart:collection';

import '../../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 在来源队列内判断视频是否属于指定一级/二级标签组合。
 *
 * 标签规则由页面从既有领域边界注入，播放器会话不自行查询媒体库或复制筛选语义。
 */
typedef PlayerChildTagMatcher = bool Function(
  VideoItem item,
  String parentTag,
  String childTag,
);

/**
 * 播放器来源队列、当前媒体和浏览选择的唯一应用状态 owner。
 *
 * controller 只持有媒体库 Route 传入的来源快照副本，不读取 Store、SQLite、文件系统、
 * `PlayerBackend`、Widget 或 Route。所有定位和删除使用 stable `videoId`，mutable path
 * 只在页面向后端发起真实 open 时使用。
 */
class PlayerSessionController {
  /**
   * 创建播放器会话。
   *
   * [sourcePlaylist] 必须是媒体库当前已接受结果的有序对象副本；
   * [acceptedSourceVideoIds] 在生产 Route 中来自同一 `LibraryQueueSnapshot`，用于拒绝
   * 成员或顺序漂移；独立组件测试可以不提供该校验输入。
   * [initialVideoId] 用稳定身份定位首个播放项，[matchesChildTag] 只在来源队列内部派生
   * 二级标签子队列。
   */
  PlayerSessionController({
    required Iterable<VideoItem> sourcePlaylist,
    required Iterable<String>? acceptedSourceVideoIds,
    required this.activeParentTag,
    required String initialVideoId,
    required PlayerChildTagMatcher matchesChildTag,
    String? initialChildTag,
  }) : _matchesChildTag = matchesChildTag {
    final source = List<VideoItem>.of(sourcePlaylist);
    if (source.isEmpty) {
      throw ArgumentError.value(
        sourcePlaylist,
        'sourcePlaylist',
        '播放器来源队列不能为空',
      );
    }
    final sourceVideoIds =
        source.map((item) => item.videoId).toList(growable: false);
    if (sourceVideoIds.toSet().length != sourceVideoIds.length) {
      throw ArgumentError.value(
        sourceVideoIds,
        'sourcePlaylist',
        '播放器来源队列不能包含重复 stable videoId',
      );
    }
    final acceptedIds = acceptedSourceVideoIds?.toList(growable: false);
    if (acceptedIds != null && !_sameOrder(sourceVideoIds, acceptedIds)) {
      throw ArgumentError.value(
        acceptedIds,
        'acceptedSourceVideoIds',
        '播放器对象队列必须与已接受 stable-ID 快照成员和顺序一致',
      );
    }
    _sourcePlaylist.addAll(source);
    setPlaylistForChildTag(
      initialChildTag,
      preferredVideoId: initialVideoId,
    );
  }

  /** 当前一级标签；为空时二级标签筛选不生效。 */
  final String? activeParentTag;

  /** 由领域层注入的二级标签匹配规则。 */
  final PlayerChildTagMatcher _matchesChildTag;

  /** 会话内可写来源副本；删除只影响当前 Route，不回写媒体库。 */
  final List<VideoItem> _sourcePlaylist = <VideoItem>[];

  /** 当前二级标签派生后的实际播放队列。 */
  final List<VideoItem> _queue = <VideoItem>[];

  /** 只读来源队列视图，禁止页面或 Widget 绕过命令直接改成员。 */
  late final List<VideoItem> sourcePlaylist =
      UnmodifiableListView<VideoItem>(_sourcePlaylist);

  /** 只读当前队列视图，保持右侧列表和播放命令消费同一顺序。 */
  late final List<VideoItem> queue = UnmodifiableListView<VideoItem>(_queue);

  /** 当前播放器队列中叠加的二级标签。 */
  String? selectedChildTag;

  /** 正在播放的视频在 [queue] 中的位置。 */
  var playingIndex = 0;

  /** 键盘或鼠标当前浏览选择的队列位置。 */
  var selectedIndex = 0;

  /** 当前正在播放的视频。 */
  VideoItem get currentItem => _queue[playingIndex];

  /** 按 stable ID 解析来源媒体；请求期间路径变化不能影响身份匹配。 */
  VideoItem? sourceItemForVideoId(String videoId) {
    for (final item in _sourcePlaylist) {
      if (item.videoId == videoId) return item;
    }
    return null;
  }

  /** 当前播放项之前是否还有可播放视频。 */
  bool get hasPrevious => _queue.isNotEmpty && playingIndex > 0;

  /** 当前播放项之后是否还有可播放视频。 */
  bool get hasNext =>
      _queue.isNotEmpty &&
      playingIndex >= 0 &&
      playingIndex < _queue.length - 1;

  /** 上一条视频索引；队首返回 null，避免页面层重复边界判断。 */
  int? get previousIndex => hasPrevious ? playingIndex - 1 : null;

  /** 下一条视频索引；队尾返回 null，确保连续播放不会默认循环。 */
  int? get nextIndex => hasNext ? playingIndex + 1 : null;

  /**
   * 按二级标签生成来源队列内的候选播放队列。
   *
   * 没有一级标签上下文或二级标签为空时返回完整来源副本，绝不访问全局媒体库。
   */
  List<VideoItem> playlistForChildTag(String? childTag) {
    final parent = activeParentTag;
    if (parent == null || childTag == null) {
      return List<VideoItem>.of(_sourcePlaylist);
    }
    return _sourcePlaylist
        .where((item) => _matchesChildTag(item, parent, childTag))
        .toList();
  }

  /**
   * 切换当前二级标签队列，并尽量保留 [preferredVideoId] 对应的稳定媒体。
   *
   * 子标签无结果时回退本次 Route 的来源队列，不得回退全局媒体库或产生空队列。
   */
  void setPlaylistForChildTag(
    String? childTag, {
    required String preferredVideoId,
  }) {
    selectedChildTag = childTag;
    final next = playlistForChildTag(childTag);
    _queue
      ..clear()
      ..addAll(next.isEmpty ? _sourcePlaylist : next);
    playingIndex =
        _queue.indexWhere((item) => item.videoId == preferredVideoId);
    if (playingIndex < 0) {
      playingIndex = 0;
    }
    selectedIndex = playingIndex;
  }

  /** 再次切换同一个二级标签时取消叠加筛选，否则应用新的来源内子队列。 */
  void toggleChildTag(
    String tag, {
    required String preferredVideoId,
  }) {
    final nextTag = selectedChildTag == tag ? null : tag;
    setPlaylistForChildTag(
      nextTag,
      preferredVideoId: preferredVideoId,
    );
  }

  /**
   * 更新键盘/鼠标选中的队列项。
   *
   * 返回 false 表示索引越界，调用方无需触发滚动或重绘。
   */
  bool select(int index) {
    if (index < 0 || index >= _queue.length) {
      return false;
    }
    selectedIndex = index;
    return true;
  }

  /** 基于当前选中项移动选择位置。 */
  int moveSelection(int delta) {
    if (_queue.isEmpty) {
      return selectedIndex;
    }
    selectedIndex = (selectedIndex + delta).clamp(0, _queue.length - 1);
    return selectedIndex;
  }

  /** 将选择位置移动到指定索引，越界时夹紧到队列范围内。 */
  int selectQueueIndex(int index) {
    if (_queue.isEmpty) {
      return selectedIndex;
    }
    selectedIndex = index.clamp(0, _queue.length - 1);
    return selectedIndex;
  }

  /**
   * 返回当前播放项定位索引但不覆盖用户浏览选择。
   *
   * 队列滚动属于视图动作；页面可以据此回到播放项，选中项仍指向用户刚浏览的条目。
   */
  int locatePlayingIndex() => playingIndex;

  /**
   * 跳转播放到指定队列项。
   *
   * 返回 false 表示索引越界，页面不得触发后端 open。
   */
  bool jumpTo(int index) {
    if (index < 0 || index >= _queue.length) {
      return false;
    }
    playingIndex = index;
    selectedIndex = index;
    return true;
  }

  /**
   * 从来源队列和当前队列中移除指定索引的视频。
   *
   * 删除匹配 stable `videoId`，避免文件 Relink/改名后 mutable path 变化导致会话残留。
   * 删除播放项之前的条目只回退索引，保证真实播放身份不变；返回值表示是否删除播放项。
   */
  bool removeItemAt(int index) {
    if (index < 0 || index >= _queue.length) {
      return false;
    }
    final item = _queue[index];
    final removedPlayingItem = index == playingIndex;
    final removedSelectedItem = index == selectedIndex;
    _sourcePlaylist.removeWhere((video) => video.videoId == item.videoId);
    _queue.removeAt(index);
    if (_queue.isEmpty) {
      playingIndex = 0;
      selectedIndex = 0;
      return removedPlayingItem;
    }

    if (index < playingIndex) {
      playingIndex--;
    } else if (playingIndex >= _queue.length) {
      playingIndex = _queue.length - 1;
    }
    if (index < selectedIndex) {
      selectedIndex--;
    } else if (selectedIndex >= _queue.length) {
      selectedIndex = _queue.length - 1;
    }
    if (removedPlayingItem || removedSelectedItem) {
      selectedIndex = playingIndex;
    }
    return removedPlayingItem;
  }

  /** 比较两个 stable-ID 序列的成员与顺序，避免只比较集合掩盖队列漂移。 */
  static bool _sameOrder(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}
