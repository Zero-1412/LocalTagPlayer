#include "gpu_compute_frame_budget.h"

#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi1_2.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <string>
#include <thread>
#include <vector>

namespace {
using Microsoft::WRL::ComPtr;

constexpr char kDetectionSource[] =
    "d3d11-timestamp-query-hdr-compute-kernel";
constexpr double kTargetFrameRate = 60.0;
constexpr double kFrameBudgetMs = 1000.0 / kTargetFrameRate;
constexpr double kComputeSliceRatio = 0.25;
constexpr double kComputeSliceMs = kFrameBudgetMs * kComputeSliceRatio;

/** 与 HDR 动态映射相近的逐像素曲线，仅用于测量 Compute 余量，不写回播放器纹理。 */
constexpr char kShaderSource[] = R"(
RWTexture2D<float4> output_texture : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
  uint width;
  uint height;
  output_texture.GetDimensions(width, height);
  if (id.x >= width || id.y >= height) return;
  float2 uv = (float2(id.xy) + 0.5) / float2(width, height);
  float3 color = float3(uv.x * 4.0, uv.y * 3.0, (uv.x + uv.y) * 2.0);
  const float A = 0.15;
  const float B = 0.50;
  const float C = 0.10;
  const float D = 0.20;
  const float E = 0.02;
  const float F = 0.30;
  float3 mapped = ((color * (A * color + C * B) + D * E) /
                   (color * (A * color + B) + D * F)) - E / F;
  output_texture[id.xy] = float4(saturate(mapped), 1.0);
}
)";

flutter::EncodableMap FailedResult(const std::string& luid,
                                   const char* error_code) {
  return flutter::EncodableMap{
      {flutter::EncodableValue("probeStatus"),
       flutter::EncodableValue("failed")},
      {flutter::EncodableValue("adapterLuid"), flutter::EncodableValue(luid)},
      {flutter::EncodableValue("detectionSource"),
       flutter::EncodableValue(kDetectionSource)},
      {flutter::EncodableValue("errorCode"),
       flutter::EncodableValue(error_code)},
      {flutter::EncodableValue("samples"),
       flutter::EncodableValue(flutter::EncodableList{})}};
}

bool ParseLuid(const std::string& value, LUID* luid) {
  if (luid == nullptr) return false;
  uint32_t high = 0;
  uint32_t low = 0;
  if (sscanf_s(value.c_str(), "%8x:%8x", &high, &low) != 2) return false;
  luid->HighPart = static_cast<LONG>(high);
  luid->LowPart = low;
  return true;
}

bool SameLuid(const LUID& left, const LUID& right) {
  return left.HighPart == right.HighPart && left.LowPart == right.LowPart;
}

