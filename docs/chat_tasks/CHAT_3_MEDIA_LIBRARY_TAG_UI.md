# CHAT_3_MEDIA_LIBRARY_TAG_UI.md

Current Version: `0.2.21`
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

## 0.2.17 Main Source + Local Library Pass

- Media Library, Recent Playback, and Smart Favorites now behave as lightweight main result sources. Recent/Favorites use in-memory lists, while Media Library clears filters and immediately rebuilds the all-video result state.
- Recent Playback gained a result-area management toolbar with single select, select all, delete selected, and clear all. These actions only clear `lastPlayedAt`; they do not delete video files, tags, favorites, or playback progress.
- "My tag library" was renamed to "Local Media Library". Its add/remove affordances now manage local root paths only and no longer open the tag-add dialog.
- Local Media Library root browsing displays folders as folder entries and indexed videos as normal video cards/list rows. The existing grid/list toggle continues to control the layout.
- Settings was removed from the top toolbar and kept at the bottom of the left function bar. Debug exe smoke testing confirmed the bottom entry opens the existing settings page.

## 0.2.18 Local Folder Back + Secondary Cleanup Pass

- Added `LOCAL_TAG_PLAYER_DATA_DIR` as a temporary profile override for reversible UI smoke tests. Normal app data paths are unchanged when the variable is absent.
- Temporary-profile mouse QA covered Recent Playback single delete, select-all delete, and clear-all. Each path cleared only `lastPlayedAt` in the temporary database.
- Temporary-profile entry switching timings were recorded: Media Library first switch ~213ms, Recent Playback ~63ms, Smart Favorites ~59ms, back to Media Library ~51ms.
- Hot secondary tags now render only the secondary tag name. The parent-primary mini label is hidden in the hot section while remaining available in the full secondary tab.
- Secondary discovery filters out the default-album tag so it does not appear in hot/all secondary candidates.
- Expanded primary cards filter real child tags named default album and keep only the leading virtual default-album chip.
- Local Media Library folder browsing now has a path back stack. Folder clicks push the current path, and both the header back button and mouse back side-button pop to the previous path.
- Recent Playback cleanup gained unit coverage for single-selected deletion and bulk clear target selection, ensuring unplayed videos are not affected.

## 0.2.19 Stable Smoke Harness Pass

- Replaced screenshot-coordinate smoke testing for the highest-risk media-library clicks with stable widget keys and harnesses.
- Added `LibrarySmokeKeys`, `LocalLibrarySmokeHarness`, and `TagDiscoverySmokeHarness` so tests can drive the real local-library folder view and right tag-discovery panel without opening the real database or depending on desktop DPI.
- Widget smoke coverage now includes local-folder open, header back button, mouse back side-button, primary tag expand/collapse, child "expand all / collapse", and primary/secondary tab switching.
- Validation passed: `dart format`, `flutter test`, `flutter analyze`, `flutter build windows --debug`; debug exe also starts with a temporary profile and stays running for the launch smoke window.

## 0.2.20 List Row + Result State Smoke Pass

- Extended the stable smoke harness to cover dense-list local folder navigation, list-row Play/Favorite/More controls, and right-panel tag result-state assertions.
- Added stable keys for list-row controls and tag chips. The list-row smoke test waits past the row double-click recognition window so single-click button assertions are deterministic.
- The right tag harness now renders a small result-state surface: selecting the default album shows all current-primary sample results, while selecting Child01 narrows the surface to only Child01.
- Validation passed: `dart format`, `flutter test` with 16 tests, `flutter analyze`, and `flutter build windows --debug`.

## 0.2.21 Non-Maximized Visibility Pass

- Fixed normal debug-window overflow by allowing the expanded top search field to shrink when the actual row width is constrained by the right tag panel.
- Increased single-column video-card height so 16:9 thumbnails, titles, tags, and bottom actions fit without Flutter overflow stripes.
- List-row actions now switch to compact icon controls at medium row widths so Play/Favorite/More stay visible instead of pushing past the row edge.
- Computer-use QA covered normal and maximized debug windows: top toolbar, list-row actions, right tag panel, and local-library back entry stayed inside the visible window.
- Validation passed: `dart format`, `flutter test` with 16 tests, `flutter analyze`, and `flutter build windows --debug`.

