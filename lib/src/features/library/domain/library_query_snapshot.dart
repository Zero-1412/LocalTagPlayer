import 'dart:convert';

import '../../../models/platform_models.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 为媒体库查询生成稳定、与集合插入顺序无关的指纹。
 *
 * 指纹只描述查询语义，不包含页面选择、滚动位置、网格密度等纯展示状态。
 * 领域层通过 JSON 编码有序结构，避免简单字符串拼接产生边界碰撞。
 */
abstract final class LibraryQueryFingerprint {
  /**
   * 返回不含搜索词和排序规则的筛选指纹。
   *
   * 标签集合和分组会先排序；同一语义的查询即使由不同点击顺序产生，也必须得到同一结果。
   */
  static String filter(FilterQuery query) => jsonEncode(<Object?>[
        query.primaryTagId ?? '',
        query.childTagId ?? '',
        _sorted(query.folderRoots),
        _sorted(query.includeTagIds),
        _sorted(query.excludeTagIds),
        _sortedGroupSelections(query.selectedGroupTagIds),
        query.favoriteOnly,
        query.unplayedOnly,
        query.errorOnly,
        _sortedGroups(query.groups),
        _sorted(query.excludedItems.map((tag) => tag.id)),
      ]);

  /**
   * 返回与当前关键字匹配语义一致的搜索指纹。
   *
   * 查询引擎对关键字执行去首尾空格和大小写归一，因此版本身份也采用相同规则。
   */
  static String search(FilterQuery query) =>
      (query.keyword ?? '').trim().toLowerCase();

  /**
   * 返回排序指纹。
   *
   * [presentationSort] 由展示层提供显式且稳定的排序字段和方向名称，不能传对象默认
   * `toString()`；[FilterQuery.sortRule] 仍被纳入，以覆盖领域查询直接指定排序的调用方。
   */
  static String sort(
    FilterQuery query, {
    required String presentationSort,
  }) =>
      jsonEncode(<Object?>[query.sortRule.name, presentationSort]);

  /**
   * 返回用于 `FilterStateSource` 缓存命中的完整查询指纹。
   */
  static String result(
    FilterQuery query, {
    required String presentationSort,
  }) =>
      jsonEncode(<Object?>[
        filter(query),
        search(query),
        sort(query, presentationSort: presentationSort),
      ]);

  static List<String> _sorted(Iterable<String> values) =>
      values.toList(growable: false)..sort();

  static List<Object?> _sortedGroupSelections(
    Map<String, Set<String>> selections,
  ) {
    final entries = selections.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    return <Object?>[
      for (final entry in entries) <Object?>[entry.key, _sorted(entry.value)],
    ];
  }

  static List<Object?> _sortedGroups(Iterable<TagGroup> groups) {
    final ordered = groups.toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    return <Object?>[
      for (final group in ordered)
        <Object?>[
          group.id,
          _sorted(group.items.map((tag) => tag.id)),
          _sorted(group.excludedItems.map((tag) => tag.id)),
        ],
    ];
  }
}

/**
 * 一次可发布媒体库结果的版本身份。
 *
 * 数据、筛选、搜索或排序任一维度改变，旧结果都不得写回页面。
 */
class LibraryResultEpoch {
  const LibraryResultEpoch({
    required this.dataRevision,
    required this.filterFingerprint,
    required this.searchFingerprint,
    required this.sortFingerprint,
  });

  /**
   * 从查询和页面排序状态构建结果版本。
   */
  factory LibraryResultEpoch.fromQuery({
    required int dataRevision,
    required FilterQuery query,
    required String presentationSort,
  }) {
    return LibraryResultEpoch(
      dataRevision: dataRevision,
      filterFingerprint: LibraryQueryFingerprint.filter(query),
      searchFingerprint: LibraryQueryFingerprint.search(query),
      sortFingerprint: LibraryQueryFingerprint.sort(
        query,
        presentationSort: presentationSort,
      ),
    );
  }

  /** 当前媒体库数据代次。 */
  final int dataRevision;

  /** 不含搜索和排序的筛选语义指纹。 */
  final String filterFingerprint;

  /** 归一化后的搜索指纹。 */
  final String searchFingerprint;

