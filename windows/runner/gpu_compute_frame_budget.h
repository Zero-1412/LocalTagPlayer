#ifndef RUNNER_GPU_COMPUTE_FRAME_BUDGET_H_
#define RUNNER_GPU_COMPUTE_FRAME_BUDGET_H_

#include <flutter/encodable_value.h>

#include <string>

/**
 * 在指定 DXGI LUID 上运行 1080p/4K Compute Shader 帧预算基线。
 *
 * 调用方必须放在后台线程；结果只包含 GPU 时间戳统计，不读取媒体库或用户路径。
 */
flutter::EncodableMap QueryGpuComputeFrameBudget(
    const std::string& adapter_luid);

#endif  // RUNNER_GPU_COMPUTE_FRAME_BUDGET_H_
