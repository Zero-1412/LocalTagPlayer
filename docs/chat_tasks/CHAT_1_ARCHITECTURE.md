# CHAT_1_ARCHITECTURE.md

## 2026-07-30 应用内 Release 资产下载提速

- 更新功能继续位于 `features/update` 平台边界内；新增独立 Release 资产下载器，不把 GitHub、
  HTTP Range 或 Windows 安装包假设泄漏到媒体库与业务层。
- 下载器先用单字节 Range 探测服务端能力；支持时固定四段并行、聚合进度并按顺序合并，不支持时
  复用探测响应回退单流，避免重复请求完整资产。
- 分段使用独立临时文件，每段瞬时网络错误最多重试一次；全部任务结束后统一清理，合并长度与发布
  清单 SHA-256 均正确才允许启动安装包。
- 更新进度模型向后兼容地增加吞吐率与预计剩余时间；完成文件按版本和 SHA-256 复用。既有调用方、
  安装启动顺序、更新确认弹窗与发布清单 contract 保持不变。
- 四连接 CDN 样本约 463 KiB/s，单连接约 54 KiB/s；八连接出现 `ECONNRESET`，因此选择稳定的
  四连接默认值。Range/非 Range/重试、完成文件复用和弹窗状态均有确定性回归测试。
- schema、标签、过滤、filtered queue、PlayerBackend、缓存队列和用户数据未改变。

## 2026-07-29 渐进式整体架构重构第一阶段

- 架构基线提升到 `0.5.134`；`library_page.dart` 从 4293 行降到 750 行，页面外壳、
  九个协调 mixin、共享运行时/host 以及设置状态/展示边界均受 1000/500 行门禁保护。
  没有迁移筛选、扫描、队列、缓存或用户数据的业务 owner。
- 前一批架构基线 `0.5.133` 的完整审计和 Phase 0-6 路线记录在
  `docs/architecture/ARCHITECTURE_REFACTOR_2026_07_29.md`。
- `main.dart`、bootstrap 组合根与 Flutter 应用壳已经分离，具体实现选择仍只发生在
  composition。
- 更新功能成为首个 `features/<name>/{domain,data,presentation}` 样板；页面不再创建
  GitHub 客户端。
- 网页端独立评审已完成，采纳版本化 Result/Count/Queue 快照、原子写入归应用服务、
  native 资源唯一 owner 和 `LibraryStore` 证据驱动拆分，详见
  `docs/architecture/ADR_001_PROGRESSIVE_ARCHITECTURE_MIGRATION.md`。
- 设置首页导航已作为无状态叶节点迁入 `features/settings/presentation`，原页面继续拥有
  设置状态和 Route；所有入口 Key 与回调保持不变。
- Phase 1.5 已建立旧交互挂载清单、测试期查询追踪、11,000 项确定性 fixture，以及
  Result/Count/Queue 版本化快照；现有筛选与计数发布链路已拒绝旧 epoch。
- Phase 2A-2 先迁移缓存诊断标题/健康状态纯展示叶节点；统计 Future、刷新、失败重试和
  清理命令仍由原页面唯一拥有。
- Phase 2A-2 随后完成其余只读快照展示迁移；动作区以 Widget 槽位注入，确保 feature
  presentation 不持有缓存命令或异步生命周期。
- Phase 2B 将普通 `PlaybackSettings` 收口到单一 controller；按操作顺序串行保存，只把
  最新失败回滚到最后成功快照。备份、缓存、Route 和平台资源继续由原 owner 管理。
- Phase 2C 将缓存统计读取收口到泛型 latest-only controller；错误态安全展示，重试、
  清理、Repository 写入和互斥命令继续留给 Phase 2D。
- Phase 2D 将现有重试/清除和 Repository 写入收口到泛型维护 controller；清除写入失败
  恢复原错误。源码没有缓存删除/重建入口，因此未新增破坏性操作。
- Phase 2E 将备份设置、状态订阅与维护互斥收口到独立纵向切片；运行态回滚、数据库
  检查和导出平台边界不变。源码没有主库替换或导入恢复入口，因此未新增破坏性流程。
- Phase 3A/3B 分离结果数据/标签定义修订，并把 stable-ID 多选和三项纯展示偏好迁入
  application owner；筛选、排序、计数、队列、扫描和批量删除命令仍由原边界拥有。
- Phase 3C 将字段、方向、fingerprint 与纯内存重排迁入单一排序 owner；页面继续负责
  偏好持久化和发布已接受结果。真实页面回归证明排序不调用完整计数且不改变 stable-ID
  成员，筛选、队列与扫描边界未迁移。
