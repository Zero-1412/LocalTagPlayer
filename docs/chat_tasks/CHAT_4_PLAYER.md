# CHAT_4_PLAYER.md

Current Version: `0.3.0`
Status: active
Owner: Chat 4 / Player Filter Queue + PlayerBackend

## Planning Source

Primary source:

```text
<private-planning-document>
```

If this task document conflicts with that file, the external plan wins.

## Scope

Owns playback stability, filtered playback queue consumption, hardware decoding, right queue behavior, diagnostics, `PlaybackSession`, and `PlayerBackend` implementation.

Allowed:

- `PlayerPage` and future `PlayerService`.
- Right queue/list behavior.
- Playback diagnostics.
- `PlaybackSession` consumption.
- Future `platform/player`.

Do not do:

- Tag database/schema redesign.
- Thumbnail queue internals.
- Broad UI visual polish.
- Advanced non-core player features like subtitles, audio tracks, frame-step, A-B loop, filters, or complex aspect-ratio controls unless explicitly requested later.

## P0/P1 Tasks

- Player queue must represent the current filtered result, not an unrelated global list.
- Preserve filter context when entering and returning from player.
- Add or maintain current index display, for example `1/1661`.
- Right queue title should summarize the current filter.
- Support switching videos from the right queue.
- Keep video information entry stable.
- Keep playback diagnostics entry stable.
- Make diagnostics copyable later.
- Move player page behind `PlayerBackend` when practical, without rewriting the player core.
- Fix async open/jump race risks before adding advanced player features.

## Prompt For New Chat

```text
这是 Chat 4 / Player Filter Queue + PlayerBackend。项目路径：<project-root>。

请先阅读：
- PROJECT.md
- ARCHITECTURE.md
- CURRENT_TASK.md
- ROADMAP.md
- <private-planning-document>
- docs/chat_tasks/CHAT_4_PLAYER.md

后续方向以 local_tag_player_flutter_cross_platform_plan_v2.md 为准；当前项目实现只代表历史状态。

职责：负责筛选结果播放队列、播放器右侧列表、播放稳定性、诊断、硬解和 PlayerBackend。不要大改标签数据库、缩略图队列或 UI 美化。

当前目标：播放器成为筛选结果消费端。从哪个 FilterQuery / PlaybackSession 进入，右侧列表就显示哪个筛选队列。显示当前序号如 1/1661，右侧标题显示筛选摘要，返回媒体库后筛选状态不丢。逐步把播放器页面收敛到 PlayerBackend，但不要重写播放器内核。

暂不优先新增字幕、音轨、逐帧、A-B 循环、滤镜、复杂画面比例等专业播放器功能。

修改代码后运行：
- flutter analyze
- flutter build windows --debug

涉及 PlayerBackend 接口、src/core 或共享模型时，先同步 Architecture 或更新 ARCHITECTURE.md 基线记录。
```

## Change Log

- `0.3.0`: Completed first Player Filter Queue pass: PlayerPage consumes a safe filtered queue copy, shows filter summary context, keeps right-side child-tag switching inside the filtered queue, and serializes rapid open requests so the latest jump wins. Acceptance follow-up normalized the empty-filter title, index display, and pending-open drain behavior.
- `0.2.0`: Rebased Player task on the external cross-platform plan and focused it on filtered queue consumption plus PlayerBackend.
- `0.1.0`: Created task template from roadmap.
