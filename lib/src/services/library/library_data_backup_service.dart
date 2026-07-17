import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/data_backup_models.dart';
import '../../models/platform_models.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 独立视频依赖备份服务。
 *
 * 主库仍是唯一业务写入源；本服务只把收藏、播放状态和非 folder 标签复制到独立 SQLite。
 * 全量任务以稳定 videoId 游标分批推进，游标和增量队列都持久化，因此应用异常退出后
 * 可以继续。任务不读取视频文件，播放期间还会在批次边界暂停，避免与解码争用磁盘。
 */
class LibraryDataBackupService {
  LibraryDataBackupService._({
    required Database sourceDatabase,
    required Database backupDatabase,
    required bool enabled,
  })  : _sourceDatabase = sourceDatabase,
        _backupDatabase = backupDatabase,
        _enabled = enabled,
        _status = DataBackupStatus(
          enabled: enabled,
          phase: enabled ? DataBackupPhase.idle : DataBackupPhase.disabled,
        );

  /** 每批最多处理 32 条，限制单次 SQLite 占用时间。 */
  static const _batchSize = 32;

  /** 主媒体库只读连接；业务写入仍由 LibraryStore 独占。 */
  final Database _sourceDatabase;

  /** 独立备份 SQLite 连接。 */
  final Database _backupDatabase;

  /** 状态广播只包含计数和阶段，不泄露用户数据。 */
  final StreamController<DataBackupStatus> _statusController =
      StreamController<DataBackupStatus>.broadcast();

  bool _enabled;
  bool _pausedForPlayback = false;
  bool _maintenanceRunning = false;
  bool _disposed = false;
  Future<void>? _workerFuture;
  DataBackupStatus _status;

  /** 创建并迁移独立备份库；启动任务由调用方显式触发。 */
  static Future<LibraryDataBackupService> create({
    required Database sourceDatabase,
    required Database backupDatabase,
    required bool enabled,
  }) async {
    await _createSchema(backupDatabase);
    return LibraryDataBackupService._(
      sourceDatabase: sourceDatabase,
      backupDatabase: backupDatabase,
      enabled: enabled,
    );
  }

  /** 设置页当前状态快照。 */
  DataBackupStatus get status => _status;

  /** 设置页状态流；业务层不依赖 Flutter。 */
  Stream<DataBackupStatus> get statusStream => _statusController.stream;

  /** 测试只读核对备份表，不允许页面直接访问。 */
  Database get database => _backupDatabase;

  /** 备份开关当前值。 */
  bool get enabled => _enabled;

