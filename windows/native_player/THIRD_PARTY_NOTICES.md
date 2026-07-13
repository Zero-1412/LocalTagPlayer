# Windows原生播放器第三方声明

本模块使用固定摘要下载以下未修改上游组件：

- libmpv Windows video build：`2023-09-24`，提交版本`652a1dd`。
- mpv API头文件：随上述libmpv构建归档提供。
- ANGLE Windows二进制：`v1.0.1`。
- media_kit_video Windows ANGLE桥接源码：`1.3.1`，MIT许可证。

libmpv及其静态链接的FFmpeg/编解码依赖可能触发GPL或LGPL分发义务。构建会同时安装mpv的GPL-2.0和LGPL-2.1许可证文本；发布者必须根据该预编译包的实际构建配置履行对应源代码提供义务。本文不是法律意见。

ANGLE使用BSD风格许可证，并可能包含Chromium第三方组件。发布目录会安装ANGLE许可证和本声明。

本原生模块只额外安装D3D11路径实际需要的`libEGL.dll`、`libGLESv2.dll`和Microsoft可再发行的`d3dcompiler_47.dll`，不额外安装归档内未被该路径引用的SwiftShader、Vulkan、libc++和zlib。默认MediaKit插件可能独立供应其自身运行库；其声明由Flutter应用的`NOTICES.Z`及对应插件分发规则负责。`d3dcompiler_47.dll`的再分发受构建所用Microsoft Visual Studio/Windows SDK许可条款约束。

上游来源：

- https://github.com/media-kit/libmpv-win32-video-build/tree/2023-09-24
- https://github.com/mpv-player/mpv/tree/v0.36.0
- https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/tree/v1.0.1
- https://github.com/media-kit/media-kit
