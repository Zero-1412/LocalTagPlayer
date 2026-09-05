import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/platform_models.dart';

// ignore_for_file: slash_for_doc_comments

/** 查询执行 profile；FTS5 只作为候选集加速，不取代 Dart 语义校验。 */
enum LibraryQueryExecutionMode { inMemory, sqliteFts5 }

/**
 * 按数据规模和 SQLite 能力选择查询路径。
 *
 * 阈值不是产品语义，而是可通过压测调整的性能参数。小库保持零额外索引维护；
 * 大库且可用 FTS5 时才允许生成候选 SQL，最终结果仍必须经过 [FilterQuery.matches]。
 */
class LibraryQueryProfile {
  const LibraryQueryProfile({
    required this.videoCount,
    required this.fts5Available,
    this.sqliteThreshold = defaultSqliteThreshold,
  });

  static const int defaultSqliteThreshold = 2000;

  final int videoCount;
  final bool fts5Available;
  final int sqliteThreshold;

  LibraryQueryExecutionMode get mode =>
      fts5Available && videoCount >= sqliteThreshold
          ? LibraryQueryExecutionMode.sqliteFts5
          : LibraryQueryExecutionMode.inMemory;
}

/** 可执行的只读候选计划；调用方必须对返回行再次执行完整 FilterQuery。 */
class LibraryQueryPlan {
  const LibraryQueryPlan({
    required this.mode,
    required this.whereSql,
    required this.whereArgs,
    required this.requiresDartVerification,
  });

  final LibraryQueryExecutionMode mode;
  final String? whereSql;
  final List<Object?> whereArgs;
  final bool requiresDartVerification;

  bool get hasSqlCandidate => whereSql != null;
}

/** 将安全的关键词候选编译为 FTS5 MATCH 子查询。 */
class LibraryQueryCompiler {
  const LibraryQueryCompiler();

  static const searchTableName = 'library_search_fts';

  LibraryQueryPlan compile(
    FilterQuery query,
    LibraryQueryProfile profile,
  ) {
    final keyword = query.keyword?.trim() ?? '';
    final tokens = keyword
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.runes.length >= 3)
        .toList(growable: false);
    // trigram 按 Unicode 码点计数；UTF-16 长度会把短 emoji 词误判为可索引片段。
    // 短片段留给最终 Dart 校验，没有可索引片段时回退完整内存路径。
    if (profile.mode != LibraryQueryExecutionMode.sqliteFts5 ||
        tokens.isEmpty) {
      return LibraryQueryPlan(
        mode: LibraryQueryExecutionMode.inMemory,
        whereSql: null,
        whereArgs: const <Object?>[],
        requiresDartVerification: false,
      );
    }
    final matchExpression =
        tokens.map((token) => '"${token.replaceAll('"', '""')}"').join(' AND ');
    return LibraryQueryPlan(
      mode: LibraryQueryExecutionMode.sqliteFts5,
      whereSql:
          'video_id IN (SELECT video_id FROM $searchTableName WHERE $searchTableName MATCH ?)',
      whereArgs: <Object?>[matchExpression],
      requiresDartVerification: true,
    );
  }
}

/** 可选 FTS5 三元组索引；SQLite 不支持时安全回退，不阻塞主库启动。 */
class LibrarySearchIndex {
  LibrarySearchIndex();

  int? _lastBuiltRevision;
  int? _pendingRevision;
  Future<bool>? _pendingBuild;

  static const tableName = LibraryQueryCompiler.searchTableName;

  Future<bool> ensureSchema(Database db) async {
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS $tableName USING fts5(
          video_id UNINDEXED,
          title,
          path,
          relative_path,
          folder,
          tags,
          tokenize = 'trigram'
        )
      ''');
      return true;
    } on Object {
      return false;
    }
  }

  /** 只重建派生候选索引；主库视频、标签和用户数据不在此动作中删除。 */
  Future<bool> ensureFresh(Database db, {required int revision}) {
    final pending = _pendingBuild;
    if (pending != null) {
      // 同代次共享正在执行的事务；新代次等待旧事务自然收尾后重新核验。
      // 只合并索引维护，不合并用户的查询，也不取消已开始的 SQLite 写入。
      if (_pendingRevision == revision) {
        return pending;
      }
      return pending.then((_) => ensureFresh(db, revision: revision));
    }
    _pendingRevision = revision;
    return _pendingBuild =
        _ensureFresh(db, revision: revision).whenComplete(() {
      // 失败同样释放句柄，下一次请求仍可重试，不能把失败缓存成成功。
      _pendingRevision = null;
      _pendingBuild = null;
    });
  }

  Future<bool> _ensureFresh(Database db, {required int revision}) async {
    final available = await ensureSchema(db);
    if (!available) {
      return false;
    }
    // 每个 repository 会话拥有一个索引；成功写入推进 revision 后才重建派生文本。
    if (_lastBuiltRevision == revision) {
      return true;
    }
    try {
      await rebuild(db);
      _lastBuiltRevision = revision;
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> rebuild(Database db) async {
    await db.transaction((transaction) async {
      await transaction.delete(tableName);
      // 别名必须先解码，JSON 转义形式不等于用户可搜索的原始文本。
      // JSON 扩展不可用或源数据损坏时事务回滚，由 ensureFresh 回退完整查询。
      final rows = await transaction.rawQuery('''
        SELECT v.video_id, v.title, v.path, v.relative_path, v.folder,
               COALESCE(GROUP_CONCAT(
                 COALESCE(t.id, '') || ' ' || COALESCE(t.name, '') || ' ' ||
                 COALESCE(t.display_name, '') || ' ' ||
                 COALESCE((SELECT GROUP_CONCAT(value, ' ')
                           FROM json_each(t.aliases_json)), ''), ' '
               ), '') AS tags
        FROM videos v
        LEFT JOIN video_tags vt ON vt.video_id = v.video_id
        LEFT JOIN tags t ON t.id = vt.tag_id
        GROUP BY v.video_id
      ''');
      final batch = transaction.batch();
      for (final row in rows) {
        batch.insert(tableName, <String, Object?>{
          'video_id': row['video_id'],
          'title': row['title'],
          'path': row['path'],
          'relative_path': row['relative_path'],
          'folder': row['folder'],
          'tags': row['tags'],
        });
      }
      await batch.commit(noResult: true);
    });
  }
}
