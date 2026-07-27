#include <windows.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <memory>
#include <numeric>
#include <string>
#include <vector>

#include "VapourSynth4.h"
#include "d3d11_midpoint_warper.h"
#include "nvOpticalFlowCuda.h"

namespace {

using CUresult = int;
constexpr CUresult kCudaSuccess = 0;

using CuInit = CUresult(WINAPI*)(unsigned int);
using CuDeviceGetCount = CUresult(WINAPI*)(int*);
using CuDeviceGet = CUresult(WINAPI*)(CUdevice*, int);
using CuDeviceGetLuid =
    CUresult(WINAPI*)(char*, unsigned int*, CUdevice);
using CuCtxCreate = CUresult(WINAPI*)(CUcontext*, unsigned int, CUdevice);
using CuCtxDestroy = CUresult(WINAPI*)(CUcontext);
using CuCtxPushCurrent = CUresult(WINAPI*)(CUcontext);
using CuCtxPopCurrent = CUresult(WINAPI*)(CUcontext*);
using CuCtxSynchronize = CUresult(WINAPI*)();
using CuMemcpyHtoD =
    CUresult(WINAPI*)(CUdeviceptr, const void*, std::size_t);
using CuMemcpyDtoH =
    CUresult(WINAPI*)(void*, CUdeviceptr, std::size_t);

using NvOfGetMaxSupportedApiVersion =
    NV_OF_STATUS(NVOFAPI*)(std::uint32_t*);
using NvOfApiCreateInstanceCuda =
    NV_OF_STATUS(NVOFAPI*)(std::uint32_t, NV_OF_CUDA_API_FUNCTION_LIST*);

/** 从已经按 SYSTEM32 边界加载的驱动模块解析强类型函数。 */
template <typename Function>
Function Resolve(HMODULE module, const char* name) {
  return reinterpret_cast<Function>(GetProcAddress(module, name));
}

/** NVOFA 产生的一对前向、后向 S10.5 光流。 */
struct BidirectionalFlow {
  std::uint32_t grid = 0;
  std::uint32_t width = 0;
  std::uint32_t height = 0;
  std::vector<NV_OF_FLOW_VECTOR> forward;
  std::vector<NV_OF_FLOW_VECTOR> backward;
  std::vector<std::uint8_t> forward_cost;
  std::vector<std::uint8_t> backward_cost;
};

/** CUDA 的 8-byte Windows LUID 与 DXGI 能力矩阵使用同一高/低位格式。 */
std::string CudaLuidString(const char* luid) {
  std::uint32_t low = 0;
  std::uint32_t high = 0;
  std::memcpy(&low, luid, sizeof(low));
  std::memcpy(&high, luid + sizeof(low), sizeof(high));
  std::array<char, 32> buffer{};
  std::snprintf(buffer.data(), buffer.size(), "%08x:%08x", high, low);
  return buffer.data();
}

/** 只接受 runner 能力矩阵输出的规范化 LUID，避免名称或枚举顺序回退。 */
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

/**
 * 单个 VapourSynth 滤镜实例拥有的 CUDA/NVOFA 会话。
 *
 * 只动态调用系统驱动，不链接 CUDA Toolkit，也不加载当前目录或 PATH 中的
 * 同名 DLL。VapourSynth 以 `fmParallelRequests` 串行调用实际处理阶段，因此
 * 一个会话可以安全复用 GPU 缓冲区。
 */
class NvidiaOpticalFlowEngine {
 public:
  NvidiaOpticalFlowEngine() = default;
  ~NvidiaOpticalFlowEngine() { Shutdown(); }

  NvidiaOpticalFlowEngine(const NvidiaOpticalFlowEngine&) = delete;
  NvidiaOpticalFlowEngine& operator=(const NvidiaOpticalFlowEngine&) = delete;