  /** 建立向后兼容、可重复执行的独立备份 schema。 */
  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_dependency_backups (
        video_id TEXT PRIMARY KEY,
        media_fingerprint TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_dependency_backup_fingerprint
      ON video_dependency_backups(media_fingerprint)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_video_sync (
        video_id TEXT PRIMARY KEY,
        queued_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS backup_control (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  /**
   * 启动或续跑本次全量核对。
   *
   * 上次未完成或异常退出时保留/重建全量核对；正常关闭后的启动只消费持久化
   * 增量队列。这样既覆盖“主库已提交但队列尚未写入”的崩溃窗口，也避免每次启动
   * 重写全部快照。
   */
  Future<void> startOrResume() async {
    if (_disposed) {
      return;
    }
    if (!_enabled) {
      // 应用以“关闭备份”启动时，后续主库修改不会入队；未来开启必须全量补齐。
      await _setControlValues(<String, String>{'reconcile_required': '1'});
      return;
    }
    final inProgress = await _controlValue('full_sync_in_progress') == '1';
    final previousSessionOpen = await _controlValue('session_open') == '1';
    final reconcileRequired = await _controlValue('reconcile_required') == '1';
    final hasCompletedBackup =
        (await _controlValue('last_completed_at') ?? '').isNotEmpty;
    var processed = 0;
    final needsFullSync = inProgress ||
        previousSessionOpen ||
        reconcileRequired ||
        !hasCompletedBackup;
    await _setControlValues(<String, String>{'session_open': '1'});
    if (!inProgress && needsFullSync) {
      await _setControlValues(<String, String>{
        'full_sync_in_progress': '1',
        'full_sync_cursor': '',
        'reconcile_required': '0',
      });
    } else if (inProgress) {
      final cursor = await _controlValue('full_sync_cursor') ?? '';
      if (cursor.isNotEmpty) {
        final rows = await _sourceDatabase.rawQuery(
          'SELECT COUNT(*) AS count FROM videos WHERE video_id <= ?',
          <Object?>[cursor],
        );
        processed = rows.single['count'] as int? ?? 0;
      }
    } else {
      final rows = await _sourceDatabase.rawQuery(
        'SELECT COUNT(*) AS count FROM videos',
      );
      processed = rows.single['count'] as int? ?? 0;
    }
    await _refreshStatus(
      phase: DataBackupPhase.running,
      processed: processed,
    );
    _kickWorker();
  }

  /** 用户点击“立即备份”时重置全量游标，不等待所有批次完成。 */
  Future<void> runNow() async {
    if (!_enabled || _disposed) {
      return;
    }
    // 若旧 worker 正在写游标，先让它停在批次边界，避免重置后的空游标被旧批次覆盖。
    _pausedForPlayback = true;
    try {
      final worker = _workerFuture;
      if (worker != null) {
        await worker;
      }
      await _setControlValues(<String, String>{
        'full_sync_in_progress': '1',
        'full_sync_cursor': '',
      });
    } finally {
      _pausedForPlayback = false;
    }
    await _refreshStatus(phase: DataBackupPhase.running, processed: 0);
    _kickWorker();
  }

  /** 切换设置；关闭时保留既有备份和未完成游标，重新开启后继续。 */
  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled || _disposed) {
      return;
    }
    _enabled = enabled;
    if (!enabled) {
      // 关闭期间主库变化不会进入增量队列，重新开启时必须做一次全量核对。
      await _setControlValues(<String, String>{'reconcile_required': '1'});
      _emitStatus(DataBackupStatus(
        enabled: false,
        phase: DataBackupPhase.disabled,
        processed: _status.processed,
        total: _status.total,
        pending: _status.pending,
        lastCompletedAt: _status.lastCompletedAt,
      ));
      return;
    }
    await startOrResume();
  }

  /** 在主库提交后把单个稳定身份加入去重增量队列。 */
  Future<void> enqueueVideo(String videoId) => enqueueVideos(<String>[videoId]);

  /** 批量加入增量队列；只写短小 videoId，不复制路径或标签内容。 */
  Future<void> enqueueVideos(Iterable<String> videoIds) async {
    if (!_enabled || _disposed) {
      return;
    }
    final unique = videoIds.where((id) => id.isNotEmpty).toSet();
    if (unique.isEmpty) {
      return;
    }
    final batch = _backupDatabase.batch();
    final now = DateTime.now().toIso8601String();
    for (final videoId in unique) {
      batch.insert(
        'pending_video_sync',
        <String, Object?>{'video_id': videoId, 'queued_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    await _refreshStatus(phase: DataBackupPhase.running);
    _kickWorker();
  }

  /** 标签定义变化后，把所有引用视频加入增量队列。 */
  Future<void> enqueueTagDependents(String tagId) async {
    if (!_enabled || _disposed) {
      return;
    }
    final rows = await _sourceDatabase.query(
      'video_tags',
      columns: const <String>['video_id'],
      where: 'tag_id = ? AND video_id IS NOT NULL',
      whereArgs: <Object?>[tagId],
      distinct: true,
    );
    await enqueueVideos(
      rows.map((row) => row['video_id'] as String).where((id) => id.isNotEmpty),
    );
  }

  /**
   * 用户明确删除单个视频时同步清理对应快照。
   *
   * 该动作不受开关影响：关闭备份期间的显式删除也不能留下未来会误恢复的旧快照。
   */
  Future<void> deleteSnapshot(String videoId) async {
    final batch = _backupDatabase.batch();
    batch.delete(
      'video_dependency_backups',
      where: 'video_id = ?',
      whereArgs: <Object?>[videoId],
    );
    batch.delete(
      'pending_video_sync',
      where: 'video_id = ?',
      whereArgs: <Object?>[videoId],
    );
    await batch.commit(noResult: true);
    await _refreshStatus();
  }

  /** 播放前在当前小批次结束后暂停；不会中断已开始的 SQLite 事务。 */
  Future<void> pauseForPlayback() async {
    if (!_enabled || _disposed) {
      return;
    }
    _pausedForPlayback = true;
    final worker = _workerFuture;
    if (worker != null) {
      await worker;
    }
    if (_enabled && !_disposed) {
      _emitStatus(DataBackupStatus(
        enabled: true,
        phase: DataBackupPhase.pausedForPlayback,
        processed: _status.processed,
        total: _status.total,
        pending: _status.pending,
        lastCompletedAt: _status.lastCompletedAt,
      ));
    }
  }

  /** 播放器原生资源释放后恢复未完成任务。 */
  void resumeAfterPlayback() {
    _pausedForPlayback = false;
    if (!_enabled || _disposed) {
      return;
    }
    _emitStatus(DataBackupStatus(
      enabled: true,
      phase: DataBackupPhase.running,
      processed: _status.processed,
      total: _status.total,
      pending: _status.pending,
      lastCompletedAt: _status.lastCompletedAt,
    ));
    _kickWorker();
  }

  /**
   * 仅在 fingerprint 备份侧唯一时返回恢复记录。
   *
   * 扫描侧唯一性和 videoId 冲突仍由扫描协调器再次验证，形成双侧唯一保护。
   */
  Future<DataBackupRestoreRecord?> findUniqueRestore(
      String mediaFingerprint) async {
    if (!_enabled || mediaFingerprint.isEmpty) {
      return null;
    }
    final rows = await _backupDatabase.query(
      'video_dependency_backups',
      where: 'media_fingerprint = ?',
      whereArgs: <Object?>[mediaFingerprint],
      limit: 2,
    );
    if (rows.length != 1) {
      return null;
    }
    return _restoreRecordFromRow(rows.single);
  }

  /** 测试或关闭前等待当前 worker 自然停在空队列/完成游标。 */
  Future<void> flush() async {
    final worker = _workerFuture;
    if (worker != null) {
      await worker;
    }
  }

  /** 停止新批次并关闭独立数据库；未完成游标保留供下次启动续跑。 */
  Future<void> close() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final worker = _workerFuture;
    if (worker != null) {
      await worker;
    }
    // 只有走到显式关闭路径才标记 clean；写标记失败时保留 dirty 语义，下一次多做
    // 一轮核对即可，不应让退出流程因已经被外部关闭的测试/宿主连接再次失败。
    try {
      await _setControlValues(<String, String>{'session_open': '0'});
    } catch (_) {
      // clean marker 只是写放大优化，不是用户数据提交；失败时保守回退异常退出语义。
    }
    await _statusController.close();
    await _backupDatabase.close();
  }

  /** 保证同一时刻只有一个低优先级 worker。 */
  void _kickWorker() {
    if (_workerFuture != null ||
        !_enabled ||
        _pausedForPlayback ||
        _maintenanceRunning ||
        _disposed) {
      return;
    }
    final worker = _runWorker();
    _workerFuture = worker;
    unawaited(worker.whenComplete(() {
      if (identical(_workerFuture, worker)) {
        _workerFuture = null;
      }
    }));
  }

  /** 增量队列优先，全量游标其次；每批后主动让出事件循环。 */
  Future<void> _runWorker() async {
    try {
      while (_enabled &&
          !_pausedForPlayback &&
          !_maintenanceRunning &&
          !_disposed) {
        final incrementalWorked = await _processPendingBatch();
        if (_pausedForPlayback || _disposed || !_enabled) {
          break;
        }
        final fullWorked =
            incrementalWorked ? false : await _processFullBatch();
        if (!incrementalWorked && !fullWorked) {
          await _refreshStatus(phase: DataBackupPhase.idle);
          break;
        }
        // 备份只做 SQLite I/O，但仍限制连续占用 UI isolate 的时间片。
        await Future<void>.delayed(const Duration(milliseconds: 12));
      }
    } catch (error) {
      _emitStatus(DataBackupStatus(
        enabled: _enabled,
        phase: DataBackupPhase.failed,
        processed: _status.processed,
        total: _status.total,
        pending: _status.pending,
        lastCompletedAt: _status.lastCompletedAt,
        error: error.runtimeType.toString(),
      ));
    }
  }

  /** 处理持久化增量队列的一小批。 */
  Future<bool> _processPendingBatch() async {
    final rows = await _backupDatabase.query(
      'pending_video_sync',
      columns: const <String>['video_id'],
      orderBy: 'queued_at ASC',
      limit: _batchSize,
    );
    if (rows.isEmpty) {
      return false;
    }
    final ids = rows.map((row) => row['video_id'] as String).toList();
    await _copyVideoIds(ids);
    final batch = _backupDatabase.batch();
    for (final id in ids) {
      batch.delete(
        'pending_video_sync',
        where: 'video_id = ?',
        whereArgs: <Object?>[id],
      );
    }
    await batch.commit(noResult: true);
    await _refreshStatus(phase: DataBackupPhase.running);
    return true;
  }

  /** 按稳定 videoId 游标处理一小批全量核对。 */
  Future<bool> _processFullBatch() async {
    if (await _controlValue('full_sync_in_progress') != '1') {
      return false;
    }
    final cursor = await _controlValue('full_sync_cursor') ?? '';
    final rows = await _sourceDatabase.query(
      'videos',
      columns: const <String>['video_id'],
      where: 'video_id > ?',
      whereArgs: <Object?>[cursor],
      orderBy: 'video_id ASC',
      limit: _batchSize,
    );
    if (rows.isEmpty) {
      final completedAt = DateTime.now();
      await _setControlValues(<String, String>{
        'full_sync_in_progress': '0',
        'last_completed_at': completedAt.toIso8601String(),
      });
      await _refreshStatus(
        phase: DataBackupPhase.idle,
        processed: _status.total,
        lastCompletedAt: completedAt,
      );
      return false;
    }
    final ids = rows.map((row) => row['video_id'] as String).toList();
    await _copyVideoIds(ids);
    await _setControlValues(<String, String>{'full_sync_cursor': ids.last});
    await _refreshStatus(
      phase: DataBackupPhase.running,
      processed: (_status.processed + ids.length).clamp(0, _status.total),
    );
    return true;
  }

  /** 从主库批量读取视频和非 folder 标签，并在一个备份 batch 中提交。 */
  Future<void> _copyVideoIds(List<String> videoIds) async {
    if (videoIds.isEmpty) {
      return;
    }
    final snapshots = await _snapshotsForVideoIds(videoIds);
    final batch = _backupDatabase.batch();
    final now = DateTime.now().toIso8601String();
    for (final snapshot in snapshots.values) {
      // 仅内容变化时更新，避免崩溃恢复或手动全量核对重写全部 SQLite 页。
      batch.rawInsert('''
        INSERT INTO video_dependency_backups(
          video_id, media_fingerprint, payload_json, updated_at
        ) VALUES(?, ?, ?, ?)
        ON CONFLICT(video_id) DO UPDATE SET
          media_fingerprint = excluded.media_fingerprint,
          payload_json = excluded.payload_json,
          updated_at = excluded.updated_at
        WHERE video_dependency_backups.media_fingerprint <>
                excluded.media_fingerprint
           OR video_dependency_backups.payload_json <> excluded.payload_json
      ''', <Object?>[
        snapshot.videoId,
        snapshot.mediaFingerprint,
        snapshot.payloadJson,
        now,
      ]);
    }
    await batch.commit(noResult: true);
  }

  /** 从主库构造稳定排序的规范快照，供同步和完整性对比共用。 */
  Future<Map<String, _CanonicalBackupSnapshot>> _snapshotsForVideoIds(
      List<String> videoIds) async {
    final placeholders = List<String>.filled(videoIds.length, '?').join(',');
    final videoRows = await _sourceDatabase.rawQuery('''
      SELECT video_id, media_fingerprint, is_favorite, last_played_at,
             playback_position_ms, playback_duration_ms, playback_completed,
             playback_position_updated_at
      FROM videos
      WHERE video_id IN ($placeholders)
    ''', videoIds);
    // usage_count 是可由关系表重新统计的全局派生值；若写入每条视频快照，一次引用数变化
    // 会把同标签的数千条快照误报为 stale。规范快照固定为 0，恢复时再由标签索引维护。
    final linkRows = await _sourceDatabase.rawQuery('''
      SELECT vt.video_id, vt.source AS link_source, vt.locked,
             t.id AS tag_id, t.name AS tag_name, t.display_name AS tag_display_name,
             t.group_id AS tag_group_id, t.parent_id AS tag_parent_id,
             t.color AS tag_color, t.source AS tag_source,
             t.aliases_json, 0 AS usage_count, t.is_favorite AS tag_is_favorite,
             t.is_hidden AS tag_is_hidden, t.sort_order AS tag_sort_order,
             g.id AS group_id, g.name AS group_name,
             g.display_name AS group_display_name, g.sort_order AS group_sort_order,
             g.allow_multi_select, g.default_logic
      FROM video_tags vt
      INNER JOIN tags t ON t.id = vt.tag_id
      LEFT JOIN tag_groups g ON g.id = t.group_id
      WHERE vt.video_id IN ($placeholders) AND vt.source <> 'folder'
      ORDER BY vt.video_id ASC, vt.tag_id ASC, vt.source ASC
    ''', videoIds);
    final linksByVideoId = <String, List<Map<String, Object?>>>{};
    for (final row in linkRows) {
      final videoId = row['video_id'] as String;
      (linksByVideoId[videoId] ??= <Map<String, Object?>>[]).add(row);
    }
    final snapshots = <String, _CanonicalBackupSnapshot>{};
    for (final row in videoRows) {
      final fingerprint = row['media_fingerprint'] as String?;
      if (fingerprint == null || fingerprint.isEmpty) {
        continue;
      }
      final videoId = row['video_id'] as String;
      final payload = <String, Object?>{
        'isFavorite': (row['is_favorite'] as int? ?? 0) == 1,
        'lastPlayedAt': row['last_played_at'],
        'playbackPositionMs': row['playback_position_ms'] as int? ?? 0,
        'playbackDurationMs': row['playback_duration_ms'] as int? ?? 0,
        'playbackCompleted': (row['playback_completed'] as int? ?? 0) == 1,
        'playbackPositionUpdatedAt': row['playback_position_updated_at'],
        'links': linksByVideoId[videoId] ?? const <Map<String, Object?>>[],
      };
      snapshots[videoId] = _CanonicalBackupSnapshot(
        videoId: videoId,
        mediaFingerprint: fingerprint,
        payloadJson: jsonEncode(payload),
      );
    }
    return snapshots;
  }

  /**
   * 用户显式检查独立备份的 SQLite、JSON 和当前主库覆盖情况。
   *
   * 检查不修复、不删除可恢复快照；必要时用户可再点击“立即备份”。
   */
  Future<DataBackupIntegrityReport> checkIntegrity() =>
      _runMaintenance(() async {
        final quickCheck = await _backupDatabase.rawQuery('PRAGMA quick_check');
        final sqliteHealthy = quickCheck.length == 1 &&
            quickCheck.single.values.single.toString().toLowerCase() == 'ok';
        final rows = await _backupDatabase.query(
          'video_dependency_backups',
          columns: const <String>[
            'video_id',
            'media_fingerprint',
            'payload_json',
          ],
          orderBy: 'video_id ASC',
        );
        var invalidPayloads = 0;
        var missingFingerprints = 0;
        final backupByVideoId = <String, Map<String, Object?>>{};
        final fingerprintCounts = <String, int>{};
        for (final row in rows) {
          final fingerprint = row['media_fingerprint'] as String? ?? '';
          if (fingerprint.isEmpty) {
            missingFingerprints += 1;
          } else {
            fingerprintCounts.update(
              fingerprint,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
          }
          try {
            final payload = jsonDecode(row['payload_json'] as String);
            if (payload is! Map || payload['links'] is! List) {
              invalidPayloads += 1;
            }
          } catch (_) {
            invalidPayloads += 1;
          }
          backupByVideoId[row['video_id'] as String] = row;
        }

        final sourceRows = await _sourceDatabase.query(
          'videos',
          columns: const <String>['video_id'],
          orderBy: 'video_id ASC',
        );
        var missingCurrentSnapshots = 0;
        var staleCurrentSnapshots = 0;
        final currentVideoIds = <String>{};
        for (var start = 0; start < sourceRows.length; start += _batchSize) {
          final end = (start + _batchSize).clamp(0, sourceRows.length);
          final ids = sourceRows
              .sublist(start, end)
              .map((row) => row['video_id'] as String)
              .toList();
          currentVideoIds.addAll(ids);
          final expected = await _snapshotsForVideoIds(ids);
          for (final videoId in ids) {
            final snapshot = expected[videoId];
            if (snapshot == null) {
              // 缺少指纹的当前视频无法形成安全快照，仍应显示为未覆盖。
              missingCurrentSnapshots += 1;
              continue;
            }
            final stored = backupByVideoId[videoId];
            if (stored == null) {
              missingCurrentSnapshots += 1;
            } else if (stored['media_fingerprint'] !=
                    snapshot.mediaFingerprint ||
                stored['payload_json'] != snapshot.payloadJson) {
              staleCurrentSnapshots += 1;
            }
          }
          // 显式检查也按小批次让出事件循环，避免大媒体库冻结设置页。
          await Future<void>.delayed(const Duration(milliseconds: 4));
        }
        final recoverableSnapshots = backupByVideoId.keys
            .where((videoId) => !currentVideoIds.contains(videoId))
            .length;
        return DataBackupIntegrityReport(
          checkedAt: DateTime.now(),
          sqliteHealthy: sqliteHealthy,
          backupRecords: rows.length,
          currentVideos: sourceRows.length,
          invalidPayloads: invalidPayloads,
          missingFingerprints: missingFingerprints,
          missingCurrentSnapshots: missingCurrentSnapshots,
          staleCurrentSnapshots: staleCurrentSnapshots,
          ambiguousFingerprints:
              fingerprintCounts.values.where((count) => count > 1).length,
          recoverableSnapshots: recoverableSnapshots,
        );
      });

  /** 创建不含媒体路径和文件内容的便携 JSON 导出数据。 */
  Future<Uint8List> createPortableExport() => _runMaintenance(() async {
        final quickCheck = await _backupDatabase.rawQuery('PRAGMA quick_check');
        if (quickCheck.length != 1 ||
            quickCheck.single.values.single.toString().toLowerCase() != 'ok') {
          throw StateError('备份数据库完整性检查未通过，已停止导出');
        }
        final rows = await _backupDatabase.query(
          'video_dependency_backups',
          columns: const <String>[
            'video_id',
            'media_fingerprint',
            'payload_json',
            'updated_at',
          ],
          orderBy: 'video_id ASC',
        );
        final records = <Map<String, Object?>>[];
        for (final row in rows) {
          final payload = jsonDecode(row['payload_json'] as String);
          if (payload is! Map || payload['links'] is! List) {
            throw StateError('备份中存在无法识别的快照，已停止导出');
          }
          records.add(<String, Object?>{
            'videoId': row['video_id'],
            'mediaFingerprint': row['media_fingerprint'],
            'payload': payload,
            'updatedAt': row['updated_at'],
          });
        }
        final document = <String, Object?>{
          'format': 'local_tag_player_video_dependency_backup',
          'version': 1,
          'exportedAt': DateTime.now().toUtc().toIso8601String(),
          'recordCount': records.length,
          'records': records,
        };
        return Uint8List.fromList(utf8.encode(jsonEncode(document)));
      });

  /** 在 worker 批次边界暂停并串行执行检查/导出，完成后恢复后台任务。 */
  Future<T> _runMaintenance<T>(Future<T> Function() action) async {
    if (_disposed) {
      throw StateError('备份服务已经关闭');
    }
    if (_maintenanceRunning) {
      throw StateError('另一项备份维护任务正在执行');
    }
    _maintenanceRunning = true;
    final worker = _workerFuture;
    if (worker != null) {
      await worker;
    }
    try {
      return await action();
    } finally {
      _maintenanceRunning = false;
      if (_enabled && !_pausedForPlayback && !_disposed) {
        _kickWorker();
      }
    }
  }

  /** 把备份 JSON 还原为扫描协调器可安全消费的领域记录。 */
  DataBackupRestoreRecord _restoreRecordFromRow(Map<String, Object?> row) {
    final payload = (jsonDecode(row['payload_json'] as String) as Map)
        .cast<String, Object?>();
    final links = <DataBackupTagLink>[];
    for (final raw in (payload['links'] as List? ?? const <Object?>[])) {
      final link = (raw as Map).cast<String, Object?>();
      final aliases = _decodeStringList(link['aliases_json']);
      final tag = TagItem(
        id: link['tag_id'] as String,
        name: link['tag_name'] as String,
        displayName: link['tag_display_name'] as String?,
        groupId: link['tag_group_id'] as String?,
        parentId: link['tag_parent_id'] as String?,
        color: link['tag_color'] as String?,
        source: _tagSource(link['tag_source']),
        aliases: aliases,
        usageCount: link['usage_count'] as int? ?? 0,
        isFavorite: (link['tag_is_favorite'] as int? ?? 0) == 1,
        isHidden: (link['tag_is_hidden'] as int? ?? 0) == 1,
        sortOrder: link['tag_sort_order'] as int? ?? 0,
      );
      final groupId = link['group_id'] as String?;
      final group = groupId == null
          ? null
          : TagGroup(
              id: groupId,
              name: link['group_name'] as String,
              displayName: link['group_display_name'] as String?,
              sortOrder: link['group_sort_order'] as int? ?? 0,
              allowMultiSelect: (link['allow_multi_select'] as int? ?? 1) == 1,
              defaultLogic: _tagGroupLogic(link['default_logic']),
              items: const <TagItem>[],
            );
      links.add(DataBackupTagLink(
        tag: tag,
        group: group,
        source: _tagSource(link['link_source']),
        locked: (link['locked'] as int? ?? 0) == 1,
      ));
    }
    return DataBackupRestoreRecord(
      videoId: row['video_id'] as String,
      mediaFingerprint: row['media_fingerprint'] as String,
      isFavorite: payload['isFavorite'] as bool? ?? false,
      lastPlayedAt:
          DateTime.tryParse(payload['lastPlayedAt']?.toString() ?? ''),
      playbackPosition: Duration(
        milliseconds: payload['playbackPositionMs'] as int? ?? 0,
      ),
      playbackDuration: Duration(
        milliseconds: payload['playbackDurationMs'] as int? ?? 0,
      ),
      playbackCompleted: payload['playbackCompleted'] as bool? ?? false,
      playbackPositionUpdatedAt: DateTime.tryParse(
        payload['playbackPositionUpdatedAt']?.toString() ?? '',
      ),
      links: List<DataBackupTagLink>.unmodifiable(links),
    );
  }

  /** 兼容旧快照中的 JSON 字符串或直接数组。 */
  List<String> _decodeStringList(Object? value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.map((item) => item.toString()).toList();
        }
      } catch (_) {
        return const <String>[];
      }
    }
    return const <String>[];
  }

  /** 未知来源保守回退 manual，避免恢复为可自动重算的 folder。 */
  TagSource _tagSource(Object? value) => TagSource.values.firstWhere(
        (source) => source.name == value?.toString(),
        orElse: () => TagSource.manual,
      );

  /** 未知组逻辑保持同组 OR 默认语义。 */
  TagGroupLogic _tagGroupLogic(Object? value) =>
      TagGroupLogic.values.firstWhere(
        (logic) => logic.name == value?.toString(),
        orElse: () => TagGroupLogic.sameGroupOr,
      );

  /** 读取单个持久化控制值。 */
  Future<String?> _controlValue(String key) async {
    final rows = await _backupDatabase.query(
      'backup_control',
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  /** 在一个 batch 中更新多个游标/完成状态。 */
  Future<void> _setControlValues(Map<String, String> values) async {
    final batch = _backupDatabase.batch();
    for (final entry in values.entries) {
      batch.insert(
        'backup_control',
        <String, Object?>{'key': entry.key, 'value': entry.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /** 重新读取无隐私计数并广播状态。 */
  Future<void> _refreshStatus({
    DataBackupPhase? phase,
    int? processed,
    DateTime? lastCompletedAt,
  }) async {
    final totalRows = await _sourceDatabase.rawQuery(
      'SELECT COUNT(*) AS count FROM videos',
    );
    final pendingRows = await _backupDatabase.rawQuery(
      'SELECT COUNT(*) AS count FROM pending_video_sync',
    );
    final persistedLast = lastCompletedAt ??
        DateTime.tryParse(
          await _controlValue('last_completed_at') ?? '',
        );
    _emitStatus(DataBackupStatus(
      enabled: _enabled,
      phase: phase ?? _status.phase,
      processed: processed ?? _status.processed,
      total: totalRows.single['count'] as int? ?? 0,
      pending: pendingRows.single['count'] as int? ?? 0,
      lastCompletedAt: persistedLast,
    ));
  }

  /** disposed 后不再向已关闭 stream 写入。 */
  void _emitStatus(DataBackupStatus status) {
    _status = status;
    if (!_disposed && !_statusController.isClosed) {
      _statusController.add(status);
    }
  }
}

/** 主库读取后生成的规范快照；不包含路径或媒体文件内容。 */
class _CanonicalBackupSnapshot {
  const _CanonicalBackupSnapshot({
    required this.videoId,
    required this.mediaFingerprint,
    required this.payloadJson,
  });

  final String videoId;
  final String mediaFingerprint;
  final String payloadJson;
}
