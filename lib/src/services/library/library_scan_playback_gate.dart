// ignore_for_file: slash_for_doc_comments

/**
 * 播放器与目录扫描之间的最小资源闸门。
 *
 * 仅当扫描正在运行且此前未由用户暂停时，才在播放动作前暂停只读扫描，并在动作结束后
 * 恢复；异常和提前返回同样经过 finally，避免扫描永久停住或覆盖用户手动暂停状态。
 */
class LibraryScanPlaybackGate {
  const LibraryScanPlaybackGate();

  /**
   * 在必要的扫描让盘窗口中执行 [action]。
   *
   * [setPaused] 由 Repository 实现，页面不知道 Rust/Dart 后端细节；[onPauseChanged]
   * 只负责同步结果区反馈，不改变扫描状态本身。
   */
  Future<T> run<T>({
    required bool scanActive,
    required bool scanAlreadyPaused,
    required Future<void> Function(bool paused) setPaused,
    required Future<T> Function() action,
    void Function(bool paused)? onPauseChanged,
  }) async {
    final shouldYield = scanActive && !scanAlreadyPaused;
    if (shouldYield) {
      onPauseChanged?.call(true);
      await setPaused(true);
    }
    try {
      return await action();
    } finally {
      if (shouldYield) {
        await setPaused(false);
        onPauseChanged?.call(false);
      }
    }
  }
}
