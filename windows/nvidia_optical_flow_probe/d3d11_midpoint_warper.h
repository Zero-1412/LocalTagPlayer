#ifndef LTP_NVOFA_D3D11_MIDPOINT_WARPER_H_
#define LTP_NVOFA_D3D11_MIDPOINT_WARPER_H_

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "nvOpticalFlowCommon.h"

/**
 * 在指定 DXGI LUID 上执行 0.5 时间点双向光流 warp。
 *
 * VapourSynth 仍提供软件平面，但逐像素采样和融合由 D3D11 Compute Shader 完成；
 * 失败由上层撤销整条插帧滤镜，不静默回退 CPU 慢路径。
 */
class D3D11MidpointWarper {
 public:
  D3D11MidpointWarper();
  ~D3D11MidpointWarper();

  D3D11MidpointWarper(const D3D11MidpointWarper&) = delete;
  D3D11MidpointWarper& operator=(const D3D11MidpointWarper&) = delete;

  /** 在 [adapter_luid] 对应的物理适配器上创建设备并编译固定 shader。 */
  bool Initialize(const std::string& adapter_luid);

  /** 上传当前帧对的前向/后向 S10.5 光流；每个中间帧只调用一次。 */
  bool PrepareFlow(
      const std::vector<NV_OF_FLOW_VECTOR>& forward,
      const std::vector<NV_OF_FLOW_VECTOR>& backward,
      std::uint32_t width,
      std::uint32_t height,
      std::uint32_t grid);

  /**
   * 对一个 8-bit 平面执行 GPU warp。
   *
   * [plane_index] 用于复用 Y/U/V 各自尺寸的 GPU 资源；[luma_width] 和
   * [luma_height] 把 NVOFA luma 光流换算到色度平面。
   */
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
      int luma_height);

  /** 返回不含驱动原文和本机路径的稳定失败阶段。 */
  const std::string& error() const;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // LTP_NVOFA_D3D11_MIDPOINT_WARPER_H_
