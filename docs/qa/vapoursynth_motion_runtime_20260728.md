# Windows VapourSynth / NVIDIA FRUC 插帧边界验证

日期：2026-07-28

## 结论

项目已经具备一个不分发第三方文件的 Windows 本机运动补偿插帧边界，但尚未宣称
NVIDIA 硬件补帧已经完成。

当前固定 libmpv 确实编译了 VapourSynth。实际向滤镜送入视频帧后，当前应用包会
因为找不到 `VSScript.dll` 而安全失败；这证明此前只有 mpv 滤镜入口，没有完整
运行时。新增原生宿主解决了路径、滤镜图所有权、能力读回和失败回退，下一阶段可
在不改变 Flutter 页面或现有插件 ABI 的前提下接入真实 VapourSynth 与 NVIDIA
FRUC 插件。

## 本轮证据

固定 DLL：

```text
mpv: v0.41.0-908-g48e6c35c0
build: 2026-07-26-48e6c35c0e
configuration: -Dvapoursynth=enabled
enabled features: vapoursynth
```

libmpv 对未知滤镜返回选项错误，而
`vapoursynth=file=...:buffered-frames=4:concurrent-frames=4` 能被解析。将
320×180、24fps、1 秒 H.264 测试视频送入透传脚本后，固定错误为：

```text
Failed to load VapourSynth VSScript library
Creating filter 'vapoursynth' failed
```

因此能力判定必须分四层：

```text
mpv 编译含滤镜
-> VSScript/Python 运行时加载
-> 脚本与滤镜创建成功
-> 输出帧率真实高于源帧率
```

不能用第一层替代第四层。

## 新平台边界

```text
Flutter PlayerPage
        |
   PlayerService
        |
PlayerMotionInterpolationBoundary
        |
WindowsNativePlayerBackend
        |
VapourSynthMotionRuntime
        |
libmpv structured vf
        |
VapourSynth / local FRUC script
```

配置只来自：

```text
LOCAL_TAG_PLAYER_VAPOURSYNTH_RUNTIME_DIR
LOCAL_TAG_PLAYER_MOTION_INTERPOLATION_SCRIPT_PATH
```

两者都必须是绝对路径。宿主只从运行时目录加载 `VSScript.dll`，使用
`LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS`，并校验
`getVSScriptAPI`。不扫描 exe 目录，不修改系统 PATH，不保存本机路径到设置或
诊断。

## 结构化滤镜与兼容性

Windows 盘符的冒号会被 mpv 字符串子选项解析器当作分隔符。正式实现不使用手工
反斜杠转义，而是：

1. 以 `MPV_FORMAT_NODE` 读取当前完整 `vf`；
2. 保留所有非 `ltp-motion-interpolation` 条目；
3. 用 `name/label/enabled/params` 节点追加 VapourSynth；
4. 以 `MPV_FORMAT_NODE` 写回。

压缩增强以后重写完整 `vf` 时，原生宿主会恢复已请求的插帧条目。脚本加载、
滤镜创建或重写失败时只移除自己的标签、增加回退计数并继续播放原视频。

`requested` 只表示滤镜配置存在。只有标签仍在并且
`estimated-vf-fps >= container-fps × 1.5` 才报告 `active`，透传脚本不会被冒充
为补帧。

## 可重复宿主探针