  /** 为固定尺寸 8-bit luma 建立硬件光流会话。 */
  bool Initialize(
      std::uint32_t width,
      std::uint32_t height,
      const std::string& expected_adapter_luid) {
    width_ = width;
    height_ = height;
    if (!IsNormalizedLuid(expected_adapter_luid)) {
      return Fail("invalid-d3d11-adapter-luid");
    }
    cuda_module_ = LoadLibraryExW(
        L"nvcuda.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    nvofa_module_ = LoadLibraryExW(
        L"nvofapi64.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (cuda_module_ == nullptr || nvofa_module_ == nullptr) {
      return Fail("load-system-driver");
    }

    cu_init_ = Resolve<CuInit>(cuda_module_, "cuInit");
    const auto cu_device_get_count =
        Resolve<CuDeviceGetCount>(cuda_module_, "cuDeviceGetCount");
    const auto cu_device_get =
        Resolve<CuDeviceGet>(cuda_module_, "cuDeviceGet");
    const auto cu_device_get_luid =
        Resolve<CuDeviceGetLuid>(cuda_module_, "cuDeviceGetLuid");
    const auto cu_ctx_create =
        Resolve<CuCtxCreate>(cuda_module_, "cuCtxCreate_v2");
    cu_ctx_destroy_ =
        Resolve<CuCtxDestroy>(cuda_module_, "cuCtxDestroy_v2");
    cu_ctx_push_current_ =
        Resolve<CuCtxPushCurrent>(cuda_module_, "cuCtxPushCurrent_v2");
    cu_ctx_pop_current_ =
        Resolve<CuCtxPopCurrent>(cuda_module_, "cuCtxPopCurrent_v2");
    cu_ctx_synchronize_ =
        Resolve<CuCtxSynchronize>(cuda_module_, "cuCtxSynchronize");
    cu_memcpy_h_to_d_ =
        Resolve<CuMemcpyHtoD>(cuda_module_, "cuMemcpyHtoD_v2");
    cu_memcpy_d_to_h_ =
        Resolve<CuMemcpyDtoH>(cuda_module_, "cuMemcpyDtoH_v2");
    if (cu_init_ == nullptr || cu_device_get_count == nullptr ||
        cu_device_get == nullptr || cu_device_get_luid == nullptr ||
        cu_ctx_create == nullptr ||
        cu_ctx_destroy_ == nullptr || cu_ctx_push_current_ == nullptr ||
        cu_ctx_pop_current_ == nullptr || cu_ctx_synchronize_ == nullptr ||
        cu_memcpy_h_to_d_ == nullptr || cu_memcpy_d_to_h_ == nullptr) {
      return Fail("resolve-cuda-driver-api");
    }

    int device_count = 0;
    CUdevice device = 0;
    if (cu_init_(0) != kCudaSuccess ||
        cu_device_get_count(&device_count) != kCudaSuccess ||
        device_count < 1) {
      return Fail("enumerate-cuda-device");
    }
    int matching_devices = 0;
    for (int index = 0; index < device_count; ++index) {
      CUdevice candidate = 0;
      std::array<char, 8> candidate_luid{};
      unsigned int node_mask = 0;
      if (cu_device_get(&candidate, index) != kCudaSuccess ||
          cu_device_get_luid(
              candidate_luid.data(), &node_mask, candidate) !=
              kCudaSuccess ||
          CudaLuidString(candidate_luid.data()) !=
              expected_adapter_luid) {
        continue;
      }
      device = candidate;
      cuda_device_index_ = index;
      ++matching_devices;
    }
    if (matching_devices != 1) {
      return Fail("match-cuda-device-by-d3d11-luid");
    }
    adapter_luid_ = expected_adapter_luid;
    if (cu_ctx_create(&cuda_context_, 0, device) != kCudaSuccess) {
      return Fail("create-cuda-context");
    }
    context_is_current_ = true;

    const auto get_max_api = Resolve<NvOfGetMaxSupportedApiVersion>(
        nvofa_module_, "NvOFGetMaxSupportedApiVersion");
    const auto create_instance = Resolve<NvOfApiCreateInstanceCuda>(
        nvofa_module_, "NvOFAPICreateInstanceCuda");
    std::uint32_t driver_max_api = 0;
    if (get_max_api == nullptr || create_instance == nullptr ||
        get_max_api(&driver_max_api) != NV_OF_SUCCESS ||
        driver_max_api < NV_OF_API_VERSION ||
        create_instance(NV_OF_API_VERSION, &api_) != NV_OF_SUCCESS) {
      return Fail("create-nvofa-api");
    }
    if (api_.nvCreateOpticalFlowCuda == nullptr ||
        api_.nvOFInit == nullptr ||
        api_.nvOFGetCaps == nullptr ||
        api_.nvOFCreateGPUBufferCuda == nullptr ||
        api_.nvOFGPUBufferGetCUdeviceptr == nullptr ||
        api_.nvOFGPUBufferGetStrideInfo == nullptr ||
        api_.nvOFExecute == nullptr ||
        api_.nvOFDestroyGPUBufferCuda == nullptr ||
        api_.nvOFDestroy == nullptr) {
      return Fail("validate-nvofa-functions");
    }
    if (api_.nvCreateOpticalFlowCuda(
            cuda_context_, &optical_flow_) != NV_OF_SUCCESS ||
        optical_flow_ == nullptr) {
      return Fail("create-nvofa-session");
    }

    std::uint32_t grid_count = 0;
    if (api_.nvOFGetCaps(
            optical_flow_, NV_OF_CAPS_SUPPORTED_OUTPUT_GRID_SIZES,
            nullptr, &grid_count) != NV_OF_SUCCESS ||
        grid_count == 0) {
      return Fail("query-output-grid-count");
    }
    std::vector<std::uint32_t> grids(grid_count);
    if (api_.nvOFGetCaps(
            optical_flow_, NV_OF_CAPS_SUPPORTED_OUTPUT_GRID_SIZES,
            grids.data(), &grid_count) != NV_OF_SUCCESS ||
        grid_count == 0) {
      return Fail("query-output-grids");
    }
    grids.resize(grid_count);
    grid_ = std::find(grids.begin(), grids.end(), 4U) != grids.end()
                ? 4U
                : grids.front();
    if (grid_ != 1 && grid_ != 2 && grid_ != 4) {
      return Fail("unsupported-output-grid");
    }

    NV_OF_INIT_PARAMS init{};
    init.width = width_;
    init.height = height_;
    init.outGridSize =
        static_cast<NV_OF_OUTPUT_VECTOR_GRID_SIZE>(grid_);
    init.mode = NV_OF_MODE_OPTICALFLOW;
    init.perfLevel = NV_OF_PERF_LEVEL_MEDIUM;
    init.enableExternalHints = NV_OF_FALSE;
    // 官方建议使用 8-bit cost；数值越高表示向量越不可靠，后续 Compute 会把
    // 它与前后向一致性共同用于遮挡保护。
    init.enableOutputCost = NV_OF_TRUE;
    init.disparityRange = NV_OF_STEREO_DISPARITY_RANGE_UNDEFINED;
    init.enableRoi = NV_OF_FALSE;
    if (api_.nvOFInit(optical_flow_, &init) != NV_OF_SUCCESS) {
      return Fail("initialize-nvofa-session");
    }

    output_width_ = (width_ + grid_ - 1) / grid_;
    output_height_ = (height_ + grid_ - 1) / grid_;
    if (!CreateBuffer(
            width_, height_, NV_OF_BUFFER_USAGE_INPUT,
            NV_OF_BUFFER_FORMAT_GRAYSCALE8, &input_) ||
        !CreateBuffer(
            width_, height_, NV_OF_BUFFER_USAGE_INPUT,
            NV_OF_BUFFER_FORMAT_GRAYSCALE8, &reference_) ||
        !CreateBuffer(
            output_width_, output_height_, NV_OF_BUFFER_USAGE_OUTPUT,
            NV_OF_BUFFER_FORMAT_SHORT2, &output_) ||
        !CreateBuffer(
            output_width_, output_height_, NV_OF_BUFFER_USAGE_COST,
            NV_OF_BUFFER_FORMAT_UINT8, &cost_)) {
      return Fail("create-nvofa-buffers");
    }

    // 创建阶段由 CUDA 自动把 context 压入当前线程；交还给驱动，后续每帧
    // 显式 push/pop，避免 VapourSynth 调度线程变化时使用错误 context。
    if (!PopContext()) return Fail("release-create-context");
    ready_ = true;
    error_.clear();
    return true;
  }