  /** 查询排序与页面排序共同组成的指纹。 */
  final String sortFingerprint;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryResultEpoch &&
          dataRevision == other.dataRevision &&
          filterFingerprint == other.filterFingerprint &&
          searchFingerprint == other.searchFingerprint &&
          sortFingerprint == other.sortFingerprint;

  @override
  int get hashCode => Object.hash(
        dataRevision,
        filterFingerprint,
        searchFingerprint,
        sortFingerprint,
      );

  @override
  String toString() =>
      'LibraryResultEpoch(data=$dataRevision, filter=$filterFingerprint, '
      'search=$searchFingerprint, sort=$sortFingerprint)';
}

/**
 * 一次可发布标签计数的版本身份。
 *
 * 排序不会改变标签命中数量，因此该版本刻意不包含排序指纹；标签定义变化必须提升
 * [tagDefinitionRevision]，防止旧候选集合的计数覆盖新标签结构。
 */
class LibraryCountEpoch {
  const LibraryCountEpoch({
    required this.dataRevision,
    required this.filterFingerprint,
    required this.searchFingerprint,
    required this.tagDefinitionRevision,
  });

  /**
   * 从查询和数据代次构建计数版本。
   */
  factory LibraryCountEpoch.fromQuery({
    required int dataRevision,
    required int tagDefinitionRevision,
    required FilterQuery query,
  }) {
    return LibraryCountEpoch(
      dataRevision: dataRevision,
      filterFingerprint: LibraryQueryFingerprint.filter(query),
      searchFingerprint: LibraryQueryFingerprint.search(query),
      tagDefinitionRevision: tagDefinitionRevision,
    );
  }

  /** 当前媒体库数据代次。 */
  final int dataRevision;

  /** 不含搜索和排序的筛选语义指纹。 */
  final String filterFingerprint;

  /** 归一化后的搜索指纹。 */
  final String searchFingerprint;

  /** 标签定义和层级结构的代次。 */
  final int tagDefinitionRevision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryCountEpoch &&
          dataRevision == other.dataRevision &&
          filterFingerprint == other.filterFingerprint &&
          searchFingerprint == other.searchFingerprint &&
          tagDefinitionRevision == other.tagDefinitionRevision;

  @override
  int get hashCode => Object.hash(
        dataRevision,
        filterFingerprint,
        searchFingerprint,
        tagDefinitionRevision,
      );

  @override
  String toString() =>
      'LibraryCountEpoch(data=$dataRevision, filter=$filterFingerprint, '
      'search=$searchFingerprint, tags=$tagDefinitionRevision)';
}

/**
 * 已接受的媒体库结果快照。
 *
 * 快照只保存稳定 `videoId` 的有序副本，避免后续原列表原地修改造成版本与内容不一致。
 */
class LibraryResultSnapshot {
  LibraryResultSnapshot({
    required this.epoch,
    required Iterable<String> orderedVideoIds,
    required this.totalCount,
  }) : orderedVideoIds =
            List<String>.unmodifiable(List<String>.of(orderedVideoIds));

  /** 该结果对应的完整发布版本。 */
  final LibraryResultEpoch epoch;

  /** 筛选并排序后的稳定视频身份。 */
  final List<String> orderedVideoIds;

  /** 生成快照时媒体库的总视频数。 */
  final int totalCount;
}

/**
 * 播放器可消费的不可变过滤队列快照。
 *
 * 队列必须来自已经被页面接受的 [LibraryResultSnapshot]，不得在进入播放器时重新查询全库。
 */
class LibraryQueueSnapshot {
  LibraryQueueSnapshot({
    required this.resultEpoch,
    required Iterable<String> orderedVideoIds,
  }) : orderedVideoIds =
            List<String>.unmodifiable(List<String>.of(orderedVideoIds));

  /**
   * 从已接受结果创建播放队列，保持相同的顺序和版本身份。
   */
  factory LibraryQueueSnapshot.fromResult(LibraryResultSnapshot result) {
    return LibraryQueueSnapshot(
      resultEpoch: result.epoch,
      orderedVideoIds: result.orderedVideoIds,
    );
  }

  /** 队列来源结果的完整版本。 */
  final LibraryResultEpoch resultEpoch;

  /** 播放顺序对应的稳定视频身份。 */
  final List<String> orderedVideoIds;
}
