#include "local_video_enhancement_plugin.h"

#include <algorithm>
#include <vector>

namespace {

/** 读取完整环境变量；未配置和空字符串都表示不启用本机插件。 */
std::wstring ReadEnvironmentPath(const wchar_t* name) {
  const DWORD required = GetEnvironmentVariableW(name, nullptr, 0);
  if (required <= 1) return {};
  std::vector<wchar_t> value(required);
  const DWORD written =
      GetEnvironmentVariableW(name, value.data(), required);
  if (written == 0 || written >= required) return {};
  return std::wstring(value.data(), written);
}

/** 只接受盘符根路径或 UNC 路径，禁止工作目录影响 DLL 解析。 */
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

/** 把 Win32 错误压缩为稳定诊断码，避免本地路径进入可复制诊断。 */
std::string WindowsErrorCode(const char* operation) {
  return std::string(operation) + "-" + std::to_string(GetLastError());
}

}  // namespace

LocalVideoEnhancementPlugin::~LocalVideoEnhancementPlugin() {
  Shutdown();
}

void LocalVideoEnhancementPlugin::Initialize(
    ID3D11Device* device, ID3D11DeviceContext* immediate_context) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (initialized_ || module_ != nullptr || disabled_) return;

  const std::wstring path =
      ReadEnvironmentPath(L"LOCAL_TAG_PLAYER_VIDEO_PLUGIN_PATH");
  if (path.empty()) {
    snapshot_.state = "not-configured";
    return;
  }
  if (!IsAbsoluteWindowsPath(path)) {
    snapshot_.state = "invalid-path";
    snapshot_.error = "plugin-path-must-be-absolute";
    disabled_ = true;
    return;
  }
  if (device == nullptr || immediate_context == nullptr) {
    snapshot_.state = "initialize-failed";
    snapshot_.error = "missing-d3d11-context";
    disabled_ = true;
    return;
  }

  module_ = LoadLibraryExW(
      path.c_str(), nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
  if (module_ == nullptr) {
    snapshot_.state = "load-failed";
    snapshot_.error = WindowsErrorCode("load-library");
    disabled_ = true;
    return;
  }
  const auto getter = reinterpret_cast<LtpGetLocalVideoPluginApiV1>(
      GetProcAddress(module_, kLtpLocalVideoPluginExportName));
  if (getter == nullptr) {
    snapshot_.state = "abi-mismatch";
    snapshot_.error = "missing-v1-export";
    disabled_ = true;
    FreeLibrary(module_);
    module_ = nullptr;
    return;
  }
  api_ = getter();
  if (api_ == nullptr ||
      api_->struct_size < sizeof(LtpLocalVideoPluginApiV1) ||
      api_->abi_version != kLtpLocalVideoPluginAbiVersion ||
      api_->initialize == nullptr || api_->process == nullptr ||
      api_->shutdown == nullptr) {
    snapshot_.state = "abi-mismatch";
    snapshot_.error = "unsupported-v1-table";
    api_ = nullptr;
    disabled_ = true;
    FreeLibrary(module_);
    module_ = nullptr;
    return;
  }
  snapshot_.name =
      api_->plugin_name == nullptr ? "unnamed-local-plugin" : api_->plugin_name;
  const LtpLocalVideoPluginInitContext context{
      sizeof(LtpLocalVideoPluginInitContext),
      kLtpLocalVideoPluginAbiVersion,
      device,
      immediate_context,
  };
  const int32_t result = api_->initialize(&context);
  if (result != 0) {
    // 初始化失败也可能留下插件私有资源；ABI 要求先对称关闭再卸载 DLL。
    api_->shutdown();
    snapshot_.state = "initialize-failed";
    snapshot_.error = "plugin-initialize-" + std::to_string(result);
    api_ = nullptr;
    disabled_ = true;
    FreeLibrary(module_);
    module_ = nullptr;
    return;
  }
  initialized_ = true;
  snapshot_.state = "ready";
  snapshot_.error.clear();
}

bool LocalVideoEnhancementPlugin::EnsureBackupTexture(
    ID3D11Device* device, const D3D11_TEXTURE2D_DESC& source_desc) {
  if (backup_texture_ != nullptr &&
      backup_desc_.Width == source_desc.Width &&
      backup_desc_.Height == source_desc.Height &&
      backup_desc_.Format == source_desc.Format &&
      backup_desc_.MipLevels == source_desc.MipLevels &&
      backup_desc_.ArraySize == source_desc.ArraySize &&
      backup_desc_.SampleDesc.Count == source_desc.SampleDesc.Count &&
      backup_desc_.SampleDesc.Quality == source_desc.SampleDesc.Quality) {
    return true;
  }
  backup_texture_.Reset();
  backup_desc_ = source_desc;
  backup_desc_.BindFlags = 0;
  backup_desc_.CPUAccessFlags = 0;
  backup_desc_.MiscFlags = 0;
  backup_desc_.Usage = D3D11_USAGE_DEFAULT;
  return SUCCEEDED(
      device->CreateTexture2D(&backup_desc_, nullptr, &backup_texture_));
}

void LocalVideoEnhancementPlugin::ProcessFrame(
    ID3D11Device* device, ID3D11DeviceContext* immediate_context,
    ID3D11Texture2D* texture, uint64_t frame_index) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!initialized_ || disabled_ || api_ == nullptr) return;
  if (device == nullptr || immediate_context == nullptr || texture == nullptr) {
    DisableWithFailure("process-failed", "missing-frame-context", true);
    return;
  }

  D3D11_TEXTURE2D_DESC texture_desc{};
  texture->GetDesc(&texture_desc);
  if (!EnsureBackupTexture(device, texture_desc)) {
    DisableWithFailure("process-failed", "backup-texture-create-failed", true);
    return;
  }

  // 备份先于任何第三方代码执行；正常返回失败时可确定性恢复同一帧。
  immediate_context->CopyResource(backup_texture_.Get(), texture);
  const LtpLocalVideoPluginFrameContext context{
      sizeof(LtpLocalVideoPluginFrameContext),
      kLtpLocalVideoPluginAbiVersion,
      device,
      immediate_context,
      texture,
      texture_desc.Width,
      texture_desc.Height,
      texture_desc.Format,
      frame_index,
  };
  const int32_t result = api_->process(&context);
  if (result != 0) {
    immediate_context->CopyResource(texture, backup_texture_.Get());
    immediate_context->Flush();
    DisableWithFailure("process-failed",
                       "plugin-process-" + std::to_string(result), true);
    return;
  }
  immediate_context->Flush();
  ++snapshot_.processed_frames;
  snapshot_.state = "active";
}

void LocalVideoEnhancementPlugin::DisableWithFailure(
    const std::string& state, const std::string& error, bool count_fallback) {
  snapshot_.state = state;
  snapshot_.error = error;
  if (count_fallback) ++snapshot_.fallback_frames;
  disabled_ = true;
}

void LocalVideoEnhancementPlugin::Shutdown() {
  std::lock_guard<std::mutex> lock(mutex_);
  backup_texture_.Reset();
  if (initialized_ && api_ != nullptr) {
    api_->shutdown();
  }
  initialized_ = false;
  api_ = nullptr;
  if (module_ != nullptr) {
    FreeLibrary(module_);
    module_ = nullptr;
  }
  if (snapshot_.state == "ready" || snapshot_.state == "active") {
    snapshot_.state = "shutdown";
  }
}

LocalVideoEnhancementPlugin::Snapshot
LocalVideoEnhancementPlugin::GetSnapshot() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return snapshot_;
}
