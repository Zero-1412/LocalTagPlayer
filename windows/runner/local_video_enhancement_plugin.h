#ifndef RUNNER_LOCAL_VIDEO_ENHANCEMENT_PLUGIN_H_
#define RUNNER_LOCAL_VIDEO_ENHANCEMENT_PLUGIN_H_

#include <Windows.h>
#include <d3d11.h>
#include <wrl/client.h>

#include <cstdint>
#include <mutex>
#include <string>

#include "../native_player/local_video_enhancement_plugin_api.h"

/**
 * 本机视频增强插件宿主。
 *
 * 仅当 LOCAL_TAG_PLAYER_VIDEO_PLUGIN_PATH 指向绝对 DLL 路径时加载。宿主不扫描
 * 安装目录、不分发插件文件，也不改变默认 MediaKit 后端；它只服务显式启用的
 * Windows 原生 mpv 实验路径。
 */
class LocalVideoEnhancementPlugin {
 public:
  /** 供 Flutter 诊断读取的线程安全快照。 */
  struct Snapshot {
    std::string state = "not-configured";
    std::string name = "unavailable";
    std::string error;
    int64_t processed_frames = 0;
    int64_t fallback_frames = 0;
  };

  LocalVideoEnhancementPlugin() = default;
  ~LocalVideoEnhancementPlugin();

  LocalVideoEnhancementPlugin(const LocalVideoEnhancementPlugin&) = delete;
  LocalVideoEnhancementPlugin& operator=(
      const LocalVideoEnhancementPlugin&) = delete;

  /**
   * 在原生播放器工作线程初始化显式指定的 DLL。
   *
   * 缺少配置或加载失败都只更新诊断，不阻止播放器继续使用原始共享纹理。
   */
  void Initialize(ID3D11Device* device,
                  ID3D11DeviceContext* immediate_context);

  /**
   * 处理一帧共享纹理。
   *
   * 调用前备份原帧；插件失败时立即恢复并停用本次插件会话，后续帧直通。
   */
  void ProcessFrame(ID3D11Device* device,
                    ID3D11DeviceContext* immediate_context,
                    ID3D11Texture2D* texture, uint64_t frame_index);

  /** 在 D3D11 表面销毁前关闭插件并卸载本机 DLL。 */
  void Shutdown();

  /** 返回可跨平台线程读取的轻量诊断。 */
  Snapshot GetSnapshot() const;

 private:
  /** 保存错误并进入不可再调用的失败状态。 */
  void DisableWithFailure(const std::string& state,
                          const std::string& error,
                          bool count_fallback);
  /** 依据输入纹理描述创建或复用无共享标志的宿主备份纹理。 */
  bool EnsureBackupTexture(ID3D11Device* device,
                           const D3D11_TEXTURE2D_DESC& source_desc);

  mutable std::mutex mutex_;
  HMODULE module_ = nullptr;
  const LtpLocalVideoPluginApiV1* api_ = nullptr;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> backup_texture_;
  D3D11_TEXTURE2D_DESC backup_desc_{};
  Snapshot snapshot_;
  bool initialized_ = false;
  bool disabled_ = false;
};

#endif  // RUNNER_LOCAL_VIDEO_ENHANCEMENT_PLUGIN_H_
