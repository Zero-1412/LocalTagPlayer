# CHAT_5_THUMBNAIL_DIAGNOSTICS.md

Current Version: `0.2.1`
Status: first phase complete
Owner: Chat 5 / Thumbnail + Diagnostics + FFmpegBackend

## Planning Source

Primary source:

```text
<private-planning-document>
```

If this task document conflicts with that file, the external plan wins.

## Scope

Owns FFmpeg/FFprobe integration, thumbnail cache queue, media probe cache, retry/failure reporting, abnormal file list, diagnostics cards, and `FFmpegBackend` implementation.

Allowed:

- `ThumbnailService`.
- `MediaDetailsService`.
- `ExternalMediaTools` until it is wrapped by `FFmpegBackend`.
- Future `platform/ffmpeg`.
- Cache diagnostics views if needed for cache function.
- Cache-related repository planning.

Do not do:

- Tag filter logic.
- Player page main structure.
- SQLite tag schema, except cache-related fields after coordination.
- Windows exe paths outside platform/backend layer.

## P0/P1 Tasks

- Keep thumbnail queue conservative during playback.
- Route FFmpeg / FFprobe discovery and execution through `FFmpegBackend`.
- Expose FFmpeg / FFprobe availability, path, and version.
- Keep FFprobe output minimal and cacheable.
- Add retry for failed thumbnail/media-probe tasks.
- Add clear failure records.
- Add abnormal file list.
- Improve diagnostics page into actionable cards.
- Preserve current Windows bundled-tool behavior behind the backend.

## Prompt For New Chat

```text
这是 Chat 5 / Thumbnail + Diagnostics + FFmpegBackend。项目路径：<project-root>。

请先阅读：
- PROJECT.md
- ARCHITECTURE.md
- CURRENT_TASK.md
- ROADMAP.md
- <private-planning-document>
- docs/chat_tasks/CHAT_5_THUMBNAIL_DIAGNOSTICS.md

后续方向以 local_tag_player_flutter_cross_platform_plan_v2.md 为准；当前项目实现只代表历史状态。

职责：负责 FFmpeg/FFprobe、缩略图缓存队列、媒体信息缓存、失败重试、异常文件列表、缓存诊断和 FFmpegBackend。不要改 Tag 筛选逻辑、播放器主结构或 UI 美化。

当前目标：稳定缩略图与 FFprobe 缓存，补充失败原因、失败重试、清除失败记录、异常文件列表和诊断卡片。把 FFmpeg/FFprobe 路径解析和调用逐步收敛到 FFmpegBackend，不要在业务层写死 Windows exe 路径。

修改代码后运行：
- flutter analyze
- flutter build windows --debug

涉及 src/core、平台接口或共享服务协议时，先同步 Architecture 或更新 ARCHITECTURE.md 基线记录。
```

## Change Log

- `0.1.0`: Created task from `local_tag_player_flutter_cross_platform_plan_v2.md`; Chat 5 now owns Thumbnail + Diagnostics + FFmpegBackend.
- `0.2.0`: Implemented first-phase cache diagnostics: FFmpeg/FFprobe calls now route through a `DesktopFFmpegBackend` compatibility adapter, tool versions are surfaced, thumbnail fallback writes through a temp file before replace, background thumbnail queueing is capped, media probe queue state is visible, and the diagnostics page can retry failures, clear failure records, and list abnormal files.
- `0.2.1`: Acceptance fix: existing thumbnail cache files now validate JPEG markers and length before being treated as cached, so 0-byte or truncated files are discarded; retry and clear-failure actions are disabled while already running or while cache jobs are active.
