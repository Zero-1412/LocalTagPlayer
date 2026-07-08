# 内置 FFmpeg 工具

构建应用前，把 Windows FFmpeg 二进制文件放在这里：

- `ffmpeg.exe`
- `ffprobe.exe`
- 同一 FFmpeg 发行包中必需的 `.dll` 文件

Windows CMake 构建会把这些文件复制到应用包内：

```text
tools/ffmpeg/bin
```

运行时应用会先检查此内置路径，然后再回退到 `PATH`。
