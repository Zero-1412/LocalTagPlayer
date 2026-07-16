import 'platform_models.dart';

// ignore_for_file: slash_for_doc_comments

/** 后台视频依赖备份的可见阶段。 */
enum DataBackupPhase { disabled, idle, running, pausedForPlayback, failed }

/** 设置页消费的轻量备份状态，不包含本地路径、标签名称或视频标题。 */
class DataBackupStatus {
  const DataBackupStatus({
    required this.enabled,
    required this.phase,
    this.processed = 0,
    this.total = 0,
    this.pending = 0,
    this.lastCompletedAt,
    this.error,
  });

  /** 是否允许后台执行和自动恢复。 */
  final bool enabled;

  /** 当前备份阶段。 */
  final DataBackupPhase phase;

  /** 本轮全量核对已处理的视频数。 */
  final int processed;

  /** 本轮启动时读取到的主库视频总数。 */
  final int total;

  /** 等待增量同步的视频数。 */
  final int pending;

  /** 最近一次完整核对完成时间。 */
  final DateTime? lastCompletedAt;

  /** 最近一次失败摘要；不得包含媒体路径或标签内容。 */
  final String? error;
}

/** 用户显式执行的视频依赖备份完整性检查结果。 */
class DataBackupIntegrityReport {
  const DataBackupIntegrityReport({
    required this.checkedAt,
    required this.sqliteHealthy,
    required this.backupRecords,
    required this.currentVideos,
    required this.invalidPayloads,
    required this.missingFingerprints,
    required this.missingCurrentSnapshots,
    required this.staleCurrentSnapshots,
    required this.ambiguousFingerprints,
    required this.recoverableSnapshots,
  });

  /** 检查完成时间。 */
  final DateTime checkedAt;

  /** SQLite `quick_check` 是否返回 `ok`。 */
  final bool sqliteHealthy;

  /** 独立备份库中的快照总数。 */
  final int backupRecords;

  /** 检查时主媒体库中的稳定视频身份总数。 */
  final int currentVideos;

  /** 无法解析或缺少必要结构的快照 JSON 数量。 */
  final int invalidPayloads;

  /** 指纹为空、无法参与安全恢复的快照数量。 */
  final int missingFingerprints;

  /** 当前主库视频尚未形成快照的数量。 */
  final int missingCurrentSnapshots;

  /** 当前主库依赖内容与快照不一致的数量。 */
  final int staleCurrentSnapshots;

  /** 同一指纹对应多条快照、因此只能拒绝自动恢复的指纹数量。 */
  final int ambiguousFingerprints;

  /** 当前主库没有同 videoId，但仍可供未来重建身份恢复的快照数量。 */
  final int recoverableSnapshots;

  /** 是否不存在影响备份可用性或当前数据覆盖的问题。 */
  bool get isHealthy =>
      sqliteHealthy &&
      invalidPayloads == 0 &&
      missingFingerprints == 0 &&
      missingCurrentSnapshots == 0 &&
      staleCurrentSnapshots == 0;
}

/** 自动恢复时需要重新建立的非 folder 标签关联。 */
class DataBackupTagLink {
  const DataBackupTagLink({
    required this.tag,
    required this.source,
    required this.locked,
    this.group,
  });

  /** 标签完整定义；manual/rule/import 等来源不能仅按名称恢复。 */
  final TagItem tag;

  /** 标签组定义；自定义分组在主库重建后也需要恢复。 */
  final TagGroup? group;

  /** 视频与标签关联的真实来源。 */
  final TagSource source;

  /** 自动流程不得静默删除的锁定标记。 */
  final bool locked;
}

/** fingerprint 唯一匹配后可应用到新扫描视频的用户依赖快照。 */
class DataBackupRestoreRecord {
  const DataBackupRestoreRecord({
    required this.videoId,
    required this.mediaFingerprint,
    required this.isFavorite,
    required this.playbackPosition,
    required this.playbackDuration,
    required this.playbackCompleted,
    required this.links,
    this.lastPlayedAt,
    this.playbackPositionUpdatedAt,
  });

  /** 快照原有稳定身份；恢复前必须确认主库没有同 videoId 冲突。 */
  final String videoId;

  /** 路径无关媒体指纹；只有备份侧和扫描侧都唯一时才允许恢复。 */
  final String mediaFingerprint;

  final bool isFavorite;
  final DateTime? lastPlayedAt;
  final Duration playbackPosition;
  final Duration playbackDuration;
  final bool playbackCompleted;
  final DateTime? playbackPositionUpdatedAt;
  final List<DataBackupTagLink> links;
}