  /**
   * 对连续两帧执行 A→B 和 B→A 两次真实 NVOFA 计算。
   *
   * [first_stride]/[second_stride] 是 VapourSynth luma 每行字节数；输出保留
   * NVOFA 原始 S10.5 向量，warp 阶段再按色度平面比例换算。
   */
  bool Compute(
      const std::uint8_t* first,
      std::ptrdiff_t first_stride,
      const std::uint8_t* second,
      std::ptrdiff_t second_stride,
      BidirectionalFlow* flow) {
    if (!ready_ || first == nullptr || second == nullptr || flow == nullptr ||
        !PushContext()) {
      return Fail("prepare-frame-context");
    }
    bool success =
        UploadFrame(input_, first, first_stride) &&
        UploadFrame(reference_, second, second_stride) &&
        Execute(
            input_, reference_, &flow->forward,
            &flow->forward_cost) &&
        Execute(
            reference_, input_, &flow->backward,
            &flow->backward_cost);
    if (!PopContext()) success = false;
    if (!success) return Fail("execute-bidirectional-flow");
    flow->grid = grid_;
    flow->width = output_width_;
    flow->height = output_height_;
    return true;
  }

  /** 返回不含路径和驱动原文的稳定失败阶段。 */
  const std::string& error() const { return error_; }

  /** 返回与 mpv D3D11 选择精确匹配的 CUDA 设备索引，仅用于匿名 QA 属性。 */
  int cuda_device_index() const { return cuda_device_index_; }

 private:
  /** 标记稳定错误阶段。 */
  bool Fail(const char* stage) {
    error_ = stage;
    return false;
  }

