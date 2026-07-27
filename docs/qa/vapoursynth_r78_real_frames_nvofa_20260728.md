# VapourSynth R78 真实帧与 NVOFA 驱动门禁

日期：2026-07-28

## 结论

官方 VapourSynth R78 已在本机隔离目录通过真实视频帧、精确 seek 与同进程 reload
验证。当前 NVIDIA 驱动同时提供 NVOFA API 5.0 和 D3D11 入口，因此项目具备继续
构建本机 FRUC 原型的运行环境。

这两项证据仍不等于 NVIDIA 硬件补帧已经完成。FRUC 实现位于 Optical Flow SDK，
而 RTX Video Super Resolution、压缩伪影消除和 SDR→HDR 属于独立的 RTX Video
SDK。两个 SDK 的下载均需要 NVIDIA 账户与许可流程；本轮没有代替用户登录或接受
许可，也没有把任何 NVIDIA SDK 文件提交或打入应用包。

## 官方 R78 来源与隔离方式

来源：

- [VapourSynth R78 Release](https://github.com/vapoursynth/vapoursynth/releases/tag/R78)
- [VapourSynth 官方安装说明](https://www.vapoursynth.com/doc/installation.html)

已验证资产：

```text
name: VapourSynth64-Portable-R78.zip
size: 23064773
sha256: 8f12c2436aba6f596cde88d779f923a0bd454899b4bde1dd111b7ebbd8d7c3e3
```

官方 portable 安装脚本摘要：

```text
sha256: 6da9bad88f2b94de198dc01121ed27680c66a4fa6d37dc69f6e108034cc9cd69
```

安装目标位于被 Git 忽略的 `build/vapoursynth-r78/installed`。安装时没有注册
VFW、没有修改注册表或系统 PATH，也没有复制文件到 runner bundle。自检结果：

```text
VapourSynth API: R4.2
VapourSynth Core: R78
Python: 3.14.0
```

## 真实帧探针

探针使用固定 libmpv、正式 `VapourSynthMotionRuntime` 与 R78 `VSScript.dll`，
向透传脚本送入 320×180、24 fps、6 秒、144 帧 H.264 样本。它验证：

1. 实际视频时间和估计输出帧持续推进；
2. `vapoursynth` 滤镜保持在结构化 `vf` 中；
3. 精确 seek 后能继续取帧；
4. 同一宿主实例可再次 load/reload；
5. 透传输出没有达到 1.5 倍源帧率，因此不会冒充真实插帧 active。

命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tool\run_vapoursynth_real_frame_probe.ps1 `
  -RuntimeDirectory .\build\vapoursynth-r78\installed\Lib\site-packages\vapoursynth `
  -Configuration Debug
```

Debug 与 Release 均得到：

```text
real-frames=passed seek=passed reload=passed passthrough-not-active=passed
```

## NVOFA 系统驱动门禁

正式 runner 与独立 QA 可执行文件复用
`ProbeNvidiaOpticalFlowDriver()`。实现只使用 Windows 动态加载边界：

- `LOAD_LIBRARY_SEARCH_SYSTEM32` 加载 `nvofapi64.dll`；
- 调用公开导出 `NvOFGetMaxSupportedApiVersion`；
- 检查 D3D11、D3D12、CUDA 与 Vulkan 创建入口；
- 不引用厂商 SDK 头文件，不创建 Optical Flow 会话，不持有 D3D11 设备。

命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tool\run_nvofa_driver_probe.ps1 -Configuration Debug
```

本机结果：

```text
nvofa-driver=available api-major=5 api-minor=0 api-raw=0x50
d3d11=available d3d12=available cuda=available vulkan=available
```

当前机器为 RTX 4070 SUPER、NVIDIA 595.97 驱动。该结果只证明驱动公开入口与
下一阶段 SDK 版本相容资格，不能证明 FRUC 插件、模型或输出帧已经存在。

## 产品边界

运行时只向 Flutter 暴露固定、类型化的只读字段：

```text
driver state
max API version
D3D11 entry available
```

媒体路径、驱动 DLL、导出符号、NVIDIA 日志、D3D11 对象和 mpv handle 都留在
Windows 原生层。MediaKit 与非 Windows 后端继续返回 unsupported。默认后端、
filtered queue、当前 index、返回媒体库状态、SQLite、标签、缓存队列、现有
单帧插件 ABI v1 和用户数据均不改变。

QA 目标使用独立 CMake 开关并标记为 `EXCLUDE_FROM_ALL`，没有 install 规则。
标准应用包不得出现 `VSScript.dll`、VapourSynth/Python 运行时、Optical Flow
SDK、FRUC 或 RTX Video SDK 文件。

## 完整验证

- `flutter analyze`：通过，无问题；
- `flutter test`：297 项通过，3 项按既有显式条件跳过；
- `flutter build windows --debug`：通过；
- R78 真实帧探针：Debug/Release 均通过；
- NVOFA 驱动探针：API 5.0，D3D11/D3D12/CUDA/Vulkan 均可用；
- 真实窗口：确认进程为工作区 Debug exe，以 `windows-native-hwnd` 进入媒体库
  首个视频，child HWND 正常出画，Escape 返回 11239 项媒体库，最终进程退出；
- 退出日志：`pause → route pop → dispose → stop → released` 完整，原生播放器从
  `dispose_started` 到 `player_disposed` 用时 57 ms；
- 返回截图中 Windows Graphics Capture 会保留已经释放的 GPU 纹理最后一帧区域，
  但可访问树已回到媒体库，日志随后明确出现 hover 预览纹理创建与
  `VideoOutput: Free Texture`，不属于残留 mpv child HWND。由于 Flutter 合成层
  在该捕获器中呈白色，本轮只能核对 child HWND 的位置、无越界和返回可达性；
  Flutter 文字对齐、对比度与遮挡沿用既有页面回归证据。

## 下一阶段门禁

1. 用户在 NVIDIA Developer Program 中接受对应许可并提供本机 SDK；
2. 先实现不分发厂商文件的 Optical Flow SDK 5.0 FRUC 原型；
3. 验证连续帧、时间戳、seek、快速切换、退出、音视频同步和失败回退；
4. 使用真人面部、动画渐变、暗场三类自然片源完成关闭/开启六组 A/B 与掉帧测试；
5. 另建 RTX Video SDK 1.1 原型，独立验证 VSR、压缩伪影消除与 SDR→HDR；
6. 只有多片源稳定获益且回退可靠，才增加用户入口并进入发布许可审查。

NVIDIA 参考：

- [Optical Flow SDK 下载与许可入口](https://developer.nvidia.com/opticalflow/download)
- [NVOFA Programming Guide](https://docs.nvidia.com/video-technologies/optical-flow-sdk/nvofa-programming-guide/index.html)
- [RTX Video SDK 1.1 Getting Started](https://developer.nvidia.com/rtx-video-sdk/getting-started)