/** 等待一次 GPU 时间戳查询完成；超时立即失败，避免驱动异常拖住 QA。 */
bool WaitForQuery(ID3D11DeviceContext* context, ID3D11Query* query, void* data,
                  UINT data_size) {
  const auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::seconds(5);
  while (std::chrono::steady_clock::now() < deadline) {
    const HRESULT result = context->GetData(
        query, data, data_size, D3D11_ASYNC_GETDATA_DONOTFLUSH);
    if (result == S_OK) return true;
    if (FAILED(result)) return false;
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  return false;
}

bool MeasureDispatch(ID3D11Device* device, ID3D11DeviceContext* context,
                     ID3D11ComputeShader* shader, uint32_t width,
                     uint32_t height, double* elapsed_ms) {
  D3D11_TEXTURE2D_DESC texture_description{};
  texture_description.Width = width;
  texture_description.Height = height;
  texture_description.MipLevels = 1;
  texture_description.ArraySize = 1;
  texture_description.Format = DXGI_FORMAT_R16G16B16A16_FLOAT;
  texture_description.SampleDesc.Count = 1;
  texture_description.Usage = D3D11_USAGE_DEFAULT;
  texture_description.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
  ComPtr<ID3D11Texture2D> texture;
  if (FAILED(device->CreateTexture2D(&texture_description, nullptr, &texture))) {
    return false;
  }

  ComPtr<ID3D11UnorderedAccessView> unordered_access;
  if (FAILED(device->CreateUnorderedAccessView(texture.Get(), nullptr,
                                                &unordered_access))) {
    return false;
  }

  D3D11_QUERY_DESC disjoint_description{D3D11_QUERY_TIMESTAMP_DISJOINT, 0};
  D3D11_QUERY_DESC timestamp_description{D3D11_QUERY_TIMESTAMP, 0};
  ComPtr<ID3D11Query> disjoint;
  ComPtr<ID3D11Query> start;
  ComPtr<ID3D11Query> end;
  if (FAILED(device->CreateQuery(&disjoint_description, &disjoint)) ||
      FAILED(device->CreateQuery(&timestamp_description, &start)) ||
      FAILED(device->CreateQuery(&timestamp_description, &end))) {
    return false;
  }

  context->Begin(disjoint.Get());
  context->End(start.Get());
  ID3D11UnorderedAccessView* views[] = {unordered_access.Get()};
  context->CSSetShader(shader, nullptr, 0);
  context->CSSetUnorderedAccessViews(0, 1, views, nullptr);
  context->Dispatch((width + 7) / 8, (height + 7) / 8, 1);
  ID3D11UnorderedAccessView* empty_views[] = {nullptr};
  context->CSSetUnorderedAccessViews(0, 1, empty_views, nullptr);
  context->End(end.Get());
  context->End(disjoint.Get());
  context->Flush();

  D3D11_QUERY_DATA_TIMESTAMP_DISJOINT disjoint_data{};
  uint64_t start_ticks = 0;
  uint64_t end_ticks = 0;
  if (!WaitForQuery(context, disjoint.Get(), &disjoint_data,
                    sizeof(disjoint_data)) ||
      !WaitForQuery(context, start.Get(), &start_ticks, sizeof(start_ticks)) ||
      !WaitForQuery(context, end.Get(), &end_ticks, sizeof(end_ticks)) ||
      disjoint_data.Disjoint || disjoint_data.Frequency == 0 ||
      end_ticks < start_ticks) {
    return false;
  }
  *elapsed_ms = static_cast<double>(end_ticks - start_ticks) * 1000.0 /
                static_cast<double>(disjoint_data.Frequency);
  return true;
}

flutter::EncodableMap MeasureResolution(ID3D11Device* device,
                                        ID3D11DeviceContext* context,
                                        ID3D11ComputeShader* shader,
                                        uint32_t width, uint32_t height) {
  constexpr int kWarmupCount = 3;
  constexpr int kSampleCount = 16;
  for (int index = 0; index < kWarmupCount; ++index) {
    double ignored = 0;
    if (!MeasureDispatch(device, context, shader, width, height, &ignored)) {
      return flutter::EncodableMap{
          {flutter::EncodableValue("width"),
           flutter::EncodableValue(static_cast<int64_t>(width))},
          {flutter::EncodableValue("height"),
           flutter::EncodableValue(static_cast<int64_t>(height))},
          {flutter::EncodableValue("probeStatus"),
           flutter::EncodableValue("failed")},
          {flutter::EncodableValue("errorCode"),
           flutter::EncodableValue("warmup-query-failed")}};
    }
  }

  std::vector<double> samples;
  samples.reserve(kSampleCount);
  for (int index = 0; index < kSampleCount; ++index) {
    double elapsed = 0;
    if (!MeasureDispatch(device, context, shader, width, height, &elapsed)) {
      return flutter::EncodableMap{
          {flutter::EncodableValue("width"),
           flutter::EncodableValue(static_cast<int64_t>(width))},
          {flutter::EncodableValue("height"),
           flutter::EncodableValue(static_cast<int64_t>(height))},
          {flutter::EncodableValue("probeStatus"),
           flutter::EncodableValue("failed")},
          {flutter::EncodableValue("errorCode"),
           flutter::EncodableValue("timestamp-query-failed")}};
    }
    samples.push_back(elapsed);
  }

  std::sort(samples.begin(), samples.end());
  const double median = (samples[7] + samples[8]) / 2.0;
  const size_t p95_index = static_cast<size_t>(
      std::ceil(samples.size() * 0.95) - 1.0);
  const double p95 = samples[std::min(p95_index, samples.size() - 1)];
  return flutter::EncodableMap{
      {flutter::EncodableValue("width"),
       flutter::EncodableValue(static_cast<int64_t>(width))},
      {flutter::EncodableValue("height"),
       flutter::EncodableValue(static_cast<int64_t>(height))},
      {flutter::EncodableValue("probeStatus"),
       flutter::EncodableValue("ready")},
      {flutter::EncodableValue("sampleCount"),
       flutter::EncodableValue(static_cast<int64_t>(samples.size()))},
      {flutter::EncodableValue("medianGpuMs"),
       flutter::EncodableValue(median)},
      {flutter::EncodableValue("p95GpuMs"), flutter::EncodableValue(p95)},
      {flutter::EncodableValue("maxGpuMs"),
       flutter::EncodableValue(samples.back())},
      {flutter::EncodableValue("frameBudgetMs"),
       flutter::EncodableValue(kFrameBudgetMs)},
      {flutter::EncodableValue("computeSliceMs"),
       flutter::EncodableValue(kComputeSliceMs)},
      {flutter::EncodableValue("p95WithinComputeSlice"),
       flutter::EncodableValue(p95 <= kComputeSliceMs)}};
}
}  // namespace

