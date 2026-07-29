# ARCHITECTURE.md

## 2026-07-30 正式播放边界与属性一致性

`Architecture Baseline 0.5.137` 把正式播放拓扑固定为：

```text
Flutter PlayerPage
-> PlayerService
-> MediaKitPlayerBackend
-> media_kit / NativePlayer / libmpv
-> media_kit_video Flutter Texture
```

产品设置不再暴露“MediaKit / MPV”二选一，因为两个旧选项最终创建的是同一个
`MediaKitPlayerBackend`。`PlayerRendererPreference` 只作为旧设置文件的兼容读取面；
读取后的运行值和保存值统一规范化为 `mediaKit`。`windows-native-hwnd` 仍属于显式 QA
组合根覆盖，不是用户设置，也不得把它的 NVIDIA 激活证据套用到正式 Texture 路径。

媒体打开以单一 latest-request worker 串行协调。open 前只提交解码与缓存引擎快照，
open 后恢复一次滤镜基线并提交一次显示快照。GPU 能力探测可以异步执行，但下一媒体
open 必须先等待上一任务结束，再由新媒体基线覆盖共享 libmpv 属性；结果发布同时校验
打开代次和路径。

设置意图与会话终态严格分离。GPU 缩放、滤镜和 HDR→SDR 色调映射使用固定属性集合，
写入后最多等待 200 ms 逐项读回；只有全部一致才是 `applied`。门槛未通过、属性不可用、
写入/读回不一致和探测异常均为非活动终态。正式 MediaKit 路径不运行 NVIDIA 原生探测，
NVIDIA VSR/HDR 诊断只允许出现在带“原生 QA”前缀的可选平台边界。

## 2026-07-30 Windows 原生滤镜事务与 MediaKit SDK 边界

正式应用继续以 MediaKit + `media_kit_video` Texture 为默认播放边界。Windows 原生
child HWND/libmpv D3D11 后端是可选平台实现，只用于 NVIDIA 激活门禁和后续原生增强，
不得反向成为页面或业务层的隐式默认。

原生滤镜设置由 `PlayerService` 的事务层统一提交、回读和回滚。libmpv/原生后端必须为
事务涉及的每个属性提供可收敛的 observed state；短暂异步不一致最多等待 200 ms，持续
不一致仍原子回滚。`deband` 与四个参数属于该 contract，不能只在 `vf` 中隐式生效。

MediaKit Windows 输出目前仍是：

```text
libmpv OpenGL Render API -> ANGLE EGL -> D3D11 texture -> Flutter Texture
```

固定补丁只提供 D3D11 device/context/texture 的原生只读访问，不构成稳定的逐帧插件 ABI。
未来 RTX Video SDK 原型只能放在原生 `Read()` 后、Flutter descriptor 返回前，并必须具备
格式/色彩、GPU 同步、surface 重建、device-loss、生命周期、原帧回退和帧预算 contract。
在具体 SDK 许可与可再分发清单完成审查前，该接口不得承载随包发布的 NVIDIA 文件。

## 2026-07-29 渐进式整体架构重构

`Architecture Baseline 0.5.134` 采用 Flutter 官方推荐的混合分层路线：共享数据和领域
contract 按类型组织，UI 按功能组织；不引入新的状态管理依赖，也不采用一次性重写。
第一阶段把 `LocalTagPlayerApp` 与 bootstrap 组合根分离，并将更新能力迁入
`features/update/{domain,data,presentation}`。`GitHubReleaseUpdateService` 只在组合根
实例化，应用壳、媒体库与关于页只依赖 `AppUpdateService`。详细审计、目标依赖方向和
Phase 0-6 门禁见 `docs/architecture/ARCHITECTURE_REFACTOR_2026_07_29.md`。

代码体积治理把 `LibraryPage` 收敛为 750 行 Route/Widget 编排外壳。生命周期、扫描、
导航、最近播放、查询、筛选、Route、播放和用户命令分别由独立 mixin 协调，所有状态与
服务仍引用同一个页面运行时，未创建第二个可写 owner。设置页保留 controller、缓存维护
和业务命令 owner，纯展示工作区只接收快照与回调。架构合同要求外壳低于 1000 行、所有
新协调文件低于 500 行；schema、标签查询、filtered queue、缓存队列与用户数据不变。

Phase 1.5 在 `features/library/domain` 建立纯 Dart 的查询指纹、结果/计数 epoch 和不可变
结果/播放队列快照。媒体库过滤与延后计数发布使用同一版本身份；排序改变结果 epoch，
但不改变计数 epoch。受保护交互清单、测试期查询追踪器和 11,000 项确定性 fixture
作为后续 MVVM 迁移的前置护栏。

Phase 2A-2 先把缓存诊断标题与健康状态迁为 `features/settings/presentation` 的无状态
叶节点；统计 Future、刷新、失败重试、清理和生命周期仍由原页面唯一拥有。
随后加载、覆盖率、指标、后台任务和失败详情也迁入只读快照视图，动作区继续由原 owner
注入，不形成第二个可写状态源。

Phase 2B 将普通 `PlaybackSettings` 收口到 `PlaybackSettingsController`。它立即发布
UI 快照、串行执行持久化，并只把仍为最新的失败请求回滚到最后成功落盘快照；备份状态、
缓存 Future/命令、Route、`BuildContext` 和平台资源继续由各自 owner 管理。

Phase 2C 使用泛型 `CacheDiagnosticsController<T>` 管理缓存统计的 generation、
loading/error/data 与 dispose。controller 只接收 loader，不依赖 `ThumbnailService`、
Repository 或平台实现；presentation 解释只读状态，重试、清理和持久化命令仍由页面拥有。

Phase 2D 使用泛型 `CacheDiagnosticsMaintenanceController<T>` 互斥编排现有失败项重试、
失败标记清除和 Repository 写入；清除写入失败时恢复原错误。当前源码没有缓存删除或
全量重建入口，架构迁移不据此新增破坏性操作。

Phase 2E 把现有备份设置拆为 bounded vertical slice。`SerialSettingsController<T>` 负责
开关的串行乐观一致性，`DataBackupStatusController<T>` 唯一拥有状态流订阅，
`DataBackupMaintenanceController<TReport>` 互斥立即备份、只读检查和导出；
`DataBackupSettingsWorkspace` 只拥有这些 controller 的 Widget 生命周期及用户反馈。
运行态开关与设置文件失败补偿仍在页面应用服务回调，数据库检查仍在 Repository，
文件选择与写出仍经 `FileSystemAdapter`。当前产品没有主库关闭/替换/重开或导入恢复
入口，因此本阶段不虚构数据库替换事务。

Phase 3A/3B 将查询失效身份与纯页面状态拆成三个轻量 application owner。
`LibraryRevisionTracker` 让所有内容提交推进 data revision，但只有 root、扫描、relink、
删除和标签维护等变化推进 tag definition revision；`LibrarySelectionController` 只保存
stable `videoId`，`LibraryViewPreferencesController` 只保存网格密度、侧栏和标签面板
显隐。三者都不持有 Store、筛选服务、Route 或平台资源；筛选、排序持久化、批量删除与
复合 `setState` 仍由页面应用层协调。

Phase 3C 将排序字段、方向、稳定 fingerprint 和纯内存重排收口到
`LibrarySortController`，并把自然排序算法迁入纯 domain。controller 不持有 Store、
`TagQueryService`、计数查询、持久化或队列；页面只对已接受的 `FilterState` 原地换序并
通过应用服务保存偏好。排序不会触发完整筛选或标签计数，也不会改变 filtered queue 的
stable-ID 成员集合。

Phase 3D 使用两个互不写入的 application owner。`LibraryQueryController` 持有最近提交
的 `FilterQuery`、已接受 `FilterState`、查询缓存和 latest-only revision；只有请求代次、
`LibraryResultEpoch` 与页面当前输入都一致时才发布。`LibraryFacetCountController`
分别持有当前筛选候选计数和全库稳定计数的只读快照，继续通过空闲窗口延后计算。
页面负责按“先视频结果、后非关键计数”的顺序协调，两个 controller 不互相监听或导入。

Phase 3E 建立已接受结果到播放器队列的单向转换。`LibraryPlaybackQueueController`
验证 `LibraryResultSnapshot` 与展示视频的 stable-ID 成员和顺序，再唯一调用
`LibraryQueueSnapshot.fromResult`；不得执行筛选、排序或 Store 查询。结果快照与队列
标题在同一次页面 build 输入上捕获，`PlayerPage` 同时接收不可变 playlist 与来源 epoch
快照。旧 Widget 回调或成员不一致只能拒绝，不能从当前 Store 重建另一份队列。

Phase 3F 使用泛型 `LibraryScanLifecycleController<TMediaProgress>` 收口扫描、路径导入
检查和扫描后媒体解析的生命周期。扫描 operation revision 与 Repository generation
共同拒绝旧进度/结果/错误；路径检查和媒体解析各自使用 latest-only generation。
controller 不导入 Store、文件系统、具体媒体服务、Flutter 或平台实现，实际扫描限流、
SQLite 事务、folder/manual 标签提交、缩略图和媒体探测仍由既有边界唯一拥有。

Phase 3G-1 把定位、改名和删除表达为显式文件 command，并由
`LibraryFileCommandExecutor` 编排注入的平台/Repository 回调。executor 不持有 Store、
具体文件系统、缓存服务或 UI；改名的跨边界补偿和删除的回收站/记录/可重建缓存顺序
保持不变。Dialog、偏好保存、SnackBar、Route 和页面刷新仍由 presentation owner 管理。

Phase 3G-2 把单视频手动标签替换表达为显式不可变 command。
`LibraryManualTagCommandExecutor` 只拥有标签归一、locked folder 保留、当前一级父级
作用域与内存模型失败补偿；Repository 批量写入仍由 `LibraryTagMaintenance` 唯一负责，
并在失败时恢复 video-tag 关系和本次新建的标签索引。主库提交后的备份入队不可反向
回滚，失败只发布诊断并由后续全量核对修复。Tag Manager 的管理/批量命令、Dialog、
Route、反馈和刷新时机仍由原 owner 管理。

Phase 3G-3 把单条 Missing/Relink 表达为捕获 stable videoId、旧 mutable path 与
fingerprint 的不可变 command。`LibraryMissingRelinkCommandExecutor` 只拒绝过期、
空路径和同一身份重复提交；picker、spinner、SnackBar、Route 和批量前缀替换仍在原
presentation/service owner。Repository 继续唯一负责路径占用、文件可读性、fingerprint
和 SQLite；单条 batch 失败会恢复同一 `VideoItem` 引用及 active/detached/tagId 索引。

Phase 3H-1 把继续观看清理/撤销迁入 `LibraryContinueWatchingCommandExecutor`。
executor 捕获精确播放快照、注入批量 Repository 提交，并在失败时恢复或重新清空同一
`VideoItem`；确认、10 秒撤销入口、SnackBar 与刷新仍在 presentation。最近播放临时
多选复用 `LibrarySelectionController`，只保存 stable videoId，不再绑定 mutable path。

Phase 3H-2 把媒体库、继续观看、收藏和本地目录的来源模式、当前路径与返回栈迁入
`LibrarySourceNavigationController`。页面注入现有路径规范化/比较策略，因此 controller
不依赖 Flutter、`dart:io Platform`、Store、筛选服务或媒体对象。标签/搜索切回普通媒体库
仍保留本地历史，主媒体库/最近播放/收藏/root 入口仍按原规则结束或重建本地浏览会话；
页面继续拥有筛选清理、选择清理、Route、动画和播放队列绑定。

Phase 4A 将播放器来源队列、二级标签子集、正在播放项与选中项迁入纯 Dart 的
`PlayerSessionController`。controller 必须同时接收媒体库已接受队列的 stable-ID 有序
快照，并拒绝重复 ID 或对象顺序不一致；对外只暴露不可修改视图，初始化、切换和删除
均按 `videoId` 定位，不依赖 mutable path。二级标签匹配规则由页面注入，空子集只能回退
同一来源队列，不能查询 Store。`PlayerPage` 继续唯一拥有 `PlayerService`、backend open、
texture/native window、计时器、全屏、Route 与 Widget 生命周期。

Phase 4B 使用 `revision + videoId + path` 不可变快照表达 latest-only 打开意图。
`PlayerOpenRequestController` 只接受当前代次的成功或安全错误，更新选择、missing 前置
拒绝和页面取消都会使旧 Future 失效。`PlayerBackendEventBridge` 集中持有 completed、
error、position、playing 四类 Stream 订阅，并在 backend stop/dispose 前幂等取消；
页面继续解释 EOF、进度节流、错误面板与播放图标。继续观看与恢复位置纯函数迁入
player domain，媒体库不再反向导入播放器 presentation。

Phase 4C-1 将主控制条显隐、设置锁定、控制区悬停与短时快捷键反馈迁入泛型纯 Dart
`PlayerInteractionStateController<TIcon>`。controller 唯一持有控制条/反馈两只 Timer，
更新会取消旧 Timer，dispose 后拒绝迟到回调；页面只注入无上下文刷新回调和 `IconData`。
Focus、键位解析、Overlay、全屏队列 Timer、窗口状态与播放器资源仍留在原 owner。

Phase 4C-2 使用纯 Dart `PlayerShortcutGateController` 统一嵌套暂停深度、标签编辑门禁、
命令处理资格与焦点恢复资格。页面继续采集 Focus/Route/Overlay/Keyboard 环境事实并执行
具体命令，controller 不依赖 Flutter。Phase 4C 完成。

Phase 4D 使用纯 Dart `PlayerFullscreenLifecycleController` 统一当前 Route 的全屏状态、
过渡状态、会话恢复与退出窗口命令顺序。页面只注入 `endOfFrame`、`window_manager`
命令和无上下文刷新回调；controller 不持有 `BuildContext`、Route、PlayerBackend 或窗口
句柄。帧边界后会重新检查 Route 是否仍挂载，避免迟到命令污染下一次会话全屏偏好。

`PlayerResourceLifecycleCoordinator` 是 Texture listener 与 PlayerService 下游原生资源
释放的唯一协调 owner。释放顺序固定为 listener 解绑、backend event bridge 取消、stop、
dispose、released；stop/release 均幂等共享 Future，dispose 抛错仍等待 released 并发送
媒体库 Route 完成信号。PlayerService 继续唯一持有具体 PlayerBackend，后端继续唯一持有
Texture、NativePlayer、D3D11 和 child HWND，页面不取得任何原生句柄。

Phase 4E 将 `PlaybackDiagnosticsSnapshot` 迁入 player domain，并把诊断弹窗依赖收窄为
播放状态流与只读采样回调。弹窗继续唯一拥有刷新 Timer、播放订阅、连续样本比较和
dispose；它不再导入 `player_page.dart` 或持有 `PlayerPageState`/PlayerService。
页面仍用同一当前播放器实例构建匿名快照，不创建第二个 Player，也不改变诊断入口、
详细指标、复制隐私边界或弹层 airspace。Phase 4 播放器 MVVM 迁移完成。

