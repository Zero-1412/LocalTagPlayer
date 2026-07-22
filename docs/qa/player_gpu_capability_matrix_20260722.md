# Windows 原生 GPU 能力矩阵（2026-07-22）

## 目的与边界

本矩阵是第三阶段运动补帧、时域降噪和 HDR 映射的前置设备证据。它通过真实 `PlayerBackend`、Windows runner、DXGI、D3D11 和系统 Vulkan loader 生成，不按显卡名称推测能力。

矩阵描述系统当前可见设备，实际活动显卡另由 MediaKit / ANGLE 的真实 D3D11 device 返回。探测和 benchmark 不读取媒体库或媒体路径；DXGI LUID 只对当前 Windows 会话有意义，只用于本次 QA 精确匹配，不进入设置或数据库。

## 复现命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run_gpu_capability_matrix.ps1 `
  -OutputPath ".local/qa/gpu-capability-matrix/active-device-compute-budget.json"
```

integration test 会创建真实 MediaKit 视频纹理，验证活动 LUID 在设备矩阵中唯一匹配，再在该 LUID 上运行 1080p / 4K Compute GPU 时间戳基线并保存隐私安全 JSON。普通应用启动不会自动运行此 benchmark。

## 当前设备矩阵

| DXGI 序号 | 适配器 | 类型 | 专用显存 | 共享内存上限 | 本地预算 / 探测时占用 | D3D | Compute | Vulkan |
|---:|---|---|---:|---:|---:|---|---|---|
| 0 | NVIDIA GeForce RTX 4070 SUPER | 硬件 | 11.72 GiB | 31.56 GiB | 10.97 GiB / 7.74 MiB | 12_1 | 已验证 | 1.4.329 |
| 1 | AMD Radeon(TM) Graphics | 硬件 | 459.77 MiB | 31.56 GiB | 31.26 GiB / 0 B | 12_1 | 已验证 | 1.3.302 |
| 2 | Microsoft Basic Render Driver | 软件 | 0 B | 31.56 GiB | 30.81 GiB / 0 B | 12_1 | 已验证但不参与硬件选择 | 未匹配 |

`vulkan-1.dll` 可加载，Vulkan instance 创建与物理设备枚举成功。Vulkan 物理设备按 vendor/device ID 分别匹配 NVIDIA 与 AMD；软件适配器未匹配 Vulkan 设备。

显存预算来自 `IDXGIAdapter3::QueryVideoMemoryInfo`，属于操作系统对当前进程的动态预算，数值会随系统负载变化；表中占用只是探测瞬间快照，不作为播放峰值基线。

## 活动适配器判定

MediaKit 的实际 `ANGLESurfaceManager::CreateD3DTexture()` 在创建 D3D11 device 后通过 `IDXGIDevice::GetAdapter()` 取得真实 adapter。当前生产纹理返回：

```text
source = media-kit-angle-d3d11-device
LUID   = 00000000:00016bec
match  = NVIDIA GeForce RTX 4070 SUPER
```

这消除了 RTX 与 AMD 同为 D3D 12_1 时的歧义。构建期只对已固定 SHA256 的单个上游源文件做可审计补丁，不写入 Pub Cache；若上游标记片段变化，CMake 配置直接失败。

## 当前显示输出

DXGI 探针在每块 adapter 下枚举 `IDXGIOutput`，并用 `IDXGIOutput6::GetDesc1` 返回当前桌面输出；该数据与显卡 Compute/Vulkan 能力分开，不从媒体色彩参数推断：

| 活动 adapter 输出 | 桌面 | 位深 | 色彩空间 | HDR 信号 | 最小 / 峰值 / 全屏峰值亮度 |
|---|---:|---:|---|---|---:|
| `\\.\DISPLAY1` | 3840×2160 | 8 bit | `rgb-full-g22-p709` | 未活动 | 0.01 / 417 / 417 nits |

当前固定 HDR10/PQ 样本因此属于播放器 HDR 映射到 SDR 输出的验证，不是 HDR passthrough。输出证据随当前桌面配置变化，应在显示设置、线缆或显示器变化后重新采集。

## 1080p / 4K Compute 帧预算

基线在上述活动 LUID 上创建独立 D3D11 compute device，运行与 HDR 映射相近的逐像素 Hable 类 kernel。每档 3 次预热、16 次正式样本，只用 `D3D11_QUERY_TIMESTAMP` 统计 GPU dispatch，不把纹理分配或 CPU 提交时间冒充 GPU 成本。

| 分辨率 | 中位 GPU | P95 GPU | 最大 GPU | 60fps 帧预算 | Compute 预留切片 | 结论 |
|---|---:|---:|---:|---:|---:|---|
| 1920×1080 | 0.025ms | 0.036ms | 0.036ms | 16.667ms | 4.167ms（25%） | 通过 |
| 3840×2160 | 0.117ms | 0.129ms | 0.129ms | 16.667ms | 4.167ms（25%） | 通过 |

该结论只代表当前设备、驱动与 kernel 的显式 QA，不代表所有显卡，也不能替代真实 HDR 长播、功耗和显示输出验证。

## 第三阶段单项实验

本轮只选择 HDR 动态映射，运动补帧和时域降噪保持未启动。设置默认关闭，启用前显示影响与回滚确认；真实播放还必须同时检测到 HDR 源、精确活动 LUID 和 Compute 能力，才应用 `tone-mapping=hable`、`hdr-compute-peak=yes`。关闭或门槛未通过时恢复 `tone-mapping=auto`、`hdr-compute-peak=auto`。

[mpv 官方手册](https://mpv.io/manual/stable/)明确说明 `hdr-compute-peak` 需要 Compute Shader，且部分驱动可能表现很差；因此本项目不把系统“支持 Compute”直接解释为应默认开启，而是保留显式基线、用户确认和完整回滚。

真实 MediaKit/libmpv integration test 已验证 `hable/yes → auto/auto`；设置页真实点击截图保存在 `.local/qa/hdr-mapping/hdr-mapping-enabled.png` 与 `hdr-mapping-rollback.png`。固定 HDR 300 秒长播、运行时压力回滚和独立 SDR 暗部基线见 `player_hdr_sdr_baseline_20260722.md`。

活动 LUID / Compute 基线 integration test 现同时断言活动 adapter 至少返回一个有效桌面输出及其尺寸、位深和色彩空间；完整验证结果见 `CURRENT_TASK.md`。

## 设备矩阵真实窗口复验

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

固定 SDR 暗部关闭态的 180 秒原始基线已经完成，近黑梯度与相邻灰阶可辨，36 个诊断样本为 0 掉帧、0 停滞；详见 `player_hdr_sdr_baseline_20260722.md`。暗部增强仍未实现，下一步必须在同一样本上做关闭/开启 A/B，未通过前不进入自动画质协调器，也不与第三阶段功能同时试验。
