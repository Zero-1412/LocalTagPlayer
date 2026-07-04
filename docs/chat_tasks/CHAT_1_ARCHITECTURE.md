# CHAT_1_ARCHITECTURE.md

Current Version: `0.4.1`
Status: active
Owner: Chat 1 / Architecture + Cross Platform Boundary

## Planning Source

Primary source:

```text
<private-planning-document>
```

If this task document conflicts with that file, the external plan wins.

## Scope

Owns project architecture, module boundaries, cross-platform route, platform interfaces, local rules, and architecture baseline versions.

Allowed:

- `main.dart` structure and `part` / future import boundaries.
- `app/`, `core/`, `models/`, `platform/`, `repositories/` interface planning.
- Core models and shared contracts.
- `FileSystemAdapter`, `PlayerBackend`, `FFmpegBackend`, `DatabaseProvider`.
- `LibraryRepository`, `TagRepository`, `CacheRepository`, `PlaybackRepository` interface planning.
- `LayoutSize`: `compact`, `medium`, `expanded`.
- Architecture documentation and versioning rules.

Do not do:

- Rewrite player behavior.
- Rewrite SQLite query logic.
- Rewrite thumbnail queue.
- Perform broad UI redesign.
- Implement Tag Manager feature logic.

## Adopted Tasks

P0/P1:

- Keep Architecture aligned to the external cross-platform plan, not old project inertia.
- Maintain `Architecture Baseline 0.3.1` as the completed baseline.
- Maintain `Architecture Baseline 0.4.0` as the completed repository/layout boundary baseline.
- Prepare `Architecture Baseline 0.4.1` for low-risk import migration and incremental implementation adoption of the 0.4.0 contracts.
- Ensure Tag query/filter logic remains platform independent.
- Ensure file system, player, FFmpeg/FFprobe, and database location rules stay behind platform boundaries.
- Record every shared boundary change in `ARCHITECTURE.md`.

## Prompt For New Chat

```text
这是 Chat 1 / Architecture + Cross Platform Boundary。项目路径：<project-root>。

请先阅读：
- PROJECT.md
- ARCHITECTURE.md
- CURRENT_TASK.md
- ROADMAP.md
- <private-planning-document>
- docs/chat_tasks/CHAT_1_ARCHITECTURE.md

后续方向以 local_tag_player_flutter_cross_platform_plan_v2.md 为准；当前项目实现只代表历史状态。

职责：只做架构基建、模块边界、跨平台接口、项目规则和架构版本记录。不要抢 Media Library、Tag UI、Thumbnail、Player、Tag Manager 的功能实现。

当前目标：推进 Architecture Baseline 0.4.0：根据规划文件收口 FileSystemAdapter、PlayerBackend、FFmpegBackend、DatabaseProvider，并规划 LibraryRepository、TagRepository、CacheRepository、PlaybackRepository、LayoutSize(compact/medium/expanded)。可小步评估从 part 迁移到普通 import，但必须保持 Windows 行为不变。

不要重写播放器、SQLite 查询、缩略图队列或 UI。

修改代码后运行：
- flutter analyze
- flutter build windows --debug

涉及底层边界时更新 ARCHITECTURE.md、ROADMAP.md 和本文件版本记录。
```

## Change Log

- `0.4.1`: Opened next Architecture baseline for future low-risk import migration and incremental adoption of the 0.4.0 contracts.
- `0.4.0`: Rebased Architecture ownership on `local_tag_player_flutter_cross_platform_plan_v2.md`, implemented repository interface stubs, shared `LayoutSize` / `LayoutBreakpoints`, expanded platform boundary methods, and extended tag/filter/playback model stubs while keeping Windows behavior unchanged.
- `0.3.0`: Added `FileSystemAdapter`, `PlayerBackend`, `FFmpegBackend`, `DatabaseProvider` interface stubs and platform-independent tag/filter/playback/cache/diagnostic model stubs without changing Windows behavior.
- `0.2.0`: Added core boundary docs, multi-chat coordination, roadmap ownership rules.