Phase 5 将媒体库 Repository 使用面拆为只读 `LibraryQueryRepository` 与写入/运行时
`LibraryCommandRepository`。`LibraryApplicationFacade` 分别持有两个能力端口，组合根
仍把同一个 `LibraryStore` 实例注入两侧，因此 SQLite 连接、内存索引和事务 owner 没有
复制。标签维护、扫描、root、删除和 relink 的跨表 batch 保持为粗粒度命令；事务亲和度
审计确认当前不满足物理拆分收益门槛，证据记录于
`docs/architecture/LIBRARY_REPOSITORY_AFFINITY_2026_07_29.md`。

Phase 6 将 16 个单元测试和 9 个 integration test 从万能 `src/app.dart` 迁到实际所属
模块，并在消费者归零后删除该兼容导出面。架构合同现在同时扫描 production、test 与
integration_test，禁止重新引入 barrel；应用入口、bootstrap 和页面挂载保持不变。
Phase 0—6 的最终结构、完成证据与后续治理原则见
`docs/architecture/ARCHITECTURE_COMPLETION_2026_07_29.md`。

后续代码瘦身采用 Effective Dart、Flutter 职责分离和 Google 小变更原则，并叠加项目
本地 presentation 行数门禁。200 行以内是新增页面/组件最佳实践，201—500 行进入关注
区，超过 500 行必须登记只降不升的历史预算，超过 1000 行属于强制重构对象且禁止新增。
这些数值不是外部规范宣称的通用文件标准；行数只用于发现风险，最终仍由职责、单向依赖、
测试和页面可达性判断是否真正解耦。完整来源和执行门禁见
`docs/architecture/CODE_DEVELOPMENT_STANDARDS_2026_07_29.md`。

首批把最近播放与标签编辑从 `library_widgets.dart` 拆为独立叶节点，聚合文件从 4577 行
降到 3819 行，并移除其对播放设置、播放进度、缩略图和视频结果组件的无关依赖；页面仍
通过原回调绑定，不改变筛选、队列或用户数据。

第二批把侧栏通用条目、左右面板转场和结果视图切换器迁为 237/52/221 行独立叶节点，
`library_widgets.dart` 继续从 3819 行降到 3348 行。转场和切换器继续由原
`AnimatedSwitcher`、页面状态 owner 与 `ValueKey` 驱动；侧栏条目只转发导航与移除
意图，不取得筛选、目录或用户数据所有权。所有超过 1000 行的 presentation 文件已进入
有序强制治理清单，当前顺序为媒体库聚合 Widget、媒体库页面、播放器页面、视频结果、
播放器队列侧栏、标签发现面板、标签管理页和 missing/relink 页面。

第三批把 sidebar 容器、折叠轨道、品牌区和桌面拖拽滚动行为迁为
418/213/121/16 行独立组件，并把 top bar 搜索输入与筛选状态区迁为 241/464 行组件；
`library_widgets.dart` 从 3348 行降到 1917 行。所有新文件低于 500 行，搜索继续使用
同一 `TextEditingController` 链，筛选状态和回调仍由页面 owner 注入。

`library_page.dart` 治理同步启动：播放解码器/渲染器下拉组件迁入
`features/settings/presentation` 的 367 行叶节点，页面从 5747 行降到 5391 行。
确认、取消、持久化与撤销路径保持原状；页面、Widget 与 integration test 改为直接导入
具体组件，不新增 presentation barrel。

第四批继续沿设置 presentation 一致性边界拆分：原始码流缓存卡、播放画质/流畅度面板、
删除文件设置和缓存失败状态/测试容器迁为 47/371/165/158 行叶节点，
`library_page.dart` 的只降不升预算从 5391 行收紧到 4686 行。叶节点只接收不可变设置
快照、布尔状态和回调，不持有 `PlaybackSettingsController`、缓存维护命令、Store、
筛选、扫描或播放队列；二级页导航、持久化、失败补偿和真实删除仍由原 owner 管理。

第五批把“播放与解码”主卡和播放器交互设置迁为 98/168 行展示叶节点，
`library_page.dart` 的只降不升预算继续从 4686 行收紧到 4487 行。叶节点只接收
`PlaybackSettings` 快照、快捷键/冲突只读映射和回调；恢复策略、渲染器/解码器确认与
撤销继续复用原组件，快捷键冲突校验、设置持久化、controller、全屏队列命令和 section
返回仍由页面 owner 管理。

第六批把设置 Route 外壳和缓存诊断卡装配迁为 82/69 行展示叶节点，
`library_page.dart` 的只降不升预算从 4487 行收紧到 4443 行。外壳只消费首页状态、
标题、刷新显隐、导航回调和 child；缓存卡只消费 loading/error/stats/busy 快照与动作
回调。section 状态、系统返回意图处理结果、缓存 controller、维护命令、Repository
写入和统计刷新生命周期仍由页面 owner 管理。

第七批把标签展示/目录发现 helper、批量选择工具栏、顶栏排序与附件控件以及 focused
测试 harness 从 `library_widgets.dart` 迁为 157/153/120/56/90/39/171/128/108 行
独立叶子，聚合文件从 1917 行降到 962 行并退出 1000 行强制重构清单。顶栏仍由原
`ReferenceTopBar` 编排，稳定 `TextField`、筛选状态、排序回调、批量选择和全部 Key
保持原调用链。随后把添加标签与清空进度/解除目录确认迁为 126/74 行对话框叶子，
`library_page.dart` 预算从 4443 行收紧到 4293 行；叶子只返回用户意图，创建标签、
收藏、移除目录和清理进度仍由页面命令 owner 执行。

SQLite schema、`FilterQuery` / `TagQueryService`、stable identity、filtered queue、
PlayerBackend、缩略图/媒体队列和用户数据均未改变。

## Windows 候选后端同法 A/B 与缺失文件边界

`Architecture Baseline 0.5.100` 保持 media-kit 为正式播放内核。fvp 只能在隔离
Windows Release harness 中消费应用提供的有序媒体清单；它不得用自身 playlist
重建、排序或持久化 filtered queue，也不得在没有重复实测证据时进入组合根。

候选后端比较必须固定同一机器、匿名样本、跳转顺序、首帧判定和进程采集器，并分别记录
截图首帧与后端结构化首帧。整帧截图包含后端编码和 Dart 解码成本，不能替代 Texture/
compositor presentation 证据；CPU/GPU 均值若包含不同释放等待，也不能单独决定后端。

`MediaKitPlayerBackend.openPath` 在启动当前打开代次后、进入 libmpv 前检查本地文件
是否存在。缺失文件立即以路径无关 `missing_file` 完成该代次失败并向安全错误流广播；
不保存或转发本机路径。存在但破损的文件仍由 libmpv 识别和分类，避免平台边界根据扩展名
猜测格式。该快速失败不改变 `PlayerBackend` contract、latest-request、filtered queue
或释放所有权。

## 同实例 libmpv 滤镜事务边界

`Architecture Baseline 0.5.99` 在 `PlayerService` 内增加
`PlayerFilterTransactionBoundary`。滤镜协调器仍只持有当前 Route 的
`PlayerRuntimeAccess`；事务通过现有 `PlayerBackend` 访问同一个 MediaKit
`Player` / `NativePlayer`，禁止为写前快照、读回验证、回滚或诊断创建第二实例。

事务只覆盖完整视频滤镜快照：写入前读取旧属性，按既有 Map 顺序批量提交，写入后逐项
读回。比较遵守 libmpv 规范化语义：数值允许等价的小数格式，`lavfi=[graph]` 与
`lavfi=graph=%N%graph` 视为同一滤镜图，但滤镜节点和参数内容不能模糊匹配。

读回不一致时先关闭 `deband`，再恢复旧参数和 `vf`，最后恢复旧主开关并再次验证。
诊断快照只保存事务序号、受控用途标签、属性名、结果和耗时，不保存属性值，避免未来
本地滤镜资源路径进入日志。原有自适应画质、暗场增强、NVIDIA 互斥和压力回滚策略不变。

## MediaKit 路径无关播放遥测边界

`Architecture Baseline 0.5.98` 在既有 `PlayerBackend` 后增加可选的
`PlayerBackendTelemetryBoundary`。页面与诊断层只消费结构化快照，不读取媒体路径，
也不要求测试替身或其他后端立即实现这组能力。

首帧指标按“媒体打开代次”隔离：MediaKit Texture 就绪后，优先使用同一个
`NativePlayer` 的 `estimated-frame-number` 变化；平台未提供该事件时，可由同代次的
视频参数与播放位置更新共同确认，最后才使用带明确证据名称的超时回退。旧代次事件
不能完成新媒体的首帧计时。

错误事件只保存分类代码、时间和所属打开代次，不写入文件路径或底层原始消息；失败率
按每个打开代次最多记一次失败计算。`hwdec-current` 与 `video-codec` 通过同一个
`NativePlayer` 持续观察，诊断显示实际解码结果而非配置意图。

释放阶段按“事件订阅/属性观察者 → MediaKit Player → Windows 原生释放宽限 →
遥测流”串行执行，并记录各阶段耗时。该边界不创建第二个 `Player`、`NativePlayer`、
`mpv_handle`、Texture 或解码链，也不改变 filtered queue、SQLite、标签过滤和缓存队列。

## MediaKit Texture 与同实例 libmpv 增强边界

`Architecture Baseline 0.5.97` 将生产播放链固定为：

```text
Flutter PlayerPage
  -> PlayerService（PlayerFacade）
  -> MediaKitPlayerBackend
     -> 常规命令：media_kit Player API
     -> 高级画质：同一个 NativePlayer 属性边界
  -> media_kit_video Texture
  -> libmpv
```

增强配置不能创建第二个 `Player`、`mpv_handle`、Texture 或解码链。media_kit 继续
拥有播放器初始化、事件分发、同步、VideoController 和 Texture 生命周期；
`MediaKitPlayerBackend` 只在同实例上使用公开的类型化 `NativePlayer`
`setProperty/getProperty`。批量属性的第一项等待 Player 与 VideoController 就绪，
后续项复用已确认会话，但单个可选属性失败仍不能阻断完整回滚快照。

`PlayerRendererPreference.windowsLibmpv` 保留原持久化名称以兼容用户设置，产品含义
改为 `MediaKit + libmpv 增强`。该配置与 `mediaKit` 兼容配置都使用 MediaKit
Texture，因此 macOS/Linux 也无需实现第二套原生播放器即可使用标准 libmpv 属性。
Windows 自研 `WindowsNativePlayerBackend` 只允许显式
`LOCAL_TAG_PLAYER_BACKEND=windows-native-mpv/windows-native-hwnd` QA 覆盖；
原生 D3D11 纹理注入、NVIDIA VSR/HDR 等 media_kit 未暴露的能力仍留在该隔离边界。

自研 MPV QA 桥接参考 media_kit 的事件模型：`mpv_set_wakeup_callback` 只唤醒唯一
工作线程，状态由 `mpv_observe_property` 与 `MPV_EVENT_PROPERTY_CHANGE` 合并；
单批最多消费 128 个事件并主动让出命令/渲染。它不再固定每 50ms 读取全部属性，
但这项优化不改变其 QA-only 身份。

## Windows MPV Texture 描述符与渲染锁边界

`Architecture Baseline 0.5.96` 将原生 Texture 的同步范围拆为两个责任互斥量：
`surface_mutex_` 只串行 MPV 绘制、共享纹理复制、插件处理和表面重建；
`surface_descriptor_mutex_` 只保护 DXGI 共享句柄、尺寸 `SetSize` 与销毁。Flutter
raster 回调只能获取后者，不能等待每一帧的 MPV/ANGLE/D3D11 工作。

描述符锁必须始终在 surface 锁之后获取；Texture 回调只能单独获取描述符锁，
销毁与 resize 使用相同顺序，避免锁反转。此优化不改变 `PlayerBackend` contract、
硬解策略、滤镜、filtered queue 或视频比例，只消除平台边界中的错误锁粒度。

seek 仍由 `PlayerPage` 的 latest-target 协调器拥有：拖动组件只在结束时提交目标，
键盘连按在短尾随窗口内累计，后端不接收已经被新输入替代的位置。MediaKit 继续复用
同一页面语义，但不消费 Windows Texture 锁。

## Windows MPV 默认容器合成边界

`Architecture Baseline 0.5.95` 把 Windows MPV 的产品默认表面从 child HWND 改为
libmpv Flutter Texture。`PlayerService` 和 `PlayerBackend` contract 不变；
`PlayerPage` 始终只挂载一个播放器容器，由组合根在容器内部选择 MediaKit Texture
或 MPV Texture。播放列表、控制条、设置与右键菜单继续属于同一 Flutter 合成树，
无需按浮层坐标裁剪视频窗口。

MPV Texture 不能直接消费非 copy D3D11VA 帧，因此
`WindowsNativePlayerBackend(mode: 'mpv')` 必须在平台边界把 `hwdec=d3d11va`
映射为 `hwdec=d3d11va-copy`。该映射只约束 Texture 表面；显式
`windows-native-hwnd` QA 覆盖继续请求 `d3d11va`，用于隔离验证 NVIDIA VSR/HDR
和原生 D3D11 链。产品设置与诊断必须据实际 selection 展示能力，不能把 QA-only
HWND 的 NVIDIA 结论套用到默认 Texture。

全屏右侧队列与视频是同级布局，展开时视频容器缩小，隐藏时恢复；底部控制条是覆盖视频的
Flutter 浮层。已授权删除全屏顶部队列语境条，不改变 filtered queue、当前 index、
队列导航、设置入口、右键菜单动作或返回路径。

## MPV child HWND 动态控制区与稳定 region

`Architecture Baseline 0.5.94` 曾保持 Windows MPV child HWND 与 Flutter 视频占位区
同尺寸。顶部全屏语境、底部控制条和弹层不再通过改变 HWND 外框实现，而由 runner
在单个 window region 中统一扣除。控制条可见时底部让出 128 逻辑像素，隐藏时只让出
3 像素进度条；这两个值参与平台侧同步缓存，状态变化必须立即更新 region。

runner 必须先保存本轮 surface 左上角、尺寸与 view 尺寸，再移动窗口和计算 region，
避免初次布局使用上一轮几何。Flutter 弹层仍只通过 `PlayerOverlaySurfaceBoundary`
发送逻辑矩形；右键菜单在 Route 挂载后测量真实菜单项并有限重试。MediaKit 不消费
这些 Windows 参数，跨平台 `PlayerBackend` 仅暴露语义化的控制区预留状态。该实现
现在只由显式 `windows-native-hwnd` QA 覆盖使用，不再是产品默认 MPV 表面。

## MPV child HWND 弹层与视口边界

`Architecture Baseline 0.5.93` 把 child HWND airspace 从“弹层出现时隐藏整个
视频窗口”收敛为矩形级 region 裁剪。`PlayerPage` 只向
`PlayerOverlaySurfaceBoundary` 发送 Flutter 逻辑弹层矩形和 view 尺寸；
`WindowsNativePlayerBackend` 负责平台通道序列化，runner 再按真实父 HWND
客户区换算物理坐标，并使用 `SetWindowRgn(..., RGN_DIFF)` 从外层视频宿主中
减去覆盖矩形。libmpv 的内部 D3D11 窗口、解码和播放时钟不暂停，矩形外继续
实时显示；未知尺寸的模态弹窗仍可要求完整隐藏。嵌套弹层在页面侧按栈恢复上一层
策略，具体 HWND/region 不泄漏到业务层。

