# ADR-001：渐进式架构迁移与一致性门禁

状态：已接受
日期：2026-07-29

## 背景

Local Tag Player 已有稳定身份、标签查询、播放后端、文件系统、数据库和缓存边界，主要风险来自
巨型页面的状态所有权、生命周期和依赖方向，而不是缺少某种状态管理库。项目同时需要保护
11,000 条本地媒体规模下的交互流畅度、filtered queue 的确定性以及用户维护数据。

2026-07-29 的 Flutter 官方资料、开源项目审计和
[网页端独立评审](https://chatgpt.com/c/6a6954f1-e418-83ec-bcef-09b842b0f2b4)
共同支持渐进式迁移，不支持一次性重写。

## 决策

### 1. 依赖与组合

```text
main
  -> composition root
       -> concrete adapters/repositories
       -> feature factories
       -> LocalTagPlayerApp
            -> feature presentation
                 -> controller/application service
                      -> domain contract
```

- composition root 是唯一允许同时看到具体实现和应用壳的位置。
- presentation/application 不依赖 composition、concrete data 或 concrete platform。
- feature presentation 不导入另一 feature 的 presentation。
- `src/app.dart` 只作为迁移期测试兼容面，生产代码不得导入；消费数量只能下降。

### 2. 状态按一致性边界划分

- 媒体库目标为 4—6 个主要 controller，而不是每个 Widget 一个 ViewModel。
- controller 按失效频率和一致性边界划分；禁止两个可写 owner 持有同一状态。
- controller 不互相监听形成隐式状态图；跨边界由明确命令、不可变快照或应用服务协调。
- controller 不持有 `BuildContext`、`Navigator`、`Route`、Widget、texture、HWND 或 backend
  handle。
- 发布的 `List`、`Set`、`Map` 必须切断底层可变引用；选择状态只保存 stable ID。

### 3. 版本化快照协议

在 Phase 3 实现前先建立下列合同：

```text
ResultEpoch
  = dataRevision
  + filterFingerprint
  + searchFingerprint
  + sortFingerprint

CountEpoch
  = dataRevision
  + filterFingerprint
  + searchFingerprint
  + tagDefinitionRevision

QueueSnapshot
  = accepted ResultEpoch
  + immutable ordered stableMediaIds
```

- 异步结果的凭证只有与当前状态完全一致时才允许发布。
- 排序不改变 `CountEpoch`；选择、列表/网格模式和滚动位置不改变查询凭证。
- 播放器只消费已接受结果生成的 `QueueSnapshot`，不得按 `FilterQuery` 重新查询全库。
- generation 只解决旧结果发布；每类查询还必须限制并发并只保留 latest 待执行任务。

### 4. 跨 Repository 编排与事务

- 跨 Repository 只读组合可在查询 controller 或应用服务中完成。
- 跨 Repository 原子写入必须由 application service/use case 和统一 transaction runner
  完成；ViewModel 只提交命令和展示进度。
- Repository 不调用 Repository，具体实现之间也不互相调用。
- 在没有 schema 或事务改造需求前，本 ADR 只记录边界，不提前引入新 transaction abstraction。

### 5. LibraryStore

当前保留 `LibraryStore` 作为同一 SQLite 数据库的聚合实现，并先收窄消费者使用面。只有同时
具备以下证据才评估物理拆分：

- data/composition 之外的 `LibraryStore` 具体类型引用为 0；
- 至少约 80% 方法只触及单一数据域；
- 跨域写操作数量少且已有明确事务 owner；
- 拆分不增加 SQL 次数、不把批处理退化为逐条调用；
- 测试 fixture 和失败定位出现可测量收益；
- 拆分前后查询计划、队列哈希和数据库完整性一致。

物理拆分是可选结论，不是架构完成的必要条件。

### 6. 性能与行为门禁

在固定 Windows 参考机、profile 模式和确定性 11,000 条数据集建立基线。初始目标：

```text
温缓存标签点击到结果 P95 <= 150 ms
冷查询标签点击 P95 <= 400 ms
debounce 后温缓存搜索结果 P95 <= 250 ms
排序 P95 <= 120 ms，完整标签计数调用 = 0
QueueSnapshot 构造 <= 20 ms，数据库查询 = 0
关键查询 P95 回退 <= 10%
稳定内存回退 <= 15%
```

这些数值在基线工具落地前是观测目标，不是假装精确的 CI 结论。立即生效的确定性合同：

- 排序、选择、视图切换和滚动不得触发完整标签计数；
- 单项选择、视图切换和滚动不得查询数据库；
- 一次稳定标签点击最多一次结果查询和一次延迟计数查询；
- 旧代次可以完成但不得发布；
- 缩略图任务不得占满筛选查询执行通道；
- 页面 dispose 后 listener、timer 和任务必须回到基线。

## 分批顺序

```text
Phase 1.5  行为清单、依赖门禁、查询追踪、版本协议、基准数据
Phase 2A   无状态设置/诊断 Widget
Phase 2B   非破坏性设置 controller
Phase 2C   只读缓存诊断
Phase 2D   缓存修改操作
Phase 2E   备份与恢复
Phase 3A-F 数据修订 -> 选择/视图 -> 排序 -> 查询/计数 -> QueueSnapshot -> 扫描/导入
Phase 4A-E 会话 -> event bridge -> 控件 -> native 生命周期 -> 诊断
Phase 5    收窄 Repository 使用面，按证据决定是否物理拆分
Phase 6    删除已经归零的兼容导出
```

## 下一批安全提交

下一批只做 Phase 1.5 与 Phase 2A：

1. 建立受保护交互清单和缓存诊断 Route characterization test。
2. 建立查询调用追踪基础设施，不改变生产查询。
3. 只提取缓存诊断纯 Widget，所有状态、回调、Route 和 `ValueKey` 原样传入。
4. 不移动删除、清空、重建、备份或恢复逻辑。

出现以下任一情况立即停止扩大范围：

- 必须修改 schema、`FilterQuery`、`TagQueryService` 或 filtered queue；
- 新 controller 需要 `BuildContext`、导航或弹窗；
- 同一诊断状态出现两个可写 owner；
- Route、Key、菜单、确认、返回路径发生差异；
- 新 presentation 导入 concrete data/platform；
- 数据库扫描次数增加；
- focused/full tests、analyze、Windows build 或真实入口验证失败；
- 同机性能或稳定内存超过已建立基线的允许回退；
- 需要顺带重构设置、备份、筛选或播放器。

## 结果

好处是每次提交只改变一个一致性边界，能用页面可达性和确定性合同证明没有隐藏回归。代价是
迁移速度看起来较慢，旧目录和兼容导出会暂时并存，但每个阶段都可运行、可回滚、可独立审查。

## 重新评估条件

- 只有现有 `Listenable` 无法在测量后满足 rebuild 或状态隔离要求时，才评估新的状态管理依赖。
- 只有 LibraryStore 的具体使用面归零且事务、查询、测试证据齐备时，才评估物理拆分。
- 只有 profile 数据证明现有查询路径成为瓶颈时，才评估把更多过滤下推 SQLite。
