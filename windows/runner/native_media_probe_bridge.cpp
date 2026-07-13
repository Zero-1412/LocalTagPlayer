#include "native_media_probe_bridge.h"

extern "C" {
#pragma warning(push)
#pragma warning(disable : 4244)
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/error.h>
#pragma warning(pop)
}

#include <chrono>
#include <Windows.h>

namespace {
constexpr char kChannelName[] = "local_tag_player/media_probe";
constexpr int64_t kProbeTimeoutMillis = 6000;

/**
 * 延迟解析 FFmpeg C API，避免默认播放器和媒体库启动时加载整套探测 DLL。
 *
 * BtbN 共享包的 ABI 已由 CMake 固定；函数指针只在唯一探测工作线程使用。
 */
class FFmpegApi {
 public:
  using AllocContext = AVFormatContext* (*)();
  using OpenInput = int (*)(AVFormatContext**, const char*,
                            const AVInputFormat*, AVDictionary**);
  using FindStreamInfo = int (*)(AVFormatContext*, AVDictionary**);
  using CloseInput = void (*)(AVFormatContext**);
  using CodecName = const char* (*)(AVCodecID);

  FFmpegApi() {
    avformat_module_ = ::LoadLibraryW(L"avformat-62.dll");
    avcodec_module_ = ::LoadLibraryW(L"avcodec-62.dll");
    if (avformat_module_ == nullptr || avcodec_module_ == nullptr) return;
    alloc_context = Resolve<AllocContext>(avformat_module_,
                                          "avformat_alloc_context");
    open_input = Resolve<OpenInput>(avformat_module_, "avformat_open_input");
    find_stream_info = Resolve<FindStreamInfo>(avformat_module_,
                                               "avformat_find_stream_info");
    close_input = Resolve<CloseInput>(avformat_module_, "avformat_close_input");
    codec_name = Resolve<CodecName>(avcodec_module_, "avcodec_get_name");
  }

  ~FFmpegApi() {
    if (avcodec_module_ != nullptr) ::FreeLibrary(avcodec_module_);
    if (avformat_module_ != nullptr) ::FreeLibrary(avformat_module_);
  }

  bool available() const {
    return alloc_context != nullptr && open_input != nullptr &&
           find_stream_info != nullptr && close_input != nullptr &&
           codec_name != nullptr;
  }

  AllocContext alloc_context = nullptr;
  OpenInput open_input = nullptr;
  FindStreamInfo find_stream_info = nullptr;
  CloseInput close_input = nullptr;
  CodecName codec_name = nullptr;

 private:
  template <typename Function>
  static Function Resolve(HMODULE module, const char* name) {
    return reinterpret_cast<Function>(::GetProcAddress(module, name));
  }

  HMODULE avformat_module_ = nullptr;
  HMODULE avcodec_module_ = nullptr;
};

FFmpegApi& GetFFmpegApi() {
  static FFmpegApi api;
  return api;
}

const flutter::EncodableValue* FindValue(const flutter::EncodableMap& map,
                                         const char* key) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  return iterator == map.end() ? nullptr : &iterator->second;
}

std::string StringValue(const flutter::EncodableMap& map, const char* key) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) return {};
  const auto* text = std::get_if<std::string>(value);
  return text == nullptr ? std::string{} : *text;
}

int64_t IntegerValue(const flutter::EncodableMap& map, const char* key,
                     int64_t fallback = -1) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) return fallback;
  if (const auto* number = std::get_if<int64_t>(value)) return *number;
  if (const auto* number = std::get_if<int32_t>(value)) return *number;
  return fallback;
}

flutter::EncodableMap CancelledResult(const std::string& video_id) {
  return {{flutter::EncodableValue("videoId"),
           flutter::EncodableValue(video_id)},
          {flutter::EncodableValue("cancelled"),
           flutter::EncodableValue(true)}};
}

flutter::EncodableMap ErrorResult(const std::string& video_id,
                                  const std::string& error) {
  return {{flutter::EncodableValue("videoId"),
           flutter::EncodableValue(video_id)},
          {flutter::EncodableValue("cancelled"),
           flutter::EncodableValue(false)},
          {flutter::EncodableValue("error"), flutter::EncodableValue(error)}};
}
}  // namespace

NativeMediaProbeBridge::NativeMediaProbeBridge(
    flutter::BinaryMessenger* messenger)
    : channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
  worker_ = std::thread([this]() { WorkerLoop(); });
}

NativeMediaProbeBridge::~NativeMediaProbeBridge() {
  channel_->SetMethodCallHandler(nullptr);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    shutting_down_ = true;
    if (active_cancelled_ != nullptr) active_cancelled_->store(true);
  }
  condition_.notify_one();
  if (worker_.joinable()) worker_.join();
}

void NativeMediaProbeBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
  const flutter::EncodableMap empty;
  const auto& values = arguments == nullptr ? empty : *arguments;
  if (call.method_name() == "cancelGeneration") {
    CancelGeneration(IntegerValue(values, "generationId", 0));
    result->Success();
    return;
  }
  if (call.method_name() != "probeBatch") {
    result->NotImplemented();
    return;
  }

  Job job;
  job.generation_id = IntegerValue(values, "generationId", 0);
  job.result = std::move(result);
  const auto* encoded_requests = FindValue(values, "requests");
  const auto* requests = encoded_requests == nullptr
                             ? nullptr
                             : std::get_if<flutter::EncodableList>(encoded_requests);
  if (requests != nullptr) {
    for (const auto& encoded : *requests) {
      const auto* request = std::get_if<flutter::EncodableMap>(&encoded);
      if (request == nullptr) continue;
      job.requests.push_back({StringValue(*request, "videoId"),
                              StringValue(*request, "path"),
                              IntegerValue(*request, "knownSize"),
                              IntegerValue(*request, "knownModifiedAt")});
    }
  }
  {
    std::lock_guard<std::mutex> lock(mutex_);
    queued_generations_.insert(job.generation_id);
    jobs_.push(std::move(job));
  }
  condition_.notify_one();
}