  /** 创建 NVOFA 管理的 CUDA device-pointer 缓冲区。 */
  bool CreateBuffer(
      std::uint32_t width,
      std::uint32_t height,
      NV_OF_BUFFER_USAGE usage,
      NV_OF_BUFFER_FORMAT format,
      NvOFGPUBufferHandle* buffer) {
    NV_OF_BUFFER_DESCRIPTOR descriptor{};
    descriptor.width = width;
    descriptor.height = height;
    descriptor.bufferUsage = usage;
    descriptor.bufferFormat = format;
    return api_.nvOFCreateGPUBufferCuda(
               optical_flow_, &descriptor,
               NV_OF_CUDA_BUFFER_TYPE_CUDEVICEPTR, buffer) ==
           NV_OF_SUCCESS;
  }

  /** 将一帧 luma 按驱动 pitch 上传到 NVOFA 输入缓冲区。 */
  bool UploadFrame(
      NvOFGPUBufferHandle buffer,
      const std::uint8_t* source,
      std::ptrdiff_t source_stride) {
    const CUdeviceptr device_pointer =
        api_.nvOFGPUBufferGetCUdeviceptr(buffer);
    NV_OF_CUDA_BUFFER_STRIDE_INFO stride{};
    if (device_pointer == 0 || source_stride < width_ ||
        api_.nvOFGPUBufferGetStrideInfo(buffer, &stride) != NV_OF_SUCCESS ||
        stride.numPlanes != 1 ||
        stride.strideInfo[0].strideXInBytes < width_) {
      return false;
    }
    const std::size_t destination_stride =
        stride.strideInfo[0].strideXInBytes;
    for (std::uint32_t y = 0; y < height_; ++y) {
      if (cu_memcpy_h_to_d_(
              device_pointer + y * destination_stride,
              source + y * source_stride, width_) != kCudaSuccess) {
        return false;
      }
    }
    return true;
  }

  /** 执行一次单向硬件光流并按驱动 pitch 回读。 */
  bool Execute(
      NvOFGPUBufferHandle input,
      NvOFGPUBufferHandle reference,
      std::vector<NV_OF_FLOW_VECTOR>* flow,
      std::vector<std::uint8_t>* cost) {
    if (flow == nullptr || cost == nullptr) return false;
    NV_OF_EXECUTE_INPUT_PARAMS execute_input{};
    execute_input.inputFrame = input;
    execute_input.referenceFrame = reference;
    execute_input.disableTemporalHints = NV_OF_TRUE;
    NV_OF_EXECUTE_OUTPUT_PARAMS execute_output{};
    execute_output.outputBuffer = output_;
    execute_output.outputCostBuffer = cost_;
    if (api_.nvOFExecute(
            optical_flow_, &execute_input, &execute_output) != NV_OF_SUCCESS ||
        cu_ctx_synchronize_() != kCudaSuccess) {
      return false;
    }

    const CUdeviceptr device_pointer =
        api_.nvOFGPUBufferGetCUdeviceptr(output_);
    NV_OF_CUDA_BUFFER_STRIDE_INFO stride{};
    const std::size_t row_size =
        static_cast<std::size_t>(output_width_) *
        sizeof(NV_OF_FLOW_VECTOR);
    if (device_pointer == 0 ||
        api_.nvOFGPUBufferGetStrideInfo(output_, &stride) != NV_OF_SUCCESS ||
        stride.numPlanes != 1 ||
        stride.strideInfo[0].strideXInBytes < row_size) {
      return false;
    }
    flow->assign(
        static_cast<std::size_t>(output_width_) * output_height_, {});
    const std::size_t source_stride =
        stride.strideInfo[0].strideXInBytes;
    for (std::uint32_t y = 0; y < output_height_; ++y) {
      if (cu_memcpy_d_to_h_(
              flow->data() + y * output_width_,
              device_pointer + y * source_stride,
              row_size) != kCudaSuccess) {
        return false;
      }
    }
    const CUdeviceptr cost_pointer =
        api_.nvOFGPUBufferGetCUdeviceptr(cost_);
    NV_OF_CUDA_BUFFER_STRIDE_INFO cost_stride{};
    if (cost_pointer == 0 ||
        api_.nvOFGPUBufferGetStrideInfo(cost_, &cost_stride) !=
            NV_OF_SUCCESS ||
        cost_stride.numPlanes != 1 ||
        cost_stride.strideInfo[0].strideXInBytes < output_width_) {
      return false;
    }
    cost->assign(
        static_cast<std::size_t>(output_width_) * output_height_, 0);
    const std::size_t cost_source_stride =
        cost_stride.strideInfo[0].strideXInBytes;
    for (std::uint32_t y = 0; y < output_height_; ++y) {
      if (cu_memcpy_d_to_h_(
              cost->data() + y * output_width_,
              cost_pointer + y * cost_source_stride,
              output_width_) != kCudaSuccess) {
        return false;
      }
    }
    return true;
  }