- Phase 3D 将筛选/搜索请求、结果缓存与 latest-only 发布归 query owner，将当前候选和
  全库稳定计数归 facet owner；二者互不写入，页面继续保证先发布视频、后延后计数。
- Phase 3E 将已接受 ResultSnapshot 固化为 filtered queue 的唯一来源；stable-ID 成员
  和顺序不一致时拒绝，生产 PlayerPage 同时接收不可变 playlist 与 queue epoch 快照。
- Phase 3F 将扫描 operation、Repository generation、路径检查与媒体解析 latest-only
  状态归单一泛型 owner；实际限流、扫描事务、标签语义和媒体服务仍在原边界。
- Phase 3G-1 将定位、改名、单条/批量删除迁为显式 command；改名补偿与删除顺序集中
  到无 UI executor，确认、偏好、反馈和页面刷新继续留在原 presentation。
- Phase 3G-2 将单视频 manual 标签替换迁为显式不可变 command；locked folder、当前
  一级父级与失败补偿集中到无 UI executor，Repository 失败同步恢复关系和新建索引，
  主库成功后的备份故障只进入诊断；Tag Manager、确认、反馈与刷新仍留在原 owner。
- Phase 3G-3 将单条 Missing/Relink 迁为 stable identity/path/fingerprint 快照 command；
  过期/重复提交被拒绝，Repository 失败恢复同一对象和路径/标签索引，picker、反馈、
  播放器入口与批量路径替换保持原 owner。
- Phase 3H-1 将继续观看清理/撤销快照、批量提交与失败补偿迁入无 UI executor；最近
  播放临时选择改为 stable videoId，确认、10 秒撤销、反馈和刷新继续留在 presentation。
- Phase 3H-2 将四类结果来源、当前本地路径和 LIFO 返回栈迁入纯应用 owner；页面注入
  平台路径策略，并继续拥有筛选清理、Route、动画、入口挂载和 filtered queue 绑定。
- Phase 4A 将播放器队列和索引迁入 stable-ID 驱动的纯应用会话 owner；只读视图和
  已接受队列快照校验阻止 Store/path 重建，页面继续唯一拥有 backend 与原生资源。
- Phase 4B 将 open 意图迁为 revision/stable-ID/path 快照，并由纯事件 bridge 统一
  持有四类 backend Stream；页面仍解释交互，释放顺序和 backend contract 不变。
- Phase 4C-1 将控制条/快捷键反馈状态和两只 Timer 迁入纯应用 owner；Focus、Overlay、
  全屏队列与播放器资源保持页面 owner。
- Phase 4C-2 将快捷键暂停与处理/焦点恢复资格迁入纯 owner；Flutter 环境探测仍在页面。
- Phase 4D 将全屏状态/窗口命令顺序迁入纯 controller，并用单一资源协调器拥有
  Texture listener、事件取消、stop、dispose 与 released；页面不再直接释放原生资源。
- Phase 4E 将诊断快照迁入 player domain；弹窗只消费状态流与采样回调，不再持有
  PlayerPageState/PlayerService。Phase 4 播放器 MVVM 完成。
- Phase 5 将媒体库只读查询与写入/运行时命令拆为两个能力接口；facade 分别依赖窄端口，
  composition 仍注入同一 `LibraryStore`，跨表 batch、稳定身份、备份补偿和用户数据
  不变。事务亲和度证据不支持当前物理拆分 Store。
- Phase 6 将 16 个单元测试和 9 个 integration test 改为具体模块 import，并删除消费者
  归零的 `src/app.dart`；架构合同禁止 production/test/integration_test 回退万能导出。
- 后续瘦身对齐 Effective Dart、Flutter 职责分离与 Google 小变更原则，并增加项目本地
  200/500/1000 行分级门禁；首批把最近播放与标签编辑拆成独立叶节点，
  `library_widgets.dart` 从 4577 行降到 3819 行并移除无关播放/缓存依赖。
- 第二批抽出 sidebar 通用条目、左右面板转场与 top bar 结果视图切换器，聚合文件继续
  降到 3348 行；全部 8 个 1000+ 行 presentation 文件进入有序强制治理清单。
- 第三批把 sidebar 容器/折叠轨道/品牌区/滚动行为与 top bar 搜索/筛选状态拆为
  418/213/121/16/241/464 行组件，`library_widgets.dart` 降到 1917 行；随后从
  `library_page.dart` 迁出 367 行播放后端设置叶节点，页面由 5747 行降到 5391 行。
- 搜索 controller、筛选状态、导航回调、播放设置确认/撤销和页面挂载路径均保持原 owner；
  schema、标签筛选、filtered queue、缓存队列和用户数据不变。