## 0.2.15 Sidebar + List QA Pass

- Left sidebar was reduced to the workflow entries that still serve the media-library loop: duplicate "playback history", low-value "current filters", and "common tags" entries were removed.
- "Recent playback" now opens the recent-video dialog directly from the sidebar.
- Directory Manager gained a non-destructive root removal affordance. It only updates configured roots and deliberately does not delete disk files or purge indexed videos.
- "My tag library" became a scrollable shortcut list with add/remove controls. Adding can reuse an existing tag or create a tag; removing only removes the shortcut, not the tag record or video relationships.
- Right-panel tag counts now use a stable all-library count cache so unrelated tag counts stay visible after selecting a primary or secondary tag.
- The top toolbar search field no longer consumes all expanded-width space, so Tag Center, favorite filter, sorting, and grid/list controls stay visible on wide desktop windows.
- Dense list mode was tightened after real-window QA: rows use a readable content width, slightly taller row extent, and visible Play/Favorite/More controls without overflow.
- Validation: `dart format`, `flutter analyze`, `flutter test`, and `flutter build windows --debug` passed. Real-window QA confirmed Recent Playback, Directory Manager, toolbar visibility, and list-mode no-overflow; scripted Win32 coordinates still did not reliably open the list-row More dialog, so that exact hit path needs one manual mouse pass.

## 0.2.16 Main Entry Behavior Pass

- Recent Playback is now a main result mode instead of a dialog. The center grid/list displays recently played videos and passes that visible list to the player queue.
- The Media Library sidebar item acts as a reset entry: it clears search, primary/secondary/group/excluded/favorite filters and returns to all videos.
- Settings is exposed from both the top toolbar and the left sidebar, reusing the existing cache/playback settings page.
- The "My tag library" add dialog now filters existing tags while typing and reports create/save errors through SnackBar.
- Opening a video from Recent Playback uses a "Recent Playback" queue title so the player does not show a misleading all-library filter summary.

## 0.2.5 Reference Layout Pixel Pass

- Top toolbar: search width now has a desktop maximum so it stays close to the reference proportions instead of stretching across ultra-wide windows.
- Current filter row and right tag filter panel keep the reference two-row ownership: toolbar spans the content area, then center filter/results and right tag card split below it.
- Right tag filter panel now reads as an independent card with reference-like outside spacing, fixed desktop width, softer nested group treatment, and segmented tabs.
- Interaction smoke test covered favorite filter, sort menu, grid/list toggle, right-panel tab switching, tag chip selection, and filter chip removal.
- Follow-up: recheck the “clear all” hit target/disabled state because coordinate automation did not reliably trigger it.

## 0.2.6 Right Tag Panel Interaction Pass

- Primary tags now use a local accordion state: clicking a collapsed primary row expands that specific primary tag and shows its own child tags.
- The primary panel defaults to more visible primary candidates and provides a “more primary tags” control instead of hard-limiting the list to a tiny subset.
- Expanded primary rows separate “expand this row” from “filter by this primary tag” through a dedicated filter icon.
- Child tag chips have larger hit targets and stable Chinese tooltips; smoke test confirmed selecting a child tag adds the active filter chip and updates the result count.
- The active filter bar clear-all button is fixed outside the horizontal chips scroller to reduce missed clicks.

## 0.2.7 Right Panel Chip Expansion Pass

- Expanded primary cards now default to 9 secondary chips, matching the reference card density more closely.
- The “expand all” affordance is now a full-row lightweight button and expands only the current primary tag’s secondary chips in local UI state.
- The “more primary tags” affordance is visually weakened into a short full-row text button at the bottom of the primary list.
- The hot secondary tag area has tighter reference-like vertical rhythm: fewer default primary rows so the section is visible, fixed 3-column chips, smaller title, and a centered fixed-height lightweight more button.
- Cleaned residual mojibake comments and tooltip notes in the right tag filter panel source so visual QA is not polluted by historical encoding artifacts.
- Smoke test covered app startup, right-panel visibility, segmented tab switching, and primary accordion row clicks. Coordinate automation for the lower “expand all” button was unstable under the current desktop/DPI environment, so that button still needs one manual click confirmation.