普通窗口的标题栏位于视频容器之外，因此不再固定预留全屏顶部 64 逻辑像素；
只有 `_isWindowFullscreen` 为 true 时通过 `reserveTopControlArea` 请求该
airspace。底部 128 像素继续保护 Flutter 控制条。此修改不改变自动/4:3/16:9/
铺满的比例语义，也不改变 MediaKit 表面、filtered queue、SQLite、标签、缓存
队列或用户数据。完整证据见
`docs/qa/mpv_hwnd_overlay_region_20260728.md`。

## 播放器后端稳定性门禁

`PlayerService` 继续是页面唯一可见的播放应用边界；稳定性矩阵不直接把媒体路径
交给具体后端，而是通过 `PlayerPage` 的正式全屏和 latest-request 队列链驱动。
测试只读取匿名 `videoId` 快照，以确认 filtered source queue、当前 index、最终
打开项和后端生命周期一致。

Windows 的 MediaKit 与原生 MPV 必须分别运行同一组全屏、DPI、快速切换和长播
场景并分开出报告。模拟 Flutter metrics 只证明布局/表面重算，真实跨显示器 DPI
仍是独立发布门禁。

macOS/Linux 当前没有第二套原生 MPV `PlayerBackend`，因此不能复用 Windows
child HWND 或自研 Texture。Baseline 0.5.97 后，标准 libmpv 高级属性通过各平台
media_kit 已拥有的同实例 `NativePlayer` 开放；只有原生纹理注入、NVIDIA 等超出
media_kit 属性边界的能力，才需要各平台另建并通过独立稳定性矩阵。

`Architecture Baseline 0.5.92` 把播放器后端的最终选择权交给用户，同时保持
平台能力边界诚实。设置页只提供 `MediaKit 兼容渲染` 与 `MPV 原生渲染`：
Windows 在选择 MPV 且硬解开启时由组合根创建原生 child HWND / D3D11 后端，
选择 MediaKit 时明确创建兼容后端；非 Windows 或关闭硬解时仍安全回退
MediaKit，因为对应原生实现尚不存在。旧 `automatic` 仅用于设置迁移，不再
显示或参与新持久化。页面与业务层仍只传递 `PlayerRendererPreference`，
`PlayerService` 继续消费抽象 `PlayerBackend`，没有取得平台纹理或自行构造
后端。MPV 专属的 GPU 高质量缩放只在对应后端显示；镜像和压缩画质增强保留在
两种后端。

NVIDIA VSR/HDR 两个手动开关从播放器齿轮删除，改为 MPV 会话进入媒体后的自动
策略。原生桥固定回传 `video-params/w` / `video-params/h`，Dart 同时检查活动
NVIDIA adapter、原生 D3D11 请求能力、源/输出尺寸、HDR 活动信号和 10-bit
输出，再原子请求 VSR/TrueHDR；未知条件继续保守关闭，性能回滚和 CPU 滤镜
互斥恢复保持有效。三类 650 kbps 1080P 实测均为 VSR/HDR 驱动 `active`、
0 总掉帧、0 音视频停滞。画质报告显式记录 `playerBackend` 与
`rendererPreference`，后续门禁不混算两种后端。filtered queue、SQLite、
标签、缓存队列和用户数据不变。完整证据见
`docs/qa/player_backend_selection_nvidia_auto_20260728.md`。

`Architecture Baseline 0.5.91` 把 NVIDIA VSR/TrueHDR 与现有 CPU 画质滤镜的
互斥从“禁止点击”改为会话级自动让路。设置层只在固定 mpv、Windows 原生
`gpu-next/D3D11`、`d3d11va` 和源信号等不可恢复门禁失败时禁用；若冲突仅来自
压缩画质增强或暗场增强，开启 NVIDIA 时暂时释放 CPU `lavfi`，不改持久偏好，
关闭、驱动拒绝或性能回滚后归还滤镜所有权并重新采样。应用仍不读取或修改
NVIDIA App 全局设置，也不把 NVIDIA App 的“未激活”当成运行时真值；实际状态
由固定 mpv 日志归一化出的 VSR/HDR `active` 分别确认。真人面部、动画渐变、
暗场三类低码率 1080P 联合门禁均为驱动 active、0 总掉帧、0 音视频停滞、无
回滚。默认仍关闭且仅会话保存；默认 MediaKit、其他平台、插件 ABI v1、
filtered queue、SQLite、标签、缓存队列和用户数据不变。完整证据见
`docs/qa/nvidia_auto_activation_20260728.md`。

`Architecture Baseline 0.5.90` 修复 Windows Debug 交付目录的启动门禁。根因
不是 VSR/HDR 或生产启动代码：Windows integration test 会复用
`build/windows/x64/runner/Debug` 并写入测试入口；若它是最后一条命令，双击
`local_tag_player.exe` 时进程会等待测试驱动，表现为存活但没有主窗口。新增
`tool/verify_windows_debug_package.ps1`，固定先重新构建正式 `main.dart`，再按
精确 PID 启动 exe，并要求限定时间内出现非零 `MainWindowHandle`。默认后端、
PlayerService、filtered queue、SQLite、标签、缓存队列和用户数据均不改变。

`Architecture Baseline 0.5.89` 收敛 Windows NVIDIA 发布边界：固定 mpv
`v0.41.0-908-g48e6c35c0` 的 RTX 视频超分与 RTX Video HDR 作为当前可交付
能力，产品文案不再标记“实验”，但仍默认关闭、仅会话保存，并受原生
`gpu-next/D3D11`、非 copy `d3d11va`、源信号、滤镜互斥、掉帧熔断和回滚保护。
修正 A/B 工具后，真人面部、动画渐变、暗场在固定第 12 秒的同尺寸最终 Windows
表面完成六组肉眼对比，20 秒两侧均为 0 总掉帧和 0 音视频停滞。VSR 对偏软真人
和动画边缘有收益，但可能放大面部压缩纹理，暗场收益很小，因此保持默认关闭、
按低码率放大场景启用。NVOFA 插帧降级为独立长期研究，不阻塞发布；patched
libmpv D3D11 hwframe 钩子与独立 FFmpeg 后端不再由原任务自动继续。默认
MediaKit、其他平台、插件 ABI v1、filtered queue、SQLite、标签、缓存队列和
用户数据不变。完整证据见 `docs/qa/nvidia_vsr_daily_ab_20260728.md`。

`Architecture Baseline 0.5.88` 校正 Windows D3D11VA 的零拷贝边界，并把偶发
child HWND 崩溃转成可重复生命周期门禁。8 次独立 runner 与 12 次同进程
`create/open/occlude/dispose` 均无 Application Error、孤儿进程或输出掉帧；
原始 `0xc0000005` 位于运行时生成代码且栈已损坏，不能归因到原生桥，因此不凭
猜测改生产线程次序。新增 QA-only `d3d11va-zero-copy=yes` 请求与固定读回，
默认产品仍为 `no`；12 轮直接采样会话及交替压缩 `vf` 均可播放，但后续 NVOFA
真实帧性能前置门禁连续产生 140/138 掉帧，六组 A/B 被阻止。公开 libmpv
render API 只有 OpenGL/软件输出，VapourSynth R4 只有软件平面，现有单帧 ABI
也没有时间戳和双帧所有权；本节当时把隔离 mpv 的 D3D11 hwframe 内部钩子列为
下一原型，该路线现已由 0.5.89 降级为独立长期研究，不再自动继续。默认
MediaKit、产品开关、
插件 ABI v1、filtered queue、SQLite、标签、缓存队列和用户数据不变。完整证据
见 `docs/qa/windows_hwnd_lifecycle_zero_copy_boundary_20260728.md`。

`Architecture Baseline 0.5.87` 在 QA-only NVOFA 原型内增加三段同 LUID
D3D11 Compute：第一段以双向 cost 和 forward-backward residual 生成稠密 flow，
对低置信度 flow-grid 单元从局部一致邻域补全；第二段保持 85% 等权的保守中点
warp，并把低 flow 置信度、两侧主导差和光度分歧合成为遮挡有效性；第三段只对
低有效性像素从 4px 邻域执行图像域 hole filling。该结构对应 NVIDIA 公布的
“双向校验 → 无效矢量补全 → 插值 → 图像域补洞”阶段，但实现为仓库自己的开放
近似，不使用或分发 FRUC SDK。确定性探针锁定 128/90/117 旧基线、矢量补洞 90
和图像补洞 201。三类自然片源六组与五类连续压力片十组均为 24→48fps、0 总
掉帧、0 音视频停滞及同一 LUID `00000000:00017093`；视觉复核未发现新增脸部
撕裂、动画暗边、暗场污染、细线断裂、字幕漂移或跨切镜混合。一次 off 组
child-HWND `0xc0000005` 启动崩溃虽未复现，仍作为产品启用 blocker。整链继续
包含 VapourSynth 软件帧、CUDA 光流回读、D3D11 上传和最终读回，因此不是
non-copy FRUC。产品入口、默认后端、插件 ABI v1、filtered queue、SQLite、
标签、缓存队列与用户数据不变。

`Architecture Baseline 0.5.86` 在同 LUID NVOFA + D3D11 Compute 原型中增加
硬件 cost 与前后向一致性保护，但明确拒绝把“置信度加权”冒充完整遮挡处理。
NVOFA 的 A→B/B→A 两次 execute 都请求 `UINT8` cost；shader 以
forward-backward residual 和 cost 判断两侧可靠性。真实动画片源证明强权重和
二次反推光流会在显露边缘产生暗色拖影，因此最终保留已验证的中点取样，并让
等权合成占 85%，只允许 42.5%–57.5% 的保守修正。确定性 Compute 探针锁定
零流等权、正确运动方向和极端不可靠单侧三种结果；三类 1080P 六组 A/B 仍为
24→48fps、0 总掉帧、0 音视频停滞和精确 LUID `00000000:00017093`。完整
遮挡 mask、矢量补洞和图像域显露区域补洞仍缺失，因此 QA 插件不安装、不进入
bundle，产品入口和默认后端不变。filtered queue、插件 ABI v1、SQLite、标签、
缓存队列与用户数据不变。

`Architecture Baseline 0.5.85` 把 NVOFA 原型的物理 GPU 身份与中点像素合成
收敛到 Windows 平台边界。child HWND 通过 DXGI 1.6 选择唯一 NVIDIA 适配器，
用名称设置 mpv `d3d11-adapter`，再用 Windows LUID 精确匹配 CUDA/NVOFA 与
D3D11 Compute 设备；同名多卡或任一匹配失败时拒绝启用。中点帧逐像素双线性
采样与融合已由固定 `cs_5_0` Compute Shader 执行，GPU 阶段失败会撤销整条实验
滤镜，没有 CPU 隐式回退。RTX 4070 SUPER 上三类 1080P 直接门禁和六组 20 秒
A/B 均得到 24→48fps、0 总掉帧、0 音视频停滞及同一 LUID
`00000000:00017093`。由于 VapourSynth 仍提供软件平面，CUDA luma 上传、光流
回读、D3D11 输入上传和最终平面读回仍存在；这是“同 GPU NVOFA + D3D11
compute warp”，不是全程 non-copy。QA 插件无 install 且不进入 bundle；默认
MediaKit、插件 ABI v1、filtered queue、SQLite、标签、缓存队列和用户数据不变。

`Architecture Baseline 0.5.84` 在既有
`PlayerMotionInterpolationBoundary` 后完成首条真实 NVOFA 2× 中间帧原型，但
继续隔离在本机 QA 边界。显式 CMake 目标动态加载 System32 的 CUDA/NVOFA 驱动，
分别执行前向与后向 Optical Flow；VapourSynth R78 插件用双向 0.5 warp 合成奇数
帧，偶数帧保留源帧，切场阈值禁止跨镜头混合。脚本通过 `user-data` 接收唯一绝对
插件路径，mpv 0.40 所需 output index 0 被显式注册；输出帧率有理数先约分，避免
非法 `VSVideoInfo`。单线程 1080P 初测 7 秒仅推进 3.52 秒并产生 97 个输出掉帧，
因此没有开放入口；按 16 行块并行后，真人、动画、暗场三类 650 kbps 1080P
off/on 六组均从 24fps 实测提升到 48fps，20 秒长播两侧均为 0 总掉帧和 0 音视频
停滞，固定中间帧人工检查未见明显双影、撕裂或暗场污染。该链仍会把 mpv 帧交给
VapourSynth 软件表面、上传 luma 到 CUDA、回读光流并在 CPU warp，不是
D3D11VA 非 copy 合成；插件、R78 与公开头文件均不进入 bundle，UI 也不开放。
默认 MediaKit、插件 ABI v1、filtered queue、SQLite、标签、缓存队列和用户数据
不变。

`Architecture Baseline 0.5.83` 在既有 Windows 原生 child HWND 边界内接入固定
mpv 提交自带的 NVIDIA RTX Video HDR 驱动扩展，不下载或分发 RTX Video SDK。
`PlayerNvidiaVideoEnhancementCapability` 现在分别建模 VSR 与 TrueHDR，并要求
固定实现版本、原生 `gpu-next/D3D11`、非 copy `d3d11va`、明确 SDR 源和无 CPU
滤镜冲突。页面只提交 VSR/HDR 两个布尔意图；应用层原子合成唯一
`d3d11vpp`，联合开启时移除 VSR 单独模式的 `format=nv12`，让 mpv 自动选择
TrueHDR 所需 10-bit 输出。原生桥只把固定日志归一化为独立的
`native-nvidia-vsr-state` / `native-nvidia-hdr-state`，并返回源 primaries/gamma；
失败恢复此前已确认组合，播放压力则同时回滚当前 NVIDIA 会话。真人面部、动画
渐变和暗场六组 20 秒 A/B 均得到驱动 `active`、PQ/BT.2020 10-bit HDR 活动信号、
0 总掉帧和 0 音视频停滞。默认 MediaKit、插件 ABI v1、filtered queue、SQLite、
标签、缓存队列和用户数据不变。

`Architecture Baseline 0.5.82` 将 NVIDIA Optical Flow 门禁从“驱动导出存在”
推进到“硬件会话实际执行”。隔离 QA 目标按固定提交和 SHA-256 临时取得 NVIDIA
BSD-3-Clause 公开的 NVOFA CUDA 2.0 头文件，只从 System32 动态加载
`nvcuda.dll` 与 `nvofapi64.dll`，在 RTX 4070 SUPER 上完成 CUDA context、
NVOFA session、三块 GPU buffer、两帧上传、`nvOFExecute`、同步与 S10.5 光流
回读。Debug/Release 都由驱动 API 5.0 接受，并产生非零水平位移向量。头文件、
探针和可执行文件只留在被忽略的构建目录；目标是 `EXCLUDE_FROM_ALL`，没有
install 规则，也不进入正式 runner 或 Flutter bundle。该证据证明本机 NVOFA
硬件光流可执行，但不等于 FRUC 已生成中间帧，更不等于 RTX Video SDK 的 VSR、
Artifact Reduction 或 SDR→HDR 已接入；因此产品能力快照、设置入口与现有插件
ABI v1 均不冒进修改。默认后端、filtered queue、SQLite、标签、缓存队列和用户
数据不变。

