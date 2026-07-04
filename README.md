# Local Tag Player

Local Tag Player 是一个 Flutter Windows 本地视频管理播放器，目标是替代“手动建文件夹 + PotPlayer 浏览”的工作流。

重点能力：

- 扫描本地视频目录，建立媒体库。
- 按文件夹自动生成一级标签和二级标签。
- 用标签、收藏、搜索快速筛选大量本地视频。
- 使用内置播放器播放，并提供右侧播放列表快速切换。
- 使用 FFmpeg / FFprobe 缓存缩略图和媒体信息。

更多项目上下文请读：

- PROJECT.md：项目背景、技术栈、约定。
- ARCHITECTURE.md：当前架构和主要类关系。
- CURRENT_TASK.md：当前状态、已知问题、下一步任务。
- CHANGELOG.md：阶段性变更记录。

## 运行

```powershell
cd <project-root>
flutter pub get
flutter run -d windows
```

## 验证

```powershell
flutter analyze
flutter build windows --debug
```

## 打包内置工具

Windows 版本会从以下目录复制内置媒体工具到构建输出：

```text
<project-root>\windows\tools\ffmpeg\bin\ffmpeg.exe
<project-root>\windows\tools\ffmpeg\bin\ffprobe.exe
<project-root>\windows\tools\sqlite\sqlite3.dll
```

如果后续公开发布，需要检查 FFmpeg 构建的 LGPL/GPL 授权要求。
