# NVIDIA VSR/HDR 原生门禁与 MediaKit SDK 评估

## 结论

- Local Tag Player 的正式默认播放后端继续使用 MediaKit。
- Windows 原生 child HWND/libmpv D3D11 后端只承担 NVIDIA VSR/HDR 激活门禁和平台
  增强实验，不替代正式默认后端。
- 原生门禁已经明确观察到 NVIDIA VSR 与 RTX Video HDR 同时为 `active`。
- MediaKit Windows Texture 链内部可以取得 D3D11 device/context/texture，但当前没有
  稳定的公开逐帧处理扩展接口。
- 在核对实际 RTX Video SDK 包许可和可再分发文件清单前，项目不得分发 NVIDIA SDK 文件。

## 激活门禁

原生滤镜事务原先只回读 `vf`，没有回读 `deband` 及其四个参数。libmpv 已成功启用
NVIDIA 滤镜后，事务校验仍会把 `deband=unavailable` 当成不一致，并回滚整个事务。

本轮补齐以下属性的观察、缓存和诊断快照：

- `deband`
- `deband-iterations`
- `deband-threshold`
- `deband-range`
- `deband-grain`

同时允许异步属性在最多 200 ms 内收敛；持续不一致仍按原规则回滚。

最终单次真人低码率 20 秒门禁报告：

```text
.local/qa/nvidia-vsr-hdr-gate-20260729-final/live-face/
  nvidia-vsr-hdr-on-retry/nvidia-vsr-hdr-on-player-baseline.json
```

关键结果：

```text
mode: nvidia-vsr-hdr-on
samples: 4
maxTotalDropped: 0
videoStalls: 0
audioStalls: 0
vf: d3d11vpp=scale=2:scaling-mode=nvidia:nvidia-true-hdr=yes
VSR: active
HDR: active
```

这证明当前机器、驱动和原生 D3D11 路径能够触发两项能力。三类片源六组脚本的第二测试
进程仍出现 `No tests were found`，因此本轮不把不完整的矩阵描述为已通过。

## MediaKit Windows 输出层

当前 Windows Texture 链为：

```text
libmpv OpenGL Render API
-> ANGLE EGL
-> ANGLESurfaceManager D3D11 texture
-> Flutter GpuSurfaceTexture
```

项目的固定 `media_kit_video 2.0.1` 补丁已经提供只读的 D3D11 device、device context
和 texture 访问器，并修复纹理生命周期与 QA 互操作。不过 `VideoOutput` 仍没有公开的：

- 逐帧处理回调与插件所有权；
- 输入/输出纹理格式及色彩元数据契约；
- in-place/out-of-place 输出约定；
- GPU 同步、resize、dispose 和 device-loss 生命周期；
- 失败时零拷贝回退及性能预算。

如果后续获得 SDK 使用与发布授权，最小原型应放在原生线程的
`surface_manager_->Read()` 之后、Flutter texture descriptor 返回之前。不得把每帧
处理放到 Dart 或 MethodChannel，也不得在门禁完成前宣称 MediaKit Texture 路径已激活
VSR/HDR。

## 发布许可门禁

NVIDIA 官方资料说明 RTX Video SDK 1.1 提供超分辨率、压缩伪影降低及 SDR 到 HDR，
支持 Windows 10 64 位上的 DX11/DX12/Vulkan/CUDA 与 RTX 20 系列以上 GPU：

- https://developer.nvidia.com/rtx-video-sdk/getting-started

当前 NVIDIA NGX/RTX SDK 通用条款要求只分发被明确标记为可再分发的部分、以集成目标代码
形式提供，开发工具不能作为独立产品分发，商业发布还需要按条款通知 NVIDIA：

- https://docs.nvidia.com/ngx/latest/ngx-eula/index.html

RTX Video SDK 的实际下载会进入 NVIDIA 登录流程：

- https://developer.nvidia.com/sw-notification

因此当前发布门禁是：由有权人员登录、接受具体 SDK 包许可、归档版本和哈希、逐文件核对
可再分发清单，并向 `nvidia-rtx-license-questions@nvidia.com` 确认不清楚的条款。在此之前
只能做不分发 NVIDIA 文件的本机原型。本文是工程发布门禁记录，不是法律意见。

## 真实窗口复测

正式 Debug 应用已从当前工作区构建路径启动，媒体库主界面能够正常显示。自动点击阶段
Computer Use 无法再次激活已捕获窗口，因此仍需人工完成：

1. 正常启动应用，进入设置，确认默认后端是 MediaKit。
2. 打开视频并查看播放诊断，确认正式路径仍为 MediaKit Texture。
3. 仅在 QA 覆盖启动方式下进入原生后端，打开低码率 SDR 视频。
4. 确认诊断同时显示 child HWND、D3D11VA、VSR `active`、HDR `active`。
5. 退出 QA 覆盖并重新启动，确认默认后端恢复 MediaKit。
