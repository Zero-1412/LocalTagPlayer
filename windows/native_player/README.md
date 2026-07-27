# Windows 原生播放器依赖

本目录定义实验性 Windows C++ 播放后端的可重复构建边界。CMake 只使用已固定 URL 与 SHA-256 的 libmpv、ANGLE 和 `media_kit_video` Windows C++ 纹理桥接源码，不读取 Pub Cache，也不链接仓库外的本机临时文件。

同一构建边界还固定供应 FFmpeg 8.1 LGPL shared 开发包。媒体探测 DLL 不参与 runner 静态导入，只有首次 `probeBatch` 才由 C++ 桥延迟加载；SQLite 始终留在 Dart Repository。

本原生模块安装实际引用的 libmpv、EGL、GLES、D3DCompiler，以及延迟媒体探测所需的 FFmpeg shared DLL，并把许可证与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 安装到 `data/licenses/native_player`。它不会额外安装 ANGLE 归档内未使用的 Vulkan/SwiftShader 等运行库；默认 MediaKit 插件仍可能独立供应自己的运行库。发布者需根据最终 bundle 和链接方式确认全部许可证义务。

运行时开关：

- 未设置：使用默认 `MediaKitPlayerBackend`。
- `LOCAL_TAG_PLAYER_BACKEND=windows-native-stub`：仅验证假纹理与生命周期。
- `LOCAL_TAG_PLAYER_BACKEND=windows-native-mpv`：启用单个 libmpv/ANGLE/D3D11 原生会话，供同媒体 A/B 使用。
- `LOCAL_TAG_PLAYER_BACKEND=windows-native-hwnd`：启用 QA-only 双层 child
  HWND，让固定 mpv `v0.41.0-908-g48e6c35c0` 直接使用
  `gpu-next/D3D11/D3D11VA`。普通窗口鼠标、弹层、全屏、快速切换和退出已
  通过；真实跨 DPI 仍无物理证据，因此不能作为正式默认后端。

该 child HWND 路径已经通过 `d3d11vpp=scale=2:scaling-mode=nvidia` 的三类
低码率片源六组 A/B。NVIDIA 开关只在非 copy `d3d11va`、原生 D3D11 输出且
无 CPU `lavfi` 冲突时开放；驱动未确认 `active` 或命令被拒绝时立即保持关闭。
这条路径使用 mpv/驱动能力，不是 RTX Video SDK，也不分发 NVIDIA SDK 文件。

原生纹理模式从 1280×720 起按 Flutter 实际纹理请求量化表面，并封顶
1920×1080；只有 `mpv_render_context_update` 返回视频帧更新时才渲染。
child HWND 后端已支持滤镜后临时截图，但既有 4K 长视频 A/B 中 Private/GPU
committed 仍高于 MediaKit，因此整体仍属于实验后端。

早期 ANGLE 纹理后端的 Private/GPU committed P95 分别约为 MediaKit 的
114.5%/113.8%，未达到 110% 目标，因此该纹理替换路线停止。新的 child HWND
路径继续保留显式实验开关；只有跨 DPI 与长期生命周期门禁补齐后，才重新评估
Windows 默认后端。
