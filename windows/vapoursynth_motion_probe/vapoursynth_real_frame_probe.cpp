#include "../runner/vapoursynth_motion_runtime.h"

#include <mpv/client.h>
#include <windows.h>

#include <chrono>
#include <cstdint>
#include <iostream>
#include <string>

namespace {

/**
 * 真实送帧阶段累计的稳定状态。
 *
 * 不保存 mpv 日志原文或输入路径，避免 QA 输出泄露本机媒体信息。
 */
struct PlaybackProbeState {
  int file_loaded_count = 0;
  int seek_count = 0;
  int playback_restart_count = 0;
  bool end_file_error = false;
  double position = -1.0;
  double source_fps = 0.0;
  double filtered_fps = 0.0;
  int64_t frame_number = -1;
  std::string video_format;
};

/** 读取浮点属性；属性尚不可用时返回调用方指定的回退值。 */
double ReadDouble(mpv_handle* player, const char* name, double fallback) {
  double value = fallback;
  return mpv_get_property(player, name, MPV_FORMAT_DOUBLE, &value) >= 0
             ? value
             : fallback;
}

/** 读取整数属性；属性尚不可用时返回调用方指定的回退值。 */
int64_t ReadInt64(mpv_handle* player, const char* name, int64_t fallback) {
  int64_t value = fallback;
  return mpv_get_property(player, name, MPV_FORMAT_INT64, &value) >= 0
             ? value
             : fallback;
}

/** 读取不含路径的固定视频格式属性。 */
std::string ReadString(mpv_handle* player, const char* name) {
  char* value = mpv_get_property_string(player, name);
  if (value == nullptr) return {};
  const std::string result(value);
  mpv_free(value);
  return result;
}

/**
 * 消费一次 mpv 事件并更新稳定状态。
 *
 * VapourSynth 日志只交给运行时做固定错误匹配，不直接写入控制台。
 */
void ConsumeEvent(mpv_handle* player, VapourSynthMotionRuntime* runtime,
                  const mpv_event* event, PlaybackProbeState* state) {
  if (event == nullptr || state == nullptr || runtime == nullptr) return;
  switch (event->event_id) {
    case MPV_EVENT_FILE_LOADED:
      ++state->file_loaded_count;
      break;
    case MPV_EVENT_SEEK:
      ++state->seek_count;
      break;
    case MPV_EVENT_PLAYBACK_RESTART:
      ++state->playback_restart_count;
      break;
    case MPV_EVENT_END_FILE: {
      const auto* end_file =
          static_cast<const mpv_event_end_file*>(event->data);
      state->end_file_error =
          end_file != nullptr &&
          end_file->reason == MPV_END_FILE_REASON_ERROR;
      break;
    }
    case MPV_EVENT_LOG_MESSAGE: {
      const auto* message =
          static_cast<const mpv_event_log_message*>(event->data);
      if (message != nullptr) {
        runtime->ObserveLog(player, message->prefix, message->text);
      }
      break;
    }
    default:
      break;
  }
}

/**
 * 在限定时间内等待真实视频状态满足条件。
 *
 * 每轮同时读取源帧率、滤镜输出帧率、播放头和估算帧号；任何运行时回退或
 * 文件错误都会立即失败，不把超时或仅写入滤镜配置冒充真实送帧成功。
 */
template <typename Predicate>
bool WaitForState(mpv_handle* player, VapourSynthMotionRuntime* runtime,
                  PlaybackProbeState* state,
                  std::chrono::milliseconds timeout, Predicate predicate) {
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  while (std::chrono::steady_clock::now() < deadline) {
    const mpv_event* event = mpv_wait_event(player, 0.05);
    if (event != nullptr && event->event_id != MPV_EVENT_NONE) {
      ConsumeEvent(player, runtime, event, state);
    }
    state->position = ReadDouble(player, "time-pos", state->position);
    state->source_fps =
        ReadDouble(player, "container-fps", state->source_fps);
    state->filtered_fps =
        ReadDouble(player, "estimated-vf-fps", state->filtered_fps);
    state->frame_number =
        ReadInt64(player, "estimated-frame-number", state->frame_number);
    state->video_format = ReadString(player, "video-format");
    runtime->ConfirmFrameRateIncrease(player, state->source_fps,
                                      state->filtered_fps);
    const auto snapshot = runtime->GetSnapshot();
    if (snapshot.state == "fallback" || state->end_file_error) return false;
    if (predicate(*state, snapshot)) return true;
  }
  return false;
}

/** 执行一个同步 mpv 命令并把失败转换为探针布尔结果。 */
bool RunCommand(mpv_handle* player, const char** arguments) {
  return mpv_command(player, arguments) >= 0;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc != 4) {
    std::cerr
        << "usage: real_frame_probe <runtime-dir> <script-path> <sample>\n";
    return 2;
  }
  SetEnvironmentVariableW(L"LOCAL_TAG_PLAYER_VAPOURSYNTH_RUNTIME_DIR",
                          argv[1]);
  SetEnvironmentVariableW(
      L"LOCAL_TAG_PLAYER_MOTION_INTERPOLATION_SCRIPT_PATH", argv[2]);

