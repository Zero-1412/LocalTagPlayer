#include "native_player_bridge.h"

#include "gpu_capability_probe.h"
#include "gpu_compute_frame_budget.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <mpv/render_gl.h>
#include <utility>

extern "C" int LtpMediaKitQueryActiveAdapterLuid(int32_t* high_part,
                                                  uint32_t* low_part);

namespace {
constexpr char kChannelName[] = "local_tag_player/native_player";
constexpr wchar_t kVideoHostWindowClass[] =
    L"LocalTagPlayerNativeVideoHost";

using QueryActiveAdapterLuid = int (*)(int32_t*, uint32_t*);

std::string StringArgument(const flutter::EncodableMap& arguments,
                           const char* key) {
  const auto iterator = arguments.find(flutter::EncodableValue(key));
  if (iterator == arguments.end()) return {};
  const auto* value = std::get_if<std::string>(&iterator->second);
  return value == nullptr ? std::string() : *value;
}

int64_t IntegerArgument(const flutter::EncodableMap& arguments,
                        const char* key) {
  const auto iterator = arguments.find(flutter::EncodableValue(key));
  if (iterator == arguments.end()) return 0;
  if (const auto* value = std::get_if<int64_t>(&iterator->second)) return *value;
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) return *value;
  return 0;
}

bool BooleanArgument(const flutter::EncodableMap& arguments, const char* key) {
  const auto iterator = arguments.find(flutter::EncodableValue(key));
  if (iterator == arguments.end()) return false;
  const auto* value = std::get_if<bool>(&iterator->second);
  return value != nullptr && *value;
}

/**
 * child HWND 只负责视频输出，不拥有鼠标命中或键盘焦点。
 *
 * `HTTRANSPARENT` 让同线程的 Flutter view 直接收到真实 Win32 鼠标消息，避免
 * `PostMessage` 丢失按钮状态、双击时序或 Flutter 自己的捕获语义。
 */
LRESULT CALLBACK VideoHostWindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam) {
  switch (message) {
    case WM_NCHITTEST:
      return HTTRANSPARENT;
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_ERASEBKGND: {
      const HDC device_context = reinterpret_cast<HDC>(wparam);
      RECT bounds{};
      GetClientRect(window, &bounds);
      FillRect(device_context, &bounds,
               static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
      return 1;
    }
    default:
      return DefWindowProc(window, message, wparam, lparam);
  }
}

/** 每个进程只登记一次原生视频宿主窗口类。 */
bool EnsureVideoHostWindowClass() {
  static std::once_flag once;
  static bool registered = false;
  std::call_once(once, []() {
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(WNDCLASSEXW);
    window_class.style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
    window_class.lpfnWndProc = VideoHostWindowProc;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.hbrBackground =
        static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    window_class.lpszClassName = kVideoHostWindowClass;
    registered = RegisterClassExW(&window_class) != 0 ||
                 GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
  });
  return registered;
}

std::string LuidString(int32_t high_part, uint32_t low_part) {
  std::array<char, 32> buffer{};
  std::snprintf(buffer.data(), buffer.size(), "%08x:%08x",
                static_cast<uint32_t>(high_part), low_part);
  return buffer.data();
}

/** 将 Flutter 请求尺寸量化并限制在原生纹理预算内，避免窗口动画产生频繁小幅重建。 */
int32_t NormalizeSurfaceDimension(size_t value, int32_t minimum,
                                  int32_t maximum, int32_t quantum) {
  const auto capped = std::min(value, static_cast<size_t>(maximum));
  const auto safe = std::max(static_cast<int32_t>(capped), minimum);
  return std::min(((safe + quantum - 1) / quantum) * quantum, maximum);
}
}  // namespace

NativePlayerBridge::NativePlayerBridge(flutter::BinaryMessenger* messenger,
                                       flutter::TextureRegistrar* textures,
                                       HWND flutter_view_window)
    : textures_(textures),
      flutter_view_window_(flutter_view_window),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())),
      gpu_capability_future_(std::async(std::launch::async, []() {
        return QueryGpuCapabilityMatrix();
      })) {
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
  worker_ = std::thread([this]() { WorkerLoop(); });
}

NativePlayerBridge::~NativePlayerBridge() {
  channel_->SetMethodCallHandler(nullptr);
  // runner 关闭也必须走与页面退出相同的纹理注销和原生资源释放顺序。
  DisposeSession();
  if (native_mpv_enabled_ && worker_.joinable()) {
    EnqueueAndWait({"destroy", {}, 0, nullptr});
  }
  DestroyHwndSurface();
  {
    std::lock_guard<std::mutex> lock(mutex_);
    shutting_down_ = true;
  }
  condition_.notify_one();
  if (worker_.joinable()) worker_.join();
}

void NativePlayerBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
  const flutter::EncodableMap empty;
  const auto& values = arguments == nullptr ? empty : *arguments;
  if (call.method_name() == "gpuCapabilities") {
    result->Success(flutter::EncodableValue(GpuCapabilitySnapshot()));
    return;
  }
  if (call.method_name() == "activeGpuAdapter") {
    result->Success(flutter::EncodableValue(
        ActiveGpuAdapterSnapshot(StringArgument(values, "backend"))));
    return;
  }
  if (call.method_name() == "computeFrameBudget") {
    result->Success(flutter::EncodableValue(
        ComputeFrameBudgetSnapshot(StringArgument(values, "adapterLuid"))));
    return;
  }
  if (call.method_name() == "create") {
    const auto mode = StringArgument(values, "mode");
    native_hwnd_enabled_ = mode == "hwnd";
    native_mpv_enabled_ = mode == "mpv" || native_hwnd_enabled_;
    if (native_hwnd_enabled_ && !CreateHwndSurface()) {
      result->Error("native-hwnd-create-failed",
                    "无法创建隔离的 Windows 视频子窗口");
      return;
    }
    if (native_mpv_enabled_) {
      EnqueueAndWait({"initialize", {}, 0, nullptr});
    }
    if (!native_hwnd_enabled_) EnsureTexture();
    result->Success(flutter::EncodableValue(StateSnapshot()));
    return;
  }
  if (call.method_name() == "state") {
    result->Success(flutter::EncodableValue(StateSnapshot()));
    return;
  }
  if (call.method_name() == "setSurfaceRect") {
    UpdateHwndSurface(values);
    result->Success();
    return;
  }
  if (call.method_name() == "setSurfaceOccluded") {
    SetHwndSurfaceOccluded(values);
    result->Success();
    return;
  }
  if (call.method_name() == "dispose") {
    if (video_host_window_ != nullptr) ShowWindow(video_host_window_, SW_HIDE);
    EnqueueAndWait({"dispose", {}, 0, nullptr});
    DisposeSession();
    if (native_mpv_enabled_) {
      EnqueueAndWait({"destroy", {}, 0, nullptr});
    }
    DestroyHwndSurface();
    result->Success();
    return;
  }
  if (call.method_name() == "command") {
    EnqueueAndWait({StringArgument(values, "name"),
                    StringArgument(values, "text"),
                    IntegerArgument(values, "integer"), nullptr});
    result->Success();
    return;
  }
  result->NotImplemented();
}

flutter::EncodableMap NativePlayerBridge::GpuCapabilitySnapshot() {
  if (gpu_capability_cache_.has_value()) return *gpu_capability_cache_;
  if (gpu_capability_future_.valid() &&
      gpu_capability_future_.wait_for(std::chrono::milliseconds(0)) ==
          std::future_status::ready) {
    gpu_capability_cache_ = gpu_capability_future_.get();
    return *gpu_capability_cache_;
  }
  // probing 快照不包含半成品数据，Dart 会短暂让出事件循环后重试。
  return flutter::EncodableMap{
      {flutter::EncodableValue("platformSupported"),
       flutter::EncodableValue(true)},
      {flutter::EncodableValue("probeStatus"),
       flutter::EncodableValue("probing")},
      {flutter::EncodableValue("detectionSource"),
       flutter::EncodableValue("dxgi-d3d11-vulkan-loader")},
      {flutter::EncodableValue("vulkanLoaderAvailable"),
       flutter::EncodableValue(false)},
      {flutter::EncodableValue("vulkanInstanceAvailable"),
       flutter::EncodableValue(false)},
      {flutter::EncodableValue("adapters"),
       flutter::EncodableValue(flutter::EncodableList{})},
  };
}

flutter::EncodableMap NativePlayerBridge::ActiveGpuAdapterSnapshot(
    const std::string& backend_kind) const {
  QueryActiveAdapterLuid query = nullptr;
  std::string source;
  if (backend_kind == "media-kit") {
    // 默认生产后端的设备由插件 DLL 拥有；读取其导出快照才能保证 LUID 来自实际纹理。
    const HMODULE plugin = GetModuleHandleW(L"media_kit_video_plugin.dll");
    if (plugin != nullptr) {
      query = reinterpret_cast<QueryActiveAdapterLuid>(
          GetProcAddress(plugin, "LtpMediaKitQueryActiveAdapterLuid"));
    }
    source = "media-kit-angle-d3d11-device";
  } else if (backend_kind == "windows-native") {
    query = &LtpMediaKitQueryActiveAdapterLuid;
    source = "windows-native-angle-d3d11-device";
  }

  if (query == nullptr) {
    return flutter::EncodableMap{
        {flutter::EncodableValue("probeStatus"),
         flutter::EncodableValue("unavailable")},
        {flutter::EncodableValue("detectionSource"),
         flutter::EncodableValue(source.empty() ? "unsupported-backend"
                                                : source)},
        {flutter::EncodableValue("errorCode"),
         flutter::EncodableValue("active-adapter-export-unavailable")}};
  }
  int32_t high_part = 0;
  uint32_t low_part = 0;
  const int status = query(&high_part, &low_part);
  if (status == 1) {
    return flutter::EncodableMap{
        {flutter::EncodableValue("probeStatus"),
         flutter::EncodableValue("ready")},
        {flutter::EncodableValue("detectionSource"),
         flutter::EncodableValue(source)},
        {flutter::EncodableValue("adapterLuid"),
         flutter::EncodableValue(LuidString(high_part, low_part))}};
  }
  return flutter::EncodableMap{
      {flutter::EncodableValue("probeStatus"),
       flutter::EncodableValue(status == 2 ? "ambiguous" : "unavailable")},
      {flutter::EncodableValue("detectionSource"),
       flutter::EncodableValue(source)},
      {flutter::EncodableValue("errorCode"),
       flutter::EncodableValue(status == 2 ? "multiple-active-adapter-luids"
                                           : "render-device-not-created")}};
}

