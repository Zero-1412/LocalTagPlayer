# 自然低码率 1080P 压缩画质 A/B（2026-07-27）
>
> 状态：历史 QA/实验记录。当前门禁与优先级以 `docs/qa/`、`ROADMAP.md` 和 QA manifest 为准。

## 结论

真人面部、动画渐变、暗场三类自然内容均完成“关闭 / 清晰增强”真实 Windows
播放器 A/B。六轮均为 0 解码掉帧、0 总掉帧、0 视频/音频停滞，清晰增强始终
实际应用去块、`hqdn3d`、现有轻锐化和保守 GPU 去色带，未触发性能回滚。

额外缩放后锐化没有跨三类内容取得一致收益：动画轮廓略清楚，但真人面部的皮肤与
胡茬压缩纹理变硬，暗场的阴影噪点被放大且没有恢复新细节。因此本轮继续不加入
GLSL 锐化，也不改变现有清晰增强参数。

## 样片与许可

样片只下载、截取和压制到 `.local/qa`，不读取用户媒体库，也不进入 Git。

| 类别 | 开放电影来源 | 参考段 | 实际平均码率 |
|---|---|---:|---:|
| 真人面部 | `Tears of Steel` teaser | 0–5 秒 | 约 492 kbps |
| 动画渐变 | `Sintel` trailer | 31–41 秒 | 约 573 kbps |
| 暗场 | `Tears of Steel` teaser | 30.7–32.8 秒 | 约 250 kbps |

- `Tears of Steel`：Blender Foundation，CC BY 3.0；许可说明为
  <https://mango.blender.org/about/>。
- `Sintel`：Blender Foundation，CC BY 3.0；许可说明为
  <https://durian.blender.org/sharing>。
- 下载地址、署名、截取时间与实际码率保存在
  `.local/qa/natural-compression-ab/natural-compression-ab-summary.json`。

三段统一输出为 1920×1080、H.264、BT.709 limited range，并循环到 35 秒。
播放器在第 12 秒暂停取证，避免运动内容变化伪装成滤镜差异。

## 性能结果

| 类别 | 关闭 | 清晰增强 |
|---|---|---|
| 真人面部 | 0 掉帧，0 停滞 | 0 掉帧，0 停滞 |
| 动画渐变 | 0 掉帧，0 停滞 | 0 掉帧，0 停滞 |
| 暗场 | 0 掉帧，0 停滞 | 0 掉帧，0 停滞 |

所有清晰增强轮次均记录：

```text
mpv 实际硬解: d3d11va-copy
自动画质档位: 去块 + 时空降噪 + 锐化
mpv 去色带: yes
活动 GPU: NVIDIA GeForce RTX 4070 SUPER
活动 GPU 判定: media-kit-angle-d3d11-device:exact-luid-match
```

## 屏幕级观感

后端导出的关闭/清晰增强 PNG 哈希完全相同，说明该接口返回滤镜前视频帧，不能作为
画质证据。本轮改用真实 Windows 窗口截图；鼠标所在的 42px 中心带在数值比较中统一
排除，原始截图保持不修图。

关闭与清晰增强的排除光标后相似度仍很高，符合保守增强预期：

| 类别 | SSIM | PSNR |
|---|---:|---:|
| 真人面部 | 约 0.9928 | 约 47.33 dB |
| 动画渐变 | 约 0.9907 | 约 46.21 dB |
| 暗场 | 约 0.9932 | 约 47.63 dB |

固定帧检查：

- 真人面部：清晰增强略收敛背景压缩波动，五官边缘仍自然；额外 0.18 强度的
  3×3 后锐化让皮肤、胡茬和眼周压缩纹理更硬，没有稳定恢复细节。
- 动画渐变：保守去色带对暖色天空最有价值，现有轻锐化保持龙翼轮廓；额外锐化只
  增强高对比轮廓，不继续改善渐变，并增加边缘振铃风险。
- 暗场：清晰增强没有抬高黑位或产生明显光晕；额外锐化突出绳索、栏杆和阴影噪点，
  但人物衣物与暗部没有出现新的可辨细节。

三组从左到右为“关闭 / 清晰增强 / QA-only 额外后锐化”的合成图位于：

```text
.local/qa/natural-compression-ab/live-face/screen-three-way.png
.local/qa/natural-compression-ab/animation-gradient/screen-three-way.png
.local/qa/natural-compression-ab/dark-scene/screen-three-way.png
```

额外锐化只是对真实窗口截图做的候选模拟，没有进入产品代码或播放器运行时。

## NVIDIA RTX Video 状态

本机为 RTX 4070 SUPER、595.97 驱动；真实会话已精确匹配该卡并使用
`d3d11va-copy`。这只能证明 NVIDIA GPU 正在承担解码/渲染，不能证明 RTX Video
Super Resolution 正在运行。

本机 NVIDIA App 11.0.7.247 的“系统 → 视频”只读检查显示：

```text
超分辨率：关
HDR：已禁用
```

截图位于 `.local/qa/natural-compression-ab/nvidia-video-status.png`。当前项目的
“GPU 画质超分”实际是 libmpv `ewa_lanczossharp + sigmoid-upscaling`，且只在画面
被放大时运行；它不是 NVIDIA RTX Video AI。当前播放器也没有接入 NVIDIA RTX
Video SDK，所以 NVIDIA App 不显示增强活动属于预期行为。

RTX Video SDK 若进入后续评估，必须作为独立的 Windows/NVIDIA 可选后端处理：
先确认 SDK 许可与可分发依赖，再验证 D3D11 纹理输入输出、非 NVIDIA 回退、三类
自然片源观感、掉帧和功耗；不能把 GPU 占用或 NVIDIA 品牌当作功能已生效的证据。

## 复跑

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tool\run_natural_compression_quality_ab.ps1 `
  -DurationSeconds 20 -VideoBitrateKbps 650
```

只重建样片与汇总、复用已有播放器报告时：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tool\run_natural_compression_quality_ab.ps1 `
  -DurationSeconds 20 -VideoBitrateKbps 650 -SkipPlayback
```

真实屏幕截图观察器会让 Flutter 测试进程在退出校验时报告外部
`SemanticsHandle` 仍活动，因此截图轮次只作为观感证据；六轮性能结论来自不连接
桌面观察器的独立通过轮次，不能把两类运行混为同一测试结果。
