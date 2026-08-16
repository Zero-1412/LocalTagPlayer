import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/data_backup_models.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../repositories/repository_interfaces.dart';
import '../tags/tag_query_service.dart';
import 'library_data_backup_service.dart';
import 'library_query_compiler.dart';
import 'library_repository_context.dart';
import 'library_scan_service.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * LibraryStore 的真实查询 owner。
 *
 * 该服务只引用共享 [LibraryRepositoryContext]，不复制视频、标签或 path 索引；命令
 * 成功提交后由 context 修订号使候选索引失效。最终筛选仍由 [TagQueryService] 负责。
 */
class LibraryStoreQueryService
    implements LibraryQueryRepository, LibraryQueryCandidateRepository {
  LibraryStoreQueryService({
    required LibraryRepositoryContext context,
    required LibraryDataBackupService dataBackupService,
    LibraryScanService? scanService,
  })  : _context = context,
        _dataBackupService = dataBackupService,
        _scanService = scanService ?? const LibraryScanService();

  final LibraryRepositoryContext _context;
  final LibraryDataBackupService _dataBackupService;
  final LibraryScanService _scanService;
  final LibrarySearchIndex _searchIndex = LibrarySearchIndex();

  Database get _database => _context.database;

  @override
  List<String> get roots => _context.roots;

  @override
  Map<String, VideoItem> get videos => _context.videos;

  @override
  Map<String, VideoItem> get videosById => _context.videos.byVideoId;

  @override
  List<String> get favoriteTags => _context.favoriteTags;

  @override
  List<TagGroup> get tagGroups => _context.tagGroups;

  @override
  Map<String, TagItem> get tagsById => _context.tagsById;

  @override
  Map<String, Set<String>> get videoTagIdsByPathKey =>
      _context.videoTagIdsByPathKey;

  @override
  Map<String, Set<String>> get videoTagIdsByVideoId =>
      _context.videoTagIdsByVideoId;

  @override
  TagQueryContext get tagQueryContext => TagQueryContext(
        tagsById: tagsById,
        videoTagIdsByPathKey: videoTagIdsByPathKey,
        videoTagIdsByVideoId: videoTagIdsByVideoId,
      );

  @override
  Iterable<TagItem> get allTagItems => tagsById.values;

  @override
  Set<String> get allTags {
    final tags = <String>{};
    for (final item in videos.values) {
      tags.addAll(item.tags);
    }
    return tags;
  }

  @override
  int get dataRevision => _context.dataRevision;

  @override
  Map<String, int> resultCounts(FilterQuery query) {
    return TagQueryService(
      videos: videos.values,
      tagContext: tagQueryContext,
    ).resultCounts(query, allTagItems);
  }

  @override
  Future<Map<String, TagUsageSummary>> tagUsageSummaries() async {
    final rows = await _database.rawQuery('''
      SELECT tag_id, source, COUNT(DISTINCT video_id) AS count
      FROM video_tags
      GROUP BY tag_id, source
    ''');
    final summaries = <String, TagUsageSummary>{
      for (final tag in tagsById.values) tag.id: const TagUsageSummary(),
    };
    for (final row in rows) {
      final tagId = row['tag_id'] as String;
      final source = TagSource.values.firstWhere(
        (candidate) => candidate.name == row['source'],
        orElse: () => TagSource.manual,
      );
      final count = row['count'] as int? ?? 0;
      summaries[tagId] = (summaries[tagId] ?? const TagUsageSummary())
          .increment(source, count);
    }
    return summaries;
  }

  @override
  Future<int> countTagReferences(TagItem tag) async {
    final rows = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM video_tags WHERE tag_id = ?',
      [tag.id],
    );
    return rows.first['count'] as int? ?? 0;
  }

  @override
  DataBackupStatus get dataBackupStatus => _dataBackupService.status;

  @override
  Stream<DataBackupStatus> get dataBackupStatusStream =>
      _dataBackupService.statusStream;

  @override
  Future<DataBackupIntegrityReport> checkDataBackupIntegrity() =>
      _dataBackupService.checkIntegrity();

  @override
  Future<Uint8List> createDataBackupExport() =>
      _dataBackupService.createPortableExport();

  @override
  Future<int> countUntrackedVideos() => _scanService.countUntrackedVideos(
        roots,
        videos.keys.toSet(),
      );

  @override
  Set<String> childTagsFor(String parentTag) {
    final tags = <String>{};
    for (final item in videos.values) {
      tags.addAll(item.childTags[parentTag] ?? const <String>{});
    }
    return tags;
  }

  /**
   * 只为真正选择 sqlite profile 的关键词查询提供候选；其它查询返回 null，保持现有
   * FilterStateSource 的增量内存路径。候选结果仍需经过 TagQueryService 最终校验。
   */
  @override
  Future<List<VideoItem>?> queryCandidatesFor(FilterQuery query) async {
    final plan = const LibraryQueryCompiler().compile(
      query,
      _context.queryProfile,
    );
    if (!plan.hasSqlCandidate) {
      return null;
    }
    final ready = await _searchIndex.ensureFresh(
      _database,
      revision: dataRevision,
    );
    if (!ready) {
      return null;
    }
    try {
      final rows = await _database.rawQuery(
        'SELECT video_id FROM videos WHERE ${plan.whereSql}',
        plan.whereArgs,
      );
      return [
        for (final row in rows)
          if (_context.videos.byId(row['video_id'] as String) case final item?)
            item,
      ];
    } on Object {
      // 派生索引或 SQLite 扩展异常时安全回退完整 Dart 语义，不阻塞媒体库。
      return null;
    }
  }
}