- 第四批把原始码流缓存、播放画质/流畅度、删除设置和缓存失败状态迁为
  47/371/165/158 行 settings presentation 叶节点，`library_page.dart` 预算从
  5391 行降到 4686 行；页面继续唯一拥有导航、controller、持久化和维护命令。
- 第五批把“播放与解码”主卡及全屏队列/快捷键展示区迁为 98/168 行叶节点，
  `library_page.dart` 预算继续降到 4487 行；展示层只接收快照与回调，controller、
  后端确认/撤销、快捷键冲突校验、持久化和业务命令仍由页面唯一拥有。
- 第六批把设置 Route 外壳和缓存诊断卡装配迁为 82/69 行叶节点，
  `library_page.dart` 预算继续降到 4443 行；section 状态、缓存 controller、维护命令、
  Repository 写入和反馈仍由页面唯一拥有。
- 第七批把标签 helper、选择工具栏、顶栏附件控件和 focused harness 迁为 200 行内
  叶子，`library_widgets.dart` 从 1917 行降到 962 行；随后迁出添加标签与两类确认
  对话框，`library_page.dart` 预算降到 4293 行。所有命令 owner 与数据语义保持原位。
- focused 261 项、完整 451 项测试（3 项显式基准跳过）、静态分析、Windows Debug
  构建和打包启动门禁通过；真实点击受 Computer Use 原生管道不可用阻塞。
- 后续按一致性边界迁移无状态诊断 UI、普通设置、媒体库和播放器；禁止一次性移动全部
  文件或改变现有业务语义。

## 2026-07-24 正式打包分支集成边界

- 发布入口统一以 `origin/master` 当前提交为基线，禁止验证一个提交却打包另一个提交。
- 全部远程开发分支必须已经成为主线祖先或达到补丁等价；未集成分支只在临时 Worktree 中累计试合并，用于发现分支间冲突，不会绕过代码审查直接产出安装包。
- Windows 与 macOS 正式包共同依赖 Windows 门禁完成全量测试、静态分析、Debug 构建和启动存活检查。
- SQLite、标签查询、filtered queue、PlayerBackend、缓存队列和用户数据边界均未改变。

## 2026-07-24 GitHub 正式版更新边界

- 应用版本提升为 `0.2.0+2`，以 `pubspec.yaml` 作为安装包和运行时版本来源。
- 新增独立 `AppUpdateService` 与 GitHub Releases 实现；首帧后异步检查公开正式 Release，远端版本更高时展示 Release 正文和 Windows 安装器入口。
- 网络错误、离线或 GitHub 限流保持静默，不阻塞媒体库启动，不进入 SQLite、标签、播放器或缓存边界。
- 发布工作流继续以 `vX.Y.Z` 标签创建 Release；更新弹窗只认 Release，不把普通 commit 误报为可安装更新。

当前版本：`0.5.28`
状态：已完成页面依赖收窄并接入 macOS/Linux runner

## 2026-07-14 页面应用服务与跨平台 runner

- `LibraryPage` 不再持有完整 `LocalTagPlayerDependencies`，只消费页面用例服务、文件系统 contract 和转交播放器路由所需 factory。
- 组合根集中创建 `LocalLibraryPageApplicationService`，拥有 AppPaths、Repository loader、FFmpeg、媒体探测 factory 与 debug 配置。
- macOS/Linux Flutter runner 与 CI build/start smoke 已接入；平台 adapter 选择在对应宿主 contract test 中验证。
- GitHub Actions run `29324080724` 已验证 macOS/Linux adapter、静态分析、debug build 与 10 秒启动存活 smoke 全部通过。
- SQLite schema/写入、FilterQuery/TagQueryService、stable identity、filtered queue 与缓存队列继续由 Dart 单写和编排。

## 2026-07-14 全量 library 边界收口

- 57 个 `part` / `part of` 已清零，Store、播放器/缩略图、应用服务与页面/widgets 已按依赖方向迁为独立 import。
- `LocalTagPlayerDependencies` 独立为组合根 contract，页面业务入口继续是 `LibraryApplicationFacade`，平台能力继续通过 adapter/backend 接口注入。
- SQLite schema/写入、标签筛选、stable identity、filtered queue 与缓存队列语义保持在 Dart；Rust/C++ 边界未扩大。
- contract/fake tests 增加零 `part` 守卫；macOS/Linux 构建仍需对应宿主验证。

当前版本：`0.5.26`
状态：进行中
负责人：Chat 1 / 架构与跨平台边界

## 2026-07-14 第二批边界迁移

