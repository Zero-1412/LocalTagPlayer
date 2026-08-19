#ifndef RUNNER_PLAYER_QA_KEYBOARD_QPC_EVIDENCE_H_
#define RUNNER_PLAYER_QA_KEYBOARD_QPC_EVIDENCE_H_

#include <windows.h>

#include <string>

/**
 * Debug QA 专用的 Flutter view 键盘消息观察器。
 *
 * 它只在显式环境变量开启时记录 J/L 的匿名动作、消息阶段、与桌面探针一致的 QPC
 * 时间及用于事件窗口筛选的 UTC 侧车。主观察目标是 FLUTTERVIEW；顶层 runner 仅作为
 * Windows 消息路由旁路，最终仍必须由 PlayerPage 的匿名键盘回执证明事件进入 Flutter
 * Focus 链。不记录原始按键、媒体标识、路径或画面；正式产品不创建任何输出文件。
 */
class PlayerQaKeyboardQpcEvidence {
 public:
  explicit PlayerQaKeyboardQpcEvidence(HWND flutter_view_window);
  ~PlayerQaKeyboardQpcEvidence();

  /** 顶层 runner 已把消息交给 Flutter 前的旁路；只在 Debug QA 环境记录 J/L。 */
  void ObserveTopLevelWindowMessage(UINT message, WPARAM wparam,
                                    LPARAM lparam) const;

  PlayerQaKeyboardQpcEvidence(const PlayerQaKeyboardQpcEvidence&) = delete;
  PlayerQaKeyboardQpcEvidence& operator=(
      const PlayerQaKeyboardQpcEvidence&) = delete;

 private:
  static LRESULT CALLBACK SubclassProc(HWND window,
                                       UINT message,
                                       WPARAM wparam,
                                       LPARAM lparam,
                                       UINT_PTR subclass_id,
                                       DWORD_PTR reference_data);
  void RecordKeyboardMessage(UINT message, WPARAM wparam, LPARAM lparam) const;
  void AppendLine(const std::string& line) const;

  HWND flutter_view_window_ = nullptr;
  HWND runner_window_ = nullptr;
  bool active_ = false;
  bool flutter_view_installed_ = false;
  bool runner_installed_ = false;
  wchar_t output_path_[MAX_PATH] = {};
  /** subclass 与顶层 runner 可能同时看到同一条消息；用原始 lParam 窗口去重。 */
  mutable UINT last_message_ = 0;
  mutable WPARAM last_wparam_ = 0;
  mutable LPARAM last_lparam_ = 0;
  mutable long long last_qpc_us_ = 0;
};

#endif  // RUNNER_PLAYER_QA_KEYBOARD_QPC_EVIDENCE_H_
