#include "../runner/local_video_enhancement_plugin.h"

#include <Windows.h>
#include <d3d11.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <iostream>

namespace {

using Microsoft::WRL::ComPtr;

/** 创建硬件 D3D11 设备；无硬件环境时退回 WARP，仍验证同设备纹理契约。 */
bool CreateDevice(ComPtr<ID3D11Device>* device,
                  ComPtr<ID3D11DeviceContext>* context) {
  D3D_FEATURE_LEVEL feature_level{};
  HRESULT result = D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, nullptr, 0,
      D3D11_SDK_VERSION, device->GetAddressOf(), &feature_level,
      context->GetAddressOf());
  if (SUCCEEDED(result)) return true;
  return SUCCEEDED(D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_WARP, nullptr, 0, nullptr, 0,
      D3D11_SDK_VERSION, device->GetAddressOf(), &feature_level,
      context->GetAddressOf()));
}

/** 把纹理第一行读回 CPU，用于比较插件调用前后的确定性像素。 */
bool ReadFirstRow(ID3D11Device* device, ID3D11DeviceContext* context,
                  ID3D11Texture2D* source,
                  std::array<uint32_t, 4>* pixels) {
  D3D11_TEXTURE2D_DESC desc{};
  source->GetDesc(&desc);
  desc.Usage = D3D11_USAGE_STAGING;
  desc.BindFlags = 0;
  desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  desc.MiscFlags = 0;
  ComPtr<ID3D11Texture2D> staging;
  if (FAILED(device->CreateTexture2D(&desc, nullptr, &staging))) return false;
  context->CopyResource(staging.Get(), source);
  D3D11_MAPPED_SUBRESOURCE mapped{};
  if (FAILED(context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped))) {
    return false;
  }
  memcpy(pixels->data(), mapped.pData, pixels->size() * sizeof(uint32_t));
  context->Unmap(staging.Get(), 0);
  return true;
}

}  // namespace

/**
 * SDK 零分发本机宿主自测。
 *
 * 第一次调用验证同设备纹理无损往返；第二次让探针破坏输出并返回错误，要求宿主
 * 恢复完整原帧且记录一次回退。DLL 路径仍由显式环境变量提供。
 */
int main() {
  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  if (!CreateDevice(&device, &context)) {
    std::cerr << "d3d11-device-create-failed\n";
    return 10;
  }

  constexpr std::array<uint32_t, 16> kPattern{
      0xff112233, 0xff445566, 0xff778899, 0xffaabbcc,
      0xff123456, 0xff234567, 0xff345678, 0xff456789,
      0xffabcdef, 0xffbcdef0, 0xffcdef01, 0xffdef012,
      0xff102030, 0xff405060, 0xff708090, 0xffa0b0c0,
  };
  D3D11_TEXTURE2D_DESC desc{};
  desc.Width = 4;
  desc.Height = 4;
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags =
      D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;
  D3D11_SUBRESOURCE_DATA initial{kPattern.data(), 4 * sizeof(uint32_t), 0};
  ComPtr<ID3D11Texture2D> texture;
  if (FAILED(device->CreateTexture2D(&desc, &initial, &texture))) {
    std::cerr << "shared-texture-create-failed\n";
    return 11;
  }

  SetEnvironmentVariableW(
      L"LOCAL_TAG_PLAYER_VIDEO_PLUGIN_PROBE_FAIL_AFTER", nullptr);
  {
    LocalVideoEnhancementPlugin plugin;
    plugin.Initialize(device.Get(), context.Get());
    if (plugin.GetSnapshot().state != "ready") {
      std::cerr << "probe-initialize-failed\n";
      return 12;
    }
    plugin.ProcessFrame(device.Get(), context.Get(), texture.Get(), 1);
    std::array<uint32_t, 4> first_row{};
    const auto snapshot = plugin.GetSnapshot();
    if (!ReadFirstRow(device.Get(), context.Get(), texture.Get(), &first_row) ||
        snapshot.state != "active" || snapshot.processed_frames != 1 ||
        snapshot.fallback_frames != 0 ||
        !std::equal(first_row.begin(), first_row.end(), kPattern.begin())) {
      std::cerr << "round-trip-verification-failed\n";
      return 13;
    }
  }

  SetEnvironmentVariableW(
      L"LOCAL_TAG_PLAYER_VIDEO_PLUGIN_PROBE_FAIL_AFTER", L"0");
  {
    LocalVideoEnhancementPlugin plugin;
    plugin.Initialize(device.Get(), context.Get());
    plugin.ProcessFrame(device.Get(), context.Get(), texture.Get(), 2);
    std::array<uint32_t, 4> first_row{};
    const auto snapshot = plugin.GetSnapshot();
    if (!ReadFirstRow(device.Get(), context.Get(), texture.Get(), &first_row) ||
        snapshot.state != "process-failed" ||
        snapshot.processed_frames != 0 ||
        snapshot.fallback_frames != 1 ||
        !std::equal(first_row.begin(), first_row.end(), kPattern.begin())) {
      std::cerr << "fallback-verification-failed\n";
      return 14;
    }
  }
  SetEnvironmentVariableW(
      L"LOCAL_TAG_PLAYER_VIDEO_PLUGIN_PROBE_FAIL_AFTER", nullptr);
  std::cout << "round-trip=passed fallback=passed\n";
  return 0;
}
