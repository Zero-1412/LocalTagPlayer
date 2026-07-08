---
name: ltp-cache-diagnostics
description: Local Tag Player 缓存与诊断技能。用于 ThumbnailService、MediaDetailsService、FFmpegBackend、FFprobe、异常文件、失败重试/清理动作或 diagnostics UI。
---

# Local Tag Player 缓存与诊断

用于缩略图、媒体详情、FFmpeg/FFprobe、诊断 UI、失败重试和异常文件。

## 上下文

通常是 Level 2；如果修改 `FFmpegBackend` 平台边界或缓存 schema，升级为 Level 3。

读取：

```text
AGENTS.md
PROJECT.md
CURRENT_TASK.md
docs/chat_tasks/CHAT_5_THUMBNAIL_DIAGNOSTICS.md
ThumbnailService / MediaDetailsService / ExternalMediaTools 相关源码
```

## 产品规则

- FFmpeg / FFprobe 访问必须经过 `FFmpegBackend` 或兼容层。
- 可见项目优先。
- 后台任务必须限流。
- 失败项目应可重试。
- 失败原因应可见。
- 0-byte 或不完整 JPEG 不能当作有效缓存。
- diagnostics UI dispose 后不能保留 timers 或 async callbacks。

## 禁止

- 不改标签筛选语义。
- 不改播放器主结构。
- 不散落 Windows exe 路径。
