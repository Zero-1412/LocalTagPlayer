import 'dart:collection';

import '../../core/tag_rules.dart';
import '../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 视频稳定身份索引。
 *
 * `byVideoId` 是唯一主索引；Map 兼容视图仍以规范化 pathKey 作为 key，供现有
 * 查询/页面代码平滑迁移。所有 Map 写入、删除和清空都会同步两个索引，避免
 * mutable path 变化后留下第二个稳定身份或旧路径悬挂记录。
 */
class VideoIdentityIndex extends MapBase<String, VideoItem> {
  VideoIdentityIndex([Iterable<VideoItem> items = const <VideoItem>[]]) {
    for (final item in items) {
      put(item);
    }
  }

  final Map<String, VideoItem> _byVideoId = <String, VideoItem>{};
  final Map<String, VideoItem> _byPathKey = <String, VideoItem>{};
  final Map<String, String> _pathKeyByVideoId = <String, String>{};

  /** 稳定 ID 主索引；返回只读快照，写入必须经过当前 Map 或 [put]。 */
  Map<String, VideoItem> get byVideoId =>
      UnmodifiableMapView<String, VideoItem>(_byVideoId);

  /** 按 stable ID 读取 active/detached 视频。 */
  VideoItem? byId(String videoId) => _byVideoId[videoId];

  /** 以视频当前 path 建立/替换两侧索引。 */
  void put(VideoItem item) {
    this[TagRules.pathKey(item.path)] = item;
  }

  /** 通过 stable ID 删除，同时移除当前 path 辅助索引。 */
  VideoItem? removeByVideoId(String videoId) {
    final item = _byVideoId.remove(videoId);
    if (item != null) {
      final pathKey =
          _pathKeyByVideoId.remove(videoId) ?? TagRules.pathKey(item.path);
      if (identical(_byPathKey[pathKey], item)) {
        _byPathKey.remove(pathKey);
      }
    }
    return item;
  }

  @override
  VideoItem? operator [](Object? key) => _byPathKey[key];

  @override
  void operator []=(String key, VideoItem value) {
    final oldAtPath = _byPathKey[key];
    if (oldAtPath != null && !identical(oldAtPath, value)) {
      if (identical(_byVideoId[oldAtPath.videoId], oldAtPath)) {
        _byVideoId.remove(oldAtPath.videoId);
        _pathKeyByVideoId.remove(oldAtPath.videoId);
      }
    }

    final oldAtId = _byVideoId[value.videoId];
    if (oldAtId != null) {
      final oldPathKey =
          _pathKeyByVideoId[value.videoId] ?? TagRules.pathKey(oldAtId.path);
      if (oldPathKey != key && identical(_byPathKey[oldPathKey], oldAtId)) {
        _byPathKey.remove(oldPathKey);
      }
    }

    _byPathKey[key] = value;
    _byVideoId[value.videoId] = value;
    _pathKeyByVideoId[value.videoId] = key;
  }

  @override
  VideoItem? remove(Object? key) {
    final item = _byPathKey.remove(key);
    if (item != null && identical(_byVideoId[item.videoId], item)) {
      _byVideoId.remove(item.videoId);
      _pathKeyByVideoId.remove(item.videoId);
    }
    return item;
  }

  @override
  void clear() {
    _byPathKey.clear();
    _byVideoId.clear();
    _pathKeyByVideoId.clear();
  }

  @override
  Iterable<String> get keys => _byPathKey.keys;

  @override
  Iterable<VideoItem> get values => _byPathKey.values;
}
