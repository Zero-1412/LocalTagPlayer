import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/tag_rules.dart';
import '../../models/data_backup_models.dart';
import '../../models/library_scan_models.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../models/video_visual_signature.dart';
import '../../platform/database_provider.dart';
import '../../repositories/repository_interfaces.dart';
import 'library_collection_rules.dart';
import 'library_data_backup_service.dart';
import 'library_load_diagnostics.dart';
import 'library_metadata_persistence.dart';
import 'library_query_compiler.dart';
import 'library_query_service.dart';
import 'library_schema_migration.dart';
import 'library_scan_backend.dart';
import 'library_scan_service.dart';
import 'library_repository_context.dart';
import 'library_store_access.dart';
import 'library_store_coordinator_service.dart';
import 'library_store_command_service.dart';
import 'library_tag_maintenance.dart';
import 'library_tag_persistence.dart';
import 'library_video_persistence.dart';
import 'video_identity_index.dart';
import '../resources/resource_scheduler.dart';

// ignore_for_file: slash_for_doc_comments, annotate_overrides

class LibraryStore
    implements
        LibraryRepository,
        LibraryQueryCandidateRepository,
        TagRepository,
        CacheRepository,
        VisualSignatureCacheRepository,
        PlaybackRepository,
        LibraryStoreAccess {
  LibraryStore._(
    this._file,
    LibraryRepositoryContext context,
    this._scanBackend,
    LibraryDataBackupService backupService,
    this._resourceScheduler,
  )   : _context = context,
        dataBackupService = backupService,
        _queryService = LibraryStoreQueryService(
          context: context,
          dataBackupService: backupService,
        ) {
    _coordinator = LibraryStoreCoordinatorService(
      repository: this,
      context: context,
      resourceScheduler: _resourceScheduler,
    );
    _commandService = LibraryStoreCommandService(repository: this);
  }

  final File _file;
  final LibraryRepositoryContext _context;
  /** 查询逻辑 owner；不复制 [LibraryRepositoryContext] 的任何索引或连接。 */
  final LibraryStoreQueryService _queryService;
  Database get _db => _context.database;
  List<String> get roots => _context.roots;
  /** 当前受 root 管理并参与筛选、标签计数和播放队列的视频。 */
  VideoIdentityIndex get videos => _context.videos;
  /** 已解除管理但保留稳定身份、标签、收藏和播放数据的视频。 */
  VideoIdentityIndex get detachedVideos => _context.detachedVideos;
  List<String> get favoriteTags => _context.favoriteTags;
  List<TagGroup> get tagGroups => _context.tagGroups;
  Map<String, TagItem> get tagsById => _context.tagsById;
  Map<String, Set<String>> get videoTagIdsByPathKey =>
      _context.videoTagIdsByPathKey;
  /** stable videoId 到 tagId 的主关系索引；path map 仅用于兼容消费者。 */
  Map<String, Set<String>> get videoTagIdsByVideoId =>
      _context.videoTagIdsByVideoId;
  LibraryQueryProfile get queryProfile => _context.queryProfile;

  /** 供诊断/压测查看当前关键词候选是否会进入 FTS5；最终语义仍在 Dart 校验。 */
  LibraryQueryPlan queryPlanFor(FilterQuery query) =>
      const LibraryQueryCompiler().compile(query, queryProfile);

  /**
   * 返回可交给 Dart FilterQuery 复核的候选视频。
   *
   * 该入口只做 profile 选择的候选缩小；调用方不得把候选集直接当最终结果，必须继续
   * 运行 [FilterQuery.matches]，以保留 folder 层级、alias、AND/OR/NOT 等完整语义。
   */
  @override
  Future<List<VideoItem>?> queryCandidatesFor(FilterQuery query) =>
      _queryService.queryCandidatesFor(query);

  /** 组合根可直接注入的真实查询 owner；命令仍共享当前 Store/Context。 */
  LibraryQueryRepository get queryRepository => _queryService;

  @override
  int get dataRevision => _queryService.dataRevision;

  /** stable videoId 主索引；pathKey 视图通过 [videos] 保持向后兼容。 */
  Map<String, VideoItem> get videosById => videos.byVideoId;

  /** detached 视频的 stable videoId 主索引。 */
  Map<String, VideoItem> get detachedVideosById => detachedVideos.byVideoId;

  /** 只读文件系统扫描边界；不拥有 SQLite 连接。 */
  final LibraryScanBackend _scanBackend;

  /** 组合根共享的扫描/探测/缓存/备份资源预算。 */
  final ResourceScheduler? _resourceScheduler;

  /** 独立视频依赖备份服务；主库仍是唯一业务写入源。 */
  final LibraryDataBackupService dataBackupService;

  /** root/扫描/relink 的协调 owner；Store 只暴露兼容端口。 */
  late final LibraryStoreCoordinatorService _coordinator;
  /** 标签、收藏和 root 元数据命令 owner；不复制 Store 状态。 */
  late final LibraryStoreCommandService _commandService;

  @override
  LibraryRepositoryContext get repositoryContext => _context;
  @override
  Database get database => _context.database;
  @override
  LibraryScanBackend get scanBackend => _scanBackend;
  @override
  int get scanGeneration => _coordinator.scanGeneration;

  @override
  DataBackupStatus get dataBackupStatus => dataBackupService.status;

  @override
  Stream<DataBackupStatus> get dataBackupStatusStream =>
      dataBackupService.statusStream;

  LibraryTagPersistence get _tagPersistence => _context.tagPersistence;

  LibraryVideoPersistence get _videoPersistence => _context.videoPersistence;

  LibraryMetadataPersistence get _metadataPersistence =>
      _context.metadataPersistence;

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
        videoTagIdsByVideoId: videoTagIdsByVideoId,
      );

  Iterable<TagItem> get allTagItems => tagsById.values;

  Map<String, int> resultCounts(FilterQuery query) {
    return _queryService.resultCounts(query);
  }

  Future<Map<String, TagUsageSummary>> tagUsageSummaries() =>
      _queryService.tagUsageSummaries();

  @override
  Future<void> addFavoriteTag(String tag) => _commandService.addFavoriteTag(tag);

  @override
  Future<void> removeFavoriteTag(String tag) =>
      _commandService.removeFavoriteTag(tag);

  @override
  Future<void> replaceRoot(String oldRoot, String newRoot) =>
      _commandService.replaceRoot(oldRoot, newRoot);

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
    _context.markDataChanged();
    await dataBackupService.enqueueVideo(video.videoId);
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
    _context.markDataChanged();
    await dataBackupService.enqueueVideo(videoId);
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
  Future<VideoVisualSignatureCacheEntry?> loadVisualSignature(
    String videoId,
  ) async =>
      (await loadVisualSignatures(<String>[videoId]))[videoId];

  @override
  Future<Map<String, VideoVisualSignatureCacheEntry>> loadVisualSignatures(
    Iterable<String> videoIds,
  ) async {
    final ids = videoIds.toSet().where((id) => id.isNotEmpty).toList();
    final result = <String, VideoVisualSignatureCacheEntry>{};
    const prefix = 'cache.visual_signature.';
    // SQLite 的 IN 参数有上限，按 400 条分块仍只需少量查询即可预热大候选集。
    for (var offset = 0; offset < ids.length; offset += 400) {
      final chunk = ids.skip(offset).take(400).toList(growable: false);
      final rows = await _db.query(
        'metadata',
        columns: const ['key', 'value'],
        where: 'key IN (${List<String>.filled(chunk.length, '?').join(', ')})',
        whereArgs: <Object?>[
          for (final id in chunk) '$prefix$id',
        ],
      );
      for (final row in rows) {
        final key = row['key'] as String?;
        if (key == null || !key.startsWith(prefix)) {
          continue;
        }
        final videoId = key.substring(prefix.length);
        try {
          final entry = VideoVisualSignatureCacheEntry.fromJson(
            videoId,
            jsonDecode(row['value']! as String),
          );
          if (entry != null) {
            result[videoId] = entry;
          }
        } on Object {
          // 单条派生缓存损坏只触发对应视频重算，不阻塞整批预热。
        }
      }
    }
    return result;
  }

  @override
  Future<void> saveVisualSignature(
    VideoVisualSignatureCacheEntry entry,
  ) async {
    if (entry.algorithm != videoVisualSignatureAlgorithm ||
        entry.hashes.length < 3) {
      return;
    }
    // 事务内再次确认 stable videoId 仍存在，防止删除与晚到的后台签名写入交叉时
    // 重新制造孤立 metadata；删除先提交时这里自然跳过，删除后提交则由删除批次清理。
    await _db.transaction((transaction) async {
      final videos = await transaction.query(
        'videos',
        columns: const ['video_id'],
        where: 'video_id = ?',
        whereArgs: [entry.videoId],
        limit: 1,
      );
      if (videos.isEmpty) {
        return;
      }
      await transaction.insert(
        'metadata',
        {
          'key': 'cache.visual_signature.${entry.videoId}',
          'value': jsonEncode(entry.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /**
   * 将视频级缓存诊断状态排入主库删除批次。
   *
   * 这些状态和视觉签名只服务诊断/派生缓存，不应在视频行删除后继续以 stable videoId
   * 残留；与标签关联、视频行同批提交，避免事务中断时出现半套依赖。
   */
  void _deleteCacheStatusesInBatch(Batch batch, String videoId) {
    batch.delete(
      'metadata',
      where: 'key IN (?, ?, ?)',
      whereArgs: <Object?>[
        'cache.thumbnail.$videoId',
        'cache.media_details.$videoId',
        'cache.visual_signature.$videoId',
      ],
    );
  }

  /** 读取视频的 manual 关系，合并时只允许复制来源明确的用户标签。 */
  Future<List<({TagItem tag, bool locked})>> _manualTagLinksForVideo(
    String videoId,
  ) async {
    final rows = await _db.query(
      'video_tags',
      columns: const <String>['tag_id', 'locked'],
      where: 'video_id = ? AND source = ?',
      whereArgs: <Object?>[videoId, TagSource.manual.name],
      orderBy: 'tag_id ASC',
    );
    final links = <({TagItem tag, bool locked})>[];
    for (final row in rows) {
      final tagId = row['tag_id'] as String?;
      final tag = tagId == null ? null : tagsById[tagId];
      if (tag == null || tag.source != TagSource.manual) {
        throw StateError('源视频存在无法解析的 manual 标签关系');
      }
      links.add(
        (
          tag: tag,
          locked: (row['locked'] as int? ?? 0) == 1,
        ),
      );
    }
    return links;
  }

  /** 在同一事务中写入目标视频新增的 manual 标签关系。 */
  void _attachManualTagInBatch(
    Batch batch,
    VideoItem target,
    ({TagItem tag, bool locked}) link,
  ) {
    final now = DateTime.now().toIso8601String();
    batch.insert(
      'video_tags',
      <String, Object?>{
        'video_path': target.path,
        'video_id': target.videoId,
        'tag_id': link.tag.id,
        'source': TagSource.manual.name,
        'locked': link.locked ? 1 : 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
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
    await dataBackupService.enqueueVideo(videoId);
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
    bool dataBackupEnabled = false,
    ResourceScheduler? resourceScheduler,
  }) async {
    final legacyFile = await databaseProvider.legacyLibraryFile();
    final db = diagnostics == null
        ? await _openDatabase(databaseProvider)
        : await diagnostics.measureAsync(
            'sqlite.open_and_maintenance',
            () => _openDatabase(databaseProvider),
          );
    final backupDb = await databaseProvider.openDataBackupDatabase(
      version: 1,
      createSchema: (_) async {},
      maintainSchema: (_) async {},
    );
    final dataBackupService = await LibraryDataBackupService.create(
      sourceDatabase: db,
      backupDatabase: backupDb,
      enabled: dataBackupEnabled,
      resourceScheduler: resourceScheduler,
    );
    try {
      final store = await _loadFromDatabase(
        legacyFile,
        db,
        diagnostics: diagnostics,
        scanBackend: scanBackend,
        dataBackupService: dataBackupService,
        resourceScheduler: resourceScheduler,
      );
      if (store.videos.isEmpty &&
          store.detachedVideos.isEmpty &&
          await legacyFile.exists()) {
        if (diagnostics == null) {
          await store._importLegacyJson();
        } else {
          await diagnostics.measureAsync(
            'legacy.import',
            store._importLegacyJson,
          );
        }
      }
      await store._promoteLegacyManualTagsToRoot();
      await store.ensureTagIndexCoverage(diagnostics: diagnostics);
      await store.dataBackupService.startOrResume();
      return store;
    } catch (_) {
      // 任一 hydration/迁移阶段失败都必须同时释放主库与独立备份库句柄。
      await dataBackupService.close();
      await db.close();
      rethrow;
    }
  }

  static Future<Database> _openDatabase(DatabaseProvider provider) {
    return provider.openLibraryDatabase(
      version: 2,
      createSchema: _createSchema,
      upgradeSchema: (db, oldVersion, newVersion) async {
        if (oldVersion < 2 && newVersion >= 2) {
          await migrateToStableIdentitySchema(db);
        }
      },
      maintainSchema: _maintainSchema,
    );
  }

  /**
   * 启动时再次检查表形状，覆盖旧版本曾把数据库 user_version 留在新值但没有完成
   * 主键迁移的异常中断场景；迁移本身幂等，已完成 schema 只做索引维护。
   */
  static Future<void> _maintainSchema(Database db) async {
    await migrateToStableIdentitySchema(db);
    await _createSchema(db);
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    // FTS5 是可选派生索引；不支持的 SQLite 版本继续使用内存查询。
    await LibrarySearchIndex().ensureSchema(db);
    await db.execute(stableVideosTableSql('videos'));
    await _ensureVideoColumns(db);
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_videos_folder ON videos(folder)');
    await db.execute(
      Platform.isWindows
          ? 'CREATE UNIQUE INDEX IF NOT EXISTS idx_videos_path ON videos(path COLLATE NOCASE)'
          : 'CREATE UNIQUE INDEX IF NOT EXISTS idx_videos_path ON videos(path)',
    );
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
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_videos_detached ON videos(is_detached)');
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
    await db.execute(stableVideoTagsTableSql('video_tags'));
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
    await addColumn('is_detached', 'INTEGER NOT NULL DEFAULT 0');
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

  /** 将视频标签 JOIN 结果 hydration 为 stable ID 主索引和 path 兼容索引。 */
  static ({
    Map<String, Set<String>> byPath,
    Map<String, Set<String>> byVideoId,
  }) _videoTagIdsFromRows(List<Map<String, Object?>> rows) {
    final linksByPath = <String, Set<String>>{};
    final linksByVideoId = <String, Set<String>>{};
    for (final row in rows) {
      final path = row['path'] as String;
      final videoId = row['video_id'] as String;
      final tagId = row['tag_id'] as String;
      (linksByPath[TagRules.pathKey(path)] ??= <String>{}).add(tagId);
      (linksByVideoId[videoId] ??= <String>{}).add(tagId);
    }
    return (byPath: linksByPath, byVideoId: linksByVideoId);
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
    required LibraryDataBackupService dataBackupService,
    ResourceScheduler? resourceScheduler,
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
    final partitionedVideos = diagnostics == null
        ? _partitionVideosFromRows(videoRows)
        : diagnostics.measureSync(
            'dart.video_object_build',
            () => _partitionVideosFromRows(videoRows),
            itemCount: (items) => items.active.length + items.detached.length,
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
    final videoTagIndexes = diagnostics == null
        ? _videoTagIdsFromRows(relationRows)
        : diagnostics.measureSync(
            'dart.video_tag_relation_hydration',
            () => _videoTagIdsFromRows(relationRows),
            itemCount: (links) => links.byPath.length + links.byVideoId.length,
          );
    final context = LibraryRepositoryContext(
      database: db,
      roots: metadata.roots,
      videos: partitionedVideos.active,
      detachedVideos: partitionedVideos.detached,
      favoriteTags: metadata.favoriteTags,
      tagGroups: tagGroups,
      tagsById: tagsById,
      videoTagIdsByPathKey: videoTagIndexes.byPath,
      videoTagIdsByVideoId: videoTagIndexes.byVideoId,
      fts5Available: await LibrarySearchIndex().ensureSchema(db),
    );
    return LibraryStore._(
      legacyFile,
      context,
      scanBackend,
      dataBackupService,
      resourceScheduler,
    );
  }

  /**
   * 将视频表行按 root 管理状态拆为 active 与 detached 两个路径索引。
   *
   * detached 行只用于重新添加/重新关联时恢复稳定身份，不能进入常规筛选和播放队列。
   */
  static ({
    VideoIdentityIndex active,
    VideoIdentityIndex detached,
  }) _partitionVideosFromRows(List<Map<String, Object?>> rows) {
    final active = VideoIdentityIndex();
    final detached = VideoIdentityIndex();
    for (final row in rows) {
      final item = LibraryVideoPersistence.videoFromRow(row);
      final target = (row['is_detached'] as int? ?? 0) == 1 ? detached : active;
      target.put(item);
    }
    return (active: active, detached: detached);
  }

  /** 一次性读取稳定身份对应的视频标签关系，避免逐视频 N+1 查询。 */
  static Future<List<Map<String, Object?>>> _queryVideoTagRows(Database db) {
    return db.rawQuery('''
      SELECT vt.tag_id, vt.video_id, v.path
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

  /**
   * 重新同步 active 视频的 folder 来源索引。
   *
   * 手动来源和 detached 视频关系属于用户数据，不能用全表清空方式“重建”。
   */
  Future<void> rebuildTagIndex() async {
    final batch = _db.batch();
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
    Iterable<String>? manualTags,
  }) =>
      _commandService.replaceManualTags(
        item,
        parentTag: parentTag,
        manualTags: manualTags,
      );

  Future<void> saveTag(TagItem tag) => _commandService.saveTag(tag);

  Future<TagItem> createManualTag({
    required String name,
    required String groupId,
    String? displayName,
  }) =>
      _commandService.createManualTag(
        name: name,
        groupId: groupId,
        displayName: displayName,
      );

  /** 启动时修复旧版二级 manual 关系，并将受影响视频排入既有备份队列。 */
  Future<void> _promoteLegacyManualTagsToRoot() async {
    await _commandService.promoteLegacyManualTagsToRoot();
  }

  Future<void> updateTagDetails(
    TagItem tag, {
    String? displayName,
    Iterable<String>? aliases,
    String? groupId,
    bool? isHidden,
    bool? isFavorite,
    int? sortOrder,
  }) =>
      _commandService.updateTagDetails(
        tag,
        displayName: displayName,
        aliases: aliases,
        groupId: groupId,
        isHidden: isHidden,
        isFavorite: isFavorite,
        sortOrder: sortOrder,
      );

  Future<int> countTagReferences(TagItem tag) =>
      _queryService.countTagReferences(tag);

  Future<int> batchAddManualTag(TagItem tag, Iterable<VideoItem> items) =>
      _commandService.batchAddManualTag(tag, items);

  Future<int> batchRemoveManualTag(TagItem tag, Iterable<VideoItem> items) =>
      _commandService.batchRemoveManualTag(tag, items);

  Future<void> save() async {
    final batch = _db.batch();
    _metadataPersistence.saveInBatch(
      batch,
      roots: roots,
      favoriteTags: favoriteTags,
    );
    // detached 行属于用户数据归档，兼容保存 active 集合时不能被全表删除。
    batch.delete('videos', where: 'is_detached = 0');
    for (final item in videos.values) {
      _videoPersistence.insertInBatch(batch, item);
      _tagMaintenance.syncFolderTagsInBatch(batch, item);
    }
    await batch.commit(noResult: true);
    _context.markDataChanged();
  }

  Future<void> saveMetadata() => _commandService.saveMetadata();

  /**
   * 关闭当前媒体库数据库连接。
   *
   * 测试和 repository 拆分需要显式释放 SQLite 文件句柄，避免临时目录清理失败。
   */
  Future<void> close() async {
    await _coordinator.cancelActiveScan();
    await dataBackupService.close();
    await _db.close();
  }

  Future<void> upsertVideo(VideoItem item) async {
    final pathKey = TagRules.pathKey(item.path);
    if (!videos.containsKey(pathKey) && detachedVideos.containsKey(pathKey)) {
      // root 移除前发出的异步探测/缓存回调不能把 detached 记录静默恢复为 active。
      return;
    }
    videos[pathKey] = item;
    await _videoPersistence.upsert(item);
    _context.markDataChanged();
    await dataBackupService.enqueueVideo(item.videoId);
  }

  /**
   * 原子提交正常视频的同目录文件重命名，并保留稳定身份和全部用户数据。
   *
   * 物理文件操作由 [FileSystemAdapter] 在页面协调层先完成；这里仅拥有 SQLite 与内存
   * 索引迁移。只有 batch 成功后才修改传入对象和 path 索引，避免提交失败留下半更新状态。
   */
  Future<void> renameVideoPath(VideoItem item, String newPath) async {
    if (item.isMissing) {
      throw StateError('缺失文件需要先重新关联，不能直接重命名');
    }
    final oldPath = item.path;
    final normalizedPath = p.normalize(newPath);
    if (!p.equals(p.dirname(oldPath), p.dirname(normalizedPath))) {
      throw StateError('播放器只允许修改文件名，不能移动文件目录');
    }
    final oldKey = TagRules.pathKey(oldPath);
    final current = videos[oldKey];
    if (current == null || current.videoId != item.videoId) {
      throw StateError('媒体库中的原文件记录已变化，请返回后重试');
    }
    final newKey = TagRules.pathKey(normalizedPath);
    final occupied = videos[newKey];
    if (occupied != null && occupied.videoId != item.videoId) {
      throw StateError('同名文件已经存在于媒体库');
    }
    if (oldKey == newKey) {
      return;
    }

    final updated = VideoItem.fromJson(item.toJson())
      ..path = normalizedPath
      ..title = p.basenameWithoutExtension(normalizedPath)
      ..relativePath = item.rootPath == null || item.rootPath!.isEmpty
          ? item.relativePath
          : p.relative(normalizedPath, from: item.rootPath!);
    final batch = _db.batch();
    _videoPersistence.relinkInBatch(batch, oldPath, updated);
    _tagPersistence.relinkVideoPathInBatch(batch, updated);
    await batch.commit(noResult: true);
    _context.markDataChanged();

    final linkedTagIds = videoTagIdsByPathKey.remove(oldKey);
    videos.remove(oldKey);
    item
      ..path = updated.path
      ..title = updated.title
      ..relativePath = updated.relativePath;
    videos[newKey] = item;
    if (linkedTagIds != null) {
      videoTagIdsByPathKey[newKey] = linkedTagIds;
    }
  }

  /**
   * 合并写入后台媒体详情更新，避免大目录导入时为每个文件单独提交 SQLite。
   *
   * 媒体详情只更新现有视频行；标签关系仍由扫描或标签维护流程拥有，不能在这里重建。
   */
  Future<void> upsertVideos(Iterable<VideoItem> items) async {
    final updates = <VideoItem>[
      for (final item in items)
        if (videos.containsKey(TagRules.pathKey(item.path)) ||
            !detachedVideos.containsKey(TagRules.pathKey(item.path)))
          item,
    ];
    if (updates.isEmpty) {
      return;
    }
    for (final item in updates) {
      final pathKey = TagRules.pathKey(item.path);
      videos[pathKey] = item;
    }
    await _videoPersistence.upsertAll(updates);
    _context.markDataChanged();
  }

  /**
   * 批量写入继续观看等用户播放状态，并同步更新独立备份。
   *
   * 媒体详情批量写入不包含在这里；只有用户依赖字段的显式操作才应进入备份队列。
   */
  @override
  Future<void> upsertPlaybackStates(Iterable<VideoItem> items) async {
    final updates = <VideoItem>[
      for (final item in items)
        // 继续观看只消费 active 视频；删除或解除管理后到达的异步清理/撤销不能复活数据库行。
        if (videos.containsKey(TagRules.pathKey(item.path))) item,
    ];
    if (updates.isEmpty) {
      return;
    }
    for (final item in updates) {
      videos[TagRules.pathKey(item.path)] = item;
    }
    await _videoPersistence.upsertAll(updates);
    _context.markDataChanged();
    await dataBackupService.enqueueVideos(
      updates.map((item) => item.videoId),
    );
  }

  /**
   * 在单个 SQLite 事务中删除视频记录及其全部标签关系。
   *
   * 收藏、播放进度、媒体详情和稳定身份字段都存放在 videos 行中；删除该行后不会留下
   * 孤立用户状态。磁盘文件与缩略图缓存由 Application 层按用户选择分别处理。
   */
  Future<VideoItem?> deleteVideo(String path) => _deleteVideo(path);

  @override
  Future<VideoItem?> deleteVideoById(String videoId) {
    final item = videos.byId(videoId) ?? detachedVideos.byId(videoId);
    if (item == null) {
      return Future<VideoItem?>.value(null);
    }
    return _deleteVideo(item.path, expectedVideoId: videoId);
  }

  @override
  Future<void> renameVideoPathById(String videoId, String newPath) {
    final item = videos.byId(videoId);
    if (item == null) {
      throw StateError('找不到仍由媒体库管理的 stable videoId');
    }
    return renameVideoPath(item, newPath);
  }

  @override
  Future<VideoItem?> deleteVideoAndMergeUserData({
    required VideoItem source,
    required VideoItem target,
  }) =>
      _deleteVideo(source.path, mergeInto: target);

  @override
  Future<VideoItem?> deleteVideoAndMergeUserDataById({
    required String sourceVideoId,
    required String targetVideoId,
  }) {
    final source =
        videos.byId(sourceVideoId) ?? detachedVideos.byId(sourceVideoId);
    final target =
        videos.byId(targetVideoId) ?? detachedVideos.byId(targetVideoId);
    if (source == null || target == null) {
      throw StateError('合并删除需要两个仍存在的 stable videoId');
    }
    return _deleteVideo(
      source.path,
      mergeInto: target,
      expectedVideoId: sourceVideoId,
    );
  }

  Future<VideoItem?> _deleteVideo(
    String path, {
    VideoItem? mergeInto,
    String? expectedVideoId,
  }) async {
    final pathKey = TagRules.pathKey(path);
    final item = videos[pathKey] ?? detachedVideos[pathKey];
    if (expectedVideoId != null &&
        (item == null || item.videoId != expectedVideoId)) {
      throw StateError('视频身份已变化，请重新执行该命令');
    }
    VideoItem? targetItem;
    VideoItem? mergedTarget;
    List<({TagItem tag, bool locked})> tagsToMerge = const [];
    if (mergeInto != null) {
      if (item == null || item.videoId == mergeInto.videoId) {
        throw StateError('合并删除需要两个不同且仍存在的视频');
      }
      targetItem = <VideoItem>[...videos.values, ...detachedVideos.values]
          .where((candidate) => candidate.videoId == mergeInto.videoId)
          .firstOrNull;
      if (targetItem == null) {
        throw StateError('合并目标视频已不在媒体库中');
      }
      final sourceLinks = await _manualTagLinksForVideo(item.videoId);
      final targetLinks = await _manualTagLinksForVideo(targetItem.videoId);
      final targetTagIds = targetLinks.map((link) => link.tag.id).toSet();
      final mergedNames = targetLinks.map((link) => link.tag.name).toList();
      final selectedLinks = <({TagItem tag, bool locked})>[];
      for (final link in sourceLinks) {
        if (targetTagIds.contains(link.tag.id) ||
            mergedNames.any(
              (name) => TagRules.sameTag(name, link.tag.name),
            )) {
          continue;
        }
        selectedLinks.add(link);
        mergedNames.add(link.tag.name);
      }
      tagsToMerge = List<({TagItem tag, bool locked})>.unmodifiable(
        selectedLinks,
      );
      final mergedFavorite = targetItem.isFavorite || item.isFavorite;
      if (mergedFavorite != targetItem.isFavorite || tagsToMerge.isNotEmpty) {
        mergedTarget = VideoItem.fromJson(targetItem.toJson())
          ..isFavorite = mergedFavorite;
        for (final link in tagsToMerge) {
          mergedTarget.tags.add(link.tag.name);
        }
      }
    }
    if (item != null) {
      // 等待当前小批次结束，避免全量 worker 在主库删除提交前把已清快照重新写回。
      await dataBackupService.pauseForPlayback();
    }
    try {
      if (item != null) {
        // 显式删除不等同 root 解除管理；独立快照必须和主库记录一起退出。
        await dataBackupService.deleteSnapshot(item.videoId);
      }
      final batch = _db.batch();
      if (item != null) {
        if (mergedTarget != null && targetItem != null) {
          _videoPersistence.insertInBatch(batch, mergedTarget);
          for (final link in tagsToMerge) {
            _attachManualTagInBatch(batch, mergedTarget, link);
          }
        }
        _tagPersistence.deleteVideoLinksInBatch(
          batch,
          item,
          updateMemoryIndex: false,
        );
        _deleteCacheStatusesInBatch(batch, item.videoId);
      }
      if (expectedVideoId != null) {
        _videoPersistence.deleteByIdInBatch(batch, expectedVideoId);
      } else {
        _videoPersistence.deleteInBatch(batch, path);
      }
      await batch.commit(noResult: true);
      _context.markDataChanged();
      if (mergedTarget != null && targetItem != null) {
        targetItem
          ..isFavorite = mergedTarget.isFavorite
          ..tags.clear()
          ..tags.addAll(mergedTarget.tags);
        final targetTagIds =
            (videoTagIdsByPathKey[TagRules.pathKey(targetItem.path)] ??=
                <String>{});
        targetTagIds.addAll(tagsToMerge.map((link) => link.tag.id));
      }
      videos.remove(pathKey);
      detachedVideos.remove(pathKey);
      videoTagIdsByPathKey.remove(pathKey);
      if (item != null) {
        videoTagIdsByVideoId.remove(item.videoId);
      }
      if (targetItem != null && mergedTarget != null) {
        await dataBackupService.enqueueVideoBestEffort(targetItem.videoId);
      }
      return item;
    } catch (_) {
      if (item != null) {
        // 主库删除失败时重新排入快照，不能因为预清理备份而制造新的数据缺口。
        await dataBackupService.enqueueVideo(item.videoId);
      }
      rethrow;
    } finally {
      if (item != null) {
        dataBackupService.resumeAfterPlayback();
      }
    }
  }

  /**
   * 从数据库批量移除路径失效、已确认 missing 或当前不可读的视频。
   *
   * 路径不存在即属于用户授权的清理范围，不要求扫描先写入 missing；该入口不调用磁盘删除边界。
   */
  Future<int> removeMissingOrUnreadableVideos() async {
    await cancelActiveScan();
    final snapshot = List<VideoItem>.of(videos.values);
    final removable = <VideoItem>[];
    const probeBatchSize = 8;
    for (var offset = 0; offset < snapshot.length; offset += probeBatchSize) {
      final end = math.min(offset + probeBatchSize, snapshot.length);
      final candidates = snapshot.sublist(offset, end);
      final unavailable =
          await Future.wait(candidates.map(_isMissingOrUnreadableVideo));
      for (var index = 0; index < candidates.length; index += 1) {
        if (unavailable[index]) {
          removable.add(candidates[index]);
        }
      }
      // 大媒体库探测分批让出事件循环，避免设置开关冻结界面。
      await Future<void>.delayed(Duration.zero);
    }
    if (removable.isEmpty) {
      return 0;
    }
    await dataBackupService.pauseForPlayback();
    try {
      await dataBackupService
          .deleteSnapshots(removable.map((item) => item.videoId));
      final batch = _db.batch();
      for (final item in removable) {
        _tagPersistence.deleteVideoLinksInBatch(
          batch,
          item,
          updateMemoryIndex: false,
        );
        _videoPersistence.deleteInBatch(batch, item.path);
      }
      await batch.commit(noResult: true);
      for (final item in removable) {
        final pathKey = TagRules.pathKey(item.path);
        videos.remove(pathKey);
        detachedVideos.remove(pathKey);
        videoTagIdsByPathKey.remove(pathKey);
        videoTagIdsByVideoId.remove(item.videoId);
      }
      return removable.length;
    } catch (_) {
      await dataBackupService
          .enqueueVideos(removable.map((item) => item.videoId));
      rethrow;
    } finally {
      dataBackupService.resumeAfterPlayback();
    }
  }

  /** 路径不存在、不是普通文件或无法打开句柄时均视为数据库无效记录。 */
  Future<bool> _isMissingOrUnreadableVideo(VideoItem item) async {
    if (item.isMissing) {
      return true;
    }
    try {
      final type = await FileSystemEntity.type(item.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        return true;
      }
      if (type != FileSystemEntityType.file) {
        return true;
      }
      final handle = await File(item.path).open();
      await handle.close();
      return false;
    } catch (_) {
      return true;
    }
  }

  Future<int> addRootAndScan(String rootPath) async {
    return _coordinator.addRootAndScan(rootPath);
  }

  /** 添加 root 并返回可供 UI 与探测队列差量消费的事务提交结果。 */
  Future<LibraryScanCommitResult> addRootAndScanWithChanges(String rootPath,
          {LibraryScanProgressCallback? onProgress}) =>
      _coordinator.addRootAndScanWithChanges(
        rootPath,
        onProgress: onProgress,
      );

  /**
   * 批量注册 root，并在 metadata 只落盘一次后执行一轮扫描。
   *
   * 文件选择和拖放可能同时命中多个父目录；先去重再扫描可避免每新增一个目录就重复遍历
   * 已有大媒体库。SQLite 写入、stable identity 与 folder 标签仍由原扫描协调器统一处理。
   */
  @override
  Future<LibraryScanCommitResult> addRootsAndScanWithChanges(
      Iterable<String> rootPaths,
      {LibraryScanProgressCallback? onProgress}) =>
      _coordinator.addRootsAndScanWithChanges(
        rootPaths,
        onProgress: onProgress,
      );

  /**
   * 从媒体库根目录列表移除一个目录。
   *
   * root 配置与仅受该 root 管理视频的 detached 状态在同一事务中提交。视频行、标签
   * 关系、收藏、播放记录和媒体缓存字段全部保留；重叠 root 仍覆盖的视频继续 active，
   * 磁盘文件始终不由该操作删除。
   */
  Future<List<VideoItem>> removeRoot(String rootPath) async {
    return _coordinator.removeRoot(rootPath);
  }

  Future<int> scan() async {
    return _coordinator.scan();
  }

  /**
   * 取消旧代次并执行只读后端扫描；只有当前代次可进入 Application 事务提交。
   */
  Future<LibraryScanCommitResult> scanWithChanges({
    LibraryScanProgressCallback? onProgress,
  }) =>
      _coordinator.scanWithChanges(onProgress: onProgress);

  @override
  Future<void> setScanPaused(bool paused) => _coordinator.setScanPaused(paused);

  /**
   * 取消当前只读扫描，并推进代次阻止已经离开后端的旧结果进入事务提交。
   *
   * 先登记取消、再解除暂停，保证正在等待播放让盘的扫描也能及时观察取消信号。
   */
  @override
  Future<void> cancelActiveScan() => _coordinator.cancelActiveScan();

  @override
  Future<void> setDataBackupEnabled(bool enabled) =>
      dataBackupService.setEnabled(enabled);

  @override
  Future<void> runDataBackupNow() => dataBackupService.runNow();

  @override
  Future<DataBackupIntegrityReport> checkDataBackupIntegrity() =>
      dataBackupService.checkIntegrity();

  @override
  Future<Uint8List> createDataBackupExport() =>
      dataBackupService.createPortableExport();

  @override
  Future<void> pauseDataBackupForPlayback() =>
      dataBackupService.pauseForPlayback();

  @override
  void resumeDataBackupAfterPlayback() =>
      dataBackupService.resumeAfterPlayback();

  /**
   * 通过 fingerprint 校验把一个 missing 条目关联到用户选择的新文件。
   *
   * 稳定 videoId 以及 manual 标签、收藏、播放记录和进度保持不变；folder 标签随新路径更新。
   */
  Future<void> relinkMissingVideo(VideoItem item, String newPath) =>
      _coordinator.relinkMissingVideo(item, newPath);

  @override
  Future<void> relinkMissingVideoById(String videoId, String newPath) {
    final item = videos.byId(videoId) ?? detachedVideos.byId(videoId);
    if (item == null) {
      throw StateError('找不到待重新关联的 stable videoId');
    }
    return relinkMissingVideo(item, newPath);
  }

  /** 在单个 SQLite batch 中提交多条 Relink，并返回重新校验或事务失败的 videoId。 */
  Future<Set<String>> relinkMissingVideosInBatch(
    Map<VideoItem, String> targets,
  ) =>
      _coordinator.relinkMissingVideosInBatch(targets);

  static Future<String?> mediaFingerprintFor(String path) async {
    return LibraryScanService.mediaFingerprintFor(path);
  }

  Future<int> countUntrackedVideos() => _queryService.countUntrackedVideos();

  Set<String> get allTags => _queryService.allTags;

  Set<String> childTagsFor(String parentTag) =>
      _queryService.childTagsFor(parentTag);
}
