# ADR-004：LibraryStore 分层、资源预算与 profile 查询编译

状态：已接受（Phase 3–5 完成，Phase 6 已接入并经真实大库基准启用）
日期：2026-08-16

## 背景

媒体库已经同时承担 SQLite 生命周期、内存身份索引、扫描合并、标签维护、缓存状态、
播放记录和备份协调。继续把这些职责放在一个可被所有调用方直接注入的 Store 中，
会让任何新功能都可能绕过统一事务或建立第二套索引。另一方面，扫描、FFprobe、
缩略图、视觉取帧和备份都受本地磁盘/CPU 争抢影响，分别限流无法表达播放优先级。

## 决策

### 1. 单库共享上下文与端口隔离

`LibraryRepositoryContext` 统一拥有：

- 唯一 SQLite connection；
- active/detached 的 stable-ID/path 双索引；
- 标签关系主索引和兼容索引；
- 视频、标签、metadata persistence helpers；
- 统一 `transaction` 入口。

`LibraryStoreQueryService`、`LibraryStoreCommandService`、`LibraryStoreCoordinatorService`
分别拥有查询、标签/收藏命令和 root/扫描/relink 协调逻辑；`LibraryStoreQueryRepository` 与
`LibraryStoreCommandRepository` 只隔离对外能力，不复制状态。低层 stable-ID 视频 CRUD、
媒体详情/播放状态和缓存写入仍由 Store 作为同一个事务 owner 保留。组合根将只读查询端口和
命令端口分别注入 facade；跨表操作仍由同一个 Store/Context 和同一个 SQLite transaction 提交。

### 2. ResourceScheduler

`ResourceScheduler` 以 `scan/probe/thumbnail/visual/backup` 为资源类别，维护每类预算、
总预算、前台/后台优先级和播放激活门。后台请求在播放期间等待，已经取得的 lease 允许
自然收尾；前台请求可显式越过。调度器不拥有 FFmpeg、SQLite、播放器或业务数据，关闭
与取消仍由各自 service 生命周期负责。

### 3. 播放运行时和渲染表面

播放器正式依赖拆为：

- `PlayerRuntimeBackend`：打开、播放控制、状态事件、运行时属性和释放；
- `PlayerSurfaceRenderer`：把当前会话绑定为 Flutter 视频 Widget；
- `PlayerBackend`：当前 MediaKit/Windows 实现的兼容聚合接口。

`PlayerService` 支持分别注入前两者；默认后端仍实现聚合接口，因而不改变正式 MediaKit
Texture、Windows native QA 路径或既有测试后端。

### 4. profile 驱动查询和 FTS5

`LibraryQueryProfile` 仅在视频数量达到阈值且 SQLite 支持 trigram FTS5 时选择
`sqliteFts5`。`LibraryQueryController`/Facade 请求候选后，`dataRevision` 只在主库成功提交
后推进；查询 service 发现新修订时按需重建派生索引。`LibraryQueryCompiler` 生成的 SQL 只能
返回关键词候选集，候选必须继续经过 `FilterQuery.matches` / `TagQueryService`；少于 3 字符、
FTS5 不可用或小库始终回退内存路径。因此 FTS5 不能改变 alias、folder 层级、分组 AND/OR、
NOT 和用户筛选语义。FTS 表是可重建派生数据，不进入数据备份；不支持 FTS5 的 SQLite 启动不失败。

## 不变事项

- `videoId` 仍是唯一用户数据身份，path 仍是可变位置；
- `FilterQuery` / `TagQueryService` 仍是最终筛选语义所有者；
- PlayerPage 只消费来源页面的 filtered queue；
- 缩略图/媒体详情/视觉任务失败可见、可重试，不能回写错误 stable ID；
- 备份只复制用户依赖数据，FTS 和其它派生索引不进入备份；
- 不增加路由框架：当前桌面应用没有 deep link、认证守卫或多 Navigator 状态需求，
  继续使用 Flutter Navigator/显式 Route 输入即可，待证据出现再评估 go_router。

## 验证证据

- `test/library_repository_context_phase3_test.dart`：单上下文和查询/命令端口门禁；
- `test/resource_scheduler_test.dart`：预算、前台优先级、播放门和 release；
- `test/player_runtime_surface_contract_test.dart`、播放器 service/filter focused：
  运行时/表面独立契约与既有行为；
- `test/library_query_compiler_phase6_test.dart`：profile 阈值、FTS5 计划和安全回退；
- `test/library_query_benchmark_test.dart`：显式隔离真实数据库副本的完整查询/候选查询对比，
  同时断言最终 stable-ID 结果集合一致；
- `dart analyze lib test/...`、稳定身份和架构 focused tests。

## 对抗式审查

```text
schema: unchanged after schema v2; FTS5 is optional derived table, no user-data migration
FilterQuery / TagQueryService: unchanged and remains final semantic owner
filtered queue: unchanged; no global-library fallback introduced
thumbnail/media queue: unchanged behavior, now shares scheduler budget
user data: preserved; FTS/index data is rebuildable and excluded from backup
prompt impact: satisfies single-store/single-budget/runtime-surface principles; no route framework added
protected behaviors: stable-ID commands, playback queue, native backend defaults preserved
unauthorized feature removal: none
mount and reachability: existing LibraryPage/PlayerPage routes remain mounted and reachable
validation: Phase 3–6 focused tests、架构契约、`flutter analyze`、全量 `flutter test -r compact`（600 通过、4 跳过）和真实 11,194 条库查询基准通过；Windows Debug build 已成功生成 `build/windows/x64/runner/Debug/local_tag_player.exe`
```
