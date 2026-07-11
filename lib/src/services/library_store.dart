part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

class LibraryStore {
  LibraryStore._(
    this._file,
    this._db,
    this.roots,
    this.videos,
    this.favoriteTags,
    this.tagGroups,
    this.tagsById,
    this.videoTagIdsByPathKey,
  );

  final File _file;
  final Database _db;
  final List<String> roots;
  final Map<String, VideoItem> videos;
  final List<String> favoriteTags;
  final List<TagGroup> tagGroups;
  final Map<String, TagItem> tagsById;
  final Map<String, Set<String>> videoTagIdsByPathKey;

  LibraryTagPersistence get _tagPersistence =>
      LibraryTagPersistence(_db, tagsById, videoTagIdsByPathKey);

  LibraryVideoPersistence get _videoPersistence => LibraryVideoPersistence(_db);

  LibraryMetadataPersistence get _metadataPersistence =>
      LibraryMetadataPersistence(_db);

  LibraryTagMaintenance get _tagMaintenance => LibraryTagMaintenance(this);

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

  static Future<LibraryStore> load() async {
    final legacyFile = await AppPaths.legacyLibraryFile();
    final db = await _openDatabase(await AppPaths.libraryDatabaseFile());
    final store = await _loadFromDatabase(legacyFile, db);
    if (store.videos.isEmpty && await legacyFile.exists()) {
      await store._importLegacyJson();
    }
    await store.ensureTagIndexCoverage();
    return store;
  }

