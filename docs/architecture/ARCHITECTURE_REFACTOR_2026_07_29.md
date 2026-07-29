# 2026-07-29 架构重构方案

## 结论

Local Tag Player 不需要推倒现有 Repository、稳定身份、过滤语义和播放器后端边界。
当前主要问题是 UI 层职责膨胀、目录按技术类型横向铺开、应用壳与组合根混合，以及测试
长期依赖万能导出文件。重构采用渐进式替换：先建立依赖方向和纵向功能样板，再拆分媒体库
与播放器巨型页面；每一阶段都保持可运行、可回滚并有页面级可达性证据。

目标不是照搬某个“Clean Architecture”模板，而是让标签闭环具备四个性质：

1. Widget 只负责布局、动画和事件转发。
2. ViewModel / 应用服务拥有页面状态、命令和跨 Repository 编排。
3. Repository 是用户数据与会话数据的单一事实源。
4. SQLite、文件系统、FFmpeg、播放器和网络具体实现只在组合根可见。

## 调研依据

- Flutter 官方 Architecture recommendations：
  <https://docs.flutter.dev/app-architecture/recommendations>
- Flutter 官方 Guide to app architecture：
  <https://docs.flutter.dev/app-architecture/guide>
- Flutter 官方 Compass case study：
  <https://docs.flutter.dev/app-architecture/case-study>
- Flutter Compass 示例源码：
  <https://github.com/flutter/samples/tree/main/compass_app/app/lib>
- AppFlowy Flutter 工程：
  <https://github.com/AppFlowy-IO/AppFlowy/tree/main/frontend/appflowy_flutter/lib>
- LocalSend Flutter 工程：
  <https://github.com/localsend/localsend/tree/main/app/lib>
- Very Good Ventures 分层架构文章：
  <https://www.verygood.ventures/blog/very-good-flutter-architecture>

共同原则是职责分离、单向数据流、依赖注入、Repository、可单测状态类和按功能组织 UI。
不同项目对状态管理库和目录命名并不一致，因此本项目不因架构重构引入 Provider、Bloc、
Riverpod 或代码生成；先使用 Flutter SDK 已有的 `Listenable` / `ChangeNotifier` 和明确
接口，只有真实复杂度证明需要时才增加依赖。

## 当前审计

审计基线为 2026-07-29 工作树：

- 103 个生产 Dart 文件、22 个测试文件，合计约 66,457 行。
- `library_page.dart` 约 7,472 行、52 个直接 import，同时承载设置、缓存诊断、扫描、
  筛选、文件操作和播放 Route 编排。
- `player_page.dart` 约 5,153 行、44 个直接 import，同时承载播放状态、窗口状态、
  画质实验、队列和大量 UI。
- `app.dart` 同时承担 bootstrap、组合根、应用 Widget 和测试万能导出面。
- `LibraryStore` 同时实现四个 Repository contract，但已经把扫描、标签、视频持久化和
  备份拆到协作者；应先收紧 facade，再评估物理拆库，不能为了类数量强行拆事务。
- `FileSystemAdapter`、`DatabaseProvider`、`FFmpegBackend`、
  `PlayerService → PlayerBackend`、`FilterQuery / TagQueryService` 和 stable identity
  已有正确边界，应继续保护。

## 目标依赖方向

```text
main
  -> composition/bootstrap
       -> concrete data + platform implementations
       -> app shell
            -> feature presentation
                 -> feature view model / application service
                      -> domain contracts
                           <- data repositories/services
                           <- platform adapters
```

硬规则：

1. `app/` 只负责主题、无障碍、路由壳和顶层 Widget 组装。
2. `composition/` 是唯一允许实例化具体 Repository、网络客户端、播放器后端和平台
   adapter 的位置。
3. `features/<name>/presentation` 只能依赖 domain/application contract，不依赖同功能
   的 concrete data 实现。
4. feature 之间不得直接导入对方 presentation；跨功能流程通过应用服务、共享领域模型
   或 Route 输入完成。
5. `domain` 不导入 Flutter、`dart:io`、SQLite、FFmpeg、mpv 或平台通道。
6. Repository 之间不互相依赖；跨 Repository 逻辑放在 ViewModel 或明确 use case。
7. Domain / Use Case 层按复杂度启用。只代理一次方法调用的类不新增。
8. `src/app.dart` 暂时仅作为测试兼容导出面；生产代码不得导入它。测试逐步迁到具体
   模块 import，最终删除万能导出。

