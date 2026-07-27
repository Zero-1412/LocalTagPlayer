#ifndef RUNNER_NVIDIA_OPTICAL_FLOW_DRIVER_PROBE_H_
#define RUNNER_NVIDIA_OPTICAL_FLOW_DRIVER_PROBE_H_

#include <cstdint>
#include <string>

/**
 * NVIDIA 显示驱动 NVOFA 入口的只读快照。
 *
 * 该快照只证明系统驱动暴露 OFAPI，不表示 FRUC 或 RTX Video SDK 已安装，也不
 * 表示当前 mpv D3D11 纹理已经注册为 Optical Flow 输入。
 */
struct NvidiaOpticalFlowDriverSnapshot {
  std::string state = "unavailable";
  std::string error = "not-probed";
  uint32_t api_version_raw = 0;
  uint32_t api_version_major = 0;
  uint32_t api_version_minor = 0;
  bool d3d11_available = false;
  bool d3d12_available = false;
  bool cuda_available = false;
  bool vulkan_available = false;
};

/**
 * 从 Windows System32 安全探测 NVIDIA OFAPI。
 *
 * 实现不链接、不下载也不分发 NVIDIA SDK；只调用显示驱动公开的最大 API 版本
 * 查询，并检查固定设备入口是否存在。
 */
NvidiaOpticalFlowDriverSnapshot ProbeNvidiaOpticalFlowDriver();

#endif  // RUNNER_NVIDIA_OPTICAL_FLOW_DRIVER_PROBE_H_