  /** 把本实例的 CUDA context 压入当前 VapourSynth 调度线程。 */
  bool PushContext() {
    if (cuda_context_ == nullptr || cu_ctx_push_current_ == nullptr ||
        cu_ctx_push_current_(cuda_context_) != kCudaSuccess) {
      return false;
    }
    context_is_current_ = true;
    return true;
  }

  /** 从当前线程弹出 context，不依赖调用发生在哪个工作线程。 */
  bool PopContext() {
    if (!context_is_current_) return true;
    CUcontext popped = nullptr;
    if (cu_ctx_pop_current_ == nullptr ||
        cu_ctx_pop_current_(&popped) != kCudaSuccess ||
        popped != cuda_context_) {
      return false;
    }
    context_is_current_ = false;
    return true;
  }

  /** 按 GPU 资源、context、DLL 的逆序确定性释放。 */
  void Shutdown() {
    if (cuda_context_ != nullptr && !context_is_current_ &&
        cu_ctx_push_current_ != nullptr &&
        cu_ctx_push_current_(cuda_context_) == kCudaSuccess) {
      context_is_current_ = true;
    }
    if (api_.nvOFDestroyGPUBufferCuda != nullptr) {
      if (cost_ != nullptr) api_.nvOFDestroyGPUBufferCuda(cost_);
      if (output_ != nullptr) api_.nvOFDestroyGPUBufferCuda(output_);
      if (reference_ != nullptr) {
        api_.nvOFDestroyGPUBufferCuda(reference_);
      }
      if (input_ != nullptr) api_.nvOFDestroyGPUBufferCuda(input_);
    }
    cost_ = nullptr;
    output_ = nullptr;
    reference_ = nullptr;
    input_ = nullptr;
    if (optical_flow_ != nullptr && api_.nvOFDestroy != nullptr) {
      api_.nvOFDestroy(optical_flow_);
    }
    optical_flow_ = nullptr;
    if (context_is_current_) PopContext();
    if (cuda_context_ != nullptr && cu_ctx_destroy_ != nullptr) {
      cu_ctx_destroy_(cuda_context_);
    }
    cuda_context_ = nullptr;
    if (nvofa_module_ != nullptr) FreeLibrary(nvofa_module_);
    if (cuda_module_ != nullptr) FreeLibrary(cuda_module_);
    nvofa_module_ = nullptr;
    cuda_module_ = nullptr;
    ready_ = false;
  }

