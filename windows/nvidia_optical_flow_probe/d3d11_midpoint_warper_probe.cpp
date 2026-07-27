#include <algorithm>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

#include "d3d11_adapter_selector.h"
#include "d3d11_midpoint_warper.h"

namespace {
constexpr int kWidth = 64;
constexpr int kHeight = 32;
constexpr std::uint32_t kGrid = 4;
constexpr std::uint32_t kFlowWidth = kWidth / kGrid;
constexpr std::uint32_t kFlowHeight = kHeight / kGrid;

/** 使用同一组资源执行一个确定性灰度平面案例。 */
bool WarpCase(
    D3D11MidpointWarper* warper,
    const std::vector<std::uint8_t>& first,
    const std::vector<std::uint8_t>& second,
    const std::vector<NV_OF_FLOW_VECTOR>& forward,
    const std::vector<NV_OF_FLOW_VECTOR>& backward,
    const std::vector<std::uint8_t>& forward_cost,
    const std::vector<std::uint8_t>& backward_cost,
    std::vector<std::uint8_t>* output) {
  if (warper == nullptr || output == nullptr ||
      !warper->PrepareFlow(
          forward, backward, forward_cost, backward_cost,
          kFlowWidth, kFlowHeight, kGrid)) {
    return false;
  }
  output->assign(static_cast<std::size_t>(kWidth) * kHeight, 0);
  return warper->WarpPlane(
      0, first.data(), kWidth, second.data(), kWidth,
      output->data(), kWidth, kWidth, kHeight, kWidth, kHeight);
}
}  // namespace

/**
 * 验证 D3D11 shader 的方向、等权融合及 cost/一致性保守修正。
 *
 * 该探针只运行仓库自己的 Compute 代码，不加载或分发 NVIDIA SDK DLL。
 */
int main() {
  const D3D11AdapterSelection adapter =
      SelectNvidiaD3D11Adapter();
  if (!adapter.ready()) {
    std::cerr << "adapter-selection-failed=" << adapter.error << "\n";
    return 2;
  }

  D3D11MidpointWarper warper;
  if (!warper.Initialize(adapter.luid)) {
    std::cerr << "warper-initialize-failed=" << warper.error() << "\n";
    return 3;
  }

  const std::size_t pixel_count =
      static_cast<std::size_t>(kWidth) * kHeight;
  const std::size_t flow_count =
      static_cast<std::size_t>(kFlowWidth) * kFlowHeight;
  std::vector<std::uint8_t> first(pixel_count, 32);
  std::vector<std::uint8_t> second(pixel_count, 224);
  std::vector<NV_OF_FLOW_VECTOR> forward(flow_count, {});
  std::vector<NV_OF_FLOW_VECTOR> backward(flow_count, {});
  std::vector<std::uint8_t> forward_cost(flow_count, 0);
  std::vector<std::uint8_t> backward_cost(flow_count, 0);
  std::vector<std::uint8_t> output;

  if (!WarpCase(
          &warper, first, second, forward, backward,
          forward_cost, backward_cost, &output) ||
      output[16 * kWidth + 32] != 128) {
    std::cerr << "zero-flow-blend-failed="
              << static_cast<int>(output.empty()
                                      ? 0
                                      : output[16 * kWidth + 32])
              << " error=" << warper.error() << "\n";
    return 4;
  }
  const int zero_blend = output[16 * kWidth + 32];

  // 第一帧向右移动 4 像素，第二帧由第一帧右移得到；中点应采到同一亮度。
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      first[y * kWidth + x] = static_cast<std::uint8_t>(x * 3);
      const int source_x = x < 4 ? 0 : x - 4;
      second[y * kWidth + x] =
          static_cast<std::uint8_t>(source_x * 3);
    }
  }
  for (auto& value : forward) value.flowx = 4 * 32;
  for (auto& value : backward) value.flowx = -4 * 32;
  if (!WarpCase(
          &warper, first, second, forward, backward,
          forward_cost, backward_cost, &output) ||
      output[16 * kWidth + 32] != 90) {
    std::cerr << "consistent-motion-failed="
              << static_cast<int>(output.empty()
                                      ? 0
                                      : output[16 * kWidth + 32])
              << " error=" << warper.error() << "\n";
    return 5;
  }
  const int consistent_motion = output[16 * kWidth + 32];

  // 两侧向量明显不一致且第二侧 cost 极高时，只允许温和偏向第一帧，
  // 防止没有补洞阶段时因强选单侧样本制造遮挡边缘拖影。
  std::fill(
      first.begin(), first.end(), static_cast<std::uint8_t>(32));
  std::fill(
      second.begin(), second.end(), static_cast<std::uint8_t>(224));
  std::fill(forward.begin(), forward.end(), NV_OF_FLOW_VECTOR{});
  std::fill(backward.begin(), backward.end(), NV_OF_FLOW_VECTOR{});
  for (auto& value : backward) value.flowx = 16 * 32;
  std::fill(
      backward_cost.begin(), backward_cost.end(),
      static_cast<std::uint8_t>(255));
  if (!WarpCase(
          &warper, first, second, forward, backward,
          forward_cost, backward_cost, &output)) {
    std::cerr << "confidence-warp-failed=" << warper.error() << "\n";
    return 6;
  }
  const int unreliable_side = output[16 * kWidth + 32];
  if (unreliable_side < 112 || unreliable_side > 122) {
    std::cerr << "confidence-weight-failed=" << unreliable_side << "\n";
    return 7;
  }

  std::cout << "d3d11-warp-confidence=passed"
            << " zero-blend=" << zero_blend
            << " consistent-motion=" << consistent_motion
            << " unreliable-side=" << unreliable_side
            << " luid=" << adapter.luid << "\n";
  return 0;
}