## 0.2.8 Right Panel Mutual Selection Pass

- Primary collapsed rows now select the clicked primary tag's "default album" and expand that primary row, so primary tag clicks are mutually exclusive.
- Every expanded primary card includes a virtual "默认专辑" child chip. It represents "all videos under the current primary tag" by keeping only the primary tag filter active; it does not create or persist a new tag.
- Child tag chips under the same primary are mutually exclusive. Selecting a new child replaces the old child; selecting the already active child returns to the current primary default album.
- Expanded primary headers use a fixed-height full-row hit target, and the child "expand all" control remains a per-primary toggle that can expand and collapse local UI state.
- Debug exe smoke test confirmed real child-chip clicks update the active filter chips, result count, and visible video paths for "崩铁 + 克拉拉/停云". Windows DPI made coordinate automation unreliable for final header-collapse and expand-all screenshots, so those two paths still need a short manual mouse confirmation.

## 0.2.9 Right Panel Primary Sort + Filter Targeting Pass

- Primary tags now default to 7 visible rows, with a lightweight "more primary tags" control that expands and collapses the remaining rows.
- Primary tags have a local sort control for count-descending and name-ascending order. Sorting affects only the right discovery panel and does not change filter semantics.
- Count sorting now uses the visible result count so the selected "按数量" control matches the displayed list order.
- Right-panel child tag selection now maps folder.child tagId back to the legacy child tag name used by `FilterQuery.childTagId`.
- Child tag fallback matching resolves a child tag's parentId back to the primary tag name before checking `VideoItem.childTags`, so default album and secondary tags can target videos under the correct primary tag even when a legacy path-derived lookup is used.
- The right panel scroll list has its own Scrollbar and right-side content padding so the thumb does not overlap primary rows.

## 0.2.10 Right Panel Stable Sorting Pass

- Removed the separate primary-sort label and shortened the sort options to "数量 / 名称 / 常用" so the control stays lightweight.
- Added a local "常用" primary sort mode based on in-session primary tag click counts. It does not persist data or change schema.
- Count sorting now uses the maximum known primary count with `usageCount` fallback, so selecting a primary tag no longer promotes that tag or reshuffles the rest of the list because of the active filter.
- Expanded primary state no longer falls back to expanding the first visible row when the previously expanded tag is outside the current visible slice.
- The "全部二级标签" tab now lists folder child tags from the tag library even when current result counts are zero, avoiding an empty tab after active filtering.

## 0.2.11 Right Panel Interaction Smoothness Pass

- Collapsed primary rows now only expand/collapse local UI. Filtering is handled by the expanded card's default-album chip or child chips, reducing click conflicts and delayed expansion.
- The result grid no longer uses a filter-keyed `AnimatedSwitcher`; it keeps a stable repaint boundary during tag switching to reduce visual shaking.
- The expanded desktop layout now supports collapsing the right tag filter panel into a slim rail and restoring it without clearing filter state.

## 0.2.12 Library Filter Refresh Pipeline Pass

- Library filtering no longer runs synchronously from `build()`. The page keeps cached filtered videos and candidate counts in State.
- Filter changes now update selected chips immediately, then refresh filtered videos and candidate counts in revision-guarded stages.
- The current filter bar shows a lightweight spinner while videos or candidate counts are refreshing, without blocking grid scrolling or clicks.

## 0.2.13 Main Surface Click Smoke Pass

- Main media-library controls were smoke tested in the debug exe: sorting, favorite filtering, result view toggle, right-panel collapse/restore, tag tabs, tag chips, tag manager navigation, playback history, directory manager, card more/edit dialog, and play entry.
- The active filter bar now includes a search-keyword chip. Search is part of `FilterQuery`, so it must be visible and individually clearable from the current filter surface.
- The left sidebar playback-history and directory-manager entries now open lightweight dialogs instead of being inert navigation rows. These dialogs do not change schema, tag semantics, or playback queue behavior.

## 0.2.14 Dense List View Pass

