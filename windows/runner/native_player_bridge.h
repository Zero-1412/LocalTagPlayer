#ifndef RUNNER_NATIVE_PLAYER_BRIDGE_H_
#define RUNNER_NATIVE_PLAYER_BRIDGE_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <array>
#include <condition_variable>
#include <cstdint>
#include <future>
#include <memory>
#include <mutex>
#include <queue>
#include <string>
#include <thread>

/**
 * Windows 原生播放器桥接骨架。
 *
 * 当前阶段提供可验证的像素纹理、串行命令队列和确定性释放协议；后续 libmpv
 * 与 D3D11 实现只替换内部渲染资源，不改变 Flutter 方法通道契约。
 */
class NativePlayerBridge {
 public:
  NativePlayerBridge(flutter::BinaryMessenger* messenger,
                     flutter::TextureRegistrar* textures);
  ~NativePlayerBridge();

  NativePlayerBridge(const NativePlayerBridge&) = delete;
  NativePlayerBridge& operator=(const NativePlayerBridge&) = delete;

 private:
  /** 串行播放器命令，保证 open/seek/stop/dispose 不交叉修改原生资源。 */
  struct Command {
    std::string name;
    std::string text;
    int64_t integer = 0;
    std::shared_ptr<std::promise<void>> completion;
  };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void EnsureTexture();
  void DisposeSession();
  void Enqueue(Command command);
  void EnqueueAndWait(Command command);
  void WorkerLoop();
  flutter::EncodableMap StateSnapshot() const;

  flutter::TextureRegistrar* textures_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::TextureVariant> pixel_texture_;
  FlutterDesktopPixelBuffer pixel_buffer_{};
  std::array<uint8_t, 16> pixels_{};
  int64_t texture_id_ = -1;

  mutable std::mutex mutex_;
  std::condition_variable condition_;
  std::queue<Command> commands_;
  std::thread worker_;
  bool shutting_down_ = false;
  bool playing_ = false;
  bool buffering_ = false;
  int64_t position_ms_ = 0;
  int64_t duration_ms_ = 0;
  double volume_ = 100.0;
  std::string lifecycle_ = "idle";
};

#endif  // RUNNER_NATIVE_PLAYER_BRIDGE_H_
