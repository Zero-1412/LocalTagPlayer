#include "native_player_bridge.h"

#include <chrono>
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
}  // namespace

NativePlayerBridge::NativePlayerBridge(flutter::BinaryMessenger* messenger,
                                       flutter::TextureRegistrar* textures)
    : textures_(textures),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
  worker_ = std::thread([this]() { WorkerLoop(); });
}

NativePlayerBridge::~NativePlayerBridge() {
  channel_->SetMethodCallHandler(nullptr);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    shutting_down_ = true;
  }
  condition_.notify_one();
  if (worker_.joinable()) worker_.join();
  DisposeSession();
}

void NativePlayerBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
  const flutter::EncodableMap empty;
  const auto& values = arguments == nullptr ? empty : *arguments;
  if (call.method_name() == "create") {
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

void NativePlayerBridge::EnsureTexture() {
  if (texture_id_ >= 0) return;
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
  const int64_t texture = texture_id_;
  texture_id_ = -1;
  if (texture >= 0) {
    textures_->UnregisterTexture(texture);
    pixel_texture_.reset();
  }
  std::lock_guard<std::mutex> lock(mutex_);
  playing_ = false;
  buffering_ = false;
  lifecycle_ = "disposed";
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
      condition_.wait(lock,
                      [this]() { return shutting_down_ || !commands_.empty(); });
      if (shutting_down_) return;
      command = std::move(commands_.front());
      commands_.pop();
      lifecycle_ = "command_" + command.name;
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
           flutter::EncodableValue("windows-native-stub")}};
}
