#include "../runner/vapoursynth_motion_runtime.h"

#include <mpv/client.h>
#include <windows.h>

#include <iostream>
#include <string>

namespace {

constexpr char kMotionLabel[] = "ltp-motion-interpolation";

/** 从结构化滤镜条目读取指定字符串字段。 */
std::string ReadStringField(const mpv_node& entry, const char* key) {
  if (entry.format != MPV_FORMAT_NODE_MAP || entry.u.list == nullptr) {
    return {};
  }
  for (int index = 0; index < entry.u.list->num; ++index) {
    if (entry.u.list->keys[index] == nullptr ||
        std::string(entry.u.list->keys[index]) != key) {
      continue;
    }
    const auto& value = entry.u.list->values[index];
    return value.format == MPV_FORMAT_STRING && value.u.string != nullptr
               ? value.u.string
               : std::string();
  }
  return {};
}

/** 查找本宿主标签并验证 file 参数保持完整的 Windows 绝对路径。 */
bool ContainsMotionFilter(mpv_handle* player,
                          const std::string& expected_script_path) {
  mpv_node filters{};
  if (mpv_get_property(player, "vf", MPV_FORMAT_NODE, &filters) < 0 ||
      filters.format != MPV_FORMAT_NODE_ARRAY || filters.u.list == nullptr) {
    mpv_free_node_contents(&filters);
    return false;
  }
  bool matched = false;
  for (int index = 0; index < filters.u.list->num; ++index) {
    const auto& entry = filters.u.list->values[index];
    if (ReadStringField(entry, "label") != kMotionLabel ||
        ReadStringField(entry, "name") != "vapoursynth") {
      continue;
    }
    if (entry.format != MPV_FORMAT_NODE_MAP || entry.u.list == nullptr) {
      continue;
    }
    for (int field = 0; field < entry.u.list->num; ++field) {
      if (entry.u.list->keys[field] == nullptr ||
          std::string(entry.u.list->keys[field]) != "params") {
        continue;
      }
      const auto& params = entry.u.list->values[field];
      matched = ReadStringField(params, "file") == expected_script_path;
    }
  }
  mpv_free_node_contents(&filters);
  return matched;
}

/** 判断指定标签是否已经从滤镜图中移除。 */
bool MotionFilterRemoved(mpv_handle* player) {
  mpv_node filters{};
  if (mpv_get_property(player, "vf", MPV_FORMAT_NODE, &filters) < 0 ||
      filters.format != MPV_FORMAT_NODE_ARRAY || filters.u.list == nullptr) {
    mpv_free_node_contents(&filters);
    return false;
  }
  bool removed = true;
  for (int index = 0; index < filters.u.list->num; ++index) {
    if (ReadStringField(filters.u.list->values[index], "label") ==
        kMotionLabel) {
      removed = false;
    }
  }
  mpv_free_node_contents(&filters);
  return removed;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc != 3) {
    std::cerr << "usage: host_test <runtime-dir> <script-path>\n";
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
    std::cerr << "runtime probe did not become ready: " << ready.state << " "
              << ready.error << "\n";
    return 3;
  }

  mpv_handle* player = mpv_create();
  if (player == nullptr) return 4;
  mpv_set_option_string(player, "config", "no");
  mpv_set_option_string(player, "terminal", "no");
  mpv_set_option_string(player, "vo", "null");
  mpv_set_option_string(player, "ao", "null");
  if (mpv_initialize(player) < 0) {
    mpv_terminate_destroy(player);
    return 5;
  }

  const int utf8_size =
      WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, argv[2], -1, nullptr,
                          0, nullptr, nullptr);
  std::string expected_script(utf8_size > 0 ? utf8_size : 0, '\0');
  if (utf8_size <= 1 ||
      WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, argv[2], -1,
                          expected_script.data(), utf8_size, nullptr,
                          nullptr) == 0) {
    mpv_terminate_destroy(player);
    return 6;
  }
  expected_script.pop_back();

  if (!runtime.Apply(player, true) ||
      !ContainsMotionFilter(player, expected_script)) {
    std::cerr << "structured append failed\n";
    mpv_terminate_destroy(player);
    return 7;
  }
  runtime.ConfirmFrameRateIncrease(player, 24.0, 60.0);
  if (runtime.GetSnapshot().state != "active") {
    std::cerr << "active frame-rate confirmation failed\n";
    mpv_terminate_destroy(player);
    return 8;
  }
  if (mpv_set_property_string(player, "vf", "format=fmt=yuv420p") < 0) {
    mpv_terminate_destroy(player);
    return 9;
  }
  runtime.ConfirmFrameRateIncrease(player, 24.0, 60.0);
  const auto missing_filter = runtime.GetSnapshot();
  if (missing_filter.state != "fallback" || missing_filter.enabled) {
    std::cerr << "missing filter did not revoke active state\n";
    mpv_terminate_destroy(player);
    return 10;
  }
  if (!runtime.Apply(player, true) ||
      !ContainsMotionFilter(player, expected_script)) {
    std::cerr << "re-enable after fallback failed\n";
    mpv_terminate_destroy(player);
    return 11;
  }
  if (mpv_set_property_string(player, "vf", "format=fmt=yuv420p") < 0 ||
      !runtime.ReapplyAfterFilterGraphChange(player) ||
      !ContainsMotionFilter(player, expected_script)) {
    std::cerr << "filter graph reapply failed\n";
    mpv_terminate_destroy(player);
    return 12;
  }
  if (!runtime.Apply(player, false) || !MotionFilterRemoved(player)) {
    std::cerr << "structured remove failed\n";
    mpv_terminate_destroy(player);
    return 13;
  }

  mpv_terminate_destroy(player);
  runtime.Shutdown();
  const auto shutdown = runtime.GetSnapshot();
  if (shutdown.configured || shutdown.state != "shutdown") {
    std::cerr << "shutdown did not clear session configuration\n";
    return 14;
  }
  runtime.Initialize();
  if (runtime.GetSnapshot().state != "ready") {
    std::cerr << "runtime did not reload after shutdown\n";
    return 15;
  }
  runtime.Shutdown();
  std::cout
      << "structured-vf=passed preserve-existing=passed remove=passed "
         "active-revocation=passed reload=passed\n";
  return 0;
}
