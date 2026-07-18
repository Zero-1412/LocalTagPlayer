## 2026-07-18 Apple UI Phase 3 目录管理与 Missing/Relink

- 目录管理改为独立维护工作区，但添加、扫描和解除 root 仍只委托既有 application facade 与页面回调；UI 不直接访问磁盘、SQLite 或平台命令。
- 解除管理继续使用 detached 语义，不删除磁盘文件，并保留 videoId、fingerprint、manual 标签、收藏、播放记录、进度和媒体详情；真实窗口确认层仅打开后取消。
- Missing 列表与批量路径替换只重排信息层级和响应式布局；单条/批量 relink 的路径占用、fingerprint、只读预览、二次确认、失败重试、root 更新和审计语义均未改变。
- 150% 文字缩放 focused tests、完整 204 项测试、静态分析、Windows debug build 与 1248×714 真实窗口连续截图通过。

## 2026-07-17 文件选择初始目录与视图偏好

- 添加目录/视频优先从当前媒体路径打开，缺少当前路径时回退首个媒体 root；单条 Relink 优先原文件父目录，再回退原 root 或媒体 root。
- 页面只选择业务相关候选路径，原生选择器参数和父目录解析继续经过 `FileSystemAdapter`，不在 UI 拼接 Windows 路径。
- 网格/列表作为显示偏好写入既有 JSON，旧文件缺字段时使用网格默认；不修改 SQLite schema、stable identity、relink fingerprint 校验、FilterQuery 或 filtered queue。

## 2026-07-16 视频依赖备份检查与便携导出

- 完整性检查在 worker 批次边界串行执行，读取独立备份库和主库依赖字段，不读取视频文件、不删除未来可恢复快照，也不改变 folder/manual 标签来源。
- 便携 JSON 使用固定 format/version，导出稳定 videoId/fingerprint 和非 folder 依赖 payload，不导出 path、视频内容、缩略图或媒体详情缓存；文件保存经过 `FileSystemAdapter`。
- `session_open` 只在显式关闭成功时清除；桌面窗口边界会在销毁前等待 Store 关闭，异常退出则下次全量补偿。正常启动只消费持久化增量队列，关闭备份期间设置 `reconcile_required`，重新开启时不会遗漏变化。
- 规范快照按 videoId/tagId/source 稳定排序，条件 UPSERT 只写真实变化。`library.db` schema、双侧 fingerprint 唯一恢复、detached 生命周期、FilterQuery/TagQueryService 与 filtered queue 均未改变。

## 2026-07-16 视频依赖独立备份与自动恢复

- 默认开启的备份设置独立保存，备份数据进入 `video_dependency_backup.db`，不复制视频文件或依赖主库 identity 行继续存在。
- 快照包含稳定 videoId/fingerprint、收藏、播放状态、非 folder 标签和必要分组定义；folder 标签仍以当前 root 文件树重新派生。
- 全量核对按 32 条小批次和稳定 videoId 游标执行，增量变更使用持久化去重队列；关闭或异常退出后下次启动继续。
- 自动恢复要求扫描侧与备份侧 fingerprint 双侧唯一且主库无 videoId 冲突；歧义拒绝合并。root detached 保留快照，显式单视频删除同步清理快照。
- 播放前等待当前备份批次结束并暂停，播放器释放后恢复。focused tests 覆盖默认设置、身份丢失恢复、删除同步、播放暂停与跨重启续跑。
- 正式窗口验证 11,163 条快照完整完成；播放期间备份游标保持不变，返回后自动续跑。独立库完整性为 `ok`，schema 不保存媒体 path。

## 2026-07-16 root detached 稳定身份归档与收藏恢复

- 正式库恢复前先创建 SQLite 一致性备份；快照 3 条收藏以 path + fingerprint 精确匹配后单事务恢复，恢复前 3 条、恢复后 6 条，前后完整性检查均为 `ok`。
- `videos.is_detached` 作为 root 管理状态，不复用 missing：文件仍存在但 root 被解除管理时，记录退出 active 媒体库，同时完整保留 videoId、标签关系、收藏、播放进度和缓存字段。
- 重新添加同一路径按 path 激活原记录；移动到新 root 时按唯一 fingerprint 复用原 relink 链路。过期媒体探测 upsert 不得激活 detached。
- `TagQueryService` 与播放器只消费 active `videos`；标签管理引用继续包含 detached，保护归档视频依赖的手动标签。root 移除不再清理缩略图缓存。
- focused tests 覆盖旧 schema 幂等迁移、同 root 恢复、跨 root fingerprint 恢复、重载和过期回调隔离；`FilterQuery`、标签来源语义和 PlayerBackend 未改变。

## 2026-07-08 Store focused tests 与扫描边界

- 新增 `test/library_store_test.dart`，用临时数据目录和真实小型文件树覆盖 `LibraryStore` 的扫描、folder 标签派生、manual 标签维护和 SQLite 持久化读写。
- 新增 `LibraryScanService`，只负责目录遍历、视频文件识别、stat 读取、folder 来源一级/二级标签派生和轻量媒体指纹。
- `LibraryStore` 继续负责 SQLite 写入、内存 `VideoItem` 状态、folder/manual 标签索引同步、用户收藏和播放记录字段，避免扫描服务直接接触用户维护数据。
- 本轮不修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、stable identity 或 missing/relink 规则。