## 目标目录

```text
lib/src/
  app/
  composition/
  domain/{models,policies,repositories}/
  data/{repositories,services}/
  features/
    library/{application,presentation}/
    player/{application,presentation}/
    tags/{application,presentation}/
    diagnostics/{application,presentation}/
    update/{domain,data,presentation}/
  platform/
  ui/core/
```

迁移期间允许旧 `models/`、`services/`、`pages/`、`widgets/` 与目标目录并存，但新功能
必须进入目标边界；旧目录只能按阶段逐步减少，不能产生新的反向依赖。

## 性能架构

- 标签点击先提交可见结果；计数、缩略图预取和媒体解析继续使用延迟、代次取消和限流。
- 排序只重排当前结果，不触发完整 `resultCounts`。
- ViewModel 暴露不可变或只读快照；Widget build 不枚举磁盘、不访问 SQLite、不创建
  FFmpeg / Player 实例。
- 11,000 条视频规模下，页面状态拆分必须减少 rebuild 范围，不能把整个媒体库改成一个
  高频 `notifyListeners()`。
- 播放器 Route 继续独占 `PlayerService`，filtered queue 内容和顺序由来源页面一次性
  传入，不在播放器重新查询全库。

## 分阶段迁移

### Phase 0：边界与测量

- [x] 记录审计指标、受保护行为和目标依赖方向。
- [x] 增加架构合同，阻止应用壳实例化具体更新服务和 update presentation 反向依赖 data。
- [x] 为最大文件、生产代码导入兼容 `app.dart`、跨 feature presentation import 增加
  渐进阈值；阈值只降不升。
- [x] 建立受保护交互清单、测试期查询调用追踪器和 11,000 条确定性生产形态基准数据生成器。
- [x] 在媒体库状态迁移前实现并验证 `LibraryResultEpoch`、`LibraryCountEpoch`、
  `LibraryResultSnapshot` 与 `LibraryQueueSnapshot` 合同。

Phase 1.5 的发布协议已经接入现有过滤和延后计数链路：

- `LibraryResultEpoch = dataRevision + filterFingerprint + searchFingerprint + sortFingerprint`；
  页面只接受与调度时完整版本一致的结果。
- `LibraryCountEpoch = dataRevision + filterFingerprint + searchFingerprint +
  tagDefinitionRevision`；排序不进入计数版本，也不触发 `resultCounts`。
- `LibraryResultSnapshot` 与 `LibraryQueueSnapshot` 只复制有序 stable `videoId`，不保存
  可变路径，也不包裹调用方仍可修改的列表。
- 标签定义暂与现有媒体库提交共用 `_libraryDataRevision`；Phase 3A 引入明确 change set
  后再拆出独立 `tagDefinitionRevision`，当前保守失效不会发布旧计数。
- `test/fixtures/legacy_interaction_manifest.json` 是只增不减的页面/Route 挂载基线；
  本阶段获授权删除仍为空。

### Phase 1：应用壳与纵向样板

- [x] `main.dart` 只调用 bootstrap。
- [x] `LocalTagPlayerApp` 移到 `app/`，不读取 `Platform` 或创建具体服务。
- [x] 更新功能迁到 `features/update/{domain,data,presentation}`。
- [x] `AppUpdateService` 由组合根创建并注入启动提示、媒体库和关于页。

### Phase 2：设置与诊断从媒体库页面解耦

- [x] 2A-1 把设置首页导航提取为无状态 feature 叶节点；数据与回调仍由现有 owner 传入，
  Route 与全部 `ValueKey` 不变。
- [x] 2A-2a 把缓存诊断标题与健康状态提取为纯展示 feature 叶节点；不读取 `CacheStats`，
  不持有 Future、刷新、重试或清理命令。
- [x] 2A-2 把加载占位、覆盖率、指标、后台任务和失败详情提取为只读快照视图；统计
  Future、动作区、刷新、重试和清理命令仍由原页面拥有。
- [x] 2B 按一致性边界拆分普通设置 controller，不建立包含备份与缓存任务的巨型
  `SettingsViewModel`。
- [x] 2C 单独迁移只读缓存诊断；读取、刷新、错误和 dispose 使用 latest-only 发布。
- [x] 2D 迁移现有缓存维护命令、失败恢复与互斥；源码没有删除/重建入口，不新增未授权
  破坏性操作。
