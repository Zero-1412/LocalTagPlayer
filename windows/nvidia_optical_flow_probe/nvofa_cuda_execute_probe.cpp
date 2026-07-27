#include <windows.h>

#include <algorithm>
#include <array>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

#include "d3d11_adapter_selector.h"
#include "nvOpticalFlowCuda.h"

namespace {

using CUresult = int;
constexpr CUresult kCudaSuccess = 0;

using CuInit = CUresult(WINAPI*)(unsigned int);
using CuDeviceGetCount = CUresult(WINAPI*)(int*);
using CuDeviceGet = CUresult(WINAPI*)(CUdevice*, int);
using CuDeviceGetName = CUresult(WINAPI*)(char*, int, CUdevice);
using CuDeviceGetLuid =
    CUresult(WINAPI*)(char*, unsigned int*, CUdevice);
using CuCtxCreate = CUresult(WINAPI*)(CUcontext*, unsigned int, CUdevice);
using CuCtxDestroy = CUresult(WINAPI*)(CUcontext);
using CuCtxSynchronize = CUresult(WINAPI*)();
using CuMemcpyHtoD =
    CUresult(WINAPI*)(CUdeviceptr, const void*, std::size_t);
using CuMemcpyDtoH =
    CUresult(WINAPI*)(void*, CUdeviceptr, std::size_t);

using NvOfGetMaxSupportedApiVersion =
    NV_OF_STATUS(NVOFAPI*)(std::uint32_t*);
using NvOfApiCreateInstanceCuda =
    NV_OF_STATUS(NVOFAPI*)(std::uint32_t, NV_OF_CUDA_API_FUNCTION_LIST*);

/**
 * 隔离探针持有的驱动、CUDA 上下文和 NVOFA 资源。
 *
 * 析构顺序严格保持“缓冲区 -> NVOFA 会话 -> CUDA 上下文 -> DLL”，
 * 让任一中途失败都不会污染播放器进程或遗留 GPU 资源。
 */
struct ProbeResources {
  HMODULE cuda_module = nullptr;
  HMODULE nvofa_module = nullptr;
  CuCtxDestroy cu_ctx_destroy = nullptr;
  CUcontext cuda_context = nullptr;
  NV_OF_CUDA_API_FUNCTION_LIST api{};
  NvOFHandle optical_flow = nullptr;
  NvOFGPUBufferHandle input = nullptr;
  NvOFGPUBufferHandle reference = nullptr;
  NvOFGPUBufferHandle output = nullptr;

