import 'dart:async';

// ignore_for_file: slash_for_doc_comments

/** 判断普通播放器控制条当前是否允许自动隐藏。 */
bool playerControlsShouldAutoHide({
  required bool settingsOpen,
  required bool pointerInControlBar,
}) {
  return !settingsOpen && !pointerInControlBar;
}

/**
 * 播放器主控制条与短时快捷键反馈的纯 Dart 状态 owner。
 *
 * controller 只拥有两只可取消 Timer 和可序列化状态，不持有 Widget、`BuildContext`、
 * Focus、Overlay、Route 或播放器资源。图标使用泛型，由 presentation 注入具体类型。
 */
class PlayerInteractionStateController<TIcon> {
  /**
   * 创建交互状态 owner。
   *
   * [onChanged] 只通知 presentation 重建，不携带上下文；[initialFeedbackIcon] 为尚未展示
   * 反馈时的安全占位。
   */
  PlayerInteractionStateController({
    required this.onChanged,
    required TIcon initialFeedbackIcon,
  }) : feedbackIcon = initialFeedbackIcon;

  /** 状态变化后的轻量页面刷新回调。 */
  final void Function() onChanged;

  /** 控制条自动隐藏 Timer。 */
  Timer? _controlsHideTimer;

  /** 快捷键反馈自动隐藏 Timer。 */
  Timer? _feedbackHideTimer;

  /** dispose 后拒绝 Timer 和页面回调。 */
  var _disposed = false;

  /** 主控制条当前是否可见。 */
  var controlsVisible = true;

  /** 鼠标是否停留在底部进度与控制区。 */
  var pointerInControlBar = false;

  /** 设置浮层是否锁定主控制条。 */
  var settingsOpen = false;

  /** 快捷键反馈是否可见。 */
  var feedbackVisible = false;

  /** 当前快捷键反馈文案。 */
  String? feedbackLabel;

  /** 当前快捷键反馈图标。 */
  TIcon feedbackIcon;

  /** 当前反馈是否使用左上角 seek 文字水印。 */
  var feedbackIsSeekWatermark = false;

  /**
   * 立即显示控制条，并在允许时重新开始自动隐藏倒计时。
   *
   * 重复调用会取消旧 Timer，保证快速鼠标移动只保留最新隐藏意图。
   */
  void showControls({
    Duration hideAfter = const Duration(seconds: 3),
  }) {
    if (_disposed) return;
    _controlsHideTimer?.cancel();
    final changed = !controlsVisible;
    controlsVisible = true;
    if (changed) _publish();
    if (!playerControlsShouldAutoHide(
      settingsOpen: settingsOpen,
      pointerInControlBar: pointerInControlBar,
    )) {
      return;
    }
    _controlsHideTimer = Timer(hideAfter, () {
      if (_disposed ||
          !playerControlsShouldAutoHide(
            settingsOpen: settingsOpen,
            pointerInControlBar: pointerInControlBar,
          )) {
        return;
      }
      controlsVisible = false;
      _publish();
    });
  }

  /** 更新控制条悬停状态；进入时锁定可见，离开时重新开始自动隐藏倒计时。 */
  void setPointerInControlBar(
    bool inside, {
    Duration hideAfter = const Duration(seconds: 3),
  }) {
    if (_disposed || pointerInControlBar == inside) return;
    pointerInControlBar = inside;
    if (inside) {
      _controlsHideTimer?.cancel();
      final changed = !controlsVisible;
      controlsVisible = true;
      if (changed) _publish();
      return;
    }
    showControls(hideAfter: hideAfter);
  }

  /** 打开设置浮层并取消自动隐藏，确保确认/撤销入口持续可见。 */
  void openSettings() {
    if (_disposed || settingsOpen) return;
    _controlsHideTimer?.cancel();
    settingsOpen = true;
    controlsVisible = true;
    _publish();
  }

  /** 关闭设置浮层并恢复统一自动隐藏规则。 */
  void closeSettings({
    Duration hideAfter = const Duration(seconds: 3),
  }) {
    if (_disposed || !settingsOpen) return;
    settingsOpen = false;
    _publish();
    showControls(hideAfter: hideAfter);
  }

  /** 显示一次短时快捷键反馈；更新反馈会覆盖旧 Timer。 */
  void showFeedback({
    required String label,
    required TIcon icon,
    bool isSeekWatermark = false,
    Duration visibleFor = const Duration(milliseconds: 850),
  }) {
    if (_disposed) return;
    _feedbackHideTimer?.cancel();
    feedbackLabel = label;
    feedbackIcon = icon;
    feedbackIsSeekWatermark = isSeekWatermark;
    feedbackVisible = true;
    _publish();
    _feedbackHideTimer = Timer(visibleFor, () {
      if (_disposed || !feedbackVisible) return;
      feedbackVisible = false;
      _publish();
    });
  }

  /** 释放两类短时 UI Timer；重复调用保持幂等。 */
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controlsHideTimer?.cancel();
    _feedbackHideTimer?.cancel();
  }

  /** 仅在有效生命周期内发布状态变化。 */
  void _publish() {
    if (!_disposed) onChanged();
  }
}
