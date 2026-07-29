import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 合并窗口拖动期间的网格宽度变化。
 *
 * 该轻量协调器只持有响应式布局宽度和短计时器，不读取视频、筛选或缩略图状态；
 * 调用方在稳定宽度提交后决定是否重建。
 */
class LibraryVideoGridResizeCoordinator {
  double? _settledWidth;
  double? _pendingWidth;
  Timer? _settleTimer;

  /**
   * 返回当前稳定宽度，并在连续变化停止后只通知一次。
   *
   * [onSettled] 只表示布局快照已更新，不携带筛选或结果数据。
   */
  double resolve(
    double measuredWidth, {
    required VoidCallback onSettled,
  }) {
    final normalizedWidth =
        measuredWidth.isFinite && measuredWidth > 0 ? measuredWidth : 1.0;
    final settledWidth = _settledWidth;
    if (settledWidth == null) {
      _settledWidth = normalizedWidth;
      return normalizedWidth;
    }
    if ((normalizedWidth - settledWidth).abs() <= 0.5) {
      _pendingWidth = null;
      _settleTimer?.cancel();
      return settledWidth;
    }
    if (_pendingWidth == null ||
        (normalizedWidth - _pendingWidth!).abs() > 0.5) {
      _pendingWidth = normalizedWidth;
      _settleTimer?.cancel();
      _settleTimer = Timer(libraryResultsResizeSettleDuration, () {
        final targetWidth = _pendingWidth;
        if (targetWidth == null) {
          return;
        }
        _settledWidth = targetWidth;
        _pendingWidth = null;
        onSettled();
      });
    }
    return settledWidth;
  }

  /** 页面销毁时取消仍未提交的宽度计时器。 */
  void dispose() {
    _settleTimer?.cancel();
  }
}
