import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../../core/tag_rules.dart';
import '../../../models/library_sort.dart';
import '../../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/** 按当前字段和方向比较两个视频，完全相同时使用稳定路径 key 兜底。 */
int compareLibraryVideosForSort(
  VideoItem a,
  VideoItem b, {
  required SortMode sortMode,
  required SortDirection sortDirection,
}) {
  return _compareVideoSortSnapshots(
    _VideoSortSnapshot(a),
    _VideoSortSnapshot(b),
    sortMode: sortMode,
    sortDirection: sortDirection,
  );
}

/** 使用预计算排序字段比较视频，避免大库排序时反复拆分文件名和路径。 */
int _compareVideoSortSnapshots(
  _VideoSortSnapshot a,
  _VideoSortSnapshot b, {
  required SortMode sortMode,
  required SortDirection sortDirection,
}) {
  if (sortMode == SortMode.size) {
    final value = _compareNullableFileSize(a.fileSize, b.fileSize);
    if (value != 0) {
      return sortDirection == SortDirection.descending ? -value : value;
    }
    return _compareVideoSnapshotIdentity(a, b);
  }

  final int value;
  switch (sortMode) {
    case SortMode.name:
      value = _compareNaturalTokens(a.titleTokens, b.titleTokens);
      break;
    case SortMode.recent:
      value = a.dateMs.compareTo(b.dateMs);
      break;
    case SortMode.type:
      final type = _compareNaturalTokens(a.extensionTokens, b.extensionTokens);
      value = type == 0
          ? _compareNaturalTokens(a.titleTokens, b.titleTokens)
          : type;
      break;
    case SortMode.size:
      value = 0;
      break;
    case SortMode.folder:
      final folder = _compareNaturalTokens(a.folderTokens, b.folderTokens);
      value = folder == 0
          ? _compareNaturalTokens(a.titleTokens, b.titleTokens)
          : folder;
      break;
    case SortMode.added:
      value = a.addedMs.compareTo(b.addedMs);
      break;
  }
  if (value == 0) {
    return _compareVideoSnapshotIdentity(a, b);
  }
  return sortDirection == SortDirection.descending ? -value : value;
}

/** 比较文件大小，并把未知大小稳定放在列表末尾。 */
int _compareNullableFileSize(int? a, int? b) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return 1;
  }
  if (b == null) {
    return -1;
  }
  return a.compareTo(b);
}

/** 比较已经拆好的自然排序 token。 */
int _compareNaturalTokens(List<String> left, List<String> right) {
  final length = math.min(left.length, right.length);
  for (var index = 0; index < length; index += 1) {
    final l = left[index];
    final r = right[index];
    final lNumber = int.tryParse(l);
    final rNumber = int.tryParse(r);
    final int result;
    if (lNumber != null && rNumber != null) {
      result = lNumber.compareTo(rNumber);
    } else {
      result = l.toLowerCase().compareTo(r.toLowerCase());
    }
    if (result != 0) {
      return result;
    }
  }
  return left.length.compareTo(right.length);
}

/** 将文本拆成数字和非数字片段，供自然排序比较器复用。 */
List<String> _naturalSortTokens(String value) {
  return RegExp(r'\d+|\D+')
      .allMatches(value)
      .map((match) => match.group(0) ?? '')
      .where((token) => token.isNotEmpty)
      .toList();
}

/** 标题相同后使用路径 key 保证跨重复执行的稳定顺序。 */
int _compareVideoSnapshotIdentity(_VideoSortSnapshot a, _VideoSortSnapshot b) {
  final title = _compareNaturalTokens(a.titleTokens, b.titleTokens);
  if (title != 0) {
    return title;
  }
  return a.pathKey.compareTo(b.pathKey);
}

/**
 * 按媒体库当前排序规则返回不可变视频列表。
 *
 * [videos] 可以来自全库、标签筛选结果、本地收藏或最近播放；统一入口避免不同来源各自
 * 实现排序，导致媒体库与播放器来源顺序不一致。
 */
List<VideoItem> sortedLibraryVideos(
  Iterable<VideoItem> videos, {
  required SortMode sortMode,
  required SortDirection sortDirection,
}) {
  final sorted = [
    for (final video in videos) _VideoSortSnapshot(video),
  ]..sort((a, b) => _compareVideoSortSnapshots(
        a,
        b,
        sortMode: sortMode,
        sortDirection: sortDirection,
      ));
  return List<VideoItem>.unmodifiable([
    for (final entry in sorted) entry.item,
  ]);
}

/**
 * 单个视频的排序快照。
 *
 * 把标题、目录、扩展名 token 和时间字段预先算好，减少 11,000 项大库比较器中的重复
 * 字符串处理；快照只在一次内存排序期间存在。
 */
class _VideoSortSnapshot {
  /** 从 [item] 一次性预计算比较字段，避免排序比较器重复解析字符串。 */
  _VideoSortSnapshot(this.item)
      : titleTokens = _naturalSortTokens(item.title),
        folderTokens = _naturalSortTokens(item.folder),
        extensionTokens =
            _naturalSortTokens(p.extension(item.path).toLowerCase()),
        dateMs = item.modifiedMs ?? item.addedAt.millisecondsSinceEpoch,
        addedMs = item.addedAt.millisecondsSinceEpoch,
        fileSize = item.fileSize,
        pathKey = TagRules.pathKey(item.path);

  /** 原始视频对象；排序完成后按快照顺序返回该引用。 */
  final VideoItem item;
  /** 标题自然排序 token。 */
  final List<String> titleTokens;
  /** 所在目录自然排序 token。 */
  final List<String> folderTokens;
  /** 小写扩展名自然排序 token。 */
  final List<String> extensionTokens;
  /** “日期”字段毫秒值，优先文件修改时间，缺失时回退入库时间。 */
  final int dateMs;
  /** 应用入库时间毫秒值。 */
  final int addedMs;
  /** 扫描记录中的文件大小；null 表示未知且固定排在末尾。 */
  final int? fileSize;
  /** 规范化路径 key，用作其它字段完全相同时的确定性兜底。 */
  final String pathKey;
}
