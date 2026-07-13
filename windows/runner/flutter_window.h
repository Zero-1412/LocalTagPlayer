#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

#include "win32_window.h"

class NativePlayerBridge;
class NativeMediaProbeBridge;

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  /** Windows 原生播放器通道与纹理生命周期所有者。 */
  std::unique_ptr<flutter::PluginRegistrarWindows> native_player_registrar_;
  std::unique_ptr<NativePlayerBridge> native_player_bridge_;
  /** 原生 FFmpeg 批处理通道与工作线程所有者。 */
  std::unique_ptr<flutter::PluginRegistrarWindows> native_probe_registrar_;
  std::unique_ptr<NativeMediaProbeBridge> native_probe_bridge_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
