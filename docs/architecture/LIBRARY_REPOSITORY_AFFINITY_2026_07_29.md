# Library Repository 事务亲和度审计

日期：2026-07-29

对应阶段：渐进式架构重构 Phase 5

结论：收窄使用面，暂不物理拆分 `LibraryStore`

## 1. 第一性原理

```text
Product goal protected: 本地媒体扫描、标签发现、筛选和 filtered playback queue 闭环
Core loop part protected: LibraryStore 的稳定身份、标签来源、扫描提交和备份协调
Must not change: schema、FilterQuery/TagQueryService、队列顺序、用户数据和既有事务
Smallest safe change: 拆分查询/命令能力接口，由同一 Store 实例实现
Fewest safe tokens: 只审计 Repository contract、facade、composition 与事务直接实现
```

## 2. 使用面证据

- 生产代码中，具体 `LibraryStore` 只由
  `lib/src/composition/local_tag_player_bootstrap.dart` 创建。
- presentation 不引用 `LibraryStore`；媒体库页面只消费
  `LibraryApplicationFacade`。
- Phase 5 前，facade 的单个 `LibraryRepository` 字段同时暴露全部查询和写入能力。
- Phase 5 后，facade 分别依赖 `LibraryQueryRepository` 与
  `LibraryCommandRepository`；组合根把同一个 Store 实例注入两个端口。
- `LibraryRepository` 只保留为 composition/data 边界的兼容聚合契约。

这使只读消费者无法通过依赖引用发起写入，同时没有创建第二份内存索引、数据库连接或
事务 owner。

## 3. 事务亲和度矩阵

| 能力组 | 代表方法 | 当前一致性边界 | 拆分约束 |
| --- | --- | --- | --- |
| 内存与派生查询 | `roots`、`videos`、`resultCounts`、`childTagsFor` | 同一 Store 内存索引与 `TagQueryContext` | 保持只读端口；不得复制过滤语义 |
| SQLite 只读查询 | `tagUsageSummaries`、`countTagReferences`、`countUntrackedVideos` | 主库只读查询 | 可独立测试，不需要新连接 |
| 备份只读检查 | `dataBackupStatus`、`checkDataBackupIntegrity`、`createDataBackupExport` | `LibraryDataBackupService` 的只读快照/导出 | 不得取得主库写权限 |
| 标签维护 | `replaceManualTags`、`batchAddManualTag`、`batchRemoveManualTag` | videos、tags、video_tags 同一 SQLite batch；主库提交后再 best-effort 入备份队列 | 必须保持一个粗粒度命令 |
| 路径与稳定身份 | `renameVideoPath`、`relinkMissingVideo(s)` | videos 与兼容 video_tags 路径在同一 batch；失败恢复内存索引 | 不得按表拆成多个 Repository 调用 |
| 删除与清理 | `deleteVideo`、`removeMissingOrUnreadableVideos` | 暂停备份后，tag links 与 video rows 同一 batch；失败重新排入备份核对 | 必须保留补偿顺序 |
| 扫描与 root | `scanWithChanges`、`removeRoot`、`addRootsAndScanWithChanges` | metadata、videos、folder tags 与 missing 状态同一 batch | 扫描 coordinator 继续拥有提交 |
| 播放状态 | `upsertPlaybackStates` | 视频行批量提交后按 stable videoId 入备份队列 | 备份故障进入诊断，不回滚已提交主库 |
| 运行时协调 | `setScanPaused`、`pauseDataBackupForPlayback`、`close` | 扫描、播放让盘和资源生命周期顺序 | 归命令端口，不伪装成数据查询 |

## 4. 是否物理拆分 LibraryStore

按 ADR 的六项门槛审查：

1. 具体 Store 在 data/composition 外的生产引用为零：满足。
2. 约 80% 方法属于单一数据域：不满足；命令仍横跨视频、标签、metadata、扫描和备份。
3. 跨域写入很少且事务 owner 清晰：事务 owner 清晰，但跨域写入是扫描、标签、relink、
   删除等核心路径，不属于少数边缘操作。
4. 不增加 SQL 调用或破坏 batch：尚无物理拆分后仍能保证该项的收益证据。
5. 有可量化测试收益：接口拆分已经提供 fake/contract 隔离，物理拆分没有新增收益证据。
6. 查询计划、队列 hash、数据库完整性一致：当前回归可保护既有实现，但不足以授权移动
   事务所有权。

因此 Phase 5 明确选择“不物理拆分”。未来只有在跨域写入先收敛到显式 application
use case 与统一 transaction runner、且 profiling/测试证明收益后，才重新评估。

## 5. 对抗式审查

```text
schema: unchanged
FilterQuery / TagQueryService: unchanged
filtered queue: unchanged
thumbnail/media queue: unchanged
user data: preserved
protected behaviors: preserved
unauthorized feature removal: none
mount and reachability: LibraryPage 仍经原 facade 和同一 Store 实例装配
prompt impact: satisfies first principles; no physical split or new transaction abstraction
```
