#include "d3d11_midpoint_warper.h"

#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi1_6.h>
#include <windows.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <charconv>
#include <cmath>
#include <cstring>
#include <limits>
#include <string>

namespace {
using Microsoft::WRL::ComPtr;

constexpr char kWarpShader[] = R"(
cbuffer WarpParameters : register(b0) {
  uint Width;
  uint Height;
  uint LumaWidth;
  uint LumaHeight;
  uint FlowWidth;
  uint FlowHeight;
  uint Grid;
  uint Padding;
  float LumaPerPlaneX;
  float LumaPerPlaneY;
  float PlanePerLumaX;
  float PlanePerLumaY;
};

Texture2D<float> FirstFrame : register(t0);
Texture2D<float> SecondFrame : register(t1);
Texture2D<int2> ForwardFlow : register(t2);
Texture2D<int2> BackwardFlow : register(t3);
RWTexture2D<float> OutputFrame : register(u0);

float SampleFirst(float2 position) {
  position = clamp(position, float2(0.0, 0.0),
                   float2((float)Width - 1.0, (float)Height - 1.0));
  int2 lower = int2(floor(position));
  int2 upper = min(lower + int2(1, 1), int2(Width - 1, Height - 1));
  float2 fraction = position - float2(lower);
  float top = lerp(FirstFrame.Load(int3(lower.x, lower.y, 0)),
                   FirstFrame.Load(int3(upper.x, lower.y, 0)), fraction.x);
  float bottom = lerp(FirstFrame.Load(int3(lower.x, upper.y, 0)),
                      FirstFrame.Load(int3(upper.x, upper.y, 0)), fraction.x);
  return lerp(top, bottom, fraction.y);
}

float SampleSecond(float2 position) {
  position = clamp(position, float2(0.0, 0.0),
                   float2((float)Width - 1.0, (float)Height - 1.0));
  int2 lower = int2(floor(position));
  int2 upper = min(lower + int2(1, 1), int2(Width - 1, Height - 1));
  float2 fraction = position - float2(lower);
  float top = lerp(SecondFrame.Load(int3(lower.x, lower.y, 0)),
                   SecondFrame.Load(int3(upper.x, lower.y, 0)), fraction.x);
  float bottom = lerp(SecondFrame.Load(int3(lower.x, upper.y, 0)),
                      SecondFrame.Load(int3(upper.x, upper.y, 0)), fraction.x);
  return lerp(top, bottom, fraction.y);
}

[numthreads(16, 16, 1)]
void main(uint3 dispatch_id : SV_DispatchThreadID) {
  if (dispatch_id.x >= Width || dispatch_id.y >= Height) return;
  float2 plane_position = float2(dispatch_id.xy);
  float2 luma_position =
      (plane_position + 0.5) * float2(LumaPerPlaneX, LumaPerPlaneY) - 0.5;
  int2 flow_position = int2(max(luma_position, float2(0.0, 0.0)) /
                            (float)Grid);
  flow_position = clamp(flow_position, int2(0, 0),
                        int2(FlowWidth - 1, FlowHeight - 1));
  float2 forward = float2(ForwardFlow.Load(int3(flow_position, 0))) /
                   32.0 * float2(PlanePerLumaX, PlanePerLumaY);
  float2 backward = float2(BackwardFlow.Load(int3(flow_position, 0))) /
                    32.0 * float2(PlanePerLumaX, PlanePerLumaY);
  float first_value = SampleFirst(plane_position - 0.5 * forward);
  float second_value = SampleSecond(plane_position - 0.5 * backward);
  OutputFrame[dispatch_id.xy] = saturate((first_value + second_value) * 0.5);
}
)";

/** Compute Shader 常量按 16-byte 行对齐。 */
struct WarpParameters {
  std::uint32_t width = 0;
  std::uint32_t height = 0;
  std::uint32_t luma_width = 0;
  std::uint32_t luma_height = 0;
  std::uint32_t flow_width = 0;
  std::uint32_t flow_height = 0;
  std::uint32_t grid = 0;
  std::uint32_t padding = 0;
  float luma_per_plane_x = 1.0F;
  float luma_per_plane_y = 1.0F;
  float plane_per_luma_x = 1.0F;
  float plane_per_luma_y = 1.0F;
};
static_assert(sizeof(WarpParameters) % 16 == 0);

