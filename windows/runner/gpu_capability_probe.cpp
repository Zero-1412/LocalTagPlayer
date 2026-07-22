#include "gpu_capability_probe.h"

#include <d3d11.h>
#include <dxgi1_6.h>
#include <windows.h>
#include <wrl/client.h>

#include <array>
#include <cstdint>
#include <cstdio>
#include <string>
#include <utility>
#include <vector>

namespace {
using Microsoft::WRL::ComPtr;

constexpr char kDetectionSource[] = "dxgi-d3d11-vulkan-loader";

// Vulkan 仅用于无扩展的只读物理设备枚举。为避免给安装包增加 Vulkan SDK 依赖，
// 这里按 Vulkan 1.0 ABI 声明所需的最小类型，并在运行时加载系统 loader。
using VkFlags = uint32_t;
using VkResult = int32_t;
struct VkInstance_T;
struct VkPhysicalDevice_T;
using VkInstance = VkInstance_T*;
using VkPhysicalDevice = VkPhysicalDevice_T*;

struct VkApplicationInfo {
  uint32_t s_type;
  const void* next;
  const char* application_name;
  uint32_t application_version;
  const char* engine_name;
  uint32_t engine_version;
  uint32_t api_version;
};

struct VkInstanceCreateInfo {
  uint32_t s_type;
  const void* next;
  VkFlags flags;
  const VkApplicationInfo* application_info;
  uint32_t enabled_layer_count;
  const char* const* enabled_layer_names;
  uint32_t enabled_extension_count;
  const char* const* enabled_extension_names;
};

/** Vulkan 规范前缀加安全尾部，允许 loader 写入完整 VkPhysicalDeviceProperties。 */
struct VkPhysicalDevicePropertiesStorage {
  uint32_t api_version;
  uint32_t driver_version;
  uint32_t vendor_id;
  uint32_t device_id;
  uint32_t device_type;
  char device_name[256];
  uint8_t pipeline_cache_uuid[16];
  std::array<uint8_t, 4096> remaining{};
};

using PfnVkCreateInstance = VkResult(WINAPI*)(
    const VkInstanceCreateInfo*, const void*, VkInstance*);
using PfnVkDestroyInstance = void(WINAPI*)(VkInstance, const void*);
using PfnVkEnumeratePhysicalDevices =
    VkResult(WINAPI*)(VkInstance, uint32_t*, VkPhysicalDevice*);
using PfnVkGetPhysicalDeviceProperties =
    void(WINAPI*)(VkPhysicalDevice, VkPhysicalDevicePropertiesStorage*);

struct VulkanDevice {
  uint32_t vendor_id = 0;
  uint32_t device_id = 0;
  uint32_t api_version = 0;
  std::string name;
};

struct VulkanSnapshot {
  bool loader_available = false;
  bool instance_available = false;
  std::vector<VulkanDevice> devices;
};

std::string Utf8FromWide(const wchar_t* value) {
  if (value == nullptr || value[0] == L'\0') return {};
  const int length = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0,
                                         nullptr, nullptr);
  if (length <= 1) return {};
  std::string result(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value, -1, result.data(), length, nullptr,
                      nullptr);
  result.resize(static_cast<size_t>(length - 1));
  return result;
}

std::string LuidString(const LUID& luid) {
  std::array<char, 32> buffer{};
  std::snprintf(buffer.data(), buffer.size(), "%08x:%08x",
                static_cast<uint32_t>(luid.HighPart), luid.LowPart);
  return buffer.data();
}

std::string FeatureLevelString(D3D_FEATURE_LEVEL level) {
  switch (level) {
    case D3D_FEATURE_LEVEL_12_1:
      return "12_1";
    case D3D_FEATURE_LEVEL_12_0:
      return "12_0";
    case D3D_FEATURE_LEVEL_11_1:
      return "11_1";
    case D3D_FEATURE_LEVEL_11_0:
      return "11_0";
    case D3D_FEATURE_LEVEL_10_1:
      return "10_1";
    case D3D_FEATURE_LEVEL_10_0:
      return "10_0";
    default:
      return "unavailable";
  }
}

std::string VulkanVersionString(uint32_t version) {
  return std::to_string(version >> 22) + "." +
         std::to_string((version >> 12) & 0x3ffu) + "." +
         std::to_string(version & 0xfffu);
}

std::string ColorSpaceString(DXGI_COLOR_SPACE_TYPE color_space) {
  switch (color_space) {
    case DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709:
      return "rgb-full-g22-p709";
    case DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709:
      return "rgb-full-linear-p709";
    case DXGI_COLOR_SPACE_RGB_STUDIO_G22_NONE_P709:
      return "rgb-limited-g22-p709";
    case DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020:
      return "rgb-full-pq-p2020";
    case DXGI_COLOR_SPACE_RGB_STUDIO_G2084_NONE_P2020:
      return "rgb-limited-pq-p2020";
    case DXGI_COLOR_SPACE_YCBCR_STUDIO_G2084_LEFT_P2020:
      return "ycbcr-limited-pq-p2020";
    default:
      return "dxgi-" + std::to_string(static_cast<int>(color_space));
  }
}

