# 渐进式整体架构重构完成记录

日期：2026-07-29

基线：Architecture Baseline 0.5.126

状态：Phase 0—6 完成

## 1. 架构目标

Local Tag Player 的架构服务于一条产品闭环：

```text
本地目录扫描
-> folder/manual 等来源明确的标签
-> 分组筛选与搜索
-> 版本一致的结果/计数快照
-> filtered playback queue
-> 播放器消费同一队列
-> 标签维护、缓存和诊断保证长期可用
```

本轮不把项目改造成通用专业播放器，也不以更换状态管理库、一次性重写或增加类数量作为
架构成果。

## 2. 最终依赖方向

```text
main
  -> composition root
       -> concrete data / platform implementation
       -> app shell

presentation
  -> application controller / facade
       -> domain snapshot / command / repository capability
            <- data implementation

PlayerPage
  -> PlayerService
       -> PlayerBackend
            -> native Texture / HWND / D3D11 resources
```

硬边界：

- composition root 是同时看到具体实现与应用壳的唯一位置。
- presentation 不依赖 composition、具体 Store、数据库连接或原生句柄。
- controller/ViewModel 不持有 `BuildContext`、Route、Widget 或 native resource。
- 过滤结果、facet count 与播放队列使用显式 epoch/snapshot；旧异步结果不能覆盖新状态。
- 跨表写入保持粗粒度 Repository command 和单一 SQLite batch owner。
- 生产、单元和集成测试都直接导入实际模块，不再存在万能 `src/app.dart`。

## 3. Phase 0—6 交付

| 阶段 | 交付 |
| --- | --- |
| Phase 0/1 | 审计巨型页面与依赖，拆分 main、bootstrap、app shell，建立架构合同 |
| Phase 1.5 | 建立 Result/Count/Queue 的 epoch 与不可变 snapshot 协议 |
| Phase 2 | 设置、缓存诊断和备份按一致性边界迁为独立 controller/vertical slice |
| Phase 3 | 媒体库数据修订、选择、视图、排序、查询、计数、队列、扫描和命令逐步收口 |
| Phase 4 | 播放会话、打开请求、backend event、控件、全屏、native resource 和诊断明确 owner |
| Phase 5 | Repository 拆为 query/command 能力端口，记录事务亲和度并保留聚合 Store |
| Phase 6 | 25 个测试入口迁到具体 import，删除消费者归零的兼容 barrel |

## 4. 刻意保留的聚合边界

`LibraryStore` 没有为了形式上的“干净分层”物理拆分。扫描、manual tag、root、删除和
relink 会同时维护 videos、tags、metadata、stable identity、内存索引与备份协调。当前
把它们拆成多个独立 Repository 实现会增加 SQL 往返或要求提前引入 transaction runner，
却没有可量化测试或性能收益。

因此使用面已经收窄，但同一个 Store 仍是唯一 SQLite/内存/事务 owner。重新评估条件见
`LIBRARY_REPOSITORY_AFFINITY_2026_07_29.md`。

## 5. 完成证据

- 具体 `LibraryStore` 只在 composition root 创建；presentation 生产引用为零。
- `LibraryApplicationFacade` 分别依赖 `LibraryQueryRepository` 和
  `LibraryCommandRepository`。
- `src/app.dart` 的 production/test/integration_test 消费者均为零，文件已删除。
- `LibraryPage` 与 `PlayerPage` 的行数门禁只降不升，关键 Widget/Route/ValueKey 仍有
  页面级可达性合同。
- 完整 442 项测试通过，3 项显式 benchmark 跳过。
- `flutter analyze` 零问题。
- `flutter build windows --debug` 通过。
- Windows Debug 正式入口点击启动并取得可见窗口。

## 6. 对抗式收官审查

```text
schema: unchanged
FilterQuery / TagQueryService: unchanged
filtered queue: changed intentionally to accepted QueueSnapshot source, tests passed
thumbnail/media queue: unchanged
user data: preserved
protected behaviors: preserved
unauthorized feature removal: none
mount and reachability: page-level architecture/widget contracts passed
native ownership: PlayerService/PlayerBackend single-owner boundary preserved
repository ownership: one LibraryStore/SQLite transaction owner preserved
compatibility barrel: consumers zero, deleted with zero-regression contract
validation: 442 tests, analyze, Windows debug build/start passed
```

## 7. 后续计划

整体重构到此收官，后续不再以“继续拆文件”为独立目标。新产品需求按 vertical slice
进入，修改到哪个一致性边界才迁移哪个局部；只有固定数据集 profile 证明瓶颈时，才下推
SQLite 查询或建立阻断式性能门禁。大页面继续采用“阈值只降不升”的机会式治理，避免
纯结构 churn。
