#include "../runner/nvidia_optical_flow_driver_probe.h"

#include <iomanip>
#include <iostream>

int wmain() {
  const auto snapshot = ProbeNvidiaOpticalFlowDriver();
  std::cout << "nvofa-driver=" << snapshot.state
            << " api-major=" << snapshot.api_version_major
            << " api-minor=" << snapshot.api_version_minor
            << " api-raw=0x" << std::hex << std::uppercase
            << snapshot.api_version_raw << std::dec
            << " d3d11="
            << (snapshot.d3d11_available ? "available" : "missing")
            << " d3d12="
            << (snapshot.d3d12_available ? "available" : "missing")
            << " cuda="
            << (snapshot.cuda_available ? "available" : "missing")
            << " vulkan="
            << (snapshot.vulkan_available ? "available" : "missing")
            << "\n";
  return snapshot.state == "available" ? 0 : 2;
}
