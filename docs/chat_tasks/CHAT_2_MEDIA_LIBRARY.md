## 2026-07-08 Store focused tests 与扫描边界

- 新增 `test/library_store_test.dart`，用临时数据目录和真实小型文件树覆盖 `LibraryStore` 的扫描、folder 标签派生、manual 标签维护和 SQLite 持久化读写。
- 新增 `LibraryScanService`，只负责目录遍历、视频文件识别、stat 读取、folder 来源一级/二级标签派生和轻量媒体指纹。
- `LibraryStore` 继续负责 SQLite 写入、内存 `VideoItem` 状态、folder/manual 标签索引同步、用户收藏和播放记录字段，避免扫描服务直接接触用户维护数据。
- 本轮不修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、stable identity 或 missing/relink 规则。

# CHAT_2_MEDIA_LIBRARY.md

## 2026-07-11 跨盘批量路径替换

- `BulkPathRelinkService` 对 missing 条目执行旧/新前缀映射，只读检查目标存在、路径占用和 fingerprint。
- 批量执行仅消费 ready 预览，逐条复用安全 relink；旧前缀精确匹配媒体 root 时同步更新扫描 root；不修改 Schema、不移动文件、不删除 missing 记录。
- 20 条真实 C:→E: soak 覆盖重载后的 videoId、manual 标签、收藏和播放进度保留。

## 2026-07-11 稳定播放状态迁移

- `videos` 幂等增加总时长与完成态字段；位置、时长、完成态和更新时间都随稳定 videoId 保留。
- 自动/手动 relink 仍只更新 mutable path 与 folder 标签，manual 标签、收藏、继续观看和播放进度不重建。
- 旧库字段默认 0/false，迁移不清空用户数据；未修改 FilterQuery / TagQueryService 语义。

## 2026-07-11 Missing/Relink 用户界面第一阶段

- 新增 missing 列表入口和单文件 relink；不立即删除缺失记录。
- relink 仅接受可读取视频、未占用目标路径和完全一致 fingerprint，拒绝误选串档。
- 成功后保持 videoId、manual 标签、收藏、播放记录与进度，只重新派生新路径的 folder 标签。
- 本轮不修改 SQLite Schema；后续再做批量路径前缀替换与冲突预览。

## 2026-07-11 Stable Video Identity 第一阶段

- SQLite 兼容增加 `videos.video_id`、missing 与播放进度字段；旧 path 主键记录启动时幂等回填，不清空用户数据库。
- `video_tags` 增加并改用 `video_id` 关联；path 暂作为兼容列，移动时只更新位置快照。
- fingerprint 使用大小与首尾各 4KB 内容采样，不依赖 path/mtime；仅新旧两侧唯一时自动 relink，歧义时保守新建，防止标签、收藏和进度串档。
- 可访问 root 中消失的记录改为 missing，不再删除；自动 relink 保留 videoId、manual 标签、收藏、播放记录、媒体缓存字段和进度，并重新计算 folder 标签。
- focused tests 覆盖旧 schema 回填、missing 保留、唯一移动认领、歧义拒绝合并与重载持久化。

当前版本：`0.4.3`
状态：进行中
负责人：Chat 2 / 标签模型 + 筛选引擎 + 媒体库

## 规划来源

主要来源：

```text
<private-planning-document>
```

如果本文档与该文件冲突，以外部规划为准。

## 范围

负责 SQLite、扫描、文件夹派生标签、分组标签模型、别名、筛选引擎、收藏、搜索、稳定媒体身份和 missing/relink 规划。

允许：

- `LibraryStore` 和未来 `MediaScanService`。
- SQLite migrations。
- 媒体身份和标签所需的 `VideoItem` 数据字段。
- `TagGroup`、`TagItem`、`FilterQuery`。
- `TagRepository`、`VideoRepository`、`TagQueryService`。
- folder / manual / rule / filename / import / auto 标签来源设计。
- `videoId + fingerprint + mutable path` 规划和 migration。

禁止：

- 播放器 UI / core 改动。
- FFmpeg / 缩略图队列改动。
- 与媒体库功能无关的视觉 polish。
- 在平台无关标签查询代码中写入 Windows 专属逻辑。

## P0 任务

- 过渡期间保留当前文件夹派生的一/二级标签行为。
- 实现分组标签模型。
- 实现标签别名。
- 实现 `FilterQuery`。
- 实现筛选语义：
  - 不同组使用 AND。
  - 同组标签使用 OR。
  - 排除标签使用 NOT。
- 搜索必须匹配文件名、路径、标签名和标签别名。
- 实现分组筛选结果计数。
- 确保筛选结果可传给 Player 作为当前播放队列。
- 保持 Tag 查询 / 筛选逻辑平台无关。

## P1 任务

- 区分 folder 标签和 manual 标签。
- 新增或规划 `video_tags.source`：`manual`、`folder`、`rule`、`filename`、`import`、`auto`。
- 新增或规划 `video_tags.locked`。
- 推进稳定 `videoId + fingerprint + mutable path`。
- 文件消失时增加 `missing` 状态，而不是立即删除记录。
- 增加单文件 relink。
- 增加批量路径替换，例如 `X:\test-media -> E:\video`。
- 未识别的新导入放入 `未分类 / 待整理 / 新导入`。

## 新对话提示

