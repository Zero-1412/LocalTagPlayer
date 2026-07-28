// ignore_for_file: slash_for_doc_comments

/**
 * 同一播放器实例上最近一次滤镜属性事务的终态。
 */
enum PlayerFilterTransactionPhase {
  idle,
  applied,
  rolledBack,
  rollbackFailed,
}

/**
 * 最近一次滤镜属性事务的路径无关诊断快照。
 *
 * 快照只保存受控标签、属性名与结果，不保存属性值，避免未来滤镜参数包含本地资源路径
 * 时被复制到诊断日志。
 */
class PlayerFilterTransactionSnapshot {
  const PlayerFilterTransactionSnapshot({
    required this.supported,
    required this.sequence,
    required this.label,
    required this.phase,
    required this.requestedPropertyCount,
    required this.verifiedPropertyCount,
    required this.mismatchedProperties,
    required this.rollbackAttempted,
    required this.rollbackVerified,
    required this.failureCode,
    required this.completedAt,
    required this.totalDuration,
  });

  /** 后端没有接入滤镜事务时使用的显式占位快照。 */
  const PlayerFilterTransactionSnapshot.unsupported()
      : supported = false,
        sequence = 0,
        label = 'unsupported',
        phase = PlayerFilterTransactionPhase.idle,
        requestedPropertyCount = 0,
        verifiedPropertyCount = 0,
        mismatchedProperties = const <String>[],
        rollbackAttempted = false,
        rollbackVerified = false,
        failureCode = null,
        completedAt = null,
        totalDuration = null;

  /** 当前服务是否支持写前快照、读回验证和失败回滚。 */
  final bool supported;

  /** 当前播放器服务内递增的匿名事务序号。 */
  final int sequence;

  /** 由调用方提供的受控用途标签，不得包含媒体路径或用户输入。 */
  final String label;

  /** 最近事务最终处于应用成功、已回滚或回滚失败。 */
  final PlayerFilterTransactionPhase phase;

  /** 本次请求包含的唯一属性数量。 */
  final int requestedPropertyCount;

  /** 写入后与目标一致的属性数量。 */
  final int verifiedPropertyCount;

  /** 首次读回不一致的属性名；不包含属性值。 */
  final List<String> mismatchedProperties;

  /** 是否因写入异常或读回不一致尝试恢复旧快照。 */
  final bool rollbackAttempted;

  /** 旧快照是否可完整读取、写回并再次验证。 */
  final bool rollbackVerified;

  /** 路径无关的稳定失败分类码。 */
  final String? failureCode;

  /** 最近事务完成时间。 */
  final DateTime? completedAt;

  /** 捕获旧值、提交、验证和必要回滚的总耗时。 */
  final Duration? totalDuration;
}
