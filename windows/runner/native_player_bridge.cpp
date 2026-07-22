#include "native_player_bridge.h"

#include "gpu_capability_probe.h"

#include <algorithm>
#include <chrono>
#include <mpv/render_gl.h>
#include <utility>

namespace {
constexpr char kChannelName[] = "local_tag_player/native_player";

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

/** 将 Flutter 请求尺寸量化并限制在原生纹理预算内，避免窗口动画产生频繁小幅重建。 */
int32_t NormalizeSurfaceDimension(size_t value, int32_t minimum,
                                  int32_t maximum, int32_t quantum) {
  const auto capped = std::min(value, static_cast<size_t>(maximum));
  const auto safe = std::max(static_cast<int32_t>(capped), minimum);
  return std::min(((safe + quantum - 1) / quantum) * quantum, maximum);
}
}  // namespace

NativePlayerBridge::NativePlayerBridge(flutter::BinaryMessenger* messenger,
                                       flutter::TextureRegistrar* textures)
    : textures_(textures),
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
  if (call.method_name() == "create") {
    const auto mode = StringArgument(values, "mode");
    native_mpv_enabled_ = mode == "mpv";
    if (native_mpv_enabled_) {
      EnqueueAndWait({"initialize", {}, 0, nullptr});
    }
    EnsureTexture();
    result->Success(flutter::EncodableValue(StateSnapshot()));
    return;
  }
  if (call.method_name() == "state") {
    result->Success(flutter::EncodableValue(StateSnapshot()));
    return;
  }
  if (call.method_name() == "dispose") {
    EnqueueAndWait({"dispose", {}, 0, nullptr});
    DisposeSession();
    if (native_mpv_enabled_) {
      EnqueueAndWait({"destroy", {}, 0, nullptr});
    }
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
              surface_manager_->Read();
              gpu_descriptor_->handle = surface_manager_->handle();
              gpu_descriptor_->width = gpu_descriptor_->visible_width =
                  surface_manager_->width();
              gpu_descriptor_->height = gpu_descriptor_->visible_height =
                  surface_manager_->height();
              ++texture_copy_count_;
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
  lifecycle_ = "mpv_initializing";
  player_ = mpv_create();
  if (player_ == nullptr) {
    lifecycle_ = "mpv_create_failed";
    return;
  }
  mpv_set_option_string(player_, "vo", "libmpv");
  mpv_set_option_string(player_, "hwdec", "d3d11va-copy");
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
    surface_manager_.reset();
  }
  if (player_ != nullptr) {
    mpv_terminate_destroy(player_);
    player_ = nullptr;
  }
  playing_ = false;
  buffering_ = false;
  lifecycle_ = "mpv_disposed";
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
      mpv_set_property_string(player_, command.text.substr(0, separator).c_str(),
                              command.text.substr(separator + 1).c_str());
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
           flutter::EncodableValue(native_mpv_enabled_ ? "windows-native-mpv"
                                                       : "windows-native-stub")},
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
          {flutter::EncodableValue("native-surface-width"),
           flutter::EncodableValue(surface_width_.load())},
          {flutter::EncodableValue("native-surface-height"),
           flutter::EncodableValue(surface_height_.load())},
          {flutter::EncodableValue("completedCount"),
           flutter::EncodableValue(completed_count_)},
          {flutter::EncodableValue("errorCount"),
           flutter::EncodableValue(error_count_)},
          {flutter::EncodableValue("lastError"),
           flutter::EncodableValue(last_error_)}};
}