# CHAT_2_MEDIA_LIBRARY.md

## 2026-07-15 冷扫描阶段进度与可暂停 sidecar

- `LibraryScanBackend` 只读边界新增阶段进度和暂停/恢复；目录发现完成后才公布 fingerprint 总量和百分比，不在未知阶段伪造进度。
- Rust stderr 只上报阶段/数量，stdout 快照、generation 取消、stable identity 唯一匹配和 Dart SQLite 单 batch 提交语义不变。
- 播放让盘通过 Repository/facade 协调，页面不接触 sidecar 文件或进程；大差量合并分段让出 UI isolate。
- `X:\test-media` 11,163 项热态基准为发现 24ms、fingerprint 1,444ms、稳定态端到端 754ms；冷盘数据继续由 `scanPhases` 记录。
- 隔离真实窗口确认确定型文案、进度条和暂停按钮位于结果摘要行内且无截断；播放返回后 diagnostics 同时包含 discovering、fingerprinting、committing。

## 2026-07-15 大目录导入分阶段状态与批量字段写入

- 扫描仍由只读 `LibraryScanBackend` 产生差量并由 Dart Application 一次提交；总量未知阶段只显示发现/校验状态，不伪造百分比。
- 扫描提交后列表立即可用，后台媒体详情按有限批次回写；`LibraryRepository.upsertVideos` 只批量更新视频行字段，不重建标签关系。
- 媒体解析完成或失败都会推进结果区百分比，全部处理后恢复正常结果数。SQLite schema、stable identity、folder/manual 标签和过滤语义不变。

## 2026-07-13 目录与视频删除语义

- 当时实现为移除 root 后删除脱离管理范围的视频行和标签关系；该策略已在 2026-07-16 被 `is_detached` 归档语义取代，保留于此仅作历史记录。
- 父子 root 重叠时，仅让不再受任何剩余 root 覆盖的条目退出 active 媒体库；focused test 覆盖父 root 移除后子 root 视频继续 active。
- 卡片删除可选择仅移出媒体库或同步删除本地文件；stable 视频行中的收藏、播放进度和媒体详情随记录删除，标签关系显式清理。

## 2026-07-13 SQLite hydration 与 Rust ScanDelta

- 真实库分阶段定位启动 38.55 秒为 stable identity 兼容 UPDATE 的 Windows NOCASE 全表相关扫描；普通视频 SQL 约 40–58 毫秒、对象构建约 208–275 毫秒、标签关系查询与 hydration 约 50–71 毫秒。
- stable identity 回填只处理缺失 `video_id` 的旧行，并建立 path NOCASE 索引；重复关系先轻量检查，root 直属视频合法零 folder 标签不再重复写入。
- `LibraryScanBackend` 只返回不可变 `LibraryScanDelta`，支持 generation 取消；Rust/Dart 后端都不访问 SQLite。
- Dart Application 继续校验 fingerprint 两侧唯一性，保留 videoId/manual 标签/收藏/播放记录/进度，并在单 batch 中提交 added/modified/missing/relink。
- 父子 root 重叠时最上层 root 优先并按 pathKey 去重，符合一级/二级 folder 标签硬规则；扫描稳定态只差量刷新 UI，新增/内容变化才进入媒体探测队列。
- 未新增 SQLite 数据列或业务表，`FilterQuery` / `TagQueryService` 语义与播放器 filtered queue 不变。

## 2026-07-11 批事务与失败重试

- ready 项在执行前统一重验，并通过一个 SQLite batch 原子提交；异常时恢复内存视频、标签和关联索引。
- 执行返回成功数与失败 videoId，UI 只定向重试失败项，不重复提交成功记录。
- 预览搜索只作用于内存结果；审计摘要隐藏路径和标题，不修改 Schema。

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

当前版本：`0.4.4`
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
# 2026-07-14 真实目录十轮增删一致性

- 隔离 profile 下对真实 `X:\test-media` 连续执行十轮添加和移除；每轮新增/移除 6,308 条，Store、SQLite 与 UI 均稳定在 4,827 → 11,135 → 4,827。
- 修复未入库统计遍历可变 roots 的并发修改；root 移除提交同步提升数据 revision，禁止过滤层复用删除前列表。
- 移除前取消媒体探测 generation，回写前复核当前 path/videoId/fingerprint，旧回调不再复活已删除视频。
- SQLite schema、`FilterQuery` / `TagQueryService` 语义、manual 标签和 filtered queue 来源不变；完整性能证据见 `docs/qa/library_add_remove_player_stress_20260714.md`。

## 2026-07-14 压力测试产物生命周期

- 媒体库增删压测输出增加 `.ltp-stress-artifact` 安全标记；启动前仅清理带标记且超过默认 7 天保留期的目录。
- 成功运行默认只保留 `summary.json` 与 `artifact-manifest.json`，删除隔离 profile、缩略图、临时数据库、录像、截图和原始采样；失败运行保留全部现场。
- `-KeepRawArtifacts` 可显式保留完整证据，`-ArtifactRetentionDays 0` 可禁用过期清理；本轮不修改媒体库、SQLite、标签或播放器业务语义。
