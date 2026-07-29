import '../../../models/library_scan_models.dart';
import '../../../services/media/media_details_service.dart';

// ignore_for_file: slash_for_doc_comments

/** 把后台媒体解析快照转换为结果区的稳定短文案。 */
String libraryMediaImportProgressLabel(MediaDetailsProgress progress) {
  final percent = (progress.fraction * 100).floor();
  final parts = <String>[
    '媒体解析 ${progress.processed}/${progress.total}',
    '$percent%',
  ];
  if (progress.isPaused) {
    parts.add('已暂停');
    return parts.join(' · ');
  }
  final speed = progress.itemsPerSecond;
  if (speed != null && speed > 0) {
    parts.add(
        speed >= 10 ? '${speed.round()}个/秒' : '${speed.toStringAsFixed(1)}个/秒');
  }
  final remaining = progress.estimatedRemaining;
  if (remaining != null) {
    parts.add('剩余${_libraryImportDurationLabel(remaining)}');
  }
  return parts.join(' · ');
}

/** 把目录发现、指纹校验和提交进度压缩为结果区短文案。 */
String libraryScanProgressLabel(LibraryScanProgress? progress) {
  if (progress == null) {
    return '正在发现视频…';
  }
  if (progress.phase == LibraryScanPhase.discovering) {
    return progress.discovered == 0
        ? '正在发现视频…'
        : '正在发现视频 · 已找到 ${progress.discovered} 个';
  }
  final total = progress.total ?? progress.discovered;
  final percent = ((progress.fraction ?? 0) * 100).floor();
  final parts = <String>[
    progress.phase == LibraryScanPhase.fingerprinting
        ? '校验文件 ${progress.processed}/$total'
        : '提交索引 ${progress.processed}/$total',
    '$percent%',
  ];
  if (progress.isPaused) {
    parts.add('播放期间已暂停');
    return parts.join(' · ');
  }
  final speed = progress.itemsPerSecond;
  if (speed != null && speed > 0) {
    parts.add(
        speed >= 10 ? '${speed.round()}个/秒' : '${speed.toStringAsFixed(1)}个/秒');
  }
  final remaining = progress.estimatedRemaining;
  if (remaining != null && remaining > Duration.zero) {
    parts.add('剩余${_libraryImportDurationLabel(remaining)}');
  }
  return parts.join(' · ');
}

/** 把 ETA 压缩为适合当前筛选结果行的一到两个时间单位。 */
String _libraryImportDurationLabel(Duration duration) {
  final seconds = duration.inSeconds.clamp(1, 359999);
  if (seconds < 60) {
    return '$seconds秒';
  }
  final minutes = seconds ~/ 60;
  if (minutes < 60) {
    final remainder = seconds % 60;
    return remainder == 0 ? '$minutes分钟' : '$minutes分$remainder秒';
  }
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours小时' : '$hours小时$remainder分';
}