`Architecture Baseline 0.5.81` 将 Windows 插帧路线从“宿主结构可用”推进到
“官方 VapourSynth R78 真实帧链可用”，并增加 NVIDIA Optical Flow 驱动能力
门禁。R78 只安装在被忽略的本机 QA 目录，不修改 PATH/注册表，也不进入应用包；
固定 libmpv 经真实 H.264 帧验证了滤镜送帧、精确 seek、同进程 reload 和透传
不会被误报为插帧 active。Windows runner 仅从 System32 安全加载
`nvofapi64.dll`，调用官方公开的最大 API 版本入口并检查 D3D11 导出，再通过
`PlayerMotionInterpolationCapability` 返回类型化只读快照。本机 API 5.0 与
D3D11 导出可用只证明驱动侧 NVOFA 入口存在，不证明 FRUC SDK/插件已安装，也不
证明 RTX Video SDK 的 VSR、伪影消除或 HDR 已接入。应用仍不下载、不提交、不
分发 NVIDIA SDK 文件；下一阶段必须由用户接受 NVIDIA 许可并提供本机 SDK 后，
才构建不分发厂商文件的 FRUC 与 RTX Video 1.1 插件。默认后端、现有插件 ABI、
filtered queue、SQLite、标签、缓存队列和用户数据不变。

`Architecture Baseline 0.5.80` 增加 Windows 本机运动补偿插帧边界，但不把外部
运行时或厂商文件伪装成应用内置能力。`PlayerService` 只暴露
`PlayerMotionInterpolationBoundary` 的强类型查询与启停结果；MediaKit 和其它
平台返回明确 unsupported。Windows libmpv runner 仅在
`LOCAL_TAG_PLAYER_VAPOURSYNTH_RUNTIME_DIR` 与
`LOCAL_TAG_PLAYER_MOTION_INTERPOLATION_SCRIPT_PATH` 都是有效绝对路径时预加载
`VSScript.dll`，校验 `getVSScriptAPI` 后才允许请求。滤镜不再拼接 Windows 路径
字符串，而是通过 `MPV_FORMAT_NODE` 读取、保留并重写完整 `vf`，只拥有
`ltp-motion-interpolation` 标签；压缩增强重写滤镜图后自动恢复该条目。运行时
错误立即移除标签并增加回退计数，只有实际滤镜输出帧率至少达到源帧率 1.5 倍才
标记 active。该边界不分发 VapourSynth、Python、NVIDIA Optical Flow SDK 或
模型；现有单帧 D3D11 插件 ABI v1 保持不变，因为它没有时间戳与多帧输出所有权，
不能用于补帧。filtered queue、SQLite、标签、缓存队列和用户数据不变。

`Architecture Baseline 0.5.79` 将普通显示同步插值纳入播放器应用层边界：
`PlaybackSettings` 只保存 `off/displayInterpolation` 类型化意图，
`PlayerService.applySmoothMotion` 统一转换为
`video-sync=display-resample + tscale=oversample + interpolation=yes`，页面不再
直接拼接这三个 mpv 属性。配置只有在后端完整读回后才标记为已确认；逐帧运行态
另由 `display-sync-active` 展示。写入或读回失败、
缓冲、掉帧或音视频停滞时只回滚当前媒体，不改写用户全局选择。Windows 原生桥
新增固定字段读回，MediaKit 与非 Windows 继续通过同一 `PlayerRuntimeAccess`
安全失败语义工作。该能力是相邻原始帧的显示插值，不是 NVIDIA/RIFE AI 生成帧。
filtered queue、插件 ABI、SQLite、缓存队列和用户数据不变。

`Architecture Baseline 0.5.78` 把 Windows 原生 libmpv 从环境变量专用路径提升为
可持久化、可撤销的用户渲染器偏好。`PlaybackSettings` 只保存
`automatic/mediaKit/windowsLibmpv`；`PlayerPage` 将偏好随硬解配置交给
`PlayerServiceFactory`，具体平台解析由组合根的
`resolvePlayerBackendSelection` 完成。Windows 增强映射到已通过 NVIDIA A/B 的
child HWND/D3D11 后端；非 Windows、硬解关闭或旧/异常设置安全回退 MediaKit，
三个既有 QA 环境覆盖保持最高优先级。当前 Route 不热拆引擎，下次进入播放器
生效。filtered queue、插件 ABI、SQLite、缓存队列和用户数据不变。

`Architecture Baseline 0.5.77` 在 Windows 原生 child HWND 后端完成
`d3d11va → d3d11vpp scaling-mode=nvidia → gpu-next/D3D11`。原生层订阅
libmpv verbose 日志，但只匹配固定 NVIDIA 成功事件并向 Flutter 返回
`inactive/requested/active/rejected`，禁止原始日志和媒体路径越过平台边界。
`PlayerService` 继续拥有命令、状态、截图与回退；页面无法取得 mpv handle、D3D11
资源或临时截图路径。真人面部、动画渐变、暗场六组 20 秒 A/B 均由驱动确认
`active`，0 掉帧、0 音视频停滞且无回滚，因此原生 D3D11 会话的 NVIDIA
滤镜门禁开放。默认 Windows 后端仍为 MediaKit，filtered queue、插件 ABI、
SQLite、缓存队列和用户数据不变。

`Architecture Baseline 0.5.76` 在现有 `PlayerBackend` 下游增加应用层
`PlayerService`：Flutter 的 `LibraryPage` / `PlayerPage` 只接收
`PlayerServiceFactory`，组合根先选择 `MediaKitPlayerBackend` 或显式
`WindowsNativePlayerBackend`，再把具体实例封装进服务。画质协调器和诊断只依赖
更窄的 `PlayerRuntimeAccess`；GPU 活动设备、Compute 基线与 child HWND airspace
由服务代理，页面不再取得具体后端、MediaKit Player、VideoController、mpv handle、
D3D11 纹理或 HWND。filtered queue 仍由 `PlayerPlaybackController` 独立拥有，
默认 MediaKit、Windows 实验门禁、设置键、插件 ABI 与释放时序不变。

```text
Flutter PlayerPage
        |
   PlayerService
        |
   PlayerBackend
     /       \
MediaKit   Windows libmpv
               |
      GPU / HWND / D3D11 / 本机增强
```

`Architecture Baseline 0.5.75` 把 Windows 固定 libmpv 升级为
`v0.41.0-908-g48e6c35c0`，归档、SHA-256 与许可证均由 CMake 固定。显式
`windows-native-hwnd` 后端在 Dart 和 runner 两层锁定非 copy `d3d11va`，
避免通用 `auto-safe` 在会话初始化后覆盖实验目标。child HWND 使用命中透明且
不激活的窗口过程，把真实鼠标语义留给 Flutter；`PlayerOverlaySurfaceBoundary`
只负责在设置、上下文菜单和对话框期间隐藏/恢复原生表面，不改变共享
`PlayerBackend`。矩形同步把 device pixel ratio 纳入去重，跨 DPI 且逻辑尺寸
不变时仍要求 runner 依据父 HWND 客户区重算物理几何。普通窗口的弹层、全屏、
快速切换、Route 返回和退出已通过；当前只有单个 96 DPI 显示器，真实跨屏证据
缺失，因此三类片源六组 A/B 与默认后端切换均继续阻断。SQLite、标签查询、
filtered queue、缓存队列、插件 ABI 和用户数据不变。

`Architecture Baseline 0.5.74` 增加仅由
`LOCAL_TAG_PLAYER_BACKEND=windows-native-hwnd` 启用的 Windows 平台实验边界：
runner 在 Flutter view 下创建双层 child HWND，外层只负责几何和 airspace
裁剪，内层交给 libmpv `wid + gpu-next + d3d11 + d3d11va`。Flutter 仍通过既有
`PlayerBackend` 控制同一 filtered queue、当前 index、播放命令和返回状态，
没有把 HWND、mpv handle 或 D3D11 资源泄漏到页面。隔离 mpv 0.41 在真人面部、
动画渐变和暗场三类低码率 1080P 页面中均为非 copy `d3d11va`、0 Flutter
纹理复制、0 掉帧；当时固定 mpv 0.36 无法启动该输出链。真实窗口画面与队列边界已
正确，但物理鼠标齿轮/右键可达性尚未形成可靠证据，因此默认 Windows 后端继续
使用 MediaKit，当轮正式 bundle 也恢复固定 mpv 0.36。SQLite、标签查询、
filtered queue、缓存队列、插件 ABI 和用户数据均未改变。

`Architecture Baseline 0.5.73` 收纳播放器齿轮的低频画面设置，但不改变
`PlayerBackend` 或持久化：镜像、GPU 高质量缩放和压缩增强只从一级页迁移到
“更多播放设置”。MediaKit Windows 仍通过 `MPV_RENDER_API_TYPE_OPENGL` 与
Chromium 5359 ANGLE 输出 D3D11 共享纹理；在 render context 创建前显式选择
D3D11VA interop 对 mpv 0.36/0.41 均不能产生非 copy 硬件帧，实验补丁已撤回。
因此不运行后续 NVIDIA A/B，也不升级正式 mpv。下一条底层实验只能隔离验证新版
ANGLE interop 或重新评估 Windows 原生渲染边界；SQLite、filtered queue、缓存、
插件 ABI 和用户数据保持不变。

`Architecture Baseline 0.5.72` 隔离验证 mpv NVIDIA scaling-mode，而不把失败候选提升为正式依赖。新版独立 mpv 已证明 `d3d11va → d3d11vpp scaling-mode=nvidia → D3D11` 和驱动 RTX Super Resolution 日志成立；同一 DLL 进入 MediaKit 后却得到 `hwdec-current=no`，因此非 copy 门槛失败。NVIDIA D3D11 滤镜与现有 CPU `lavfi` 直接串联还会静默停用压缩滤镜，所以 `PlayerAdaptiveQualityEnhancer` 统一拥有完整 `vf` 快照，并把两类路径设为互斥；NVIDIA 请求需读回、复用掉帧熔断且只保存会话状态。正式包继续固定 mpv 0.36.0，`filterChainValidated=false`，未改 `PlayerBackend`、插件 ABI、SQLite、filtered queue、缓存或用户数据。

`Architecture Baseline 0.5.71` 在播放器齿轮增加内嵌 mpv NVIDIA scaling-mode 的只读实验门禁。Windows 固定的 mpv 0.36.0 实际 DLL 包含 `d3d11vpp`，但不包含 mpv 0.39.0 才加入的 `scaling-mode=nvidia`；能力服务优先读取 `mpv-version`，不可用时回退固定依赖版本。当前会话开关明确禁用，且把“mpv 解析器具备选项”与“D3D11 硬件帧、现有 `vf` 链和性能回滚完成接入”分开判定，所以替换新版 DLL 也不会产生假启用。未写 NVIDIA filter、未升级依赖、未改 `PlayerBackend` 或本机视频增强插件 ABI，也不把该驱动路径描述成 RTX Video SDK。

`Architecture Baseline 0.5.70` 在实验性 `WindowsNativePlayerBackend` 后增加 SDK 中立的本机视频增强 ABI v1。只有同时显式选择 `LOCAL_TAG_PLAYER_BACKEND=windows-native-mpv` 并提供绝对 `LOCAL_TAG_PLAYER_VIDEO_PLUGIN_PATH` 时，runner 才会加载可信本机 DLL；不扫描安装目录、不修改默认 MediaKit、不安装或分发探针/NVIDIA 文件。mpv 帧在原生工作线程从 ANGLE 内部纹理复制到同一设备的共享 D3D11 纹理，再调用插件；宿主先备份原帧，插件返回错误时恢复纹理、停用当前插件会话并继续原播放器。诊断通过既有只读属性展示插件状态、处理帧与回退数，不扩展 `PlayerBackend` contract。QA-only 往返探针和宿主自测均无 install 规则，后者已证明“无损往返”和“破坏输出后原帧恢复”。真实 RTX Video SDK、许可及发布隔离仍未进入产品。

`Architecture Baseline 0.5.69` 把既有 libmpv 入口明确命名为“GPU 高质量缩放（非 NVIDIA AI）”，不改变设置键、mpv 属性、`PlayerBackend` contract 或性能回滚。RTX Video SDK 只完成许可、D3D11 纹理接入和非 NVIDIA 回退评估：未来原型必须留在 Windows 原生平台边界、精确复用活动 D3D11 LUID，并在任何能力或运行失败时回到现有 libmpv 缩放。SDK 1.1 下载包 EULA、MIT 排除声明和目标代码再分发尚未完成发布核对，因此不下载、不提交、不分发 SDK。

`Architecture Baseline 0.5.68` 在不扩展 `PlayerBackend` contract 的前提下，把旧自动画质布尔配置升级为“关闭 / 自动 / 清晰增强”枚举。播放器页面仍通过既有 mpv 属性边界串行应用同一 `vf` 去块、`hqdn3d` 与 `unsharp` 图，并以 GPU renderer 的 `deband` 属性增加保守去色带；性能协调器拥有实际档位，掉帧、缓冲或停滞可覆盖用户请求并回滚。设置只表达意图，不承诺恢复源视频已丢失的细节；缩放后 GLSL 锐化在固定低码率 1080P A/B 后保持未启用。SQLite、标签查询、filtered queue、缓存队列和用户数据不变。

## 总览

`Architecture Baseline 0.5.67` 将 GitHub Release 更新边界扩展为可验证的 Windows 应用内安装：安装器先写入系统临时更新目录的 `.part` 文件，完整下载后流式校验 GitHub 资产 SHA-256，只有摘要匹配才原子改名并启动交互式安装器。设置新增关于页，版本信息和主动检查均消费 `AppUpdateService`，不直接访问平台 API。旧 Release 缺少摘要、非 Windows 平台或下载失败时保留发布页降级入口；SQLite、标签查询、filtered queue、PlayerBackend、缓存队列和用户数据不变。

`Architecture Baseline 0.5.66` 修正默认开启的无效记录清理语义：当前路径只要不存在，即使尚未由扫描写入 `isMissing`，也会从主库、标签关系和依赖备份中移除。该策略仍不调用 `FileSystemAdapter` 的删除或回收站能力，不删除任何磁盘文件或文件夹。

`Architecture Baseline 0.5.65` 将已验证的 `media_kit_video 2.0.1` Windows 隔离迁移纳入主线。固定 pub.dev 归档与 SHA256，继续在构建期替换 `video_output.cc`：GPU 与软件纹理回调捕获稳定 descriptor，销毁后返回空指针，所有权保持到 Flutter 注销纹理。Profile 基线与 FFmpeg 缩略图 A/B 只作为 QA 工具，不改变正式缩略图路径、PlayerBackend contract、filtered queue 或用户数据。

`Architecture Baseline 0.5.64` 在正式打包边界增加远程分支集成门禁。待打包提交必须等于 `origin/master` 当前提交；所有其它远程分支必须已经成为主线祖先或与主线补丁等价。仍有独有提交时只在临时 Worktree 中累计试合并，用于暴露分支间冲突，但不会把未经审查的临时结果直接打包。门禁通过后还必须完成全量测试、静态分析、Windows Debug 构建和启动存活检查，平台安装包 job 才能继续。

架构路线以以下规划文件为准：

```text
<private-planning-document>
```

当前代码结构是过渡实现，不再作为后续功能优先级的主导依据。后续架构重构必须服务该规划中的 Tag 驱动检索闭环：分组 Tag、组合筛选、筛选结果播放队列、Tag 管理、缓存诊断和跨平台边界。