flutter::EncodableMap NativePlayerBridge::ComputeFrameBudgetSnapshot(
    const std::string& adapter_luid) {
  if (adapter_luid.empty()) {
    return flutter::EncodableMap{
        {flutter::EncodableValue("probeStatus"),
         flutter::EncodableValue("failed")},
        {flutter::EncodableValue("detectionSource"),
         flutter::EncodableValue("d3d11-timestamp-query-hdr-compute-kernel")},
        {flutter::EncodableValue("errorCode"),
         flutter::EncodableValue("missing-adapter-luid")},
        {flutter::EncodableValue("samples"),
         flutter::EncodableValue(flutter::EncodableList{})}};
  }
  if (compute_budget_cache_.has_value() &&
      compute_budget_luid_ == adapter_luid) {
    return *compute_budget_cache_;
  }
  if (compute_budget_future_.valid()) {
    if (compute_budget_luid_ != adapter_luid) {
      return flutter::EncodableMap{
          {flutter::EncodableValue("probeStatus"),
           flutter::EncodableValue("failed")},
          {flutter::EncodableValue("detectionSource"),
           flutter::EncodableValue(
               "d3d11-timestamp-query-hdr-compute-kernel")},
          {flutter::EncodableValue("errorCode"),
           flutter::EncodableValue("another-adapter-benchmark-is-running")},
          {flutter::EncodableValue("samples"),
           flutter::EncodableValue(flutter::EncodableList{})}};
    }
    if (compute_budget_future_.wait_for(std::chrono::milliseconds(0)) ==
        std::future_status::ready) {
      compute_budget_cache_ = compute_budget_future_.get();
      return *compute_budget_cache_;
    }
  } else {
    compute_budget_luid_ = adapter_luid;
    compute_budget_future_ =
        std::async(std::launch::async, [adapter_luid]() {
          return QueryGpuComputeFrameBudget(adapter_luid);
        });
  }
  return flutter::EncodableMap{
      {flutter::EncodableValue("probeStatus"),
       flutter::EncodableValue("probing")},
      {flutter::EncodableValue("adapterLuid"),
       flutter::EncodableValue(adapter_luid)},
      {flutter::EncodableValue("detectionSource"),
       flutter::EncodableValue("d3d11-timestamp-query-hdr-compute-kernel")},
      {flutter::EncodableValue("samples"),
       flutter::EncodableValue(flutter::EncodableList{})}};
}

bool NativePlayerBridge::CreateHwndSurface() {
  if (video_host_window_ != nullptr) return true;
  if (flutter_view_window_ == nullptr || !EnsureVideoHostWindowClass()) {
    std::lock_guard<std::mutex> lock(mutex_);
    lifecycle_ = "hwnd_host_unavailable";
    last_error_ = "native-hwnd-host-unavailable";
    ++error_count_;
    return false;
  }
  video_host_window_ = CreateWindowExW(
      0, kVideoHostWindowClass, L"", WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
      0, 0, 1, 1, flutter_view_window_, nullptr, GetModuleHandle(nullptr),
      nullptr);
  if (video_host_window_ == nullptr) {
    std::lock_guard<std::mutex> lock(mutex_);
    lifecycle_ = "hwnd_create_failed";
    last_error_ = "native-hwnd-create-failed";
    ++error_count_;
    return false;
  }
  mpv_render_window_ = CreateWindowExW(
      0, kVideoHostWindowClass, L"",
      WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS, 0, 0, 1, 1,
      video_host_window_, nullptr, GetModuleHandle(nullptr), nullptr);
  if (mpv_render_window_ == nullptr) {
    DestroyWindow(video_host_window_);
    video_host_window_ = nullptr;
    mpv_render_window_ = nullptr;
    std::lock_guard<std::mutex> lock(mutex_);
    lifecycle_ = "hwnd_render_create_failed";
    last_error_ = "native-hwnd-render-create-failed";
    ++error_count_;
    return false;
  }
  ShowWindow(mpv_render_window_, SW_SHOWNA);
  ShowWindow(video_host_window_, SW_HIDE);
  std::lock_guard<std::mutex> lock(mutex_);
  lifecycle_ = "hwnd_created";
  hwnd_surface_visible_ = false;
  return true;
}

