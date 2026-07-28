# NVOFA VapourSynth 2× 中间帧本机原型验证

日期：2026-07-28

## 结论

Windows 本机原型已经从“能执行 NVOFA 光流”推进到“在活动 mpv D3D11 GPU 上
生成中间帧”。固定 libmpv 通过 VapourSynth R78 把连续帧交给隔离插件；插件分别
执行 A→B 与 B→A 两次 NVIDIA Optical Flow，并由同 LUID 的 D3D11 Compute 在
0.5 时间点双向 warp。两次 execute 同时输出硬件 cost；三段 shader 依次完成
forward-backward 校验与局部矢量补洞、平均为主的候选 warp 与遮挡有效性、
图像域 hole filling，输出 24fps→48fps。真实 H.264 帧、精确 seek、同进程
reload、关闭移除和失败回退均通过。

这不是已发布功能。当前帧链为：

```text
mpv / D3D11VA
→ VapourSynth 软件帧
→ luma 上传 CUDA
→ NVOFA 前向 + 后向光流
→ 光流回读
→ 光流上传到同 LUID D3D11 设备
→ D3D11 Compute 双向 warp
→ 最终 8-bit 平面读回
→ VapourSynth 48fps 软件帧
→ gpu-next / D3D11 child HWND
```

因此光流和逐像素 warp 都已使用同一块 NVIDIA GPU，但整条合成链仍不是
non-copy D3D11，也不能标成全程零复制硬件插帧。

## 当前三段遮挡处理

实现阶段参考 NVIDIA 官方 FRUC Programming Guide：

1. 生成前向/后向光流；
2. 用 forward-backward consistency 拒绝无效向量；
3. 把无效向量补为稠密光流；
4. 生成中间图像；
5. 在图像域填补显露区域空洞。

官方资料：

- <https://docs.nvidia.com/video-technologies/optical-flow-sdk/nvfruc-programming-guide/index.html>
- <https://developer.nvidia.com/blog/whats-new-in-optical-flow-sdk-3-0/>
- <https://github.com/NVIDIA/NVIDIAOpticalFlowSDK>

仓库没有下载、链接或分发需要 NVIDIA Developer Program 许可的 FRUC SDK。
当前三段 Compute 只是按公开阶段实现的开放近似，不能以官方 FRUC 的名义发布：

```text
raw forward/backward flow + UINT8 cost
→ flow-grid consistency + local vector infill
→ conservative midpoint warp + per-pixel validity
→ image-domain hole fill for low-validity pixels
→ final R32 plane readback
```

确定性探针在 RTX 4070 SUPER 的固定 LUID 上得到：

```text
d3d11-warp-occlusion=passed
zero-blend=128
consistent-motion=90
unreliable-side=117
vector-infill=90
image-hole-fill=201
luid=00000000:00017093
```

旧的三项基线保持不变；新增两项分别证明单个坏光流格会从一致邻域恢复，以及
高反差显露边界会离开中灰双影风险值。探针前置脚本必须同时匹配 90/201，
不能仅因 shader 能编译就通过。

## 实现边界

- CMake 目标 `ltp_nvofa_vapoursynth_plugin` 只有显式
  `LTP_BUILD_NVOFA_VAPOURSYNTH_PLUGIN=ON` 才生成；
- 目标为 `MODULE EXCLUDE_FROM_ALL`，没有 install 规则；
- 只从 System32 动态加载 `nvcuda.dll` 与 `nvofapi64.dll`；
- 构建使用固定提交的 NVIDIA BSD-3-Clause 公开头文件，仓库和应用包不携带头文件
  或厂商 DLL；
- R78 只在被忽略的本机 QA 目录，未修改 PATH/注册表，也未进入 Flutter bundle；
- Flutter 只发送布尔启停意图，插件 DLL 绝对路径由原生宿主通过结构化
  `user-data` 交给脚本；
- child HWND 先以 DXGI 1.6 高性能顺序选择唯一 NVIDIA 适配器，mpv 通过
  `d3d11-adapter` 使用它；CUDA 通过 `cuDeviceGetLuid` 精确匹配相同 LUID；
- 多块同名 NVIDIA 适配器会拒绝启用，必要时可由
  `LOCAL_TAG_PLAYER_NVIDIA_ADAPTER_LUID` 显式指定；
- 现有本机视频增强 ABI v1 不变，没有把多帧/时间戳偷偷塞进单帧原位纹理 ABI。

输出时间线保持偶数帧为源帧，奇数帧为生成帧。平均 luma 差异达到保守阈值时，
奇数帧复制前帧并写入 `LTPNVOFASceneCut=1`，防止跨镜头混合。其它帧写入：

```text
LTPNVOFAInterpolated
LTPNVOFASceneCut
LTPNVOFAProcessUs
LTPNVOFAAdapterMatched
LTPNVOFACudaDeviceIndex
LTPNVOFAD3D11Warp
LTPNVOFAConsistencyProtected
```

## 同 LUID 与 D3D11 Compute 结果

RTX 4070 SUPER 的真实 execute、VapourSynth 和完整播放器报告一致：