显式 QA 构建会产生不安装的假 `VSScript.dll` 和宿主测试。假 DLL 只导出
`getVSScriptAPI`，不处理视频帧；测试用途是证明绝对路径门禁、结构化参数和既有
滤镜保留。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tool\run_vapoursynth_motion_host_probe.ps1 -Configuration Debug
```

本机结果：

```text
structured-vf=passed preserve-existing=passed remove=passed
active-revocation=passed reload=passed
```

探针库和测试均为 `EXCLUDE_FROM_ALL` 显式目标；即使 QA 构建目录保留探针选项，
标准构建也不会顺带编译它们。探针没有 install 规则，工作区 Debug runner 目录已
确认不含假 `VSScript.dll`。

## 验证结果

- `flutter analyze`：通过，无问题；
- `flutter test`：297 项通过，3 项按既有条件跳过；
- `flutter build windows --debug`：通过；
- 原生宿主探针：结构化追加、现有滤镜保留、移除、`active` 过期撤销与宿主释放后
  重新加载在 Debug、Release 两种配置下全部通过；
- 真实窗口：确认进程路径为工作区 Debug exe，媒体库正常加载 11239 个视频；
  点击“设置”后页面完整显示，返回媒体库正常。默认未设置两个外部运行时环境变量时
  没有崩溃、弹窗、遮挡、溢出或布局错位；
- 退出后进程正常结束，runner bundle 未发现 `VSScript.dll`。

## 版本与外部依赖

截至 2026-07-28，VapourSynth 最新稳定版是
[R78](https://github.com/vapoursynth/vapoursynth/releases/tag/R78)，发布日期为
2026-07-24。官方安装文档建议 Python 3.12+ 与 `pip install vapoursynth`，同时
提供 Windows installer 和 portable 脚本/包：
[官方安装说明](https://www.vapoursynth.com/doc/installation.html)。

官方 R78 64 位便携包的 GitHub 元数据为：

```text
VapourSynth64-Portable-R78.zip
sha256:8f12c2436aba6f596cde88d779f923a0bd454899b4bde1dd111b7ebbd8d7c3e3
```

后续已完成官方摘要校验、隔离安装和真实 R78 送帧测试；结果见
`docs/qa/vapoursynth_r78_real_frames_nvofa_20260728.md`。本文件保留最初宿主
边界证据，不再代表 R78 当前状态。

## NVIDIA 插帧目标

真实 NVIDIA 硬件补帧应使用 Optical Flow SDK 的 FRUC，而不是 RTX Video
Super Resolution/HDR：

- [NVIDIA FRUC Programming Guide](https://docs.nvidia.com/video-technologies/optical-flow-sdk/nvfruc-programming-guide/index.html)
  说明输入连续两帧并生成中间帧，使用 NVOFA 硬件与 CUDA，支持 Windows、
  Turing 及以上 GPU，并提供 DirectX/CUDA 集成；
- [NVIDIA Optical Flow 下载页](https://developer.nvidia.com/opticalflow/download)
  要求 NVIDIA Developer Program 登录和许可接受；
- [Optical Flow SDK 许可](https://docs.nvidia.com/video-technologies/optical-flow-sdk/license/index.html)
  允许的使用与分发范围必须以实际 SDK 包和发布审查为准。

本轮没有代替用户登录、接受许可或下载 NVIDIA 文件。未来本机 FRUC 插件必须由
独立目录提供，并保持：

```text
mpv/VapourSynth 负责帧序与时间戳
-> 本机插件调用 NVOFA FRUC
-> 失败返回原帧
-> PlayerService 只接收状态
```

若 VapourSynth 不能可靠承载 D3D11 纹理，才新增拥有前帧、后帧、目标时间戳和
输出纹理队列的插件 ABI v2。现有 ABI v1 每次只原位处理一张 BGRA 纹理，无法插入
额外带时间戳的帧，不能勉强复用。

## 与 RTX Video VSR / HDR 的关系

- RTX Video Super Resolution 已在 child HWND 的
  `d3d11va → d3d11vpp scaling-mode=nvidia → gpu-next/D3D11` 路径通过六组
  A/B，属于空间超分；
- 本轮边界属于时间域补帧；
- RTX Video HDR 是另一条 SDR→HDR 原生 SDK 能力，不能用现有通用 tone mapping
  或 NVOFA FRUC 冒充，仍需单独接入与输出 HDR 信号验证。

## 下一阶段门禁

1. 官方 R78 便携运行时的透传脚本真实送帧和 seek/reload 已完成。
2. 由用户/发布负责人接受 NVIDIA Optical Flow SDK 许可后，在本机隔离目录构建
   FRUC 插件，不提交厂商二进制。
3. 真人面部、动画渐变、暗场三类自然低码率片源各做关闭/开启 A/B，读回源/输出
   FPS、掉帧、音视频同步、缓冲和回退。
4. 验证快速切换、全屏、跨 DPI、退出和非 NVIDIA 机器回退。
5. 全部门禁通过后才增加设置入口；在此之前保持能力 API 可诊断但无用户假开关。

## 产品保护

本轮没有修改 SQLite schema、`FilterQuery`、`TagQueryService`、filtered queue、
当前 index、返回媒体库状态、缩略图/媒体详情队列或用户数据。现有单帧本机视频
插件 ABI v1 不变。
