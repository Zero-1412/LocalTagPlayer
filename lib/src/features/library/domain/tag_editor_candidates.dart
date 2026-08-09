import '../../../core/tag_rules.dart';
import '../../../models/platform_models.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 生成标签编辑器当前层级可见的名称候选。
 *
 * 顶层编辑只显示所有非隐藏 manual 标签。manual 不受目录层级约束，
 * 因而兼容旧版带 parentId 的 manual 定义；保存层会把实际关联规范化为顶层
 * manual 关联。带 [parentTag] 的查询仅兼容读取历史二级 manual 定义，候选始终不会
 * 混入 folder 来源。
 */
Set<String> tagEditorCandidatesForScope(
  Iterable<TagItem> tags, {
  String? parentTag,
}) {
  return <String>{
    for (final tag in tags)
      if (!tag.isHidden &&
          tag.source == TagSource.manual &&
          (parentTag == null ||
              tag.parentId != null &&
                  TagRules.sameTag(tag.parentId!, parentTag)))
        tag.name,
  };
}