VulkanSnapshot QueryVulkanDevices() {
  VulkanSnapshot snapshot;
  HMODULE library = LoadLibraryW(L"vulkan-1.dll");
  if (library == nullptr) return snapshot;
  snapshot.loader_available = true;

  const auto create_instance = reinterpret_cast<PfnVkCreateInstance>(
      GetProcAddress(library, "vkCreateInstance"));
  const auto destroy_instance = reinterpret_cast<PfnVkDestroyInstance>(
      GetProcAddress(library, "vkDestroyInstance"));
  const auto enumerate_devices =
      reinterpret_cast<PfnVkEnumeratePhysicalDevices>(
          GetProcAddress(library, "vkEnumeratePhysicalDevices"));
  const auto get_properties =
      reinterpret_cast<PfnVkGetPhysicalDeviceProperties>(
          GetProcAddress(library, "vkGetPhysicalDeviceProperties"));
  if (create_instance == nullptr || destroy_instance == nullptr ||
      enumerate_devices == nullptr || get_properties == nullptr) {
    FreeLibrary(library);
    return snapshot;
  }

  const VkApplicationInfo application{0, nullptr, "Local Tag Player", 1,
                                      "Local Tag Player", 1, 1u << 22};
  const VkInstanceCreateInfo create_info{1,       nullptr, 0, &application,
                                         0,       nullptr, 0, nullptr};
  VkInstance instance = nullptr;
  if (create_instance(&create_info, nullptr, &instance) != 0 ||
      instance == nullptr) {
    FreeLibrary(library);
    return snapshot;
  }

  uint32_t count = 0;
  const VkResult count_result = enumerate_devices(instance, &count, nullptr);
  if (count_result == 0) {
    if (count == 0) {
      snapshot.instance_available = true;
    } else {
      std::vector<VkPhysicalDevice> devices(count);
      if (enumerate_devices(instance, &count, devices.data()) == 0) {
        snapshot.instance_available = true;
        devices.resize(count);
        for (const auto device : devices) {
          VkPhysicalDevicePropertiesStorage properties{};
          get_properties(device, &properties);
          snapshot.devices.push_back(
              {properties.vendor_id, properties.device_id,
               properties.api_version, properties.device_name});
        }
      }
    }
  }
  destroy_instance(instance, nullptr);
  FreeLibrary(library);
  return snapshot;
}

struct D3dSnapshot {
  std::string feature_level = "unavailable";
  bool compute_shader_supported = false;
};

D3dSnapshot QueryD3dCapabilities(IDXGIAdapter1* adapter) {
  constexpr std::array<D3D_FEATURE_LEVEL, 6> levels{
      D3D_FEATURE_LEVEL_12_1, D3D_FEATURE_LEVEL_12_0,
      D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0,
      D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0};
  ComPtr<ID3D11Device> device;
  D3D_FEATURE_LEVEL selected = D3D_FEATURE_LEVEL_10_0;
  HRESULT result = D3D11CreateDevice(
      adapter, D3D_DRIVER_TYPE_UNKNOWN, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
      levels.data(), static_cast<UINT>(levels.size()), D3D11_SDK_VERSION,
      &device, &selected, nullptr);
  // 旧版 Windows SDK 运行时可能不认识 11_1，请按 Microsoft 建议移除该项重试。
  if (result == E_INVALIDARG) {
    result = D3D11CreateDevice(
        adapter, D3D_DRIVER_TYPE_UNKNOWN, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT, levels.data() + 3, 3,
        D3D11_SDK_VERSION, &device, &selected, nullptr);
  }
  if (FAILED(result) || device == nullptr) return {};

  bool compute_supported = selected >= D3D_FEATURE_LEVEL_11_0;
  if (!compute_supported) {
    D3D11_FEATURE_DATA_D3D10_X_HARDWARE_OPTIONS options{};
    if (SUCCEEDED(device->CheckFeatureSupport(
            D3D11_FEATURE_D3D10_X_HARDWARE_OPTIONS, &options,
            sizeof(options)))) {
      compute_supported = options
                              .ComputeShaders_Plus_RawAndStructuredBuffers_Via_Shader_4_x !=
                          FALSE;
    }
  }
  return {FeatureLevelString(selected), compute_supported};
}

