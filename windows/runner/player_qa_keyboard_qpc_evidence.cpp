#include "player_qa_keyboard_qpc_evidence.h"

#include <commctrl.h>

#include <chrono>
#include <string>

namespace {

constexpr UINT_PTR kSubclassId = 0x4C545051;  // LTPQ
constexpr UINT_PTR kRunnerSubclassId = 0x4C545052;  // LTPR

bool IsEnabledQaEnvironment() {
#if !defined(_DEBUG)
  return false;
#else
  wchar_t enabled[8] = {};
  const DWORD length = GetEnvironmentVariableW(
      L"LOCAL_TAG_PLAYER_NATIVE_QPC_INPUT_QA", enabled,
      static_cast<DWORD>(std::size(enabled)));
  return length == 1 && enabled[0] == L'1';
#endif
}

bool ReadOutputPath(wchar_t* output_path, DWORD capacity) {
  if (output_path == nullptr || capacity < 2) {
    return false;
  }
  wchar_t output_root[MAX_PATH] = {};
  const DWORD length = GetEnvironmentVariableW(
      L"LOCAL_TAG_PLAYER_PIXEL_OUTPUT", output_root,
      static_cast<DWORD>(std::size(output_root)));
  if (length == 0 || length >= std::size(output_root)) {
    return false;
  }
  const std::wstring output_file =
      std::wstring(output_root) + L"\\native-keyboard-qpc-events.jsonl";
  if (output_file.size() + 1 > capacity) {
    return false;
  }
  wcsncpy_s(output_path, capacity, output_file.c_str(), _TRUNCATE);
  return true;
}

const char* ActionForVirtualKey(WPARAM virtual_key) {
  switch (virtual_key) {
    case 'L':
      return "forward";
    case 'J':
      return "backward";
    default:
      return nullptr;
  }
}

long long QueryPerformanceMicroseconds() {
  LARGE_INTEGER counter = {};
  LARGE_INTEGER frequency = {};
  if (!QueryPerformanceCounter(&counter) ||
      !QueryPerformanceFrequency(&frequency) || frequency.QuadPart <= 0) {
    return 0;
  }
  return static_cast<long long>(
      static_cast<long double>(counter.QuadPart) * 1000000.0L /
      static_cast<long double>(frequency.QuadPart));
}

long long WallClockMicroseconds() {
  const auto now = std::chrono::system_clock::now().time_since_epoch();
  return std::chrono::duration_cast<std::chrono::microseconds>(now).count();
}

}  // namespace

PlayerQaKeyboardQpcEvidence::PlayerQaKeyboardQpcEvidence(
    HWND flutter_view_window)
    : flutter_view_window_(flutter_view_window) {
  if (!IsEnabledQaEnvironment() || flutter_view_window_ == nullptr ||
      !ReadOutputPath(output_path_, static_cast<DWORD>(std::size(output_path_)))) {
    return;
  }
  active_ = true;
  // 必须观察实际取得键盘焦点的 FLUTTERVIEW 子窗口，而不是仅观察父 HWND；否则会把
  // 前台窗口状态误当作实体键盘已送达 Flutter 的证据。部分 Flutter Windows 消息路由
  // 会先把 WM_KEY* 交给顶层 runner，因此同时观察父窗口；最终仍由 PlayerPage 回执
  // 过滤“只到 native、未到 Focus 链”的输入。
  flutter_view_installed_ =
      SetWindowSubclass(flutter_view_window_, SubclassProc, kSubclassId,
                        reinterpret_cast<DWORD_PTR>(this)) != FALSE;
  runner_window_ = GetParent(flutter_view_window_);
  if (runner_window_ != nullptr && runner_window_ != flutter_view_window_) {
    runner_installed_ =
        SetWindowSubclass(runner_window_, SubclassProc, kRunnerSubclassId,
                          reinterpret_cast<DWORD_PTR>(this)) != FALSE;
  }
  // 顶层旁路由 FlutterWindow 自身提供；即使 subclass 在某些窗口组合下失败，活动
  // Debug QA 进程仍有一条可审计的 native 消息观察路径。
  const bool installed = active_ || flutter_view_installed_ || runner_installed_;
  // 该状态行不是输入样本，只用于区分“无人按键”和“观察器未安装”；不含 HWND、进程、
  // 路径或原始按键。实体门禁会在基线后用文件长度标记跳过它。
  AppendLine(
      std::string("{\"event\":\"native_keyboard_observer_ready\",\"installed\":") +
      (installed ? "true" : "false") +
      ",\"childInstalled\":" +
      (flutter_view_installed_ ? "true" : "false") +
      ",\"runnerInstalled\":" + (runner_installed_ ? "true" : "false") +
      ",\"topLevelActive\":" + (active_ ? "true" : "false") +
      "}\n");
}

