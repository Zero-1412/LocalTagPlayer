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
      SELECT tag_id, source, COUNT(DISTINCT video_path) AS count
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
        last_played_at TEXT
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
        tag_id TEXT NOT NULL,
        source TEXT NOT NULL,
        locked INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (video_path, tag_id, source)
      )
    ''');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_tags_group ON tags(group_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tag_aliases_alias ON tag_aliases(alias)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_video_tags_video ON video_tags(video_path)');
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
  }

  static Future<void> _ensureDefaultTagGroups(Database db) async {
    final groups = const <Map<String, Object?>>[
      {
        'id': 'folder.primary',
        'name': 'folder.primary',
        'display_name': '一级文件夹',
        'sort_order': 10,
      },
      {
        'id': 'folder.child',
        'name': 'folder.child',
        'display_name': '二级文件夹',
        'sort_order': 20,
      },
      {
        'id': 'manual',
        'name': 'manual',
        'display_name': '手动标签',
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
    for (final row in await db.query('video_tags')) {
      final path = row['video_path'] as String;
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
    final metadata = <String, String>{};
    for (final row in await db.query('metadata')) {
      metadata[row['key'] as String] = row['value'] as String;
    }

    final roots = _dedupeRoots(
        ((jsonDecode(metadata['roots'] ?? '[]') as List?) ?? const [])
            .cast<String>());
    final favoriteTags = _dedupeTags(
        ((jsonDecode(metadata['favoriteTags'] ?? '[]') as List?) ?? const [])
            .cast<String>());
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
      roots,
      videos,
      favoriteTags,
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
      // 损坏的旧 JSON 不应阻止新的 SQLite 媒体库启动。
    }
  }

  Future<void> rebuildTagIndex() async {
    final batch = _db.batch();
    batch.delete('video_tags');
    videoTagIdsByPathKey.clear();
    for (final item in videos.values) {
      _syncFolderTagsInBatch(batch, item);
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
        _syncFolderTagsInBatch(batch, item);
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
    final batch = _db.batch();
    _syncManualTagsInBatch(batch, item, parentTag: parentTag);
    _videoPersistence.insertInBatch(batch, item);
    await batch.commit(noResult: true);
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
      throw StateError('同名标签已存在于该分组且来源不是 manual');
    }
    final tag = _tagFor(
      name: normalized,
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
    if (tag.source != TagSource.manual) {
      throw StateError('批量添加只支持 manual 标签');
    }
    final videosToUpdate = items.toList();
    if (videosToUpdate.isEmpty) {
      return 0;
    }
    final batch = _db.batch();
    for (final item in videosToUpdate) {
      _addManualTagToItem(item, tag);
      _videoPersistence.insertInBatch(batch, item);
      _tagPersistence.attachTagInBatch(
        batch,
        item.path,
        tag,
        source: TagSource.manual,
      );
    }
    await batch.commit(noResult: true);
    return videosToUpdate.length;
  }

  Future<int> batchRemoveManualTag(
      TagItem tag, Iterable<VideoItem> items) async {
    if (tag.source != TagSource.manual) {
      throw StateError('批量移除只支持 manual 标签');
    }
    final videosToUpdate = items.toList();
    if (videosToUpdate.isEmpty) {
      return 0;
    }
    final batch = _db.batch();
    var changed = 0;
    for (final item in videosToUpdate) {
      final hadManualLink =
          videoTagIdsByPathKey[TagRules.pathKey(item.path)]?.contains(tag.id) ??
              false;
      final changedCompat = _removeManualTagFromItem(item, tag);
      batch.delete(
        'video_tags',
        where: Platform.isWindows
            ? 'video_path = ? COLLATE NOCASE AND tag_id = ? AND source = ?'
            : 'video_path = ? AND tag_id = ? AND source = ?',
        whereArgs: [item.path, tag.id, TagSource.manual.name],
      );
      videoTagIdsByPathKey[TagRules.pathKey(item.path)]?.remove(tag.id);
      if (videoTagIdsByPathKey[TagRules.pathKey(item.path)]?.isEmpty ?? false) {
        videoTagIdsByPathKey.remove(TagRules.pathKey(item.path));
      }
      if (hadManualLink || changedCompat) {
        changed++;
      }
      _videoPersistence.insertInBatch(batch, item);
    }
    await batch.commit(noResult: true);
    return changed;
  }

  void _addManualTagToItem(VideoItem item, TagItem tag) {
    final parentId = tag.parentId;
    if (parentId == null) {
      item.tags.add(tag.name);
      return;
    }
    (item.childTags[parentId] ??= <String>{}).add(tag.name);
  }

  bool _removeManualTagFromItem(VideoItem item, TagItem tag) {
    final parentId = tag.parentId;
    if (parentId == null) {
      final folderTags = _folderTagsForItem(item);
      final shouldKeepFolder =
          folderTags.any((folderTag) => TagRules.sameTag(folderTag, tag.name));
      if (shouldKeepFolder) {
        return false;
      }
      final before = item.tags.length;
      item.tags.removeWhere((value) => TagRules.sameTag(value, tag.name));
      return item.tags.length != before;
    }
    final folderChildren = _folderChildTagsForItem(item, parentId);
    final shouldKeepFolder = folderChildren
        .any((folderTag) => TagRules.sameTag(folderTag, tag.name));
    if (shouldKeepFolder) {
      return false;
    }
    final children = item.childTags[parentId];
    if (children == null) {
      return false;
    }
    final before = children.length;
    children.removeWhere((value) => TagRules.sameTag(value, tag.name));
    if (children.isEmpty) {
      item.childTags.remove(parentId);
    }
    return children.length != before;
  }

  void _syncFolderTagsInBatch(Batch batch, VideoItem item) {
    _tagPersistence.removeVideoTagSourceInBatch(
        batch, item.path, TagSource.folder);
    for (final tag in item.tags) {
      _tagPersistence.attachTagInBatch(
        batch,
        item.path,
        _tagFor(
          name: tag,
          groupId: 'folder.primary',
          source: TagSource.folder,
        ),
        source: TagSource.folder,
      );
    }
    for (final entry in item.childTags.entries) {
      for (final child in entry.value) {
        _tagPersistence.attachTagInBatch(
          batch,
          item.path,
          _tagFor(
            name: child,
            groupId: 'folder.child',
            source: TagSource.folder,
            parentId: entry.key,
          ),
          source: TagSource.folder,
        );
      }
    }
  }

  void _syncManualTagsInBatch(Batch batch, VideoItem item,
      {String? parentTag}) {
    _tagPersistence.removeManualTagScopeInBatch(
      batch,
      item.path,
      parentTag: parentTag,
    );
    if (parentTag == null) {
      final folderTags = _folderTagsForItem(item);
      for (final tag in item.tags) {
        if (folderTags.any((folderTag) => TagRules.sameTag(folderTag, tag))) {
          continue;
        }
        _tagPersistence.attachTagInBatch(
          batch,
          item.path,
          _tagFor(
            name: tag,
            groupId: 'manual',
            source: TagSource.manual,
          ),
          source: TagSource.manual,
        );
      }
      return;
    }
    final folderChildTags = _folderChildTagsForItem(item, parentTag);
    for (final child in item.childTags[parentTag] ?? const <String>{}) {
      if (folderChildTags
          .any((folderTag) => TagRules.sameTag(folderTag, child))) {
        continue;
      }
      _tagPersistence.attachTagInBatch(
        batch,
        item.path,
        _tagFor(
          name: child,
          groupId: 'manual',
          source: TagSource.manual,
          parentId: parentTag,
        ),
        source: TagSource.manual,
      );
    }
  }

  Set<String> _folderTagsForItem(VideoItem item) {
    final rootPath = item.rootPath;
    if (rootPath == null || rootPath.isEmpty) {
      return const <String>{};
    }
    return TagRules.parentTagsFor(rootPath, item.path);
  }

  Set<String> _folderChildTagsForItem(VideoItem item, String parentTag) {
    final rootPath = item.rootPath;
    if (rootPath == null || rootPath.isEmpty) {
      return const <String>{};
    }
    return TagRules.childTagsFor(rootPath, item.path)[parentTag] ??
        const <String>{};
  }

  TagItem _tagFor({
    required String name,
    required String groupId,
    required TagSource source,
    String? parentId,
  }) {
    final id = _tagIdFor(name: name, groupId: groupId, parentId: parentId);
    final existing = tagsById[id];
    if (existing != null) {
      return existing;
    }
    final item = TagItem(
      id: id,
      name: name,
      displayName: name,
      groupId: groupId,
      parentId: parentId,
      source: source,
    );
    tagsById[id] = item;
    return item;
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
    batch.insert('metadata', {'key': 'roots', 'value': jsonEncode(roots)},
        conflictAlgorithm: ConflictAlgorithm.replace);
    batch.insert(
        'metadata', {'key': 'favoriteTags', 'value': jsonEncode(favoriteTags)},
        conflictAlgorithm: ConflictAlgorithm.replace);
    batch.delete('videos');
    for (final item in videos.values) {
      _videoPersistence.insertInBatch(batch, item);
      _syncFolderTagsInBatch(batch, item);
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveMetadata() async {
    final batch = _db.batch();
    batch.insert('metadata', {'key': 'roots', 'value': jsonEncode(roots)},
        conflictAlgorithm: ConflictAlgorithm.replace);
    batch.insert(
        'metadata', {'key': 'favoriteTags', 'value': jsonEncode(favoriteTags)},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
  }

  /**
   * 关闭当前媒体库数据库连接。
   *
   * 应用运行期通常随进程持有 `LibraryStore`，测试和未来 repository 拆分需要显式释放
   * SQLite 文件句柄，避免临时 profile 或测试数据库目录被占用。
   */
  Future<void> close() => _db.close();

  Future<void> upsertVideo(VideoItem item) async {
    videos[TagRules.pathKey(item.path)] = item;
    await _videoPersistence.upsert(item);
  }

  Future<void> deleteVideo(String path) async {
    videos.remove(TagRules.pathKey(path));
    await _tagPersistence.deleteVideoLinks(path);
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
   * 从媒体库根目录列表移除一个目录。
   *
   * 这里只更新 root 配置，不删除磁盘文件，也不立即清理已有视频记录；
   * 后续 stable identity / missing-relink 阶段再决定视频记录如何标记。
   */
  Future<void> removeRoot(String rootPath) async {
    final rootKey = TagRules.pathKey(TagRules.normalizeRootPath(rootPath));
    roots.removeWhere((root) => TagRules.pathKey(root) == rootKey);
    await saveMetadata();
  }

  Future<int> scan() async {
    final scanResult = await const LibraryScanService().scanRoots(roots);
    final batch = _db.batch();
    var added = 0;

    for (final scanned in scanResult.entries) {
      final videoKey = TagRules.pathKey(scanned.path);
      final existing = videos[videoKey];
      if (existing == null) {
        final item = VideoItem(
          path: scanned.path,
          title: scanned.title,
          folder: scanned.folder,
          tags: scanned.tags,
          childTags: scanned.childTags,
          rootPath: scanned.rootPath,
          relativePath: scanned.relativePath,
          fileSize: scanned.fileSize,
          modifiedMs: scanned.modifiedMs,
          mediaFingerprint: scanned.mediaFingerprint,
          addedAt: DateTime.now(),
        );
        videos[videoKey] = item;
        _videoPersistence.insertInBatch(batch, item);
        _syncFolderTagsInBatch(batch, item);
        added++;
      } else {
        final tagsChanged = !_setEquals(existing.tags, scanned.tags);
        final childTagsChanged =
            !_childTagsEquals(existing.childTags, scanned.childTags);
        final contentChanged = existing.mediaFingerprint != null &&
            existing.mediaFingerprint != scanned.mediaFingerprint;
        final indexChanged = existing.rootPath != scanned.rootPath ||
            existing.relativePath != scanned.relativePath ||
            existing.fileSize != scanned.fileSize ||
            existing.modifiedMs != scanned.modifiedMs ||
            existing.mediaFingerprint != scanned.mediaFingerprint;
        existing.tags
          ..clear()
          ..addAll(scanned.tags);
        existing.childTags
          ..clear()
          ..addAll(scanned.childTags
              .map((key, value) => MapEntry(key, <String>{...value})));
        existing.rootPath = scanned.rootPath;
        existing.relativePath = scanned.relativePath;
        existing.fileSize = scanned.fileSize;
        existing.modifiedMs = scanned.modifiedMs;
        existing.mediaFingerprint = scanned.mediaFingerprint;
        if (contentChanged) {
          existing.mediaDetails = null;
          existing.mediaDetailsError = null;
          existing.thumbnailError = null;
        }
        if (tagsChanged || childTagsChanged || indexChanged) {
          _videoPersistence.insertInBatch(batch, existing);
          if (tagsChanged || childTagsChanged) {
            _syncFolderTagsInBatch(batch, existing);
          }
        }
      }
    }

    final removedPaths = <String>[];
    videos.removeWhere((pathKey, item) {
      final shouldRemove = !scanResult.seenPathKeys.contains(pathKey) &&
          !File(item.path).existsSync();
      if (shouldRemove) {
        removedPaths.add(item.path);
      }
      return shouldRemove;
    });
    for (final path in removedPaths) {
      videoTagIdsByPathKey.remove(TagRules.pathKey(path));
      batch.delete(
        'video_tags',
        where: Platform.isWindows
            ? 'video_path = ? COLLATE NOCASE'
            : 'video_path = ?',
        whereArgs: [path],
      );
      batch.delete(
        'videos',
        where: Platform.isWindows ? 'path = ? COLLATE NOCASE' : 'path = ?',
        whereArgs: [path],
      );
    }
    batch.insert('metadata', {'key': 'roots', 'value': jsonEncode(roots)},
        conflictAlgorithm: ConflictAlgorithm.replace);
    batch.insert(
        'metadata', {'key': 'favoriteTags', 'value': jsonEncode(favoriteTags)},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
    return added;
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