  static Future<Database> _openDatabase(File databaseFile) {
    return databaseFactory.openDatabase(
      databaseFile.path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async => _createSchema(db),
        onOpen: (db) async {
          await _createSchema(db);
          await db.execute('PRAGMA foreign_keys=ON');
          await db.execute('PRAGMA journal_mode=WAL');
          await db.execute('PRAGMA synchronous=NORMAL');
          await db.execute('PRAGMA temp_store=MEMORY');
          await db.execute('PRAGMA cache_size=-20000');
        },
      ),
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
    await _backfillStableVideoIds(db);
    // 旧版本可能残留同一身份的重复 path 兼容行；建唯一索引前只清理冗余关系。
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

  /** 幂等回填旧视频身份，并把既有标签关系绑定到对应 `videoId`。 */
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
      final newId = VideoItem._newVideoId();
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

  static Future<List<TagGroup>> _loadTagGroups(Database db) async {
    final rows = await db.query('tag_groups',
        orderBy: 'sort_order ASC, display_name ASC');
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

  static Future<Map<String, TagItem>> _loadTagsById(Database db) async {
    final aliasesByTagId = <String, Set<String>>{};
    for (final row in await db.query('tag_aliases')) {
      final tagId = row['tag_id'] as String;
      final alias = TagRules.normalizeTag(row['alias'] as String? ?? '');
      if (alias.isNotEmpty) {
        (aliasesByTagId[tagId] ??= <String>{}).add(alias);
      }
    }
    final rows = await db.query('tags');
    final tags = <String, TagItem>{};
    for (final row in rows) {
      final id = row['id'] as String;
      tags[id] = _tagFromRow(row,
          extraAliases: aliasesByTagId[id] ?? const <String>{});
    }
    return tags;
  }

  static Future<Map<String, Set<String>>> _loadVideoTagIds(Database db) async {
    final links = <String, Set<String>>{};
    final rows = await db.rawQuery('''
      SELECT vt.tag_id, v.path
      FROM video_tags vt
      INNER JOIN videos v ON v.video_id = vt.video_id
    ''');
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
    final mergedAliases = _dedupeTags(<String>[...aliases, ...extraAliases]);
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
      File legacyFile, Database db) async {
    final metadata = await LibraryMetadataPersistence(db).load();
    final videos = <String, VideoItem>{};
    for (final row in await db.query('videos')) {
      final item = LibraryVideoPersistence.videoFromRow(row);
      videos[TagRules.pathKey(item.path)] = item;
    }
    final tagGroups = await _loadTagGroups(db);
    final tagsById = await _loadTagsById(db);
    final videoTagIdsByPathKey = await _loadVideoTagIds(db);
    return LibraryStore._(
      legacyFile,
      db,
      metadata.roots,
      videos,
      metadata.favoriteTags,
      tagGroups,
      tagsById,
      videoTagIdsByPathKey,
    );
  }

  Future<void> _importLegacyJson() async {
    try {
      final decoded =
          jsonDecode(await _file.readAsString()) as Map<String, Object?>;
      roots
        ..clear()
        ..addAll(_dedupeRoots(
            ((decoded['roots'] as List?) ?? const []).cast<String>()));
      favoriteTags
        ..clear()
        ..addAll(_dedupeTags(
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

  Future<void> ensureTagIndexCoverage() async {
    if (videos.isEmpty) {
      return;
    }
    final batch = _db.batch();
    var changed = false;
    for (final item in videos.values) {
      final tagIds = videoTagIdsByPathKey[TagRules.pathKey(item.path)];
      if (tagIds == null || tagIds.isEmpty) {
        _tagMaintenance.syncFolderTagsInBatch(batch, item);
        changed = true;
      }
    }
    if (changed) {
      await batch.commit(noResult: true);
    }
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
    final id = _tagIdFor(name: normalized, groupId: groupId);
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
        aliases: aliases == null ? tag.aliases : _dedupeTags(aliases),
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

  static String _tagIdFor({
    required String name,
    required String groupId,
    String? parentId,
  }) {
    final parent = parentId == null ? '' : ':${parentId.trim().toLowerCase()}';
    return '$groupId$parent:${name.trim().toLowerCase()}';
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
  Future<void> close() => _db.close();

  Future<void> upsertVideo(VideoItem item) async {
    videos[TagRules.pathKey(item.path)] = item;
    await _videoPersistence.upsert(item);
  }

  Future<void> deleteVideo(String path) async {
    final item = videos.remove(TagRules.pathKey(path));
    if (item != null) {
      await _tagPersistence.deleteVideoLinks(item);
    }
    await _videoPersistence.delete(path);
  }

  Future<int> addRootAndScan(String rootPath) async {
    final normalizedRoot = TagRules.normalizeRootPath(rootPath);
    if (normalizedRoot.isEmpty) {
      return 0;
    }
    final rootKey = TagRules.pathKey(normalizedRoot);
    if (!roots.any((root) => TagRules.pathKey(root) == rootKey)) {
      roots.add(normalizedRoot);
      await saveMetadata();
    }
    return scan();
  }

  /**
   *
   * 从媒体库根目录列表移除一个目录。
   *
   *
鍙洿鏂?
 root
   * 只更新 root 配置，不删除磁盘文件，也不立即清理已有视频记录。
   */
  Future<void> removeRoot(String rootPath) async {
    final rootKey = TagRules.pathKey(TagRules.normalizeRootPath(rootPath));
    roots.removeWhere((root) => TagRules.pathKey(root) == rootKey);
    await saveMetadata();
  }

  Future<int> scan() async {
    return LibraryScanCoordinator(this).scan();
  }

  /**
   * 通过 fingerprint 校验把一个 missing 条目关联到用户选择的新文件。
   *
   * 稳定 videoId 以及 manual 标签、收藏、播放记录和进度保持不变；folder 标签随新路径更新。
   */
  Future<void> relinkMissingVideo(VideoItem item, String newPath) {
    return LibraryScanCoordinator(this).relinkMissingVideo(item, newPath);
  }

  static Future<String?> mediaFingerprintFor(String path) async {
    return LibraryScanService.mediaFingerprintFor(path);
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    return a.length == b.length && a.containsAll(b);
  }

  static bool _childTagsEquals(
      Map<String, Set<String>> a, Map<String, Set<String>> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || !_setEquals(entry.value, other)) {
        return false;
      }
    }
    return true;
  }

  static List<String> _dedupeRoots(Iterable<String> rawRoots) {
    final seen = <String>{};
    final roots = <String>[];
    for (final raw in rawRoots) {
      final root = TagRules.normalizeRootPath(raw);
      if (root.isEmpty) {
        continue;
      }
      if (seen.add(TagRules.pathKey(root))) {
        roots.add(root);
      }
    }
    return roots;
  }

  static List<String> _dedupeTags(Iterable<String> rawTags) {
    final seen = <String>{};
    final tags = <String>[];
    for (final raw in rawTags) {
      final tag = TagRules.normalizeTag(raw);
      if (tag.isEmpty) {
        continue;
      }
      if (seen.add(tag.toLowerCase())) {
        tags.add(tag);
      }
    }
    return tags;
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
