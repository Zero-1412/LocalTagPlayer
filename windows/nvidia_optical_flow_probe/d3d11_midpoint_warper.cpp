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

constexpr char kFlowInfillShader[] = R"(
cbuffer FlowParameters : register(b0) {
  uint FlowWidth;
  uint FlowHeight;
  uint Grid;
  uint Padding;
};

Texture2D<int2> ForwardFlow : register(t0);
Texture2D<int2> BackwardFlow : register(t1);
Texture2D<uint> ForwardCost : register(t2);
Texture2D<uint> BackwardCost : register(t3);
RWTexture2D<float4> ResolvedForward : register(u0);
RWTexture2D<float4> ResolvedBackward : register(u1);

int2 ClampFlowCoordinate(int2 coordinate) {
  return clamp(coordinate, int2(0, 0),
               int2(FlowWidth - 1, FlowHeight - 1));
}

int2 FlowCoordinateFromLuma(float2 luma_position) {
  int2 coordinate =
      int2(max(luma_position, float2(0.0, 0.0)) / (float)Grid);
  return ClampFlowCoordinate(coordinate);
}

float2 LoadForwardAt(int2 coordinate) {
  return float2(ForwardFlow.Load(
      int3(ClampFlowCoordinate(coordinate), 0))) / 32.0;
}

float2 LoadBackwardAt(int2 coordinate) {
  return float2(BackwardFlow.Load(
      int3(ClampFlowCoordinate(coordinate), 0))) / 32.0;
}

float FlowConfidence(float2 flow, float2 reverse, uint hardware_cost) {
  float residual = length(flow + reverse);
  float tolerance =
      1.5 + 0.05 * (length(flow) + length(reverse));
  float consistency =
      1.0 - saturate((residual - tolerance) / tolerance);
  float cost_confidence =
      1.0 - saturate((float)hardware_cost / 255.0);
  return max(0.02,
             (0.15 + 0.85 * consistency) *
             (0.15 + 0.85 * cost_confidence));
}

float4 EvaluateForward(int2 coordinate) {
  coordinate = ClampFlowCoordinate(coordinate);
  float2 flow = LoadForwardAt(coordinate);
  float2 origin =
      (float2(coordinate) + 0.5) * (float)Grid - 0.5;
  float2 reverse = LoadBackwardAt(
      FlowCoordinateFromLuma(origin + flow));
  uint cost = ForwardCost.Load(int3(coordinate, 0));
  return float4(flow, FlowConfidence(flow, reverse, cost), 1.0);
}

float4 EvaluateBackward(int2 coordinate) {
  coordinate = ClampFlowCoordinate(coordinate);
  float2 flow = LoadBackwardAt(coordinate);
  float2 origin =
      (float2(coordinate) + 0.5) * (float)Grid - 0.5;
  float2 reverse = LoadForwardAt(
      FlowCoordinateFromLuma(origin + flow));
  uint cost = BackwardCost.Load(int3(coordinate, 0));
  return float4(flow, FlowConfidence(flow, reverse, cost), 1.0);
}

float4 ResolveForward(int2 coordinate) {
  float4 center = EvaluateForward(coordinate);
  if (center.z >= 0.30) return center;
  float4 best = center;
  float best_score = center.z;
  [unroll]
  for (int y = -2; y <= 2; ++y) {
    [unroll]
    for (int x = -2; x <= 2; ++x) {
      if (x == 0 && y == 0) continue;
      float4 candidate = EvaluateForward(coordinate + int2(x, y));
      float score =
          candidate.z - 0.04 * length(float2(x, y));
      if (score > best_score) {
        best = candidate;
        best_score = score;
      }
    }
  }
  if (best.z >= 0.35 && best.z > center.z + 0.12) {
    return float4(best.xy, best.z * 0.92, 0.0);
  }
  return center;
}

float4 ResolveBackward(int2 coordinate) {
  float4 center = EvaluateBackward(coordinate);
  if (center.z >= 0.30) return center;
  float4 best = center;
  float best_score = center.z;
  [unroll]
  for (int y = -2; y <= 2; ++y) {
    [unroll]
    for (int x = -2; x <= 2; ++x) {
      if (x == 0 && y == 0) continue;
      float4 candidate = EvaluateBackward(coordinate + int2(x, y));
      float score =
          candidate.z - 0.04 * length(float2(x, y));
      if (score > best_score) {
        best = candidate;
        best_score = score;
      }
    }
  }
  if (best.z >= 0.35 && best.z > center.z + 0.12) {
    return float4(best.xy, best.z * 0.92, 0.0);
  }
  return center;
}

