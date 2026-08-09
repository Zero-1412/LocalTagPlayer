import '../../../core/tag_rules.dart';
import '../../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/** 替换单视频某一层级 manual 标签的显式命令。 */
class ReplaceVideoManualTagsCommand {
  ReplaceVideoManualTagsCommand({
    required this.item,
    required Iterable<String> selectedTags,
    required Iterable<String> lockedFolderTags,
    this.parentTag,
  })  : selectedTags = List<String>.unmodifiable(selectedTags),
        lockedFolderTags = List<String>.unmodifiable(lockedFolderTags);

  /** 以 stable videoId 持有身份、以当前 mutable path 供 Repository 兼容写入的视频。 */
  final VideoItem item;

  /** 用户在编辑器中确认的标签名；执行器会统一规范化和大小写去重。 */
  final List<String> selectedTags;

  /** 路径派生且不可由 manual 编辑删除的 folder 标签。 */
  final List<String> lockedFolderTags;

  /** null 表示一级 manual 标签；非空表示该一级父级下的二级 manual 标签。 */
  final String? parentTag;
}

/**
 * 单视频 manual 标签命令执行器。
 *
 * 本类只修改调用方提供的兼容模型并注入 Repository 提交；不读取标签索引、不创建 tagId、
 * 不持有 Store、BuildContext 或 Route。Repository 失败时恢复完整一级/二级快照，避免
 * 内存 UI 与 SQLite 分叉。
 */
class LibraryManualTagCommandExecutor {
  const LibraryManualTagCommandExecutor();

  /** 应用 folder 锁定规则、提交显式 manual 关系，并在失败时恢复原模型。 */
  Future<void> replace(
    ReplaceVideoManualTagsCommand command, {
    required Future<void> Function(
      VideoItem item,
      String? parentTag,
      Set<String> manualTags,
    ) commit,
  }) async {
    final item = command.item;
    final previousTags = <String>{...item.tags};
    final previousChildTags = <String, Set<String>>{
      for (final entry in item.childTags.entries)
        entry.key: <String>{...entry.value},
    };
    final manualTags = _normalize(command.selectedTags);
    final nextTags = <String>{
      ..._normalize(command.lockedFolderTags),
      ...manualTags
    };
    final parentTag = command.parentTag;
    if (parentTag == null) {
      item.tags
        ..clear()
        ..addAll(nextTags);
    } else {
      item.childTags[parentTag] = nextTags;
    }
    try {
      await commit(item, parentTag, manualTags);
    } catch (_) {
      item.tags
        ..clear()
        ..addAll(previousTags);
      item.childTags
        ..clear()
        ..addAll(previousChildTags);
      rethrow;
    }
  }

  /** 按 TagRules 规范化并以大小写不敏感语义去重。 */
  Set<String> _normalize(Iterable<String> tags) {
    final seen = <String>{};
    final normalized = <String>{};
    for (final raw in tags) {
      final tag = TagRules.normalizeTag(raw);
      if (tag.isNotEmpty && seen.add(tag.toLowerCase())) {
        normalized.add(tag);
      }
    }
    return normalized;
  }
}