PlayerQaKeyboardQpcEvidence::~PlayerQaKeyboardQpcEvidence() {
  if (flutter_view_installed_ && flutter_view_window_ != nullptr) {
    RemoveWindowSubclass(flutter_view_window_, SubclassProc, kSubclassId);
  }
  if (runner_installed_ && runner_window_ != nullptr) {
    RemoveWindowSubclass(runner_window_, SubclassProc, kRunnerSubclassId);
  }
}

void PlayerQaKeyboardQpcEvidence::ObserveTopLevelWindowMessage(
    UINT message, WPARAM wparam, LPARAM lparam) const {
  // Flutter 的 HandleTopLevelWindowProc 可能在 runner 原始 WndProc 内直接消费
  // WM_KEY*；该旁路保留同一消息的 QPC，不改变消息返回值或正式产品行为。
  RecordKeyboardMessage(message, wparam, lparam);
}

LRESULT CALLBACK PlayerQaKeyboardQpcEvidence::SubclassProc(
    HWND window,
    UINT message,
    WPARAM wparam,
    LPARAM lparam,
    UINT_PTR subclass_id,
    DWORD_PTR reference_data) {
  auto* evidence = reinterpret_cast<PlayerQaKeyboardQpcEvidence*>(reference_data);
  if (evidence != nullptr &&
      (message == WM_KEYDOWN || message == WM_KEYUP ||
       message == WM_SYSKEYDOWN || message == WM_SYSKEYUP)) {
    evidence->RecordKeyboardMessage(message, wparam, lparam);
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

void PlayerQaKeyboardQpcEvidence::RecordKeyboardMessage(UINT message,
                                                         WPARAM wparam,
                                                         LPARAM lparam) const {
  if (!active_) {
    return;
  }
  if (message != WM_KEYDOWN && message != WM_KEYUP &&
      message != WM_SYSKEYDOWN && message != WM_SYSKEYUP) {
    return;
  }
  const char* action = ActionForVirtualKey(wparam);
  if (action == nullptr) {
    return;
  }
  const bool is_down = message == WM_KEYDOWN || message == WM_SYSKEYDOWN;
  const long long qpc_us = QueryPerformanceMicroseconds();
  const long long utc_us = WallClockMicroseconds();
  if (qpc_us <= 0 || utc_us <= 0) {
    return;
  }

  // 同一条消息可能先经过 runner subclass、再进入 FlutterWindow::MessageHandler；
  // 保留第一条观察结果，避免一个实体按键被统计两次。真实重复按键的 lParam 会变化，
  // 且不会在 5ms 内重复到达，因此不影响长按合同的 Down/Up 语义。
  if (message == last_message_ && wparam == last_wparam_ &&
      lparam == last_lparam_ && last_qpc_us_ > 0 &&
      qpc_us - last_qpc_us_ <= 5000) {
    return;
  }
  last_message_ = message;
  last_wparam_ = wparam;
  last_lparam_ = lparam;
  last_qpc_us_ = qpc_us;

  // 内容只含固定动作枚举、消息阶段、QPC 与 UTC 侧车，不留下真实快捷键或媒体关联；
  // UTC 只用于和 PLAYER_SEEK_TRACE 建立事件窗口，性能延迟仍以 QPC 为准。
  const std::string line = std::string("{\"event\":\"native_keyboard_message\",\"action\":\"") +
      action + "\",\"phase\":\"" + (is_down ? "down" : "up") +
      "\",\"qpcUs\":" + std::to_string(qpc_us) +
      ",\"utcUs\":" + std::to_string(utc_us) + "}\n";
  AppendLine(line);
}

void PlayerQaKeyboardQpcEvidence::AppendLine(const std::string& line) const {
  HANDLE output = CreateFileW(output_path_, FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                              OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (output == INVALID_HANDLE_VALUE) {
    return;
  }
  DWORD written = 0;
  WriteFile(output, line.data(), static_cast<DWORD>(line.size()), &written,
            nullptr);
  CloseHandle(output);
}
