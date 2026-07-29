# Windows 原生播放器第三方声明

本模块使用固定摘要下载下列上游组件，并在构建时对 MediaKit Windows ANGLE 桥接源代码
应用可审计的小型补丁：

- libmpv Windows video build：`2026-07-26`，mpv
  `v0.41.0-908-g48e6c35c0`。
- mpv API 头文件：随上述 libmpv 构建归档提供。
- ANGLE Windows 二进制：`v1.0.1`。
- media_kit_video Windows ANGLE 桥接源代码：`2.0.1`，MIT 许可证。
- FFmpeg Windows 共享开发包：BtbN `autobuild-2026-06-30-13-34`，
  FFmpeg `n8.1.2-21-gce3c09c101`，LGPL shared 变体。

构建时补丁用于 D3D11 纹理生命周期、QA 互操作和只读资源访问，不改变上游许可证，也不
构成稳定的第三方插件 ABI。补丁生成文件和固定摘要由
`windows/native_player/CMakeLists.txt` 维护。

libmpv 及其静态链接的 FFmpeg/编解码依赖可能触发 GPL 或 LGPL 分发义务。构建会同时安装
mpv 的 GPL-2.0 和 LGPL-2.1 许可证文本；发布者必须根据该预编译包的实际构建配置履行对应
源代码提供义务。本文不是法律意见。

ANGLE 使用 BSD 风格许可证，并可能包含 Chromium 第三方组件。发布目录会安装 ANGLE
许可证和本声明。

媒体探测桥只链接共享 `libavformat/libavcodec/libavutil`，不访问 SQLite。BtbN LGPL
shared 归档的 `LICENSE.txt` 会随包安装；发布者仍需按最终启用组件提供对应许可证、
动态链接说明和可替换库文件。

本原生模块只额外安装 D3D11 路径实际需要的 `libEGL.dll`、`libGLESv2.dll` 和 Microsoft
可再发行的 `d3dcompiler_47.dll`，不额外安装归档内未被该路径引用的 SwiftShader、
Vulkan、libc++ 和 zlib。默认 MediaKit 插件可能独立供应自身运行库；其声明由 Flutter
应用的 `NOTICES.Z` 及对应插件分发规则负责。`d3dcompiler_47.dll` 的再分发受构建所用
Microsoft Visual Studio/Windows SDK 许可条款约束。

本项目当前不分发 RTX Video SDK、NGX 或其他 NVIDIA SDK 文件。原生 NVIDIA 激活门禁
仅调用 mpv/驱动公开的 D3D11 视频处理路径。任何未来 SDK 集成都必须先核对具体下载包
许可证及逐文件可再分发清单。

上游来源：

- https://github.com/zhongfly/mpv-winbuild/releases/tag/2026-07-26-48e6c35c0e
- https://github.com/mpv-player/mpv/tree/v0.41.0
- https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/tree/v1.0.1
- https://github.com/media-kit/media-kit/tree/media_kit_video-v2.0.1
- https://github.com/BtbN/FFmpeg-Builds/releases/tag/autobuild-2026-06-30-13-34
- https://developer.nvidia.com/rtx-video-sdk/getting-started
- https://docs.nvidia.com/ngx/latest/ngx-eula/index.html
