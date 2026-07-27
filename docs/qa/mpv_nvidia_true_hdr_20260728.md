# Windows 原生 libmpv NVIDIA RTX Video HDR 验证

## 结论

固定 libmpv `v0.41.0-908-g48e6c35c0` 已通过 Windows 原生 child HWND 后端
实际启用 NVIDIA RTX Video HDR：

```text
SDR H.264
→ d3d11va（非 copy）
→ d3d11vpp=nvidia-true-hdr=yes
→ NVIDIA D3D11 驱动扩展
→ gpu-next / D3D11 child HWND
→ 10-bit PQ / BT.2020 HDR 活动信号
```

这是 mpv 调用 NVIDIA 驱动扩展，不是应用分发 RTX Video SDK。原生层收到固定
成功事件 `NVIDIA RTX Video HDR enabled.` 后，只向 Flutter 返回
`native-nvidia-hdr-state=active`，不回传 verbose 原始日志。

## 产品与安全边界

- 入口稳定键为 `player.settings.nvidiaVideoHdrExperiment`，默认关闭、会话级。
- 只允许固定实现版本、原生 `gpu-next/D3D11` child HWND、
  `hwdec-current=d3d11va`、明确 SDR 源且无 CPU `lavfi` 冲突的会话开启。
- 源 gamma 为 PQ/HLG 时入口禁用；色彩属性未知时保持等待，不猜测为 SDR。
- VSR 与 TrueHDR 原子生成唯一 `d3d11vpp`。联合模式为
  `d3d11vpp=scale=2:scaling-mode=nvidia:nvidia-true-hdr=yes`，不能沿用 VSR
  单独模式的 `format=nv12`。
- 新组合未被 mpv 读回时恢复此前已确认组合；运行压力复用既有掉帧、缓存和音视频
  停滞熔断，回滚只影响当前媒体。
- 不下载、不提交、不安装、不打包 NVIDIA SDK、头文件或 DLL；插件 ABI v1 不变。

## 三类自然低码率 A/B

样本均为 650 kbps、1920×1080 SDR，每类关闭/开启各播放 20 秒：

| 样本 | 开启组驱动 | 滤镜格式门禁 | off/on 总掉帧 | 视频停滞 | 音频停滞 |
|---|---:|---:|---:|---:|---:|
| 真人面部 | active | 无 NV12 | 0 / 0 | 0 / 0 | 0 / 0 |
| 动画渐变 | active | 无 NV12 | 0 / 0 | 0 / 0 | 0 / 0 |
| 暗场 | active | 无 NV12 | 0 / 0 | 0 / 0 | 0 / 0 |

匿名汇总位于 `.local/qa/nvidia-true-hdr-ab/summary.json`，复跑命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool/run_nvidia_true_hdr_ab.ps1 -DurationSeconds 20
```

另有同一会话同时开启 VSR 与 TrueHDR 的三类六组门禁。组合滤镜固定为
`scale=2:scaling-mode=nvidia:nvidia-true-hdr=yes`，三类驱动门禁、滤镜共存
门禁和性能门禁全部通过；关闭/组合开启两侧总掉帧均为 0，音视频停滞均为 0。
复跑命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool/run_nvidia_vsr_hdr_ab.ps1 -DurationSeconds 20
```

组合汇总位于 `.local/qa/nvidia-vsr-hdr-ab/summary.json`。

三组完成帧的 off/on PSNR 分别为 39.47 dB、37.14 dB、31.83 dB，证明导出帧
确实发生处理而不是同帧复制。人工检查未见真人肤色断层、高光剪切、动画渐变新增
条带或暗场黑位吞噬。PNG 会把 HDR 输出重新映射到普通图像，因此这些帧只用于
伪影检查，不能证明显示器亮度观感。

## HDR 输出与限制

六组播放期间 DXGI 都报告：

```text
3840×2160 · 10 bit · rgb-full-pq-p2020 · HDR 信号活动
```

这证明最终 swap chain 已建立 HDR 信号，不再只是滤镜字符串或驱动日志。当前
峰值亮度字段为 `0.0 nits`，代表元数据不可用；本轮不能据此评价实际峰值亮度、
显示器校准或相机拍摄观感。后续需要支持峰值读取的 HDR 显示链补测。

## UI 与验证

- 真实 Debug 播放中点击齿轮，TrueHDR 开关为开启态；弹层锚定在齿轮上方，没有
  遮挡右侧队列或越界，三行说明无裁切、溢出和低对比度。
- 弹层显示时 child HWND 按 airspace 规则隐藏，Flutter 合成层截图中的视频区域
  为黑色；关闭弹层后由既有生命周期恢复。
- 自定义 Windows runner 未注册 integration_test 的系统级
  `captureScreenshot`，调用会得到 `MissingPluginException`。最终证据使用运行中
  Flutter Navigator Overlay 合成层截图，不冒充 Windows Graphics Capture。
- focused widget、Windows 原生桥与架构合同测试通过；`flutter analyze` 和
  Windows Debug build 通过。

## 依据

- [mpv d3d11vpp 文档](https://mpv.io/manual/master/#video-filters-d3d11vpp)
- [NVIDIA RTX Video SDK 能力说明](https://developer.nvidia.com/rtx-video-sdk/getting-started)