void NativePlayerBridge::UpdateHwndSurface(
    const flutter::EncodableMap& arguments) {
  if (!native_hwnd_enabled_ || video_host_window_ == nullptr) return;
  const auto logical_left = std::clamp<int64_t>(
      IntegerArgument(arguments, "left"), -32768, 32767);
  const auto logical_top = std::clamp<int64_t>(
      IntegerArgument(arguments, "top"), -32768, 32767);
  const auto logical_width =
      std::clamp<int64_t>(IntegerArgument(arguments, "width"), 0, 16384);
  const auto logical_height =
      std::clamp<int64_t>(IntegerArgument(arguments, "height"), 0, 16384);
  const auto view_width =
      std::max<int64_t>(IntegerArgument(arguments, "viewWidth"), 1);
  const auto view_height =
      std::max<int64_t>(IntegerArgument(arguments, "viewHeight"), 1);
  RECT parent_bounds{};
  GetClientRect(flutter_view_window_, &parent_bounds);
  const double scale_x =
      static_cast<double>(parent_bounds.right - parent_bounds.left) /
      static_cast<double>(view_width);
  const double scale_y =
      static_cast<double>(parent_bounds.bottom - parent_bounds.top) /
      static_cast<double>(view_height);
  // Flutter 测试可覆盖逻辑 surface size；以实际父 HWND 客户区做最终换算，不能
  // 假定 devicePixelRatio 就等于当前测试画布到窗口客户区的比例。
  const auto left = static_cast<int>(std::lround(logical_left * scale_x));
  const auto top = static_cast<int>(std::lround(logical_top * scale_y));
  const auto width = static_cast<int>(std::lround(logical_width * scale_x));
  const auto height = static_cast<int>(std::lround(logical_height * scale_y));
  const bool requested_visible =
      BooleanArgument(arguments, "visible") && width >= 64 && height >= 64;
  bool occluded = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    hwnd_surface_requested_visible_ = requested_visible;
    occluded = hwnd_surface_occluded_;
  }
  const bool visible = requested_visible && !occluded;
  if (visible) {
    SetWindowPos(video_host_window_, HWND_TOP, left, top, width, height,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
    // 内层由 mpv 使用，外层始终裁剪其输出，防止媒体加载时 wid 自行扩张越界。
    SetWindowPos(mpv_render_window_, HWND_TOP, 0, 0, width, height,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
  } else {
    ShowWindow(video_host_window_, SW_HIDE);
  }
  surface_left_ = left;
  surface_top_ = top;
  surface_width_ = width;
  surface_height_ = height;
  std::lock_guard<std::mutex> lock(mutex_);
  hwnd_surface_visible_ = visible;
}

void NativePlayerBridge::SetHwndSurfaceOccluded(
    const flutter::EncodableMap& arguments) {
  if (!native_hwnd_enabled_ || video_host_window_ == nullptr) return;
  const bool occluded = BooleanArgument(arguments, "occluded");
  bool should_show = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    hwnd_surface_occluded_ = occluded;
    should_show = hwnd_surface_requested_visible_ && !occluded;
    hwnd_surface_visible_ = should_show;
  }
  if (!should_show) {
    ShowWindow(video_host_window_, SW_HIDE);
    return;
  }
  // 恢复最后一次 Flutter 布局矩形，避免弹层关闭后等待下一次布局才重新出画。
  SetWindowPos(video_host_window_, HWND_TOP, surface_left_, surface_top_,
               surface_width_, surface_height_,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  SetWindowPos(mpv_render_window_, HWND_TOP, 0, 0, surface_width_,
               surface_height_, SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void NativePlayerBridge::DestroyHwndSurface() {
  if (video_host_window_ != nullptr) {
    ShowWindow(video_host_window_, SW_HIDE);
    DestroyWindow(video_host_window_);
    video_host_window_ = nullptr;
    mpv_render_window_ = nullptr;
  }
  std::lock_guard<std::mutex> lock(mutex_);
  hwnd_surface_requested_visible_ = false;
  hwnd_surface_occluded_ = false;
  hwnd_surface_visible_ = false;
}

void NativePlayerBridge::EnsureTexture() {
  if (texture_id_ >= 0) return;
  if (native_mpv_enabled_ && surface_manager_ != nullptr) {
    gpu_descriptor_ =
        std::make_unique<FlutterDesktopGpuSurfaceDescriptor>();
    gpu_descriptor_->struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
    gpu_descriptor_->handle = surface_manager_->handle();
    gpu_descriptor_->width = gpu_descriptor_->visible_width =
        surface_manager_->width();
    gpu_descriptor_->height = gpu_descriptor_->visible_height =
        surface_manager_->height();
    gpu_descriptor_->format = kFlutterDesktopPixelFormatBGRA8888;
    gpu_descriptor_->release_callback = [](void*) {};
    gpu_descriptor_->release_context = nullptr;
    gpu_texture_ = std::make_unique<flutter::TextureVariant>(
        flutter::GpuSurfaceTexture(
            kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
            [this](size_t width, size_t height) {
              if (!rendering_enabled_ || surface_manager_ == nullptr) {
                return static_cast<FlutterDesktopGpuSurfaceDescriptor*>(
                    nullptr);
              }
              desired_surface_width_ =
                  NormalizeSurfaceDimension(width, 640, 1920, 64);
              desired_surface_height_ =
                  NormalizeSurfaceDimension(height, 360, 1080, 32);
              std::lock_guard<std::mutex> surface_lock(surface_mutex_);
              if (!rendering_enabled_ || surface_manager_ == nullptr) {
                return static_cast<FlutterDesktopGpuSurfaceDescriptor*>(
                    nullptr);
              }
              gpu_descriptor_->handle = surface_manager_->handle();
              gpu_descriptor_->width = gpu_descriptor_->visible_width =
                  surface_manager_->width();
              gpu_descriptor_->height = gpu_descriptor_->visible_height =
                  surface_manager_->height();
              return gpu_descriptor_.get();
            }));
    texture_id_ = textures_->RegisterTexture(gpu_texture_.get());
    rendering_enabled_ = true;
    textures_->MarkTextureFrameAvailable(texture_id_);
    std::lock_guard<std::mutex> lock(mutex_);
    lifecycle_ = "mpv_texture_ready";
    return;
  }
  // 2x2 BGRA 棋盘格用于验证 Flutter 外部纹理注册与释放，不代表真实视频帧。
  pixels_ = {0x38, 0x78, 0x0f, 0xff, 0x70, 0x70, 0x70, 0xff,
             0x70, 0x70, 0x70, 0xff, 0x38, 0x78, 0x0f, 0xff};
  pixel_buffer_.buffer = pixels_.data();
  pixel_buffer_.width = 2;
  pixel_buffer_.height = 2;
  pixel_texture_ = std::make_unique<flutter::TextureVariant>(
      flutter::PixelBufferTexture(
          [this](size_t, size_t) { return &pixel_buffer_; }));
  texture_id_ = textures_->RegisterTexture(pixel_texture_.get());
  textures_->MarkTextureFrameAvailable(texture_id_);
  std::lock_guard<std::mutex> lock(mutex_);
  lifecycle_ = "texture_ready";
}

void NativePlayerBridge::DisposeSession() {
  rendering_enabled_ = false;
  const int64_t texture = texture_id_;
  texture_id_ = -1;
  if (texture >= 0) {
    textures_->UnregisterTexture(texture);
    pixel_texture_.reset();
    gpu_texture_.reset();
    gpu_descriptor_.reset();
  }
  std::lock_guard<std::mutex> lock(mutex_);
  playing_ = false;
  buffering_ = false;
  lifecycle_ = "disposed";
}

void NativePlayerBridge::InitializePlayer() {
  if (player_ != nullptr) return;
  lifecycle_ =
      native_hwnd_enabled_ ? "mpv_hwnd_initializing" : "mpv_initializing";
  player_ = mpv_create();
  if (player_ == nullptr) {
    lifecycle_ = "mpv_create_failed";
    return;
  }
  if (native_hwnd_enabled_) {
    // wid 路径让 libmpv 直接拥有 D3D11 swap chain，绕开 Flutter Texture 与
    // MediaKit/ANGLE 的 copy 边界；只在显式实验开关下使用。
    mpv_set_option_string(player_, "vo", "gpu-next");
    mpv_set_option_string(player_, "gpu-api", "d3d11");
    mpv_set_option_string(player_, "gpu-context", "d3d11");
    mpv_set_option_string(player_, "hwdec", "d3d11va");
    mpv_set_option_string(player_, "gpu-hwdec-interop", "d3d11va");
    mpv_set_option_string(player_, "input-default-bindings", "no");
    mpv_set_option_string(player_, "input-cursor", "no");
    int64_t window_id =
        static_cast<int64_t>(reinterpret_cast<intptr_t>(mpv_render_window_));
    mpv_set_option(player_, "wid", MPV_FORMAT_INT64, &window_id);
  } else {
    mpv_set_option_string(player_, "vo", "libmpv");
    mpv_set_option_string(player_, "hwdec", "d3d11va-copy");
  }
  mpv_set_option_string(player_, "video-sync", "display-resample");
  mpv_set_option_string(player_, "cache", "yes");
  mpv_set_option_string(player_, "demuxer-readahead-secs", "12");
  mpv_set_option_string(player_, "demuxer-max-bytes", "64MiB");
  mpv_set_option_string(player_, "demuxer-max-back-bytes", "16MiB");
  if (mpv_initialize(player_) < 0) {
    lifecycle_ = "mpv_initialize_failed";
    mpv_terminate_destroy(player_);
    player_ = nullptr;
    return;
  }
  if (native_hwnd_enabled_) {
    lifecycle_ = "mpv_hwnd_ready";
    return;
  }
  try {
    surface_manager_ = std::make_unique<ANGLESurfaceManager>(1280, 720);
    surface_width_ = surface_manager_->width();
    surface_height_ = surface_manager_->height();
    surface_manager_->MakeCurrent(true);
    mpv_opengl_init_params gl_init{
        [](void*, const char* name) {
          return reinterpret_cast<void*>(eglGetProcAddress(name));
        },
        nullptr};
    mpv_render_param parameters[] = {
        {MPV_RENDER_PARAM_API_TYPE,
         const_cast<char*>(MPV_RENDER_API_TYPE_OPENGL)},
        {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_init},
        {MPV_RENDER_PARAM_INVALID, nullptr}};
    const auto result =
        mpv_render_context_create(&render_context_, player_, parameters);
    surface_manager_->MakeCurrent(false);
    if (result < 0) {
      lifecycle_ = "mpv_render_context_failed";
      DestroyPlayer();
      return;
    }
    // 插件只借用 ANGLE 的活动设备；失败状态留在诊断中，不改变原生视频会话。
    video_enhancement_plugin_.Initialize(
        surface_manager_->d3d_11_device(),
        surface_manager_->d3d_11_device_context());
    mpv_render_context_set_update_callback(
        render_context_,
        [](void* context) {
          auto* bridge = static_cast<NativePlayerBridge*>(context);
          ++bridge->render_request_count_;
          bridge->render_requested_ = true;
          bridge->condition_.notify_one();
        },
        this);
    lifecycle_ = "mpv_ready";
  } catch (...) {
    lifecycle_ = "angle_initialization_failed";
    DestroyPlayer();
  }
}

void NativePlayerBridge::DestroyPlayer() {
  rendering_enabled_ = false;
  if (render_context_ != nullptr) {
    mpv_render_context_set_update_callback(render_context_, nullptr, nullptr);
    mpv_render_context_free(render_context_);
    render_context_ = nullptr;
  }
  {
    std::lock_guard<std::mutex> surface_lock(surface_mutex_);
    // 插件可能持有同设备资源，必须先关闭再销毁 ANGLE 表面。
    video_enhancement_plugin_.Shutdown();
    surface_manager_.reset();
  }
  if (player_ != nullptr) {
    mpv_terminate_destroy(player_);
    player_ = nullptr;
  }
  playing_ = false;
  buffering_ = false;
  lifecycle_ = native_hwnd_enabled_ ? "mpv_hwnd_disposed" : "mpv_disposed";
}

void NativePlayerBridge::ExecutePlayerCommand(const Command& command) {
  if (player_ == nullptr) return;
  if (command.name == "open") {
    const char* arguments[] = {"loadfile", command.text.c_str(), "replace",
                               nullptr};
    mpv_command_async(player_, 0, arguments);
  } else if (command.name == "play" || command.name == "pause") {
    int paused = command.name == "pause" ? 1 : 0;
    mpv_set_property(player_, "pause", MPV_FORMAT_FLAG, &paused);
  } else if (command.name == "stop") {
    const char* arguments[] = {"stop", nullptr};
    mpv_command_async(player_, 0, arguments);
  } else if (command.name == "seek") {
    double seconds = static_cast<double>(command.integer) / 1000.0;
    mpv_set_property(player_, "time-pos", MPV_FORMAT_DOUBLE, &seconds);
  } else if (command.name == "volume") {
    double value = static_cast<double>(command.integer) / 1000.0;
    mpv_set_property(player_, "volume", MPV_FORMAT_DOUBLE, &value);
  } else if (command.name == "rate") {
    double value = static_cast<double>(command.integer) / 1000.0;
    mpv_set_property(player_, "speed", MPV_FORMAT_DOUBLE, &value);
  } else if (command.name == "property") {
    const auto separator = command.text.find('=');
    if (separator != std::string::npos) {
      const auto property = command.text.substr(0, separator);
      auto value = command.text.substr(separator + 1);
      if (native_hwnd_enabled_ && property == "hwdec") {
        // child HWND 门禁专门验证 D3D11VA 非 copy 链。通用播放设置仍可保留
        // auto-safe，但不得在会话初始化后把这个隔离实验覆盖成 copy 后端。
        value = "d3d11va";
      }
      mpv_set_property_string(player_, property.c_str(), value.c_str());
    }
  }
}

void NativePlayerBridge::SamplePlayerState() {
  if (player_ == nullptr) return;
  // 事件与属性在同一原生工作线程消费，避免 EOF、错误回调与控制命令交叉修改会话状态。
  while (const mpv_event* event = mpv_wait_event(player_, 0.0)) {
    if (event->event_id == MPV_EVENT_NONE) break;
    if (event->event_id == MPV_EVENT_FILE_LOADED) {
      lifecycle_ = "media_loaded";
      last_error_.clear();
    } else if (event->event_id == MPV_EVENT_END_FILE) {
      const auto* end_file = static_cast<const mpv_event_end_file*>(event->data);
      if (end_file != nullptr && end_file->reason == MPV_END_FILE_REASON_EOF) {
        ++completed_count_;
        lifecycle_ = "media_completed";
      } else if (end_file != nullptr &&
                 end_file->reason == MPV_END_FILE_REASON_ERROR) {
        ++error_count_;
        last_error_ = mpv_error_string(end_file->error);
        lifecycle_ = "media_error";
      }
    }
  }
  auto read_double = [this](const char* name, double fallback) {
    double value = fallback;
    return mpv_get_property(player_, name, MPV_FORMAT_DOUBLE, &value) >= 0
               ? value
               : fallback;
  };
  auto read_int = [this](const char* name, int64_t fallback) {
    int64_t value = fallback;
    return mpv_get_property(player_, name, MPV_FORMAT_INT64, &value) >= 0
               ? value
               : fallback;
  };
  auto read_string = [this](const char* name) {
    char* value = mpv_get_property_string(player_, name);
    const std::string result = value == nullptr ? "unavailable" : value;
    if (value != nullptr) mpv_free(value);
    return result;
  };
  position_ms_ = static_cast<int64_t>(read_double("time-pos", 0.0) * 1000);
  duration_ms_ = static_cast<int64_t>(read_double("duration", 0.0) * 1000);
  int paused = 1;
  mpv_get_property(player_, "pause", MPV_FORMAT_FLAG, &paused);
  playing_ = paused == 0;
  int buffering = 0;
  mpv_get_property(player_, "paused-for-cache", MPV_FORMAT_FLAG, &buffering);
  buffering_ = buffering != 0;
  volume_ = read_double("volume", volume_);
  avsync_ = read_double("avsync", avsync_);
  audio_pts_ = read_double("audio-pts", audio_pts_);
  cache_duration_ = read_double("demuxer-cache-duration", cache_duration_);
  estimated_vf_fps_ = read_double("estimated-vf-fps", estimated_vf_fps_);
  display_fps_ = read_double("display-fps", display_fps_);
  frame_number_ = read_int("estimated-frame-number", frame_number_);
  dropped_frames_ = read_int("frame-drop-count", dropped_frames_);
  hwdec_ = read_string("hwdec-current");
  video_codec_ = read_string("video-codec");
  audio_codec_ = read_string("audio-codec");
}

void NativePlayerBridge::RenderFrame() {
  if (!rendering_enabled_ || render_context_ == nullptr ||
      surface_manager_ == nullptr) {
    return;
  }
  const auto update_flags = mpv_render_context_update(render_context_);
  if ((update_flags & MPV_RENDER_UPDATE_FRAME) == 0) {
    ++skipped_render_count_;
    return;
  }
  std::lock_guard<std::mutex> surface_lock(surface_mutex_);
  if (!rendering_enabled_ || surface_manager_ == nullptr) return;
  const auto desired_width = desired_surface_width_.load();
  const auto desired_height = desired_surface_height_.load();
  if (desired_width != surface_manager_->width() ||
      desired_height != surface_manager_->height()) {
    surface_manager_->SetSize(desired_width, desired_height);
    surface_width_ = surface_manager_->width();
    surface_height_ = surface_manager_->height();
    ++surface_resize_count_;
  }
  surface_manager_->Draw([this]() {
    mpv_opengl_fbo framebuffer{0, surface_manager_->width(),
                               surface_manager_->height(), 0};
    mpv_render_param parameters[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &framebuffer},
        {MPV_RENDER_PARAM_INVALID, nullptr}};
    mpv_render_context_render(render_context_, parameters);
  });
  // 在原生工作线程完成共享纹理复制和插件处理，Flutter raster 回调只读取成品描述符。
  surface_manager_->Read();
  ++texture_copy_count_;
  video_enhancement_plugin_.ProcessFrame(
      surface_manager_->d3d_11_device(),
      surface_manager_->d3d_11_device_context(),
      surface_manager_->d3d_11_texture(),
      static_cast<uint64_t>(rendered_frame_count_.load() + 1));
  ++rendered_frame_count_;
  if (texture_id_ >= 0) textures_->MarkTextureFrameAvailable(texture_id_);
}

void NativePlayerBridge::Enqueue(Command command) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    commands_.push(std::move(command));
  }
  condition_.notify_one();
}

