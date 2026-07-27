#include "d3d11_adapter_selector.h"

#include <d3d11.h>
#include <dxgi1_6.h>
#include <windows.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdio>
#include <cwctype>
#include <string>
#include <vector>

namespace {
using Microsoft::WRL::ComPtr;

constexpr std::uint32_t kNvidiaVendorId = 0x10de;
constexpr wchar_t kRequestedLuidEnvironment[] =
    L"LOCAL_TAG_PLAYER_NVIDIA_ADAPTER_LUID";

/** 适配器候选保留 mpv 选项所需名称和 CUDA 匹配所需 LUID。 */
struct AdapterCandidate {
  DXGI_ADAPTER_DESC1 description{};
  std::string utf8_description;
  std::string luid;
};

/** 将 DXGI LUID 归一化为能力矩阵使用的固定十六进制格式。 */
std::string LuidString(const LUID& luid) {
  std::array<char, 32> buffer{};
  std::snprintf(buffer.data(), buffer.size(), "%08x:%08x",
                static_cast<std::uint32_t>(luid.HighPart), luid.LowPart);
  return buffer.data();
}

/** 把 DXGI 的宽字符描述转换为 mpv 选项要求的 UTF-8。 */
std::string Utf8FromWide(const wchar_t* value) {
  if (value == nullptr || value[0] == L'\0') return {};
  const int length = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0,
                                         nullptr, nullptr);
  if (length <= 1) return {};
  std::string result(static_cast<std::size_t>(length), '\0');
  if (WideCharToMultiByte(CP_UTF8, 0, value, -1, result.data(), length,
                          nullptr, nullptr) <= 0) {
    return {};
  }
  result.resize(static_cast<std::size_t>(length - 1));
  return result;
}

/** 读取完整可选 LUID；不扫描注册表或其它配置位置。 */
std::string RequestedLuid() {
  const DWORD required =
      GetEnvironmentVariableW(kRequestedLuidEnvironment, nullptr, 0);
  if (required <= 1) return {};
  std::wstring value(static_cast<std::size_t>(required), L'\0');
  const DWORD written = GetEnvironmentVariableW(
      kRequestedLuidEnvironment, value.data(), required);
  if (written == 0 || written >= required) return {};
  value.resize(written);
  std::string result = Utf8FromWide(value.c_str());
  std::transform(result.begin(), result.end(), result.begin(),
                 [](unsigned char current) {
                   return static_cast<char>(std::tolower(current));
                 });
  return result;
}

/** mpv 按不区分大小写的名称前缀匹配；完整同名仍然无法区分，必须拒绝。 */
bool SameDescription(const wchar_t* left, const wchar_t* right) {
  if (left == nullptr || right == nullptr) return false;
  while (*left != L'\0' && *right != L'\0') {
    if (std::towlower(*left) != std::towlower(*right)) return false;
    ++left;
    ++right;
  }
  return *left == L'\0' && *right == L'\0';
}

/** 只有可创建 Feature Level 11.0+ 设备的硬件适配器才进入候选。 */
bool SupportsRequiredD3D11(IDXGIAdapter1* adapter) {
  constexpr std::array<D3D_FEATURE_LEVEL, 4> levels{
      D3D_FEATURE_LEVEL_12_1, D3D_FEATURE_LEVEL_12_0,
      D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0};
  ComPtr<ID3D11Device> device;
  D3D_FEATURE_LEVEL selected = D3D_FEATURE_LEVEL_11_0;
  HRESULT result = D3D11CreateDevice(
      adapter, D3D_DRIVER_TYPE_UNKNOWN, nullptr,
      D3D11_CREATE_DEVICE_BGRA_SUPPORT, levels.data(),
      static_cast<UINT>(levels.size()), D3D11_SDK_VERSION, &device,
      &selected, nullptr);
  if (result == E_INVALIDARG) {
    result = D3D11CreateDevice(
        adapter, D3D_DRIVER_TYPE_UNKNOWN, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT, levels.data() + 3, 1,
        D3D11_SDK_VERSION, &device, &selected, nullptr);
  }
  return SUCCEEDED(result) && device != nullptr &&
         selected >= D3D_FEATURE_LEVEL_11_0;
}