  HMODULE cuda_module_ = nullptr;
  HMODULE nvofa_module_ = nullptr;
  CuInit cu_init_ = nullptr;
  CuCtxDestroy cu_ctx_destroy_ = nullptr;
  CuCtxPushCurrent cu_ctx_push_current_ = nullptr;
  CuCtxPopCurrent cu_ctx_pop_current_ = nullptr;
  CuCtxSynchronize cu_ctx_synchronize_ = nullptr;
  CuMemcpyHtoD cu_memcpy_h_to_d_ = nullptr;
  CuMemcpyDtoH cu_memcpy_d_to_h_ = nullptr;
  CUcontext cuda_context_ = nullptr;
  bool context_is_current_ = false;
  NV_OF_CUDA_API_FUNCTION_LIST api_{};
  NvOFHandle optical_flow_ = nullptr;
  NvOFGPUBufferHandle input_ = nullptr;
  NvOFGPUBufferHandle reference_ = nullptr;
  NvOFGPUBufferHandle output_ = nullptr;
  NvOFGPUBufferHandle cost_ = nullptr;
  std::uint32_t width_ = 0;
  std::uint32_t height_ = 0;
  std::uint32_t grid_ = 0;
  std::uint32_t output_width_ = 0;
  std::uint32_t output_height_ = 0;
  bool ready_ = false;
  int cuda_device_index_ = -1;
  std::string adapter_luid_;
  std::string error_;
};

/** VapourSynth 节点和其唯一的 NVOFA 会话。 */
struct InterpolationData {
  VSNode* node = nullptr;
  VSVideoInfo input_info{};
  VSVideoInfo output_info{};
  double scene_threshold = 24.0;
  NvidiaOpticalFlowEngine engine;
  D3D11MidpointWarper warper;
};

/** 估算全帧 luma 差异；明显切镜时禁止生成跨场景鬼影。 */
double MeanLumaDifference(
    const VSFrame* first,
    const VSFrame* second,
    const VSAPI* vsapi) {
  const auto* first_ptr = vsapi->getReadPtr(first, 0);
  const auto* second_ptr = vsapi->getReadPtr(second, 0);
  const std::ptrdiff_t first_stride = vsapi->getStride(first, 0);
  const std::ptrdiff_t second_stride = vsapi->getStride(second, 0);
  const int width = vsapi->getFrameWidth(first, 0);
  const int height = vsapi->getFrameHeight(first, 0);
  std::uint64_t difference = 0;
  std::uint64_t samples = 0;
  for (int y = 0; y < height; y += 4) {
    for (int x = 0; x < width; x += 4) {
      difference += static_cast<std::uint64_t>(
          std::abs(
              static_cast<int>(first_ptr[y * first_stride + x]) -
              static_cast<int>(second_ptr[y * second_stride + x])));
      ++samples;
    }
  }
  return samples == 0
             ? std::numeric_limits<double>::infinity()
             : static_cast<double>(difference) /
                   static_cast<double>(samples);
}

/**
 * 用前后向 NVOFA 光流把两帧各 warp 到 0.5 时间点并融合。
 *
 * NVOFA 仍通过 CUDA 会话输出原始 S10.5 光流；逐像素采样和融合迁移到同一
 * LUID 的 D3D11 Compute。VapourSynth 当前只提供软件帧，所以输入上传和最终
 * 平面读回仍存在，不能把这条原型描述为零复制。
 */
bool WarpMidpoint(
    const VSFrame* first,
    const VSFrame* second,
    VSFrame* destination,
    const BidirectionalFlow& flow,
    D3D11MidpointWarper* warper,
    const VSAPI* vsapi) {
  if (warper == nullptr ||
      !warper->PrepareFlow(
          flow.forward, flow.backward, flow.forward_cost,
          flow.backward_cost, flow.width, flow.height, flow.grid)) {
    return false;
  }
  const int luma_width = vsapi->getFrameWidth(first, 0);
  const int luma_height = vsapi->getFrameHeight(first, 0);
  const auto* format = vsapi->getVideoFrameFormat(first);
  for (int plane = 0; plane < format->numPlanes; ++plane) {
    const int width = vsapi->getFrameWidth(first, plane);
    const int height = vsapi->getFrameHeight(first, plane);
    if (!warper->WarpPlane(
            plane, vsapi->getReadPtr(first, plane),
            vsapi->getStride(first, plane),
            vsapi->getReadPtr(second, plane),
            vsapi->getStride(second, plane),
            vsapi->getWritePtr(destination, plane),
            vsapi->getStride(destination, plane), width, height,
            luma_width, luma_height)) {
      return false;
    }
  }
  return true;
}

/** 写入输出帧率对应的时长和匿名运行证据。 */
void SetOutputProperties(
    VSFrame* frame,
    const InterpolationData* data,
    bool interpolated,
    bool scene_cut,
    std::int64_t process_microseconds,
    const VSAPI* vsapi) {
  VSMap* properties = vsapi->getFramePropertiesRW(frame);
  vsapi->mapSetInt(
      properties, "_DurationNum", data->output_info.fpsDen, maReplace);
  vsapi->mapSetInt(
      properties, "_DurationDen", data->output_info.fpsNum, maReplace);
  vsapi->mapSetInt(
      properties, "LTPNVOFAInterpolated", interpolated ? 1 : 0,
      maReplace);
  vsapi->mapSetInt(
      properties, "LTPNVOFASceneCut", scene_cut ? 1 : 0, maReplace);
  vsapi->mapSetInt(
      properties, "LTPNVOFAProcessUs", process_microseconds, maReplace);
  vsapi->mapSetInt(
      properties, "LTPNVOFAAdapterMatched", 1, maReplace);
  vsapi->mapSetInt(
      properties, "LTPNVOFACudaDeviceIndex",
      data->engine.cuda_device_index(), maReplace);
  vsapi->mapSetInt(
      properties, "LTPNVOFAD3D11Warp", 1, maReplace);
  vsapi->mapSetInt(
      properties, "LTPNVOFAConsistencyProtected", 1, maReplace);
}

/** VapourSynth 请求输出帧；偶数帧保留源帧，奇数帧生成 0.5 中间帧。 */
const VSFrame* VS_CC InterpolationGetFrame(
    int n,
    int activation_reason,
    void* instance_data,
    void** frame_data,
    VSFrameContext* frame_context,
    VSCore* core,
    const VSAPI* vsapi) {
  auto* data = static_cast<InterpolationData*>(instance_data);
  const int source_index = n / 2;
  const bool interpolated = (n % 2) != 0;
  if (activation_reason == arInitial) {
    vsapi->requestFrameFilter(source_index, data->node, frame_context);
    if (interpolated) {
      vsapi->requestFrameFilter(
          source_index + 1, data->node, frame_context);
    }
    return nullptr;
  }
  if (activation_reason != arAllFramesReady) return nullptr;

  const VSFrame* first =
      vsapi->getFrameFilter(source_index, data->node, frame_context);
  if (!interpolated) {
    VSFrame* output = vsapi->copyFrame(first, core);
    SetOutputProperties(output, data, false, false, 0, vsapi);
    vsapi->freeFrame(first);
    return output;
  }
  const VSFrame* second =
      vsapi->getFrameFilter(source_index + 1, data->node, frame_context);
  const double difference = MeanLumaDifference(first, second, vsapi);
  const bool scene_cut = difference >= data->scene_threshold;
  const auto started = std::chrono::steady_clock::now();
  VSFrame* output = vsapi->newVideoFrame(
      vsapi->getVideoFrameFormat(first),
      vsapi->getFrameWidth(first, 0),
      vsapi->getFrameHeight(first, 0), first, core);

  if (scene_cut) {
    const auto* format = vsapi->getVideoFrameFormat(first);
    for (int plane = 0; plane < format->numPlanes; ++plane) {
      const auto* source = vsapi->getReadPtr(first, plane);
      auto* destination = vsapi->getWritePtr(output, plane);
      const auto source_stride = vsapi->getStride(first, plane);
      const auto destination_stride = vsapi->getStride(output, plane);
      const int width = vsapi->getFrameWidth(first, plane);
      const int height = vsapi->getFrameHeight(first, plane);
      for (int y = 0; y < height; ++y) {
        std::copy_n(
            source + y * source_stride, width,
            destination + y * destination_stride);
      }
    }
  } else {
    BidirectionalFlow flow;
    if (!data->engine.Compute(
            vsapi->getReadPtr(first, 0), vsapi->getStride(first, 0),
            vsapi->getReadPtr(second, 0), vsapi->getStride(second, 0),
            &flow)) {
      const std::string message =
          "LTP NVOFA interpolation failed: " + data->engine.error();
      vsapi->setFilterError(message.c_str(), frame_context);
      vsapi->freeFrame(output);
      vsapi->freeFrame(second);
      vsapi->freeFrame(first);
      return nullptr;
    }
    if (!WarpMidpoint(
            first, second, output, flow, &data->warper, vsapi)) {
      const std::string message =
          "LTP NVOFA D3D11 warp failed: " + data->warper.error();
      vsapi->setFilterError(message.c_str(), frame_context);
      vsapi->freeFrame(output);
      vsapi->freeFrame(second);
      vsapi->freeFrame(first);
      return nullptr;
    }
  }
  const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
      std::chrono::steady_clock::now() - started);
  SetOutputProperties(
      output, data, true, scene_cut, elapsed.count(), vsapi);
  vsapi->freeFrame(second);
  vsapi->freeFrame(first);
  return output;
}