- Dense result mode now uses a real vertical `ListView.builder` instead of a card-like grid with smaller dimensions.
- Each list row keeps the existing media actions but changes the visual structure to thumbnail, title/path/tag summary, and compact right-side actions.
- Repaired source damage exposed by historical mojibake cleanup and restored the helper widgets/classes needed for media-library build stability.
- Cleaned remaining mojibake comments and visible strings in the touched media-library source files.
- Validation passed: `dart format`, `flutter analyze`, `flutter build windows --debug`, and `flutter test`. The widget test taps the result-view toggle and confirms dense mode is selected.

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

- `0.2.20`: Extended stable smoke coverage to list-row Play/Favorite/More, local-library dense-list back navigation, and right tag chip result-state assertions. No schema, query, player queue, or cache queue behavior changed.
- `0.2.21`: Fixed non-maximized window overflow in the media-library top bar, grid cards, and list-row actions, then verified normal and maximized debug windows with computer-use. No schema, query, player queue, or cache queue behavior changed.
- `0.2.19`: Added stable key/harness smoke tests for local-library back paths and right-tag-panel expand/collapse paths, avoiding screenshot-coordinate desktop automation for these flows. No schema, query, player queue, or cache queue behavior changed.
- `0.2.10`: Stabilized primary count sorting, added runtime-only frequent sorting, removed the extra primary-sort label, shortened sort option labels, prevented fallback expansion of the first row, and kept the all-secondary tab populated under active filters. No schema, player queue, or cache queue behavior changed.
- `0.2.11`: Decoupled primary row expansion from filtering, stabilized result-grid repaint during tag switches, and added a collapsible right tag-filter rail. No schema, query, player queue, or cache queue behavior changed.
- `0.2.12`: Moved library filter result and candidate-count computation out of `build()` into cached, revision-guarded staged refreshes with a lightweight refresh indicator. No schema, player queue, or cache queue behavior changed.
- `0.2.9`: Added primary-list expand/collapse at 7 rows, local count/name sorting, child tagId-to-name query mapping, parentId-to-primary-name fallback matching, and right-panel scrollbar padding. No schema, player queue, or cache queue behavior changed.
- `0.2.8`: Added right-panel default-album selection, mutually exclusive primary and child selection, larger expanded header hit targets, and preserved local expand/collapse state without changing schema, query contracts, player queue, or cache queue behavior.
- `0.2.7`: Tuned the right tag filter panel’s expanded primary card density, changed “expand all” into a full-row local UI control, weakened the “more primary tags” affordance, made hot secondary tags visible in the reference viewport with fixed 3-column rhythm, and cleaned right-panel mojibake comments. No schema, query, player queue, or cache queue behavior changed.
- `0.2.6`: Reworked the right tag filter panel interaction model: primary tags now expand their own secondary tags, more primary candidates can be shown, primary filtering has a separate icon, child chips have larger hit targets, and clear-all is no longer inside the horizontal chip scroller. No schema, query, player queue, or cache queue behavior changed.
- `0.2.4`: Corrected the expanded Media Library structure against the reference red boxes: the top toolbar now spans both the result area and the right tag filter panel, while the active filter bar remains scoped to the center result column and the tag filter panel starts on the second row. No schema, query, player queue, or cache queue behavior changed.
- `0.2.3`: Aligned the Media Library top selected area with the reference layout: flexible search row with tag manager, favorite filter, sort, and view toggles; active filter row now shows direct chips, clear-all action, and result count in one white bar. No schema, tag query, player queue, or cache queue behavior changed.
- `0.2.2`: Improved Media Library tag interaction responsiveness: `LibraryPage` caches the current filtered result and result counts in State, moves expensive refresh work out of `build()`, updates selected tags/chips immediately, refreshes videos and candidate counts in staged async passes, and guards stale async completions with `_filterRevision`. Lightweight busy indicators show refresh progress without blocking the whole page.
- `0.2.1`: Acceptance pass fixes: synchronized equivalent legacy first/second-level tag state with grouped tag state to avoid duplicated filters, and made the active filter bar wrap on narrow layouts.
- `0.2.0`: Implemented first-phase Media Library Tag discovery UI: grouped filter sidebar, active filter chips, result count, clear filter, exclude tag chips, save smart list TODO entry, and expanded/medium/compact layout structure.
- `0.1.0`: Created task from `local_tag_player_flutter_cross_platform_plan_v2.md`; Chat 3 owns Media Library Tag UI.