[numthreads(16, 16, 1)]
void main(uint3 dispatch_id : SV_DispatchThreadID) {
  if (dispatch_id.x >= FlowWidth || dispatch_id.y >= FlowHeight) return;
  int2 coordinate = int2(dispatch_id.xy);
  ResolvedForward[coordinate] = ResolveForward(coordinate);
  ResolvedBackward[coordinate] = ResolveBackward(coordinate);
}
)";

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
Texture2D<float4> ResolvedForward : register(t2);
Texture2D<float4> ResolvedBackward : register(t3);
RWTexture2D<float4> WarpCandidate : register(u0);

int2 FlowCoordinate(float2 luma_position) {
  int2 coordinate =
      int2(max(luma_position, float2(0.0, 0.0)) / (float)Grid);
  return clamp(coordinate, int2(0, 0),
               int2(FlowWidth - 1, FlowHeight - 1));
}

float4 LoadForward(float2 luma_position) {
  return ResolvedForward.Load(
      int3(FlowCoordinate(luma_position), 0));
}

float4 LoadBackward(float2 luma_position) {
  return ResolvedBackward.Load(
      int3(FlowCoordinate(luma_position), 0));
}

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
  float4 forward_data = LoadForward(luma_position);
  float2 forward = forward_data.xy;
  float2 first_source_luma = luma_position - 0.5 * forward;
  float4 backward_data = LoadBackward(luma_position);
  float2 backward = backward_data.xy;
  float2 second_source_luma = luma_position - 0.5 * backward;

  float first_confidence = forward_data.z;
  float second_confidence = backward_data.z;

  float2 plane_scale = float2(PlanePerLumaX, PlanePerLumaY);
  float first_value =
      SampleFirst(plane_position - 0.5 * forward * plane_scale);
  float second_value =
      SampleSecond(plane_position - 0.5 * backward * plane_scale);
  float confidence_sum = first_confidence + second_confidence;
  float reliability_share = first_confidence / confidence_sum;
  // NVOFA cost 与前后向一致性只能识别风险，不能替代 FRUC 的矢量补洞和图像补洞。
  // 因此平均合成仍占 85%，可靠性最多把比例推到约 57.5/42.5，避免高反差
  // 动画边缘因强选单侧样本产生暗色拖影。
  float first_weight =
      clamp(lerp(0.5, reliability_share, 0.15), 0.425, 0.575);
  float candidate = saturate(
      first_value * first_weight +
      second_value * (1.0 - first_weight));
  float dominance =
      (first_confidence - second_confidence) / confidence_sum;
  float disagreement = abs(first_value - second_value);
  float peak_confidence =
      max(first_confidence, second_confidence);
  float low_flow_risk =
      (1.0 - smoothstep(0.20, 0.55, peak_confidence)) *
      smoothstep(0.04, 0.18, disagreement);
  float occlusion_risk =
      smoothstep(0.45, 0.85, abs(dominance)) *
      smoothstep(0.05, 0.22, disagreement);
  float infill_risk =
      (1.0 - min(forward_data.w, backward_data.w)) *
      smoothstep(0.08, 0.25, disagreement) * 0.35;
  float validity =
      1.0 - saturate(max(max(low_flow_risk, occlusion_risk),
                         infill_risk));
  WarpCandidate[dispatch_id.xy] =
      float4(candidate, validity, dominance, 0.0);
}
)";

constexpr char kHoleFillShader[] = R"(
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

Texture2D<float4> WarpCandidate : register(t0);
RWTexture2D<float> OutputFrame : register(u0);

int2 ClampPixel(int2 coordinate) {
  return clamp(coordinate, int2(0, 0),
               int2(Width - 1, Height - 1));
}

[numthreads(16, 16, 1)]
void main(uint3 dispatch_id : SV_DispatchThreadID) {
  if (dispatch_id.x >= Width || dispatch_id.y >= Height) return;
  int2 coordinate = int2(dispatch_id.xy);
  float4 center = WarpCandidate.Load(int3(coordinate, 0));
  if (center.y >= 0.82) {
    OutputFrame[coordinate] = center.x;
    return;
  }

  float4 best = center;
  float best_score = -1000.0;
  bool found = false;
  [unroll]
  for (int radius = 1; radius <= 4; ++radius) {
    [loop]
    for (int y = -radius; y <= radius; ++y) {
      [loop]
      for (int x = -radius; x <= radius; ++x) {
        if (abs(x) != radius && abs(y) != radius) continue;
        int2 sample_coordinate = ClampPixel(
            coordinate + int2(x, y));
        float4 candidate =
            WarpCandidate.Load(int3(sample_coordinate, 0));
        if (candidate.y < max(0.55, center.y + 0.08)) continue;
        float distance_penalty =
            0.06 * length(float2(x, y));
        float side_penalty =
            0.18 * abs(candidate.z - center.z);
        float color_penalty =
            0.05 * abs(candidate.x - center.x);
        float score = candidate.y - distance_penalty -
                      side_penalty - color_penalty;
        if (!found || score > best_score) {
          best = candidate;
          best_score = score;
          found = true;
        }
      }
    }
  }

  float fill_strength =
      found ? saturate((0.82 - center.y) / 0.65) : 0.0;
  OutputFrame[coordinate] =
      saturate(lerp(center.x, best.x, fill_strength));
}
)";

