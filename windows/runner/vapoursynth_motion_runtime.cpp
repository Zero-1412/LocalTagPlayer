#include "vapoursynth_motion_runtime.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cwctype>
#include <filesystem>
#include <vector>

namespace {

constexpr wchar_t kRuntimeDirectoryEnvironment[] =
    L"LOCAL_TAG_PLAYER_VAPOURSYNTH_RUNTIME_DIR";
constexpr wchar_t kScriptPathEnvironment[] =
    L"LOCAL_TAG_PLAYER_MOTION_INTERPOLATION_SCRIPT_PATH";
constexpr wchar_t kUserDataEnvironment[] =
    L"LOCAL_TAG_PLAYER_NVOFA_VS_PLUGIN_PATH";
constexpr char kFilterLabel[] = "ltp-motion-interpolation";

/** 读取完整环境变量；空值保持“未配置”，不会搜索当前工作目录。 */
std::wstring ReadEnvironmentValue(const wchar_t* name) {
  const DWORD required = GetEnvironmentVariableW(name, nullptr, 0);
  if (required <= 1) return {};
  std::vector<wchar_t> value(required);
  const DWORD written = GetEnvironmentVariableW(name, value.data(), required);
  if (written == 0 || written >= required) return {};
  return std::wstring(value.data(), written);
}

/** 只接受盘符根路径或 UNC 路径，禁止相对路径改变 DLL 搜索边界。 */
bool IsAbsoluteWindowsPath(const std::wstring& path) {
  const bool drive_rooted =
      path.size() >= 3 &&
      ((path[0] >= L'A' && path[0] <= L'Z') ||
       (path[0] >= L'a' && path[0] <= L'z')) &&
      path[1] == L':' && (path[2] == L'\\' || path[2] == L'/');
  const bool unc_rooted =
      path.size() >= 3 && path[0] == L'\\' && path[1] == L'\\';
  return drive_rooted || unc_rooted;
}

/** 将 Win32 路径转为 libmpv 结构化节点使用的 UTF-8，不执行字符串转义。 */
std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int required = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (required <= 0) return {};
  std::string output(required, '\0');
  const int written = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), output.data(), required, nullptr, nullptr);
  return written == required ? output : std::string();
}

/** 文件扩展名按 Windows 语义忽略大小写。 */
bool HasVpyExtension(const std::filesystem::path& path) {
  auto extension = path.extension().wstring();
  std::transform(extension.begin(), extension.end(), extension.begin(),
                 [](wchar_t value) { return std::towlower(value); });
  return extension == L".vpy";
}

/** 可选本机插件只接受 DLL，避免脚本用户数据被误配为目录或其它文件。 */
bool HasDllExtension(const std::filesystem::path& path) {
  auto extension = path.extension().wstring();
  std::transform(extension.begin(), extension.end(), extension.begin(),
                 [](wchar_t value) { return std::towlower(value); });
  return extension == L".dll";
}

/** 只接受能力矩阵输出的规范化 LUID，禁止回退到 GPU 名称或枚举序号。 */
bool IsNormalizedLuid(const std::string& value) {
  if (value.size() != 17 || value[8] != ':') return false;
  for (std::size_t index = 0; index < value.size(); ++index) {
    if (index == 8) continue;
    const char current = value[index];
    const bool decimal = current >= '0' && current <= '9';
    const bool lower_hex = current >= 'a' && current <= 'f';
    if (!decimal && !lower_hex) return false;
  }
  return true;
}

/** 把 Win32 错误压缩为稳定码，避免配置路径进入诊断。 */
std::string WindowsErrorCode(const char* operation) {
  return std::string(operation) + "-" + std::to_string(GetLastError());
}

/** 创建字符串节点；底层字符串由调用栈中的稳定存储持有。 */
mpv_node StringNode(char* value) {
  mpv_node node{};
  node.format = MPV_FORMAT_STRING;
  node.u.string = value;
  return node;
}

/** 判断结构化滤镜条目是否由本宿主拥有。 */
bool IsMotionFilterEntry(const mpv_node& entry) {
  if (entry.format != MPV_FORMAT_NODE_MAP || entry.u.list == nullptr) {
    return false;
  }
  const auto* map = entry.u.list;
  for (int index = 0; index < map->num; ++index) {
    if (map->keys[index] == nullptr ||
        std::string(map->keys[index]) != "label") {
      continue;
    }
    const auto& value = map->values[index];
    return value.format == MPV_FORMAT_STRING && value.u.string != nullptr &&
           std::string(value.u.string) == kFilterLabel;
  }
  return false;
}

