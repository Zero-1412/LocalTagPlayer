# ROADMAP.md

## Planning Source Of Truth

The controlling product and architecture plan is:

```text
<private-planning-document>
```

When this project document conflicts with older project habits, the cross-platform plan wins. The current app state is treated as implementation history, not as the product direction.

The project is not a PotPlayer / VLC replacement. The target is:

```text
Tag-driven local video discovery player
= local scan
+ SQLite media library
+ multi-level and grouped tags
+ tag alias search
+ web-style filter UX
+ filtered playback queue
+ basic player
+ cache and diagnostics
+ Flutter cross-platform shell
```

## Core Loop

All later tasks should protect this loop:

```text
scan local folders
-> derive initial folder tags
-> add/edit player-owned tags
-> distinguish folder/manual/rule/filename/import/auto tag sources
-> filter by grouped tags and keyword
-> show current filter chips and result count
-> use filtered result as playback queue
-> player consumes the current queue
-> fix tags through tag manager / batch tagging
-> keep thumbnails, media details, diagnostics stable
```

## Non-Goals For Current Phase

Do not spend primary effort on:

- subtitle, audio track, frame-step, A-B loop, filters, rotation, advanced playback controls.
- over-polished animation or purely visual redesign before Tag discovery UX is stable.
- Web support.
- deep Android / iOS support.
- replacing the current Windows app before desktop behavior is stable.

## Architecture Baseline

Completed baseline: `Architecture Baseline 0.4.0`

Current target baseline: `Architecture Baseline 0.4.1`

Completed 0.3.0 scope:

- Added lightweight stubs for `FileSystemAdapter`, `PlayerBackend`, `FFmpegBackend`, `DatabaseProvider`.
- Added platform-independent stubs for `TagGroup`, `TagItem`, `FilterQuery`, `PlaybackSession`, `CacheStatus`, `DiagnoseStatus`.
- Kept current Windows behavior unchanged.
- Kept current `part` structure as a transition state.

Completed 0.3.1 scope:

- Added tag aliases to the platform-independent tag model.
- Added grouped/excluded tag semantics to `FilterQuery.matches`.
- Defined group AND, in-group OR, excluded NOT matching behavior.
- Routed existing media-library filtering through `FilterQuery` while keeping current Windows behavior.

Completed 0.4.0 scope:

- Align contracts with the cross-platform plan instead of current implementation habits.
- Add or refine boundaries for `LibraryRepository`, `TagRepository`, `CacheRepository`, `PlaybackRepository`.
- Add shared layout semantics for `compact`, `medium`, `expanded`.
- Refine `FileSystemAdapter`, `PlayerBackend`, `FFmpegBackend`, and `DatabaseProvider` contracts without replacing current Windows implementations.
- Keep `part` as the active transition structure after evaluating import migration risk for this small baseline.
- Do not rewrite player behavior, SQLite query behavior, thumbnail queue behavior, or UI flows in Architecture.

## Required Platform Boundaries

`FileSystemAdapter` owns:

- picking directories.
- checking existence.
- recursive video scanning.
- reveal in file manager.
- path normalization and relative path rules.

`PlayerBackend` owns:

- open/play/pause/seek/stop/dispose.
- playback state stream.
- diagnostics stream.
- platform player implementation details.

`FFmpegBackend` owns:

- locating FFmpeg / FFprobe.
- availability and version reporting.
- media probing.
- thumbnail generation.
- platform-specific executable or library access.

`DatabaseProvider` owns:

- database open/close.
- database file location.
- schema version.
- migration dispatch.

Platform-independent code must not depend on Windows, mpv, FFmpeg executables, or concrete file-system APIs.

## Tag Discovery Design

Do not stop at the current first-level / second-level folder tag tree. Keep it as an initial source, then build grouped tags.

Recommended groups:

```text
作品: 原神 / FGO / 东方 / 崩坏三
角色: 丽莎 / 雷电将军 / 丝柯克 / miku
类型: 3D / MMD / mod / vtuber
来源: Iwara / B站 / 本地录制
质量: 720p / 1080p / 4K / H264 / H265
状态: 收藏 / 未播放 / 已播放 / 缩略图异常 / 视频信息异常
```

Filter semantics:

```text
Different groups: AND
Same group: OR
Excluded tags: NOT
Keyword: file name / path / tag name / tag alias
```

Example:

```text
作品 = 原神
AND (角色 = 丽莎 OR 雷电将军)
AND (类型 = 3D OR MMD)
AND NOT NTR
```

## Target Models

