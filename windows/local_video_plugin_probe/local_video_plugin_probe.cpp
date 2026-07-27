#include "../native_player/local_video_enhancement_plugin_api.h"

#include <Windows.h>
#include <wrl/client.h>

#include <cstdint>
#include <cstdlib>

namespace {

Microsoft::WRL::ComPtr<ID3D11Texture2D> g_round_trip_texture;
D3D11_TEXTURE2D_DESC g_round_trip_desc{};
int64_t g_fail_after = -1;
uint64_t g_processed_frames = 0;

/** 读取故障注入帧号；负数表示始终成功。 */
int64_t ReadFailAfter() {
  wchar_t value[32]{};
  const DWORD written = GetEnvironmentVariableW(
      L"LOCAL_TAG_PLAYER_VIDEO_PLUGIN_PROBE_FAIL_AFTER", value, 32);
  if (written == 0 || written >= 32) return -1;
  wchar_t* end = nullptr;
  const long long parsed = wcstoll(value, &end, 10);
  return end == value ? -1 : parsed;
}

/** 尺寸变化时重建私有往返纹理，证明插件能消费播放器的活动 D3D11 设备。 */
bool EnsureRoundTripTexture(ID3D11Device* device,
                            const D3D11_TEXTURE2D_DESC& source_desc) {
  if (g_round_trip_texture != nullptr &&
      g_round_trip_desc.Width == source_desc.Width &&
      g_round_trip_desc.Height == source_desc.Height &&
      g_round_trip_desc.Format == source_desc.Format &&
      g_round_trip_desc.SampleDesc.Count == source_desc.SampleDesc.Count &&
      g_round_trip_desc.SampleDesc.Quality == source_desc.SampleDesc.Quality) {
    return true;
  }
  g_round_trip_texture.Reset();
  g_round_trip_desc = source_desc;
  g_round_trip_desc.BindFlags = 0;
  g_round_trip_desc.CPUAccessFlags = 0;
  g_round_trip_desc.MiscFlags = 0;
  g_round_trip_desc.Usage = D3D11_USAGE_DEFAULT;
  return SUCCEEDED(device->CreateTexture2D(
      &g_round_trip_desc, nullptr, &g_round_trip_texture));
}

int32_t __cdecl Initialize(
    const LtpLocalVideoPluginInitContext* context) {
  if (context == nullptr ||
      context->struct_size < sizeof(LtpLocalVideoPluginInitContext) ||
      context->abi_version != kLtpLocalVideoPluginAbiVersion ||
      context->device == nullptr || context->immediate_context == nullptr) {
    return 10;
  }
  g_fail_after = ReadFailAfter();
  g_processed_frames = 0;
  return 0;
}

int32_t __cdecl Process(
    const LtpLocalVideoPluginFrameContext* context) {
  if (context == nullptr ||
      context->struct_size < sizeof(LtpLocalVideoPluginFrameContext) ||
      context->abi_version != kLtpLocalVideoPluginAbiVersion ||
      context->device == nullptr || context->immediate_context == nullptr ||
      context->texture == nullptr) {
    return 20;
  }
  D3D11_TEXTURE2D_DESC desc{};
  context->texture->GetDesc(&desc);
  if (!EnsureRoundTripTexture(context->device, desc)) return 22;
  if (g_fail_after >= 0 &&
      static_cast<int64_t>(g_processed_frames) >= g_fail_after) {
    Microsoft::WRL::ComPtr<ID3D11RenderTargetView> render_target;
    if (FAILED(context->device->CreateRenderTargetView(
            context->texture, nullptr, &render_target))) {
      return 23;
    }
    const float poison_color[] = {1.0f, 0.0f, 1.0f, 1.0f};
    // 故障注入先确定性破坏输出，再返回错误，确保宿主自测真正覆盖原帧恢复。
    context->immediate_context->ClearRenderTargetView(render_target.Get(),
                                                       poison_color);
    return 21;
  }

  // 无视觉变化的双向 GPU 复制用于验证输入、输出和设备接入，不依赖厂商 SDK。
  context->immediate_context->CopyResource(g_round_trip_texture.Get(),
                                            context->texture);
  context->immediate_context->CopyResource(context->texture,
                                            g_round_trip_texture.Get());
  ++g_processed_frames;
  return 0;
}

void __cdecl Shutdown() {
  g_round_trip_texture.Reset();
  g_processed_frames = 0;
  g_fail_after = -1;
}

const LtpLocalVideoPluginApiV1 kApi{
    sizeof(LtpLocalVideoPluginApiV1),
    kLtpLocalVideoPluginAbiVersion,
    "ltp-d3d11-round-trip-probe",
    &Initialize,
    &Process,
    &Shutdown,
};

}  // namespace

extern "C" __declspec(dllexport) const LtpLocalVideoPluginApiV1* __cdecl
LtpGetLocalVideoEnhancementPluginV1() {
  return &kApi;
}
