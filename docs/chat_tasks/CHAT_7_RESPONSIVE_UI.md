# CHAT_7_RESPONSIVE_UI.md

Current Version: `0.2.0`
Status: first-stage accepted
Owner: Chat 7 / Responsive UI + Platform Polish

## Planning Source

Primary source:

```text
<private-planning-document>
```

If this task document conflicts with that file, the external plan wins.

## Scope

Owns final visual consistency, responsive layout completion, platform polish, and macOS/Linux adaptation notes after the core Tag discovery UI is functional.

Allowed:

- Visual consistency for cards, buttons, dialogs, sidebars.
- Light media-library style and dark player style consistency.
- Full `compact`, `medium`, `expanded` layout behavior.
- Platform polish notes for desktop targets.
- Shared UI tokens after Architecture defines the boundary.

Do not do:

- Delay Tag discovery UI until this phase.
- SQLite schema changes.
- Core Tag query behavior.
- Player backend or FFmpeg internals.
- Mobile/Web deep adaptation in current phase.

## P1/P2 Tasks

- Unify video cards.
- Unify buttons.
- Unify dialogs.
- Unify sidebars.
- Keep media library and player visually coherent.
- Complete responsive layouts:
  - `expanded`: persistent filter/sidebar layouts.
  - `medium`: collapsible sidebars and side sheets.
  - `compact`: drawer/bottom-sheet filters and compact video list/card layout.
- Add macOS/Linux adaptation notes after Windows remains stable.

## First Stage Result

Completed in `0.2.0`:

- Unified dialog baseline through app theme: light surface, border, 8px radius, and stronger title hierarchy.
- Unified media-library sidebar spacing and action button behavior; directory actions wrap instead of overflowing narrow side sheets.
- Unified video card behavior: responsive grid spacing, compact single-column sizing, stable bottom action row, and fixed icon button dimensions.
- Unified cache diagnostics spacing with media-library pages; compact AppBar actions now collapse into a menu.
- Unified Tag Manager basic layout with responsive `expanded` / `medium` / `compact` behavior:
  - `expanded`: persistent 360px tag management sidebar.
  - `medium`: persistent but narrower 316px management sidebar.
  - `compact`: vertical list/detail layout without horizontal overflow.
- Player dark queue sidebar now remains persistent only when width allows it; compact opens the queue from the AppBar as a bottom sheet.
- Media library compact filter BottomSheet uses the same light surface and 8px top radius as the rest of the app.

Not changed:

- SQLite schema.
- `TagQueryService`, `FilterQuery`, or `TagQueryContext`.
- Player filtered queue semantics, player open worker, or playback backend.
- Thumbnail queue, FFmpeg/FFprobe backend behavior, or cache diagnostics logic.
- Smart List, relink/missing, file move, tag delete, or tag merge migration.

## macOS / Linux Adaptation Notes

- FFmpeg bundled tools: current Windows layout expects `.exe` tools under `tools/ffmpeg/bin`; macOS/Linux packaging needs platform-specific binaries, executable permissions, quarantine/signing checks on macOS, and separate lookup order per platform.
- sqlite3 dynamic library: Windows currently bundles `sqlite3.dll`; macOS/Linux need `.dylib` / `.so` placement compatible with Flutter desktop packaging and runtime library search paths.
- File manager reveal: Windows reveal behavior should map to Finder `open -R` on macOS and desktop-environment-specific reveal/open commands on Linux; fallback should open the parent folder when exact reveal is unavailable.
- Window sizes: the current desktop UX is best at `expanded`; macOS/Linux should set sensible minimum window sizes and test compact/medium resizing because tiling window managers can create very narrow desktop windows.
- Shortcuts: verify Command vs Control conventions on macOS, Delete/Backspace differences, function key behavior, and mouse side-button availability across Linux desktop environments.

## Prompt For New Chat

```text
这是 Chat 7 / Responsive UI + Platform Polish。项目路径：<project-root>。

请先阅读：
- PROJECT.md
- ARCHITECTURE.md
- CURRENT_TASK.md
- ROADMAP.md
- <private-planning-document>
- docs/chat_tasks/CHAT_7_RESPONSIVE_UI.md

后续方向以 local_tag_player_flutter_cross_platform_plan_v2.md 为准；当前项目实现只代表历史状态。

职责：负责最终视觉统一、完整响应式布局和平台 polish。注意：Tag 检索 UI 不应等到 Chat 7 才做；Chat 7 是在核心 Tag UX 可用后的统一和完善。

当前目标：统一卡片、按钮、弹窗、侧栏、媒体库浅色区域和播放器深色区域；完善 compact / medium / expanded 响应式布局；补充 macOS/Linux 适配点。不要改 SQLite schema、Tag 查询核心、播放器内核或 FFmpeg 队列。

修改代码后运行：
- flutter analyze
- flutter build windows --debug

涉及 shared layout token、src/core 或平台边界时，更新 ARCHITECTURE.md、ROADMAP.md 和本文件版本记录。
```

## Change Log

- `0.2.0`: Completed first-stage responsive UI polish and added macOS/Linux adaptation notes.
- `0.1.0`: Created task from `local_tag_player_flutter_cross_platform_plan_v2.md`.