`TagGroup` should move toward:

- `id`
- `name`
- `displayName`
- `sortOrder`
- `allowMultiSelect`
- `defaultLogic`: `sameGroupOr` or `sameGroupAnd`

`TagItem` should move toward:

- `id`
- `name`
- `displayName`
- `groupId`
- `parentId`
- `color`
- `aliases`
- `usageCount`
- `isFavorite`
- `isHidden`
- `sortOrder`

`FilterQuery` should move toward:

- `keyword`
- `includeTagIds`
- `excludeTagIds`
- `selectedGroupTags`
- `sortRule`
- `favoriteOnly`
- `unplayedOnly`
- `errorOnly`

`PlaybackSession` should move toward:

- `sourceFilter`
- `queue`
- `currentIndex`
- `currentVideoId`
- `createdAt`

## Media Library Homepage

The library homepage is a Tag discovery page, not a flat tag browser.

Recommended layout:

```text
top: search file name / path / tag / alias
left: grouped tag filter sidebar
center top: current filter chips + result count + clear + save smart list
center: video card grid
```

Must support:

- grouped tag filters.
- current filter chips, for example `[原神 x] [丽莎 x] [3D x] [-NTR x]`.
- per-tag counts.
- clear filter.
- excluded tags.
- save current filter as a smart list entry.
- current filtered result as the playback queue.

Responsive rules:

```text
expanded: persistent left filter sidebar
medium: collapsible filter sidebar
compact: filter in Drawer / BottomSheet
```

## Player Page

The player consumes the current filter result. It should not become a general professional player first.

Must support:

- right queue bound to current `FilterQuery` / `PlaybackSession`.
- current index display such as `1/1661`.
- queue title or summary for the current filter.
- return to library without losing filter state.
- switch videos from right queue.
- stable video information entry.
- stable playback diagnostics entry.
- copyable diagnostics later.
- UI depending on `PlayerBackend`, not concrete player internals.

Do not prioritize:

- subtitles.
- audio tracks.
- frame-step.
- A-B loop.
- filters.
- complex aspect-ratio controls.

## Folder Tags And Stable Identity

Keep current folder-derived first/second tags, but treat them as initial `folder` source tags.

Target identity model:

```text
videoId = stable database identity
fingerprint = file/media identity
path = current mutable location
```

Video tags, favorites, play records, and playback progress bind to `videoId`, not mutable `path`.

Future `video_tags` relation should move toward:

```text
videoId
tagId
source: manual / folder / rule / filename / import / auto
locked
createdAt
updatedAt
```

Rules:

- manual tags are never removed because a file moved.
- folder tags can be recalculated from path rules.
- rule and filename tags can be recalculated by their owners.
- important tags can be locked.
- missing files are marked `missing`; records are not immediately deleted.
- relink and bulk path replacement come after stable identity design.

## New Import Flow

Recommended flow:

```text
new video appears in monitored folder
-> scan detects it
-> path rules derive folder tags if possible
-> otherwise put it in 未分类 / 待整理 / 新导入
-> user batch-tags it in the app
-> optional future action can move files by tag
```

Moving files by tag is optional. It must never be required for classification.

## Chat Execution Plan

### Chat 1: Architecture + Cross Platform Boundary

Task file: `docs/chat_tasks/CHAT_1_ARCHITECTURE.md`

Owns architecture, contracts, module boundaries, route rules, and version records.

Allowed:

- `main.dart`, core/model boundaries, future import migration.
- `FileSystemAdapter`, `PlayerBackend`, `FFmpegBackend`, `DatabaseProvider`.
- repository interface planning.
- layout-size shared contract.
- documentation and versioning.

Do not do:

- rewrite player behavior.
- rewrite SQLite query behavior.
- rewrite thumbnail queue.
- broad UI redesign.

Next task:

- progress `Architecture Baseline 0.4.1` with low-risk import migration or implementation adoption of the 0.4.0 contracts.

### Chat 2: Tag Model + Filter Engine + Media Library

Task file: `docs/chat_tasks/CHAT_2_MEDIA_LIBRARY.md`

Owns SQLite, scanning, folder tags, grouped tag model, aliases, filter engine, stable identity planning.

P0:

- implement grouped tag model.
- implement aliases.
- implement `FilterQuery`.
- implement AND/OR/NOT filter semantics.
- keyword search across file name, path, tag name, alias.
- result counts.
- pass filtered result to player queue.

P1:

