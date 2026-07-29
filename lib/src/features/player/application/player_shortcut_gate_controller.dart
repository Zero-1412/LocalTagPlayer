// ignore_for_file: slash_for_doc_comments

/**
 * 播放器快捷键暂停深度与纯资格判定 owner。
 *
 * controller 不读取 Focus、Keyboard、Route 或 Overlay；presentation 先采集这些环境事实，
 * 再交给本类统一判断，避免处理入口和焦点恢复入口复制不同门禁。
 */
class PlayerShortcutGateController {
  /** 原生文件对话框等显式暂停操作的嵌套深度。 */
  var _suspensionDepth = 0;

  /** manual 标签编辑器是否正在占用 Escape 与键盘输入。 */
  var _manualTagEditorOpen = false;

  /** 当前是否存在显式或标签编辑暂停。 */
  bool get isExplicitlySuspended =>
      _suspensionDepth > 0 || _manualTagEditorOpen;

  /** 进入一层可嵌套快捷键暂停。 */
  void beginSuspension() {
    _suspensionDepth++;
  }

  /** 退出一层暂停；多余结束调用保持在零，避免错误恢复负深度。 */
  void endSuspension() {
    if (_suspensionDepth > 0) _suspensionDepth--;
  }

  /** 同步 manual 标签编辑生命周期。 */
  void setManualTagEditorOpen(bool value) {
    _manualTagEditorOpen = value;
  }

  /** 判断当前键盘事件是否允许进入播放器命令匹配。 */
  bool canHandle({
    required bool settingsOpen,
    required bool focusEditable,
    required bool focusOnDifferentRoute,
    required bool blockingOverlay,
  }) {
    return !isExplicitlySuspended &&
        !settingsOpen &&
        !focusEditable &&
        !focusOnDifferentRoute &&
        !blockingOverlay;
  }

  /** 判断下一帧是否允许把焦点交还播放器 FocusNode。 */
  bool canRestoreFocus({
    required bool settingsOpen,
    required bool focusOnDifferentRoute,
  }) {
    return !isExplicitlySuspended && !settingsOpen && !focusOnDifferentRoute;
  }
}
