import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/tag_rules.dart';
import '../../models/library_scan_models.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../platform/database_provider.dart';
import '../../repositories/repository_interfaces.dart';
import '../tags/tag_query_service.dart';
import 'library_collection_rules.dart';
import 'library_load_diagnostics.dart';
import 'library_metadata_persistence.dart';
import 'library_scan_backend.dart';
import 'library_scan_coordinator.dart';
import 'library_scan_service.dart';
import 'library_store_access.dart';
import 'library_tag_maintenance.dart';
import 'library_tag_persistence.dart';
import 'library_video_persistence.dart';

// ignore_for_file: slash_for_doc_comments, annotate_overrides

class LibraryStore
    implements
        LibraryRepository,
        TagRepository,
        CacheRepository,
        PlaybackRepository,
        LibraryStoreAccess {
  LibraryStore._(
    this._file,
    this._db,
    this.roots,
    this.videos,
    this.favoriteTags,
    this.tagGroups,
    this.tagsById,
    this.videoTagIdsByPathKey,
    this._scanBackend,
  );

  final File _file;
  final Database _db;
  final List<String> roots;
  final Map<String, VideoItem> videos;
  final List<String> favoriteTags;
  final List<TagGroup> tagGroups;
  final Map<String, TagItem> tagsById;
  final Map<String, Set<String>> videoTagIdsByPathKey;

  /** 只读文件系统扫描边界；不拥有 SQLite 连接。 */
  final LibraryScanBackend _scanBackend;

  /** 当前有效扫描代次；旧代次返回后不得提交数据库或回写 UI。 */
  int _scanGeneration = 0;

  @override
  Database get database => _db;
  @override
  LibraryScanBackend get scanBackend => _scanBackend;
  @override
  int get scanGeneration => _scanGeneration;

  LibraryTagPersistence get _tagPersistence =>
      LibraryTagPersistence(_db, tagsById, videoTagIdsByPathKey);

  LibraryVideoPersistence get _videoPersistence => LibraryVideoPersistence(_db);

  LibraryMetadataPersistence get _metadataPersistence =>
      LibraryMetadataPersistence(_db);

  LibraryTagMaintenance get _tagMaintenance => LibraryTagMaintenance(this);

  @override
  LibraryTagPersistence get tagPersistence => _tagPersistence;
  @override
  LibraryVideoPersistence get videoPersistence => _videoPersistence;
  @override
  LibraryMetadataPersistence get metadataPersistence => _metadataPersistence;

  TagQueryContext get tagQueryContext => TagQueryContext(
        tagsById: tagsById,
        videoTagIdsByPathKey: videoTagIdsByPathKey,
      );

  Iterable<TagItem> get allTagItems => tagsById.values;

  Map<String, int> resultCounts(FilterQuery query) {
    return TagQueryService(
      videos: videos.values,
      tagContext: tagQueryContext,
    ).resultCounts(query, allTagItems);
  }

  Future<Map<String, TagUsageSummary>> tagUsageSummaries() async {
    final rows = await _db.rawQuery('''
      SELECT tag_id, source, COUNT(DISTINCT video_id) AS count
      FROM video_tags
      GROUP BY tag_id, source
    ''');
    final summaries = <String, TagUsageSummary>{
      for (final tag in tagsById.values) tag.id: const TagUsageSummary(),
    };
    for (final row in rows) {
      final tagId = row['tag_id'] as String;
      final source = _tagSourceFromName(row['source'] as String?);
      final count = row['count'] as int? ?? 0;
      summaries[tagId] = (summaries[tagId] ?? const TagUsageSummary())
          .increment(source, count);
    }
    return summaries;
  }

  @override
  Future<void> addFavoriteTag(String tag) async {
    final normalized = TagRules.normalizeTag(tag);
    if (normalized.isEmpty || favoriteTags.contains(normalized)) return;
    favoriteTags.add(normalized);
    await saveMetadata();
  }

  @override
  Future<void> removeFavoriteTag(String tag) async {
    favoriteTags.removeWhere((value) => TagRules.sameTag(value, tag));
    await saveMetadata();
  }

  @override
  Future<void> replaceRoot(String oldRoot, String newRoot) async {
    final oldKey = TagRules.pathKey(TagRules.normalizeRootPath(oldRoot));
    final normalizedNewRoot = TagRules.normalizeRootPath(newRoot);
    final index = roots.indexWhere((root) => TagRules.pathKey(root) == oldKey);
    if (index < 0 || normalizedNewRoot.isEmpty) return;
    final previousRoot = roots[index];
    roots[index] = normalizedNewRoot;
    try {
      await saveMetadata();
    } catch (_) {
      roots[index] = previousRoot;
      rethrow;
    }
  }

  @override
  Future<List<TagGroup>> loadGroups() async =>
      List<TagGroup>.unmodifiable(tagGroups);

  @override
  Future<List<TagItem>> loadTags({String? groupId}) async =>
      List<TagItem>.unmodifiable(
        tagsById.values.where(
          (tag) => groupId == null || tag.groupId == groupId,
        ),
      );

  @override
  Future<void> attachTag({
    required String videoId,
    required String tagId,
    required TagSource source,
    bool locked = false,
  }) async {
    final video =
        videos.values.where((item) => item.videoId == videoId).firstOrNull;
    final tag = tagsById[tagId];
    if (video == null || tag == null) {
      throw StateError('无法为不存在的视频或标签建立关联');
    }
    final batch = _db.batch();
    _tagPersistence.attachTagInBatch(
      batch,
      video,
      tag,
      source: source,
      locked: locked,
    );
    await batch.commit(noResult: true);
  }

  @override
  Future<void> detachTag({
    required String videoId,
    required String tagId,
    required TagSource source,
  }) async {
    final video =
        videos.values.where((item) => item.videoId == videoId).firstOrNull;
    if (video == null) return;
    await _db.delete(
      'video_tags',
      where: 'video_id = ? AND tag_id = ? AND source = ?',
      whereArgs: [videoId, tagId, source.name],
    );
    final remainingRows = await _db.rawQuery(
      'SELECT COUNT(*) FROM video_tags WHERE video_id = ? AND tag_id = ?',
      [videoId, tagId],
    );
    final remaining = remainingRows.first.values.first as int?;
    if ((remaining ?? 0) == 0) {
      videoTagIdsByPathKey[TagRules.pathKey(video.path)]?.remove(tagId);
    }
  }

  @override
  Future<CacheStatus> thumbnailStatus(String videoId) =>
      _loadCacheStatus('thumbnail', videoId);

  @override
  Future<CacheStatus> mediaDetailsStatus(String videoId) =>
      _loadCacheStatus('media_details', videoId);

  @override
  Future<void> saveThumbnailStatus(String videoId, CacheStatus status) =>
      _saveCacheStatus('thumbnail', videoId, status);

  @override
  Future<void> saveMediaDetailsStatus(String videoId, CacheStatus status) =>
      _saveCacheStatus('media_details', videoId, status);

  /** 缓存状态只保存诊断字段，不保存媒体路径。 */
  Future<CacheStatus> _loadCacheStatus(String kind, String videoId) async {
    final rows = await _db.query(
      'metadata',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: ['cache.$kind.$videoId'],
      limit: 1,
    );
    if (rows.isEmpty) return const CacheStatus(kind: CacheStatusKind.unknown);
    final decoded = jsonDecode(rows.first['value']! as String);
    if (decoded is! Map) {
      return const CacheStatus(kind: CacheStatusKind.unknown);
    }
    return CacheStatus(
      kind: CacheStatusKind.values.firstWhere(
        (value) => value.name == decoded['kind'],
        orElse: () => CacheStatusKind.unknown,
      ),
      message: decoded['message'] as String?,
      updatedAt: DateTime.tryParse(decoded['updatedAt']?.toString() ?? ''),
    );
  }

  Future<void> _saveCacheStatus(
    String kind,
    String videoId,
    CacheStatus status,
  ) async {
    await _db.insert(
      'metadata',
      {
        'key': 'cache.$kind.$videoId',
        'value': jsonEncode({
          'kind': status.kind.name,
          'message': status.message,
          'updatedAt': status.updatedAt?.toIso8601String(),
        }),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> saveSession(PlaybackSession session) async {
    await _db.insert(
      'metadata',
      {
        'key': 'playback.last_session',
        'value': jsonEncode({
          'id': session.id,
          'currentPath': session.currentPath,
          'queuePaths': session.queuePaths,
          'currentVideoId': session.currentVideoId,
          'createdAt': session.createdAt?.toIso8601String(),
          'positionMs': session.position.inMilliseconds,
          'durationMs': session.duration?.inMilliseconds,
          'isPlaying': session.isPlaying,
        }),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<PlaybackSession?> loadLastSession() async {
    final rows = await _db.query(
      'metadata',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const ['playback.last_session'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.first['value']! as String);
    if (decoded is! Map || decoded['currentPath'] is! String) return null;
    return PlaybackSession(
      id: decoded['id'] as String?,
      currentPath: decoded['currentPath']! as String,
      queuePaths:
          ((decoded['queuePaths'] as List?) ?? const <Object>[]).cast<String>(),
      currentVideoId: decoded['currentVideoId'] as String?,
      createdAt: DateTime.tryParse(decoded['createdAt']?.toString() ?? ''),
      position: Duration(milliseconds: decoded['positionMs'] as int? ?? 0),
      duration: decoded['durationMs'] == null
          ? null
          : Duration(milliseconds: decoded['durationMs'] as int),
      isPlaying: decoded['isPlaying'] == true,
    );
  }

  @override
  Future<void> savePlaybackPosition({
    required String videoId,
    required Duration position,
    required Duration duration,
    required bool completed,
    required DateTime updatedAt,
  }) async {
    final item =
        videos.values.where((video) => video.videoId == videoId).firstOrNull;
    if (item == null) return;
    item
      ..playbackPosition = position
      ..playbackDuration = duration
      ..playbackCompleted = completed
      ..playbackPositionUpdatedAt = updatedAt
      ..lastPlayedAt = updatedAt;
    await _videoPersistence.upsert(item);
  }

  /**
   * 从 SQLite 恢复媒体库；[diagnostics] 仅供显式性能基准收集阶段耗时。
   *
   * 默认调用不保留诊断对象，也不会记录任何媒体路径或标签内容。
   */
  static Future<LibraryStore> load({
    LibraryLoadDiagnostics? diagnostics,
    required LibraryScanBackend scanBackend,
    required DatabaseProvider databaseProvider,
  }) async {
    final legacyFile = await databaseProvider.legacyLibraryFile();
    final db = diagnostics == null
        ? await _openDatabase(databaseProvider)
        : await diagnostics.measureAsync(
            'sqlite.open_and_maintenance',
            () => _openDatabase(databaseProvider),
          );
    final store = await _loadFromDatabase(
      legacyFile,
      db,
      diagnostics: diagnostics,
      scanBackend: scanBackend,
    );
    if (store.videos.isEmpty && await legacyFile.exists()) {
      if (diagnostics == null) {
        await store._importLegacyJson();
      } else {
        await diagnostics.measureAsync(
          'legacy.import',
          store._importLegacyJson,
        );
      }
    }
    await store.ensureTagIndexCoverage(diagnostics: diagnostics);
    return store;
  }

  static Future<Database> _openDatabase(DatabaseProvider provider) {
    return provider.openLibraryDatabase(
      version: 1,
      createSchema: _createSchema,
      maintainSchema: _createSchema,
    );
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS videos (
        path TEXT PRIMARY KEY,
        video_id TEXT,
        title TEXT NOT NULL,
        folder TEXT NOT NULL,
        root_path TEXT,
        relative_path TEXT,
        file_size INTEGER,
        modified_ms INTEGER,
        tags_json TEXT NOT NULL,
        child_tags_json TEXT NOT NULL,
        is_favorite INTEGER NOT NULL,
        media_details_json TEXT,
        media_fingerprint TEXT,
        thumbnail_error TEXT,
        media_details_error TEXT,
        added_at TEXT NOT NULL,
        last_played_at TEXT,
        is_missing INTEGER NOT NULL DEFAULT 0,
        playback_position_ms INTEGER NOT NULL DEFAULT 0,
        playback_duration_ms INTEGER NOT NULL DEFAULT 0,
        playback_completed INTEGER NOT NULL DEFAULT 0,
        playback_position_updated_at TEXT
      )
    ''');
    await _ensureVideoColumns(db);
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_videos_folder ON videos(folder)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_videos_title ON videos(title)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_videos_root_path ON videos(root_path)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_videos_favorite ON videos(is_favorite)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_videos_modified ON videos(modified_ms)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_videos_added ON videos(added_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_videos_last_played ON videos(last_played_at)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tag_groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        display_name TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        allow_multi_select INTEGER NOT NULL DEFAULT 1,
        default_logic TEXT NOT NULL DEFAULT 'sameGroupOr'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        display_name TEXT,
        group_id TEXT,
        parent_id TEXT,
        color TEXT,
        source TEXT NOT NULL,
        aliases_json TEXT NOT NULL DEFAULT '[]',
        usage_count INTEGER NOT NULL DEFAULT 0,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        is_hidden INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tag_aliases (
        tag_id TEXT NOT NULL,
        alias TEXT NOT NULL,
        PRIMARY KEY (tag_id, alias)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_tags (
        video_path TEXT NOT NULL,
        video_id TEXT,
        tag_id TEXT NOT NULL,
        source TEXT NOT NULL,
        locked INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (video_path, tag_id, source)
      )
    ''');
    await _ensureVideoTagColumns(db);
    if (Platform.isWindows) {
      // 旧库只在缺失稳定身份时执行 path 回填；NOCASE 索引避免每条关系都全表扫描 videos。
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_videos_path_nocase '
        'ON videos(path COLLATE NOCASE)',
      );
    }
    await _backfillStableVideoIds(db);
    // 先用轻量查询判断迁移遗留，正常启动不执行全表删除。
    final duplicateRelations = await db.rawQuery('''
      SELECT 1
      FROM video_tags
      WHERE video_id IS NOT NULL
      GROUP BY video_id, tag_id, source
      HAVING COUNT(*) > 1
      LIMIT 1
    ''');
    if (duplicateRelations.isNotEmpty) {
      // 仅旧版迁移可能遗留同一稳定身份的重复 path 兼容行；正常启动不再执行全表 DELETE。
      await db.execute('''
        DELETE FROM video_tags
        WHERE video_id IS NOT NULL
          AND rowid NOT IN (
            SELECT MIN(rowid)
            FROM video_tags
            WHERE video_id IS NOT NULL
            GROUP BY video_id, tag_id, source
          )
      ''');
    }
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_videos_video_id ON videos(video_id)');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_tags_group ON tags(group_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tag_aliases_alias ON tag_aliases(alias)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_video_tags_video ON video_tags(video_path)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_video_tags_video_id ON video_tags(video_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_video_tags_identity ON video_tags(video_id, tag_id, source) WHERE video_id IS NOT NULL');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_video_tags_tag ON video_tags(tag_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_video_tags_source ON video_tags(source)');
    await _ensureDefaultTagGroups(db);
  }

  static Future<void> _ensureVideoColumns(Database db) async {
    final rows = await db.rawQuery('PRAGMA table_info(videos)');
    final columns = rows.map((row) => row['name'] as String).toSet();
    Future<void> addColumn(String name, String definition) async {
      if (!columns.contains(name)) {
        await db.execute('ALTER TABLE videos ADD COLUMN $name $definition');
      }
    }

    await addColumn('root_path', 'TEXT');
    await addColumn('relative_path', 'TEXT');
    await addColumn('file_size', 'INTEGER');
    await addColumn('modified_ms', 'INTEGER');
    await addColumn('video_id', 'TEXT');
    await addColumn('is_missing', 'INTEGER NOT NULL DEFAULT 0');
    await addColumn('playback_position_ms', 'INTEGER NOT NULL DEFAULT 0');
    await addColumn('playback_duration_ms', 'INTEGER NOT NULL DEFAULT 0');
    await addColumn('playback_completed', 'INTEGER NOT NULL DEFAULT 0');
    await addColumn('playback_position_updated_at', 'TEXT');
  }

  /** 为旧版 `video_tags` 增加稳定身份兼容列，保留旧 path 列用于平滑迁移。 */
  static Future<void> _ensureVideoTagColumns(Database db) async {
    final rows = await db.rawQuery('PRAGMA table_info(video_tags)');
    final columns = rows.map((row) => row['name'] as String).toSet();
    if (!columns.contains('video_id')) {
      await db.execute('ALTER TABLE video_tags ADD COLUMN video_id TEXT');
    }
  }

  /**
   * 幂等回填旧视频稳定身份，并只修复缺少 `video_id` 的旧标签关系。
   *
   * 已绑定稳定身份的关系不能在每次启动时按 mutable path 重写；这既会破坏 relink 语义，
   * 也会在 Windows NOCASE 比较缺少对应索引时退化为关系数乘视频数的全表扫描。
   */
  static Future<void> _backfillStableVideoIds(Database db) async {
    final rows = await db.query(
      'videos',
      columns: const ['path', 'video_id'],
      orderBy: 'added_at ASC, path ASC',
    );
    final batch = db.batch();
    final seenIds = <String>{};
    var changed = false;
    for (final row in rows) {
      final currentId = (row['video_id'] as String? ?? '').trim();
      if (currentId.isNotEmpty && seenIds.add(currentId)) {
        continue;
      }
      final newId = VideoItem.newVideoId();
      seenIds.add(newId);
      batch.update(
        'videos',
        {'video_id': newId},
        where: Platform.isWindows ? 'path = ? COLLATE NOCASE' : 'path = ?',
        whereArgs: [row['path']],
      );
      changed = true;
    }
    if (changed) {
      await batch.commit(noResult: true);
    }
    await db.execute('''
      UPDATE video_tags
      SET video_id = (
        SELECT videos.video_id
        FROM videos
        WHERE ${Platform.isWindows ? 'videos.path = video_tags.video_path COLLATE NOCASE' : 'videos.path = video_tags.video_path'}
      )
      WHERE video_id IS NULL OR TRIM(video_id) = ''
    ''');
  }

  static Future<void> _ensureDefaultTagGroups(Database db) async {
    final groups = const <Map<String, Object?>>[
      {
        'id': 'folder.primary',
        'name': 'folder.primary',
        'display_name': '\u4e00\u7ea7\u6587\u4ef6\u5939',
        'sort_order': 10,
      },
      {
        'id': 'folder.child',
        'name': 'folder.child',
        'display_name': '\u4e8c\u7ea7\u6587\u4ef6\u5939',
        'sort_order': 20,
      },
      {
        'id': 'manual',
        'name': 'manual',
        'display_name': '\u624b\u52a8\u6807\u7b7e',
        'sort_order': 30,
      },
    ];
    for (final group in groups) {
      await db.insert(
        'tag_groups',
        {
          ...group,
          'allow_multi_select': 1,
          'default_logic': TagGroupLogic.sameGroupOr.name,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /** 将已读取的标签组行转换为不可变业务模型。 */
  static List<TagGroup> _tagGroupsFromRows(List<Map<String, Object?>> rows) {
    return rows
        .map(
          (row) => TagGroup(
            id: row['id'] as String,
            name: row['name'] as String,
            displayName: row['display_name'] as String?,
            sortOrder: row['sort_order'] as int? ?? 0,
            allowMultiSelect: (row['allow_multi_select'] as int? ?? 1) == 1,
            defaultLogic:
                _tagGroupLogicFromName(row['default_logic'] as String?),
            items: const <TagItem>[],
          ),
        )
        .toList();
  }

  /** 将别名行和标签行合并为按 tagId 索引的标签模型。 */
  static Map<String, TagItem> _tagsByIdFromRows(
    List<Map<String, Object?>> aliasRows,
    List<Map<String, Object?>> tagRows,
  ) {
    final aliasesByTagId = <String, Set<String>>{};
    for (final row in aliasRows) {
      final tagId = row['tag_id'] as String;
      final alias = TagRules.normalizeTag(row['alias'] as String? ?? '');
      if (alias.isNotEmpty) {
        (aliasesByTagId[tagId] ??= <String>{}).add(alias);
      }
    }
    final tags = <String, TagItem>{};
    for (final row in tagRows) {
      final id = row['id'] as String;
      tags[id] = _tagFromRow(row,
          extraAliases: aliasesByTagId[id] ?? const <String>{});
    }
    return tags;
  }

  /** 将视频标签 JOIN 结果 hydration 为规范化路径索引。 */
  static Map<String, Set<String>> _videoTagIdsFromRows(
      List<Map<String, Object?>> rows) {
    final links = <String, Set<String>>{};
    for (final row in rows) {
      final path = row['path'] as String;
      final tagId = row['tag_id'] as String;
      (links[TagRules.pathKey(path)] ??= <String>{}).add(tagId);
    }
    return links;
  }

  static TagGroupLogic _tagGroupLogicFromName(String? value) {
    return TagGroupLogic.values.firstWhere(
      (logic) => logic.name == value,
      orElse: () => TagGroupLogic.sameGroupOr,
    );
  }

  static TagSource _tagSourceFromName(String? value) {
    return TagSource.values.firstWhere(
      (source) => source.name == value,
      orElse: () => TagSource.manual,
    );
  }

  static TagItem _tagFromRow(Map<String, Object?> row,
      {Iterable<String> extraAliases = const <String>[]}) {
    final aliases =
        ((jsonDecode(row['aliases_json'] as String? ?? '[]') as List?) ??
                const [])
            .cast<String>();
    final mergedAliases =
        dedupeLibraryTags(<String>[...aliases, ...extraAliases]);
    return TagItem(
      id: row['id'] as String,
      name: row['name'] as String,
      displayName: row['display_name'] as String?,
      groupId: row['group_id'] as String?,
      parentId: row['parent_id'] as String?,
      color: row['color'] as String?,
      source: _tagSourceFromName(row['source'] as String?),
      aliases: mergedAliases,
      usageCount: row['usage_count'] as int? ?? 0,
      isFavorite: (row['is_favorite'] as int? ?? 0) == 1,
      isHidden: (row['is_hidden'] as int? ?? 0) == 1,
      sortOrder: row['sort_order'] as int? ?? 0,
    );
  }

  static Future<LibraryStore> _loadFromDatabase(
    File legacyFile,
    Database db, {
    LibraryLoadDiagnostics? diagnostics,
    required LibraryScanBackend scanBackend,
  }) async {
    final metadata = diagnostics == null
        ? await LibraryMetadataPersistence(db).load()
        : await diagnostics.measureAsync(
            'sqlite.metadata_query_and_build',
            () => LibraryMetadataPersistence(db).load(),
          );
    final videoRows = diagnostics == null
        ? await db.query('videos')
        : await diagnostics.measureAsync(
            'sqlite.video_rows_query',
            () => db.query('videos'),
            itemCount: (rows) => rows.length,
          );
    final videos = diagnostics == null
        ? _videosFromRows(videoRows)
        : diagnostics.measureSync(
            'dart.video_object_build',
            () => _videosFromRows(videoRows),
            itemCount: (items) => items.length,
          );
    final groupRows = diagnostics == null
        ? await db.query(
            'tag_groups',
            orderBy: 'sort_order ASC, display_name ASC',
          )
        : await diagnostics.measureAsync(
            'sqlite.tag_group_rows_query',
            () => db.query(
              'tag_groups',
              orderBy: 'sort_order ASC, display_name ASC',
            ),
            itemCount: (rows) => rows.length,
          );
    final aliasRows = diagnostics == null
        ? await db.query('tag_aliases')
        : await diagnostics.measureAsync(
            'sqlite.tag_alias_rows_query',
            () => db.query('tag_aliases'),
            itemCount: (rows) => rows.length,
          );
    final tagRows = diagnostics == null
        ? await db.query('tags')
        : await diagnostics.measureAsync(
            'sqlite.tag_rows_query',
            () => db.query('tags'),
            itemCount: (rows) => rows.length,
          );
    final tagGroups = diagnostics == null
        ? _tagGroupsFromRows(groupRows)
        : diagnostics.measureSync(
            'dart.tag_group_object_build',
            () => _tagGroupsFromRows(groupRows),
            itemCount: (groups) => groups.length,
          );
    final tagsById = diagnostics == null
        ? _tagsByIdFromRows(aliasRows, tagRows)
        : diagnostics.measureSync(
            'dart.tag_object_and_alias_hydration',
            () => _tagsByIdFromRows(aliasRows, tagRows),
            itemCount: (tags) => tags.length,
          );
    final relationRows = diagnostics == null
        ? await _queryVideoTagRows(db)
        : await diagnostics.measureAsync(
            'sqlite.video_tag_relation_query',
            () => _queryVideoTagRows(db),
            itemCount: (rows) => rows.length,
          );
    final videoTagIdsByPathKey = diagnostics == null
        ? _videoTagIdsFromRows(relationRows)
        : diagnostics.measureSync(
            'dart.video_tag_relation_hydration',
            () => _videoTagIdsFromRows(relationRows),
            itemCount: (links) => links.length,
          );
    return LibraryStore._(
      legacyFile,
      db,
      metadata.roots,
      videos,
      metadata.favoriteTags,
      tagGroups,
      tagsById,
      videoTagIdsByPathKey,
      scanBackend,
    );
  }

  /** 将视频表行转换为按规范化路径索引的对象集合。 */
  static Map<String, VideoItem> _videosFromRows(
      List<Map<String, Object?>> rows) {
    final videos = <String, VideoItem>{};
    for (final row in rows) {
      final item = LibraryVideoPersistence.videoFromRow(row);
      videos[TagRules.pathKey(item.path)] = item;
    }
    return videos;
  }

  /** 一次性读取稳定身份对应的视频标签关系，避免逐视频 N+1 查询。 */
  static Future<List<Map<String, Object?>>> _queryVideoTagRows(Database db) {
    return db.rawQuery('''
      SELECT vt.tag_id, v.path
      FROM video_tags vt
      INNER JOIN videos v ON v.video_id = vt.video_id
    ''');
  }

  Future<void> _importLegacyJson() async {
    try {
      final decoded =
          jsonDecode(await _file.readAsString()) as Map<String, Object?>;
      roots
        ..clear()
        ..addAll(dedupeLibraryRoots(
            ((decoded['roots'] as List?) ?? const []).cast<String>()));
      favoriteTags
        ..clear()
        ..addAll(dedupeLibraryTags(
            ((decoded['favoriteTags'] as List?) ?? const []).cast<String>()));
      videos.clear();
      for (final raw in (decoded['videos'] as List? ?? const [])) {
        final item = VideoItem.fromJson((raw as Map).cast<String, Object?>());
        videos[TagRules.pathKey(item.path)] = item;
      }
      await save();
    } catch (_) {
      // 损坏的旧 JSON 不应阻塞新的 SQLite 媒体库启动。
    }
  }

  Future<void> rebuildTagIndex() async {
    final batch = _db.batch();
    batch.delete('video_tags');
    videoTagIdsByPathKey.clear();
    for (final item in videos.values) {
      _tagMaintenance.syncFolderTagsInBatch(batch, item);
    }
    await batch.commit(noResult: true);
  }

  Future<void> ensureTagIndexCoverage(
      {LibraryLoadDiagnostics? diagnostics}) async {
    if (videos.isEmpty) {
      return;
    }
    final batch = _db.batch();
    final missingCoverage = diagnostics == null
        ? _videosMissingFolderTagCoverage()
        : diagnostics.measureSync(
            'dart.folder_tag_coverage_evaluation',
            _videosMissingFolderTagCoverage,
            itemCount: (items) => items.length,
          );
    for (final item in missingCoverage) {
      _tagMaintenance.syncFolderTagsInBatch(batch, item);
    }
    if (missingCoverage.isNotEmpty) {
      if (diagnostics == null) {
        await batch.commit(noResult: true);
      } else {
        await diagnostics.measureAsync(
          'sqlite.folder_tag_coverage_write',
          () => batch.commit(noResult: true),
          itemCount: (_) => missingCoverage.length,
        );
      }
    }
  }

  /**
   * 只返回确实缺少路径派生 folder tagId 的视频。
   *
   * root 直属视频合法地没有一级/二级 folder 标签，不能因为关系集合为空就在每次启动时
   * 重复排入 SQLite batch；manual 关系也不能被误当作 folder 覆盖证明。
   */
  List<VideoItem> _videosMissingFolderTagCoverage() {
    final missing = <VideoItem>[];
    for (final item in videos.values) {
      final expected = _tagMaintenance.expectedFolderTagIds(item);
      if (expected.isEmpty) {
        continue;
      }
      final actual =
          videoTagIdsByPathKey[TagRules.pathKey(item.path)] ?? const <String>{};
      if (!actual.containsAll(expected)) {
        missing.add(item);
      }
    }
    return missing;
  }

  Future<void> replaceManualTags(
    VideoItem item, {
    String? parentTag,
  }) async {
    await _tagMaintenance.replaceManualTags(item, parentTag: parentTag);
  }

  Future<void> saveTag(TagItem tag) async {
    await _tagPersistence.saveTag(tag);
  }

  Future<TagItem> createManualTag({
    required String name,
    required String groupId,
    String? displayName,
  }) async {
    final normalized = TagRules.normalizeTag(name);
    if (normalized.isEmpty) {
      throw ArgumentError('tag name is empty');
    }
    final id = TagRules.tagIdFor(name: normalized, groupId: groupId);
    final existing = tagsById[id];
    if (existing != null && existing.source != TagSource.manual) {
      throw StateError('manual tag conflicts with an existing non-manual tag');
    }
    final tag = existing ??
        TagItem(
          id: id,
          name: normalized,
          displayName: normalized,
          groupId: groupId,
          source: TagSource.manual,
        );
    final updated = TagItem(
      id: tag.id,
      name: tag.name,
      displayName: displayName == null || displayName.trim().isEmpty
          ? tag.displayName
          : displayName.trim(),
      groupId: groupId,
      parentId: tag.parentId,
      color: tag.color,
      source: TagSource.manual,
      aliases: tag.aliases,
      usageCount: tag.usageCount,
      isFavorite: tag.isFavorite,
      isHidden: tag.isHidden,
      sortOrder: tag.sortOrder,
    );
    await saveTag(updated);
    return updated;
  }

  Future<void> updateTagDetails(
    TagItem tag, {
    String? displayName,
    Iterable<String>? aliases,
    String? groupId,
    bool? isHidden,
    bool? isFavorite,
    int? sortOrder,
  }) async {
    await saveTag(
      TagItem(
        id: tag.id,
        name: tag.name,
        displayName: displayName,
        groupId: groupId ?? tag.groupId,
        parentId: tag.parentId,
        color: tag.color,
        source: tag.source,
        aliases: aliases == null ? tag.aliases : dedupeLibraryTags(aliases),
        usageCount: tag.usageCount,
        isFavorite: isFavorite ?? tag.isFavorite,
        isHidden: isHidden ?? tag.isHidden,
        sortOrder: sortOrder ?? tag.sortOrder,
      ),
    );
  }

  Future<int> countTagReferences(TagItem tag) async {
    return _tagPersistence.countTagReferences(tag);
  }

  Future<int> batchAddManualTag(TagItem tag, Iterable<VideoItem> items) async {
    return _tagMaintenance.batchAddManualTag(tag, items);
  }

  Future<int> batchRemoveManualTag(
      TagItem tag, Iterable<VideoItem> items) async {
    return _tagMaintenance.batchRemoveManualTag(tag, items);
  }

  Future<void> save() async {
    final batch = _db.batch();
    _metadataPersistence.saveInBatch(
      batch,
      roots: roots,
      favoriteTags: favoriteTags,
    );
    batch.delete('videos');
    for (final item in videos.values) {
      _videoPersistence.insertInBatch(batch, item);
      _tagMaintenance.syncFolderTagsInBatch(batch, item);
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveMetadata() async {
    await _metadataPersistence.save(
      roots: roots,
      favoriteTags: favoriteTags,
    );
  }

  /**
   * 关闭当前媒体库数据库连接。
   *
   * 测试和 repository 拆分需要显式释放 SQLite 文件句柄，避免临时目录清理失败。
   */
  Future<void> close() async {
    if (_scanGeneration > 0) {
      _scanBackend.cancelGeneration(_scanGeneration);
    }
    await _db.close();
  }

  Future<void> upsertVideo(VideoItem item) async {
    videos[TagRules.pathKey(item.path)] = item;
    await _videoPersistence.upsert(item);
  }

  /**
   * 合并写入后台媒体详情更新，避免大目录导入时为每个文件单独提交 SQLite。
   *
   * 媒体详情只更新现有视频行；标签关系仍由扫描或标签维护流程拥有，不能在这里重建。
   */
  Future<void> upsertVideos(Iterable<VideoItem> items) async {
    final updates = items.toList(growable: false);
    if (updates.isEmpty) {
      return;
    }
    for (final item in updates) {
      videos[TagRules.pathKey(item.path)] = item;
    }
    await _videoPersistence.upsertAll(updates);
  }

  /**
   * 在单个 SQLite 事务中删除视频记录及其全部标签关系。
   *
   * 收藏、播放进度、媒体详情和稳定身份字段都存放在 videos 行中；删除该行后不会留下
   * 孤立用户状态。磁盘文件与缩略图缓存由 Application 层按用户选择分别处理。
   */
  Future<VideoItem?> deleteVideo(String path) async {
    final pathKey = TagRules.pathKey(path);
    final item = videos[pathKey];
    final batch = _db.batch();
    if (item != null) {
      _tagPersistence.deleteVideoLinksInBatch(
        batch,
        item,
        updateMemoryIndex: false,
      );
    }
    _videoPersistence.deleteInBatch(batch, path);
    await batch.commit(noResult: true);
    videos.remove(pathKey);
    videoTagIdsByPathKey.remove(pathKey);
    return item;
  }

  Future<int> addRootAndScan(String rootPath) async {
    return (await addRootAndScanWithChanges(rootPath)).addedCount;
  }

  /** 添加 root 并返回可供 UI 与探测队列差量消费的事务提交结果。 */
  Future<LibraryScanCommitResult> addRootAndScanWithChanges(
    String rootPath,
  ) =>
      addRootsAndScanWithChanges(<String>[rootPath]);

  /**
   * 批量注册 root，并在 metadata 只落盘一次后执行一轮扫描。
   *
   * 文件选择和拖放可能同时命中多个父目录；先去重再扫描可避免每新增一个目录就重复遍历
   * 已有大媒体库。SQLite 写入、stable identity 与 folder 标签仍由原扫描协调器统一处理。
   */
  @override
  Future<LibraryScanCommitResult> addRootsAndScanWithChanges(
    Iterable<String> rootPaths,
  ) async {
    final normalizedRoots = <String>[];
    final pendingKeys = <String>{};
    for (final rootPath in rootPaths) {
      final normalizedRoot = TagRules.normalizeRootPath(rootPath);
      if (normalizedRoot.isEmpty) {
        continue;
      }
      final rootKey = TagRules.pathKey(normalizedRoot);
      if (pendingKeys.add(rootKey)) {
        normalizedRoots.add(normalizedRoot);
      }
    }
    if (normalizedRoots.isEmpty) {
      return LibraryScanCommitResult.cancelled(_scanGeneration);
    }

    var metadataChanged = false;
    final existingKeys = roots.map(TagRules.pathKey).toSet();
    for (final normalizedRoot in normalizedRoots) {
      if (existingKeys.add(TagRules.pathKey(normalizedRoot))) {
        roots.add(normalizedRoot);
        metadataChanged = true;
      }
    }
    if (metadataChanged) {
      await saveMetadata();
    }
    return scanWithChanges();
  }

  /**
   * 从媒体库根目录列表移除一个目录。
   *
   * root 配置、仅受该 root 管理的视频行及其标签关系在同一事务中提交。重叠 root
   * 仍覆盖的视频会保留，磁盘文件始终不由该操作删除。
   */
  Future<List<VideoItem>> removeRoot(String rootPath) async {
    final normalizedRoot = TagRules.normalizeRootPath(rootPath);
    final rootKey = TagRules.pathKey(normalizedRoot);
    if (!roots.any((root) => TagRules.pathKey(root) == rootKey)) {
      return const <VideoItem>[];
    }

    // 取消进行中的只读扫描并推进代次，禁止旧扫描在 root 删除后重新提交旧结果。
    if (_scanGeneration > 0) {
      _scanBackend.cancelGeneration(_scanGeneration);
      _scanGeneration++;
    }
    final remainingRoots = <String>[
      for (final root in roots)
        if (TagRules.pathKey(root) != rootKey) root,
    ];
    final removedVideos = <VideoItem>[
      for (final item in videos.values)
        if (TagRules.rootContainsFile(normalizedRoot, item.path) &&
            !remainingRoots.any(
              (root) => TagRules.rootContainsFile(root, item.path),
            ))
          item,
    ];

    final batch = _db.batch();
    _metadataPersistence.saveInBatch(
      batch,
      roots: remainingRoots,
      favoriteTags: favoriteTags,
    );
    for (final item in removedVideos) {
      _tagPersistence.deleteVideoLinksInBatch(
        batch,
        item,
        updateMemoryIndex: false,
      );
      _videoPersistence.deleteInBatch(batch, item.path);
    }
    await batch.commit(noResult: true);

    roots
      ..clear()
      ..addAll(remainingRoots);
    for (final item in removedVideos) {
      final pathKey = TagRules.pathKey(item.path);
      videos.remove(pathKey);
      videoTagIdsByPathKey.remove(pathKey);
    }
    return List<VideoItem>.unmodifiable(removedVideos);
  }

  Future<int> scan() async {
    return (await scanWithChanges()).addedCount;
  }

  /**
   * 取消旧代次并执行只读后端扫描；只有当前代次可进入 Application 事务提交。
   */
  Future<LibraryScanCommitResult> scanWithChanges() async {
    final previousGeneration = _scanGeneration;
    if (previousGeneration > 0) {
      _scanBackend.cancelGeneration(previousGeneration);
    }
    final generation = ++_scanGeneration;
    return LibraryScanCoordinator(this).scan(generationId: generation);
  }

  /**
   * 通过 fingerprint 校验把一个 missing 条目关联到用户选择的新文件。
   *
   * 稳定 videoId 以及 manual 标签、收藏、播放记录和进度保持不变；folder 标签随新路径更新。
   */
  Future<void> relinkMissingVideo(VideoItem item, String newPath) {
    return LibraryScanCoordinator(this).relinkMissingVideo(item, newPath);
  }

  /** 在单个 SQLite batch 中提交多条 Relink，并返回重新校验或事务失败的 videoId。 */
  Future<Set<String>> relinkMissingVideosInBatch(
    Map<VideoItem, String> targets,
  ) {
    return LibraryScanCoordinator(this).relinkMissingVideosInBatch(targets);
  }

  static Future<String?> mediaFingerprintFor(String path) async {
    return LibraryScanService.mediaFingerprintFor(path);
  }

  Future<int> countUntrackedVideos() async {
    return const LibraryScanService().countUntrackedVideos(
      roots,
      videos.keys.toSet(),
    );
  }

  Set<String> get allTags {
    final tags = <String>{};
    for (final item in videos.values) {
      tags.addAll(item.tags);
    }
    return tags;
  }

  Set<String> childTagsFor(String parentTag) {
    final tags = <String>{};
    for (final item in videos.values) {
      tags.addAll(item.childTags[parentTag] ?? const <String>{});
    }
    return tags;
  }
}