void AddMemoryInfo(flutter::EncodableMap* values, IDXGIAdapter1* adapter,
                   DXGI_MEMORY_SEGMENT_GROUP group, const char* budget_key,
                   const char* usage_key) {
  ComPtr<IDXGIAdapter3> adapter3;
  if (FAILED(adapter->QueryInterface(IID_PPV_ARGS(&adapter3)))) return;
  DXGI_QUERY_VIDEO_MEMORY_INFO info{};
  if (FAILED(adapter3->QueryVideoMemoryInfo(0, group, &info))) return;
  values->insert_or_assign(flutter::EncodableValue(budget_key),
                           flutter::EncodableValue(
                               static_cast<int64_t>(info.Budget)));
  values->insert_or_assign(flutter::EncodableValue(usage_key),
                           flutter::EncodableValue(
                               static_cast<int64_t>(info.CurrentUsage)));
}

/** 枚举适配器当前连接的桌面输出，记录真实输出色彩空间而非推测 HDR 状态。 */
void AddDisplayOutputs(flutter::EncodableMap* values, IDXGIAdapter1* adapter) {
  flutter::EncodableList outputs;
  for (UINT index = 0;; ++index) {
    ComPtr<IDXGIOutput> output;
    const HRESULT enumeration_result = adapter->EnumOutputs(index, &output);
    if (enumeration_result == DXGI_ERROR_NOT_FOUND) break;
    if (FAILED(enumeration_result) || output == nullptr) break;

    DXGI_OUTPUT_DESC base_description{};
    if (FAILED(output->GetDesc(&base_description))) continue;
    flutter::EncodableMap output_values{
        {flutter::EncodableValue("deviceName"),
         flutter::EncodableValue(Utf8FromWide(base_description.DeviceName))},
        {flutter::EncodableValue("attachedToDesktop"),
         flutter::EncodableValue(base_description.AttachedToDesktop != FALSE)},
        {flutter::EncodableValue("desktopLeft"),
         flutter::EncodableValue(
             static_cast<int64_t>(base_description.DesktopCoordinates.left))},
        {flutter::EncodableValue("desktopTop"),
         flutter::EncodableValue(
             static_cast<int64_t>(base_description.DesktopCoordinates.top))},
        {flutter::EncodableValue("desktopWidth"),
         flutter::EncodableValue(static_cast<int64_t>(
             base_description.DesktopCoordinates.right -
             base_description.DesktopCoordinates.left))},
        {flutter::EncodableValue("desktopHeight"),
         flutter::EncodableValue(static_cast<int64_t>(
             base_description.DesktopCoordinates.bottom -
             base_description.DesktopCoordinates.top))},
    };

    ComPtr<IDXGIOutput6> output6;
    if (SUCCEEDED(output.As(&output6)) && output6 != nullptr) {
      DXGI_OUTPUT_DESC1 description{};
      if (SUCCEEDED(output6->GetDesc1(&description))) {
        const bool hdr_signal_active =
            description.BitsPerColor >= 10 &&
            (description.ColorSpace ==
                 DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020 ||
             description.ColorSpace ==
                 DXGI_COLOR_SPACE_RGB_STUDIO_G2084_NONE_P2020 ||
             description.ColorSpace ==
                 DXGI_COLOR_SPACE_YCBCR_STUDIO_G2084_LEFT_P2020);
        output_values.insert_or_assign(
            flutter::EncodableValue("bitsPerColor"),
            flutter::EncodableValue(
                static_cast<int64_t>(description.BitsPerColor)));
        output_values.insert_or_assign(
            flutter::EncodableValue("colorSpace"),
            flutter::EncodableValue(ColorSpaceString(description.ColorSpace)));
        output_values.insert_or_assign(
            flutter::EncodableValue("hdrSignalActive"),
            flutter::EncodableValue(hdr_signal_active));
        output_values.insert_or_assign(
            flutter::EncodableValue("minLuminanceNits"),
            flutter::EncodableValue(
                static_cast<double>(description.MinLuminance)));
        output_values.insert_or_assign(
            flutter::EncodableValue("maxLuminanceNits"),
            flutter::EncodableValue(
                static_cast<double>(description.MaxLuminance)));
        output_values.insert_or_assign(
            flutter::EncodableValue("maxFullFrameLuminanceNits"),
            flutter::EncodableValue(
                static_cast<double>(description.MaxFullFrameLuminance)));
      }
    }
    outputs.emplace_back(std::move(output_values));
  }
  values->insert_or_assign(flutter::EncodableValue("outputs"),
                           flutter::EncodableValue(std::move(outputs)));
}

}  // namespace

