# CHAT_6_TAG_MANAGER.md

Current Version: `0.2.1`
Status: first phase completed
Owner: Chat 6 / Tag Manager + Batch Tagging

## Planning Source

Primary source:

```text
<private-planning-document>
```

If this task document conflicts with that file, the external plan wins.

## Scope

Owns long-term tag maintenance UI and batch tag operations after the grouped tag model and filter engine are usable.

Allowed:

- Tag manager page.
- Tag group manager UI.
- Tag details editor.
- Tag aliases.
- Tag rename/merge/delete.
- Favorite/hidden/sort controls.
- Batch tag current filtered result.
- Batch remove tags.
- Saved filter / smart list management if coordinated with Chat 2/3.

Do not do:

- Player backend changes.
- Thumbnail queue internals.
- Platform-specific file operations unless coordinated through Architecture.
- Destructive tag/schema migration without compatibility and documentation.

## P1 Tasks

- Add tag management page.
- Search tags.
- Create tags.
- Rename tags.
- Merge duplicate tags.
- Maintain aliases.
- Maintain tag groups.
- Hide/favorite/sort tags.
- Batch add tags to current filtered result.
- Batch remove tags from selected or filtered videos.
- Keep batch operations platform independent.

## Prompt For New Chat

```text
这是 Chat 6 / Tag Manager + Batch Tagging。项目路径：<project-root>。

请先阅读：
- PROJECT.md
- ARCHITECTURE.md
- CURRENT_TASK.md
- ROADMAP.md
- <private-planning-document>
- docs/chat_tasks/CHAT_6_TAG_MANAGER.md

后续方向以 local_tag_player_flutter_cross_platform_plan_v2.md 为准；当前项目实现只代表历史状态。

职责：负责标签管理页、标签组、标签别名、重命名、合并、隐藏/收藏/排序、批量打标签和批量移除标签。不要改播放器内核、缩略图队列或平台文件操作。

当前目标：在 Tag Model + Filter Engine 稳定后，提供长期维护大量标签的入口。用户应能维护别名、合并重复标签，并能给当前筛选结果批量打标签。

修改代码后运行：
- flutter analyze
- flutter build windows --debug

涉及 schema、src/core 或共享模型时，更新 ARCHITECTURE.md、ROADMAP.md 和本文件版本记录。
```

## Change Log

- `0.1.0`: Created task from `local_tag_player_flutter_cross_platform_plan_v2.md`.
- `0.2.0`: Added first-phase Tag Manager entry and page. Supports viewing groups/tags/aliases/source usage counts, searching tags, creating manual tags, editing displayName/aliases/hidden/favorite/sortOrder/group, and batch add/remove manual tags for the current filtered result. Delete/merge remain guarded placeholders with `video_tags` reference checks; folder-derived tags are not hard-deleted.
- `0.2.1`: Acceptance fixes. Tag groups are shown directly in Tag Manager, batch add/remove is restricted to `manual` source tags, and manual tag creation now refuses to overwrite same-group non-manual tags.
