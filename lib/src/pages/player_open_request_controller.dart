part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 播放页 open 请求队列协调器。
 *
 * 该 controller 只维护“最新待打开路径、是否有 drain worker、是否展示打开中遮罩”，不直接调用
 * `Player.open`，因此不会改变 PlayerBackend/mpv 行为。
 */
class PlayerOpenRequestController {
  /** 最新一次请求打开的视频路径。 */
  String? _pendingOpenPath;

  /** 是否已有 worker 正在串行处理 open 请求。 */
  var _workerRunning = false;

  /** 页面是否应展示打开中遮罩。 */
  var isOpening = false;

  /** 当前是否还有待处理路径。 */
  bool get hasPending => _pendingOpenPath != null;

  /**
   * 记录一次打开请求。
   *
   * 返回 `true` 表示调用方需要启动 drain worker；返回 `false` 表示已有 worker 会消费最新路径。
   */
  bool request(String path) {
    _pendingOpenPath = path;
    if (_workerRunning) {
      return false;
    }
    return true;
  }

  /**
   * 标记 drain worker 开始运行。
   */
  void beginDrain() {
    _workerRunning = true;
    isOpening = true;
  }

  /**
   * 取出并清空当前待打开路径。
   *
   * open 请求只保留最新路径，快速跳转时旧路径会被覆盖，避免排队打开过时视频。
   */
  String? takePendingPath() {
    final path = _pendingOpenPath;
    _pendingOpenPath = null;
    return path;
  }

  /**
   * 标记 drain worker 完成。
   *
   * [keepOpening] 为 true 时说明 finally 阶段已经发现新请求，遮罩保持打开直到下一轮 drain。
   */
  void finishDrain({required bool keepOpening}) {
    _workerRunning = false;
    isOpening = keepOpening;
  }

  /**
   * 页面销毁时取消尚未处理的 open 请求。
   */
  void cancel() {
    _pendingOpenPath = null;
    _workerRunning = false;
    isOpening = false;
  }
}