void NativeMediaProbeBridge::WorkerLoop() {
  while (true) {
    Job job;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      condition_.wait(lock, [this]() { return shutting_down_ || !jobs_.empty(); });
      if (shutting_down_) return;
      job = std::move(jobs_.front());
      jobs_.pop();
      queued_generations_.erase(job.generation_id);
      active_generation_ = job.generation_id;
      active_cancelled_ = std::make_shared<std::atomic_bool>(
          cancelled_generations_.count(job.generation_id) > 0);
    }

    flutter::EncodableList results;
    for (const auto& request : job.requests) {
      if (IsGenerationCancelled(job.generation_id)) {
        results.emplace_back(CancelledResult(request.video_id));
        continue;
      }
      const InterruptState interrupt{active_cancelled_,
                                     NowMillis() + kProbeTimeoutMillis};
      results.emplace_back(ProbeOne(request, interrupt));
    }
    {
      std::lock_guard<std::mutex> lock(mutex_);
      active_generation_ = -1;
      active_cancelled_.reset();
      cancelled_generations_.erase(job.generation_id);
    }
    job.result->Success(flutter::EncodableValue(std::move(results)));
  }
}

flutter::EncodableMap NativeMediaProbeBridge::ProbeOne(
    const Request& request, const InterruptState& interrupt) {
  if (request.path.empty()) return ErrorResult(request.video_id, "empty_path");
  auto& api = GetFFmpegApi();
  if (!api.available()) {
    return ErrorResult(request.video_id, "native_probe_unavailable");
  }
  AVFormatContext* format = api.alloc_context();
  if (format == nullptr) return ErrorResult(request.video_id, "alloc_failed");
  format->interrupt_callback.callback = &NativeMediaProbeBridge::InterruptCallback;
  format->interrupt_callback.opaque = const_cast<InterruptState*>(&interrupt);
  int status = api.open_input(&format, request.path.c_str(), nullptr, nullptr);
  if (status >= 0) status = api.find_stream_info(format, nullptr);
  if (interrupt.cancelled->load()) {
    api.close_input(&format);
    return CancelledResult(request.video_id);
  }
  if (status < 0) {
    api.close_input(&format);
    return ErrorResult(request.video_id,
                       NowMillis() >= interrupt.deadline_millis
                           ? "probe_timeout"
                           : "probe_failed");
  }

  std::string video_codec;
  std::string audio_codec;
  int32_t width = 0;
  int32_t height = 0;
  for (unsigned int index = 0; index < format->nb_streams; ++index) {
    const AVCodecParameters* parameters = format->streams[index]->codecpar;
    if (parameters == nullptr) continue;
    if (parameters->codec_type == AVMEDIA_TYPE_VIDEO && video_codec.empty()) {
      video_codec = api.codec_name(parameters->codec_id);
      width = parameters->width;
      height = parameters->height;
    } else if (parameters->codec_type == AVMEDIA_TYPE_AUDIO &&
               audio_codec.empty()) {
      audio_codec = api.codec_name(parameters->codec_id);
    }
  }
  api.close_input(&format);
  flutter::EncodableMap result{
      {flutter::EncodableValue("videoId"),
       flutter::EncodableValue(request.video_id)},
      {flutter::EncodableValue("cancelled"), flutter::EncodableValue(false)}};
  if (!video_codec.empty()) {
    result.emplace(flutter::EncodableValue("videoCodec"),
                   flutter::EncodableValue(video_codec));
  }
  if (!audio_codec.empty()) {
    result.emplace(flutter::EncodableValue("audioCodec"),
                   flutter::EncodableValue(audio_codec));
  }
  if (width > 0) {
    result.emplace(flutter::EncodableValue("width"),
                   flutter::EncodableValue(width));
  }
  if (height > 0) {
    result.emplace(flutter::EncodableValue("height"),
                   flutter::EncodableValue(height));
  }
  return result;
}

bool NativeMediaProbeBridge::IsGenerationCancelled(
    int64_t generation_id) const {
  std::lock_guard<std::mutex> lock(mutex_);
  return cancelled_generations_.count(generation_id) > 0 ||
         (active_generation_ == generation_id && active_cancelled_ != nullptr &&
          active_cancelled_->load());
}

void NativeMediaProbeBridge::CancelGeneration(int64_t generation_id) {
  std::lock_guard<std::mutex> lock(mutex_);
  const bool is_active = active_generation_ == generation_id;
  if (is_active || queued_generations_.count(generation_id) > 0) {
    cancelled_generations_.insert(generation_id);
  }
  if (is_active && active_cancelled_ != nullptr) {
    active_cancelled_->store(true);
  }
}

int NativeMediaProbeBridge::InterruptCallback(void* context) {
  const auto* interrupt = static_cast<const InterruptState*>(context);
  return interrupt == nullptr || interrupt->cancelled->load() ||
                 NowMillis() >= interrupt->deadline_millis
             ? 1
             : 0;
}

int64_t NativeMediaProbeBridge::NowMillis() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}