/** 添加一个 NVIDIA 硬件候选，并按 LUID 去重。 */
void AddCandidate(IDXGIAdapter1* adapter,
                  std::vector<AdapterCandidate>* candidates) {
  if (adapter == nullptr || candidates == nullptr) return;
  DXGI_ADAPTER_DESC1 description{};
  if (FAILED(adapter->GetDesc1(&description)) ||
      (description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) != 0 ||
      description.VendorId != kNvidiaVendorId ||
      !SupportsRequiredD3D11(adapter)) {
    return;
  }
  const std::string luid = LuidString(description.AdapterLuid);
  if (std::any_of(
          candidates->begin(), candidates->end(),
          [&luid](const AdapterCandidate& item) {
            return item.luid == luid;
          })) {
    return;
  }
  const std::string utf8_description =
      Utf8FromWide(description.Description);
  if (utf8_description.empty()) return;
  candidates->push_back(
      AdapterCandidate{description, utf8_description, luid});
}

/** 优先使用 DXGI 1.6 的高性能顺序，旧系统再退回标准枚举顺序。 */
std::vector<AdapterCandidate> EnumerateCandidates(
    IDXGIFactory1* factory) {
  std::vector<AdapterCandidate> candidates;
  ComPtr<IDXGIFactory6> factory6;
  if (SUCCEEDED(factory->QueryInterface(IID_PPV_ARGS(&factory6))) &&
      factory6 != nullptr) {
    for (UINT index = 0;; ++index) {
      ComPtr<IDXGIAdapter1> adapter;
      const HRESULT result = factory6->EnumAdapterByGpuPreference(
          index, DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE,
          IID_PPV_ARGS(&adapter));
      if (result == DXGI_ERROR_NOT_FOUND) break;
      if (FAILED(result)) break;
      AddCandidate(adapter.Get(), &candidates);
    }
    return candidates;
  }
  for (UINT index = 0;; ++index) {
    ComPtr<IDXGIAdapter1> adapter;
    const HRESULT result = factory->EnumAdapters1(index, &adapter);
    if (result == DXGI_ERROR_NOT_FOUND) break;
    if (FAILED(result)) break;
    AddCandidate(adapter.Get(), &candidates);
  }
  return candidates;
}
}  // namespace

D3D11AdapterSelection SelectNvidiaD3D11Adapter() {
  D3D11AdapterSelection result;
  ComPtr<IDXGIFactory1> factory;
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory))) ||
      factory == nullptr) {
    result.error = "dxgi-factory-failed";
    return result;
  }
  const auto candidates = EnumerateCandidates(factory.Get());
  if (candidates.empty()) {
    result.error = "nvidia-d3d11-adapter-not-found";
    return result;
  }

  const std::string requested_luid = RequestedLuid();
  const AdapterCandidate* selected = nullptr;
  if (!requested_luid.empty()) {
    const auto found = std::find_if(
        candidates.begin(), candidates.end(),
        [&requested_luid](const AdapterCandidate& item) {
          return item.luid == requested_luid;
        });
    if (found == candidates.end()) {
      result.error = "requested-nvidia-adapter-not-found";
      return result;
    }
    selected = &*found;
  } else {
    selected = &candidates.front();
  }

  const std::size_t same_name_count =
      static_cast<std::size_t>(std::count_if(
          candidates.begin(), candidates.end(),
          [selected](const AdapterCandidate& item) {
            return SameDescription(
                item.description.Description,
                selected->description.Description);
          }));
  if (same_name_count != 1) {
    result.state = "ambiguous";
    result.error = "duplicate-nvidia-adapter-description";
    return result;
  }

  result.state = "ready";
  result.error.clear();
  result.description = selected->utf8_description;
  result.luid = selected->luid;
  result.vendor_id = selected->description.VendorId;
  result.device_id = selected->description.DeviceId;
  return result;
}