- [x] 2E 最后迁移现有备份设置、状态订阅和维护命令；源码没有数据库关闭、替换、重开
  或导入恢复入口，因此不新增破坏性流程，现有跨服务补偿仍由应用服务拥有。
- [x] 每一步保留确认、取消、撤销、返回和所有 `ValueKey`，增加 Route 级挂载测试。

Phase 2B 只迁移 `PlaybackSettings` 这一致性边界：

- `PlaybackSettingsController` 是普通播放设置的唯一可写 owner，立即发布 UI 快照并按用户
  操作顺序串行持久化；失败只回滚仍为最新的请求，回滚目标是最后成功持久化快照。
- controller 只依赖 `ChangeNotifier` 与设置模型，不持有 `BuildContext`、Route、备份状态、
  缓存任务或平台资源；备份和缓存继续由原页面分别拥有。
- 设置首页、播放行为、渲染器、解码器、画质、播放器交互、删除设置和快捷键入口均保留；
  页面级测试覆盖“首页 → 播放设置 → 修改 → 返回首页”的真实挂载路径。
- `LibraryPage` 行数门禁由 6,642 下调到 6,640；后续 Phase 2C 不得为迁移方便调高。

Phase 2C 将缓存统计读取迁入泛型 `CacheDiagnosticsController<CacheStats>`：

- controller 只依赖 Flutter foundation 和注入的异步 loader，不导入 `ThumbnailService`、
  Repository、文件系统或平台实现；页面仍负责组合当前媒体集合与缓存服务。
- 每次刷新递增 generation，旧结果、旧错误和 dispose 后完成的 Future 均不得发布。
- loading/error/data 分派由只读 presentation 处理；错误态不展示原始异常，避免本机路径
  泄漏，并提供只重新读取统计的恢复入口。
- 失败项重试、失败标记清理、Repository 写入、动作互斥与反馈仍由页面拥有，留给
  Phase 2D；`LibraryPage` 行数门禁继续下调到 6,636。

Phase 2D 将现有“重试失败项”和“清除失败标记”迁入
`CacheDiagnosticsMaintenanceController<T>`：

- controller 通过注入命令编排缓存服务与 Repository，互斥执行重试/清除；重试只持久化
  已清除旧错误的条目。
- 清除标记后 Repository 写入失败会恢复全部原失败原因，避免内存 UI 与持久化状态分裂。
- controller 不持有具体缓存实现、`BuildContext`、Route、Widget 或读取 controller；
  页面继续负责 SnackBar 和动作结束后的只读统计刷新。
- 源码没有缓存文件删除、全量重建、确认或撤销入口；本阶段不凭路线描述新增用户未授权
  的破坏性功能。全部现有动作 Key 保留，`LibraryPage` 行数门禁降到 6,633。

Phase 2E 将现有视频数据备份设置迁入独立纵向切片：

- `SerialSettingsController<T>` 统一串行保存、最新失败回滚与最后成功快照；
  `PlaybackSettingsController` 复用同一合同，不形成第二套竞态语义。
- `DataBackupStatusController<T>` 是状态流订阅和 dispose 的唯一 owner；
  `DataBackupMaintenanceController<TReport>` 互斥立即备份、完整性检查和导出，但不读取
  数据库、不选择文件，也不持有 `BuildContext` 或 Route。
- `DataBackupSettingsWorkspace` 只在备份二级页挂载，拥有 controller 生命周期、
  Dialog 和 SnackBar。设置文件失败时恢复运行态的跨服务补偿仍在页面应用服务回调，
  完整性检查仍在 Repository，导出仍经 `FileSystemAdapter`。
- 当前源码没有主库关闭、文件替换、重开、全局失效或导入恢复入口；不因计划中的防护
  描述虚构未授权流程。Route 级测试保护首页入口、卡片、三个维护动作与返回路径，
  `LibraryPage` 行数门禁降到 6,021。

### Phase 3：媒体库 MVVM

- [x] 3A 建立独立结果数据/标签定义修订 tracker；排序不提交数据变化，普通内容变化不再
  误推进标签定义代次，root、扫描、relink、删除和标签维护仍同时失效两者。
