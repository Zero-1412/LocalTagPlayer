# Windows 原生 libmpv NVIDIA RTX Super Resolution 集成验证
>
> 状态：历史 QA/实验记录。当前门禁与优先级以 `docs/qa/`、`ROADMAP.md` 和 QA manifest 为准。

## 结论

Windows 原生 child HWND 后端已经建立并验证：

```text
d3d11va（非 copy）
→ mpv d3d11vpp
→ scaling-mode=nvidia
→ gpu-next / D3D11 child HWND
```

本机 RTX 4070 SUPER 的六组真实播放均收到 mpv verbose 日志中的固定成功事件，
原生层将其归一化为 `native-nvidia-vsr-state=active`。该状态证明 NVIDIA 驱动
RTX Super Resolution 已实际启用，不再只依赖 `vf` 字符串推断。

## 安全边界

- 原生层不把 verbose 日志回传 Flutter，只匹配固定成功文本并输出
  `inactive / requested / active / rejected`。
- 开关只在 Windows、mpv 0.39+、原生 `gpu-next/D3D11` child HWND、
  `hwdec-current=d3d11va`、无 CPU `lavfi` 冲突时可用。
- 热切换最多重试 5 次“写入 → 等待 200 ms → 读回”；未读回完整 NVIDIA
  滤镜图时立即清空 `vf`。
- NVIDIA 模式继续与压缩增强、暗场增强互斥，并接受既有掉帧/停滞熔断。
- 这是 mpv 调用 NVIDIA 驱动扩展，不捆绑、不下载、不分发 RTX Video SDK。

## 三类自然低码率 A/B

样本均为 650 kbps 低码率 1080P，每类分别运行关闭和开启 20 秒：

| 样本 | 开启组驱动确认 | 关闭/开启总掉帧 | 视频停滞 | 音频停滞 | 回滚 |
|---|---:|---:|---:|---:|---:|
| 真人面部 | active | 0 / 0 | 0 / 0 | 0 / 0 | 无 |
| 动画渐变 | active | 0 / 0 | 0 / 0 | 0 / 0 | 无 |
| 暗场 | active | 0 / 0 | 0 / 0 | 0 / 0 | 无 |

汇总位于 `.local/qa/nvidia-scaling-ab/summary.json`，每组包含中点与固定 12 秒
完成帧。开启帧为 3840×2160，右上角包含驱动生成的 `RTX VSR` 状态标记；
关闭帧保持 1920×1080。真人面部固定帧显示边缘与背景轮廓更清晰，同时保留
皮肤纹理；动画渐变和暗场未观察到新增闪烁或明显噪点放大。

## 验证

- 三类片源六组 A/B：通过。
- 全量 Flutter 测试：287 项通过。
- `flutter analyze`：通过。
- Windows Debug build：通过。
- 真实窗口：原生 child HWND 播放、底部控制层和齿轮菜单均可达；齿轮弹层显示时
  视频 HWND 正确隐藏，弹层位置、对齐和对比度正常。当前用户配置同时启用了 CPU
  压缩/暗场滤镜，NVIDIA 开关按设计禁用并给出互斥说明，没有绕过安全门禁。
- 原生截图：通过，截图命令只使用应用生成的临时路径，并在读取后清理。

## 依据

- [mpv d3d11vpp 文档](https://mpv.io/manual/master/#video-filters-d3d11vpp)
- [NVIDIA RTX Video SDK 能力说明](https://developer.nvidia.com/rtx-video-sdk/getting-started)
- [mpv.net 的 libmpv/高质量视频输出方向](https://github.com/mpvnet-player/mpv.net)