/** 单个 Y/U/V 平面复用的输入、输出和读回资源。 */
struct PlaneResources {
  int width = 0;
  int height = 0;
  ComPtr<ID3D11Texture2D> first;
  ComPtr<ID3D11Texture2D> second;
  ComPtr<ID3D11ShaderResourceView> first_view;
  ComPtr<ID3D11ShaderResourceView> second_view;
  ComPtr<ID3D11Texture2D> output;
  ComPtr<ID3D11UnorderedAccessView> output_view;
  ComPtr<ID3D11Texture2D> staging;

  void Reset() {
    width = 0;
    height = 0;
    first.Reset();
    second.Reset();
    first_view.Reset();
    second_view.Reset();
    output.Reset();
    output_view.Reset();
    staging.Reset();
  }
};

/** 解析固定 `hhhhhhhh:llllllll` LUID。 */
bool ParseLuid(const std::string& value, LUID* luid) {
  if (luid == nullptr || value.size() != 17 || value[8] != ':') return false;
  std::uint32_t high = 0;
  std::uint32_t low = 0;
  const auto high_result = std::from_chars(
      value.data(), value.data() + 8, high, 16);
  const auto low_result = std::from_chars(
      value.data() + 9, value.data() + value.size(), low, 16);
  if (high_result.ec != std::errc() ||
      high_result.ptr != value.data() + 8 ||
      low_result.ec != std::errc() ||
      low_result.ptr != value.data() + value.size()) {
    return false;
  }
  luid->HighPart = static_cast<LONG>(high);
  luid->LowPart = low;
  return true;
}

bool SameLuid(const LUID& left, const LUID& right) {
  return left.HighPart == right.HighPart && left.LowPart == right.LowPart;
}
}  // namespace

class D3D11MidpointWarper::Impl {
 public:
  /** 在显式 LUID 上创建设备和固定计算管线。 */
  bool Initialize(const std::string& adapter_luid) {
    LUID requested{};
    if (!ParseLuid(adapter_luid, &requested)) {
      return Fail("invalid-d3d11-adapter-luid");
    }
    ComPtr<IDXGIFactory1> factory;
    if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) {
      return Fail("dxgi-factory-failed");
    }
    ComPtr<IDXGIAdapter1> selected;
    for (UINT index = 0;; ++index) {
      ComPtr<IDXGIAdapter1> candidate;
      const HRESULT result = factory->EnumAdapters1(index, &candidate);
      if (result == DXGI_ERROR_NOT_FOUND) break;
      if (FAILED(result)) break;
      DXGI_ADAPTER_DESC1 description{};
      if (SUCCEEDED(candidate->GetDesc1(&description)) &&
          SameLuid(description.AdapterLuid, requested)) {
        selected = candidate;
        break;
      }
    }
    if (selected == nullptr) return Fail("d3d11-adapter-not-found");

    constexpr std::array<D3D_FEATURE_LEVEL, 4> levels{
        D3D_FEATURE_LEVEL_12_1, D3D_FEATURE_LEVEL_12_0,
        D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0};
    D3D_FEATURE_LEVEL selected_level = D3D_FEATURE_LEVEL_11_0;
    HRESULT result = D3D11CreateDevice(
        selected.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT, levels.data(),
        static_cast<UINT>(levels.size()), D3D11_SDK_VERSION, &device_,
        &selected_level, &context_);
    if (result == E_INVALIDARG) {
      result = D3D11CreateDevice(
          selected.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr,
          D3D11_CREATE_DEVICE_BGRA_SUPPORT, levels.data() + 3, 1,
          D3D11_SDK_VERSION, &device_, &selected_level, &context_);
    }
    if (FAILED(result) || device_ == nullptr || context_ == nullptr ||
        selected_level < D3D_FEATURE_LEVEL_11_0) {
      return Fail("create-d3d11-compute-device");
    }

