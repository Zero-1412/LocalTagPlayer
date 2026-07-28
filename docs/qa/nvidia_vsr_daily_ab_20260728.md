# NVIDIA RTX 视频超分日常开启 A/B

## 结论

NVIDIA RTX 视频超分（VSR）已经具备当前 Windows 增强后端的可交付条件，但不适合
作为所有视频的日常默认：

- 默认保持关闭，仅保存当前播放会话。
- 低码率画面明显偏软、且显示尺寸大于源分辨率时，建议按需开启。
- 真人面部会变清晰，但低码率皮肤纹理也可能变硬；暗场收益很小。
- 已经清晰的高码率片源、暗场或对压缩纹理敏感的真人内容，建议保持关闭。

RTX Video HDR 是另一项独立的当前可交付能力，继续要求 Windows HDR、10-bit
输出、明确 SDR 源和无冲突滤镜，且同样默认关闭。

## 测试边界

测试设备与播放链：

```text
NVIDIA GeForce RTX 4070 SUPER
mpv v0.41.0-908-g48e6c35c0
d3d11va（非 copy）
→ d3d11vpp=scale=2:scaling-mode=nvidia:format=nv12
→ gpu-next / D3D11 child HWND
```

三段样本均为真实开源电影素材的低码率 1080P24 截取，关闭/开启各播放 20 秒：

| 样本 | 视频码率 | 容器码率 | 时长 |
|---|---:|---:|---:|
| 真人面部 | 486.2 kbps | 488.7 kbps | 35 秒 |
| 动画渐变 | 570.4 kbps | 572.7 kbps | 35 秒 |
| 暗场 | 247.4 kbps | 250.0 kbps | 35 秒 |

样本来自 CC BY 3.0 的 Tears of Steel 与 Sintel，仓库只在忽略目录生成 QA
转码样本，不读取用户媒体库。

## 固定帧与性能结果

旧 A/B 使用 `mpv screenshot video`，关闭组得到 1920×1080、开启组得到
3840×2160，而且没有锁定同一媒体时间，不能作为观感结论。本轮修正为：

- 两侧都在媒体第 12 秒生成完成标记。
- 测试进程绑定目标窗口，以 `PrintWindow(PW_RENDERFULLCONTENT)` 捕获最终
  Windows 表面。
- 只有 off/on 截图尺寸完全相同时，视觉门禁才通过。
- 性能仍独立采样 20 秒，不以截图替代掉帧和停滞门禁。

| 样本 | off/on 截图 | off/on 总掉帧 | 视频停滞 | 音频停滞 | VSR 开启确认 |
|---|---:|---:|---:|---:|---:|
| 真人面部 | 1920×1080 | 0 / 0 | 0 / 0 | 0 / 0 | active |
| 动画渐变 | 1920×1080 | 0 / 0 | 0 / 0 | 0 / 0 | active |
| 暗场 | 1920×1080 | 0 / 0 | 0 / 0 | 0 / 0 | active |

汇总位于 `.local/qa/nvidia-vsr-daily-ab/summary.json`，六张最终窗口截图位于对应
样本的 `nvidia-off` / `nvidia-on` 子目录。复跑命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool/run_nvidia_scaling_ab.ps1 `
  -DurationSeconds 20 `
  -OutputDirectory .local/qa/nvidia-vsr-daily-ab
```

## 肉眼 A/B

- 真人面部：头发、眼部轮廓和胡须边缘更清楚，没有明显光晕；同时皮肤和胡须区域
  的低码率块状/粗糙纹理也更容易看到，不是无条件正收益。
- 动画渐变：翼缘、爪部和角色轮廓有轻微改善；大面积渐变基本不变，没有新增明显
  色带或描边光晕。
- 暗场：差异接近不可见；没有发现黑位抬升或噪点被明显放大，但也不足以支持日常
  常开。

测试时 Windows 桌面 HDR 已开启，`PrintWindow` 会让部分高亮区域在 PNG 中显得
过曝。因为 off/on 使用相同输出状态，这些图仍可比较边缘和压缩纹理，但不能作为
色彩准确度或 HDR 亮度证据。4K 全屏下 VSR 可能更容易显示收益，可作为后续观感
补测，不作为本次发布门禁。

## 发布范围

- VSR/HDR 从界面文案中的“实验”收敛为当前 NVIDIA 能力，但仍由 Windows 原生
  增强后端、硬件/源信号门禁、掉帧熔断和会话回滚保护。
- NVOFA 插帧保留为独立长期研究，不进入产品入口、不进入安装包，也不阻塞发布。
- patched libmpv D3D11 hwframe 钩子不再是自动后续任务；只有未来显式重启
  NVOFA 研究时才重新评估。
- 默认 MediaKit、其他平台、插件 ABI v1、filtered queue、SQLite、标签、缓存
  队列和用户数据均不改变。

## UI 与验证

- 真实 Windows integration test 从播放器齿轮打开一级设置，并在原生 child HWND
  按 airspace 规则隐藏后捕获 Flutter 最终合成层。VSR/HDR 标题完整，VSR 的按需
  开启说明自然换行；循环开关和“更多播放设置”入口没有遮挡、错位或溢出。
- UI 截图位于
  `.local/qa/nvidia-vsr-release-ui/nvidia-off-player-settings.png`。
- `flutter analyze`、298 项全量测试（另 3 项按既有条件跳过）、Windows Debug
  build、PowerShell 语法和 1 项真实 Windows 集成测试均通过。