/** 查询当前结构化滤镜图是否仍包含本宿主标签。 */
bool FilterGraphContainsMotion(mpv_handle* player) {
  mpv_node filters{};
  if (player == nullptr ||
      mpv_get_property(player, "vf", MPV_FORMAT_NODE, &filters) < 0 ||
      filters.format != MPV_FORMAT_NODE_ARRAY || filters.u.list == nullptr) {
    mpv_free_node_contents(&filters);
    return false;
  }
  bool found = false;
  for (int index = 0; index < filters.u.list->num; ++index) {
    if (IsMotionFilterEntry(filters.u.list->values[index])) {
      found = true;
      break;
    }
  }
  mpv_free_node_contents(&filters);
  return found;
}

}  // namespace

VapourSynthMotionRuntime::~VapourSynthMotionRuntime() {
  Shutdown();
}

void VapourSynthMotionRuntime::Initialize(
    const std::string& active_adapter_luid) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (vsscript_module_ != nullptr || snapshot_.configured) return;

  const std::wstring runtime_directory =
      ReadEnvironmentValue(kRuntimeDirectoryEnvironment);
  const std::wstring script_path =
      ReadEnvironmentValue(kScriptPathEnvironment);
  const std::wstring user_data_path =
      ReadEnvironmentValue(kUserDataEnvironment);
  if (runtime_directory.empty() && script_path.empty()) {
    snapshot_.state = "not-configured";
    return;
  }
  snapshot_.configured = true;
  if (runtime_directory.empty()) {
    snapshot_.state = "runtime-not-configured";
    snapshot_.error = "vapoursynth-runtime-directory-required";
    return;
  }
  if (script_path.empty()) {
    snapshot_.state = "script-not-configured";
    snapshot_.error = "motion-script-path-required";
    return;
  }
  if (!IsAbsoluteWindowsPath(runtime_directory) ||
      !IsAbsoluteWindowsPath(script_path)) {
    snapshot_.state = "invalid-path";
    snapshot_.error = "runtime-and-script-paths-must-be-absolute";
    return;
  }

  const std::filesystem::path runtime_path(runtime_directory);
  const std::filesystem::path script_file(script_path);
  std::error_code file_error;
  if (!std::filesystem::is_directory(runtime_path, file_error)) {
    snapshot_.state = "invalid-runtime";
    snapshot_.error = "runtime-directory-missing";
    return;
  }
  file_error.clear();
  if (!std::filesystem::is_regular_file(script_file, file_error) ||
      !HasVpyExtension(script_file)) {
    snapshot_.state = "invalid-script";
    snapshot_.error = "motion-script-missing-or-not-vpy";
    return;
  }
  if (!user_data_path.empty()) {
    const std::filesystem::path user_data_file(user_data_path);
    file_error.clear();
    if (!IsAbsoluteWindowsPath(user_data_path) ||
        !std::filesystem::is_regular_file(user_data_file, file_error) ||
        !HasDllExtension(user_data_file)) {
      snapshot_.state = "invalid-user-data";
      snapshot_.error = "motion-user-data-missing-or-not-dll";
      return;
    }
    const std::string user_data_path_utf8 = WideToUtf8(user_data_path);
    if (user_data_path_utf8.empty()) {
      snapshot_.state = "invalid-user-data";
      snapshot_.error = "motion-user-data-utf8-conversion-failed";
      return;
    }
    if (!IsNormalizedLuid(active_adapter_luid)) {
      snapshot_.state = "invalid-user-data";
      snapshot_.error = "motion-active-d3d11-adapter-luid-required";
      return;
    }
    // Windows 文件名不能包含 `|`，因此该分隔符不会与绝对插件路径冲突。
    user_data_utf8_ =
        user_data_path_utf8 + "|" + active_adapter_luid;
  }

  const auto vsscript_path = runtime_path / L"VSScript.dll";
  file_error.clear();
  if (!std::filesystem::is_regular_file(vsscript_path, file_error)) {
    snapshot_.state = "invalid-runtime";
    snapshot_.error = "vsscript-dll-missing";
    return;
  }
  vsscript_module_ = LoadLibraryExW(
      vsscript_path.c_str(), nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
  if (vsscript_module_ == nullptr) {
    snapshot_.state = "runtime-load-failed";
    snapshot_.error = WindowsErrorCode("load-vsscript");
    return;
  }
  if (GetProcAddress(vsscript_module_, "getVSScriptAPI") == nullptr) {
    snapshot_.state = "runtime-abi-mismatch";
    snapshot_.error = "missing-get-vsscript-api";
    FreeLibrary(vsscript_module_);
    vsscript_module_ = nullptr;
    return;
  }
  script_path_utf8_ = WideToUtf8(script_path);
  if (script_path_utf8_.empty()) {
    snapshot_.state = "invalid-script";
    snapshot_.error = "script-path-utf8-conversion-failed";
    FreeLibrary(vsscript_module_);
    vsscript_module_ = nullptr;
    return;
  }
  snapshot_.state = "ready";
  snapshot_.error.clear();
}

