# 1080p / 4K 软硬解画质协调基线（2026-07-22）

## 目的与口径

本基线用于约束第二阶段自动画质协调器的最高档位，不代表所有设备。测试在隔离 profile 中固定同一 1080p 类 H.264 样本与同一 4K 类 HEVC 样本，分别使用 `auto-safe` 与 `no`，真实执行进入播放器、队列滚动、两次 seek、全屏往返和诊断采样。

- CPU：Windows 进程 `TotalProcessorTime` 的稳定段中位数，100% 表示占用约一个逻辑核心，不按整机核心数归一化。
- GPU 引擎：该进程全部 `GPU Engine` 实例的 `Utilization Percentage` 合计中位数；多引擎并行时允许超过 100%。
- GPU committed：`GPU Process Memory / Total Committed` 稳定段中位数，只表示显存提交，不冒充 GPU 计算利用率。
- 掉帧：播放器诊断读取 libmpv 的解码、VO 与总掉帧累计值；`VO` 在当前 MediaKit 后端不可用时保持 `empty`，不推测为 0。

## 参考环境

- Windows / MediaKit / libmpv
- GPU：NVIDIA GeForce RTX 4070 SUPER
- GPU 路径实际值：`d3d11va-copy`
- 采样脚本：`tool/run_player_real_library_stress.ps1`
- 隔离证据：`.local/qa/2026-07-22-quality-baseline/`（不提交真实媒体路径与原始截图）

## 稳定段结果

| 分辨率档 | 解码路径 | CPU 中位 | GPU 引擎中位 | GPU committed 中位 | 解码 / 总掉帧 | AV 偏移 | 停滞 |
|---|---|---:|---:|---:|---:|---:|---:|
| 1080p 类 | `d3d11va-copy` | 64.9% | 43.3% | 507.0 MiB | 0 / 0 | 0.000007 秒 | 0 / 0 |
| 1080p 类 | `no` | 142.4% | 1.0% | 108.2 MiB | 0 / 0 | 0.000006 秒 | 0 / 0 |
| 4K 类 | `d3d11va-copy` | 66.5% | 59.2% | 829.4 MiB | 0 / 0 | 0.000028 秒 | 0 / 0 |
| 4K 类 | `no` | 216.1% | 1.0% | 113.1 MiB | 0 / 27 | 0.114115 秒 | 0 / 0 |

## 协调器约束

- 1080p 及以下 GPU 硬解：允许在连续健康样本后逐级启用去块、降噪和适度锐化。
- 1080p 及以下 CPU 软件解码：最多到去块 + 降噪，不自动叠加锐化。
- 4K GPU 硬解：最高只启用去块；CPU 型 libavfilter 会带来额外拷贝和处理成本，不能因当前 0 掉帧就默认全开。
- 4K CPU 软件解码：保持关闭。基线已有 27 帧总掉帧和 0.114 秒 AV 偏移，没有可安全分配给增强滤镜的余量。
- 任意新增掉帧、缓冲、音视频停滞、缓存低于 3 秒或估算 FPS 低于源 FPS 92% 时立即关闭增强；轻度余量不足时降低一级。
- 升级需要连续 8 个扩展样本且两次升级至少间隔 10 秒；播放器每两秒采一个扩展样本，因此不会高频重建滤镜链。

## 第三阶段门槛

AI 超分、时域降噪、运动补帧、HDR 映射与 Vulkan / Compute Shader 在实现前必须由 `PlayerGpuCapabilityDetector` 读取当前 `PlayerBackend` 的真实渲染 API、上下文、硬解与 HDR 源信号。当前契约没有 Compute Shader 能力位，因此该项必须显示“未验证”，不能按显卡型号猜测支持。

## 自动协调器真实窗口复验

- 1080p H.264 / `d3d11va-copy`：连续健康采样后实际档位为“去块 + 降噪 + 锐化”，`vf` 同时包含 `deblock`、`hqdn3d` 与 `unsharp`，解码/总掉帧为 0。
- 4K H.264 / `d3d11va-copy`：实际档位封顶“去块”，`vf` 只包含 `deblock`，解码/总掉帧为 0。
- 两条媒体均读取到 D3D11 Feature Level 12_1；嵌入式输出驱动为 `libmpv` 且 GPU API/上下文属性为空时，仍以该明确能力值确认 GPU 渲染存在，但 Compute Shader 继续显示未验证。
- 证据截图位于 `.local/qa/2026-07-22-quality-live/`，使用隔离 profile 生成且不提交仓库。
