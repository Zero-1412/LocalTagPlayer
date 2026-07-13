# Windows 原生播放器依赖

本目录定义实验性 Windows C++ 播放后端的可重复构建边界。CMake 只使用已固定 URL 与 SHA-256 的 libmpv、ANGLE 和 `media_kit_video` Windows C++ 纹理桥接源码，不读取 Pub Cache，也不链接仓库外的本机临时文件。

同一构建边界还固定供应 FFmpeg 8.1 LGPL shared 开发包。媒体探测 DLL 不参与 runner 静态导入，只有首次 `probeBatch` 才由 C++ 桥延迟加载；SQLite 始终留在 Dart Repository。

本原生模块安装实际引用的 libmpv、EGL、GLES、D3DCompiler，以及延迟媒体探测所需的 FFmpeg shared DLL，并把许可证与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 安装到 `data/licenses/native_player`。它不会额外安装 ANGLE 归档内未使用的 Vulkan/SwiftShader 等运行库；默认 MediaKit 插件仍可能独立供应自己的运行库。发布者需根据最终 bundle 和链接方式确认全部许可证义务。

运行时开关：

- 未设置：使用默认 `MediaKitPlayerBackend`。
- `LOCAL_TAG_PLAYER_BACKEND=windows-native-stub`：仅验证假纹理与生命周期。
- `LOCAL_TAG_PLAYER_BACKEND=windows-native-mpv`：启用单个 libmpv/ANGLE/D3D11 原生会话，供同媒体 A/B 使用。

原生模式从 1280×720 起按 Flutter 实际纹理请求量化表面，并封顶 1920×1080；只有 `mpv_render_context_update` 返回视频帧更新时才渲染。截图接口尚未实现，且 4K 长视频 A/B 中 Private/GPU committed 仍高于 MediaKit，因此仍属于实验后端。

最终门槛判定中，原生 Private/GPU committed P95 分别约为 MediaKit 的 114.5%/113.8%，未达到 110% 目标；默认播放器替换路线停止，后端仅保留显式实验开关。
