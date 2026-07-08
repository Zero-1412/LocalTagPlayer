---
name: ltp-media-library-tag-ui
description: Local Tag Player 媒体库标签发现 UI 技能。用于 grouped filter sidebar、current filter chips、result count、save smart list 入口、响应式媒体库布局或 UI redesign 阶段规划。
---

# Local Tag Player 媒体库标签 UI

用于媒体库首页 UX、分组过滤、过滤 chips、结果数、排除标签展示、保存筛选入口和响应式布局。

## 上下文

通常是 Level 2。

读取：

```text
AGENTS.md
PROJECT.md
CURRENT_TASK.md
docs/chat_tasks/CHAT_3_MEDIA_LIBRARY_TAG_UI.md
相关 LibraryPage/widgets 文件
```

只有 final polish 需要时读取 CHAT_7。只有涉及 shared layout/core 时读取 `ARCHITECTURE.md`。

## 产品规则

媒体库首页是标签发现页，不是扁平标签浏览器，也不是单纯视觉 polish。

```text
top: search file name/path/tag/alias
left: grouped tag filter sidebar
center top: current filter chips + result count + clear + save smart list
center: video card grid
```

响应式：

```text
expanded: persistent left filter sidebar
medium: collapsible sidebar/sheet
compact: filter Drawer/BottomSheet
```

## Phase 1 指引

- 先修 overflow 和稳定性。
- 复用现有 filter/query state。
- 保留 click-to-play filtered queue。
- 避免新增 data model/schema。

## 禁止

不要修改：

```text
schema
FilterQuery
TagQueryService
player queue
player backend
thumbnail/media queue
```

## 对抗式审查

最终审查必须包含：

```text
schema: unchanged / changed with migration notes
FilterQuery/TagQueryService: unchanged / changed intentionally
filtered queue: unchanged / changed intentionally
thumbnail/media queue: unchanged / changed intentionally
user data: preserved / risk noted
prompt impact: satisfies first principles without extra context, scope, output cost, or other side effects
```