`Architecture Baseline 0.5.63` 在不改变 SQLite schema 的前提下增加显式无效记录清理策略。设置默认开启，但 missing 删除只接受成功扫描 root 形成的 `isMissing`，临时离线且未标记的路径保留；不可读只接受当前存在但不是普通文件或无法打开句柄。Repository 批量删除主库行、标签关系与对应依赖备份，不进入 `FileSystemAdapter` 删除/回收站边界。标签查询、filtered queue、PlayerBackend 和磁盘媒体内容不变。

`Architecture Baseline 0.5.62` 在应用组合根外层增加独立的 GitHub Release 更新边界：首帧后以短超时读取公开正式 Release，只有远端语义版本更高时才展示更新说明和安装包入口。网络失败保持静默，不进入媒体库 Store、SQLite、标签查询、filtered queue、播放器或缓存队列。

`Architecture Baseline 0.5.61` 在不改变 PlayerBackend contract 的前提下统一 MediaKit 冷启动边界：应用先提交 Flutter 首帧，再由进程级幂等门禁预热原生库；媒体卡悬停和正式播放器都必须经过同一门禁并允许失败重试。播放器首帧占位只复用 `ThumbnailService` 已验证的进程内缓存，不启动额外 FFmpeg、磁盘扫描或 UI 线程视频处理。SQLite schema、标签查询、filtered queue 和用户数据不变。

GPU 能力边界分为两层：原生矩阵描述当前系统可见设备、显存和 API 能力，实际纹理渲染边界描述当前选中的 device LUID。系统“存在支持 Compute/Vulkan 的显卡”不等于播放器已选择该显卡；单硬件卡、Feature Level、名称、显存使用或枚举顺序均不能替代实际 LUID。DXGI LUID 仅在当前 Windows 会话内用于匹配和 QA，不进入 SQLite 或设置文件。

显卡矩阵与显式 Compute 基线由 runner 后台 future 执行，平台通道在未完成时返回 `probing`，避免驱动、Vulkan loader 或 benchmark 阻塞 Flutter UI。普通播放不会自动运行基线。第三阶段当前只允许 HDR 动态映射：持久化开关只是用户意图，实际会话还必须同时满足 HDR 源、精确活动 LUID 与 Compute 能力；否则保持 mpv 自动映射。会话复用两秒健康样本，新增掉帧、缓冲或停滞立即恢复自动映射，中等压力需连续两次才回滚；该回滚不改写全局开关。运动补帧保持未启动；自动画质的 `hqdn3d` 已以保守时域参数执行时空降噪，SDR 暗部增强也已完成独立 A/B 后作为默认关闭的可选能力。

SQLite schema 与写入、标签筛选和 stable identity 仍由 Dart 业务层统一拥有；Rust/C++ 只保留在只读扫描、媒体探测和实验播放器等平台边界后。`test/architecture_contract_test.dart` 会阻止重新引入 `part`。

当前应用是 Flutter 跨平台单体桌面应用，入口保留在：

```text
<project-root>\lib\main.dart
```

主要实现已按现有类边界拆到：

```text
lib/src/core
lib/src/models
lib/src/platform
lib/src/repositories
lib/src/services/library|media|player|relink|tags|window
lib/src/pages/library|player|tags
lib/src/widgets/library
```

一级目录表达技术模块，文件较多的模块再按业务职责进入二级目录。所有 Dart 源文件均已使用独立 import/export 边界；跨文件协作只通过公开 contract、facade 或明确的 UI 组合类型完成。


## 架构基线版本

已完成基线：`Architecture Baseline 0.5.124`

当前推进中：通过 macOS/Linux runner 持续验证 adapter、原生构建和启动；不扩大 SQLite 双写边界或改变业务语义。

变更点：

- `0.5.124`：诊断快照迁入 player domain；诊断弹窗只依赖播放状态流和采样回调，
  不再反向持有 PlayerPageState 或播放器资源。
- `0.5.123`：全屏状态/窗口命令顺序归纯 controller；Texture listener、事件取消、
  stop、dispose 与 released 归单一资源协调 owner，页面不再直接释放原生资源。
- `0.5.122`：快捷键暂停深度、标签编辑门禁、命令处理与焦点恢复资格归纯应用 owner；
  Focus/Keyboard/Route/Overlay 探测和命令执行保持 presentation owner。
- `0.5.121`：主控制条与快捷键反馈状态及两只短时 Timer 归单一纯应用 owner；
  设置/悬停锁定、latest Timer 覆盖和 dispose 后拒绝回调成为确定性状态合同。
- `0.5.120`：播放器打开意图使用 revision/stable-ID/path 快照拒绝旧异步结果；四类
  backend Stream 归单一纯事件 bridge，并在 PlayerService 释放前统一幂等取消。
- `0.5.119`：播放器来源队列、二级标签子集与播放/选择索引迁入纯应用会话 owner；
  stable-ID 快照校验、只读列表和同源回退阻止页面从 Store 或 mutable path 重建队列。
- `0.5.118`：媒体库四类结果来源、当前本地路径与 LIFO 返回栈归单一纯应用 owner；
  路径策略由页面注入，筛选清理、入口可达性、filtered queue 和平台边界保持不变。
- `0.5.117`：继续观看清理/撤销快照、批量提交与失败补偿迁入无 UI executor；最近播放
  临时选择改为 stable videoId，页面保留确认、反馈与刷新绑定。
- `0.5.116`：单条 Missing/Relink 使用捕获 stable identity/path/fingerprint 的显式
  command；过期/重复提交被拒绝，Repository batch 失败补偿同一对象和全部路径/标签索引。
- `0.5.115`：单视频手动标签替换成为显式不可变 command；folder 锁定、一级父级作用域
  与内存模型补偿集中到无 UI executor，Repository 失败同步恢复标签关系和新建索引；
  主库提交后的备份故障只进入诊断，不再诱导业务模型错误回滚。
- `0.5.114`：文件定位、同目录改名和删除成为显式 command；跨文件系统/Repository
  补偿顺序集中到无 UI executor，确认、偏好与反馈仍留在 presentation。
- `0.5.113`：扫描、路径导入检查和扫描后媒体解析状态归单一泛型 lifecycle owner；
  operation/Repository/media generation 拒绝旧发布，暂停/取消保持既有后端与事务边界。
- `0.5.112`：已接受 ResultSnapshot 成为 QueueSnapshot 的唯一来源；stable-ID 成员/
  顺序严格校验，PlayerPage 同时接收不可变 playlist 与来源 epoch，禁止从 Store 重建队列。
- `0.5.111`：筛选/搜索结果与 facet 计数拆成两个互不写入的 latest-only owner；
  结果按 `LibraryResultEpoch` 发布，候选/稳定计数保持独立只读快照，高频交互先更新视频。
- `0.5.110`：排序字段、方向、fingerprint 与纯内存重排归单一 application owner，
  自然排序算法迁入纯 domain；切换排序不重新筛选、不刷新标签计数，也不改变现有队列成员。
- `0.5.109`：媒体库结果数据与标签定义修订分离；主结果多选只保存 stable videoId，
  网格密度、侧栏和标签面板显隐归纯展示 owner。筛选、排序、计数、队列和扫描语义不变。
- `0.5.108`：备份设置迁为独立纵向切片；串行设置、状态订阅与维护互斥分别由轻量
  controller 拥有，Dialog/SnackBar 留在 presentation，运行态回滚、数据库检查和导出
  adapter 边界保持不变。源码无数据库替换/导入入口，因此未新增破坏性恢复。
- `0.5.107`：缓存维护命令迁入独立泛型 controller；重试/清除互斥，清除持久化失败执行
  内存补偿，不新增当前产品不存在的缓存删除或重建入口。
- `0.5.106`：缓存统计读取迁入泛型 latest-only controller；旧代次和 dispose 后结果不再
  发布，错误态不暴露原始异常，缓存破坏性命令继续留在独立 owner。
- `0.5.105`：普通播放设置迁入单一一致性 controller；串行保存并抑制旧失败回滚，页面
  保留全部设置入口和 Route 返回路径，备份与缓存生命周期未并入巨型 ViewModel。
- `0.5.101`：建立渐进式整体重构路线与依赖合同；启动入口、应用壳和组合根分离，
  更新功能成为首个 `domain/data/presentation` 纵向切片，具体 GitHub 客户端只在
  组合根创建。当时保留 `src/app.dart` 作为测试兼容导出面，生产入口不再依赖它；
  该兼容面已在 `0.5.126` 消费者归零后删除。

- `0.5.78`：新增类型化播放器渲染器偏好和纯组合根解析器；设置切换需确认并
  可撤销，Windows 用户无需环境变量即可在下次播放时进入原生 libmpv/D3D11。
  非 Windows、硬解关闭与异常值回退 MediaKit，自动档暂不改变默认后端。
- `0.5.77`：Windows 原生 libmpv 后端补齐 NVIDIA RTX Super Resolution
  驱动确认与滤镜后截图；能力只在 child HWND、非 copy D3D11VA、无 CPU
  滤镜冲突时开放。三类自然低码率片源六组 A/B 全部 0 掉帧、0 停滞、无回滚。
- `0.5.76`：新增 Route 级 `PlayerService`，组合根把 MediaKit/Windows libmpv
  后端封装后再注入页面；`PlayerPage` 与 `LibraryPage` 改依赖
  `PlayerServiceFactory`，画质/诊断改依赖 `PlayerRuntimeAccess`。Windows GPU、
  HWND、D3D11 与本机增强仍是后端可选能力，filtered queue、默认后端、插件 ABI、
  设置和退出释放顺序不变。

- `0.5.75`：Windows 固定 mpv 升级到 `v0.41.0-908-g48e6c35c0`；child
  HWND 使用命中透明窗口过程并在 Flutter 弹层期间隐藏。普通窗口的鼠标、
  弹层、全屏、快速切换、返回和退出已通过，DPR 变化会强制重算物理矩形；
  真实跨 DPI 尚无多显示器证据，因此 A/B 和默认后端切换继续阻断。
- `0.5.74`：Windows runner 增加显式 QA-only 双层 child HWND 后端；外层
  约束 Flutter airspace，内层交给 libmpv D3D11 输出。mpv 0.41 的三类自然
  低码率 1080P 页面均得到 `hwdec-current=d3d11va`、0 纹理复制和 0 掉帧，
  固定 mpv 0.36 不能启动该链。真实窗口画面与右侧队列不重叠，但齿轮和中央
  右键的物理鼠标门禁未可靠通过，因此实验入口不提升为 Windows 默认后端。
- `0.5.72`：隔离新版 mpv 的独立进程可启用 NVIDIA scaling mode，但 MediaKit 内实际回退 `hwdec-current=no`；首条自然片源即阻断开关。NVIDIA `d3d11vpp` 与 CPU `lavfi` 改为互斥完整 `vf` 快照，并预置读回确认和掉帧熔断；正式 mpv 仍为 0.36.0，产品门禁保持关闭。
- `0.5.71`：固定的 Windows mpv 0.36.0 DLL 已确认有 `d3d11vpp`、无 `scaling-mode=nvidia`。齿轮新增只读能力门禁和禁用的会话级实验开关；版本达到 0.39+ 仍需独立完成 D3D11 硬件帧、现有 `vf` 共存和回滚验证才允许点击。未升级 libmpv、未写 NVIDIA filter、未改插件 ABI、`PlayerBackend`、SQLite、filtered queue、缓存队列或用户数据。
- `0.5.70`：实验性 Windows 原生 mpv 后端新增 SDK 中立本机视频增强插件 ABI v1。插件只从 `LOCAL_TAG_PLAYER_VIDEO_PLUGIN_PATH` 显式绝对路径加载，不扫描、不安装、不分发；mpv/ANGLE 在原生工作线程写入共享 D3D11 纹理后调用插件，宿主提前备份原帧，插件失败时恢复并停用该会话。QA-only 往返探针和宿主自测无 install 规则，已验证无损往返与故障恢复；诊断通过现有 `PlayerBackend.getProperty` 展示插件状态。默认 MediaKit、filtered queue、缓存和用户数据不变，真实 RTX SDK 与发布许可仍未接入。
- `0.5.69`：播放器齿轮与诊断把既有 libmpv 能力统一标注为“GPU 高质量缩放（非 NVIDIA AI）”，保留 `videoSuperResolutionEnabled` 键、mpv 缩放属性和运行行为。RTX Video SDK 只形成平台评估：公开 RTX SDK 家族许可允许嵌入应用的目标代码分发但禁止 SDK 受开源许可约束，实际 SDK 1.1 下载包 EULA 仍是发布阻断；D3D11 原型必须在 Windows 原生边界拥有同一活动 LUID 的逐帧输入/输出纹理，失败回到 libmpv 缩放。未修改 PlayerBackend、SQLite、标签查询、filtered queue、缓存队列或用户数据。
- `0.5.68`：`PlaybackSettings` 向后兼容增加压缩画质增强三档；旧布尔 `true` 迁移为自动，缺失或无效值保持关闭。`PlayerPage` 复用现有低频健康样本和 profile 上限，清晰增强只提前请求最高安全档，后续压力回滚与迟滞恢复不变。去色带通过现有 mpv 属性访问串行启停，不新增离线处理、FFmpeg 播放链或 `PlayerBackend` 方法。450 kbps 1080P Windows A/B 为 0 掉帧/0 卡顿，固定帧未见明显光晕，故缩放后 GLSL 锐化继续不启用。SQLite、标签查询、filtered queue、缓存队列和用户数据未改变。
- `0.5.67`：`AppUpdateService` 增加当前版本读取与下载安装边界；GitHub 实现仅在 Windows 下载带 SHA-256 摘要的正式安装器，使用 `.part`、长度检查、流式摘要校验和原子改名后启动，不传递静默安装或提权参数。设置首页新增关于入口，显示版本、构建号、正式版渠道和主动检查状态。非 Windows、摘要缺失与失败路径继续使用 Release 页面，不修改 SQLite、标签语义、filtered queue、PlayerBackend、缓存队列或用户数据。
- `0.5.66`：无效记录清理把 `FileSystemEntityType.notFound` 明确纳入删除条件，不再要求路径先由扫描标记为 missing；既有批量数据库事务、依赖备份清理和磁盘文件保护边界不变。
- `0.5.65`：主线升级到 `media_kit_video 2.0.1`，固定 archive 与 SHA256，并在 Windows 构建期继续替换 `ANGLESurfaceManager` 和 `video_output.cc`；架构合同要求稳定 GPU/软件 descriptor 捕获及销毁门禁。新增不切换 SDK 的 Windows Profile 播放/输入/全屏基线，以及不接入产品的 FFmpeg 8.1.2 缩略图 GPU A/B。PlayerBackend contract、SQLite、标签查询、filtered queue、缓存队列和用户数据不变。
- `0.5.64`：正式打包工作流先刷新并检查全部 `origin/*` 分支；祖先关系与 `git cherry` 补丁等价均视为已集成，仍有独有提交则在隔离临时 Worktree 中按稳定顺序累计试合并并阻断发布。只有待打包提交等于 `origin/master`，且全量测试、静态分析、Windows Debug 构建与启动存活检查全部通过，Windows/macOS 正式包才允许构建。该边界不修改应用业务、SQLite、标签语义、filtered queue、PlayerBackend、缓存队列或用户数据。
- `0.5.63`：`PlaybackSettings` 增加默认开启的无效记录清理策略；设置开启与扫描完成后经 `LibraryRepository.removeMissingOrUnreadableVideos` 串行执行。探测限并发并让出 UI，主库与依赖备份同步删除以防自动复活，但不删除磁盘文件。SQLite schema、标签来源、FilterQuery、filtered queue、PlayerBackend 和缓存队列不变。
- `0.5.62`：新增平台无关 `AppUpdateService` 查询边界及 GitHub Releases 实现；应用首帧后检查 `Zero-1412/LocalTagPlayer` 最新正式 Release，按安装包版本比较并展示 Release 正文，Windows 优先打开对应安装器资产。网络失败不阻塞本地启动；SQLite、标签查询、filtered queue、PlayerBackend、缓存队列和用户数据不变。
- `0.5.61`：MediaKit 从“首次创建播放后端时初始化”收敛为“Flutter 首帧后统一预热、消费者幂等兜底”；悬停 Player 构造失败不再泄漏 loading。播放器使用已验证缩略图跨越纹理接管窗口，并把 loading 延迟到真实慢打开。PlayerBackend contract、缩略图调度、SQLite、标签查询、filtered queue 和用户数据不变。
- `0.5.60`：`PlaybackSettings` 向后兼容增加暗部细节增强开关；实际会话只在明确 SDR、1080p 及以下与硬解三项都通过时应用 `eq` 曲线。曲线与自动去块/时空降噪/锐化使用同一原子 `vf` 快照，压力回滚拥有独立会话状态。设置页删除内部路线卡，HDR 映射保留 LUID/Compute/HDR 源门槛并使用正式用户文案。PlayerBackend contract、SQLite、标签查询、filtered queue 和用户数据不变。