  ~ProbeResources() {
    if (api.nvOFDestroyGPUBufferCuda != nullptr) {
      if (output != nullptr) api.nvOFDestroyGPUBufferCuda(output);
      if (reference != nullptr) api.nvOFDestroyGPUBufferCuda(reference);
      if (input != nullptr) api.nvOFDestroyGPUBufferCuda(input);
    }
    if (optical_flow != nullptr && api.nvOFDestroy != nullptr) {
      api.nvOFDestroy(optical_flow);
    }
    if (cuda_context != nullptr && cu_ctx_destroy != nullptr) {
      cu_ctx_destroy(cuda_context);
    }
    if (nvofa_module != nullptr) FreeLibrary(nvofa_module);
    if (cuda_module != nullptr) FreeLibrary(cuda_module);
  }
};

/**
 * 从系统 DLL 解析一个强类型入口。
 *
 * 探针只允许由 LoadLibraryExW 的 SYSTEM32 搜索范围加载驱动，避免当前目录
 * 或 PATH 中同名 DLL 干扰证据。
 */
template <typename Function>
Function Resolve(HMODULE module, const char* name) {
  return reinterpret_cast<Function>(GetProcAddress(module, name));
}

/** 输出稳定的失败阶段，便于 QA 脚本拒绝“只加载成功但未执行”。 */
int Fail(const char* stage, long status) {
  std::cerr << "nvofa-execute=failed stage=" << stage
            << " status=" << status << std::endl;
  return EXIT_FAILURE;
}

/** 把 CUDA 返回的 8-byte Windows LUID 归一化为 DXGI 使用的字符串。 */
std::string CudaLuidString(const char* luid) {
  std::uint32_t low = 0;
  std::uint32_t high = 0;
  std::memcpy(&low, luid, sizeof(low));
  std::memcpy(&high, luid + sizeof(low), sizeof(high));
  std::array<char, 32> buffer{};
  std::snprintf(buffer.data(), buffer.size(), "%08x:%08x", high, low);
  return buffer.data();
}

/** 查询单值能力；宽高边界查询失败时不允许猜测默认值。 */
bool QuerySingleCapability(const NV_OF_CUDA_API_FUNCTION_LIST& api,
                           NvOFHandle handle,
                           NV_OF_CAPS capability,
                           std::uint32_t* value) {
  std::uint32_t size = 0;
  if (api.nvOFGetCaps(handle, capability, nullptr, &size) != NV_OF_SUCCESS ||
      size != 1) {
    return false;
  }
  return api.nvOFGetCaps(handle, capability, value, &size) == NV_OF_SUCCESS &&
         size == 1;
}

/** 创建一个由 NVOFA 管理、可取得 CUdeviceptr 的 GPU 缓冲区。 */
NV_OF_STATUS CreateBuffer(const NV_OF_CUDA_API_FUNCTION_LIST& api,
                          NvOFHandle handle,
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
  return api.nvOFCreateGPUBufferCuda(
      handle, &descriptor, NV_OF_CUDA_BUFFER_TYPE_CUDEVICEPTR, buffer);
}

/** 按驱动返回的行间距把灰度测试帧上传到 NVOFA 输入缓冲区。 */
bool UploadFrame(const NV_OF_CUDA_API_FUNCTION_LIST& api,
                 CuMemcpyHtoD copy,
                 NvOFGPUBufferHandle buffer,
                 const std::vector<std::uint8_t>& frame,
                 std::uint32_t width,
                 std::uint32_t height) {
  const CUdeviceptr device_pointer =
      api.nvOFGPUBufferGetCUdeviceptr(buffer);
  NV_OF_CUDA_BUFFER_STRIDE_INFO stride{};
  if (device_pointer == 0 ||
      api.nvOFGPUBufferGetStrideInfo(buffer, &stride) != NV_OF_SUCCESS ||
      stride.numPlanes != 1 ||
      stride.strideInfo[0].strideXInBytes < width) {
    return false;
  }

  const std::size_t row_stride = stride.strideInfo[0].strideXInBytes;
  for (std::uint32_t y = 0; y < height; ++y) {
    if (copy(device_pointer + y * row_stride, frame.data() + y * width,
             width) != kCudaSuccess) {
      return false;
    }
  }
  return true;
}

/**
 * 从光流输出缓冲区读取紧凑的 S10.5 向量矩阵。
 *
 * 驱动可能为每行添加 pitch，因此逐行复制，不能直接按 width*height 假定连续。
 */
bool DownloadFlow(const NV_OF_CUDA_API_FUNCTION_LIST& api,
                  CuMemcpyDtoH copy,
                  NvOFGPUBufferHandle buffer,
                  std::uint32_t width,
                  std::uint32_t height,
                  std::vector<NV_OF_FLOW_VECTOR>* flow) {
  const CUdeviceptr device_pointer =
      api.nvOFGPUBufferGetCUdeviceptr(buffer);
  NV_OF_CUDA_BUFFER_STRIDE_INFO stride{};
  const std::size_t row_size =
      static_cast<std::size_t>(width) * sizeof(NV_OF_FLOW_VECTOR);
  if (device_pointer == 0 ||
      api.nvOFGPUBufferGetStrideInfo(buffer, &stride) != NV_OF_SUCCESS ||
      stride.numPlanes != 1 ||
      stride.strideInfo[0].strideXInBytes < row_size) {
    return false;
  }

  flow->assign(static_cast<std::size_t>(width) * height, {});
  const std::size_t row_stride = stride.strideInfo[0].strideXInBytes;
  for (std::uint32_t y = 0; y < height; ++y) {
    if (copy(flow->data() + y * width, device_pointer + y * row_stride,
             row_size) != kCudaSuccess) {
      return false;
    }
  }
  return true;
}

}  // namespace

/**
 * 建立真实 CUDA/NVOFA 会话并执行一对合成灰度帧。
 *
 * 成功条件同时覆盖：官方 ABI 实例化、硬件会话初始化、GPU 缓冲区、
 * execute、同步、结果回读，以及位移区域存在非零 S10.5 光流。该探针不是
 * FRUC 插帧器，也不会进入 Local Tag Player 的正式运行时。
 */