/** 光流补洞 Shader 常量按 16-byte 对齐。 */
struct FlowParameters {
  std::uint32_t width = 0;
  std::uint32_t height = 0;
  std::uint32_t grid = 0;
  std::uint32_t padding = 0;
};
static_assert(sizeof(FlowParameters) % 16 == 0);

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

/** 单个 Y/U/V 平面复用的输入、候选、最终输出和读回资源。 */
struct PlaneResources {
  int width = 0;
  int height = 0;
  ComPtr<ID3D11Texture2D> first;
  ComPtr<ID3D11Texture2D> second;
  ComPtr<ID3D11ShaderResourceView> first_view;
  ComPtr<ID3D11ShaderResourceView> second_view;
  ComPtr<ID3D11Texture2D> candidate;
  ComPtr<ID3D11ShaderResourceView> candidate_view;
  ComPtr<ID3D11UnorderedAccessView> candidate_output_view;
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
    candidate.Reset();
    candidate_view.Reset();
    candidate_output_view.Reset();
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

    /**
     * 三段 Shader 必须在同一固定适配器上创建；任一阶段失败都保持 QA
     * 插值关闭，不能静默退回 CPU 并掩盖 D3D11 互操作问题。
     */
    const auto create_shader =
        [this](const char* source, std::size_t source_size,
               const char* source_name,
               ID3D11ComputeShader** destination) -> bool {
      ComPtr<ID3DBlob> bytecode;
      ComPtr<ID3DBlob> compiler_error;
      if (FAILED(D3DCompile(
              source, source_size, source_name, nullptr, nullptr, "main",
              "cs_5_0", D3DCOMPILE_OPTIMIZATION_LEVEL3, 0,
              &bytecode, &compiler_error)) ||
          bytecode == nullptr) {
        return false;
      }
      return SUCCEEDED(device_->CreateComputeShader(
          bytecode->GetBufferPointer(), bytecode->GetBufferSize(),
          nullptr, destination));
    };
    if (!create_shader(
            kFlowInfillShader, sizeof(kFlowInfillShader) - 1,
            "ltp_nvofa_flow_infill.hlsl",
            flow_infill_shader_.GetAddressOf())) {
      return Fail("create-d3d11-flow-infill-shader");
    }
    if (!create_shader(
            kWarpShader, sizeof(kWarpShader) - 1,
            "ltp_nvofa_midpoint_warp.hlsl",
            warp_shader_.GetAddressOf())) {
      return Fail("create-d3d11-warp-shader");
    }
    if (!create_shader(
            kHoleFillShader, sizeof(kHoleFillShader) - 1,
            "ltp_nvofa_hole_fill.hlsl",
            hole_fill_shader_.GetAddressOf())) {
      return Fail("create-d3d11-hole-fill-shader");
    }

