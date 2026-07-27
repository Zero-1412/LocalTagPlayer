#include <windows.h>

/**
 * 仅供结构化滤镜宿主测试识别 ABI 导出的假 VSScript。
 *
 * 测试不会送入视频帧，也不会调用返回值；该 DLL 没有安装规则，禁止作为真实
 * VapourSynth 运行时使用或进入应用发布目录。
 */
extern "C" __declspec(dllexport) void* getVSScriptAPI(int) {
  return nullptr;
}