int main() {
  const D3D11AdapterSelection d3d11_adapter =
      SelectNvidiaD3D11Adapter();
  if (!d3d11_adapter.ready()) {
    return Fail(d3d11_adapter.error.c_str(), -1);
  }
  ProbeResources resources;
  resources.cuda_module = LoadLibraryExW(
      L"nvcuda.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  resources.nvofa_module = LoadLibraryExW(
      L"nvofapi64.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (resources.cuda_module == nullptr || resources.nvofa_module == nullptr) {
    return Fail("load-system-driver", GetLastError());
  }

  const auto cu_init = Resolve<CuInit>(resources.cuda_module, "cuInit");
  const auto cu_device_get_count =
      Resolve<CuDeviceGetCount>(resources.cuda_module, "cuDeviceGetCount");
  const auto cu_device_get =
      Resolve<CuDeviceGet>(resources.cuda_module, "cuDeviceGet");
  const auto cu_device_get_name =
      Resolve<CuDeviceGetName>(resources.cuda_module, "cuDeviceGetName");
  const auto cu_device_get_luid =
      Resolve<CuDeviceGetLuid>(resources.cuda_module, "cuDeviceGetLuid");
  const auto cu_ctx_create =
      Resolve<CuCtxCreate>(resources.cuda_module, "cuCtxCreate_v2");
  resources.cu_ctx_destroy =
      Resolve<CuCtxDestroy>(resources.cuda_module, "cuCtxDestroy_v2");
  const auto cu_ctx_synchronize =
      Resolve<CuCtxSynchronize>(resources.cuda_module, "cuCtxSynchronize");
  const auto cu_memcpy_h_to_d =
      Resolve<CuMemcpyHtoD>(resources.cuda_module, "cuMemcpyHtoD_v2");
  const auto cu_memcpy_d_to_h =
      Resolve<CuMemcpyDtoH>(resources.cuda_module, "cuMemcpyDtoH_v2");
  if (cu_init == nullptr || cu_device_get_count == nullptr ||
      cu_device_get == nullptr || cu_device_get_name == nullptr ||
      cu_device_get_luid == nullptr ||
      cu_ctx_create == nullptr || resources.cu_ctx_destroy == nullptr ||
      cu_ctx_synchronize == nullptr || cu_memcpy_h_to_d == nullptr ||
      cu_memcpy_d_to_h == nullptr) {
    return Fail("resolve-cuda-driver-api", GetLastError());
  }

  int device_count = 0;
  if (cu_init(0) != kCudaSuccess ||
      cu_device_get_count(&device_count) != kCudaSuccess ||
      device_count < 1) {
    return Fail("enumerate-cuda-device", device_count);
  }

  CUdevice device = 0;
  int matching_devices = 0;
  std::string cuda_luid;
  for (int index = 0; index < device_count; ++index) {
    CUdevice candidate = 0;
    std::array<char, 8> candidate_luid{};
    unsigned int node_mask = 0;
    if (cu_device_get(&candidate, index) != kCudaSuccess ||
        cu_device_get_luid(
            candidate_luid.data(), &node_mask, candidate) !=
            kCudaSuccess) {
      continue;
    }
    const std::string normalized =
        CudaLuidString(candidate_luid.data());
    if (normalized != d3d11_adapter.luid) continue;
    device = candidate;
    cuda_luid = normalized;
    ++matching_devices;
  }
  if (matching_devices != 1) {
    return Fail("match-cuda-device-by-d3d11-luid", matching_devices);
  }
  char device_name[128] = {};
  if (cu_device_get_name(device_name, sizeof(device_name), device) !=
          kCudaSuccess ||
      cu_ctx_create(&resources.cuda_context, 0, device) != kCudaSuccess) {
    return Fail("create-cuda-context", device);
  }

  const auto get_max_api = Resolve<NvOfGetMaxSupportedApiVersion>(
      resources.nvofa_module, "NvOFGetMaxSupportedApiVersion");
  const auto create_instance = Resolve<NvOfApiCreateInstanceCuda>(
      resources.nvofa_module, "NvOFAPICreateInstanceCuda");
  if (get_max_api == nullptr || create_instance == nullptr) {
    return Fail("resolve-nvofa-api", GetLastError());
  }

  std::uint32_t driver_max_api = 0;
  if (get_max_api(&driver_max_api) != NV_OF_SUCCESS ||
      driver_max_api < NV_OF_API_VERSION) {
    return Fail("nvofa-api-version", driver_max_api);
  }
  NV_OF_STATUS status =
      create_instance(NV_OF_API_VERSION, &resources.api);
  if (status != NV_OF_SUCCESS) {
    return Fail("create-nvofa-api-instance", status);
  }
  if (resources.api.nvCreateOpticalFlowCuda == nullptr ||
      resources.api.nvOFInit == nullptr ||
      resources.api.nvOFCreateGPUBufferCuda == nullptr ||
      resources.api.nvOFGPUBufferGetCUdeviceptr == nullptr ||
      resources.api.nvOFGPUBufferGetStrideInfo == nullptr ||
      resources.api.nvOFExecute == nullptr ||
      resources.api.nvOFDestroyGPUBufferCuda == nullptr ||
      resources.api.nvOFDestroy == nullptr ||
      resources.api.nvOFGetCaps == nullptr) {
    return Fail("validate-nvofa-function-list", -1);
  }

  status = resources.api.nvCreateOpticalFlowCuda(
      resources.cuda_context, &resources.optical_flow);
  if (status != NV_OF_SUCCESS || resources.optical_flow == nullptr) {
    return Fail("create-nvofa-session", status);
  }

  std::uint32_t grid_count = 0;
  status = resources.api.nvOFGetCaps(
      resources.optical_flow, NV_OF_CAPS_SUPPORTED_OUTPUT_GRID_SIZES,
      nullptr, &grid_count);
  if (status != NV_OF_SUCCESS || grid_count == 0) {
    return Fail("query-output-grid-count", status);
  }
  std::vector<std::uint32_t> grids(grid_count);
  status = resources.api.nvOFGetCaps(
      resources.optical_flow, NV_OF_CAPS_SUPPORTED_OUTPUT_GRID_SIZES,
      grids.data(), &grid_count);
  if (status != NV_OF_SUCCESS || grid_count == 0) {
    return Fail("query-output-grids", status);
  }
  grids.resize(grid_count);
  const std::uint32_t grid =
      std::find(grids.begin(), grids.end(), 4U) != grids.end()
          ? 4U
          : grids.front();
  if (grid != 1 && grid != 2 && grid != 4) {
    return Fail("unsupported-output-grid", grid);
  }

  std::uint32_t minimum_width = 0;
  std::uint32_t minimum_height = 0;
  std::uint32_t maximum_width = 0;
  std::uint32_t maximum_height = 0;
  if (!QuerySingleCapability(resources.api, resources.optical_flow,
                             NV_OF_CAPS_WIDTH_MIN, &minimum_width) ||
      !QuerySingleCapability(resources.api, resources.optical_flow,
                             NV_OF_CAPS_HEIGHT_MIN, &minimum_height) ||
      !QuerySingleCapability(resources.api, resources.optical_flow,
                             NV_OF_CAPS_WIDTH_MAX, &maximum_width) ||
      !QuerySingleCapability(resources.api, resources.optical_flow,
                             NV_OF_CAPS_HEIGHT_MAX, &maximum_height)) {
    return Fail("query-frame-limits", -1);
  }
  const std::uint32_t width =
      std::max<std::uint32_t>(minimum_width, 320);
  const std::uint32_t height =
      std::max<std::uint32_t>(minimum_height, 192);
  if (width > maximum_width || height > maximum_height) {
    return Fail("select-frame-size", -1);
  }

  NV_OF_INIT_PARAMS init{};
  init.width = width;
  init.height = height;
  init.outGridSize =
      static_cast<NV_OF_OUTPUT_VECTOR_GRID_SIZE>(grid);
  init.mode = NV_OF_MODE_OPTICALFLOW;
  init.perfLevel = NV_OF_PERF_LEVEL_MEDIUM;
  init.enableExternalHints = NV_OF_FALSE;
  init.enableOutputCost = NV_OF_FALSE;
  init.disparityRange = NV_OF_STEREO_DISPARITY_RANGE_UNDEFINED;
  init.enableRoi = NV_OF_FALSE;
  status = resources.api.nvOFInit(resources.optical_flow, &init);
  if (status != NV_OF_SUCCESS) return Fail("initialize-nvofa-session", status);

  const std::uint32_t output_width = (width + grid - 1) / grid;
  const std::uint32_t output_height = (height + grid - 1) / grid;
  status = CreateBuffer(resources.api, resources.optical_flow, width, height,
                        NV_OF_BUFFER_USAGE_INPUT,
                        NV_OF_BUFFER_FORMAT_GRAYSCALE8, &resources.input);
  if (status != NV_OF_SUCCESS) return Fail("create-input-buffer", status);
  status = CreateBuffer(resources.api, resources.optical_flow, width, height,
                        NV_OF_BUFFER_USAGE_INPUT,
                        NV_OF_BUFFER_FORMAT_GRAYSCALE8,
                        &resources.reference);
  if (status != NV_OF_SUCCESS) return Fail("create-reference-buffer", status);
  status = CreateBuffer(resources.api, resources.optical_flow, output_width,
                        output_height, NV_OF_BUFFER_USAGE_OUTPUT,
                        NV_OF_BUFFER_FORMAT_SHORT2, &resources.output);
  if (status != NV_OF_SUCCESS) return Fail("create-output-buffer", status);

  std::vector<std::uint8_t> input_frame(
      static_cast<std::size_t>(width) * height, 16);
  std::vector<std::uint8_t> reference_frame = input_frame;
  const std::uint32_t block_width = std::max<std::uint32_t>(64, width / 5);
  const std::uint32_t block_height =
      std::max<std::uint32_t>(64, height / 3);
  const std::uint32_t start_x = width / 5;
  const std::uint32_t start_y = height / 3;
  const std::uint32_t shift_x = std::max<std::uint32_t>(16, width / 16);
  for (std::uint32_t y = start_y;
       y < std::min(height, start_y + block_height); ++y) {
    for (std::uint32_t x = start_x;
         x < std::min(width, start_x + block_width); ++x) {
      input_frame[y * width + x] = 235;
      if (x + shift_x < width) {
        reference_frame[y * width + x + shift_x] = 235;
      }
    }
  }
  if (!UploadFrame(resources.api, cu_memcpy_h_to_d, resources.input,
                   input_frame, width, height) ||
      !UploadFrame(resources.api, cu_memcpy_h_to_d, resources.reference,
                   reference_frame, width, height)) {
    return Fail("upload-test-frames", -1);
  }

  NV_OF_EXECUTE_INPUT_PARAMS execute_input{};
  execute_input.inputFrame = resources.input;
  execute_input.referenceFrame = resources.reference;
  execute_input.disableTemporalHints = NV_OF_TRUE;
  NV_OF_EXECUTE_OUTPUT_PARAMS execute_output{};
  execute_output.outputBuffer = resources.output;
  status = resources.api.nvOFExecute(
      resources.optical_flow, &execute_input, &execute_output);
  if (status != NV_OF_SUCCESS) return Fail("execute-optical-flow", status);
  if (cu_ctx_synchronize() != kCudaSuccess) {
    return Fail("synchronize-cuda-context", -1);
  }

  std::vector<NV_OF_FLOW_VECTOR> flow;
  if (!DownloadFlow(resources.api, cu_memcpy_d_to_h, resources.output,
                    output_width, output_height, &flow)) {
    return Fail("download-flow-vectors", -1);
  }
  std::size_t nonzero_vectors = 0;
  std::int32_t maximum_absolute_x = 0;
  std::int32_t maximum_absolute_y = 0;
  for (const auto& vector : flow) {
    const std::int32_t absolute_x =
        std::abs(static_cast<std::int32_t>(vector.flowx));
    const std::int32_t absolute_y =
        std::abs(static_cast<std::int32_t>(vector.flowy));
    maximum_absolute_x = std::max(maximum_absolute_x, absolute_x);
    maximum_absolute_y = std::max(maximum_absolute_y, absolute_y);
    if (absolute_x != 0 || absolute_y != 0) ++nonzero_vectors;
  }
  if (nonzero_vectors == 0 || maximum_absolute_x < 32) {
    return Fail("validate-nonzero-flow", maximum_absolute_x);
  }

  std::cout << "nvofa-execute=passed"
            << " api=" << (NV_OF_API_VERSION >> 4) << "."
            << (NV_OF_API_VERSION & 0xF)
            << " driver-max=" << (driver_max_api >> 4) << "."
            << (driver_max_api & 0xF)
            << " device=" << device_name
            << " d3d11-luid=" << d3d11_adapter.luid
            << " cuda-luid=" << cuda_luid
            << " luid-match=passed"
            << " grid=" << grid
            << " frame=" << width << "x" << height
            << " nonzero=" << nonzero_vectors
            << " max-flow-x-s10.5=" << maximum_absolute_x
            << " max-flow-y-s10.5=" << maximum_absolute_y
            << std::endl;
  return EXIT_SUCCESS;
}
