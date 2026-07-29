import 'dart:collection';

import '../../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/** 单条 missing relink 的不可变提交快照。 */
class RelinkMissingVideoCommand {
  RelinkMissingVideoCommand({
    required this.item,
    required this.newPath,
  })  : videoId = item.videoId,
        previousPath = item.path,
        expectedFingerprint = item.mediaFingerprint;

  /** Repository 兼容写入使用的当前媒体对象。 */
  final VideoItem item;

  /** 创建命令时捕获的稳定身份。 */
  final String videoId;

  /** picker 打开前的 mutable path，用于拒绝过期选择结果。 */
  final String previousPath;

  /** picker 打开前的媒体 fingerprint，用于拒绝身份已变化的旧命令。 */
  final String? expectedFingerprint;

  /** 用户明确选择的新路径；最终规范化和内容校验仍由 Repository 负责。 */
  final String newPath;
}

/** 单条 relink 的无 UI 执行结果。 */
class RelinkMissingVideoCommandResult {
  const RelinkMissingVideoCommandResult._({
    required this.videoId,
    required this.changed,
    this.error,
  });

  /** 成功结果只表达同一 stable videoId 已提交新 mutable path。 */
  factory RelinkMissingVideoCommandResult.succeeded(String videoId) =>
      RelinkMissingVideoCommandResult._(
        videoId: videoId,
        changed: true,
      );

  /** 失败结果保留安全错误，由 presentation 决定如何展示。 */
  factory RelinkMissingVideoCommandResult.failed(
    String videoId,
    Object error,
  ) =>
      RelinkMissingVideoCommandResult._(
        videoId: videoId,
        changed: false,
        error: error,
      );

  final String videoId;
  final bool changed;
  final Object? error;
}

/**
 * 单条 missing relink 命令执行器。
 *
 * 本类只拒绝过期/重复命令并委托 Repository；不读取文件、不计算 fingerprint、不持有
 * Store、BuildContext、Route 或平台资源。最终路径占用、可读性、fingerprint 与原子提交
 * 仍由 Repository 唯一负责。
 */
class LibraryMissingRelinkCommandExecutor {
  final Set<String> _runningVideoIds = <String>{};

  /** presentation 只读观察的稳定身份集合，用于行级忙碌反馈。 */
  Set<String> get runningVideoIds =>
      UnmodifiableSetView<String>(_runningVideoIds);

  /** 按创建时身份快照提交一次 relink，并把可展示错误转换为结果。 */
  Future<RelinkMissingVideoCommandResult> execute(
    RelinkMissingVideoCommand command, {
    required Future<void> Function(VideoItem item, String newPath) commit,
  }) async {
    final item = command.item;
    if (item.videoId != command.videoId ||
        item.path != command.previousPath ||
        item.mediaFingerprint != command.expectedFingerprint ||
        !item.isMissing) {
      return RelinkMissingVideoCommandResult.failed(
        command.videoId,
        StateError('缺失记录已变化，请重新选择文件'),
      );
    }
    if (command.newPath.trim().isEmpty) {
      return RelinkMissingVideoCommandResult.failed(
        command.videoId,
        ArgumentError.value(command.newPath, 'newPath', '新路径不能为空'),
      );
    }
    if (!_runningVideoIds.add(command.videoId)) {
      return RelinkMissingVideoCommandResult.failed(
        command.videoId,
        StateError('该视频正在重新关联，请稍候'),
      );
    }
    try {
      await commit(item, command.newPath);
      return RelinkMissingVideoCommandResult.succeeded(command.videoId);
    } catch (error) {
      return RelinkMissingVideoCommandResult.failed(command.videoId, error);
    } finally {
      _runningVideoIds.remove(command.videoId);
    }
  }
}