```text
d3d11-luid=00000000:00017093
cuda-luid=00000000:00017093
luid-match=passed
d3d11-warp=passed
```

固定 `cs_5_0` shader 使用 `R8_UNORM` 输入、`R16G16_SINT` 双向原始光流、
`R8_UINT` 双向 cost、`R32G32B32A32_FLOAT` resolved-flow/候选纹理和
`R32_FLOAT` 最终 UAV；任一设备创建、shader 编译、资源上传、dispatch、map
或读回失败都会让滤镜报错并触发既有会话回滚，没有静默 CPU 路径。

三类 650 kbps、1920×1080 片源的 4 秒实时窗口复测为：

| 样本 | 媒体秒数 | 墙钟秒数 | 窗口新增掉帧 |
|---|---:|---:|---:|
| 真人面部 | 4.000 | 3.996 | 0 |
| 动画渐变 | 4.000 | 3.998 | 0 |
| 暗场 | 4.000 | 3.995 | 0 |

上一阶段六组 20 秒完整播放器 A/B 位于
`.local/qa/nvofa-consistency-bound-final/summary.json`。三类均为
off 24fps / on
48fps、off/on 总掉帧 0/0、on 音频/视频停滞 0/0，六组活动 GPU 均由
`windows-native-mpv-selected-d3d11-adapter` 报告同一 LUID。共生成六份匿名
报告和六张正常出画截图，六个播放器进程均完成 stop/dispose/exit。

## 被拒绝的强加权版本

第一版一致性实现会二次反推光流源坐标，并按 cost/一致性置信度强选单侧样本。
它通过了确定性探针、24→48fps 和零掉帧门禁，却在动画片源的翼缘与显露区域
产生清楚可见的锯齿暗拖影。技术门禁不能覆盖这类质量回归，因此该版本被拒绝。

最终 shader 保留原先已验证的中点光流取样。等权合成占 85%，可靠性只修正剩余
15%，最终比例限制在 42.5%–57.5%。确定性探针结果为：

```text
d3d11-warp-confidence=passed
zero-blend=128
consistent-motion=90
unreliable-side=117
```

相对旧版动画开启截图，最终版本 SSIM 为 0.9981、PSNR 为 57.68 dB；被拒绝
版本只有 0.9943 / 40.44 dB。数值只用于量化“是否偏离已通过基线”，质量判断仍
以翼缘拖影的人工 A/B 为准。该保护不能替代 NVIDIA FRUC 指南所描述的无效矢量
剔除、矢量补洞和图像域 hole filling。

当前版本已实现上述两级补洞近似，仍不代表达到了官方 FRUC 的质量或许可边界。

## 当前自然片源与连续压力 A/B

当前插件 SHA-256 为：

```text
aaea83ae158818755b1ea7846a7363f3b583c8a68f6c87f6c22ea5a0fc986f31
```

三类 650 kbps 自然片源的六组证据位于
`.local/qa/nvofa-occlusion-natural-final/results/summary.json`：

| 样本 | off/on FPS | off/on 总掉帧 | on 视频/音频停滞 |
|---|---:|---:|---:|
| 真人面部 | 24 / 48 | 0 / 0 | 0 / 0 |
| 动画渐变 | 24 / 48 | 0 / 0 | 0 / 0 |
| 暗场 | 24 / 48 | 0 / 0 | 0 / 0 |

五类匿名 1080P24 连续压力样本的十组证据位于
`.local/qa/nvofa-occlusion-stress-final/results/summary.json`：

| 样本 | 质量焦点 | off/on FPS | off/on 总掉帧 |
|---|---|---:|---:|
| 快速横移 | 大位移、边界和显露区域 | 24 / 48 | 0 / 0 |
| 2px 细栅栏 | 高频误配和断线 | 24 / 48 | 0 / 0 |
| 固定字幕 | 静态文字/运动背景分层 | 24 / 48 | 0 / 0 |
| 运动模糊 | 模糊轮廓和重影 | 24 / 48 | 0 / 0 |
| 重复切镜 | 跨场景错误合成 | 24 / 48 | 0 / 0 |

16 组都报告 `windows-native-mpv-selected-d3d11-adapter` 和同一 LUID
`00000000:00017093`，on 侧音视频停滞均为 0。该 mpv 构建没有提供 decoder/
output 分项掉帧，因此 schema 5 保留 `null`，只把实际可读的
`totalDroppedFrames=0` 当门禁，不能把不可用字段写成 0。

固定奇数帧人工审查未发现新增脸部撕裂、动画翼缘暗边、暗场亮斑、细线断裂、
字幕漂移或跨切镜混合；切镜 off/on SSIM 为 0.999906。运动模糊样本自身含五帧
曝光，单帧 A/B 不能证明产品级稳定收益，因此摘要明确记录
`productEnablement=blocked`。

压力首轮在尚未启用插件的 off 组发生一次原生宿主 `0xc0000005` 启动崩溃。
Windows 事件日志定位到 `local_tag_player.exe`/unknown module；同条件最小复现
完整通过，随后 16 组最终证据也全部完成。这不是 shader 质量失败，但属于
child HWND 生命周期风险，仍阻止产品入口开放。

