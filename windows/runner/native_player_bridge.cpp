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
constexpr wchar_t kD3D11VaZeroCopyQaEnvironment[] =
    L"LOCAL_TAG_PLAYER_D3D11VA_ZERO_COPY_QA";

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

/** 只接受显式值 `1`，避免继承到含糊环境文本时误开高风险驱动路径。 */
bool IsQaEnvironmentEnabled(const wchar_t* name) {
  std::array<wchar_t, 2> value{};
  const DWORD length =
      GetEnvironmentVariableW(name, value.data(), static_cast<DWORD>(value.size()));
  return length == 1 && value[0] == L'1';
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
    if (!native_hwnd_enabled_) d3d11va_zero_copy_ = "no";
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
    result->Success(flutter::EncodableValue(StateSnapshot()));
    return;
  }
  if (call.method_name() == "setProperties") {
    const auto iterator =
        values.find(flutter::EncodableValue("properties"));
    const auto* properties = iterator == values.end()
                                 ? nullptr
                                 : std::get_if<flutter::EncodableList>(
                                       &iterator->second);
    if (properties != nullptr) {
      for (size_t index = 0; index < properties->size(); ++index) {
        const auto* property =
            std::get_if<flutter::EncodableMap>(&properties->at(index));
        if (property == nullptr) continue;
        const bool sample_state = index + 1 == properties->size();
        EnqueueAndWait(
            {"property",
             StringArgument(*property, "property") + "=" +
                 StringArgument(*property, "value"),
             0, nullptr, sample_state});
      }
    }
    result->Success(flutter::EncodableValue(StateSnapshot()));
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
  } else if (backend_kind == "windows-native" && native_hwnd_enabled_) {
    std::lock_guard<std::mutex> lock(mutex_);
    const std::string detection_source =
        "windows-native-mpv-selected-d3d11-adapter";
    if (d3d11_adapter_.ready()) {
      return flutter::EncodableMap{
          {flutter::EncodableValue("probeStatus"),
           flutter::EncodableValue("ready")},
          {flutter::EncodableValue("detectionSource"),
           flutter::EncodableValue(detection_source)},
          {flutter::EncodableValue("adapterLuid"),
           flutter::EncodableValue(d3d11_adapter_.luid)}};
    }
    return flutter::EncodableMap{
        {flutter::EncodableValue("probeStatus"),
         flutter::EncodableValue(
             d3d11_adapter_.state == "ambiguous" ? "ambiguous"
                                                  : "unavailable")},
        {flutter::EncodableValue("detectionSource"),
         flutter::EncodableValue(detection_source)},
        {flutter::EncodableValue("errorCode"),
         flutter::EncodableValue(d3d11_adapter_.error)}};
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
  airspace_inset_top_ = std::max<int64_t>(
      0, IntegerArgument(arguments, "airspaceTop"));
  airspace_inset_bottom_ = std::max<int64_t>(
      0, IntegerArgument(arguments, "airspaceBottom"));
  surface_view_width_ = view_width;
  surface_view_height_ = view_height;
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
  bool partial_occlusion = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    hwnd_surface_requested_visible_ = requested_visible;
    occluded = hwnd_surface_occluded_;
    partial_occlusion = hwnd_surface_partial_occlusion_;
  }
  const bool visible = requested_visible && (!occluded || partial_occlusion);
  // region 计算必须先看到本次最终矩形，不能在窗口移动后仍使用上一帧尺寸。
  surface_left_ = left;
  surface_top_ = top;
  surface_width_ = width;
  surface_height_ = height;
  if (visible) {
    SetWindowPos(video_host_window_, HWND_TOP, left, top, width, height,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
    // 内层由 mpv 使用，外层始终裁剪其输出，防止媒体加载时 wid 自行扩张越界。
    SetWindowPos(mpv_render_window_, HWND_TOP, 0, 0, width, height,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
    ApplyHwndSurfaceOcclusionRegion();
  } else {
    ShowWindow(video_host_window_, SW_HIDE);
  }
  std::lock_guard<std::mutex> lock(mutex_);
  hwnd_surface_visible_ = visible;
}

void NativePlayerBridge::SetHwndSurfaceOccluded(
    const flutter::EncodableMap& arguments) {
  if (!native_hwnd_enabled_ || video_host_window_ == nullptr) return;
  const bool occluded = BooleanArgument(arguments, "occluded");
  const bool partial =
      occluded && BooleanArgument(arguments, "partial");
  bool should_show = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    hwnd_surface_occluded_ = occluded;
    hwnd_surface_partial_occlusion_ = partial;
    if (partial) {
      overlay_left_ = IntegerArgument(arguments, "overlayLeft");
      overlay_top_ = IntegerArgument(arguments, "overlayTop");
      overlay_width_ =
          std::max<int64_t>(0, IntegerArgument(arguments, "overlayWidth"));
      overlay_height_ =
          std::max<int64_t>(0, IntegerArgument(arguments, "overlayHeight"));
      overlay_view_width_ =
          std::max<int64_t>(1, IntegerArgument(arguments, "viewWidth"));
      overlay_view_height_ =
          std::max<int64_t>(1, IntegerArgument(arguments, "viewHeight"));
    }
    should_show = hwnd_surface_requested_visible_ && (!occluded || partial);
    hwnd_surface_visible_ = should_show;
  }
  if (!should_show) {
    SetWindowRgn(video_host_window_, nullptr, TRUE);
    ShowWindow(video_host_window_, SW_HIDE);
    return;
  }
  ApplyHwndSurfaceOcclusionRegion();
  // 恢复最后一次 Flutter 布局矩形，避免弹层关闭后等待下一次布局才重新出画。
  SetWindowPos(video_host_window_, HWND_TOP, surface_left_, surface_top_,
               surface_width_, surface_height_,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  SetWindowPos(mpv_render_window_, HWND_TOP, 0, 0, surface_width_,
               surface_height_, SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void NativePlayerBridge::ApplyHwndSurfaceOcclusionRegion() {
  if (video_host_window_ == nullptr) return;
  RECT parent_bounds{};
  GetClientRect(flutter_view_window_, &parent_bounds);
  const double control_scale_y =
      static_cast<double>(parent_bounds.bottom - parent_bounds.top) /
      static_cast<double>(std::max<int64_t>(surface_view_height_, 1));
  const int width = surface_width_.load();
  const int height = surface_height_.load();
  const int top_control_height = std::clamp(
      static_cast<int>(std::ceil(airspace_inset_top_.load() * control_scale_y)),
      0, height);
  const int bottom_control_height = std::clamp(
      static_cast<int>(
          std::ceil(airspace_inset_bottom_.load() * control_scale_y)),
      0, height);
  const bool has_control_occlusion =
      top_control_height > 0 || bottom_control_height > 0;
  if (!has_control_occlusion && !hwnd_surface_partial_occlusion_) {
    SetWindowRgn(video_host_window_, nullptr, TRUE);
    return;
  }

  HRGN visible_region = CreateRectRgn(0, 0, width, height);
  if (visible_region == nullptr) return;
  const auto subtract_region =
      [visible_region, width, height](int left, int top, int right, int bottom) {
        const int clipped_left = std::clamp(left, 0, width);
        const int clipped_top = std::clamp(top, 0, height);
        const int clipped_right = std::clamp(right, 0, width);
        const int clipped_bottom = std::clamp(bottom, 0, height);
        if (clipped_left >= clipped_right || clipped_top >= clipped_bottom) {
          return;
        }
        HRGN occlusion_region = CreateRectRgn(
            clipped_left, clipped_top, clipped_right, clipped_bottom);
        if (occlusion_region == nullptr) return;
        CombineRgn(visible_region, visible_region, occlusion_region, RGN_DIFF);
        DeleteObject(occlusion_region);
      };
  subtract_region(0, 0, width, top_control_height);
  subtract_region(
      0, height - bottom_control_height, width, height);

  if (hwnd_surface_partial_occlusion_) {
    const double overlay_scale_x =
        static_cast<double>(parent_bounds.right - parent_bounds.left) /
        static_cast<double>(std::max<int64_t>(overlay_view_width_, 1));
    const double overlay_scale_y =
        static_cast<double>(parent_bounds.bottom - parent_bounds.top) /
        static_cast<double>(std::max<int64_t>(overlay_view_height_, 1));
    const int overlay_left = static_cast<int>(
        std::floor(overlay_left_ * overlay_scale_x)) - surface_left_;
    const int overlay_top = static_cast<int>(
        std::floor(overlay_top_ * overlay_scale_y)) - surface_top_;
    const int overlay_right = static_cast<int>(
        std::ceil((overlay_left_ + overlay_width_) * overlay_scale_x)) -
        surface_left_;
    const int overlay_bottom = static_cast<int>(
        std::ceil((overlay_top_ + overlay_height_) * overlay_scale_y)) -
        surface_top_;
    subtract_region(
        overlay_left, overlay_top, overlay_right, overlay_bottom);
  }

  // SetWindowRgn 成功后由系统接管 region；失败时仍由当前进程释放。
  if (SetWindowRgn(video_host_window_, visible_region, TRUE) == 0) {
    DeleteObject(visible_region);
  }
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
  hwnd_surface_partial_occlusion_ = false;
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
              std::lock_guard<std::mutex> descriptor_lock(
                  surface_descriptor_mutex_);
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
  // 驱动探测只读 System32 固定模块，不创建 OF 会话或占用视频纹理。
  nvofa_driver_ = ProbeNvidiaOpticalFlowDriver();
  d3d11_adapter_ = D3D11AdapterSelection{};
  if (native_hwnd_enabled_) {
    // mpv 只公开按名称选择 D3D11 adapter；先用 DXGI 得到唯一名称和 LUID，
    // 再把同一 LUID 交给 CUDA/NVOFA，禁止两个子系统各自使用默认设备。
    d3d11_adapter_ = SelectNvidiaD3D11Adapter();
  }
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
    d3d11va_zero_copy_ =
        IsQaEnvironmentEnabled(kD3D11VaZeroCopyQaEnvironment) ? "requested"
                                                               : "no";
    if (d3d11va_zero_copy_ == "requested" &&
        mpv_set_option_string(player_, "d3d11va-zero-copy", "yes") < 0) {
      d3d11va_zero_copy_ = "rejected";
    }
    if (d3d11_adapter_.ready() &&
        mpv_set_option_string(
            player_, "d3d11-adapter",
            d3d11_adapter_.description.c_str()) < 0) {
      d3d11_adapter_.state = "rejected";
      d3d11_adapter_.error = "mpv-d3d11-adapter-option-rejected";
      d3d11_adapter_.description.clear();
      d3d11_adapter_.luid.clear();
    }
    mpv_set_option_string(player_, "input-default-bindings", "no");
    mpv_set_option_string(player_, "input-cursor", "no");
    int64_t window_id =
        static_cast<int64_t>(reinterpret_cast<intptr_t>(mpv_render_window_));
    mpv_set_option(player_, "wid", MPV_FORMAT_INT64, &window_id);
  } else {
    mpv_set_option_string(player_, "vo", "libmpv");
    mpv_set_option_string(player_, "hwdec", "d3d11va-copy");
  }
  // 仅预加载用户显式配置的本机运行时；NVOFA 路径还必须取得同一 D3D11 LUID。
  motion_runtime_.Initialize(
      native_hwnd_enabled_ && d3d11_adapter_.ready()
          ? d3d11_adapter_.luid
          : std::string());
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
  // 参考 media_kit 的 libmpv 调用边界：回调只负责唤醒，所有事件仍由本类唯一
  // 工作线程串行消费，避免固定间隔扫描属性和跨线程读取 mpv_event。
  mpv_set_wakeup_callback(
      player_,
      [](void* context) {
        auto* bridge = static_cast<NativePlayerBridge*>(context);
        bridge->event_requested_ = true;
        bridge->condition_.notify_one();
      },
      this);
  RegisterObservedProperties();
  if (d3d11va_zero_copy_ == "requested") {
    char* value = mpv_get_property_string(player_, "d3d11va-zero-copy");
    d3d11va_zero_copy_ = value == nullptr ? "unavailable" : value;
    if (value != nullptr) mpv_free(value);
  }
  // NVIDIA 扩展的成功文本位于 verbose 级别，但只有 child HWND 能通过对应门禁。
  // Texture 产品会话降到 warn，避免无用 verbose 日志与 60fps 状态事件争夺工作线程。
  // 两种模式都只匹配固定文本并输出枚举，绝不把媒体路径或原始日志传给 Flutter。
  mpv_request_log_messages(player_, native_hwnd_enabled_ ? "v" : "warn");
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
  event_requested_ = false;
  if (render_context_ != nullptr) {
    mpv_render_context_set_update_callback(render_context_, nullptr, nullptr);
    mpv_render_context_free(render_context_);
    render_context_ = nullptr;
  }
  {
    std::lock_guard<std::mutex> surface_lock(surface_mutex_);
    // 插件可能持有同设备资源，必须先关闭再销毁 ANGLE 表面。
    video_enhancement_plugin_.Shutdown();
    std::lock_guard<std::mutex> descriptor_lock(
        surface_descriptor_mutex_);
    surface_manager_.reset();
  }
  if (player_ != nullptr) {
    // 先断开可能来自 mpv 内部线程的唤醒，再销毁桥接对象拥有的会话状态。
    mpv_set_wakeup_callback(player_, nullptr, nullptr);
    mpv_terminate_destroy(player_);
    player_ = nullptr;
  }
  // VSScript 必须晚于 mpv 会话释放，避免滤镜线程仍持有运行时函数表。
  motion_runtime_.Shutdown();
  playing_ = false;
  buffering_ = false;
  lifecycle_ = native_hwnd_enabled_ ? "mpv_hwnd_disposed" : "mpv_disposed";
}

void NativePlayerBridge::ExecutePlayerCommand(const Command& command) {
  if (player_ == nullptr) return;
  if (command.name == "open") {
    // 新媒体的观察事件尚未到达前先清除旧媒体身份，避免诊断短暂引用上一条视频。
    position_ms_ = 0;
    duration_ms_ = 0;
    buffering_ = true;
    frame_number_ = 0;
    frame_number_observed_ = false;
    frame_number_source_ = "unavailable";
    video_width_ = 0;
    video_height_ = 0;
    video_codec_ = "unavailable";
    audio_codec_ = "unavailable";
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
  } else if (command.name == "motion-interpolation") {
    // 插帧脚本路径只存在于原生宿主，Flutter 仅发送布尔意图。
    motion_runtime_.Apply(player_, command.integer != 0);
  } else if (command.name == "screenshot") {
    // Dart 只传入应用生成的临时路径；使用 video 模式保留滤镜输出且不包含
    // Flutter 控制层，便于 NVIDIA/压缩增强做同帧 A/B。
    const char* arguments[] = {"screenshot-to-file", command.text.c_str(),
                               "video", nullptr};
    mpv_command(player_, arguments);
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
      const auto result =
          mpv_set_property_string(player_, property.c_str(), value.c_str());
      if (property == "vf") {
        if (result >= 0) video_filters_ = value;
        if (value.find("scaling-mode=nvidia") == std::string::npos) {
          nvidia_vsr_state_ = "inactive";
        } else {
          nvidia_vsr_state_ = result >= 0 ? "requested" : "rejected";
        }
        if (value.find("nvidia-true-hdr") == std::string::npos) {
          nvidia_hdr_state_ = "inactive";
        } else {
          nvidia_hdr_state_ = result >= 0 ? "requested" : "rejected";
        }
        if (result >= 0) {
          // 压缩增强会重写完整滤镜图；已启用插帧必须以结构化条目重新追加。
          motion_runtime_.ReapplyAfterFilterGraphChange(player_);
        }
      }
    }
  }
}

void NativePlayerBridge::RegisterObservedProperties() {
  if (player_ == nullptr) return;
  struct ObservedProperty {
    const char* name;
    mpv_format format;
  };
  // 与 media_kit 一样请求属性的原生类型，让 libmpv 合并连续变化；Dart 仍只按
  // 100ms 读取快照，避免 60fps 的 time-pos 直接触发 Flutter rebuild。
  static constexpr ObservedProperty properties[] = {
      {"pause", MPV_FORMAT_FLAG},
      {"paused-for-cache", MPV_FORMAT_FLAG},
      {"time-pos", MPV_FORMAT_DOUBLE},
      {"duration", MPV_FORMAT_DOUBLE},
      {"volume", MPV_FORMAT_DOUBLE},
      {"avsync", MPV_FORMAT_DOUBLE},
      {"audio-pts", MPV_FORMAT_DOUBLE},
      {"demuxer-cache-duration", MPV_FORMAT_DOUBLE},
      {"container-fps", MPV_FORMAT_DOUBLE},
      {"estimated-vf-fps", MPV_FORMAT_DOUBLE},
      {"display-fps", MPV_FORMAT_DOUBLE},
      {"estimated-frame-number", MPV_FORMAT_INT64},
      {"frame-drop-count", MPV_FORMAT_INT64},
      {"video-params/w", MPV_FORMAT_INT64},
      {"video-params/h", MPV_FORMAT_INT64},
      {"interpolation", MPV_FORMAT_FLAG},
      {"display-sync-active", MPV_FORMAT_FLAG},
      {"hwdec-current", MPV_FORMAT_STRING},
      {"d3d11va-zero-copy", MPV_FORMAT_STRING},
      {"mpv-version", MPV_FORMAT_STRING},
      {"vf", MPV_FORMAT_STRING},
      {"video-params/primaries", MPV_FORMAT_STRING},
      {"video-params/gamma", MPV_FORMAT_STRING},
      {"video-params/colorlevels", MPV_FORMAT_STRING},
      {"video-params/colormatrix", MPV_FORMAT_STRING},
      {"video-output-levels", MPV_FORMAT_STRING},
      {"video-target-params/colorlevels", MPV_FORMAT_STRING},
      {"video-codec", MPV_FORMAT_STRING},
      {"audio-codec", MPV_FORMAT_STRING},
      {"video-sync", MPV_FORMAT_STRING},
      {"tscale", MPV_FORMAT_STRING},
  };
  uint64_t reply = 1;
  for (const auto& property : properties) {
    mpv_observe_property(player_, reply++, property.name, property.format);
  }
}

void NativePlayerBridge::ApplyObservedProperty(
    const mpv_event_property& property) {
  if (property.name == nullptr) return;
  const std::string name(property.name);
  if (property.format == MPV_FORMAT_NONE || property.data == nullptr) {
    // 媒体切换期间只清除会误导诊断的媒体字段；会话级选项保留上次已确认值。
    if (name == "time-pos") position_ms_ = 0;
    if (name == "duration") duration_ms_ = 0;
    if (name == "video-params/w") video_width_ = 0;
    if (name == "video-params/h") video_height_ = 0;
    if (name == "audio-pts") audio_pts_ = "unavailable";
    if (name == "video-codec") video_codec_ = "unavailable";
    if (name == "audio-codec") audio_codec_ = "unavailable";
    return;
  }
  if (property.format == MPV_FORMAT_FLAG) {
    const bool value = *static_cast<const int*>(property.data) != 0;
    if (name == "pause") {
      playing_ = !value;
    } else if (name == "paused-for-cache") {
      buffering_ = value;
    } else if (name == "interpolation") {
      interpolation_ = value ? "yes" : "no";
    } else if (name == "display-sync-active") {
      display_sync_active_ = value ? "yes" : "no";
    }
    return;
  }
  if (property.format == MPV_FORMAT_DOUBLE) {
    const double value = *static_cast<const double*>(property.data);
    if (name == "time-pos") {
      position_ms_ = static_cast<int64_t>(value * 1000);
    } else if (name == "duration") {
      duration_ms_ = static_cast<int64_t>(value * 1000);
    } else if (name == "volume") {
      volume_ = value;
    } else if (name == "avsync") {
      avsync_ = value;
    } else if (name == "audio-pts") {
      audio_pts_ = std::to_string(value);
    } else if (name == "demuxer-cache-duration") {
      cache_duration_ = value;
    } else if (name == "container-fps") {
      container_fps_ = value;
    } else if (name == "estimated-vf-fps") {
      estimated_vf_fps_ = value;
    } else if (name == "display-fps") {
      display_fps_ = value;
    }
    return;
  }
  if (property.format == MPV_FORMAT_INT64) {
    const int64_t value = *static_cast<const int64_t*>(property.data);
    if (name == "estimated-frame-number") {
      frame_number_ = value;
      if (value > 0) {
        frame_number_observed_ = true;
        frame_number_source_ = "mpv-observed";
      }
    } else if (name == "frame-drop-count") {
      dropped_frames_ = value;
    } else if (name == "video-params/w") {
      video_width_ = value;
    } else if (name == "video-params/h") {
      video_height_ = value;
    }
    return;
  }
  if (property.format != MPV_FORMAT_STRING) return;
  const char* value = *static_cast<char* const*>(property.data);
  const std::string text = value == nullptr ? "unavailable" : value;
  if (name == "hwdec-current") {
    hwdec_ = text;
  } else if (name == "d3d11va-zero-copy") {
    if (d3d11va_zero_copy_ != "no" && d3d11va_zero_copy_ != "rejected") {
      d3d11va_zero_copy_ = text;
    }
  } else if (name == "mpv-version") {
    mpv_version_ = text;
  } else if (name == "vf") {
    video_filters_ = text == "unavailable" ? "" : text;
  } else if (name == "video-params/primaries") {
    video_primaries_ = text;
  } else if (name == "video-params/gamma") {
    video_gamma_ = text;
  } else if (name == "video-params/colorlevels") {
    video_color_levels_ = text;
  } else if (name == "video-params/colormatrix") {
    video_color_matrix_ = text;
  } else if (name == "video-output-levels") {
    video_output_levels_ = text;
  } else if (name == "video-target-params/colorlevels") {
    video_target_color_levels_ = text;
  } else if (name == "video-codec") {
    video_codec_ = text;
  } else if (name == "audio-codec") {
    audio_codec_ = text;
  } else if (name == "video-sync") {
    video_sync_ = text;
  } else if (name == "tscale") {
    temporal_scaler_ = text;
  }
}

bool NativePlayerBridge::DrainPlayerEvents() {
  if (player_ == nullptr) return false;
  // 事件与属性在同一原生工作线程消费，避免 EOF、错误回调与控制命令交叉修改会话状态。
  // media_kit 的 Dart 异步处理会在事件间自然让出；这里是单一 C++ 工作线程，必须
  // 显式限制单批数量，否则高频属性或 verbose 日志可能长期饿死 play/seek 与渲染。
  constexpr int kMaxEventsPerBatch = 128;
  int processed = 0;
  while (processed < kMaxEventsPerBatch) {
    const mpv_event* event = mpv_wait_event(player_, 0.0);
    if (event == nullptr) break;
    if (event->event_id == MPV_EVENT_NONE) break;
    ++processed;
    ++player_event_count_;
    if (event->event_id == MPV_EVENT_PROPERTY_CHANGE) {
      const auto* property =
          static_cast<const mpv_event_property*>(event->data);
      if (property != nullptr) ApplyObservedProperty(*property);
    } else if (event->event_id == MPV_EVENT_FILE_LOADED) {
      lifecycle_ = "media_loaded";
      last_error_.clear();
    } else if (event->event_id == MPV_EVENT_LOG_MESSAGE) {
      const auto* log_message =
          static_cast<const mpv_event_log_message*>(event->data);
      if (log_message != nullptr && log_message->text != nullptr) {
        const std::string text(log_message->text);
        if (text.find("NVIDIA RTX Super Resolution enabled") !=
            std::string::npos) {
          nvidia_vsr_state_ = "active";
        } else if (text.find(
                       "Failed to enable NVIDIA RTX Super Resolution") !=
                   std::string::npos) {
          nvidia_vsr_state_ = "rejected";
        }
        if (text.find("NVIDIA RTX Video HDR enabled") != std::string::npos) {
          nvidia_hdr_state_ = "active";
        } else if (text.find("NVIDIA RTX Video HDR not supported") !=
                       std::string::npos ||
                   text.find("Failed to enable NVIDIA RTX Video HDR") !=
                       std::string::npos) {
          nvidia_hdr_state_ = "rejected";
        } else if (text.find(
                       "NVIDIA RTX Video HDR requested, but the source is "
                       "already HDR, not used") != std::string::npos) {
          nvidia_hdr_state_ = "ignored-source-hdr";
        }
        motion_runtime_.ObserveLog(player_, log_message->prefix,
                                   log_message->text);
      }
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
  // estimated-frame-number 在当前固定 mpv 上只发送初值，不随播放持续观察。
  // 使用同样由 mpv 观察到的播放时间与滤镜 FPS 派生诊断帧号；它只服务停滞判断，
  // 不参与 seek、播放时钟或画面渲染。
  if (!frame_number_observed_ && estimated_vf_fps_ > 0.0 &&
      position_ms_ > 0) {
    frame_number_ = static_cast<int64_t>(
        static_cast<double>(position_ms_) * estimated_vf_fps_ / 1000.0);
    frame_number_source_ = "time-pos-fps-derived";
  }
  if (processed == kMaxEventsPerBatch) {
    ++event_batch_yield_count_;
    event_requested_ = true;
    condition_.notify_one();
  }
  motion_runtime_.ConfirmFrameRateIncrease(player_, container_fps_,
                                           estimated_vf_fps_);
  return processed == kMaxEventsPerBatch;
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
    std::lock_guard<std::mutex> descriptor_lock(
        surface_descriptor_mutex_);
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
      condition_.wait(lock, [this]() {
        return shutting_down_ || !commands_.empty() || render_requested_ ||
               event_requested_;
      });
      if (shutting_down_) return;
      if (commands_.empty()) {
        const bool should_render = render_requested_.exchange(false);
        const bool should_drain_events = event_requested_.exchange(false);
        lock.unlock();
        if (should_render) RenderFrame();
        lock.lock();
        const bool batch_saturated =
            should_drain_events && DrainPlayerEvents();
        if (batch_saturated) {
          // 事件风暴期间给 MethodChannel 快照与用户命令一个确定的抢锁窗口。
          lock.unlock();
          std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
        continue;
      }
      // libmpv 的更新回调代表有新视频帧可取；属性批次不能长期占满队列并让视频
      // 时钟在渲染前持续前进。每条控制命令前最多消费一个合并后的渲染请求。
      const bool should_render = render_requested_.exchange(false);
      if (should_render) {
        lock.unlock();
        RenderFrame();
        lock.lock();
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
        if (command.sample_state) DrainPlayerEvents();
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
  const auto motion = motion_runtime_.GetSnapshot();
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
          {flutter::EncodableValue("native-overlay-partial"),
           flutter::EncodableValue(hwnd_surface_partial_occlusion_)},
          {flutter::EncodableValue("native-overlay-left"),
           flutter::EncodableValue(overlay_left_)},
          {flutter::EncodableValue("native-overlay-top"),
           flutter::EncodableValue(overlay_top_)},
          {flutter::EncodableValue("native-overlay-width"),
           flutter::EncodableValue(overlay_width_)},
          {flutter::EncodableValue("native-overlay-height"),
           flutter::EncodableValue(overlay_height_)},
          {flutter::EncodableValue("native-input-forwarding"),
           flutter::EncodableValue(native_hwnd_enabled_)},
          {flutter::EncodableValue("native-input-mode"),
           flutter::EncodableValue(native_hwnd_enabled_
                                        ? "hit-test-transparent"
                                        : "flutter-texture")},
          {flutter::EncodableValue("native-airspace-inset-top"),
           flutter::EncodableValue(
               native_hwnd_enabled_ ? airspace_inset_top_.load() : 0)},
          {flutter::EncodableValue("native-airspace-inset-bottom"),
           flutter::EncodableValue(
               native_hwnd_enabled_ ? airspace_inset_bottom_.load() : 0)},
          {flutter::EncodableValue("hwdec-current"),
           flutter::EncodableValue(hwdec_)},
          {flutter::EncodableValue("d3d11va-zero-copy"),
           flutter::EncodableValue(d3d11va_zero_copy_)},
          {flutter::EncodableValue("mpv-version"),
           flutter::EncodableValue(mpv_version_)},
          {flutter::EncodableValue("vf"),
           flutter::EncodableValue(video_filters_)},
          {flutter::EncodableValue("native-nvidia-vsr-state"),
           flutter::EncodableValue(nvidia_vsr_state_)},
          {flutter::EncodableValue("native-nvidia-hdr-state"),
           flutter::EncodableValue(nvidia_hdr_state_)},
          {flutter::EncodableValue("video-params/primaries"),
           flutter::EncodableValue(video_primaries_)},
          {flutter::EncodableValue("video-params/gamma"),
           flutter::EncodableValue(video_gamma_)},
          {flutter::EncodableValue("video-params/colorlevels"),
           flutter::EncodableValue(video_color_levels_)},
          {flutter::EncodableValue("video-params/colormatrix"),
           flutter::EncodableValue(video_color_matrix_)},
          {flutter::EncodableValue("video-output-levels"),
           flutter::EncodableValue(video_output_levels_)},
          {flutter::EncodableValue("video-target-params/colorlevels"),
           flutter::EncodableValue(video_target_color_levels_)},
          {flutter::EncodableValue("video-params/w"),
           flutter::EncodableValue(video_width_)},
          {flutter::EncodableValue("video-params/h"),
           flutter::EncodableValue(video_height_)},
          {flutter::EncodableValue("video-codec"),
           flutter::EncodableValue(video_codec_)},
          {flutter::EncodableValue("audio-codec"),
           flutter::EncodableValue(audio_codec_)},
          {flutter::EncodableValue("avsync"), flutter::EncodableValue(avsync_)},
          {flutter::EncodableValue("audio-pts"),
           flutter::EncodableValue(audio_pts_)},
          {flutter::EncodableValue("demuxer-cache-duration"),
           flutter::EncodableValue(cache_duration_)},
          {flutter::EncodableValue("container-fps"),
           flutter::EncodableValue(container_fps_)},
          {flutter::EncodableValue("estimated-vf-fps"),
           flutter::EncodableValue(estimated_vf_fps_)},
          {flutter::EncodableValue("display-fps"),
           flutter::EncodableValue(display_fps_)},
          {flutter::EncodableValue("video-sync"),
           flutter::EncodableValue(video_sync_)},
          {flutter::EncodableValue("interpolation"),
           flutter::EncodableValue(interpolation_)},
          {flutter::EncodableValue("tscale"),
           flutter::EncodableValue(temporal_scaler_)},
          {flutter::EncodableValue("display-sync-active"),
           flutter::EncodableValue(display_sync_active_)},
          {flutter::EncodableValue("estimated-frame-number"),
           flutter::EncodableValue(frame_number_)},
          {flutter::EncodableValue("native-frame-number-source"),
           flutter::EncodableValue(frame_number_source_)},
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
          {flutter::EncodableValue("native-mpv-events"),
           flutter::EncodableValue(player_event_count_.load())},
          {flutter::EncodableValue("native-event-batch-yields"),
           flutter::EncodableValue(event_batch_yield_count_.load())},
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
          {flutter::EncodableValue("native-motion-interpolation-state"),
           flutter::EncodableValue(motion.state)},
          {flutter::EncodableValue("native-motion-interpolation-error"),
           flutter::EncodableValue(motion.error)},
          {flutter::EncodableValue("native-motion-interpolation-configured"),
           flutter::EncodableValue(motion.configured)},
          {flutter::EncodableValue("native-motion-interpolation-enabled"),
           flutter::EncodableValue(motion.enabled)},
          {flutter::EncodableValue("native-motion-interpolation-fallbacks"),
           flutter::EncodableValue(motion.fallback_count)},
          {flutter::EncodableValue("native-nvofa-driver-state"),
           flutter::EncodableValue(nvofa_driver_.state)},
          {flutter::EncodableValue("native-nvofa-driver-error"),
           flutter::EncodableValue(nvofa_driver_.error)},
          {flutter::EncodableValue("native-nvofa-api-version"),
           flutter::EncodableValue(
               static_cast<int64_t>(nvofa_driver_.api_version_raw))},
          {flutter::EncodableValue("native-nvofa-d3d11"),
           flutter::EncodableValue(nvofa_driver_.d3d11_available)},
          {flutter::EncodableValue("native-d3d11-adapter-state"),
           flutter::EncodableValue(d3d11_adapter_.state)},
          {flutter::EncodableValue("native-d3d11-adapter-error"),
           flutter::EncodableValue(d3d11_adapter_.error)},
          {flutter::EncodableValue("native-d3d11-adapter-luid"),
           flutter::EncodableValue(d3d11_adapter_.luid)},
          {flutter::EncodableValue("completedCount"),
           flutter::EncodableValue(completed_count_)},
          {flutter::EncodableValue("errorCount"),
           flutter::EncodableValue(error_count_)},
          {flutter::EncodableValue("lastError"),
           flutter::EncodableValue(last_error_)}};
}