flutter::EncodableMap QueryGpuComputeFrameBudget(
    const std::string& adapter_luid) {
  LUID requested_luid{};
  if (!ParseLuid(adapter_luid, &requested_luid)) {
    return FailedResult(adapter_luid, "invalid-adapter-luid");
  }

  ComPtr<IDXGIFactory1> factory;
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) {
    return FailedResult(adapter_luid, "dxgi-factory-failed");
  }
  ComPtr<IDXGIAdapter1> selected_adapter;
  for (UINT index = 0;; ++index) {
    ComPtr<IDXGIAdapter1> candidate;
    const HRESULT result = factory->EnumAdapters1(index, &candidate);
    if (result == DXGI_ERROR_NOT_FOUND) break;
    if (FAILED(result)) break;
    DXGI_ADAPTER_DESC1 description{};
    if (SUCCEEDED(candidate->GetDesc1(&description)) &&
        SameLuid(description.AdapterLuid, requested_luid)) {
      selected_adapter = candidate;
      break;
    }
  }
  if (selected_adapter == nullptr) {
    return FailedResult(adapter_luid, "adapter-not-found");
  }

  constexpr std::array<D3D_FEATURE_LEVEL, 4> feature_levels{
      D3D_FEATURE_LEVEL_12_1, D3D_FEATURE_LEVEL_12_0,
      D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0};
  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  D3D_FEATURE_LEVEL selected_level = D3D_FEATURE_LEVEL_11_0;
  HRESULT device_result = D3D11CreateDevice(
      selected_adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr,
      D3D11_CREATE_DEVICE_BGRA_SUPPORT, feature_levels.data(),
      static_cast<UINT>(feature_levels.size()), D3D11_SDK_VERSION, &device,
      &selected_level, &context);
  if (device_result == E_INVALIDARG) {
    device_result = D3D11CreateDevice(
        selected_adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT, feature_levels.data() + 3, 1,
        D3D11_SDK_VERSION, &device, &selected_level, &context);
  }
  if (FAILED(device_result) || device == nullptr || context == nullptr ||
      selected_level < D3D_FEATURE_LEVEL_11_0) {
    return FailedResult(adapter_luid, "compute-device-failed");
  }

  ComPtr<ID3DBlob> bytecode;
  ComPtr<ID3DBlob> compiler_error;
  if (FAILED(D3DCompile(kShaderSource, sizeof(kShaderSource) - 1,
                        "ltp_hdr_budget.hlsl", nullptr, nullptr, "main",
                        "cs_5_0", D3DCOMPILE_OPTIMIZATION_LEVEL3, 0,
                        &bytecode, &compiler_error)) ||
      bytecode == nullptr) {
    return FailedResult(adapter_luid, "shader-compile-failed");
  }
  ComPtr<ID3D11ComputeShader> shader;
  if (FAILED(device->CreateComputeShader(bytecode->GetBufferPointer(),
                                          bytecode->GetBufferSize(), nullptr,
                                          &shader))) {
    return FailedResult(adapter_luid, "shader-create-failed");
  }

  flutter::EncodableList samples;
  samples.emplace_back(MeasureResolution(device.Get(), context.Get(),
                                         shader.Get(), 1920, 1080));
  samples.emplace_back(MeasureResolution(device.Get(), context.Get(),
                                         shader.Get(), 3840, 2160));
  bool ready = true;
  for (const auto& item : samples) {
    const auto* values = std::get_if<flutter::EncodableMap>(&item);
    if (values == nullptr) {
      ready = false;
      continue;
    }
    const auto status = values->find(flutter::EncodableValue("probeStatus"));
    if (status == values->end() ||
        std::get_if<std::string>(&status->second) == nullptr ||
        *std::get_if<std::string>(&status->second) != "ready") {
      ready = false;
    }
  }

  return flutter::EncodableMap{
      {flutter::EncodableValue("probeStatus"),
       flutter::EncodableValue(ready ? "ready" : "failed")},
      {flutter::EncodableValue("adapterLuid"),
       flutter::EncodableValue(adapter_luid)},
      {flutter::EncodableValue("detectionSource"),
       flutter::EncodableValue(kDetectionSource)},
      {flutter::EncodableValue("targetFrameRate"),
       flutter::EncodableValue(kTargetFrameRate)},
      {flutter::EncodableValue("computeSliceRatio"),
       flutter::EncodableValue(kComputeSliceRatio)},
      {flutter::EncodableValue("samples"),
       flutter::EncodableValue(std::move(samples))}};
}