压力样本复跑命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool/generate_nvofa_motion_stress_samples.ps1 `
  -DurationSeconds 20 -VideoBitrateKbps 6000
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool/run_nvofa_motion_ab.ps1 -DurationSeconds 20 `
  -OutputDirectory .local/qa/nvofa-occlusion-stress-final/results `
  -CaseManifest .local/qa/nvofa-motion-stress/samples/manifest.json
```

## 首次失败与性能修复

单线程 CPU warp 没有通过真实 1080P 门禁：

```text
7 秒墙钟时间只推进到 3.52083 秒
output frame drops = 97
```

该版本没有被开放。warp 改为每 16 行一个任务并行后，三类 650 kbps、1920×1080
片源的 4 秒 1× 实时窗口结果为：

| 样本 | 媒体秒数 | 墙钟秒数 | 窗口新增掉帧 |
|---|---:|---:|---:|
| 真人面部 | 4.000 | 3.998 | 0 |
| 动画渐变 | 4.021 | 4.016 | 0 |
| 暗场 | 4.021 | 4.010 | 0 |

## 三类六组长播 A/B

每类关闭/开启各播放 20 秒，并在 12.020833 秒导出中间帧：

| 样本 | off/on 实测 FPS | off/on 总掉帧 | on 视频停滞 | on 音频停滞 |
|---|---:|---:|---:|---:|
| 真人面部 | 24 / 48 | 0 / 0 | 0 | 0 |
| 动画渐变 | 24 / 48 | 0 / 0 | 0 | 0 |
| 暗场 | 24 / 48 | 0 / 0 | 0 | 0 |

匿名汇总位于
`.local/qa/nvofa-consistency-bound-final/summary.json`，复跑命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool/run_nvofa_motion_ab.ps1 -DurationSeconds 20 `
  -OutputDirectory .local/qa/nvofa-consistency-bound-final
```

摘要 schema 4 记录插件 SHA-256
`4b55e595947f7e77988e4c3bfcbc1c35064e4c041088b7aabc044777e6b588db`；
六个分组各自的 `plugin-sha256.txt` 都与摘要及当前插件二进制一致。续跑只接受
同 hash 的报告、完整截图和成功日志，不能跨 shader 实现复用旧证据。

固定帧人工检查：

- 真人：眼睛、鼻翼、嘴唇和发际线未见明显双影，肤色没有局部断裂；
- 动画：主体移动到两个源帧之间，翼膜和外轮廓未见明显撕裂或双轮廓；
- 暗场：黑位没有被抬亮，绳索、栏杆和人物边缘未见明显混脏。

off/on 单帧 PSNR 约为 46.94、26.05、53.50 dB，只证明输出不是同帧复制。因为
24fps 样本没有真实 48fps 中点真值，这些数值不能作为质量高低评分；人工单帧也
不能替代长运动序列的遮挡/显露区域审查。

## 启停时序修复

Windows 方法命令和只读属性快照通过不同平台消息返回。真实测试发现启用命令已经
排队，但 Dart 紧邻读回仍可能看到旧的 `ready`，从而返回 `applied=false`。
`WindowsNativePlayerBackend` 现在最多等待 2 秒，只有读回
`requested/active + enabled=true` 才确认成功；fallback/unavailable 立即停止
等待。命令投递本身仍不被当成成功。

## 验证与未完成门禁

已通过：

- NVOFA CUDA execute；
- 插件 Debug/Release 构建；
- 24→48fps、seek、reload、关闭回退；
- 三类 1080P 实时门禁；
- 三类六组 20 秒长播 A/B；
- NVOFA 双向 cost、前后向一致性与保守合成比例；
- flow-grid 局部矢量补洞、遮挡有效性与图像域 hole filling；
- 独立 D3D11 确定性探针；
- 五类连续运动压力片十组 A/B；
- 架构合同：QA-only、无 install、双向 execute、结构化 user-data；
- VSR + TrueHDR 同会话三类六组门禁（独立能力链）。
- `flutter analyze`、297 项全量测试（另 3 项按既有条件跳过）；
- `flutter build windows --debug`；
- 正式 Debug bundle 不含 NVOFA、CUDA、VapourSynth 或 VSScript 文件；
- 五个相关 QA PowerShell 脚本语法解析；
- 正式 Debug bundle 的 48 个文件不含 NVOFA、CUDA、VapourSynth、VSScript
  或 Optical Flow 文件。

产品入口仍保持关闭，下一阶段至少需要：

1. 去除 VapourSynth 软件帧、CUDA 光流回读和最终平面读回；
2. 对本次一次性 `0xc0000005` 做多轮启动/退出、全屏、跨 DPI、快速切换 soak；
3. 用具备真实高帧率中点真值的自然片源补充时序质量指标，而非只看单帧；
4. 确认 NVIDIA Optical Flow/FRUC 发布许可，或继续保持零厂商文件分发；
5. 全部通过后才设计用户入口、自动回退和持久化设置。

默认 MediaKit、Windows 后端选择、filtered queue、当前 index、返回媒体库状态、
SQLite、标签、缓存队列和用户数据均未改变。
