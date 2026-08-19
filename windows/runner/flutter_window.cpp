#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "native_player_bridge.h"
#include "native_media_probe_bridge.h"
#include "player_qa_keyboard_qpc_evidence.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  native_player_registrar_ =
      std::make_unique<flutter::PluginRegistrarWindows>(
          flutter_controller_->engine()->GetRegistrarForPlugin(
              "LocalTagPlayerNativePlayer"));
  native_player_bridge_ = std::make_unique<NativePlayerBridge>(
      native_player_registrar_->messenger(),
      native_player_registrar_->texture_registrar(),
      flutter_controller_->view()->GetNativeWindow());
  native_probe_registrar_ =
      std::make_unique<flutter::PluginRegistrarWindows>(
          flutter_controller_->engine()->GetRegistrarForPlugin(
              "LocalTagPlayerNativeMediaProbe"));
  native_probe_bridge_ = std::make_unique<NativeMediaProbeBridge>(
      native_probe_registrar_->messenger());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  // SetChildContent 之后父子 HWND 关系才稳定；键盘观察器需要在此之后读取
  // FLUTTERVIEW 的 runner parent，避免顶层消息旁路在 ready 行中误报未安装。
  player_qa_keyboard_evidence_ = std::make_unique<PlayerQaKeyboardQpcEvidence>(
      flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    player_qa_keyboard_evidence_.reset();
    native_probe_bridge_.reset();
    native_probe_registrar_.reset();
    native_player_bridge_.reset();
    native_player_registrar_.reset();
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (player_qa_keyboard_evidence_) {
    // 顶层消息可能在 Flutter 的 HandleTopLevelWindowProc 内直接返回，不能只依赖
    // FLUTTERVIEW subclass；观察器内部仅 Debug QA 记录 J/L 并对 subclass 重复去重。
    player_qa_keyboard_evidence_->ObserveTopLevelWindowMessage(message, wparam,
                                                                lparam);
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      // 窗口销毁会先释放 Flutter controller；随后排队抵达的字体/输入法通知
      // 不能再访问已释放的 engine，否则标签输入等 TextField 场景会触发原生访问冲突。
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