void NativePlayerBridge::EnqueueAndWait(Command command) {
  command.completion = std::make_shared<std::promise<void>>();
  auto completed = command.completion->get_future();
  Enqueue(std::move(command));
  completed.wait();
}

void NativePlayerBridge::WorkerLoop() {
  while (true) {
    Command command;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      condition_.wait_for(lock, std::chrono::milliseconds(50), [this]() {
        return shutting_down_ || !commands_.empty() || render_requested_;
      });
      if (shutting_down_) return;
      if (commands_.empty()) {
        const bool should_render = render_requested_.exchange(false);
        lock.unlock();
        if (should_render) RenderFrame();
        lock.lock();
        SamplePlayerState();
        continue;
      }
      command = std::move(commands_.front());
      commands_.pop();
      lifecycle_ = "command_" + command.name;
      if (command.name == "initialize") {
        InitializePlayer();
      } else if (command.name == "destroy") {
        DestroyPlayer();
      } else if (native_mpv_enabled_) {
        ExecutePlayerCommand(command);
        SamplePlayerState();
      }
      if (!native_mpv_enabled_) {
        if (command.name == "open") {
          position_ms_ = 0;
          duration_ms_ = 1;
          buffering_ = false;
        } else if (command.name == "play") {
          playing_ = true;
        } else if (command.name == "pause" || command.name == "stop" ||
                   command.name == "dispose") {
          playing_ = false;
        } else if (command.name == "seek") {
          position_ms_ = command.integer;
        } else if (command.name == "volume") {
          volume_ = static_cast<double>(command.integer) / 1000.0;
        }
      }
    }
    if (command.completion != nullptr) command.completion->set_value();
  }
}