- `0.5.59`：`PlaybackSettings` 向后兼容增加 `fullscreenQueueEdgeHoverEnabled`，旧 JSON 缺字段时默认开启。播放器交互页只暴露该开关，历史热区宽度与隐藏延迟字段保留读取兼容但不再驱动运行时；播放器使用固定 32px 入口、实际列表宽度加 12px 保持区和 450ms 离开宽限。展开后移除覆盖列表最右侧的独立边缘层，显式列表按钮不受开关影响。未修改 PlayerBackend、SQLite、标签查询、filtered queue、缓存队列或用户数据。

- `0.5.58`：媒体库 Route 持有只存在于当前应用会话的 `PlayerFullscreenSessionController`。播放器切换全屏时同步该状态；全屏返回以 `window_manager` 实际状态兜底，按“退出全屏 → 最大化 → Route 返回”恢复主界面，且保留下次播放器全屏偏好。用户主动退出全屏会清除偏好，普通窗口/最大化进入与返回不触发窗口改写。未修改 PlayerBackend contract、`PlaybackSettings`、桌面窗口布局文件、SQLite、标签查询、filtered queue、缓存队列或用户数据。

- `0.5.57`：组合根不再在应用首帧前加载 `media_kit` 原生库；只有默认 MediaKit 播放后端被实际创建时才执行初始化，修复 Windows Debug exe 独立启动后进程存活但窗口不出现。全屏顶部队列语境与底部控制条互斥显示，只复用现有显隐状态和动画时长。未修改 PlayerBackend contract、SQLite、标签查询、filtered queue、缓存队列或用户数据。

- `0.5.56`：Windows DXGI 探针从活动适配器返回桌面输出、分辨率、位深、色彩空间、HDR 信号与亮度元数据；固定 1080p HDR10/PQ 与 SDR 暗部样本分别建立 300 秒和 180 秒真实 MediaKit 长播基线。HDR 会话压力协调器复用既有健康 Timer，严重压力立即回滚、中等压力连续两次回滚并锁存到下一媒体，用户持久设置不变。设置首页拆分“播放与解码”和“视频画质与增强”，仍共享同一设置模型。未修改 SQLite、标签查询、filtered queue、缓存队列或用户数据。

- `0.5.55`：固定 SHA256 的 MediaKit `ANGLESurfaceManager` 在真实 D3D11 device 生命周期登记活动 LUID，runner 通过导出函数读取；构建期补丁不写 Pub Cache，并在上游片段变化时失败。`PlayerGpuRenderBoundary` 类型化返回活动证据和显式 D3D11 timestamp Compute 报告；当前 RTX 4070 SUPER 的 1080p / 4K HDR 类 kernel P95 为 0.036ms / 0.129ms，均低于 60fps 的 4.167ms 预留切片。第三阶段仅开放默认关闭、确认启用、关闭恢复 `auto` 的 HDR 动态映射；真实播放还由 HDR 源、精确 LUID 与 Compute 能力共同门控。未修改 SQLite、标签查询、filtered queue、缓存队列或用户数据。

- `0.5.54`：`PlayerBackend` 新增类型化显卡设备矩阵。Windows runner 在后台用 DXGI 枚举适配器与显存、用真实 D3D11 device 验证 Feature Level / Compute、用系统 Vulkan loader 匹配物理设备；Flutter 平台线程只读取 `probing/ready` 快照。系统能力与活动渲染器分离，只有当前会话已确认 GPU renderer 且单硬件卡或 Feature Level 唯一匹配时才验证活动 Compute，多卡歧义保持锁定。未修改 SQLite、标签查询、filtered queue、缓存队列或用户数据。

- `0.5.53`：在隔离 profile 中建立 1080p 类 / 4K 类 × GPU 硬解 / CPU 软件解码四组真实稳定段基线，同时采集进程 CPU、GPU Engine、GPU committed、实际解码器和掉帧；基线明确 4K 软件解码已有掉帧与 AV 偏移，因此禁止自动叠加滤镜。`PlayerAdaptiveQualityCoordinator` 复用播放器健康 Timer，每两秒读取一次扩展样本，以连续健康、滞回和冷却时间逐级启用去块、降噪与适度锐化，任何掉帧、缓冲、停滞或 FPS 压力立即降级；`vf` 完整快照通过既有 `PlayerBackend.setProperty` 串行应用。`PlayerGpuCapabilityDetector` 只读取当前后端明确报告的输出驱动、渲染 API/上下文、D3D11 Feature Level、硬解和 HDR 源信号；嵌入式 `libmpv` 返回明确 D3D11 Feature Level 时可确认 GPU 渲染存在，Compute Shader 能力仍保持未验证，不按显卡型号猜测。未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、PlayerBackend contract、缓存队列或用户数据。