    D3D11_BUFFER_DESC constants{};
    constants.ByteWidth = sizeof(FlowParameters);
    constants.Usage = D3D11_USAGE_DEFAULT;
    constants.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    if (FAILED(device_->CreateBuffer(
            &constants, nullptr, &flow_constant_buffer_))) {
      return Fail("create-d3d11-flow-constants");
    }
    constants.ByteWidth = sizeof(WarpParameters);
    if (FAILED(device_->CreateBuffer(
            &constants, nullptr, &warp_constant_buffer_))) {
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
      const std::vector<std::uint8_t>& forward_cost,
      const std::vector<std::uint8_t>& backward_cost,
      std::uint32_t width,
      std::uint32_t height,
      std::uint32_t grid) {
    const std::size_t count =
        static_cast<std::size_t>(width) * height;
    if (device_ == nullptr || context_ == nullptr || width == 0 ||
        height == 0 || grid == 0 || forward.size() != count ||
        backward.size() != count || forward_cost.size() != count ||
        backward_cost.size() != count) {
      return Fail("invalid-d3d11-flow");
    }
    if (!EnsureFlowResources(width, height)) return false;
    const UINT row_pitch =
        width * static_cast<UINT>(sizeof(NV_OF_FLOW_VECTOR));
    context_->UpdateSubresource(
        forward_flow_.Get(), 0, nullptr, forward.data(), row_pitch, 0);
    context_->UpdateSubresource(
        backward_flow_.Get(), 0, nullptr, backward.data(), row_pitch, 0);
    context_->UpdateSubresource(
        forward_cost_.Get(), 0, nullptr, forward_cost.data(), width, 0);
    context_->UpdateSubresource(
        backward_cost_.Get(), 0, nullptr, backward_cost.data(), width, 0);

    FlowParameters parameters;
    parameters.width = width;
    parameters.height = height;
    parameters.grid = grid;
    context_->UpdateSubresource(
        flow_constant_buffer_.Get(), 0, nullptr, &parameters, 0, 0);
    ID3D11ShaderResourceView* views[] = {
        forward_flow_view_.Get(), backward_flow_view_.Get(),
        forward_cost_view_.Get(), backward_cost_view_.Get()};
    ID3D11UnorderedAccessView* outputs[] = {
        resolved_forward_output_view_.Get(),
        resolved_backward_output_view_.Get()};
    ID3D11Buffer* constants = flow_constant_buffer_.Get();
    context_->CSSetShader(flow_infill_shader_.Get(), nullptr, 0);
    context_->CSSetConstantBuffers(0, 1, &constants);
    context_->CSSetShaderResources(0, 4, views);
    context_->CSSetUnorderedAccessViews(0, 2, outputs, nullptr);
    context_->Dispatch((width + 15) / 16, (height + 15) / 16, 1);

    // 后续逐平面读取 resolved flow，必须先解除本阶段 UAV/SRV 绑定。
    std::array<ID3D11ShaderResourceView*, 4> empty_views{};
    std::array<ID3D11UnorderedAccessView*, 2> empty_outputs{};
    context_->CSSetShaderResources(0, 4, empty_views.data());
    context_->CSSetUnorderedAccessViews(
        0, 2, empty_outputs.data(), nullptr);
    context_->CSSetShader(nullptr, nullptr, 0);
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
        warp_constant_buffer_.Get(), 0, nullptr, &parameters, 0, 0);

    ID3D11ShaderResourceView* views[] = {
        plane.first_view.Get(), plane.second_view.Get(),
        resolved_forward_view_.Get(), resolved_backward_view_.Get()};
    ID3D11UnorderedAccessView* candidate_output =
        plane.candidate_output_view.Get();
    ID3D11Buffer* constants = warp_constant_buffer_.Get();
    context_->CSSetShader(warp_shader_.Get(), nullptr, 0);
    context_->CSSetConstantBuffers(0, 1, &constants);
    context_->CSSetShaderResources(0, 4, views);
    context_->CSSetUnorderedAccessViews(
        0, 1, &candidate_output, nullptr);
    context_->Dispatch(
        (static_cast<UINT>(width) + 15) / 16,
        (static_cast<UINT>(height) + 15) / 16, 1);

    // 图像域补洞需要把候选 UAV 改绑为 SRV，先显式解除写绑定。
    std::array<ID3D11ShaderResourceView*, 4> empty_views{};
    ID3D11UnorderedAccessView* empty_output = nullptr;
    context_->CSSetShaderResources(0, 4, empty_views.data());
    context_->CSSetUnorderedAccessViews(0, 1, &empty_output, nullptr);

    ID3D11ShaderResourceView* candidate_view =
        plane.candidate_view.Get();
    ID3D11UnorderedAccessView* final_output =
        plane.output_view.Get();
    context_->CSSetShader(hole_fill_shader_.Get(), nullptr, 0);
    context_->CSSetShaderResources(0, 1, &candidate_view);
    context_->CSSetUnorderedAccessViews(
        0, 1, &final_output, nullptr);
    context_->Dispatch(
        (static_cast<UINT>(width) + 15) / 16,
        (static_cast<UINT>(height) + 15) / 16, 1);

    // 解除最终阶段绑定后再复制到 staging，避免驱动延迟处理资源 hazard。
    ID3D11ShaderResourceView* empty_candidate = nullptr;
    context_->CSSetShaderResources(0, 1, &empty_candidate);
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