flutter::EncodableMap NativePlayerBridge::StateSnapshot() const {
  std::lock_guard<std::mutex> lock(mutex_);
  const auto plugin = video_enhancement_plugin_.GetSnapshot();
  return {{flutter::EncodableValue("textureId"),
           flutter::EncodableValue(texture_id_)},
          {flutter::EncodableValue("positionMs"),
           flutter::EncodableValue(position_ms_)},
          {flutter::EncodableValue("durationMs"),
           flutter::EncodableValue(duration_ms_)},
          {flutter::EncodableValue("playing"), flutter::EncodableValue(playing_)},
          {flutter::EncodableValue("buffering"),
           flutter::EncodableValue(buffering_)},
          {flutter::EncodableValue("volume"), flutter::EncodableValue(volume_)},
          {flutter::EncodableValue("lifecycle"),
           flutter::EncodableValue(lifecycle_)},
          {flutter::EncodableValue("backend"),
           flutter::EncodableValue(
               native_hwnd_enabled_
                   ? "windows-native-hwnd"
                   : native_mpv_enabled_ ? "windows-native-mpv"
                                         : "windows-native-stub")},
          {flutter::EncodableValue("native-surface-kind"),
           flutter::EncodableValue(native_hwnd_enabled_ ? "child-hwnd"
                                                        : "flutter-texture")},
          {flutter::EncodableValue("native-surface-visible"),
           flutter::EncodableValue(hwnd_surface_visible_)},
          {flutter::EncodableValue("native-surface-occluded"),
           flutter::EncodableValue(hwnd_surface_occluded_)},
          {flutter::EncodableValue("native-input-forwarding"),
           flutter::EncodableValue(native_hwnd_enabled_)},
          {flutter::EncodableValue("native-input-mode"),
           flutter::EncodableValue(native_hwnd_enabled_
                                        ? "hit-test-transparent"
                                        : "flutter-texture")},
          {flutter::EncodableValue("native-airspace-inset-top"),
           flutter::EncodableValue(native_hwnd_enabled_ ? 64 : 0)},
          {flutter::EncodableValue("native-airspace-inset-bottom"),
           flutter::EncodableValue(native_hwnd_enabled_ ? 128 : 0)},
          {flutter::EncodableValue("hwdec-current"),
           flutter::EncodableValue(hwdec_)},
          {flutter::EncodableValue("video-codec"),
           flutter::EncodableValue(video_codec_)},
          {flutter::EncodableValue("audio-codec"),
           flutter::EncodableValue(audio_codec_)},
          {flutter::EncodableValue("avsync"), flutter::EncodableValue(avsync_)},
          {flutter::EncodableValue("audio-pts"),
           flutter::EncodableValue(audio_pts_)},
          {flutter::EncodableValue("demuxer-cache-duration"),
           flutter::EncodableValue(cache_duration_)},
          {flutter::EncodableValue("estimated-vf-fps"),
           flutter::EncodableValue(estimated_vf_fps_)},
          {flutter::EncodableValue("display-fps"),
           flutter::EncodableValue(display_fps_)},
          {flutter::EncodableValue("estimated-frame-number"),
           flutter::EncodableValue(frame_number_)},
          {flutter::EncodableValue("frame-drop-count"),
           flutter::EncodableValue(dropped_frames_)},
          {flutter::EncodableValue("native-render-requests"),
           flutter::EncodableValue(render_request_count_.load())},
          {flutter::EncodableValue("native-rendered-frames"),
           flutter::EncodableValue(rendered_frame_count_.load())},
          {flutter::EncodableValue("native-skipped-renders"),
           flutter::EncodableValue(skipped_render_count_.load())},
          {flutter::EncodableValue("native-texture-copies"),
           flutter::EncodableValue(texture_copy_count_.load())},
          {flutter::EncodableValue("native-surface-resizes"),
           flutter::EncodableValue(surface_resize_count_.load())},
          {flutter::EncodableValue("native-surface-left"),
           flutter::EncodableValue(surface_left_.load())},
          {flutter::EncodableValue("native-surface-top"),
           flutter::EncodableValue(surface_top_.load())},
          {flutter::EncodableValue("native-surface-width"),
           flutter::EncodableValue(surface_width_.load())},
          {flutter::EncodableValue("native-surface-height"),
           flutter::EncodableValue(surface_height_.load())},
          {flutter::EncodableValue("native-video-plugin-state"),
           flutter::EncodableValue(plugin.state)},
          {flutter::EncodableValue("native-video-plugin-name"),
           flutter::EncodableValue(plugin.name)},
          {flutter::EncodableValue("native-video-plugin-frames"),
           flutter::EncodableValue(plugin.processed_frames)},
          {flutter::EncodableValue("native-video-plugin-fallbacks"),
           flutter::EncodableValue(plugin.fallback_frames)},
          {flutter::EncodableValue("native-video-plugin-error"),
           flutter::EncodableValue(plugin.error)},
          {flutter::EncodableValue("completedCount"),
           flutter::EncodableValue(completed_count_)},
          {flutter::EncodableValue("errorCount"),
           flutter::EncodableValue(error_count_)},
          {flutter::EncodableValue("lastError"),
           flutter::EncodableValue(last_error_)}};
}
