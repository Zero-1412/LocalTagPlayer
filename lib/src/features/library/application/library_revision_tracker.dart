// ignore_for_file: slash_for_doc_comments

/**
 * 媒体库提交对查询发布协议造成的影响类型。
 *
 * 普通内容变化只使结果与计数数据过期；标签定义变化还会使候选标签、层级和别名对应的
 * 计数身份过期。排序和纯展示偏好不属于数据提交，不能调用本协议。
 */
enum LibraryDataChangeKind {
  /** 视频内容、收藏、播放状态或媒体详情发生变化。 */
  content,

  /** 标签定义、folder 层级、root 或标签关系可能发生变化。 */
  tagDefinitions,
}

/**
 * 媒体库查询发布使用的不可变修订快照。
 *
 * [dataRevision] 保护所有结果和计数；[tagDefinitionRevision] 只在标签定义边界变化时
 * 前进，使排序、播放进度等普通内容提交不再无意义地失效标签定义身份。
 */
class LibraryRevisionSnapshot {
  const LibraryRevisionSnapshot({
    required this.dataRevision,
    required this.tagDefinitionRevision,
  });

  /** 任何可影响结果或计数的数据提交代次。 */
  final int dataRevision;

  /** 标签定义、层级或关系候选可能变化的独立代次。 */
  final int tagDefinitionRevision;
}

/**
 * 媒体库修订协议的唯一可写 owner。
 *
 * tracker 不发布 UI 事件、不读取 Store，也不决定筛选语义；页面应用层在真实提交成功后
 * 记录一次 change kind，再把快照交给 `LibraryResultEpoch` / `LibraryCountEpoch`。
 */
class LibraryRevisionTracker {
  var _dataRevision = 0;
  var _tagDefinitionRevision = 0;

  /** 高频结果 epoch 构造直接读取的数据代次，不分配快照对象。 */
  int get dataRevision => _dataRevision;

  /** 高频计数 epoch 构造直接读取的标签定义代次，不分配快照对象。 */
  int get tagDefinitionRevision => _tagDefinitionRevision;

  /** 当前不可变修订快照。 */
  LibraryRevisionSnapshot get snapshot => LibraryRevisionSnapshot(
        dataRevision: _dataRevision,
        tagDefinitionRevision: _tagDefinitionRevision,
      );

  /**
   * 记录一次已经成功提交的数据变化。
   *
   * 标签变化同时影响结果数据，因此一定推进 [dataRevision]；普通内容变化不得推进标签
   * 代次，避免播放进度、收藏或媒体详情更新让延后标签计数无意义失效。
   */
  LibraryRevisionSnapshot record(LibraryDataChangeKind kind) {
    _dataRevision += 1;
    if (kind == LibraryDataChangeKind.tagDefinitions) {
      _tagDefinitionRevision += 1;
    }
    return snapshot;
  }
}
