import '../media/media_details_service.dart';
import '../media/thumbnail_service.dart';
import 'video_similarity_scan_controller.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放器会话的后台媒体让渡门。
 *
 * 相似视觉扫描、缩略图和媒体详情共用同一个播放优先级边界；进入时只暂停能暂停的
 * 后续队列，退出时按进入前快照恢复，不能把用户原本手动暂停的后台服务误恢复。
 */
class LibraryPlaybackBackgroundGate {
  LibraryPlaybackBackgroundGate({
    required ThumbnailService thumbnailService,
    required MediaDetailsService? mediaDetailsService,
    required VideoSimilarityScanController? similarityScanController,
  })  : _thumbnailService = thumbnailService,
        _mediaDetailsService = mediaDetailsService,
        _similarityScanController = similarityScanController;

  final ThumbnailService _thumbnailService;
  final MediaDetailsService? _mediaDetailsService;
  final VideoSimilarityScanController? _similarityScanController;
  var _thumbnailWasPaused = false;
  var _mediaDetailsWasPaused = false;
  var _entered = false;

  void enter() {
    if (_entered) {
      return;
    }
    _entered = true;
    _similarityScanController?.setPlaybackActive(true);
    _mediaDetailsWasPaused = _mediaDetailsService?.isPaused ?? false;
    if (!_mediaDetailsWasPaused) {
      _mediaDetailsService?.pause();
    }
    _thumbnailWasPaused = _thumbnailService.isPaused;
    if (!_thumbnailWasPaused) {
      _thumbnailService.pause(allowPriorityRequests: true);
    }
  }

  void restore() {
    if (!_entered) {
      return;
    }
    if (!_thumbnailWasPaused) {
      _thumbnailService.resume();
    }
    if (!_mediaDetailsWasPaused) {
      _mediaDetailsService?.resume();
    }
    _similarityScanController?.setPlaybackActive(false);
    _entered = false;
  }
}