/** 释放节点后由成员析构确定性销毁 CUDA/NVOFA 会话。 */
void VS_CC InterpolationFree(
    void* instance_data,
    VSCore* core,
    const VSAPI* vsapi) {
  auto* data = static_cast<InterpolationData*>(instance_data);
  vsapi->freeNode(data->node);
  delete data;
}

/** 验证固定 8-bit planar 输入并建立 2× FPS 输出节点。 */
void VS_CC InterpolationCreate(
    const VSMap* input,
    VSMap* output,
    void* user_data,
    VSCore* core,
    const VSAPI* vsapi) {
  std::unique_ptr<InterpolationData> data(
      new InterpolationData());
  int error = 0;
  data->node = vsapi->mapGetNode(input, "clip", 0, &error);
  if (error || data->node == nullptr) {
    vsapi->mapSetError(output, "NVOFAInterpolate: clip is required");
    return;
  }
  data->input_info = *vsapi->getVideoInfo(data->node);
  const auto& format = data->input_info.format;
  if (data->input_info.width <= 0 || data->input_info.height <= 0 ||
      data->input_info.numFrames < 2 ||
      format.sampleType != stInteger || format.bitsPerSample != 8 ||
      format.bytesPerSample != 1 ||
      (format.colorFamily != cfYUV && format.colorFamily != cfGray)) {
    vsapi->mapSetError(
        output,
        "NVOFAInterpolate: constant 8-bit planar YUV/Gray input with "
        "at least two frames is required");
    vsapi->freeNode(data->node);
    data->node = nullptr;
    return;
  }
  const std::int64_t source_fps_num =
      vsapi->mapGetInt(input, "source_fps_num", 0, &error);
  if (error) {
    vsapi->mapSetError(
        output, "NVOFAInterpolate: source_fps_num is required");
    vsapi->freeNode(data->node);
    data->node = nullptr;
    return;
  }
  const std::int64_t source_fps_den =
      vsapi->mapGetInt(input, "source_fps_den", 0, &error);
  if (error || source_fps_num <= 0 || source_fps_den <= 0) {
    vsapi->mapSetError(
        output, "NVOFAInterpolate: a positive source FPS is required");
    vsapi->freeNode(data->node);
    data->node = nullptr;
    return;
  }
  const char* adapter_luid_data =
      vsapi->mapGetData(input, "adapter_luid", 0, &error);
  const int adapter_luid_size =
      error ? 0 : vsapi->mapGetDataSize(input, "adapter_luid", 0, &error);
  const std::string adapter_luid =
      error || adapter_luid_data == nullptr || adapter_luid_size <= 0
          ? std::string()
          : std::string(
                adapter_luid_data,
                static_cast<std::size_t>(adapter_luid_size));
  if (error || !IsNormalizedLuid(adapter_luid)) {
    vsapi->mapSetError(
        output,
        "NVOFAInterpolate: normalized D3D11 adapter LUID is required");
    vsapi->freeNode(data->node);
    data->node = nullptr;
    return;
  }
  data->scene_threshold =
      vsapi->mapGetFloat(input, "scene_threshold", 0, &error);
  if (error) data->scene_threshold = 24.0;
  if (!std::isfinite(data->scene_threshold) ||
      data->scene_threshold < 1.0 ||
      data->scene_threshold > 255.0) {
    vsapi->mapSetError(
        output,
        "NVOFAInterpolate: scene_threshold must be between 1 and 255");
    vsapi->freeNode(data->node);
    data->node = nullptr;
    return;
  }
  const std::int64_t source_fps_gcd =
      std::gcd(source_fps_num, source_fps_den);
  const std::int64_t normalized_fps_num =
      source_fps_num / source_fps_gcd;
  const std::int64_t normalized_fps_den =
      source_fps_den / source_fps_gcd;
  if (normalized_fps_num >
      std::numeric_limits<std::int64_t>::max() / 2) {
    vsapi->mapSetError(output, "NVOFAInterpolate: output timeline overflow");
    vsapi->freeNode(data->node);
    data->node = nullptr;
    return;
  }

  data->output_info = data->input_info;
  const std::int64_t doubled_fps_num = normalized_fps_num * 2;
  const std::int64_t output_fps_gcd =
      std::gcd(doubled_fps_num, normalized_fps_den);
  data->output_info.fpsNum = doubled_fps_num / output_fps_gcd;
  data->output_info.fpsDen = normalized_fps_den / output_fps_gcd;
  constexpr int kMpvUnknownFrameSentinel =
      std::numeric_limits<int>::max() / 16;
  // mpv 用 INT_MAX/16 表示实时/可 seek 的未知长度输入。该 sentinel 不能翻倍，
  // 否则 VapourSynth 会判定 VSVideoInfo 非法；保留它仍足以覆盖真实播放长度。
  data->output_info.numFrames =
      data->input_info.numFrames >= kMpvUnknownFrameSentinel
          ? data->input_info.numFrames
          : data->input_info.numFrames * 2 - 1;
  if (!data->engine.Initialize(
          static_cast<std::uint32_t>(data->input_info.width),
          static_cast<std::uint32_t>(data->input_info.height),
          adapter_luid)) {
    const std::string message =
        "NVOFAInterpolate: hardware initialization failed: " +
        data->engine.error();
    vsapi->mapSetError(output, message.c_str());
    vsapi->freeNode(data->node);
    data->node = nullptr;
    return;
  }
  if (!data->warper.Initialize(adapter_luid)) {
    const std::string message =
        "NVOFAInterpolate: D3D11 warp initialization failed: " +
        data->warper.error();
    vsapi->mapSetError(output, message.c_str());
    vsapi->freeNode(data->node);
    data->node = nullptr;
    return;
  }

  const VSFilterDependency dependencies[] = {
      {data->node, rpGeneral},
  };
  vsapi->createVideoFilter(
      output, "NVOFAInterpolate", &data->output_info,
      InterpolationGetFrame, InterpolationFree, fmParallelRequests,
      dependencies, 1, data.get(), core);
  data.release();
}

}  // namespace

/**
 * 注册本机 NVOFA 2× 插帧滤镜。
 *
 * 插件本身不携带 NVIDIA 头文件或运行库；只有显式 QA/本机原型构建才生成 DLL，
 * 标准 Flutter bundle 没有 install 规则。
 */
VS_EXTERNAL_API(void)
VapourSynthPluginInit2(
    VSPlugin* plugin,
    const VSPLUGINAPI* plugin_api) {
  plugin_api->configPlugin(
      "localtagplayer.nvofa.interpolation", "ltp_nvofa",
      "Local Tag Player NVIDIA Optical Flow Interpolation",
      VS_MAKE_VERSION(0, 1), VAPOURSYNTH_API_VERSION, 0, plugin);
  plugin_api->registerFunction(
      "Interpolate",
      "clip:vnode;source_fps_num:int;source_fps_den:int;adapter_luid:data;"
      "scene_threshold:float:opt;",
      "clip:vnode;",
      InterpolationCreate, nullptr, plugin);
}
