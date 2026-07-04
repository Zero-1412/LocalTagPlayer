# CHAT_3_MEDIA_LIBRARY_TAG_UI.md

Current Version: `0.2.1`
Status: completed
Owner: Chat 3 / Media Library Tag UI

## Planning Source

Primary source:

```text
<private-planning-document>
```

If this task document conflicts with that file, the external plan wins.

## Scope

Owns the media-library homepage Tag discovery UI. This is feature UI, not final visual polish.

Allowed:

- `LibraryPage` layout required for Tag discovery.
- Filter sidebar.
- Filter bar.
- Tag chips.
- Result count UI.
- Clear filter UI.
- Save smart list entry UI.
- First pass of `expanded`, `medium`, `compact` layout behavior for Tag discovery.

Do not do:

- SQLite schema changes.
- Core Tag query behavior.
- Player backend or FFmpeg internals.
- Broad final visual polish unrelated to Tag discovery.

## P0 Tasks

- Upgrade homepage from flat tags to web-style grouped filter UI.
- Left side: grouped tag filter.
- Top: search file name / path / tag / alias.
- Center top: current filter chips.
- Show current result count and total count.
- Support clear filter.
- Support excluded tag UI, for example `[-NTR x]`.
- Add save current filter as smart list entry.
- Ensure click-to-play still enters the current filtered playback queue.

## Responsive Requirements

```text
expanded: persistent left filter sidebar
medium: collapsible filter sidebar
compact: filter in Drawer / BottomSheet
```

Do not build complex animation first. Keep the layout practical and stable.

## Prompt For New Chat

```text
这是 Chat 3 / Media Library Tag UI。项目路径：<project-root>。

请先阅读：
- PROJECT.md
- ARCHITECTURE.md
- CURRENT_TASK.md
- ROADMAP.md
- <private-planning-document>
- docs/chat_tasks/CHAT_3_MEDIA_LIBRARY_TAG_UI.md

后续方向以 local_tag_player_flutter_cross_platform_plan_v2.md 为准；当前项目实现只代表历史状态。

职责：负责媒体库首页的网页式 Tag 检索 UI。注意：Tag 检索 UI 是核心功能，不是最后才做的普通美化。不要改 SQLite schema、Tag 查询核心、播放器内核或缩略图队列。

当前目标：把首页从平铺标签升级为分组筛选 UI。实现左侧分组标签筛选、顶部当前筛选 Chips、结果数量、清空筛选、排除标签显示、保存筛选入口，并保持点击播放进入当前筛选结果队列。预留 expanded / medium / compact 响应式结构。

修改代码后运行：
- flutter analyze
- flutter build windows --debug

涉及 shared layout token、src/core 或数据/平台边界时，先同步 Architecture 或更新 ARCHITECTURE.md 基线记录。
```

## Change Log

- `0.2.1`: Acceptance pass fixes: synchronized equivalent legacy first/second-level tag state with grouped tag state to avoid duplicated filters, and made the active filter bar wrap on narrow layouts.
- `0.2.0`: Implemented first-phase Media Library Tag discovery UI: grouped filter sidebar, active filter chips, result count, clear filter, exclude tag chips, save smart list TODO entry, and expanded/medium/compact layout structure.
- `0.1.0`: Created task from `local_tag_player_flutter_cross_platform_plan_v2.md`; Chat 3 owns Media Library Tag UI.
