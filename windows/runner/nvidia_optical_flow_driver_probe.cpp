#include "nvidia_optical_flow_driver_probe.h"

#include <windows.h>

namespace {

/** NVIDIA OFAPI 的稳定成功码；官方公开头文件定义成功为零。 */
constexpr int32_t kNvOfSuccess = 0;

/**
 * 查询驱动最大 OFAPI 版本的公开函数签名。
 *
 * 签名来自 NVIDIA 官方公开 `nvOpticalFlowCommon.h`；这里不复制需要 Developer
 * Program 接受许可的 FRUC/RTX Video SDK 文件。
 */
using NvOfGetMaxSupportedApiVersion =
    int32_t(__stdcall*)(uint32_t* version);

/** 安全查询固定导出。 */
FARPROC FindExport(HMODULE module, const char* name) {
  return module == nullptr ? nullptr : GetProcAddress(module, name);
}

}  // namespace

NvidiaOpticalFlowDriverSnapshot ProbeNvidiaOpticalFlowDriver() {
  NvidiaOpticalFlowDriverSnapshot snapshot;
  // 只允许系统目录中的 NVIDIA 显示驱动模块，避免应用目录或工作目录 DLL 劫持。
  HMODULE module = LoadLibraryExW(L"nvofapi64.dll", nullptr,
                                  LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (module == nullptr) {
    snapshot.error = "system-driver-dll-missing";
    return snapshot;
  }

  const auto get_max_version =
      reinterpret_cast<NvOfGetMaxSupportedApiVersion>(
          FindExport(module, "NvOFGetMaxSupportedApiVersion"));
  snapshot.d3d11_available =
      FindExport(module, "NvOFAPICreateInstanceD3D11") != nullptr;
  snapshot.d3d12_available =
      FindExport(module, "NvOFAPICreateInstanceD3D12") != nullptr;
  snapshot.cuda_available =
      FindExport(module, "NvOFAPICreateInstanceCuda") != nullptr;
  snapshot.vulkan_available =
      FindExport(module, "NvOFAPICreateInstanceVk") != nullptr;
  if (get_max_version == nullptr) {
    snapshot.error = "max-version-export-missing";
    FreeLibrary(module);
    return snapshot;
  }

  const int32_t status =
      get_max_version(&snapshot.api_version_raw);
  if (status != kNvOfSuccess || snapshot.api_version_raw == 0) {
    snapshot.error = "max-version-query-failed";
    FreeLibrary(module);
    return snapshot;
  }

  // OFAPI 公开头文件把主版本放在高四位、次版本放在低四位。
  snapshot.api_version_major = snapshot.api_version_raw >> 4;
  snapshot.api_version_minor = snapshot.api_version_raw & 0x0F;
  snapshot.state =
      snapshot.d3d11_available ? "available" : "d3d11-unavailable";
  snapshot.error =
      snapshot.d3d11_available ? "" : "d3d11-entry-missing";
  FreeLibrary(module);
  return snapshot;
}