- 实例化 AppPaths 并落地 DatabaseProvider，Store 不再选择 factory 或数据库路径。
- facade 使用只读集合和明确命令，Tag/Cache/Playback repository 接入同一 Dart SQLite writer。
- 移除静态媒体工具、窗口单例与旧位置 service，debug 环境和诊断写入退出页面。
- 57 个 part 已消除 22 个，剩余 35 个按 Repository/平台→应用服务→页面继续。

## 规划来源

主要来源：

```text
<private-planning-document>
```

如果本文档与该文件冲突，以外部规划为准。

## 范围

负责项目架构、模块边界、跨平台路线、平台接口、本地规则和架构基线版本。

允许：

- `main.dart` 结构、`part` / 未来 import 边界。
- `app/`、`core/`、`models/`、`platform/`、`repositories/` 接口规划。
- 核心模型和共享契约。
- `FileSystemAdapter`、`PlayerBackend`、`FFmpegBackend`、`DatabaseProvider`。
- `LibraryRepository`、`TagRepository`、`CacheRepository`、`PlaybackRepository` 接口规划。
- `LayoutSize`：`compact`、`medium`、`expanded`。
- 架构文档和版本规则。

禁止：

- 重写播放器行为。
- 重写 SQLite 查询逻辑。
- 重写缩略图队列。
- 大范围 UI 重设计。
- 实现 Tag Manager 功能逻辑。

## 已采用任务

P0 / P1：

- 让 Architecture 对齐外部跨平台规划，而不是旧项目惯性。
- 维护已完成的 `Architecture Baseline 0.3.1`。
- 维护已完成的 `Architecture Baseline 0.4.0` 仓储 / 布局边界基线。
- 为低风险 import 迁移和逐步采用 `0.4.0` 契约准备 `Architecture Baseline 0.4.1`。
- 保证标签查询 / 筛选逻辑保持平台无关。
- 保证文件系统、播放器、FFmpeg/FFprobe、数据库位置规则位于平台边界后。
- 在 `ARCHITECTURE.md` 记录每次共享边界变更。

## 新对话提示

```text
这是 Chat 1 / 架构与跨平台边界。项目路径：<project-root>。
请先阅读：
- PROJECT.md
- ARCHITECTURE.md
- CURRENT_TASK.md
- ROADMAP.md
- <private-planning-document>
- docs/chat_tasks/CHAT_1_ARCHITECTURE.md

后续方向以 local_tag_player_flutter_cross_platform_plan_v2.md 为准；当前项目实现只代表历史状态。
职责：负责 main.dart 拆分、模块边界、平台接口、repository 接口、跨平台路线和架构版本记录。
不要重写播放器行为、SQLite 查询、缩略图队列或做大范围 UI 重设计。
当前目标：推进 Architecture Baseline 0.4.1，做低风险 import 迁移或逐步采用 0.4.0 契约。
修改代码后运行：
- flutter analyze
- flutter build windows --debug
```

## 变更记录

- `0.5.25`：实现并接入 `DesktopFileSystemAdapter`；`LibraryStore` 落地为实际 `LibraryRepository`，页面统一依赖 `LibraryApplicationFacade`；具体 backend/repository 工厂移入 bootstrap composition root。文件系统模块、`LayoutSize`、`MediaDetails` 首批脱离 `part`，其余模块继续按依赖顺序渐进迁移。

- `0.5.24`：Windows 原生依赖使用临时文件下载、固定 SHA256 校验、原子落盘和最多三次重试；mpv/ANGLE 的项目校验副本直接提供给 media_kit 插件，避免 Android Studio/CMake 重复下载与坏缓存连锁失败。
- `0.5.23`：为文件较多的一级模块增加职责二级目录；`pages` 分为 library/player/tags，`services` 分为 library/media/player/relink/tags/window，`widgets` 的媒体库组件归入 library。继续保留单一 `app.dart` part library，不改变业务或平台边界。
- `0.4.1`：为后续低风险 import 迁移和逐步采用 `0.4.0` 契约开启下一轮架构基线。
- `0.4.0`：按 `local_tag_player_flutter_cross_platform_plan_v2.md` 重定架构职责，新增 repository 接口 stub、共享 `LayoutSize` / `LayoutBreakpoints`，扩展平台边界方法，并扩展 tag/filter/playback 模型 stub，同时保持 Windows 行为不变。
- `0.3.0`：新增 `FileSystemAdapter`、`PlayerBackend`、`FFmpegBackend`、`DatabaseProvider` 接口 stub 和平台无关 tag/filter/playback/cache/diagnostic 模型 stub，不改变 Windows 行为。
- `0.2.0`：新增 core 边界文档、多 Chat 协作和 roadmap 归属规则。