  /** 创建或复用 R16G16_SINT 光流、R8_UINT cost 纹理及 SRV。 */
  bool EnsureFlowResources(std::uint32_t width, std::uint32_t height) {
    if (forward_flow_ != nullptr && flow_resource_width_ == width &&
        flow_resource_height_ == height) {
      return true;
    }
    forward_flow_.Reset();
    backward_flow_.Reset();
    forward_flow_view_.Reset();
    backward_flow_view_.Reset();
    forward_cost_.Reset();
    backward_cost_.Reset();
    forward_cost_view_.Reset();
    backward_cost_view_.Reset();
    resolved_forward_.Reset();
    resolved_backward_.Reset();
    resolved_forward_view_.Reset();
    resolved_backward_view_.Reset();
    resolved_forward_output_view_.Reset();
    resolved_backward_output_view_.Reset();
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
    D3D11_TEXTURE2D_DESC cost = description;
    cost.Format = DXGI_FORMAT_R8_UINT;
    if (FAILED(device_->CreateTexture2D(
            &cost, nullptr, &forward_cost_)) ||
        FAILED(device_->CreateTexture2D(
            &cost, nullptr, &backward_cost_)) ||
        FAILED(device_->CreateShaderResourceView(
            forward_cost_.Get(), nullptr, &forward_cost_view_)) ||
        FAILED(device_->CreateShaderResourceView(
            backward_cost_.Get(), nullptr, &backward_cost_view_))) {
      return Fail("create-d3d11-cost-resources");
    }
    D3D11_TEXTURE2D_DESC resolved = description;
    resolved.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
    resolved.BindFlags =
        D3D11_BIND_SHADER_RESOURCE |
        D3D11_BIND_UNORDERED_ACCESS;
    if (FAILED(device_->CreateTexture2D(
            &resolved, nullptr, &resolved_forward_)) ||
        FAILED(device_->CreateTexture2D(
            &resolved, nullptr, &resolved_backward_)) ||
        FAILED(device_->CreateShaderResourceView(
            resolved_forward_.Get(), nullptr,
            &resolved_forward_view_)) ||
        FAILED(device_->CreateShaderResourceView(
            resolved_backward_.Get(), nullptr,
            &resolved_backward_view_)) ||
        FAILED(device_->CreateUnorderedAccessView(
            resolved_forward_.Get(), nullptr,
            &resolved_forward_output_view_)) ||
        FAILED(device_->CreateUnorderedAccessView(
            resolved_backward_.Get(), nullptr,
            &resolved_backward_output_view_))) {
      return Fail("create-d3d11-resolved-flow-resources");
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

    D3D11_TEXTURE2D_DESC candidate = input;
    candidate.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
    candidate.BindFlags =
        D3D11_BIND_SHADER_RESOURCE |
        D3D11_BIND_UNORDERED_ACCESS;
    if (FAILED(device_->CreateTexture2D(
            &candidate, nullptr, &plane->candidate)) ||
        FAILED(device_->CreateShaderResourceView(
            plane->candidate.Get(), nullptr,
            &plane->candidate_view)) ||
        FAILED(device_->CreateUnorderedAccessView(
            plane->candidate.Get(), nullptr,
            &plane->candidate_output_view))) {
      return Fail("create-d3d11-plane-candidate");
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
  ComPtr<ID3D11ComputeShader> flow_infill_shader_;
  ComPtr<ID3D11ComputeShader> warp_shader_;
  ComPtr<ID3D11ComputeShader> hole_fill_shader_;
  ComPtr<ID3D11Buffer> flow_constant_buffer_;
  ComPtr<ID3D11Buffer> warp_constant_buffer_;
  ComPtr<ID3D11Texture2D> forward_flow_;
  ComPtr<ID3D11Texture2D> backward_flow_;
  ComPtr<ID3D11ShaderResourceView> forward_flow_view_;
  ComPtr<ID3D11ShaderResourceView> backward_flow_view_;
  ComPtr<ID3D11Texture2D> forward_cost_;
  ComPtr<ID3D11Texture2D> backward_cost_;
  ComPtr<ID3D11ShaderResourceView> forward_cost_view_;
  ComPtr<ID3D11ShaderResourceView> backward_cost_view_;
  ComPtr<ID3D11Texture2D> resolved_forward_;
  ComPtr<ID3D11Texture2D> resolved_backward_;
  ComPtr<ID3D11ShaderResourceView> resolved_forward_view_;
  ComPtr<ID3D11ShaderResourceView> resolved_backward_view_;
  ComPtr<ID3D11UnorderedAccessView> resolved_forward_output_view_;
  ComPtr<ID3D11UnorderedAccessView> resolved_backward_output_view_;
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
    const std::vector<std::uint8_t>& forward_cost,
    const std::vector<std::uint8_t>& backward_cost,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t grid) {
  return impl_->PrepareFlow(
      forward, backward, forward_cost, backward_cost,
      width, height, grid);
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