bool VapourSynthMotionRuntime::Apply(mpv_handle* player, bool enabled) {
  std::lock_guard<std::mutex> lock(mutex_);
  const std::string previous_state = snapshot_.state;
  const std::string previous_error = snapshot_.error;
  if (player == nullptr) {
    snapshot_.state = "apply-failed";
    snapshot_.error = "missing-mpv-session";
    return false;
  }
  if (enabled &&
      (vsscript_module_ == nullptr || script_path_utf8_.empty())) {
    snapshot_.error = "runtime-not-ready";
    return false;
  }
  if (!RewriteFilterGraph(player, enabled)) {
    snapshot_.state = "apply-failed";
    snapshot_.error = "structured-vf-write-failed";
    if (enabled) ++snapshot_.fallback_count;
    snapshot_.enabled = false;
    return false;
  }
  snapshot_.enabled = enabled;
  if (enabled) {
    snapshot_.state = "requested";
    snapshot_.error.clear();
  } else if (vsscript_module_ != nullptr && !script_path_utf8_.empty()) {
    snapshot_.state = "ready";
    snapshot_.error.clear();
  } else {
    // “关闭”仍应移除残留条目，但不能把未配置/无效运行时伪装成 ready。
    snapshot_.state = previous_state;
    snapshot_.error = previous_error;
  }
  return true;
}

bool VapourSynthMotionRuntime::ReapplyAfterFilterGraphChange(
    mpv_handle* player) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!snapshot_.enabled) return true;
  if (!RewriteFilterGraph(player, true)) {
    snapshot_.state = "fallback";
    snapshot_.error = "reapply-after-vf-change-failed";
    snapshot_.enabled = false;
    ++snapshot_.fallback_count;
    return false;
  }
  snapshot_.state = "requested";
  return true;
}

void VapourSynthMotionRuntime::ObserveLog(mpv_handle* player,
                                          const char* prefix,
                                          const char* text) {
  if (prefix == nullptr || text == nullptr) return;
  const std::string component(prefix);
  const std::string message(text);
  std::string normalized_message(message);
  std::transform(normalized_message.begin(), normalized_message.end(),
                 normalized_message.begin(),
                 [](unsigned char value) {
                   return static_cast<char>(std::tolower(value));
                 });
  const bool runtime_failed =
      component == "vapoursynth" &&
      message.find("Failed to load VapourSynth VSScript library") !=
          std::string::npos;
  const bool script_failed =
      component == "vapoursynth" &&
      (normalized_message.find("script evaluation failed") !=
           std::string::npos ||
       normalized_message.find("vapoursynth error") !=
           std::string::npos);
  const bool filter_failed =
      component == "user_filter_wrapper" &&
      message.find("Creating filter 'vapoursynth' failed") !=
          std::string::npos;
  if (!runtime_failed && !script_failed && !filter_failed) return;

  std::lock_guard<std::mutex> lock(mutex_);
  if (!snapshot_.enabled) return;
  FailAndRollback(player, runtime_failed
                              ? "vsscript-runtime-unavailable"
                              : script_failed ? "motion-script-failed"
                                              : "vapoursynth-filter-failed");
}

