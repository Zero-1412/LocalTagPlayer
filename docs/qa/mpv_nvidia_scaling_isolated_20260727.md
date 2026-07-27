# mpv NVIDIA scaling-mode 隔离验证（2026-07-27）

## 结论

本轮不启用产品开关，也不升级正式包的 mpv。

隔离候选 `mpv v0.41.0-744-g304426c39` 在独立 `mpv.exe` 中可以建立
`d3d11va → d3d11vpp scaling-mode=nvidia → D3D11` 链，并由日志确认
`NVIDIA RTX Super Resolution enabled`。但同一 DLL 进入 Local Tag Player 的
MediaKit/libmpv 渲染边界后，请求 `d3d11va` 的实际属性为
`hwdec-current=no`，非 copy 纹理链未成立。真人面部第一组即未通过硬门槛，
因此按“先通过多片源再启用”的规则终止后续开组。

## 隔离候选

- 来源：`shinchiro/mpv-winbuild-cmake` 的 `20260610` Windows 构建。
- 归档：`mpv-dev-x86_64-20260610-git-304426c.7z`。
- SHA-256：`8cbb25ea784f01afbb3f904217cab1317430a8bcfd5680fd827a866367f71cc9`。
- 候选只放在 `.local/qa/mpv-nvidia-scaling/`；最终 Debug 包已恢复
  `v0.36.0-403-g652a1dd907`。

## 纹理链与滤镜证据

独立候选以 `vo=gpu-next`、`gpu-api=d3d11`、`hwdec=d3d11va` 和
`vf=d3d11vpp=scale=2:scaling-mode=nvidia` 运行时，日志确认硬解、NVIDIA
RTX Super Resolution，以及 1920×1080 D3D11 输入到 3840×2160 D3D11 输出。

直接再串联现有 CPU `lavfi` 时，mpv 无法转换 `d3d11` 硬件帧并停用压缩滤镜，
但进程仍返回 0。显式加入 `hwdownload` 虽可运行，却让 2 倍放大的 4K 帧回到
CPU，不满足零拷贝和性能边界。

证据文件：

- `.local/qa/mpv-nvidia-scaling/standalone-nvidia-d3d11.log`
- `.local/qa/mpv-nvidia-scaling/standalone-nvidia-plus-lavfi.log`
- `.local/qa/mpv-nvidia-scaling/standalone-nvidia-plus-download-lavfi.log`

## 应用内失败门槛

升级 DLL 的隔离 Debug 应用完成构建，包内版本确认为候选版本。真人面部关闭组
完成 20 秒实播并通过；开启组请求 `d3d11va` 后诊断为：

```text
PLAYER_HEALTH software_decode_confirmed requested=d3d11va actual=no
```

设置开关因 `hwdec-current != d3d11va` 保持禁用，测试按设计超时失败，没有写入
NVIDIA `vf`。这证明当前阻断位于 MediaKit/libmpv 的非 copy D3D11 设备接入，
不是 mpv 选项缺失。

证据文件：

- `.local/qa/nvidia-scaling-ab/live-face/nvidia-off/`
- `.local/qa/nvidia-scaling-ab/live-face/nvidia-on/baseline.log`
- `.local/qa/nvidia-scaling-ab-run.log`

## 产品门禁与下一步

1. 正式依赖继续固定 mpv 0.36.0，实验开关继续禁用。
2. NVIDIA `d3d11vpp` 与压缩/暗场 `lavfi` 保持互斥，写入必须读回并接受掉帧熔断。
3. 不修改现有本机视频增强插件 ABI，不分发 NVIDIA 文件。
4. 下一轮先在 MediaKit Windows 边界证明同一活动 D3D11 device 能为 libmpv
   提供 `d3d11va` 非 copy 硬件帧。
5. 只有该门槛通过后，才重跑真人面部、动画渐变、暗场各自关闭/开启 A/B；全部
   片源无新增掉帧、停滞或回滚后，才能把 `filterChainValidated` 改为 `true`。

## MediaKit interop 复核

后续复核确认 MediaKit Windows 输出只创建
`MPV_RENDER_API_TYPE_OPENGL` render context，再通过 Chromium 5359 的 ANGLE
渲染到 BGRA D3D11 共享纹理；libmpv render API 头文件没有可由宿主选择的
`MPV_RENDER_API_TYPE_D3D11`。

按 mpv 文档，`gpu-hwdec-interop=auto` 在 `vo=libmpv` 下已经等价于加载全部
interop。仍在 render context 创建前显式收窄为 `d3d11va`，分别用正式 0.36
和隔离 0.41 候选运行真人面部关闭组，两次都得到：

```text
PLAYER_HEALTH software_decode_confirmed requested=d3d11va actual=no
```

因此该参数补丁无效并已撤回，Debug DLL 和构建缓存均恢复 0.36。硬门槛没有
解决，所以没有运行余下五组，也没有改 NVIDIA 滤镜参数。新的证据位于：

```text
.local/qa/mpv-d3d11va-interop/
```

下一条可验证路线不是增加 mpv 参数，而是隔离构建新版 Google ANGLE，确认其
EGL/D3D11 interop 能否在 MediaKit 自建上下文中导入硬件帧；若仍失败，则
MediaKit Flutter 纹理模型与 mpv 原生 D3D11 VO 之间不存在小补丁，需要重新
评估原生 HWND/渲染后端边界。
