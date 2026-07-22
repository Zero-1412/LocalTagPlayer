# Windows 原生 GPU 能力矩阵（2026-07-22）

## 目的与边界

本矩阵是第三阶段运动补帧、时域降噪和 HDR 映射的前置设备证据。它通过真实 `PlayerBackend`、Windows runner、DXGI、D3D11 和系统 Vulkan loader 生成，不按显卡名称推测能力。

矩阵描述系统当前可见设备，不等价于播放器当前活动适配器。多硬件卡无法唯一匹配时，Compute 增强必须保持关闭。探测不读取媒体库或媒体路径；DXGI LUID 只对当前 Windows 会话有意义，因此不写入本文、不进入设置或数据库。

## 复现命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run_gpu_capability_matrix.ps1 `
  -OutputPath ".local/qa/2026-07-22-gpu-matrix/device-matrix.json"
```

integration test 会验证至少存在一块硬件适配器，所有设备名称、vendor/device ID、显存值和 D3D Feature Level 均可解析，再保存隐私安全 JSON。完整回归为 247 项测试通过、3 项显式 benchmark 跳过，`flutter analyze` 与 Windows Debug build 通过。

## 当前设备矩阵

| DXGI 序号 | 适配器 | 类型 | 专用显存 | 共享内存上限 | 本地预算 / 探测时占用 | D3D | Compute | Vulkan |
|---:|---|---|---:|---:|---:|---|---|---|
| 0 | NVIDIA GeForce RTX 4070 SUPER | 硬件 | 11.72 GiB | 31.56 GiB | 10.97 GiB / 7.74 MiB | 12_1 | 已验证 | 1.4.329 |
| 1 | AMD Radeon(TM) Graphics | 硬件 | 459.77 MiB | 31.56 GiB | 31.26 GiB / 0 B | 12_1 | 已验证 | 1.3.302 |
| 2 | Microsoft Basic Render Driver | 软件 | 0 B | 31.56 GiB | 30.81 GiB / 0 B | 12_1 | 已验证但不参与硬件选择 | 未匹配 |

`vulkan-1.dll` 可加载，Vulkan instance 创建与物理设备枚举成功。Vulkan 物理设备按 vendor/device ID 分别匹配 NVIDIA 与 AMD；软件适配器未匹配 Vulkan 设备。

显存预算来自 `IDXGIAdapter3::QueryVideoMemoryInfo`，属于操作系统对当前进程的动态预算，数值会随系统负载变化；表中占用只是探测瞬间快照，不作为播放峰值基线。

## 活动适配器判定

当前机器存在两块硬件适配器，且两者 D3D Feature Level 都是 12_1。现有 MediaKit/libmpv 会话只报告 D3D Feature Level，不能据此唯一选择 NVIDIA 或 AMD，因此诊断结论为：

```text
GPU 设备已枚举，活动适配器尚未唯一确认
```

这意味着系统能力位已经建立，但运动补帧、时域降噪和 HDR 映射仍不能启动。下一步必须由当前渲染边界返回活动 adapter LUID，再叠加 1080p / 4K Compute 帧预算和掉帧回退门槛。

## 真实窗口复验

- 使用隔离 Debug profile 打开 1080p H.264，实际硬解为 `d3d11va-copy`，播放器持续推进，解码/总掉帧均为 0。
- 右键打开“诊断检查”并滚动详细指标，确认原生探测 `ready`、设备数量 3、Vulkan loader / instance 为“是 / 是”、活动 GPU 为“未唯一确认”。
- RTX、AMD 与软件适配器三条矩阵没有弹窗越界、横向溢出或互相遮挡；滚动期间视频继续播放，UI 操作正常响应。
- 截图位于 `.local/qa/2026-07-22-gpu-matrix/player-diagnostics-device-matrix.png` 与 `player-diagnostics-adapter-matrix.png`，隔离证据不提交仓库。

## 暗部增强独立基线

暗部增强不是“显卡支持 Compute”即可启用的功能。它需要独立固定 SDR 暗场样本，至少比较：

- 暗部纹理与噪声是否真实保留；
- 黑位是否被抬升、灰雾化或发生色带；
- 1080p / 4K 的 CPU、GPU、显存、解码/输出/总掉帧；
- 拖动进度、滚动队列、打开设置时的 UI 响应；
- 自动协调器降级后能否完整恢复原画。

在该观感与性能基线完成前，暗部增强不进入自动画质协调器，也不与第三阶段功能同时试验。
