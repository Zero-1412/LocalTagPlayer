# HDR 长播与 SDR 暗部基线（2026-07-22）

## 目的与边界

本基线验证当前唯一第三阶段实验“HDR 动态映射”的真实长播稳定性、显示输出与运行成本，并为暗部增强保留一条完全独立的 SDR 关闭态对照。它不代表所有显卡、显示器或媒体，也不把 GPU 支持、HDR 源信号或截图颜色冒充 HDR 直通证据。

测试直接构建单项 `PlayerPage` 和真实 MediaKit 后端，不读取用户媒体库。固定视频由仓库脚本生成，证据输出到 `.local/qa/`，不提交视频、截图、进程 PID 或本机动态指标。

## 复现命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run_fixed_quality_baseline.ps1 `
  -HdrSeconds 300 `
  -SdrDarkSeconds 180 `
  -OutputDirectory ".local/qa/fixed-quality-baseline"
```

脚本先用 `tool/generate_player_quality_samples.ps1` 原子生成并经 FFprobe 校验两份样本，再分别启动真实 Windows integration test。播放器每 5 秒保存一次匿名诊断；外部监控只绑定测试进程 PID，约每秒采集进程 CPU、GPU Engine、GPU committed 和窗口响应，同时读取 NVIDIA-SMI 的整卡功耗。中点与结束点同时保存播放器后端视频帧和 `PrintWindow` 窗口截图，避免其它前台窗口污染证据。

## 固定样本

| 模式 | 内容 | 编码与色彩 | 记录时长 |
|---|---|---|---:|
| HDR | 1080p/30fps 运动彩条、细线、棋盘和渐变 | HEVC 10 bit、BT.2020、PQ、HDR10 mastering / MaxCLL | 302 秒 |
| SDR 暗部 | 1080p/30fps 近黑渐变、相邻暗灰块和移动灰块 | H.264 8 bit、BT.709、Limited | 182 秒 |

样本不含音轨，因此本轮不能用它评价听感或音频设备功耗；`audioStalled=false` 仅表示播放器诊断没有报告音频链路停滞，不代表完成了有声长播测试。

## 显示输出基线

活动渲染边界返回 LUID `00000000:00016bec`，精确匹配 NVIDIA GeForce RTX 4070 SUPER。DXGI `IDXGIOutput6::GetDesc1` 返回当前实际桌面输出：

| 输出 | 桌面 | 位深 | 色彩空间 | HDR 信号 | 最小 / 峰值 / 全屏峰值亮度 |
|---|---:|---:|---|---|---:|
| `\\.\DISPLAY1` | 3840×2160 | 8 bit | `rgb-full-g22-p709` | 未活动 | 0.01 / 417 / 417 nits |

因此本次 HDR 结果应解释为：HDR10/PQ 源在播放器内启用 Hable 与 Compute peak 后映射到 SDR BT.709 桌面输出。它验证的是映射链路与稳定性，不是 HDR passthrough，也不能凭截图做色度学准确性结论。

## 长播结果

| 指标 | HDR10/PQ | SDR 暗部 |
|---|---:|---:|
| 播放器诊断样本 | 60 | 36 |
| 解码 / 输出 / 总掉帧最大值 | 0 / 不可用 / 0 | 0 / 不可用 / 0 |
| 视频/音频停滞样本 | 0 | 0 |
| `smooth=false` 样本 | 0 | 0 |
| 最低前向缓存 | 60.47 秒 | 60.83 秒 |
| 窗口无响应样本 | 0 / 71 | 0 / 45 |
| 进程 GPU Engine 中位 / P95 | 6.7% / 9.6% | 5.1% / 5.7% |
| GPU committed 中位 / P95 | 458.5 / 470.4 MiB | 301.4 / 308.4 MiB |
| 工作集内存中位 / P95 | 585.0 / 691.9 MiB | 494.1 / 540.7 MiB |
| NVIDIA 整卡功耗中位 / P95 / 最大 | 157.77 / 168.31 / 172.81 W | 159.41 / 180.74 / 184.83 W |

NVIDIA-SMI 数值是整块适配器功耗，会包含桌面合成器和其它 GPU 负载，不能用两模式差值推导播放器自身功耗；进程级可信口径是 Windows GPU Engine 与 GPU committed。当前 SDR 整卡功耗高于 HDR 正说明整卡指标受外部负载影响，不能拿它宣称 HDR 更省电。

HDR 记录结束时的真实诊断为 `d3d11va-copy`、源传递函数 `pq`、活动 LUID 精确匹配、`tone-mapping=hable`、`hdr-compute-peak=yes`，压力保护状态“实时余量正常”，自动回滚原因为“无”。SDR 暗部段为 `d3d11va-copy`、源传递函数 `bt.1886`，HDR 映射保持 `auto`。

## 观感检查

- HDR 后端帧与窗口截图在中点和结束点均能辨认运动细线、棋盘、渐变和主体色块，未见窗口遮挡、尺寸跳变或采证错绑；由于实际输出为 SDR，这只能说明映射后的结构与层次可用，不能证明 HDR 色彩准确。
- SDR 暗部样本的近黑渐变、三组相邻暗灰块和移动灰块在后端帧与窗口中可辨；未启用暗部增强，没有观察到由增强器引入的黑位抬升、灰雾或色偏。这条记录是后续 A/B 的原始参考，不是“暗部增强已完成”。
- 播放窗口与右侧单项队列在两个模式下均无截断、遮挡或溢出，采样期间窗口持续响应。

## HDR 会话压力回滚

`PlayerHdrMappingSafetyCoordinator` 复用既有两秒播放健康样本，不增加逐帧 Flutter 工作：

- 新增解码/输出/总掉帧、缓冲或音视频停滞：立即把当前会话恢复为 mpv `auto`；
- 帧未推进、缓存低于 2 秒或估算 FPS 低于源 FPS 的 95%：连续两个样本才回滚；
- seek 后 3 秒和暂停状态不评估，避免正常交互误触发；
- 回滚锁存到下一媒体，防止同一压力会话反复开关；全局实验开关保持用户原值；
- 新媒体重置计数器，播放器退出/释放期不再评估。

单元测试分别覆盖严重压力立即回滚、中等压力两次回滚、锁存和重置；正常 300 秒 HDR 记录期没有触发回滚。

## 设置与真实点击

主设置首页已按职责拆分：

- “播放与解码”：继续观看、硬件/软件解码与原始码流缓存；
- “视频画质与增强”：比例、Lanczos/Bicubic、输出范围、自动画质、超分与 HDR 实验；
- “播放器交互”：全屏列表和快捷键。

三者仍消费同一 `PlaybackSettings` 快照，不复制保存逻辑。隔离 integration test 真实点击“设置 → 视频画质与增强 → HDR 实验 → 确认 → 关闭”，保存首页、画质页和开关两态四张 PID 绑定截图；未见文字截断、遮挡、横向溢出、对齐或状态反馈问题。

## 后续门槛

1. HDR 实验继续默认关闭，不因本机一次通过就升级为自动默认策略。
2. 暗部增强只在固定 SDR 暗部样本上做关闭/开启 A/B，比较黑位、色带、细节和进程级 GPU 成本；不得与 HDR 或其它第三阶段功能同时试验。
3. 若要验证 HDR 直通，必须在系统 HDR 输出已活动的 10 bit/PQ 显示链路上重新建立 DXGI 输出和长播基线。

本轮未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缓存队列、稳定身份或用户数据。
