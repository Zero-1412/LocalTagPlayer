import 'video_item.dart';

// ignore_for_file: slash_for_doc_comments

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
