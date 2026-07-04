# CHAT_2_MEDIA_LIBRARY.md

Current Version: `0.4.1`
Status: active
Owner: Chat 2 / Tag Model + Filter Engine + Media Library

## Planning Source

Primary source:

```text
<private-planning-document>
```

If this task document conflicts with that file, the external plan wins.

## Scope

Owns SQLite, scanning, folder-derived tags, grouped tag model, aliases, filter engine, favorites, search, stable media identity, missing/relink planning.

Allowed:

- `LibraryStore` and future `MediaScanService`.
- SQLite migrations.
- `VideoItem` data fields needed for media identity and tags.
- `TagGroup`, `TagItem`, `FilterQuery`.
- `TagRepository`, `VideoRepository`, `TagQueryService`.
- Folder/manual/rule/filename/import/auto tag-source design.
- `videoId + fingerprint + mutable path` planning and migration.

Do not do:

- Player UI/core changes.
- FFmpeg/thumbnail queue changes.
- Visual polish except minimal controls needed for media-library function.
- Windows-specific logic in platform-independent tag query code.

## P0 Tasks

- Preserve current folder-derived first/second tag behavior during transition.
- Implement grouped tag model.
- Implement tag aliases.
- Implement `FilterQuery`.
- Implement filter semantics:
  - different groups use AND.
  - tags inside the same group use OR.
  - excluded tags use NOT.
- Search must match file name, path, tag name, and tag alias.
- Implement result counts for grouped filters.
- Ensure filtered result can be passed to Player as current playback queue.
- Keep Tag query/filter logic platform independent.

## P1 Tasks

- Separate folder tags and manual tags.
- Add or plan `video_tags.source`: `manual`, `folder`, `rule`, `filename`, `import`, `auto`.
- Add or plan `video_tags.locked`.
- Move toward stable `videoId + fingerprint + mutable path`.
- Add `missing` state instead of deleting records immediately when files disappear.
- Add single-file relink.
- Add bulk path replacement, for example `X:\test-media -> E:\video`.
- Put unrecognized new imports into `未分类 / 待整理 / 新导入`.

## Prompt For New Chat

```text
这是 Chat 2 / Tag Model + Filter Engine + Media Library。项目路径：<project-root>。

请先阅读：
- PROJECT.md
- ARCHITECTURE.md
- CURRENT_TASK.md
- ROADMAP.md
- <private-planning-document>
- docs/chat_tasks/CHAT_2_MEDIA_LIBRARY.md

后续方向以 local_tag_player_flutter_cross_platform_plan_v2.md 为准；当前项目实现只代表历史状态。

职责：负责 SQLite、目录扫描、folder/manual Tag、分组 Tag、标签别名、FilterQuery、组合筛选、稳定视频身份、missing/relink 规划。不要修改播放器内核、缩略图队列或 UI 美化。

当前目标：实现 Tag Model + Filter Engine。保留文件夹树生成一级/二级 Tag，同时建立播放器自己的分组 Tag 检索能力。不同标签组 AND，同组 OR，排除标签 NOT。搜索匹配文件名、路径、标签名、标签别名。筛选结果必须可传给播放器作为当前播放队列。

后续目标：区分 folder/manual/rule/filename/import/auto Tag 来源，规划 video_tags.source/locked，推进 videoId + fingerprint + mutable path，路径失效标记 missing，不立即删除记录。

如果需要修改 src/core、数据库 schema 或共享模型，更新 ARCHITECTURE.md 的架构基线说明和本文件版本号。

修改代码后运行：
- flutter analyze
- flutter build windows --debug
```

## Change Log

- `0.4.1`: Acceptance fixes for the first Tag Model + Filter Engine pass: tag index backfill now covers videos missing links without wiping manual links, manual tag writes only refresh the current manual scope and exclude folder-derived tags, result counts ignore the candidate tag group to avoid in-group count collapse, and SQLite gained alias/source lookup indexes.
- `0.4.0`: Added normalized SQLite tag index tables (`tag_groups`, `tags`, `tag_aliases`, `video_tags`), synchronized folder/manual tag links from scan and tag editing, added `TagQueryContext` and `TagQueryService`, enabled alias-aware keyword matching for tags linked to each video, exposed grouped result counts, and kept the current filtered result as the player queue.
- `0.3.0`: Rebased Media Library on the external cross-platform plan, expanded ownership to Tag Model + Filter Engine, aliases, grouped semantics, stable identity, missing/relink, and tag-source separation.
- `0.2.0`: Implemented platform-independent `FilterQuery.matches` semantics with tag groups AND, in-group OR, excluded tags NOT, tag aliases for search, and wired current media-library filtering through `FilterQuery` while preserving folder-derived first/second tag behavior.
- `0.1.0`: Created task template from roadmap.