- `0.5.52`：`PlaybackSettings` 向后兼容增加 5 / 10 / 15 / 30 / 60 秒快进快退档位；播放器快捷键与按钮统一消费该档位，按键连发只显示一次左上角轻量文字水印，不再在画面中央遮挡内容。控制条首次进入默认显示，3 秒无交互后收起，仅底部进度区域重新唤出；全屏队列迁到根 `Stack` 的固定覆盖层，以淡入和短距离右滑动画出现，不再逐帧改变视频纹理尺寸。播放设置二级页改为直接替换内容树，避免 Windows 视频纹理与新旧复杂设置树重叠时触发 Flutter 引擎访问冲突；弹层开合动效与 reduced motion 降级保持。未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend` contract、缓存队列或用户数据。

- `0.5.51`：`PlaybackSettings` 向后兼容增加默认关闭的 GPU 画质超分开关；`PlayerVideoSuperResolution` 只通过既有 `PlayerBackend.setProperty` 应用 libmpv GPU renderer 的 `ewa_lanczossharp`、sigmoid 与 resize-only，并按后端串行化 open 重放和用户切换，在媒体 open 前后恢复完整配置。当前 libmpv 不包含 Intel/NVIDIA `d3d11vpp scaling-mode` 厂商扩展，因此不宣称 AI 超分。Flutter UI 不处理视频帧；未修改 `PlayerBackend` contract、硬解选择、SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缓存队列或用户数据。

- `0.5.50`：`FileSystemAdapter` 增加拒绝覆盖的单文件重命名契约；播放器文件名入口只编辑 basename 并保留扩展名，标签入口继续独占 manual 标签维护。`LibraryRepository.renameVideoPath` 仅提交同目录 mutable path、标题和兼容 path 索引，SQLite batch 成功后才迁移内存索引；稳定 `videoId`、标签关系、收藏和播放状态保持。当前文件句柄不允许重命名时，播放器使用既有 pause/stop/open/seek 边界恢复原位置，不修改 `PlayerBackend` contract。未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缓存队列或标签来源语义。

- `0.5.49`：`PlaybackSettings` 向后兼容增加删除确认、回收站最终状态和“返回上一页”绑定；设置写入失败时恢复旧状态或中止删除。单条、批量和播放器队列共用 `VideoDeleteDecision`，跳过确认仍只通过现有 stable identity 清理与 `FileSystemAdapter.moveFileToTrash` 边界执行。非主路由用仅当前 Route 生效的键盘处理器和鼠标返回侧键统一返回，EditableText、PopupRoute 与快捷键录制焦点拥有门禁；播放器全屏 Esc 保持固定安全出口。快捷键录制支持常用基础键及 Control / Alt / Shift 组合，冲突不交换绑定。未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、缓存队列或用户标签/收藏数据。

- `0.5.48`：`FileSystemAdapter` 的目录/文件选择增加可选初始目录，并提供跨平台父目录解析；媒体库和 Relink 页面只决定业务候选位置，桌面适配器继续独占原生选择器实现。`LibrarySortPreferences` 向后兼容保存网格/列表偏好，旧 JSON 缺字段时保持网格默认；超宽列表只消费内存中的标签、媒体详情和文件大小。缩略图失败统计统一为“无有效缓存且存在错误”的缺失子集，页面可查看原因、重试或仅清除失败标记，活动队列期间禁用操作。SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、缓存 key/JPEG 有效性和 stable identity/relink 校验均未改变。

- `0.5.47`：`LibraryRepository` 增加批量 `upsertPlaybackStates` 与 `cancelActiveScan` 契约；前者支持“继续观看”按 stable videoId 保存并精确撤销完整播放快照，且不会覆盖撤销后重播生成的新进度，后者取消当前扫描 backend generation、解除暂停并阻止旧差量提交。备份规范快照不再持久化全局派生的标签 `usage_count`，避免把一致的 video-tag 关系误判为过期；fingerprint 歧义仍只阻止不安全自动恢复。播放器页面统一暂停 EditableText、PopupRoute、菜单、弹窗和原生文件对话框期间的单键快捷键，并持续跟踪全屏队列热区。SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、缩略图/媒体详情队列和 stable identity 语义未改变。

- `0.5.40`：`MediaDetails` 增加可选容器总时长；Windows 原生 `MediaProbeBackend` 从 `AVFormatContext::duration` 返回毫秒，兼容 `DesktopFFmpegBackend` 只追加读取 `format.duration`，仍经过既有平台边界和单批次限流。媒体库扫描后只为旧详情中缺少可靠时长的活动视频补齐，并复用 `videos.playback_duration_ms` 持久化，不新增 SQLite 列或迁移。网格卡片移除缩略图播放按钮、底部操作区、标签和路径，收藏/时长改为缩略图角标，卡片高度按实际列宽计算；卡片本身成为打开当前 filtered queue 的入口。`FilterQuery` / `TagQueryService`、filtered queue、缩略图队列、stable identity 和用户收藏数据语义未改变。

- `0.5.39`：独立备份库以 `session_open` 和 `reconcile_required` 区分正常关闭、异常退出与关闭期间的主库变化；`DesktopWindowStateService` 在桌面窗口销毁前等待 Store 关闭和 clean marker，正常启动跳过全量游标，异常窗口仍保守补做全量。全量和增量统一使用规范快照与条件 UPSERT，指纹和依赖 JSON 均未变化时不更新 `updated_at` 或 SQLite 数据页。设置页新增只读完整性检查和便携 JSON 导出；检查覆盖 SQLite、JSON、当前视频缺失/过期快照及指纹歧义，保留未来可恢复快照且不自动修复。导出通过 `FileSystemAdapter` 选择和写入位置，不包含路径、媒体文件或缓存。主 `library.db` schema、stable identity 恢复保护、标签语义、filtered queue、PlayerBackend 和缓存队列未改变。

- `0.5.38`：`DatabaseProvider` 增加独立备份库打开边界，`AppPaths` 固定使用 `video_dependency_backup.db`，不复制视频文件或复用主库文件。默认开启的 `DataBackupSettings` 独立持久化；全量核对按稳定 videoId 小批次推进并在备份库保存游标，增量修改进入去重队列，应用重启后续跑。恢复仅在扫描侧与备份侧 fingerprint 双侧唯一且主库无 videoId 冲突时发生，恢复收藏、播放状态、非 folder 标签及其分组定义；folder 标签仍按当前 root 派生。root detached 保留快照，显式单视频删除在 worker 批次边界同步删除快照。播放器创建前暂停备份、原生释放后恢复；`FilterQuery` / `TagQueryService`、filtered queue 与 PlayerBackend contract 未改变。

- `0.5.37`：`videos` 幂等增加 `is_detached`，Store hydration 拆分 active/detached 路径索引。移除 root 在同一 SQLite batch 中保存剩余 roots 并标记仅属于该 root 的视频 detached，保留 videoId、标签关系、收藏、播放记录、媒体详情和缩略图；detached 不进入 `TagQueryService` 或 filtered queue，但标签管理仍保留其引用计数。重新添加相同 root 按 path 激活原行，路径变化时由扫描协调器按两侧唯一 fingerprint relink；过期媒体探测 upsert 不能静默激活 detached。旧库默认迁移为 active，未修改 `FilterQuery` / `TagQueryService` 语义或 `PlayerBackend`。
- `0.5.36`：`FileSystemAdapter.moveFileToTrash` 明确区分可恢复删除与原永久 `deleteFile`；Windows 桌面适配器通过系统 `SendToRecycleBin` 边界执行，路径不拼接进脚本，失败时抛出异常且上层不删除 SQLite 记录。播放器队列左滑操作区改为主题深色胶囊、细描边和低强调图标，不再使用突兀的大面积红色块。只读数据库审计确认收藏字段一直写入 SQLite；本轮未修改 schema、stable identity、`FilterQuery` / `TagQueryService`、filtered queue 或缓存队列，也未自动改写用户正式库。
- `0.5.35`：`PlaybackSettings` 向后兼容增加镜像、队列播放方式、画面比例和倍速；旧 `settings.json` 缺字段或包含异常值时恢复安全默认值。播放器设置写入串行化并同步更新应用级快照，重启后的新会话会在媒体 open 前后把比例与倍速重新送入 `PlayerBackend`，避免只保存数据或 UI 选中态。设置浮层保持一级镜像/循环开关，二级只显示比例与倍速导航，各自进入三级选择列表；二级不再重复播放方式、快捷键和播放诊断。SQLite schema、FilterQuery/TagQueryService、filtered queue、缩略图/媒体详情队列和用户数据均未改变。
- `0.5.34`：`LibraryScanBackend` 增加无路径阶段进度与暂停/恢复契约；Rust sidecar 先发现候选，再对确定总数执行 stat/fingerprint，并用 stderr 计数协议上报，stdout 快照协议与 SQLite 单写边界不变。播放前通过 `LibraryScanPlaybackGate` 自动暂停目录扫描，退出后原位恢复；提交大量差量时每 256 项让出 UI isolate。真实 `X:\test-media` 热缓存强制 fingerprint 对照为 11,163 项：目录发现 24ms、fingerprint 1,444ms、初次历史上下文提交 1,995ms、稳定态端到端 754ms；冷启动继续由阶段 JSONL 记录，不把热缓存结果冒充冷盘数据。SQLite schema、stable identity、标签语义、filtered queue、PlayerBackend 和媒体探测并发均未改变。
- `0.5.33`：媒体库大目录导入分为“发现并校验视频”和“后台解析媒体信息”两阶段；总量未知时显示不确定进度，扫描提交后立即开放视频列表并显示已处理/总数/百分比。`MediaDetailsService` 保持单原生批次执行和可见项优先，每个后台批次最多 8 条；`MediaProbeBackend.probeBatch` 与新增 Repository 批量 upsert 把平台调用、SQLite 提交从逐文件收敛为有限批次。新扫描会取消旧媒体探测以避免磁盘争抢。SQLite schema、stable identity、标签语义、filtered queue 和缩略图队列不变。
- `0.5.32`：`FileSystemAdapter` 增加跨平台多文件选择契约，桌面适配器统一返回规范化路径；媒体库把选择/拖入的视频父目录与目录本身归并为最上层 root，并通过新增批量 Repository 命令只触发一轮扫描。`desktop_drop` 只负责传递本地路径和悬停反馈，文件识别、stable identity、folder 标签与 SQLite 写入仍由原 Dart 扫描链路拥有。目录管理删除复用统一页面清理协调；SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/media 队列和磁盘文件删除规则不变。
- `0.5.31`：`FFmpegBackend` 增加独立 `createFramePreview` 契约，播放器进度条悬停帧通过现有平台工具边界提取，不 seek 主播放器、不在 UI 散落进程路径。悬停连续移动只更新轻量位置，停稳 350ms 后才进入单并发取帧；临时帧按秒复用并以 24 项 LRU 限制。媒体库缩略图主队列、失败状态、`PlayerBackend`、SQLite、FilterQuery/TagQueryService、filtered queue 和用户数据均不变。
- `0.5.30`：`PlayerBackend.buildVideoSurface` 增加可选 `mirror` 参数；MediaKit 与 Windows 原生后端只水平翻转视频表面，Flutter 控制条保持原方向和命中坐标。播放器设置改为一级紧凑开关列表与二级完整设置，比例、倍速、快捷键和诊断只在二级页挂载。SQLite、FilterQuery/TagQueryService、filtered queue、缓存队列、播放生命周期和用户数据均不变。
- `0.5.29`：`PlayerBackend.buildVideoSurface` 增加可选 `BoxFit` 与显示宽高比参数，页面仍不接触具体 Player/纹理控制器；默认 `contain` 保持完整画面，显式“铺满”由 media_kit 视频表面使用 `cover` 并结合 mpv panscan 等比裁边。SQLite、FilterQuery/TagQueryService、filtered queue、缓存队列、播放生命周期和用户数据均不变。
- `0.5.28`：新增 `LibraryPageApplicationService`，把 facade 首屏加载、偏好持久化、缩略图/媒体详情创建和 debug 诊断配置移出页面；`LibraryPage` 不再依赖完整 `LocalTagPlayerDependencies`。生成 macOS/Linux runner 并增加跨平台 CI build/start smoke；SQLite、FilterQuery/TagQueryService、stable identity、filtered queue 与缓存队列语义不变。

- `0.5.27`：清零全部 Dart `part` / `part of`；按 Store 私有协作、播放器/缩略图实现、应用服务、页面/widgets 的顺序建立独立 library 边界。新增组合根依赖 contract 与零 `part` 架构测试；schema、FilterQuery/TagQueryService、filtered queue、缓存队列和用户数据语义不变。

- `0.5.25`：落地 `DesktopFileSystemAdapter`，目录选择、异步目录枚举、文件 stat/写入/删除和文件管理器定位统一经过平台边界；`LibraryStore` 成为真实 `LibraryRepository` 实现，页面改依赖 `LibraryApplicationFacade`。播放器、媒体探测、扫描与 FFmpeg 具体实现由 bootstrap 组合根选择。首批把文件系统契约/实现、`LayoutSize`、`MediaDetails` 从 `part` 迁移为独立 import；SQLite、标签筛选、stable identity 和 filtered queue 继续由 Dart 单写与编排。

- `0.1.0`：完成 `main.dart` 第一阶段机械拆分，形成 `src/models`、`src/services`、`src/pages`、`src/widgets`。
- `0.2.0`：新增 `src/core`，集中 `TagRules`、`AppPaths`、`PlaybackSettings`，作为后续平台接口和独立 import 模块的过渡基建。
- `0.3.0`：新增 `FileSystemAdapter`、`PlayerBackend`、`FFmpegBackend`、`DatabaseProvider` 接口边界，并新增 `TagGroup`、`TagItem`、`FilterQuery`、`PlaybackSession`、`CacheStatus`、`DiagnoseStatus` 等平台无关模型 stub；当前仅定义协议，不替换现有 Windows 实现。
- `0.3.1`：补齐 `TagItem` 别名、`TagGroup` 排除项和 `FilterQuery.matches` 平台无关筛选语义；不同标签组 AND，同组标签 OR，排除标签 NOT，并让主界面现有单选筛选通过 `FilterQuery` 执行。
- `0.4.0`：收口平台接口职责，补齐目录选择、文件管理器定位、FFmpeg 可用性/版本、数据库文件位置等边界方法；新增 `LibraryRepository`、`TagRepository`、`CacheRepository`、`PlaybackRepository` 接口规划；新增 `LayoutSize` 与 `LayoutBreakpoints` 共享响应式契约；扩展 Tag/Filter/Playback stub 到外部规划字段，保持现有 Windows 行为不变。
- `0.4.1`：新增 SQLite `tag_groups`、`tags`、`tag_aliases`、`video_tags` 规范化索引表；`LibraryStore` 同步 folder/manual 来源 tag 索引，新增 `TagQueryContext` 与 `TagQueryService`，让关键字搜索匹配当前视频关联的标签名和别名，并保持筛选结果作为播放器当前队列。
- `0.4.2`：补齐 Tag 索引验收修复；旧库加载时按视频缺失情况回填 folder 来源索引；手动标签同步只刷新 manual 当前编辑范围并排除路径派生 folder 标签；结果计数忽略候选标签所在组，避免同组计数塌缩；补充 alias/source 查询索引。
- `0.4.3`：Chat 5 第一阶段落地 `DesktopFFmpegBackend` 兼容适配层，`ExternalMediaTools` 统一通过 `FFmpegBackend` 定位和调用 FFmpeg/FFprobe；诊断页显示工具版本、缩略图/媒体信息队列状态，并提供失败重试、清除失败记录和异常文件列表。Windows bundled tools 查找顺序保持不变。
- `0.4.4`：Chat 6 第一阶段新增 Tag Manager 入口和页面；`LibraryStore` 增加标签来源使用统计、创建/编辑标签、别名、hidden/favorite/sortOrder、移动标签组和当前筛选结果批量添加/移除 manual 标签能力。批量移除只删除 `source=manual` 关系并同步兼容字段，folder 来源关系不被移除；删除/合并暂只做引用检查与风险提示。
- `0.4.5`：补充 `LibraryStore` focused tests，覆盖目录扫描、folder/manual 标签维护和 SQLite 持久化读写；新增 `LibraryScanService` 隔离文件系统扫描、folder 标签派生和轻量媒体指纹，`LibraryStore` 继续负责 SQLite 写入、内存状态和标签索引同步。播放器页面继续拆分为主页面、底部上下文面板和右侧队列侧栏，播放队列语义不变。
- `0.5.0`：落地 Stable Video Identity 第一阶段。`videos.video_id` 成为稳定身份，path 为 mutable location；`video_tags.video_id` 承载标签关联，旧 path 关联自动回填。扫描使用路径无关的小样本内容 fingerprint 做唯一 relink，歧义匹配拒绝合并；缺失路径标记 missing 而不删除记录。播放进度与最近播放写入稳定视频行，移动后随 videoId 保留。
- `0.5.1`：强化标签播放器闭环。播放器 manual 标签编辑支持最近使用、收藏标签和搜索；队列搜索严格限定当前 filtered queue；收藏和打标只做单条写入并延后无计数刷新。新增 `DesktopFileLocationService`，把 Windows/macOS/Linux 文件管理器定位命令留在 platform 边界。
- `0.5.2`：开放 Missing/Relink 首个用户闭环。`MissingRelinkPage` 展示 missing 稳定条目；手动 relink 复用单文件扫描快照和标签同步事务，只在 fingerprint 一致且路径未占用时更新 mutable path。播放器标签弹窗补齐键盘链路，并用 50,000 条队列基准保护轻量搜索边界。
- `0.5.3`：播放状态完整绑定 stable videoId。`videos` 幂等增加总时长与完成态，播放器低频/切换/退出/EOF 统一保存稳定播放快照；继续观看只消费有效未完成进度。missing 队列项停止失效路径 I/O，并从播放器失败面板复用 fingerprint Relink。
- `0.5.4`：增加批量路径前缀替换的只读预览与安全执行，所有 ready 项仍复用单文件 fingerprint Relink；新增按 videoId 合并、全局串行的播放快照写入队列，并在播放器返回前 flush。真实 C:→E: 20 条跨盘 soak 覆盖移动、重载与用户数据保留。
- `0.5.5`：批量 Relink 升级为执行前统一重验和单 SQLite batch 原子提交，事务失败恢复内存索引并返回失败 videoId；预览支持内存搜索、隐私安全审计摘要和失败项定向重试。
- `0.5.6`：`PlaybackSettings` 增加向后兼容的默认恢复行为；旧设置文件自动采用“从上次位置继续”，仅用户选择“每次询问”时播放器才显示恢复弹窗。设置页同时把常用解码策略与具体高级后端分层展示，不改变 PlayerBackend 或 SQLite schema。
- `0.5.7`：新增 `DesktopWindowStateService` 桌面边界，通过 `window_manager` 恢复并延迟保存窗口大小与最大化状态；`PlaybackSettings` 向后兼容扩展用户快捷键映射，设置页负责编辑和冲突交换。窗口状态使用独立 JSON，不修改 SQLite schema、PlayerBackend 或 filtered queue。
- `0.5.8`：`PlaybackSettings` 向后兼容增加全屏队列右侧热区宽度和自动隐藏延迟；旧 JSON 缺字段时使用 12px / 180ms，异常值约束在 4–40px、0–1000ms。设置页滑杆松开后持久化，并可只恢复这两个默认值；播放器仅消费共享配置，不修改 PlayerBackend、SQLite schema 或 filtered queue。
- `0.5.9`：Windows 播放器继续通过 media_kit/libmpv 平台边界使用 D3D11 硬解；页面层限制输入与 demux 缓存预算，并持续独立采样视频帧号和音频 PTS。退出协议在路由 pop 前确认 pause，路由释放后等待原生 Player dispose；不修改 filtered queue、SQLite schema 或标签查询契约。
- `0.5.10`：Windows 推荐硬解固定为 `d3d11va-copy`。实测会话 dispose 快且重复进入无线程累积，因此 PlayerBackend 的目标是串行拥有并释放每次播放会话，而不是保留全局长驻 libmpv/D3D11 实例；后者会把原生驱动线程带回媒体库页面，不能降低播放峰值。
- `0.5.11`：播放器生命周期诊断跨 Flutter ImageCache、media_kit 纹理 ID、libmpv demux 状态与 Windows GPU Process Memory 对齐。VideoController 仍由 Player release 回调释放；退出后 D3D Shared 回落而 NVIDIA Dedicated/Committed 可保留为驱动缓存，不引入平台命令强制清理或破坏缩略图缓存。
- `0.5.12`：`PlayerBackend` 扩展为完整播放会话、纹理、轻量状态、诊断属性与释放完成契约。`MediaKitPlayerBackend` 独占现有 Player/VideoController，`PlayerPage` 只消费可注入后端，不再穿透 media_kit 或 libmpv；默认行为仍为现有 `d3d11va-copy` 路径，为后续 Windows C++ 后端保留可回滚 A/B 切换点。
- `0.5.13`：Windows runner新增`NativePlayerBridge`骨架，提供方法通道、外部像素纹理、单线程串行命令与确定性释放；`WindowsNativePlayerBackend`仅能通过环境开关显式启用假纹理，默认仍使用media_kit。真实libmpv/D3D11接入必须先供应固定版本、可重复构建的头文件和二进制，不允许依赖Pub Cache或build临时目录。
- `0.5.14`：Windows 原生后端固定并按 SHA-256 校验 libmpv、ANGLE 和纹理桥接源码，构建产物随包安装运行库与许可证。单个 `mpv_handle`、`mpv_render_context` 和 ANGLE/D3D11 共享纹理均由串行工作线程拥有，EOF、错误、帧推进、AV 偏移、缓存和硬解状态通过节流快照进入现有 `PlayerBackend`；默认仍为 MediaKit，仅通过环境开关执行可回滚 A/B。
- `0.5.15`：真实 3840×2160 长视频以同样本、同种子分别完成 MediaKit、原生基线和原生优化各 480 秒/18 轮。压力采样明确区分播放器启动、稳定播放、释放与媒体库空闲阶段；原生渲染调用 `mpv_render_context_update` 过滤非帧更新，ANGLE 表面按 Flutter 请求在 1280×720 到 1920×1080 间量化，demux 预算收敛到 64+16 MiB。优化后无音视频停滞且 seek P95 从 118 ms 降至 27 ms，但稳定期 Private/GPU committed 仍高于 MediaKit，因此默认后端不变。
- `0.5.16`：完成 D3D11/ANGLE 最终内存归因并停止默认原生播放器替换路线；新增独立 `MediaProbeBackend`，Windows C++ 通过延迟加载的 FFmpeg 8.1 shared libraries 串行执行 `probeBatch/cancelGeneration`，SQLite 仍只由 Dart Repository 写入。真实 11,135 条索引库证明扫描瓶颈来自未变化文件的随机指纹读取，`LibraryScanService` 复用数据库 size/mtime/fingerprint 后 15,958 文件热扫描降至 2.72 秒，不引入 Rust。
- `0.5.17`：修复 SQLite 启动时无条件 stable identity 回填产生的 NOCASE 关系数乘视频数全表扫描，并建立 `LibraryScanBackend` / `LibraryScanDelta` / generation 取消边界。Windows Rust sidecar 只读目录、stat 与 fingerprint，缺失时回退 Dart；Dart Application 独占 stable identity/relink 校验和 SQLite 单 batch 提交。父子 root 最上层优先去重，首帧不等待扫描或媒体探测，新增/内容变化项才进入缓存与 `MediaProbeBackend`。
- `0.5.18`：明确媒体库删除边界。移除 root 由 Dart Application/SQLite Repository 单事务删除不再受其它 root 管理的视频记录，磁盘文件不动；单视频删除由 UI 显式选择是否同步删文件，并清理稳定视频行、标签关系和缩略图缓存。缩略图可见任务可抢占滚动遗留队列；PlayerBackend 诊断持续区分硬解属性不可用与明确软件解码，硬解参数只在 open 前设置，播放中不热切换解码后端。SQLite schema、过滤语义与 filtered queue 不变。
- `0.5.19`：新增只读 `PlayerHardwareCompatibility` 预检边界。它只消费 SQLite hydration 已恢复的 `MediaDetails` 与播放设置，不读取文件、不启动 FFprobe；4K H.264/HEVC/AV1 真实矩阵用于避免误报，已确认回退软件解码的 8K H.264 在创建 `PlayerBackend` 前要求用户确认，并给出不覆盖源文件的代理/转码建议。
- `0.5.20`：增加仅在显式环境变量下注册的 debug 媒体库压力控制边界，复用现有 Dart Application、SQLite Repository、LibraryScanBackend、MediaProbeBackend 与 PlayerBackend，不另建业务写入路径。root 移除会先取消媒体探测 generation，探测结果写回前必须确认 path、videoId、fingerprint 仍属于当前 Store；数据 revision 同步失效过滤派生缓存，防止 SQLite 与 UI 分裂。
- `0.5.21`：缩略图后台候选与文件校验分层限流，可见卡片仍通过共享优先队列抢占；播放前仅对用户点击且缓存详情不完整的当前项执行独立 `MediaProbeBackend` 预检，播放器页面与 filtered queue 不主动探测。Windows MediaKit 的 released 契约覆盖依赖内部延迟执行的 `mpv_terminate_destroy`，下一会话不得与旧 libmpv/D3D 资源重叠；已确认回退 CPU 的 8K H.264 默认阻止直接播放。SQLite schema、标签语义和 filtered queue 来源不变。
- `0.5.22`：debug 压测在卡片外壳、预览、元数据、标签和操作区建立显式 build/layout 诊断边界，并在最后一次 `PlayerBackend.released` 后持续采样进程、线程、句柄、有效 GPU counter 和播放器内存快照。诊断只观测应用 builder 与 RenderObject/PlayerBackend/驱动边界，不调用 GC、不清理 Flutter ImageCache，也不改变生产构建的缓存和释放策略。
- `0.5.23`：在现有一级模块内增加职责二级目录：页面按 library/player/tags，服务按 library/media/player/relink/tags/window，媒体库组件归入 widgets/library。所有文件仍属于同一个 `app.dart` part library，本轮只移动文件并修正相对路径，不修改 schema、平台 contract、过滤语义、filtered queue 或缓存行为。
- `0.5.24`：Windows 原生依赖下载改为临时文件、SHA256 校验通过后原子落盘并最多重试三次；项目已校验的 mpv/ANGLE 归档复用给 media_kit 插件，避免重复下载留下损坏缓存。PlayerBackend contract、运行时行为和用户数据不变。

协作要求：

- 其它 Chat 如果修改 `src/core`、模块目录、底层服务协议、数据库 schema、跨平台路径/工具规则，必须同步更新本节版本号和变更点。
- 普通 UI、播放器调参、缩略图策略、扫描细节可以在对应 Chat 内处理，但不能绕过 core 规则重复实现底层逻辑。
- 如果当前实现习惯与 `local_tag_player_flutter_cross_platform_plan_v2.md` 冲突，以规划文件为准；短期无法实现时必须在 `ROADMAP.md` 或对应 Chat 文档记录临时偏离原因。

核心数据流：

```text
本地目录
  -> Dart / Rust LibraryScanBackend 只读扫描并输出 ScanDelta
  -> Dart Application 校验 stable identity / relink
  -> SQLite Repository 单事务提交并差量刷新内存
  -> folder 来源初始 Tag
  -> player-owned grouped tags
  -> FilterQuery 组合筛选
  -> 当前筛选状态条与结果列表
  -> PlaybackSession / filtered queue
  -> PlayerPage 消费当前队列
  -> Tag Manager / batch tagging 反向修正标签