- folder/manual/rule/filename/import/auto tag sources.
- `video_tags.source` and `locked`.
- stable `videoId + fingerprint + mutable path`.
- `missing`.
- relink and bulk path replacement.

### Chat 3: Media Library Tag UI

Task file: `docs/chat_tasks/CHAT_3_MEDIA_LIBRARY_TAG_UI.md`

Owns feature UI for Tag discovery and the first responsive layout pass.

P0:

- grouped filter sidebar.
- current filter chips.
- result count.
- clear filter.
- excluded tag UI.
- save smart list entry.
- preserve click-to-play filtered queue behavior.
- expanded/medium/compact structure.

Do not wait for final visual polish to build Tag discovery UI.

### Chat 4: Player Filter Queue + PlayerBackend

Task file: `docs/chat_tasks/CHAT_4_PLAYER.md`

Owns playback stability, filtered queue consumption, player diagnostics, and `PlayerBackend` implementation.

P0/P1:

- player queue is current filtered result.
- player displays current index like `1/1661`.
- right queue title summarizes current filter.
- return to library preserves filter state.
- right queue switching remains stable.
- player page moves behind `PlayerBackend` without rewriting the player core.

### Chat 5: Thumbnail + Diagnostics + FFmpegBackend

Task file: `docs/chat_tasks/CHAT_5_THUMBNAIL_DIAGNOSTICS.md`

Owns thumbnail queue, FFprobe cache, cache diagnostics, failures, retry, FFmpeg backend implementation.

P0/P1:

- keep playback-time queue load conservative.
- route FFmpeg/FFprobe through `FFmpegBackend`.
- expose availability/version/status.
- retry failed cache tasks.
- clear failure records.
- abnormal file list.
- card-based diagnostics page.

### Chat 6: Tag Manager + Batch Tagging

Task file: `docs/chat_tasks/CHAT_6_TAG_MANAGER.md`

Owns long-term tag maintenance UI and batch operations.

P1:

- tag manager page.
- tag search.
- create/rename/delete tags.
- merge duplicate tags.
- aliases.
- tag groups.
- hide/favorite/sort tags.
- batch tag current filtered result.
- batch remove tags.

### Chat 7: Responsive UI + Platform Polish

Task file: `docs/chat_tasks/CHAT_7_RESPONSIVE_UI.md`

Owns final visual consistency and platform polish after core Tag UX works.

P1/P2:

- unified card, button, dialog, sidebar styles.
- light media-library mode and dark player mode consistency.
- complete `compact`, `medium`, `expanded` layouts.
- macOS/Linux adaptation notes.

## Priority Table

### P0

1. Keep Windows desktop stable.
2. Keep folder-derived first/second tags during transition.
3. Grouped tag model.
4. `FilterQuery`.
5. Group AND, in-group OR, excluded NOT.
6. Keyword search by file name, path, tag name, alias.
7. Tag result counts.
8. Current filter state chips.
9. Filter result becomes playback queue.
10. Return from player preserves filter state.
11. Core platform boundaries.

### P1

1. Separate folder/manual tag sources.
2. `video_tags.source` and `locked`.
3. Stable identity: `videoId + fingerprint + mutable path`.
4. Missing state.
5. Relink.
6. Bulk path replacement.
7. Tag Manager.
8. Batch tagging.
9. Saved filters / smart lists.
10. Recent play / continue play.
11. Cache failure retry.
12. Abnormal file list.
13. Diagnostics cards.
14. Initial responsive layout.

### P2

1. Automatic tagging rules.
2. Tag import/export.
3. Advanced search syntax.
4. Optional move-by-tag file organization.
5. Advanced fingerprint dedupe.
6. Advanced player features.
7. macOS/Linux adaptation.
8. Android/iOS exploration.
9. Web exploration, low priority.

## Versioning Rules

- Each Chat owns one task document in `docs/chat_tasks/`.
- Chat documents must follow this roadmap and the external cross-platform plan.
- If implementation conflicts with the external plan, update implementation or document a temporary deviation with reason and owner.
- Any change to `src/core`, platform boundaries, schema, identity model, or shared service contracts must update `ARCHITECTURE.md`.
- Every implementation chat runs:

```powershell
flutter analyze
flutter build windows --debug
```

## New Chat Rule

When opening a new chat, paste the matching prompt from `docs/chat_tasks/CHAT_*`. The new chat must first read:

- `PROJECT.md`
- `ARCHITECTURE.md`
- `CURRENT_TASK.md`
- `ROADMAP.md`
- `<private-planning-document>`
- its own `docs/chat_tasks/CHAT_*.md`
