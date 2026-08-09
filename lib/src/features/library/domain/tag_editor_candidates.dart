import '../../../core/tag_rules.dart';
import '../../../models/platform_models.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 生成标签编辑器当前层级可见的名称候选。
 *
 * 顶层编辑显示顶层标签及所有非隐藏 manual 标签。manual 不受目录层级约束，
 * 因而兼容旧版带 parentId 的 manual 定义；保存层会把实际关联规范化为顶层
 * manual 关联。二级 folder 候选仍只显示当前父级下的项目，避免破坏目录层级。
 */
Set<String> tagEditorCandidatesForScope(
  Iterable<TagItem> tags, {
  String? parentTag,
}) {
  return <String>{
    for (final tag in tags)
      if (!tag.isHidden &&
          (parentTag == null
              ? tag.parentId == null || tag.source == TagSource.manual
              : tag.parentId != null &&
                  TagRules.sameTag(tag.parentId!, parentTag)))
        tag.name,
  };
}