- [x] 3B 迁移只保存 stable ID 的主结果选择状态，以及网格密度、侧栏和标签面板显隐。
- [x] 3C 单独迁移排序，验证完整计数调用为 0，且不会隐式改变既有播放队列。
- [x] 3D 以 `LibraryQueryController` 和 `LibraryFacetCountController` 迁移筛选、搜索、结果和计数；
  共享版本协议，但不得互相成为可写状态源。
- [x] 3E 只从已接受的 `ResultSnapshot` 创建 `QueueSnapshot`。
- [x] 3F 最后迁移扫描/导入生命周期，保留 latest-only 排队、限流和 generation cancellation。
- [x] 3G 把文件菜单、标签维护、Missing/Relink 变成明确 command。
- [ ] 3H `LibraryPage` 只保留布局、动画、Route 跳转和命令绑定。

Phase 3A/3B 的落地边界：

- `LibraryRevisionTracker` 每次真实内容提交推进 data revision；只有可能改变标签候选、
  folder 层级、定义或关系的提交推进 tag definition revision。`LibraryCountEpoch`
  使用独立标签代次，不再让收藏、播放进度或媒体详情把标签结构误判为变化。
- `LibrarySelectionController` 通过复用的 `UnmodifiableSetView` 暴露 stable `videoId`
  集合，统一进入、切换、全选、清空和删除成功项；不持有 `VideoItem` 或 mutable path。
- `LibraryViewPreferencesController` 只拥有网格密度、主侧栏折叠和标签发现面板显隐，
  不触发筛选、计数或缩略图工作。页面仍用一次复合 `setState` 协调来源切换，并继续通过
  应用服务持久化网格/排序偏好。
- 排序、筛选/计数、QueueSnapshot 和扫描生命周期留给 3C-3F；页面行数门禁降到 6,019。

Phase 3C 的落地边界：

- `LibrarySortController` 唯一拥有字段、方向、稳定 fingerprint 与纯内存重排；
  自然排序、未知大小末尾和稳定路径兜底保留在纯 domain。
- controller 不读取 Store、`TagQueryService`、`resultCounts`、持久化或队列。页面在一次
  `setState` 内只重排已接受 `FilterState`，随后通过应用服务保存偏好。
- 页面级回归从名称正序切换为倒序，确认 stable `videoId` 成员不变且完整计数调用零增长；
  排序入口、菜单、回调、最近播放、收藏、本地目录和 filtered queue 均保留。
- 筛选/计数、QueueSnapshot 和扫描生命周期继续留给 3D-3F；页面行数门禁降到 5,998。

Phase 3D 的落地边界：

- `LibraryQueryController` 保存最近请求的 `FilterQuery`、已接受 `FilterState` 与
  `FilterStateSource` 缓存；自增 revision、`LibraryResultEpoch` 和页面当前输入三重
  校验共同拒绝旧搜索、旧筛选、旧排序或旧数据结果。
- `LibraryFacetCountController` 分别保存当前候选计数和全库稳定计数的不可变 Map，
  复用原空闲调度与 `LibraryCountEpoch`；它不读取或写入 query owner。
- 页面只协调输入快照与发布后的局部重建，先更新可见视频，再安排非关键计数。页面级
  搜索/清空/排序回归证明 stable-ID 成员和顺序正确，高频交互完整计数调用零增长。
- QueueSnapshot 与扫描生命周期继续留给 3E-3F；页面行数门禁降到 5,977。

Phase 3E 的落地边界：

- `LibraryPlaybackQueueController` 只验证已接受结果与展示视频的 stable-ID 成员/顺序，
  唯一通过 `LibraryQueueSnapshot.fromResult` 转换；不读取 Store、不筛选、不排序。
- 主筛选复用 query owner 的 result epoch；最近、收藏和本地目录使用显式来源 epoch。
  结果快照与队列标题在一次 build 中绑定，旧 Widget 回调无法借当前页面状态换源。
- `PlayerPage` 同时接收同序不可变 playlist 与 queue snapshot；邻近预热只消费该队列并
  跳过 missing。生产页面不直接构造 Result/Queue snapshot，也不从 Store 重建 playlist。
- 扫描/导入生命周期继续留给 3F；媒体库/播放器页面门禁分别降到 5,975 / 5,374。

Phase 3F 的落地边界：

- `LibraryScanLifecycleController<TMediaProgress>` 保存扫描 operation revision、首次接受的
  Repository generation、路径检查 revision 与媒体解析 generation；四类旧回调均拒绝。
