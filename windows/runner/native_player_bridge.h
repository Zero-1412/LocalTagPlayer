#ifndef RUNNER_NATIVE_PLAYER_BRIDGE_H_
#define RUNNER_NATIVE_PLAYER_BRIDGE_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>
#include <mpv/client.h>
#include <mpv/render.h>
#include <windows.h>

#include "angle_surface_manager.h"
#include "d3d11_adapter_selector.h"
#include "local_video_enhancement_plugin.h"
#include "nvidia_optical_flow_driver_probe.h"
#include "vapoursynth_motion_runtime.h"

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
                     flutter::TextureRegistrar* textures,
                     HWND flutter_view_window);
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
    /** 属性批次仅在最后一项排空事件，避免配置阶段反复打断 60fps 渲染。 */
    bool sample_state = true;
  };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  /** 在 Flutter 平台线程创建隔离 child HWND；默认路径不会触发该窗口。 */
  bool CreateHwndSurface();
  /** 同步 Flutter 视频占位区域对应的物理像素矩形与可见性。 */
  void UpdateHwndSurface(const flutter::EncodableMap& arguments);
  /** Flutter 弹层期间裁剪或隐藏 child HWND，并在弹层关闭后恢复最后矩形。 */
  void SetHwndSurfaceOccluded(const flutter::EncodableMap& arguments);
  /** 合并可见控制区与 Flutter 弹层，在 child HWND 本地窗口区域执行差集裁剪。 */
  void ApplyHwndSurfaceOcclusionRegion();
  /** 在 libmpv 会话释放后销毁 child HWND，避免悬空 wid。 */
  void DestroyHwndSurface();
  void EnsureTexture();
  void InitializePlayer();
  void DestroyPlayer();
  void ExecutePlayerCommand(const Command& command);
  /** 注册会话状态观察项；高频进度只由 libmpv 变化事件驱动。 */
  void RegisterObservedProperties();
  /**
   * 排空一批 libmpv 事件，并把属性变化合并进轻量状态快照。
   *
   * 返回 true 表示批次已饱和，调用方应主动让出工作线程。
   */
  bool DrainPlayerEvents();
  /** 在事件仍有效时复制观察属性，禁止跨越下一次 mpv_wait_event 保存裸指针。 */
  void ApplyObservedProperty(const mpv_event_property& property);
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
  /** Flutter view 的 HWND，只作为实验视频子窗口的父窗口，不改变主 runner 所有权。 */
  HWND flutter_view_window_ = nullptr;
  /** `gpu-next/d3d11` 直接输出目标；该窗口只在显式 `hwnd` 模式创建。 */
  HWND video_host_window_ = nullptr;
  /**
   * 交给 libmpv 的内部 HWND。
   *
   * 外层宿主负责 Flutter 几何与裁剪；即使 mpv 在媒体加载时重设内部窗口尺寸，也
   * 不能越过外层 child HWND 的 airspace 边界。
   */
  HWND mpv_render_window_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::TextureVariant> pixel_texture_;
  std::unique_ptr<flutter::TextureVariant> gpu_texture_;
  std::unique_ptr<FlutterDesktopGpuSurfaceDescriptor> gpu_descriptor_;
  std::unique_ptr<ANGLESurfaceManager> surface_manager_;
  /** 只服务显式本机 DLL 的 SDK 中立 D3D11 原型宿主。 */
  LocalVideoEnhancementPlugin video_enhancement_plugin_;
  /** 只服务显式本机 VapourSynth/插帧脚本的结构化滤镜宿主。 */
  VapourSynthMotionRuntime motion_runtime_;
  /** NVIDIA 显示驱动 OFAPI 的只读能力，不代表 FRUC 插件已经安装。 */
  NvidiaOpticalFlowDriverSnapshot nvofa_driver_;
  /** child HWND 的 mpv D3D11 适配器选择；其 LUID 同时约束 CUDA/NVOFA。 */
  D3D11AdapterSelection d3d11_adapter_;
  mpv_handle* player_ = nullptr;
  mpv_render_context* render_context_ = nullptr;
  FlutterDesktopPixelBuffer pixel_buffer_{};
  std::array<uint8_t, 16> pixels_{};
  int64_t texture_id_ = -1;
  bool native_mpv_enabled_ = false;
  bool native_hwnd_enabled_ = false;
  /** Flutter 布局是否仍请求显示 child HWND；与弹层临时遮挡状态分开保存。 */
  bool hwnd_surface_requested_visible_ = false;
  /** Flutter 弹层是否正在占用视频区域。 */
  bool hwnd_surface_occluded_ = false;
  /** true 表示只裁剪弹层矩形；false 表示完整隐藏原生表面。 */
  bool hwnd_surface_partial_occlusion_ = false;
  int64_t overlay_left_ = 0;
  int64_t overlay_top_ = 0;
  int64_t overlay_width_ = 0;
  int64_t overlay_height_ = 0;
  int64_t overlay_view_width_ = 1;
  int64_t overlay_view_height_ = 1;
  bool hwnd_surface_visible_ = false;
  std::atomic<bool> rendering_enabled_{false};
  std::atomic<bool> render_requested_{false};
  /**
   * libmpv 唤醒回调只设置该标记并通知工作线程。
   *
   * 回调可能来自任意 mpv 线程，不能在其中读取属性、执行命令或触碰 Flutter。
   */
  std::atomic<bool> event_requested_{false};
  std::atomic<int32_t> desired_surface_width_{1280};
  std::atomic<int32_t> desired_surface_height_{720};
  std::atomic<int32_t> surface_left_{0};
  std::atomic<int32_t> surface_top_{0};
  std::atomic<int32_t> surface_width_{1280};
  std::atomic<int32_t> surface_height_{720};
  /** Flutter 逻辑画布尺寸，用于把控制区高度稳定换算到当前物理 HWND。 */
  std::atomic<int64_t> surface_view_width_{1};
  std::atomic<int64_t> surface_view_height_{1};
  /** Flutter 当前需要显示在视频之上的顶部/底部逻辑控制区。 */
  std::atomic<int64_t> airspace_inset_top_{0};
  std::atomic<int64_t> airspace_inset_bottom_{0};
  std::atomic<int64_t> render_request_count_{0};
  std::atomic<int64_t> rendered_frame_count_{0};
  std::atomic<int64_t> skipped_render_count_{0};
  std::atomic<int64_t> texture_copy_count_{0};
  std::atomic<int64_t> surface_resize_count_{0};
  /** 已消费的 mpv 事件数，用于确认事件驱动状态链持续工作。 */
  std::atomic<int64_t> player_event_count_{0};
  /** 单批达到上限并主动让出命令/渲染的次数。 */
  std::atomic<int64_t> event_batch_yield_count_{0};

  mutable std::mutex mutex_;
  /** 串行 mpv 绘制、共享纹理复制、插件处理与表面重建。 */
  mutable std::mutex surface_mutex_;
  /**
   * 只保护 ANGLE 共享句柄与尺寸重建。
   *
   * Flutter raster 线程读取纹理描述符时不得等待整帧 mpv 绘制、D3D 复制或插件；
   * 只有极少发生的 SetSize/销毁可以短暂阻塞描述符读取。
   */
  mutable std::mutex surface_descriptor_mutex_;
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
  /**
   * mpv 是否直接采样 D3D11VA 解码表面。
   *
   * 该选项可能触发驱动兼容问题，仅由隔离 QA 环境变量请求；默认产品会话保持关闭。
   */
  std::string d3d11va_zero_copy_ = "no";
  /** libmpv 运行时版本，只通过固定属性返回，不复制原生日志。 */
  std::string mpv_version_ = "unavailable";
  /** 当前完整视频滤镜图，用于确认 NVIDIA 请求是否被 libmpv 接受。 */
  std::string video_filters_ = "";
  /**
   * 当前去色带属性快照。
   *
   * PlayerService 会把这些属性与 `vf` 作为同一事务提交；原生后端必须完整回读，
   * 否则一个已经成功的 D3D11 滤镜会因旁路属性不可见而被错误回滚。
   */
  std::string deband_ = "unavailable";
  std::string deband_iterations_ = "unavailable";
  std::string deband_threshold_ = "unavailable";
  std::string deband_range_ = "unavailable";
  std::string deband_grain_ = "unavailable";
  /**
   * NVIDIA RTX Super Resolution 运行状态。
   *
   * 只允许 `inactive/requested/active/rejected`，禁止把可能包含路径的 mpv
   * 原始日志传回 Flutter。
   */
  std::string nvidia_vsr_state_ = "inactive";
  /**
   * NVIDIA RTX Video HDR 运行状态。
   *
   * 只允许 `inactive/requested/active/rejected/ignored-source-hdr`，禁止把
   * HRESULT、媒体路径或原始日志传回 Flutter。
   */
  std::string nvidia_hdr_state_ = "inactive";
  /** 当前源色彩原色，供 Dart 诊断和保守 SDR/HDR 门禁使用。 */
  std::string video_primaries_ = "unavailable";
  /** 当前源传递函数；只有明确的 PQ/HLG 才会被 Dart 识别为 HDR。 */
  std::string video_gamma_ = "unavailable";
  /** 当前源量化范围，用于区分 limited/TV 与 full/PC，避免凭显示亮度猜测。 */
  std::string video_color_levels_ = "unavailable";
  /** 当前源色彩矩阵，用于确认 BT.601/709/2020 转换路径。 */
  std::string video_color_matrix_ = "unavailable";
  /** libmpv 当前请求的 RGB 输出电平策略。 */
  std::string video_output_levels_ = "unavailable";
  /** libmpv 渲染目标最终确认的输出范围。 */
  std::string video_target_color_levels_ = "unavailable";
  /**
   * 当前源画面尺寸。
   *
   * 只暴露 mpv 已确认的正整数，用于 Dart 判断显示输出是否实际需要 VSR；
   * 媒体切换期间属性不可用时归零，避免沿用上一条视频尺寸。
   */
  int64_t video_width_ = 0;
  int64_t video_height_ = 0;
  std::string video_codec_ = "unavailable";
  std::string audio_codec_ = "unavailable";
  double avsync_ = 0.0;
  /** 属性不可用时保留显式文本，避免把回退 0 误判成音频播放头停滞。 */
  std::string audio_pts_ = "unavailable";
  double cache_duration_ = 0.0;
  /** 容器报告的源帧率，用于确认外部插帧确实提高了时间采样。 */
  double container_fps_ = 0.0;
  double estimated_vf_fps_ = 0.0;
  double display_fps_ = 0.0;
  /** 显示同步插值的实际 mpv 属性，用于 Flutter 侧能力读回而非写入推断。 */
  std::string video_sync_ = "unavailable";
  std::string interpolation_ = "unavailable";
  std::string temporal_scaler_ = "unavailable";
  std::string display_sync_active_ = "unavailable";
  int64_t frame_number_ = 0;
  /** mpv 未持续推送帧号时，明确记录由播放时间和滤镜 FPS 派生。 */
  std::string frame_number_source_ = "unavailable";
  /** 只有收到正数原生帧号后才停止使用派生值。 */
  bool frame_number_observed_ = false;
  int64_t dropped_frames_ = 0;
  int64_t completed_count_ = 0;
  int64_t error_count_ = 0;
  std::string last_error_;
};

#endif  // RUNNER_NATIVE_PLAYER_BRIDGE_H_