```

## 主要模块

### 核心层

职责：

- `TagRules` 集中一级/二级标签派生、默认专辑排序、视频扩展名判断。
- `AppPaths` 集中应用数据目录、设置文件、媒体库数据库、缩略图目录。
- `PlaybackSettings` 保存播放硬解、稳定进度默认起播、快捷键和全屏队列交互参数。
- `PlayerHardwareCompatibility` 把真实样本验证结论转成不可变预检结果；未知规格保持 unknown，UI 不得自行猜测硬解能力。
- `platform_interfaces.dart` 定义文件系统、播放器、FFmpeg/FFprobe、数据库 Provider 的跨平台接口边界。
- `layout_size.dart` 定义 `compact`、`medium`、`expanded` 共享布局语义，避免后续页面各自写死宽度规则。

core 类已使用独立 Dart library，并作为平台接口、Repository 与页面依赖的稳定基础。

### 仓储接口

职责：

- `LibraryRepository` 规划媒体库根目录、视频列表、单条 upsert、missing 标记等数据访问边界。
- `TagRepository` 规划标签组、标签、视频标签关系和 `folder/manual/rule/filename/import/auto` 来源写入边界。
- `CacheRepository` 规划缩略图与媒体信息缓存状态读写边界。
- `PlaybackRepository` 规划播放会话和播放位置持久化边界。

当前仅定义接口，不替换 `LibraryStore` 的 SQLite 实现，避免在 Architecture Chat 重写查询与扫描行为。

### 媒体库存储

职责：

- 保存根目录列表。
- 递归扫描视频文件。
- 维护 `Map<String, VideoItem>`。
- 根据文件夹生成一级标签和二级标签。
- 保存收藏、标签、媒体信息到 SQLite。

当前扫描边界：

- `LibraryScanService` 只遍历文件系统、识别视频扩展名、读取 stat、派生 folder 来源标签和轻量媒体指纹。
- `LibraryStore` 消费扫描结果，继续负责 `VideoItem` 内存状态、SQLite 写入、folder/manual 标签索引同步和持久化读写。
- manual 标签维护、用户收藏、播放记录和媒体缓存字段不由扫描服务直接修改。

标签规则：

```text
X:\test-media\原神\木偶\a.mp4
一级标签: 原神
二级标签: 木偶

X:\test-media\原神\b.mp4
一级标签: 原神
二级标签: 默认专辑
```

### 视频条目

职责：单个视频的领域对象。

包含：

- `path`：当前路径。
- `title`：显示标题。
- `folder`：来源文件夹。
- `tags`：一级标签兼容字段。
- `childTags`：二级标签兼容字段。
- `isFavorite`：收藏状态。
- `mediaFingerprint`：媒体指纹。
- `thumbnailError`：缩略图错误。
- `mediaDetailsError`：媒体信息错误。
- `addedAt / lastPlayedAt`：入库时间 / 最近播放时间。

### 缩略图服务

职责：缩略图缓存队列。

当前策略：

- 可见区域优先。
- 后台补全缺失缩略图。
- 可暂停队列。
- 优先使用 FFmpeg。
- FFmpeg 失败时回退 media_kit 截图。
- 后台排队有上限，避免一次性派发过多低优先级任务。
- FFmpeg 和 media_kit 兜底写入均先写临时文件，成功后替换缓存文件。
- 缓存 key 基于路径、文件大小、修改时间。

播放时会暂停缩略图队列，降低卡顿概率。

### 媒体信息服务

职责：读取和缓存媒体信息。

当前策略：

- 通过 `MediaProbeBackend` 使用原生探测，失败原因写入可重试状态。
- 可见项独立优先；后台条目以最多 8 条有限批次执行，原生侧仍保持单工作线程。
- 同一批结果由 Dart Repository 合并为一次 SQLite batch，避免大目录逐文件提交。
- 向媒体库和诊断页暴露总量、排队、执行中、本轮完成和失败数量。
- 缓存视频编码、音频编码、分辨率等。

### 媒体库页面

职责：主界面。

包含：

- 左侧目录、常用标签、标签筛选。
- 顶部搜索、排序、设置入口。
- 标签管理入口，可基于当前筛选结果执行批量 manual 打标签。
- 顶部二级标签横向条。
- 中间视频网格。

### 标签管理页面

职责：标签维护和批量打标签第一阶段入口。

包含：

- 查看 tag groups、tags、aliases 和来源使用数量。
- 搜索标签和别名。
- 创建 manual tag，编辑 displayName、aliases、hidden、favorite、sortOrder 和 group。
- 对当前媒体库筛选结果批量添加 manual 标签或移除 manual 标签。
- 删除和合并入口会先检查 `video_tags` 引用；第一阶段不执行硬删除或合并，folder 来源 tag 不允许直接硬删除。

当前选择规则：

- 常用标签单选。
- 标签筛选单选。
- 二级标签单选。
- 二级标签可再次点击取消。

### 播放页面

职责：播放页面。

包含：

- media_kit 播放器。
- 快捷键控制。
- 右键菜单：视频信息、诊断检查。
- 右侧播放列表。

当前页面拆分：

- `player_page.dart` 保留播放器生命周期、键盘快捷键、播放跳转和页面级状态协调。
- `player_context_panel.dart` 负责底部当前视频和筛选上下文摘要。
- `player_queue_sidebar.dart` 负责右侧筛选结果队列、队列定位按钮、队列项展示和队列可见性测试 helper。

快捷键：

- PgUp：上一个。
- PgDn：下一个。
- Home：第一个。
- End：最后一个。
- Esc：退出播放器。
- Alt + Insert：收藏 / 取消收藏当前视频。
- Ctrl + Shift + Delete：删除当前正在播放且已选中的视频。
- 鼠标侧键返回：退出播放器。

### 播放队列侧栏

职责：播放器右侧列表。

显示：

- 当前一级标签标题。
- 当前一级标签下的同级二级标签。
- 视频序号、缩略图、视频名、视频编码、分辨率、音频编码。

行为：

- 单击视频：选中。
- 双击视频：播放。
- 点击顶部二级标签：切换当前播放列表。
- 二级标签从完整一级标签源列表计算，不只来自当前过滤后的列表。

## 外部工具

Windows 内置工具位置：

```text
windows\tools\ffmpeg\bin\ffmpeg.exe
windows\tools\ffmpeg\bin\ffprobe.exe
windows\tools\sqlite\sqlite3.dll
```

构建后位置：

```text
build\windows\x64\runner\Debug\tools\ffmpeg\bin\ffmpeg.exe
build\windows\x64\runner\Debug\tools\ffmpeg\bin\ffprobe.exe
build\windows\x64\runner\Debug\sqlite3.dll
```

## 后续架构建议

第一阶段拆分已经完成，当前结构：

```text
lib/
  main.dart
  src/
    app/
      local_tag_player_app.dart
    composition/
      local_tag_player_bootstrap.dart
      local_tag_player_dependencies.dart
    core/
      app_paths.dart
      layout_size.dart
      playback_settings.dart
      platform_interfaces.dart
      tag_rules.dart
    models/
      video_item.dart
      media_details.dart
      platform_models.dart
    repositories/
      repository_interfaces.dart
    services/
      library_store.dart
      library_metadata_persistence.dart
      library_scan_coordinator.dart
      library_tag_maintenance.dart
      library_tag_persistence.dart
      library_video_persistence.dart
      external_media_tools.dart
      thumbnail_service.dart
      media_details_service.dart
    pages/
      library_page.dart
      player_delete_dialog.dart
      player_diagnostics_dialog.dart
      player_open_request_controller.dart
      player_playback_controller.dart
      player_page.dart
    widgets/
      library_widgets.dart
```
下一阶段建议在现有独立 library 边界上继续演进：

- 继续保护 `TagRules` 的独立 import 边界，以及目录派生标签与用户手动标签的来源隔离。
- 抽出 `LibraryRepository`，隔离 SQLite schema、查询和写入。
- 继续收敛 `LibraryStore` 剩余职责，在测试保护下再拆 tag usage 查询、schema/default groups 初始化和 legacy JSON 导入。
- 抽出 `MediaTools`，隔离 Windows FFmpeg/FFprobe 与移动端实现。
- 继续把 `AppPaths` 扩展为平台文件系统适配，避免服务层直接依赖平台路径。






## 2026-07-12 桌面全屏窗口状态边界补充

- 播放器全屏通过既有 `window_manager` 桌面边界切换，不把平台命令散落到业务数据层。
- `DesktopWindowStateService` 在全屏期间跳过尺寸快照，避免显示器尺寸污染普通窗口恢复状态。
- 本次未修改 `PlayerBackend`、SQLite schema、filtered queue 或标签查询契约。

## 2026-07-22 播放器 Route 全屏会话边界补充

- `DesktopWindowStateService` 继续只负责普通窗口尺寸和最大化持久化；播放器是否在下一次进入时恢复全屏由媒体库 Route 的内存态单独负责。
- 全屏播放器返回时必须在 Route pop 前退出系统全屏并最大化底层窗口，避免主界面或设置页继承全屏布局；该恢复动作不等于清除播放器全屏偏好。
- 普通窗口或最大化窗口没有播放器全屏事实时，不执行任何全屏退出或最大化命令；用户在播放器内主动退出全屏则清除会话偏好。

## 2026-07-24 Windows 纹理回调与窗口恢复边界补充

- `media_kit_video` 的 Flutter 纹理回调不得通过可变的全局 `texture_id_` 查找当前描述符；`RegisterTexture` 允许同步取帧，创建尚未入表或注销时 ID 已切换都会形成竞态。
- 每个 GPU/软件纹理回调捕获自己的稳定描述符地址，描述符所有权继续由对应 texture ID 的 map 保持到 `UnregisterTexture` 完成。项目只补丁化固定 SHA256 归档，禁止直接修改全局 Pub Cache。
- 压力测试通过 `PlayerPageState` 的测试专用入口调用按钮和快捷键共用的正式全屏状态机；该入口不复制窗口命令、会话语义或纹理逻辑，也不进入生产 UI。
- `DesktopWindowStateService` 当前只保存普通窗口尺寸与最大化状态，不保存坐标，因此恢复时必须居中。只有未来同时持久化并校验显示器内坐标后，才允许传入非居中恢复。
- 播放器 Route 退出与 Windows 宿主进程关闭是两条独立生命周期：前者通过页面压力门禁不代表后者安全。宿主关闭必须单独验证 registrar 销毁后不再有纹理线程调用 `FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable`。
- 本轮不改变 `PlayerBackend` contract、SQLite schema、标签查询、filtered queue、缓存队列或用户数据。

## 2026-07-28 Windows MPV 命令与渲染调度边界补充

- `PlayerBackend` 继续表达跨平台最小播放能力；`PlayerPropertyBatchBoundary` 是可选
  性能边界，只允许把有序属性快照合并为一次平台调用。未实现该接口的后端必须由
  `PlayerService` 按原顺序串行执行，不能改变属性语义。
- Windows 原生 MPV 的控制命令返回同一次 worker 执行后的状态快照，Flutter 不再为
  每条命令追加一次状态调用。属性批次只在最后一项执行完整 mpv 状态采样。
- libmpv update callback 仍只合并为一个待渲染标志；worker 在每条控制命令前优先
  消费该标志，防止属性或打开偏好突发饿死视频渲染。渲染上下文和所有 mpv 属性访问
  仍由同一原生线程拥有。
- Flutter Texture 路径继续使用 `d3d11va-copy` 与 ANGLE → D3D11 成品纹理复制；
  真正零拷贝或 NVIDIA 原生增强仍需独立 D3D11 surface 边界，不由批处理接口推断。
- 50/60fps copy-back 会话不自动启用 CPU 画质滤镜；低帧率会话的压力回滚锁存于
  当前媒体，打开新媒体时重置。两者都不写入 SQLite 或用户持久设置。