- controller 互斥扫描，暂停失败只回滚同一代次，取消状态保持到扫描 Future 退出；
  播放器让盘只镜像同一快照，不建立第二套扫描状态。
- 页面继续注入 `FileSystemAdapter` 检查、Repository 扫描/暂停/取消与既有媒体服务；
  后端限流、SQLite 提交、folder/manual 标签、缓存队列和用户数据均未迁入 controller。
- 扫描进度文案迁入只读 presentation 叶节点；真实页面回归覆盖重新扫描、暂停、继续、
  取消和相邻搜索/排序/更多菜单。媒体库页面门禁降到 5,932。

Phase 3G-1 的落地边界：

- 定位、同目录改名和删除分别使用显式 command；`LibraryFileCommandExecutor` 只编排
  注入回调，不导入 Store、FileSystemAdapter、ThumbnailService、Flutter 或 Route。
- 改名保持“物理文件 → Repository mutable path → 失败时原路径补偿”；删除保持“可选
  回收站 → Repository 记录 → best-effort 缓存”，不新增永久删除或静默降级。
- 批量删除返回不可变成功 stable-ID 与失败对象，页面只清除成功选择并统一刷新；Dialog、
  删除偏好、SnackBar、播放器延迟刷新和全部菜单入口仍由原 presentation owner 管理。
- 文件命令 focused/页面/播放器回归及全量门禁通过；媒体库页面预算降到 5,919。

Phase 3G-2 的落地边界：

- 单视频手动标签替换使用显式不可变 command；输入独立携带 selected、locked folder、
  可选一级父级和目标媒体，不从页面或 Store 隐式读取第二份状态。
- `LibraryManualTagCommandExecutor` 负责大小写归一、folder 标签保留、二级标签父级隔离
  与失败时 `VideoItem.tags/childTags` 完整恢复；它不导入 Flutter、Route、Store 或
  具体 Repository。
- `LibraryTagMaintenance` 的批量提交失败会恢复当前视频的 tagId 关系，并清除本次新建
  但未提交的标签索引；SQLite schema、tagId 语义与 Tag Manager 管理/批量入口未改变。
- 主库提交后的备份入队是不可反向补偿的次级副作用；失败只发布备份诊断并由后续全量
  核对修复，不能向 command 抛出并恢复旧 `VideoItem`。
- TagEditor 的确认/取消、播放器延迟刷新、反馈和 Tag Manager Route 仍由原 presentation
  owner 管理；focused/页面回归及全量门禁通过，媒体库页面预算降到 5,913。

Phase 3G-3 的落地边界：

- 单条 Missing/Relink 使用显式不可变 command，创建时捕获 stable videoId、旧 mutable
  path 与 fingerprint；picker 返回后的过期身份、空路径和同一身份重复提交会被拒绝。
- `LibraryMissingRelinkCommandExecutor` 不导入 Flutter、Store、FileSystemAdapter、
  Route 或具体 Repository；最终路径占用、可读性、fingerprint 和 SQLite 仍由原
  Repository 唯一校验。
- picker 初始目录、取消不忙碌、行级 spinner、SnackBar、返回布尔值、播放器原地重试、
  批量预览/定向重试/root 更新全部保留在原 presentation/service owner。
- 单条 Repository batch 失败会恢复同一 `VideoItem` 引用、旧 path、missing、
  active/detached 与 tagId 索引；确定性数据库关闭测试覆盖补偿。`LibraryPage` 门禁保持
  5,913，Phase 3G 完成。

Phase 3H-1 的落地边界：

- 继续观看清理/撤销使用无 UI executor；精确快照、同一对象修改、批量提交、清理失败
  恢复和撤销失败重新清空由单一 owner 管理。
- 最近播放选择复用 `LibrarySelectionController` 并只保存 stable videoId；路径变化不能
  丢失或串用临时选择，`RecentPlaybackView` 不再按 pathKey 判断选中。
- 清理单条/已选/全部、确认弹窗、10 秒撤销、新播放不覆盖、SnackBar、刷新和 Route
  全部保留；`LibraryPage` 门禁由 5,913 降到 5,796。

Phase 3H-2 的落地边界：

- `LibrarySourceNavigationController` 唯一持有四类结果来源、当前本地路径和 LIFO
  返回栈；不持有 Widget、Route、Store、筛选查询、VideoItem 或播放队列。