flutter::EncodableMap QueryGpuCapabilityMatrix() {
  flutter::EncodableMap result{
      {flutter::EncodableValue("platformSupported"),
       flutter::EncodableValue(true)},
      {flutter::EncodableValue("probeStatus"),
       flutter::EncodableValue("failed")},
      {flutter::EncodableValue("detectionSource"),
       flutter::EncodableValue(kDetectionSource)},
      {flutter::EncodableValue("vulkanLoaderAvailable"),
       flutter::EncodableValue(false)},
      {flutter::EncodableValue("vulkanInstanceAvailable"),
       flutter::EncodableValue(false)},
  };

  ComPtr<IDXGIFactory1> factory;
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) {
    result.insert_or_assign(flutter::EncodableValue("errorCode"),
                            flutter::EncodableValue("dxgi-factory-failed"));
    result.insert_or_assign(flutter::EncodableValue("adapters"),
                            flutter::EncodableValue(flutter::EncodableList{}));
    return result;
  }

  const VulkanSnapshot vulkan = QueryVulkanDevices();
  result.insert_or_assign(flutter::EncodableValue("vulkanLoaderAvailable"),
                          flutter::EncodableValue(vulkan.loader_available));
  result.insert_or_assign(flutter::EncodableValue("vulkanInstanceAvailable"),
                          flutter::EncodableValue(vulkan.instance_available));

  flutter::EncodableList adapters;
  for (UINT index = 0;; ++index) {
    ComPtr<IDXGIAdapter1> adapter;
    const HRESULT enumeration_result = factory->EnumAdapters1(index, &adapter);
    if (enumeration_result == DXGI_ERROR_NOT_FOUND) break;
    if (FAILED(enumeration_result)) break;
    if (adapter == nullptr) continue;
    DXGI_ADAPTER_DESC1 description{};
    if (FAILED(adapter->GetDesc1(&description))) continue;

    const D3dSnapshot d3d = QueryD3dCapabilities(adapter.Get());
    const VulkanDevice* matched_vulkan = nullptr;
    for (const auto& candidate : vulkan.devices) {
      if (candidate.vendor_id == description.VendorId &&
          candidate.device_id == description.DeviceId) {
        matched_vulkan = &candidate;
        break;
      }
    }

    flutter::EncodableMap values{
        {flutter::EncodableValue("name"),
         flutter::EncodableValue(Utf8FromWide(description.Description))},
        {flutter::EncodableValue("luid"),
         flutter::EncodableValue(LuidString(description.AdapterLuid))},
        {flutter::EncodableValue("vendorId"),
         flutter::EncodableValue(static_cast<int64_t>(description.VendorId))},
        {flutter::EncodableValue("deviceId"),
         flutter::EncodableValue(static_cast<int64_t>(description.DeviceId))},
        {flutter::EncodableValue("enumerationIndex"),
         flutter::EncodableValue(static_cast<int64_t>(index))},
        {flutter::EncodableValue("isSoftware"),
         flutter::EncodableValue(
             (description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) != 0)},
        {flutter::EncodableValue("dedicatedVideoMemoryBytes"),
         flutter::EncodableValue(static_cast<int64_t>(
             description.DedicatedVideoMemory))},
        {flutter::EncodableValue("sharedSystemMemoryBytes"),
         flutter::EncodableValue(
             static_cast<int64_t>(description.SharedSystemMemory))},
        {flutter::EncodableValue("d3dFeatureLevel"),
         flutter::EncodableValue(d3d.feature_level)},
        {flutter::EncodableValue("computeShaderSupported"),
         flutter::EncodableValue(d3d.compute_shader_supported)},
        {flutter::EncodableValue("vulkanSupported"),
         flutter::EncodableValue(matched_vulkan != nullptr)},
    };
    AddMemoryInfo(&values, adapter.Get(), DXGI_MEMORY_SEGMENT_GROUP_LOCAL,
                  "localMemoryBudgetBytes", "localMemoryUsageBytes");
    AddMemoryInfo(&values, adapter.Get(), DXGI_MEMORY_SEGMENT_GROUP_NON_LOCAL,
                  "nonLocalMemoryBudgetBytes", "nonLocalMemoryUsageBytes");
    AddDisplayOutputs(&values, adapter.Get());
    if (matched_vulkan != nullptr) {
      values.insert_or_assign(
          flutter::EncodableValue("vulkanApiVersion"),
          flutter::EncodableValue(
              VulkanVersionString(matched_vulkan->api_version)));
      values.insert_or_assign(flutter::EncodableValue("vulkanDeviceName"),
                              flutter::EncodableValue(matched_vulkan->name));
    }
    adapters.emplace_back(std::move(values));
  }

  const bool no_adapters = adapters.empty();
  result.insert_or_assign(flutter::EncodableValue("adapters"),
                          flutter::EncodableValue(std::move(adapters)));
  if (no_adapters) {
    result.insert_or_assign(flutter::EncodableValue("errorCode"),
                            flutter::EncodableValue("no-dxgi-adapters"));
    return result;
  }
  result.insert_or_assign(flutter::EncodableValue("probeStatus"),
                          flutter::EncodableValue("ready"));
  return result;
}