    ComPtr<ID3DBlob> bytecode;
    ComPtr<ID3DBlob> compiler_error;
    if (FAILED(D3DCompile(
            kWarpShader, sizeof(kWarpShader) - 1,
            "ltp_nvofa_midpoint_warp.hlsl", nullptr, nullptr, "main",
            "cs_5_0", D3DCOMPILE_OPTIMIZATION_LEVEL3, 0,
            &bytecode, &compiler_error)) ||
        bytecode == nullptr) {
      return Fail("compile-d3d11-warp-shader");
    }
    if (FAILED(device_->CreateComputeShader(
            bytecode->GetBufferPointer(), bytecode->GetBufferSize(),
            nullptr, &shader_))) {
      return Fail("create-d3d11-warp-shader");
    }
    D3D11_BUFFER_DESC constants{};
    constants.ByteWidth = sizeof(WarpParameters);
    constants.Usage = D3D11_USAGE_DEFAULT;
    constants.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    if (FAILED(device_->CreateBuffer(
            &constants, nullptr, &constant_buffer_))) {
      return Fail("create-d3d11-warp-constants");
    }
    adapter_luid_ = adapter_luid;
    error_.clear();
    return true;
  }

  /** 上传同一中间帧的双向光流，三个颜色平面共享。 */
  bool PrepareFlow(
      const std::vector<NV_OF_FLOW_VECTOR>& forward,
      const std::vector<NV_OF_FLOW_VECTOR>& backward,
      std::uint32_t width,
      std::uint32_t height,
      std::uint32_t grid) {
    const std::size_t count =
        static_cast<std::size_t>(width) * height;
    if (device_ == nullptr || context_ == nullptr || width == 0 ||
        height == 0 || grid == 0 || forward.size() != count ||
        backward.size() != count) {
      return Fail("invalid-d3d11-flow");
    }
    if (!EnsureFlowResources(width, height)) return false;
    const UINT row_pitch =
        width * static_cast<UINT>(sizeof(NV_OF_FLOW_VECTOR));
    context_->UpdateSubresource(
        forward_flow_.Get(), 0, nullptr, forward.data(), row_pitch, 0);
    context_->UpdateSubresource(
        backward_flow_.Get(), 0, nullptr, backward.data(), row_pitch, 0);
    flow_width_ = width;
    flow_height_ = height;
    grid_ = grid;
    return true;
  }

  /** 上传软件平面，执行 compute，并只把最终 8-bit 平面读回 VapourSynth。 */
  bool WarpPlane(
      int plane_index,
      const std::uint8_t* first,
      std::ptrdiff_t first_stride,
      const std::uint8_t* second,
      std::ptrdiff_t second_stride,
      std::uint8_t* destination,
      std::ptrdiff_t destination_stride,
      int width,
      int height,
      int luma_width,
      int luma_height) {
    if (plane_index < 0 ||
        plane_index >= static_cast<int>(planes_.size()) ||
        first == nullptr || second == nullptr || destination == nullptr ||
        width <= 0 || height <= 0 || luma_width <= 0 ||
        luma_height <= 0 || first_stride < width ||
        second_stride < width || destination_stride < width ||
        flow_width_ == 0 || flow_height_ == 0 || grid_ == 0) {
      return Fail("invalid-d3d11-plane");
    }
    PlaneResources& plane = planes_[plane_index];
    if (!EnsurePlaneResources(&plane, width, height)) return false;
    context_->UpdateSubresource(
        plane.first.Get(), 0, nullptr, first,
        static_cast<UINT>(first_stride), 0);
    context_->UpdateSubresource(
        plane.second.Get(), 0, nullptr, second,
        static_cast<UINT>(second_stride), 0);

    WarpParameters parameters;
    parameters.width = static_cast<std::uint32_t>(width);
    parameters.height = static_cast<std::uint32_t>(height);
    parameters.luma_width = static_cast<std::uint32_t>(luma_width);
    parameters.luma_height = static_cast<std::uint32_t>(luma_height);
    parameters.flow_width = flow_width_;
    parameters.flow_height = flow_height_;
    parameters.grid = grid_;
    parameters.luma_per_plane_x =
        static_cast<float>(luma_width) / static_cast<float>(width);
    parameters.luma_per_plane_y =
        static_cast<float>(luma_height) / static_cast<float>(height);
    parameters.plane_per_luma_x = 1.0F / parameters.luma_per_plane_x;
    parameters.plane_per_luma_y = 1.0F / parameters.luma_per_plane_y;
    context_->UpdateSubresource(
        constant_buffer_.Get(), 0, nullptr, &parameters, 0, 0);

    ID3D11ShaderResourceView* views[] = {
        plane.first_view.Get(), plane.second_view.Get(),
        forward_flow_view_.Get(), backward_flow_view_.Get()};
    ID3D11UnorderedAccessView* output_view = plane.output_view.Get();
    ID3D11Buffer* constants = constant_buffer_.Get();
    context_->CSSetShader(shader_.Get(), nullptr, 0);
    context_->CSSetConstantBuffers(0, 1, &constants);
    context_->CSSetShaderResources(0, 4, views);
    context_->CSSetUnorderedAccessViews(0, 1, &output_view, nullptr);
    context_->Dispatch(
        (static_cast<UINT>(width) + 15) / 16,
        (static_cast<UINT>(height) + 15) / 16, 1);

    // 解除绑定后再复制到 staging，避免驱动把读写 hazard 延迟到下一帧。
    std::array<ID3D11ShaderResourceView*, 4> empty_views{};
    ID3D11UnorderedAccessView* empty_output = nullptr;
    context_->CSSetShaderResources(0, 4, empty_views.data());
    context_->CSSetUnorderedAccessViews(0, 1, &empty_output, nullptr);
    context_->CSSetShader(nullptr, nullptr, 0);
    context_->CopyResource(plane.staging.Get(), plane.output.Get());

    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context_->Map(
            plane.staging.Get(), 0, D3D11_MAP_READ, 0, &mapped)) ||
        mapped.pData == nullptr) {
      return Fail("map-d3d11-warp-output");
    }
    if (mapped.RowPitch <
        static_cast<UINT>(width * sizeof(float))) {
      context_->Unmap(plane.staging.Get(), 0);
      return Fail("invalid-d3d11-warp-row-pitch");
    }
    for (int y = 0; y < height; ++y) {
      const auto* source = reinterpret_cast<const float*>(
          static_cast<const std::uint8_t*>(mapped.pData) +
          static_cast<std::size_t>(y) * mapped.RowPitch);
      auto* output = destination + y * destination_stride;
      for (int x = 0; x < width; ++x) {
        const long value =
            std::lround(std::clamp(source[x], 0.0F, 1.0F) * 255.0F);
        output[x] = static_cast<std::uint8_t>(
            std::clamp(value, 0L, 255L));
      }
    }
    context_->Unmap(plane.staging.Get(), 0);
    return true;
  }

  const std::string& error() const { return error_; }

 private:
  bool Fail(const char* stage) {
    error_ = stage;
    return false;
  }

  /** 创建或复用 R16G16_SINT 光流纹理及 SRV。 */
  bool EnsureFlowResources(std::uint32_t width, std::uint32_t height) {
    if (forward_flow_ != nullptr && flow_resource_width_ == width &&
        flow_resource_height_ == height) {
      return true;
    }
    forward_flow_.Reset();
    backward_flow_.Reset();
    forward_flow_view_.Reset();
    backward_flow_view_.Reset();
    D3D11_TEXTURE2D_DESC description{};
    description.Width = width;
    description.Height = height;
    description.MipLevels = 1;
    description.ArraySize = 1;
    description.Format = DXGI_FORMAT_R16G16_SINT;
    description.SampleDesc.Count = 1;
    description.Usage = D3D11_USAGE_DEFAULT;
    description.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    if (FAILED(device_->CreateTexture2D(
            &description, nullptr, &forward_flow_)) ||
        FAILED(device_->CreateTexture2D(
            &description, nullptr, &backward_flow_)) ||
        FAILED(device_->CreateShaderResourceView(
            forward_flow_.Get(), nullptr, &forward_flow_view_)) ||
        FAILED(device_->CreateShaderResourceView(
            backward_flow_.Get(), nullptr, &backward_flow_view_))) {
      return Fail("create-d3d11-flow-resources");
    }
    flow_resource_width_ = width;
    flow_resource_height_ = height;
    return true;
  }

  /** 为一个颜色平面创建可复用的 R8 输入、R32 输出与 staging。 */
  bool EnsurePlaneResources(
      PlaneResources* plane, int width, int height) {
    if (plane == nullptr) return Fail("missing-d3d11-plane");
    if (plane->first != nullptr && plane->width == width &&
        plane->height == height) {
      return true;
    }
    plane->Reset();
    D3D11_TEXTURE2D_DESC input{};
    input.Width = static_cast<UINT>(width);
    input.Height = static_cast<UINT>(height);
    input.MipLevels = 1;
    input.ArraySize = 1;
    input.Format = DXGI_FORMAT_R8_UNORM;
    input.SampleDesc.Count = 1;
    input.Usage = D3D11_USAGE_DEFAULT;
    input.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    if (FAILED(device_->CreateTexture2D(
            &input, nullptr, &plane->first)) ||
        FAILED(device_->CreateTexture2D(
            &input, nullptr, &plane->second)) ||
        FAILED(device_->CreateShaderResourceView(
            plane->first.Get(), nullptr, &plane->first_view)) ||
        FAILED(device_->CreateShaderResourceView(
            plane->second.Get(), nullptr, &plane->second_view))) {
      return Fail("create-d3d11-plane-input");
    }

    D3D11_TEXTURE2D_DESC output = input;
    output.Format = DXGI_FORMAT_R32_FLOAT;
    output.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
    if (FAILED(device_->CreateTexture2D(
            &output, nullptr, &plane->output)) ||
        FAILED(device_->CreateUnorderedAccessView(
            plane->output.Get(), nullptr, &plane->output_view))) {
      return Fail("create-d3d11-plane-output");
    }
    D3D11_TEXTURE2D_DESC staging = output;
    staging.Usage = D3D11_USAGE_STAGING;
    staging.BindFlags = 0;
    staging.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    if (FAILED(device_->CreateTexture2D(
            &staging, nullptr, &plane->staging))) {
      return Fail("create-d3d11-plane-staging");
    }
    plane->width = width;
    plane->height = height;
    return true;
  }

  ComPtr<ID3D11Device> device_;
  ComPtr<ID3D11DeviceContext> context_;
  ComPtr<ID3D11ComputeShader> shader_;
  ComPtr<ID3D11Buffer> constant_buffer_;
  ComPtr<ID3D11Texture2D> forward_flow_;
  ComPtr<ID3D11Texture2D> backward_flow_;
  ComPtr<ID3D11ShaderResourceView> forward_flow_view_;
  ComPtr<ID3D11ShaderResourceView> backward_flow_view_;
  std::array<PlaneResources, 3> planes_;
  std::uint32_t flow_resource_width_ = 0;
  std::uint32_t flow_resource_height_ = 0;
  std::uint32_t flow_width_ = 0;
  std::uint32_t flow_height_ = 0;
  std::uint32_t grid_ = 0;
  std::string adapter_luid_;
  std::string error_;
};

D3D11MidpointWarper::D3D11MidpointWarper()
    : impl_(std::make_unique<Impl>()) {}

D3D11MidpointWarper::~D3D11MidpointWarper() = default;

bool D3D11MidpointWarper::Initialize(
    const std::string& adapter_luid) {
  return impl_->Initialize(adapter_luid);
}

bool D3D11MidpointWarper::PrepareFlow(
    const std::vector<NV_OF_FLOW_VECTOR>& forward,
    const std::vector<NV_OF_FLOW_VECTOR>& backward,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t grid) {
  return impl_->PrepareFlow(forward, backward, width, height, grid);
}

bool D3D11MidpointWarper::WarpPlane(
    int plane_index,
    const std::uint8_t* first,
    std::ptrdiff_t first_stride,
    const std::uint8_t* second,
    std::ptrdiff_t second_stride,
    std::uint8_t* destination,
    std::ptrdiff_t destination_stride,
    int width,
    int height,
    int luma_width,
    int luma_height) {
  return impl_->WarpPlane(
      plane_index, first, first_stride, second, second_stride,
      destination, destination_stride, width, height,
      luma_width, luma_height);
}

const std::string& D3D11MidpointWarper::error() const {
  return impl_->error();
}