- 路径规范化与平台等价比较由页面注入现有 `TagRules` 策略，controller 不直接依赖
  `dart:io Platform` 或文件系统。标签/搜索只切换来源的旧行为与主入口完整重置行为
  分成两个显式命令，避免“统一实现”误改历史栈语义。
- 页面继续在一次 `setState` 中复合清理搜索、标签、收藏和临时选择；侧栏四入口、本地
  文件夹进入、按钮/鼠标返回、root 移除、文件选择器上下文和 filtered queue 绑定保留。
- 6 项纯状态测试、页面/widget 回归、架构合同和全量门禁通过；`LibraryPage` 预算降到
  5,748，Phase 3 媒体库 MVVM 一致性边界迁移完成。

### Phase 4：播放器 MVVM

- [x] 4A 拆出 `PlayerSessionController`，只拥有队列、当前媒体与会话命令。
- [x] 4B 拆出 latest-request 与 backend event bridge。
- [x] 4C 拆出控件显隐、计时器和快捷键状态。
- [x] 4D 最后处理 texture、native window 和全屏生命周期；每种资源只有一个 dispose owner。
- [ ] 4E 独立迁移播放器诊断。

Phase 4A 的落地边界：

- `PlayerSessionController` 同时校验来源对象和已接受 `QueueSnapshot` 的 stable-ID
  有序快照；重复 ID、对象缺失或错序立即拒绝，禁止从 Store 或 mutable path 重建队列。
- 来源队列和二级标签子集只以不可修改视图发布；初始化、切换、过滤和删除都按
  `videoId` 保持当前播放身份，空二级标签结果只能回退同一来源队列。
- 标签匹配规则由页面以回调注入，controller 不导入 Flutter、Store、`TagRules`、
  `PlayerBackend` 或平台实现。旧文件仅保留 import 路径兼容导出。
- `PlayerPage` 继续唯一拥有 `PlayerService`、backend open、texture/native window、
  timer、全屏、Route 与 Widget 生命周期；页面门禁降到 5,371，Phase 4A 完成。

Phase 4B 的落地边界：

- `PlayerOpenRequestController` 用 `revision + videoId + path` 捕获不可变打开意图；
  stable ID 决定媒体身份，path 只是本次 `openPath` 快照，旧代次不能发布成功或错误。
- 新选择、missing 前置拒绝和页面取消都会推进代次；重试从安全失败快照恢复同一
  stable ID/path，错误码不携带本地路径。
- `PlayerBackendEventBridge` 只绑定四类 Stream 与页面回调，统一持有订阅并幂等取消；
  页面在 stop/dispose backend 前等待 bridge，仍唯一解释 EOF、进度、错误和播放反馈。
- 播放进度纯函数迁入 player domain，媒体库不再导入播放器 presentation；
  `PlayerBackend`、后端选择、texture/native window 和全屏 owner 均未改变。
- 4 项 request/event focused tests、页面回归、架构合同和全量门禁通过；`PlayerPage`
  预算降到 5,370，Phase 4B 完成。

Phase 4C-1 的落地边界：

- `PlayerInteractionStateController<TIcon>` 唯一持有主控制条显隐、设置/悬停锁定、
  快捷键反馈内容，以及控制条/反馈两只可取消 Timer。
- 新显示意图覆盖旧 Timer；设置或悬停期间不隐藏，关闭/离开恢复统一倒计时，dispose
  后不再调用 presentation 回调。
- controller 不导入 Flutter、Focus、Overlay、Route、窗口或播放器资源；页面注入
  `IconData` 与无上下文刷新回调。
- FocusNode、键位解析、全屏队列 Timer、窗口/texture 和快捷键命令执行保持原 owner；
  4 项 focused tests、页面回归和全量门禁通过，页面预算降到 5,325。

Phase 4C-2 将嵌套暂停深度、标签编辑门禁、命令处理和焦点恢复资格迁入纯 Dart
`PlayerShortcutGateController`；Focus/Keyboard/Route/Overlay 探测与命令执行仍在页面。
4 项 focused tests 与全量门禁通过，页面预算降到 5,322，Phase 4C 完成。

