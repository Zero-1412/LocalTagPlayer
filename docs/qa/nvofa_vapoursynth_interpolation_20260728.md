# NVOFA VapourSynth 2× 中间帧本机原型验证

日期：2026-07-28

## 结论

Windows 本机原型已经从“能执行 NVOFA 光流”推进到“能在真实 mpv 播放链生成
中间帧”。固定 libmpv 通过 VapourSynth R78 把连续帧交给隔离插件；插件分别执行
A→B 与 B→A 两次 NVIDIA Optical Flow，并在 0.5 时间点双向 warp，输出
24fps→48fps。真实 H.264 帧、精确 seek、同进程 reload、关闭移除和失败回退均
通过。

这不是已发布功能。当前帧链为：

```text
mpv / D3D11VA
→ VapourSynth 软件帧
→ luma 上传 CUDA
→ NVOFA 前向 + 后向光流
→ 光流回读
→ CPU 并行双向 warp
→ VapourSynth 48fps 软件帧
→ gpu-next / D3D11 child HWND
```

因此“光流计算”确实使用 NVIDIA OFA，但整条合成链还不是 non-copy D3D11，也
不能标成完全 GPU 插帧。

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
- 现有本机视频增强 ABI v1 不变，没有把多帧/时间戳偷偷塞进单帧原位纹理 ABI。

输出时间线保持偶数帧为源帧，奇数帧为生成帧。平均 luma 差异达到保守阈值时，
奇数帧复制前帧并写入 `LTPNVOFASceneCut=1`，防止跨镜头混合。其它帧写入：

```text
LTPNVOFAInterpolated
LTPNVOFASceneCut
LTPNVOFAProcessUs
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

匿名汇总位于 `.local/qa/nvofa-motion-ab/summary.json`，复跑命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool/run_nvofa_motion_ab.ps1 -DurationSeconds 20
```

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
- 架构合同：QA-only、无 install、双向 execute、结构化 user-data；
- VSR + TrueHDR 同会话三类六组门禁（独立能力链）。
- `flutter analyze`、297 项全量测试（另 3 项按既有条件跳过）；
- `flutter build windows --debug`；
- 正式 Debug bundle 不含 NVOFA、CUDA、VapourSynth 或 VSScript 文件；
- 四个新增/扩展 QA PowerShell 脚本语法解析。

产品入口仍保持关闭，下一阶段至少需要：

1. 按活动 D3D11 adapter LUID 创建同设备资源，禁止固定 CUDA device 0；
2. 去除软件帧和光流回读，把 warp/遮挡处理迁到 D3D11 compute；
3. 增加前后向一致性、遮挡 mask 与显露区域处理，而不只做双向平均；
4. 对快速平移、细栅栏、字幕、运动模糊和切场附近做连续视频审查；
5. 重跑全屏、跨 DPI、快速切换、音画同步、退出和三类六组性能门禁；
6. 全部通过后才设计用户入口、自动回退和发布许可，不提前持久化设置。

默认 MediaKit、Windows 后端选择、filtered queue、当前 index、返回媒体库状态、
SQLite、标签、缓存队列和用户数据均未改变。