void VapourSynthMotionRuntime::ConfirmFrameRateIncrease(
    mpv_handle* player, double source_fps, double filtered_fps) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!snapshot_.enabled) return;
  if (!FilterGraphContainsMotion(player)) {
    snapshot_.enabled = false;
    snapshot_.state = "fallback";
    snapshot_.error = "motion-filter-missing";
    ++snapshot_.fallback_count;
    return;
  }
  if (source_fps > 1.0 && filtered_fps >= source_fps * 1.5) {
    snapshot_.state = "active";
    snapshot_.error.clear();
  } else if (snapshot_.state == "active") {
    // 输出帧率回落时撤销 active，避免把历史采样冒充当前插帧状态。
    snapshot_.state = "requested";
  }
}

void VapourSynthMotionRuntime::Shutdown() {
  std::lock_guard<std::mutex> lock(mutex_);
  script_path_utf8_.clear();
  user_data_utf8_.clear();
  snapshot_.enabled = false;
  if (vsscript_module_ != nullptr) {
    FreeLibrary(vsscript_module_);
    vsscript_module_ = nullptr;
  }
  // 桥对象可能在同一进程重建 mpv 会话；清除静态门禁才能重新读取本机配置。
  snapshot_.configured = false;
  snapshot_.state = "shutdown";
  snapshot_.error.clear();
  snapshot_.fallback_count = 0;
}

VapourSynthMotionRuntime::Snapshot VapourSynthMotionRuntime::GetSnapshot()
    const {
  std::lock_guard<std::mutex> lock(mutex_);
  return snapshot_;
}

bool VapourSynthMotionRuntime::RewriteFilterGraph(
    mpv_handle* player, bool append_motion_filter) {
  mpv_node current{};
  if (mpv_get_property(player, "vf", MPV_FORMAT_NODE, &current) < 0 ||
      current.format != MPV_FORMAT_NODE_ARRAY || current.u.list == nullptr) {
    mpv_free_node_contents(&current);
    return false;
  }

  std::vector<mpv_node> entries;
  entries.reserve(static_cast<size_t>(current.u.list->num) + 1);
  for (int index = 0; index < current.u.list->num; ++index) {
    const auto& entry = current.u.list->values[index];
    if (!IsMotionFilterEntry(entry)) entries.push_back(entry);
  }

  std::array<char*, 4> parameter_keys{
      const_cast<char*>("file"),
      const_cast<char*>("buffered-frames"),
      const_cast<char*>("concurrent-frames"),
      const_cast<char*>("user-data"),
  };
  std::array<mpv_node, 4> parameter_values{
      StringNode(script_path_utf8_.data()),
      StringNode(const_cast<char*>("4")),
      StringNode(const_cast<char*>("4")),
      StringNode(user_data_utf8_.data()),
  };
  mpv_node_list parameter_map{
      static_cast<int>(parameter_values.size()),
      parameter_values.data(),
      parameter_keys.data(),
  };
  mpv_node parameter_node{};
  parameter_node.format = MPV_FORMAT_NODE_MAP;
  parameter_node.u.list = &parameter_map;

  std::array<char*, 4> filter_keys{
      const_cast<char*>("name"),
      const_cast<char*>("label"),
      const_cast<char*>("enabled"),
      const_cast<char*>("params"),
  };
  std::array<mpv_node, 4> filter_values{
      StringNode(const_cast<char*>("vapoursynth")),
      StringNode(const_cast<char*>(kFilterLabel)),
      mpv_node{},
      parameter_node,
  };
  filter_values[2].format = MPV_FORMAT_FLAG;
  filter_values[2].u.flag = 1;
  mpv_node_list filter_map{
      static_cast<int>(filter_values.size()),
      filter_values.data(),
      filter_keys.data(),
  };
  mpv_node filter_entry{};
  filter_entry.format = MPV_FORMAT_NODE_MAP;
  filter_entry.u.list = &filter_map;
  if (append_motion_filter) entries.push_back(filter_entry);

  mpv_node_list output_list{
      static_cast<int>(entries.size()),
      entries.empty() ? nullptr : entries.data(),
      nullptr,
  };
  mpv_node output{};
  output.format = MPV_FORMAT_NODE_ARRAY;
  output.u.list = &output_list;
  const int result =
      mpv_set_property(player, "vf", MPV_FORMAT_NODE, &output);
  mpv_free_node_contents(&current);
  return result >= 0;
}

void VapourSynthMotionRuntime::FailAndRollback(
    mpv_handle* player, const std::string& error) {
  RewriteFilterGraph(player, false);
  snapshot_.enabled = false;
  snapshot_.state = "fallback";
  snapshot_.error = error;
  ++snapshot_.fallback_count;
}
