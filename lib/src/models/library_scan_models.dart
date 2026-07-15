import 'video_item.dart';

// ignore_for_file: slash_for_doc_comments

/** 媒体库扫描在用户可感知路径上的阶段。 */
enum LibraryScanPhase {
  /** 递归枚举目录并收集视频候选；总量在阶段结束前未知。 */
  discovering,

  /** 对已经发现的候选读取 stat，并复用或计算轻量 fingerprint。 */
  fingerprinting,

  /** Dart Application 合并稳定身份并提交 SQLite 差量。 */
  committing,
}

/** 扫描阶段进度回调；实现不得携带路径、标题或标签内容。 */
typedef LibraryScanProgressCallback = void Function(
  LibraryScanProgress progress,
);

/**
 * 一次只读扫描或应用提交的不可变进度快照。
 *
 * 目录发现阶段不伪造百分比；发现结束后 [total] 已确定，指纹与提交阶段才显示
 * 确定型进度。播放期间 [isPaused] 为 true，扫描保留当前位置但停止继续读取磁盘。
 */
class LibraryScanProgress {
  const LibraryScanProgress({
    required this.generationId,
    required this.phase,
    required this.processed,
    required this.discovered,
    this.total,
    this.itemsPerSecond,
    this.estimatedRemaining,
    this.isPaused = false,
  });

  /** 当前扫描代次，防止旧任务覆盖新 UI。 */
  final int generationId;

  /** 当前扫描阶段。 */
  final LibraryScanPhase phase;

  /** 当前阶段已处理数量。 */
  final int processed;

  /** 本轮截至当前已经发现的视频候选数量。 */
  final int discovered;

  /** 当前阶段总数；目录发现期间保持 null。 */
  final int? total;

  /** 当前阶段最近窗口的平滑速度。 */
  final double? itemsPerSecond;

  /** 当前阶段按平滑速度估算的剩余时间。 */
  final Duration? estimatedRemaining;

  /** 是否为正在播放的视频主动让出扫描磁盘读取。 */
  final bool isPaused;

  /** 只有已知总量的阶段才返回确定型进度。 */
  double? get fraction {
    final target = total;
    if (target == null || target <= 0) {
      return null;
    }
    return (processed / target).clamp(0, 1);
  }

  /** 复制当前快照并更新播放让盘状态。 */
  LibraryScanProgress copyWith({bool? isPaused}) => LibraryScanProgress(
        generationId: generationId,
        phase: phase,
        processed: processed,
        discovered: discovered,
        total: total,
        itemsPerSecond: itemsPerSecond,
        estimatedRemaining: estimatedRemaining,
        isPaused: isPaused ?? this.isPaused,
      );
}

/**
 * 应用层提交扫描差量后的不可变结果。
 *
 * [changedVideos] 供 UI 做差量失效，[probeCandidates] 只包含新增或内容变化的视频；
 * 两者均引用事务提交成功后的稳定 [VideoItem]，不包含已取消代次的部分结果。
 */
class LibraryScanCommitResult {
  LibraryScanCommitResult({
    required this.generationId,
    required this.addedCount,
    required this.modifiedCount,
    required this.missingCount,
    required this.relinkedCount,
    required Iterable<VideoItem> changedVideos,
    required Iterable<VideoItem> probeCandidates,
    this.cancelled = false,
  })  : changedVideos = List<VideoItem>.unmodifiable(changedVideos),
        probeCandidates = List<VideoItem>.unmodifiable(probeCandidates);

  /** 扫描代次。 */
  final int generationId;
  /** 新建稳定记录数量。 */
  final int addedCount;
  /** 已有路径内容或索引发生变化的数量。 */
  final int modifiedCount;
  /** 本轮新标记为 missing 的数量。 */
  final int missingCount;
  /** 通过唯一 fingerprint 保留稳定身份的移动数量。 */
  final int relinkedCount;
  /** 事务提交后需要刷新 UI 的稳定对象。 */
  final List<VideoItem> changedVideos;
  /** 可送入缩略图或 MediaProbe 队列的新增或内容变化对象。 */
  final List<VideoItem> probeCandidates;
  /** 代次是否在提交前取消。 */
  final bool cancelled;

  /** 创建不产生数据库或 UI 副作用的取消结果。 */
  factory LibraryScanCommitResult.cancelled(int generationId) =>
      LibraryScanCommitResult(
        generationId: generationId,
        addedCount: 0,
        modifiedCount: 0,
        missingCount: 0,
        relinkedCount: 0,
        changedVideos: const <VideoItem>[],
        probeCandidates: const <VideoItem>[],
        cancelled: true,
      );
}