  VapourSynthMotionRuntime runtime;
  runtime.Initialize();
  const auto ready = runtime.GetSnapshot();
  if (ready.state != "ready" || !ready.configured) {
    std::cerr << "runtime-not-ready state=" << ready.state
              << " error=" << ready.error << "\n";
    return 3;
  }

  mpv_handle* player = mpv_create();
  if (player == nullptr) return 4;
  mpv_set_option_string(player, "config", "no");
  mpv_set_option_string(player, "terminal", "no");
  mpv_set_option_string(player, "vo", "null");
  mpv_set_option_string(player, "ao", "null");
  mpv_set_option_string(player, "hwdec", "no");
  mpv_set_option_string(player, "keep-open", "yes");
  mpv_set_option_string(player, "speed", "2");
  if (mpv_initialize(player) < 0) {
    mpv_terminate_destroy(player);
    return 5;
  }
  mpv_request_log_messages(player, "v");
  if (!runtime.Apply(player, true)) {
    mpv_terminate_destroy(player);
    return 6;
  }

  const int sample_utf8_size =
      WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, argv[3], -1, nullptr,
                          0, nullptr, nullptr);
  std::string sample_utf8(sample_utf8_size > 0 ? sample_utf8_size : 0, '\0');
  if (sample_utf8_size <= 1 ||
      WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, argv[3], -1,
                          sample_utf8.data(), sample_utf8_size, nullptr,
                          nullptr) == 0) {
    mpv_terminate_destroy(player);
    return 7;
  }
  sample_utf8.pop_back();

  PlaybackProbeState state;
  const char* load_arguments[] = {"loadfile", sample_utf8.c_str(), "replace",
                                  nullptr};
  if (!RunCommand(player, load_arguments) ||
      !WaitForState(
          player, &runtime, &state, std::chrono::seconds(8),
          [](const PlaybackProbeState& current,
             const VapourSynthMotionRuntime::Snapshot& snapshot) {
            return current.file_loaded_count >= 1 &&
                   current.position >= 0.6 && current.source_fps > 1.0 &&
                   current.filtered_fps > 1.0 &&
                   current.frame_number >= 5 &&
                   !current.video_format.empty() && snapshot.enabled &&
                   snapshot.state == "requested";
          })) {
    const auto failed = runtime.GetSnapshot();
    std::cerr << "real-frame-timeout state=" << failed.state
              << " error=" << failed.error << "\n";
    mpv_terminate_destroy(player);
    return 8;
  }

  const char* seek_arguments[] = {"seek", "3", "absolute+exact", nullptr};
  if (!RunCommand(player, seek_arguments) ||
      !WaitForState(
          player, &runtime, &state, std::chrono::seconds(6),
          [](const PlaybackProbeState& current,
             const VapourSynthMotionRuntime::Snapshot& snapshot) {
            return current.seek_count >= 1 && current.position >= 3.1 &&
                   current.playback_restart_count >= 1 && snapshot.enabled &&
                   snapshot.state == "requested";
          })) {
    const auto failed = runtime.GetSnapshot();
    std::cerr << "seek-timeout state=" << failed.state
              << " error=" << failed.error << "\n";
    mpv_terminate_destroy(player);
    return 9;
  }

  state.end_file_error = false;
  if (!RunCommand(player, load_arguments) ||
      !WaitForState(
          player, &runtime, &state, std::chrono::seconds(8),
          [](const PlaybackProbeState& current,
             const VapourSynthMotionRuntime::Snapshot& snapshot) {
            return current.file_loaded_count >= 2 &&
                   current.position >= 0.5 && current.position < 2.5 &&
                   current.filtered_fps > 1.0 && snapshot.enabled &&
                   snapshot.state == "requested";
          })) {
    const auto failed = runtime.GetSnapshot();
    std::cerr << "reload-timeout state=" << failed.state
              << " error=" << failed.error << "\n";
    mpv_terminate_destroy(player);
    return 10;
  }

  if (!runtime.Apply(player, false)) {
    mpv_terminate_destroy(player);
    return 11;
  }
  mpv_terminate_destroy(player);
  runtime.Shutdown();
  std::cout << "real-frames=passed seek=passed reload=passed "
               "passthrough-not-active=passed\n";
  return 0;
}
