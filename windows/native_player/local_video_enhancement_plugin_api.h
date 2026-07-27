#ifndef LTP_LOCAL_VIDEO_ENHANCEMENT_PLUGIN_API_H_
#define LTP_LOCAL_VIDEO_ENHANCEMENT_PLUGIN_API_H_

#include <Windows.h>
#include <d3d11.h>

#include <cstdint>

/**
 * 本机视频增强插件 ABI 版本。
 *
 * 该头文件只描述 Local Tag Player 与本机实验 DLL 的 D3D11 边界，不引用、
 * 打包或暗示任何厂商 SDK。不同版本必须通过导出表协商，禁止按结构体布局猜测。
 */
constexpr uint32_t kLtpLocalVideoPluginAbiVersion = 1;

/**
 * 插件初始化上下文。
 *
 * device 与 immediate_context 由播放器的 ANGLE 表面拥有；插件只能在回调期间使用，
 * 不得释放。插件若需跨帧持有，必须自行 AddRef，并在 shutdown 中对称释放。
 */
struct LtpLocalVideoPluginInitContext {
  uint32_t struct_size;
  uint32_t abi_version;
  ID3D11Device* device;
  ID3D11DeviceContext* immediate_context;
};

/**
 * 单帧原位处理上下文。
 *
 * texture 是 Flutter 即将读取的共享 BGRA 纹理。返回 0 表示结果可展示；任何非零值
 * 都会触发宿主恢复原帧并停用插件，因此插件不得把异步工作遗留到回调返回之后。
 */
struct LtpLocalVideoPluginFrameContext {
  uint32_t struct_size;
  uint32_t abi_version;
  ID3D11Device* device;
  ID3D11DeviceContext* immediate_context;
  ID3D11Texture2D* texture;
  uint32_t width;
  uint32_t height;
  DXGI_FORMAT format;
  uint64_t frame_index;
};

using LtpLocalVideoPluginInitialize =
    int32_t(__cdecl*)(const LtpLocalVideoPluginInitContext* context);
using LtpLocalVideoPluginProcess =
    int32_t(__cdecl*)(const LtpLocalVideoPluginFrameContext* context);
using LtpLocalVideoPluginShutdown = void(__cdecl*)();

/**
 * ABI v1 导出表。
 *
 * plugin_name 必须指向 DLL 生命周期内稳定的 UTF-8 字符串。宿主仅记录诊断，
 * 不把名称用于授权、文件发现或能力判断。
 */
struct LtpLocalVideoPluginApiV1 {
  uint32_t struct_size;
  uint32_t abi_version;
  const char* plugin_name;
  LtpLocalVideoPluginInitialize initialize;
  LtpLocalVideoPluginProcess process;
  LtpLocalVideoPluginShutdown shutdown;
};

using LtpGetLocalVideoPluginApiV1 =
    const LtpLocalVideoPluginApiV1*(__cdecl*)();

constexpr char kLtpLocalVideoPluginExportName[] =
    "LtpGetLocalVideoEnhancementPluginV1";

#endif  // LTP_LOCAL_VIDEO_ENHANCEMENT_PLUGIN_API_H_
