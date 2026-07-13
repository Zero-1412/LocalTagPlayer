# Windows 原生播放器依赖

本目录定义实验性 Windows C++ 播放后端的可重复构建边界。CMake 只使用已固定 URL 与 SHA-256 的 libmpv、ANGLE 和 `media_kit_video` Windows C++ 纹理桥接源码，不读取 Pub Cache，也不链接仓库外的本机临时文件。

本原生模块只额外安装实际引用的 libmpv、EGL、GLES 与 D3DCompiler DLL，并把许可证与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 安装到 `data/licenses/native_player`。它不会额外安装归档内未使用的 Vulkan/SwiftShader 等运行库；默认 MediaKit 插件仍可能独立供应自己的运行库。发布者需根据最终 bundle 和链接方式确认全部许可证义务。

运行时开关：

- 未设置：使用默认 `MediaKitPlayerBackend`。
- `LOCAL_TAG_PLAYER_BACKEND=windows-native-stub`：仅验证假纹理与生命周期。
- `LOCAL_TAG_PLAYER_BACKEND=windows-native-mpv`：启用单个 libmpv/ANGLE/D3D11 原生会话，供同媒体 A/B 使用。

原生模式当前固定 1920×1080 渲染表面，截图接口尚未实现，因此仍属于实验后端，不能仅凭单轮短测切换为默认值。