Phase 4D 将全屏/过渡状态、会话恢复和退出窗口命令顺序迁入纯 Dart
`PlayerFullscreenLifecycleController`；`endOfFrame`、`window_manager` 与 mounted
事实仍由 presentation 注入。`PlayerResourceLifecycleCoordinator` 唯一绑定 Texture
listener，并串行取消 backend events、stop、dispose 与等待 released；重复释放共享
Future，异常仍完成 Route 协调信号。页面预算降到 5,021，filtered queue、当前 index、
后端选择、overlay airspace 和用户数据不变。
- [ ] 画质实验只依赖 `PlayerRuntimeAccess`，不进入 Widget 状态机。
- [ ] 保留快速切换 latest-request、纹理释放、全屏恢复和 filtered queue 合同。

### Phase 5：数据层收口

- [ ] 先按 facade 使用面拆分只读查询与命令接口，再评估 `LibraryStore` 物理拆分。
- [ ] 需要同一 SQLite 事务的写入继续由同一 transaction coordinator 持有。
- [ ] 只有 profile 证明需要时才把过滤查询下推 SQLite；不改变 AND / OR / NOT 语义。

### Phase 6：测试和兼容面清理

- [ ] 测试目录镜像生产模块，公共 fake 移入测试 support。
- [ ] 测试从 Phase 2 起随所改模块逐个改为具体 import，兼容 import 数只能下降。
- [ ] 没有消费者后删除 `src/app.dart` 兼容导出面。

## 网页端独立评审采纳记录

2026-07-29 已把产品目标、硬约束、审计数据、目标依赖和 Phase 1 结果提交到
[网页端独立评审](https://chatgpt.com/c/6a6954f1-e418-83ec-bcef-09b842b0f2b4)。
评审结论不是推翻当前方向，而是把“大页面分阶段拆分”收紧为“一次迁移一个一致性边界”。

采纳：

1. 在筛选与播放器重构前建立版本化发布凭证：
   `ResultEpoch = dataRevision + filter/search/sort fingerprint`，
   `CountEpoch = dataRevision + filter/search/tagDefinition revision`，
   `QueueSnapshot = ResultEpoch + ordered stable media IDs`。
2. 跨 Repository 读取可以由查询 controller 组合；跨 Repository 原子写入必须由应用服务和
   transaction runner 持有，ViewModel 不决定事务边界。
3. ViewModel 禁止持有 `BuildContext`、`Navigator`、`Route`、Widget 或 native 资源；
   texture、backend handle、window handle 和 listener 必须有明确且唯一的 dispose owner。
4. 继续使用 SDK `Listenable` / `ChangeNotifier`，按失效频率和一致性边界拆为少量 controller；
   同一状态存在两个可写 owner 或 controller 互相监听时审查失败。
5. `LibraryStore` 当前不做物理拆分。先让 data/composition 之外的具体类型引用归零，并记录
   方法—数据表亲和度、跨域事务数量、测试收益和查询计划；证据不足时保留聚合实现。
6. 测试 import 迁移不等待 Phase 6；从现在起所改测试优先改为具体模块 import，兼容面预算
   只能下降。

暂不直接照搬：

- 评审给出的 P95、帧耗时和内存阈值先作为“参考机初始目标”，必须在固定 Windows 机器、
  profile 模式和确定性 11,000 条数据集上取得基线后，才能升级为阻断式 CI 门禁。
- 不因评审建议提前实现 schema、事务或筛选语义变更；版本协议先以行为合同和观测设施落地。

详细决策、停止条件和重新评估证据见
[`ADR_001_PROGRESSIVE_ARCHITECTURE_MIGRATION.md`](ADR_001_PROGRESSIVE_ARCHITECTURE_MIGRATION.md)。

## 每阶段交付门禁

```text
schema: 默认不变；变化时必须迁移、幂等和旧库验证
FilterQuery / TagQueryService: 行为等价测试
filtered queue: 内容、顺序、当前 index 与返回状态等价
thumbnail/media queue: 并发、取消、重试和播放让盘等价
user data: 标签、收藏、播放记录、备份与设置保留
protected behaviors: 页面/Route 级可达性证据
performance: focused benchmark 或真实大库交互无回退
validation: focused tests + full tests + analyze + Windows debug build + 真实点击
```

## 本阶段获授权删除

无。Phase 1 只移动更新模块、分离组合职责并收紧依赖注入；Phase 1.5 只新增版本发布
护栏并替换重复的私有查询签名实现。所有原有入口、`ValueKey`、回调、Route 和降级路径
均由交互清单保护。
