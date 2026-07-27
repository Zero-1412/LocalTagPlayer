#ifndef RUNNER_VAPOURSYNTH_MOTION_RUNTIME_H_
#define RUNNER_VAPOURSYNTH_MOTION_RUNTIME_H_

#include <mpv/client.h>
#include <windows.h>

#include <cstdint>
#include <mutex>
#include <string>

/**
 * 本机 VapourSynth 插帧运行时宿主。
 *
 * 该宿主不分发 VapourSynth、Python、NVIDIA Optical Flow SDK 或第三方模型，
 * 只从用户显式配置的绝对目录预加载 `VSScript.dll`，并通过 libmpv 的结构化
 * `vf` 属性挂载本机 `.vpy` 脚本。结构化节点避免 Windows 盘符、空格和冒号被
 * mpv 的字符串子选项解析器误拆。
 */
class VapourSynthMotionRuntime {
 public:
  /** 不包含本地路径或第三方日志原文的稳定诊断快照。 */
  struct Snapshot {
    std::string state = "not-configured";
    std::string error;
    bool configured = false;
    bool enabled = false;
    int64_t fallback_count = 0;
  };

  VapourSynthMotionRuntime() = default;
  ~VapourSynthMotionRuntime();

  VapourSynthMotionRuntime(const VapourSynthMotionRuntime&) = delete;
  VapourSynthMotionRuntime& operator=(const VapourSynthMotionRuntime&) = delete;

  /**
   * 读取本机配置并预加载 VSScript。
   *
   * 必须在首次挂载 VapourSynth 滤镜前调用；重复调用不会替换已经验证的运行时。
   */
  void Initialize();

  /**
   * 启用或关闭带稳定标签的 VapourSynth 滤镜。
   *
   * [player] 必须是已初始化的独占 libmpv 会话。方法保留现有去块、降噪、
   * 锐化等滤镜，只替换 `ltp-motion-interpolation` 标签对应的条目。
   */
  bool Apply(mpv_handle* player, bool enabled);

  /**
   * 其它画质协调器重写完整 `vf` 后恢复已请求的插帧滤镜。
   *
   * 该方法只在当前会话已经启用时生效，避免滤镜顺序变化静默关闭插帧。
   */
  bool ReapplyAfterFilterGraphChange(mpv_handle* player);

  /**
   * 消费 mpv 固定错误文本并执行安全回退。
   *
   * 原始日志可能包含媒体或脚本路径，禁止保存或跨平台通道返回。
   */
  void ObserveLog(mpv_handle* player, const char* prefix, const char* text);

  /**
   * 以实际滤镜输出帧率确认插帧已经生效。
   *
   * 仅当带标签滤镜仍存在且输出帧率显著高于源帧率时进入 active，防止透传脚本
   * 或仅成功写入配置被误报为真实补帧。
   */
  void ConfirmFrameRateIncrease(mpv_handle* player, double source_fps,
                                double filtered_fps);

  /** 释放预加载模块并清除会话级启用状态。 */
  void Shutdown();

  Snapshot GetSnapshot() const;

 private:
  /** 在保留其它滤镜的前提下移除或追加本宿主拥有的结构化条目。 */
  bool RewriteFilterGraph(mpv_handle* player, bool append_motion_filter);

  /** 标记运行失败并从当前滤镜图移除本宿主条目。 */
  void FailAndRollback(mpv_handle* player, const std::string& error);

  mutable std::mutex mutex_;
  HMODULE vsscript_module_ = nullptr;
  std::string script_path_utf8_;
  /** 可选脚本用户数据；NVOFA 原型用它传递本机插件绝对路径。 */
  std::string user_data_utf8_;
  Snapshot snapshot_;
};

#endif  // RUNNER_VAPOURSYNTH_MOTION_RUNTIME_H_
