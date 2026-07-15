# ARCHITECTURE.md

## 总览

架构路线以以下规划文件为准：

```text
<private-planning-document>
```

当前代码结构是过渡实现，不再作为后续功能优先级的主导依据。后续架构重构必须服务该规划中的 Tag 驱动检索闭环：分组 Tag、组合筛选、筛选结果播放队列、Tag 管理、缓存诊断和跨平台边界。

`Architecture Baseline 0.5.29` 已在全部 Dart `part` 清零后继续收窄页面边界。Store 私有持久化协作、播放器与缩略图实现、应用服务、页面和 widgets 现在都是具有显式 import 的独立 library；`LibraryPage` 只接收页面级应用服务和必要的平台 contract，不再遍历完整组合根依赖图。

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

已完成基线：`Architecture Baseline 0.5.29`

当前推进中：通过 macOS/Linux runner 持续验证 adapter、原生构建和启动；不扩大 SQLite 双写边界或改变业务语义。

变更点：

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

- 优先使用 FFprobe。
- 失败时回退 media_kit。
- 读取队列串行执行，并向诊断页暴露排队、执行中、本轮完成和失败数量。
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
    app.dart
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
