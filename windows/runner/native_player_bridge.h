#ifndef RUNNER_NATIVE_PLAYER_BRIDGE_H_
#define RUNNER_NATIVE_PLAYER_BRIDGE_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>
#include <mpv/client.h>
#include <mpv/render.h>

#include "angle_surface_manager.h"

#include <array>
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <future>
#include <memory>
#include <mutex>
#include <optional>
#include <queue>
#include <string>
#include <thread>

/**
 * Windows 原生播放器桥接。
 *
 * 统一拥有 libmpv 会话、ANGLE/D3D11 共享纹理、串行命令和节流诊断；Flutter
 * 页面只能通过 PlayerBackend 适配器消费该契约。
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
  void InitializePlayer();
  void DestroyPlayer();
  void ExecutePlayerCommand(const Command& command);
  void SamplePlayerState();
  void RenderFrame();
  void DisposeSession();
  void Enqueue(Command command);
  void EnqueueAndWait(Command command);
  void WorkerLoop();
  flutter::EncodableMap StateSnapshot() const;
  /** 返回后台探测完成的显卡矩阵；未完成时只返回非阻塞状态。 */
  flutter::EncodableMap GpuCapabilitySnapshot();
  /** 从实际 ANGLE 渲染设备返回活动 LUID，不使用系统枚举顺序推断。 */
  flutter::EncodableMap ActiveGpuAdapterSnapshot(
      const std::string& backend_kind) const;
  /** 启动或轮询绑定活动 LUID 的 1080p/4K Compute 帧预算。 */
  flutter::EncodableMap ComputeFrameBudgetSnapshot(
      const std::string& adapter_luid);

  flutter::TextureRegistrar* textures_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::TextureVariant> pixel_texture_;
  std::unique_ptr<flutter::TextureVariant> gpu_texture_;
  std::unique_ptr<FlutterDesktopGpuSurfaceDescriptor> gpu_descriptor_;
  std::unique_ptr<ANGLESurfaceManager> surface_manager_;
  mpv_handle* player_ = nullptr;
  mpv_render_context* render_context_ = nullptr;
  FlutterDesktopPixelBuffer pixel_buffer_{};
  std::array<uint8_t, 16> pixels_{};
  int64_t texture_id_ = -1;
  bool native_mpv_enabled_ = false;
  std::atomic<bool> rendering_enabled_{false};
  std::atomic<bool> render_requested_{false};
  std::atomic<int32_t> desired_surface_width_{1280};
  std::atomic<int32_t> desired_surface_height_{720};
  std::atomic<int32_t> surface_width_{1280};
  std::atomic<int32_t> surface_height_{720};
  std::atomic<int64_t> render_request_count_{0};
  std::atomic<int64_t> rendered_frame_count_{0};
  std::atomic<int64_t> skipped_render_count_{0};
  std::atomic<int64_t> texture_copy_count_{0};
  std::atomic<int64_t> surface_resize_count_{0};

  mutable std::mutex mutex_;
  /** 防止 Flutter raster 读取共享纹理时与工作线程重建或绘制表面交叉。 */
  mutable std::mutex surface_mutex_;
  std::condition_variable condition_;
  std::queue<Command> commands_;
  std::thread worker_;
  /** 驱动初始化独立于 Flutter 平台线程，避免首次打开设置或诊断时卡住 UI。 */
  std::future<flutter::EncodableMap> gpu_capability_future_;
  std::optional<flutter::EncodableMap> gpu_capability_cache_;
  /** Compute 压测只在显式 QA 请求时创建，并始终离开 Flutter 平台线程。 */
  std::future<flutter::EncodableMap> compute_budget_future_;
  std::optional<flutter::EncodableMap> compute_budget_cache_;
  std::string compute_budget_luid_;
  bool shutting_down_ = false;
  bool playing_ = false;
  bool buffering_ = false;
  int64_t position_ms_ = 0;
  int64_t duration_ms_ = 0;
  double volume_ = 100.0;
  std::string lifecycle_ = "idle";
  std::string hwdec_ = "native-stub";
  std::string video_codec_ = "unavailable";
  std::string audio_codec_ = "unavailable";
  double avsync_ = 0.0;
  double audio_pts_ = 0.0;
  double cache_duration_ = 0.0;
  double estimated_vf_fps_ = 0.0;
  double display_fps_ = 0.0;
  int64_t frame_number_ = 0;
  int64_t dropped_frames_ = 0;
  int64_t completed_count_ = 0;
  int64_t error_count_ = 0;
  std::string last_error_;
};

#endif  // RUNNER_NATIVE_PLAYER_BRIDGE_H_
