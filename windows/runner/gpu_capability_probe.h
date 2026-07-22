#ifndef RUNNER_GPU_CAPABILITY_PROBE_H_
#define RUNNER_GPU_CAPABILITY_PROBE_H_

#include <flutter/encodable_value.h>

/**
 * 枚举当前 Windows 会话可见的显卡，并返回不包含用户路径的只读能力矩阵。
 *
 * 该结果描述系统设备，不声明播放器当前选择了哪块显卡；活动适配器必须由上层结合
 * 播放会话证据单独判定。
 */
flutter::EncodableMap QueryGpuCapabilityMatrix();

#endif  // RUNNER_GPU_CAPABILITY_PROBE_H_