```text
这是 Chat 2 / 标签模型 + 筛选引擎 + 媒体库。项目路径：<project-root>。
请先阅读：
- PROJECT.md
- ARCHITECTURE.md
- CURRENT_TASK.md
- ROADMAP.md
- <private-planning-document>
- docs/chat_tasks/CHAT_2_MEDIA_LIBRARY.md

后续方向以 local_tag_player_flutter_cross_platform_plan_v2.md 为准；当前项目实现只代表历史状态。
职责：负责 SQLite、目录扫描、folder/manual 标签、分组 Tag、标签别名、FilterQuery、组合筛选、稳定视频身份和 missing/relink 规划。不要修改播放器内核、缩略图队列或 UI 美化。
当前目标：实现 Tag Model + Filter Engine。保留文件夹树生成一/二级 Tag，同时建立播放器自己的分组 Tag 检索能力。不同标签组 AND，同组 OR，排除标签 NOT。搜索匹配文件名、路径、标签名和标签别名。筛选结果必须可传给播放器作为当前播放队列。
后续目标：区分 folder/manual/rule/filename/import/auto Tag 来源，规划 video_tags.source/locked，推进 videoId + fingerprint + mutable path，路径失效标记 missing，不立即删除记录。
如果需要修改 src/core、数据库 schema 或共享模型，更新 ARCHITECTURE.md 的架构基线说明和本文档版本号。
修改代码后运行：
- flutter analyze
- flutter build windows --debug
```

## 变更记录

- `0.4.3`：恢复 `TagQueryService.resultCounts` 的分组结果计数批处理：候选标签按标签组分批，每个标签组只扫描一次视频集合，并在旧兼容匹配前优先使用标准化视频 tagId 做候选交集判断；未修改 SQLite schema。
- `0.4.2`：针对大媒体库优化分组结果计数：`TagQueryService.resultCounts` 按标签组批量计算候选计数，候选 tagId 可用时使用索引化关联减少重复扫描；筛选语义仍统一经过 `FilterQuery` / `TagQueryService`，未修改 SQLite schema。
- `0.4.1`：第一轮标签模型 + 筛选引擎验收修复：tag 索引回填覆盖缺失关联的视频但不清空手动关联；manual tag 写入只刷新当前 manual 范围并排除 folder 派生标签；结果计数忽略候选标签所在组，避免同组计数塌缩；SQLite 增加 alias/source 查询索引。
- `0.4.0`：新增标准化 SQLite tag 索引表（`tag_groups`、`tags`、`tag_aliases`、`video_tags`），扫描和标签编辑同步 folder/manual 关联；新增 `TagQueryContext` 与 `TagQueryService`；关键字搜索支持当前视频关联标签和别名；暴露分组结果计数，并保持当前筛选结果作为播放器队列。
- `0.3.0`：按外部跨平台规划重定媒体库职责，扩展为 Tag Model + Filter Engine、别名、分组语义、稳定身份、missing/relink 和标签来源分离。
- `0.2.0`：实现平台无关 `FilterQuery.matches` 语义：标签组 AND、同组 OR、排除 NOT、标签别名搜索；媒体库筛选接入 `FilterQuery`，同时保留文件夹派生的一/二级标签行为。
- `0.1.0`：从 roadmap 创建任务模板。

## 2026-07-08 LibraryStore tag/video persistence 拆分

- 补充 repository 边界 focused tests：标签别名、隐藏、收藏、排序字段会跨 store reload 保留；manual child tag 与 folder child tag 会按来源分离；video upsert/delete 会持久化视频字段并清理 `video_tags` 关联。
- 新增 `LibraryTagPersistence`，集中 `tags`、`tag_aliases`、`video_tags` 的写入、手动标签作用域清理和引用计数。
- 新增 `LibraryVideoPersistence`，集中 `videos` 表行映射、批量写入、单条 upsert 和删除。
- `LibraryStore` 仍负责扫描协调、folder/manual 来源语义、内存索引协调和兼容字段维护；本轮未修改 SQLite schema、`FilterQuery` / `TagQueryService` 过滤语义。

## 2026-07-08 LibraryStore metadata / scan / tag maintenance 拆分

- 补充 focused tests：metadata roots / favoriteTags 去重持久化、扫描删除缺失视频并保留剩余 manual 标签、manual child link 删除不破坏 folder child 兼容字段。
- 新增 `LibraryMetadataPersistence`，集中 metadata 表读写和去重。
- 新增 `LibraryScanCoordinator`，集中扫描结果合并、增量写库、缺失视频清理、folder 标签索引刷新和 metadata batch 保存。
- 新增 `LibraryTagMaintenance`，集中 manual/folder 来源分离策略和批量 manual 标签维护。
- 本轮未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、stable identity 或 missing/relink 行为。

## 2026-07-08 LibraryStore 异常路径测试补强

- 继续补充扫描协调 focused tests：视频内容变化后会清理旧 `mediaDetails`、`mediaDetailsError` 和 `thumbnailError`，避免缓存字段描述旧文件内容。
- 缺失或不可访问 root 会被扫描服务跳过，不会把仍存在但本轮未枚举的旧视频误删。
- `LibraryTagMaintenance` 批量添加/移除继续只允许 `manual` 来源标签；folder 来源标签会被拒绝，保护 folder/manual 来源分离。
- 本轮未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、stable identity 或 missing/relink 行为。
