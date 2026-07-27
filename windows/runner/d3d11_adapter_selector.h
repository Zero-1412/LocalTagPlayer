#ifndef RUNNER_D3D11_ADAPTER_SELECTOR_H_
#define RUNNER_D3D11_ADAPTER_SELECTOR_H_

#include <cstdint>
#include <string>

/**
 * Windows 原生 NVIDIA 播放链预先选定的 D3D11 适配器。
 *
 * mpv 的 `d3d11-adapter` 只接受适配器名称，因此名称必须在当前 DXGI 会话中唯一；
 * `luid` 才是交给 CUDA/NVOFA 做同设备匹配的稳定会话内身份。
 */
struct D3D11AdapterSelection {
  std::string state = "unavailable";
  std::string error = "not-probed";
  std::string description;
  std::string luid;
  std::uint32_t vendor_id = 0;
  std::uint32_t device_id = 0;

  /** 只有 D3D11 能力、唯一名称和 LUID 都已确认时才允许绑定 mpv/NVOFA。 */
  bool ready() const {
    return state == "ready" && !description.empty() && !luid.empty();
  }
};

/**
 * 选择当前 Windows 会话的高性能 NVIDIA D3D11 适配器。
 *
 * 可选环境变量 `LOCAL_TAG_PLAYER_NVIDIA_ADAPTER_LUID` 只接受能力矩阵使用的
 * `hhhhhhhh:llllllll` 形式，用于多 NVIDIA 设备机器显式指定；未设置时选择
 * DXGI 高性能顺序中的第一块。名称重复时拒绝，避免 mpv 前缀匹配到另一块卡。
 */
D3D11AdapterSelection SelectNvidiaD3D11Adapter();

#endif  // RUNNER_D3D11_ADAPTER_SELECTOR_H_
