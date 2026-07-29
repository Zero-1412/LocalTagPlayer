// ignore_for_file: slash_for_doc_comments

/** 同一次页面选择捕获的 stable ID 与 mutable path。 */
typedef PlayerOpenTarget = ({String videoId, String path});

/**
 * 一次不可变的播放器打开意图。
 *
 * [revision] 用于拒绝旧异步结果，[videoId] 保持稳定媒体身份，[path] 只作为本次后端
 * `openPath` 的可变位置快照。三者必须在同一次请求中捕获。
 */
class PlayerOpenRequest {
  /** 创建一次已编号的打开请求。 */
  const PlayerOpenRequest({
    required this.revision,
    required this.videoId,
    required this.path,
  });

  /** latest-only 请求代次。 */
  final int revision;

  /** 当前媒体的 stable database identity。 */
  final String videoId;

  /** 发起请求时的 mutable path 快照。 */
  final String path;
}

/**
 * 可以展示或重试的安全打开错误快照。
 *
 * 错误只保存路径无关类型码；路径仅用于应用内重试，不能进入可复制诊断文本。
 */
class PlayerOpenFailure {
  /** 创建一次与稳定媒体身份绑定的失败快照。 */
  const PlayerOpenFailure({
    required this.videoId,
    required this.path,
    required this.code,
  });

  /** 失败媒体的 stable database identity。 */
  final String videoId;

  /** 失败时的 mutable path 快照。 */
  final String path;

  /** 不包含本地路径的安全错误类型。 */
  final String code;
}

/**
 * 播放页 latest-only 打开请求的唯一应用状态 owner。
 *
 * controller 不调用 `PlayerService` 或 `PlayerBackend`，只管理请求代次、drain worker
 * 状态和安全失败快照。旧 open Future 即使稍后完成，也不能覆盖更新的 stable-ID 意图。
 */
class PlayerOpenRequestController {
  /** 单调递增请求代次；立即失败和取消同样推进，确保旧 Future 失效。 */
  var _revision = 0;

  /** 尚未被 drain worker 取出的最新请求。 */
  PlayerOpenRequest? _pending;

  /** 是否已有 worker 正在串行处理 open 请求。 */
  var _workerRunning = false;

  /** 页面是否应展示打开中遮罩。 */
  var isOpening = false;

  /** 当前可以展示或重试的失败快照。 */
  PlayerOpenFailure? _failure;

  /** 当前是否还有待处理请求。 */
  bool get hasPending => _pending != null;

  /** 当前是否有需要用户重试或跳过的稳定打开错误。 */
  bool get hasFailure => _failure != null;

  /** 最近失败的视频路径，仅在播放器页生命周期内保留。 */
  String? get failedPath => _failure?.path;

  /** 最近失败视频的 stable database identity。 */
  String? get failedVideoId => _failure?.videoId;

  /** 不包含本地路径的安全错误类型。 */
  String? get failureCode => _failure?.code;

  /**
   * 记录一次打开请求。
   *
   * 返回 true 表示调用方需要启动 drain worker；已有 worker 时只覆盖 pending 请求，
   * worker 会在当前不可中断步骤结束后消费最新代次。
   */
  bool request(PlayerOpenTarget target) {
    clearFailure();
    _pending = PlayerOpenRequest(
      revision: ++_revision,
      videoId: target.videoId,
      path: target.path,
    );
    return !_workerRunning;
  }

  /**
   * 记录未进入 worker 的即时失败。
   *
   * missing 等前置拒绝必须推进代次并清空 pending，使仍在返回途中的旧 open 结果失效。
   */
  void markImmediateFailure(
    PlayerOpenTarget target, {
    required String code,
  }) {
    _revision++;
    _pending = null;
    _failure = PlayerOpenFailure(
      videoId: target.videoId,
      path: target.path,
      code: code,
    );
  }

  /**
   * 接受当前请求的最终失败。
   *
   * 返回 false 表示请求已被更新 stable-ID 意图取代，页面不得展示旧错误。
   */
  bool markFailure(
    PlayerOpenRequest request, {
    required String code,
  }) {
    if (hasSuperseded(request)) {
      return false;
    }
    _failure = PlayerOpenFailure(
      videoId: request.videoId,
      path: request.path,
      code: code,
    );
    return true;
  }

  /**
   * 接受当前请求的成功结果。
   *
   * 返回 false 表示结果已经过期；调用方不能据此发布 opened path 或恢复位置。
   */
  bool markSuccess(PlayerOpenRequest request) {
    if (hasSuperseded(request)) {
      return false;
    }
    clearFailure();
    return true;
  }

  /** 清理当前打开错误，但不改变请求代次。 */
  void clearFailure() {
    _failure = null;
  }

  /** 重新排队最近失败的视频，并复用同一 latest-only worker 语义。 */
  bool retryFailure() {
    final failure = _failure;
    if (failure == null) {
      return false;
    }
    return request((videoId: failure.videoId, path: failure.path));
  }

  /** 标记 drain worker 开始运行。 */
  void beginDrain() {
    _workerRunning = true;
    isOpening = true;
  }

  /**
   * 取出并清空当前待打开请求。
   *
   * pending 只保留最新代次，快速跳转不会形成逐路径积压。
   */
  PlayerOpenRequest? takePending() {
    final request = _pending;
    _pending = null;
    return request;
  }

  /** 判断异步结果是否已被更新请求、即时失败或取消取代。 */
  bool hasSuperseded(PlayerOpenRequest request) =>
      request.revision != _revision;

  /**
   * 标记 drain worker 完成。
   *
   * [keepOpening] 为 true 时说明 finally 阶段已有新请求，遮罩保持到下一轮 drain。
   */
  void finishDrain({required bool keepOpening}) {
    _workerRunning = false;
    isOpening = keepOpening;
  }

  /** 页面销毁时推进代次并取消尚未处理的请求与失败反馈。 */
  void cancel() {
    _revision++;
    _pending = null;
    _workerRunning = false;
    isOpening = false;
    clearFailure();
  }
}
