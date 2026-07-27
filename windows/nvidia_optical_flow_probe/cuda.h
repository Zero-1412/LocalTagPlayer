#ifndef LTP_NVOFA_CUDA_DRIVER_TYPES_H_
#define LTP_NVOFA_CUDA_DRIVER_TYPES_H_

#include <cstdint>

/**
 * NVOFA 的公开 CUDA 头只依赖这些 CUDA Driver API 句柄类型。
 *
 * 隔离探针通过系统 nvcuda.dll 动态解析函数，不要求开发机安装 CUDA Toolkit；
 * 这里不声明 CUDA 函数，也不冒充完整 cuda.h。
 */
using CUdevice = int;
struct CUctx_st;
struct CUstream_st;
struct CUarray_st;
using CUcontext = CUctx_st*;
using CUstream = CUstream_st*;
using CUarray = CUarray_st*;
using CUdeviceptr = std::uint64_t;

#endif  // LTP_NVOFA_CUDA_DRIVER_TYPES_H_
