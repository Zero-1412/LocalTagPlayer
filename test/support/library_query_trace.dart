import 'package:local_tag_player/src/features/library/domain/library_query_snapshot.dart';
import 'package:local_tag_player/src/models/platform_models.dart';
import 'package:local_tag_player/src/models/video_item.dart';
import 'package:local_tag_player/src/services/tags/tag_query_service.dart';

// ignore_for_file: slash_for_doc_comments

/** 媒体库查询追踪事件类型。 */
enum LibraryQueryTraceKind {
  resultComputed,
  countComputed,
  resultAccepted,
  resultDiscarded,
  countAccepted,
  countDiscarded,
}

/**
 * 一条测试期查询追踪事件。
 *
 * 只保存版本、结果规模和事件类型，不记录用户本地路径或标签文本。
 */
class LibraryQueryTraceEvent {
  const LibraryQueryTraceEvent({
    required this.kind,
    required this.epoch,
    required this.itemCount,
  });

  /** 本次计算或发布动作的类别。 */
  final LibraryQueryTraceKind kind;

  /** `LibraryResultEpoch` 或 `LibraryCountEpoch`。 */
  final Object epoch;

  /** 结果视频数或标签计数项数。 */
  final int itemCount;
}

/**
 * 测试期媒体库查询调用追踪器。
 *
 * 追踪器是显式装饰器，不进入生产查询热路径；focused tests 用它验证旧 epoch 被丢弃以及
 * 排序不会触发计数。事件不含高基数路径，避免测试日志泄露本地媒体信息。
 */
class LibraryQueryTraceRecorder {
  final List<LibraryQueryTraceEvent> _events = <LibraryQueryTraceEvent>[];

  /** 已记录事件的只读快照。 */
  List<LibraryQueryTraceEvent> get events =>
      List<LibraryQueryTraceEvent>.unmodifiable(_events);

  /**
   * 执行并记录一次结果查询。
   */
  List<VideoItem> computeResult({
    required TagQueryService service,
    required FilterQuery query,
    required LibraryResultEpoch epoch,
  }) {
    final result = service.filter(query);
    _events.add(LibraryQueryTraceEvent(
      kind: LibraryQueryTraceKind.resultComputed,
      epoch: epoch,
      itemCount: result.length,
    ));
    return result;
  }

  /**
   * 执行并记录一次标签计数查询。
   */
  Map<String, int> computeCounts({
    required TagQueryService service,
    required FilterQuery query,
    required Iterable<TagItem> tags,
    required LibraryCountEpoch epoch,
  }) {
    final result = service.resultCounts(query, tags);
    _events.add(LibraryQueryTraceEvent(
      kind: LibraryQueryTraceKind.countComputed,
      epoch: epoch,
      itemCount: result.length,
    ));
    return result;
  }

  /**
   * 按期望版本记录结果是否允许发布。
   */
  bool publishResult({
    required LibraryResultEpoch expected,
    required LibraryResultEpoch candidate,
    required int itemCount,
  }) {
    final accepted = expected == candidate;
    _events.add(LibraryQueryTraceEvent(
      kind: accepted
          ? LibraryQueryTraceKind.resultAccepted
          : LibraryQueryTraceKind.resultDiscarded,
      epoch: candidate,
      itemCount: itemCount,
    ));
    return accepted;
  }

  /**
   * 按期望版本记录计数是否允许发布。
   */
  bool publishCounts({
    required LibraryCountEpoch expected,
    required LibraryCountEpoch candidate,
    required int itemCount,
  }) {
    final accepted = expected == candidate;
    _events.add(LibraryQueryTraceEvent(
      kind: accepted
          ? LibraryQueryTraceKind.countAccepted
          : LibraryQueryTraceKind.countDiscarded,
      epoch: candidate,
      itemCount: itemCount,
    ));
    return accepted;
  }
}
