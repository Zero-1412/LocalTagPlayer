# ROADMAP.md

## 2026-07-16 视频依赖独立备份完成

- 默认开启独立 SQLite 备份，覆盖稳定身份、收藏、播放状态与非 folder 标签；视频文件、缩略图和媒体详情缓存不重复复制。
- 全量游标和增量队列可跨重启续跑，播放器会话期间暂停；root detached 与显式单视频删除保持不同的快照生命周期。
- identity 重建后的自动恢复采用扫描侧/备份侧 fingerprint 双侧唯一保护，歧义文件不自动合并。
- 下一步在不读取媒体文件的前提下增加备份库完整性检查与可选导出位置，并评估按变更摘要减少每次启动的全量核对写放大。

## 2026-07-16 root detached 身份保护完成

- root 移除不再硬删 SQLite 视频行和标签关系；新增 detached 状态把“是否由当前目录管理”与 missing、stable identity 和用户数据解耦。
- 重新添加相同目录按 path 恢复，目录或文件移动后按唯一 fingerprint 恢复；收藏、手动标签、播放进度、媒体详情和缓存继续绑定原 videoId。
- detached 不进入常规筛选或 filtered queue，过期媒体探测不能把它重新激活；标签管理保留归档引用以防误删。
- 下一步为 detached 归档提供只读数量与显式“永久清理归档”入口，危险清理必须再次确认并默认不执行。

## 2026-07-15 冷扫描阶段进度与播放资源协调

- 目录发现与 fingerprint 已拆分：总量未知时只显示发现数，候选确定后使用确定型进度、速度和 ETA；真实冷启动阶段耗时继续写入隐私安全 JSONL。
- 播放期间自动暂停只读扫描并在退出后原位恢复，优先保护视频解码和 UI 输入；不通过继续提高媒体探测并发掩盖机械盘瓶颈。
- 11,163 项热缓存强制 fingerprint 对照为发现 24ms、校验 1,444ms、首次提交 1,995ms；下一步在重启后真实冷盘使用中继续收集 HDD/SSD 多轮样本，再决定是否需要进一步调整 fingerprint 读取布局。
- SQLite schema、stable identity、标签过滤、filtered queue 与 PlayerBackend 均保持不变。

## 2026-07-15 大目录导入分阶段进度与批量媒体解析

- 大目录添加先显示“正在发现并校验视频”；扫描提交后视频列表立即可筛选、滚动和播放，同时在当前筛选结果区显示媒体信息已处理数/总数和百分比。
- 媒体详情从逐文件原生调用、逐文件 SQLite upsert 改为最多 8 条有限批次；可见卡片仍独立优先，新扫描会取消旧探测，避免扫描与后台解析争抢磁盘。
- 完成或失败均计入已处理进度，全部结束后自动恢复“全部视频 · xx 个结果”；异常文件继续保留失败原因和重试入口。
- SQLite schema、stable identity、`FilterQuery` / `TagQueryService`、filtered queue 和缩略图队列语义不变。

## 2026-07-15 媒体库文件导入与目录删除入口

- 空媒体库中央提供大号“添加视频文件”入口，系统选择器支持多选；媒体库结果区支持从资源管理器拖入视频或目录，并在悬停时显示明确释放反馈。
- 文件父目录与拖入目录先归并为最上层 root，已受现有 root 覆盖的文件只重新扫描；Repository 批量注册全部新 root 后只执行一轮扫描，避免大媒体库重复遍历。
- 目录管理删除与左侧 root 移除复用同一协调入口；当时采用移除索引、关系和缓存但不删除磁盘视频的策略，现已由 2026-07-16 的 detached 身份归档策略取代。

## 2026-07-14 页面依赖收窄与跨平台 runner

- `LibraryPage` 已从完整组合根依赖图收窄为页面级应用服务、文件系统 contract 和播放器路由所需 factory；路径、FFmpeg、Repository 及 debug 配置不再暴露给页面。
- macOS/Linux runner、平台 media_kit 库与 GitHub Actions build/start smoke 已接入；对应宿主会执行 adapter contract、debug build 和启动存活检查。
- SQLite schema/写入、标签筛选、stable identity、filtered queue 与缓存队列继续由 Dart 业务层统一拥有。

## 2026-07-14 独立 Dart library 迁移完成

- 57 个 `part` / `part of` 已全部清零；Store 私有协作、播放器与缩略图实现、应用服务、页面和 widgets 均使用显式 import。
- 组合根依赖图、Repository/facade 和平台 adapter 均有独立 contract/fake 测试；架构测试阻止重新引入 `part`。Windows analyze/build、96 项测试与真实窗口标签/目录 smoke 已通过。
- 下一步聚焦收窄 `LibraryPage` 对组合根依赖图的使用，并在 macOS/Linux 宿主执行构建与 adapter 验证；SQLite、标签筛选和 stable identity 继续由 Dart 单写拥有。

## 2026-07-14 独立 Dart library 迁移第二批完成

- `part` 从 57 降至 35；领域模型/契约、DatabaseProvider、扫描与媒体平台边界、播放辅助和窗口服务已独立。
- 下一批先拆 Store 的 metadata/tag/scan coordinator 私有协作，再拆播放器实现，最后处理页面与 widgets。
- macOS/Linux adapter 已接入组合根；对应 build 必须在各自宿主 runner 验证。

## 2026-07-13 SQLite hydration 与 Rust 扫描边界完成

- 分阶段诊断确认约 40 秒并非普通 SQLite 查询或对象 hydration，而是启动维护中的无条件 NOCASE 相关回填；修复后真实副本加载低于 1 秒，真实窗口首帧约 1.42 秒。
- Rust `LibraryScanBackend` 已作为 Windows 只读 sidecar 接入，运行时失败回退 Dart；SQLite 仍由 Dart Repository 单写，不引入双端 migration/transaction 风险。
- 父子 root 重叠按最上层 root 和 pathKey 去重；首次提交把历史 root 上下文统一到当前文件树，第二轮 11,133 条稳定态端到端 240 毫秒且零差量。
- 下一步只在真实 NAS/掉盘环境评估 watcher 事件丢失与周期性全量 reconciliation；在证据出现前不让 watcher 直接标记 missing，也不迁移 SQLite 或标签查询到 Rust。

## 2026-07-13 原生核心服务渐进路线决策

- D3D11/ANGLE 最终调查未达到 Private/GPU P95 为 MediaKit 110% 以内的门槛，默认播放器继续使用 MediaKit，C++ 播放器只保留实验 A/B，不继续扩大剩余生命周期改造。
- Windows 原生核心先落地独立 `MediaProbeBackend`，使用 FFmpeg C API 批处理与 generation 取消；SQLite、标签查询和用户数据继续由 Dart Repository 独占。
- 该阶段“暂不引入 Rust”的结论已被后续 hydration 修复与稳定态 A/B 更新：Rust 仅作为可回滚只读扫描边界接入，SQLite 单写和用户数据所有权不变。

## 2026-07-13 Windows 原生播放器 A/B 第一阶段完成

- 已固定供应 libmpv/ANGLE、补齐许可证，并贯通单会话、共享纹理、串行命令和原生诊断。
- 同媒体短测证明原生链路可播放、可 seek、可退出且无音视频停滞，但 GPU committed 峰值未优于默认 MediaKit，暂不切换生产默认值。
- 已完成同一 4K 长视频三组 480 秒分阶段 A/B，并收敛动态纹理、渲染判定和缓存预算；原生 CPU/工作集有收益，但 Private/GPU committed 仍高于 MediaKit，暂不切换默认后端。
- 下一步只调查一次额外 D3D11/ANGLE device context 与驱动 committed 来源；若 Private/GPU P95 无法进入 MediaKit 的 110% 以内，则停止默认替换路线，仅保留实验后端。

## 2026-07-12 窗口恢复、快捷键设置与统一 UI 完成

- 桌面窗口恢复上次尺寸和最大化状态，状态通过平台边界写入独立 JSON。
- 播放器快捷键提示迁入设置页，可修改并在冲突时交换绑定；播放器页面不再常驻提示栏。
- 统一全局 Dialog、PopupMenu、Menu、BottomSheet 和 SnackBar 视觉；播放器使用独立暗色主题。

## 2026-07-12 设置页信息架构增强完成

- 继续观看改为默认行为设置，减少逐条打开弹窗；默认直接恢复，保留从头和每次询问。
- 常用解码策略与高级具体后端分层，缓存统计改为可直接判断完成度和队列状态的数字列表。
- 下一步保持功能冻结，观察用户是否需要调整默认恢复行为或进入高级解码选项。

## 2026-07-11 第四阶段轻量播放体验完成

- 在不改变 filtered queue 来源的前提下提供随机、单曲循环和列表循环，默认顺序播放仍在队尾停止。
- 提供有限倍速档位和少量高频快捷键；全屏仅保留必要的队列上下文与标签入口。
- 字幕、音轨等专业播放器能力不预建，等待真实用户反馈和使用证据。

## 2026-07-11 批量 Relink 审计与失败恢复完成

- 已完成预览搜索、隐私安全审计摘要、SQLite 批事务提交和失败项定向重试。
- 已完成预览后目标消失→失败保留→文件恢复→同一预览重试成功的 focused test。
- 下一步：导出结构化审计文件、为超大批次增加分段事务上限，并接入诊断页历史记录。

## 2026-07-11 跨盘迁移与快照队列完成

- 已完成 C:→E: 20 条隔离媒体 soak，以及批量路径前缀替换预览/确认执行。
- 已完成播放快照按 videoId 合并与串行落库，离开播放器前保证 flush。
- 下一步：为批量预览增加搜索/导出审计摘要，并评估 SQLite 事务批量提交与失败重试策略。

## 2026-07-11 Stable Video Identity 播放状态第三阶段完成

- 已完成位置、总时长、完成态的 videoId 持久化，以及继续/从头选择。
- 已将最近播放升级为带进度的继续观看，并完成短视频动态完成阈值。
- 已补齐队列 missing 状态与播放器内 Relink，移动/重命名后继续沿用稳定用户数据。
- 下一步：真实跨盘迁移长时间 soak、批量路径替换预览和播放快照写入合并队列。

## 2026-07-11 Missing/Relink 用户闭环第一步

- 已完成 missing 条目可见列表和经过 fingerprint 校验的单文件 relink。
- 已完成播放器标签编辑键盘导航和 50,000 条当前队列性能基准。
- 下一步：批量路径前缀替换预览、冲突逐项确认、missing 搜索/排序和 relink 审计摘要。

## 2026-07-11 标签播放器差异化第二阶段完成

- 播放器内可完成收藏、manual 标签搜索/新增/移除，并快速使用最近和收藏标签。
- folder 标签只展示路径来源，不允许在播放器中删除。
- 当前队列支持轻量搜索定位；不扫描全库、不改变 filtered queue。
- 文件位置入口已进入桌面平台边界；下一步继续补 missing/relink UI 与播放器标签操作的真实大库耗时采样。

## 2026-07-11 Stable Video Identity 第一阶段完成

- 已完成 `videoId + fingerprint + mutable path` 兼容迁移，旧数据库无需清空。
- 已完成扫描期唯一 fingerprint 自动 relink、歧义拒绝合并和 missing 保留。
- 已完成标签、收藏、最近播放与播放进度随稳定 videoId 保留。
- 下一阶段：提供 missing 列表、单文件手动 relink 与批量路径前缀替换 UI；在真实跨盘目录迁移上补大库性能与冲突审计。

## 规划基准

产品和架构规划以此文件为准：

```text
<private-planning-document>
```

如果本项目文档与旧实现习惯冲突，以跨平台规划文件为准。当前应用状态只代表历史实现，不代表产品方向。

本项目不是 PotPlayer / VLC 替代品。目标是：

```text
标签驱动的本地视频发现播放器
= 本地扫描
+ SQLite 媒体库
+ 多级标签和分组标签
+ 标签别名搜索
+ 网页式筛选体验
+ 筛选结果播放队列
+ 基础播放器
+ 缓存和诊断
+ Flutter 跨平台壳
```

## 核心闭环

所有后续任务都要保护这条闭环：

```text
扫描本地文件夹
-> 派生初始文件夹标签
-> 添加 / 编辑播放器自有标签
-> 区分 folder / manual / rule / filename / import / auto 标签来源
-> 按分组标签和关键字筛选
-> 展示当前筛选 chips 和结果数量
-> 使用筛选结果作为播放队列
-> 播放器消费当前队列
-> 通过标签管理器 / 批量打标修正标签
-> 保持缩略图、媒体信息和诊断稳定
```

## 当前阶段非目标

当前阶段不要把主要精力放在：

- 字幕、音轨、逐帧、A-B loop、滤镜、旋转、高级播放控制。
- 标签发现体验稳定前的过度动画或纯视觉重设计。
- Web 支持。
- 深度 Android / iOS 支持。
- Windows 桌面行为稳定前替换当前桌面应用。

## 架构基线

已完成基线：`Architecture Baseline 0.5.25`

当前目标基线：`Architecture Baseline 0.5.26`

已完成 `0.5.25` 范围：

- `DesktopFileSystemAdapter` 已替换页面的生产文件操作，并把本地目录枚举移出 Widget build。
- `LibraryStore` 已实现真实 `LibraryRepository`，页面通过 `LibraryApplicationFacade` 发起用例。
- 具体文件系统、扫描、媒体探测、播放器和 FFmpeg 实现由 bootstrap composition root 统一选择。
- 文件系统模块、`LayoutSize`、`MediaDetails` 已迁移为独立 import；剩余 `part` 按依赖方向继续迁移。
- SQLite、标签筛选、stable identity、用户数据写入继续由 Dart 独占，不迁往 Rust/C++。

已完成 `0.3.0` 范围：

- 新增 `FileSystemAdapter`、`PlayerBackend`、`FFmpegBackend`、`DatabaseProvider` 轻量接口 stub。
- 新增平台无关的 `TagGroup`、`TagItem`、`FilterQuery`、`PlaybackSession`、`CacheStatus`、`DiagnoseStatus` stub。
- 保持当前 Windows 行为不变。
- 保留当前 `part` 结构作为过渡状态。

已完成 `0.3.1` 范围：

- 在平台无关标签模型中增加标签别名。
- 在 `FilterQuery.matches` 中增加分组 / 排除标签语义。
- 定义不同组 AND、同组 OR、排除 NOT 的匹配行为。
- 让现有媒体库筛选经过 `FilterQuery`，同时保持当前 Windows 行为。

已完成 `0.4.0` 范围：

- 让接口契约对齐跨平台规划，而不是当前实现惯性。
- 新增或细化 `LibraryRepository`、`TagRepository`、`CacheRepository`、`PlaybackRepository` 边界。
- 增加 `compact`、`medium`、`expanded` 共享布局语义。
- 细化 `FileSystemAdapter`、`PlayerBackend`、`FFmpegBackend`、`DatabaseProvider` 契约，不替换当前 Windows 实现。
- 评估导入迁移风险后，继续把 `part` 作为当前过渡结构。
- Architecture 阶段不重写播放器行为、SQLite 查询行为、缩略图队列行为或 UI 流程。

## 必须保持的平台边界

`FileSystemAdapter` 负责：

- 选择目录。
- 检查文件是否存在。
- 递归扫描视频。
- 在文件管理器中定位。
- 路径规范化和相对路径规则。

`PlayerBackend` 负责：

- 打开、播放、暂停、跳转、停止和释放。
- 播放状态流。
- 诊断状态流。
- 平台播放器实现细节。

`FFmpegBackend` 负责：

- 定位 FFmpeg / FFprobe。
- 可用性和版本报告。
- 媒体探测。
- 缩略图生成。
- 平台相关可执行文件或库访问。

`DatabaseProvider` 负责：

- 数据库打开和关闭。
- 数据库文件位置。
- schema 版本。
- migration 分发。

平台无关代码不能依赖 Windows、mpv、FFmpeg 可执行文件或具体文件系统 API。

## 标签发现设计

不要止步于当前一级 / 二级文件夹标签树。它只能作为初始来源，后续要建设分组标签。

推荐分组：

```text
作品：原神 / FGO / 东方 / 崩坏三
角色：丽莎 / 雷电将军 / 丝柯克 / miku
类型：3D / MMD / mod / vtuber
来源：Iwara / B站 / 本地录制
质量：720p / 1080p / 4K / H264 / H265
状态：收藏 / 未播放 / 已播放 / 缩略图异常 / 视频信息异常
```

筛选语义：

```text
不同组：AND
同组：OR
排除标签：NOT
关键字：文件名 / 路径 / 标签名 / 标签别名
```

示例：

```text
作品 = 原神
AND (角色 = 丽莎 OR 雷电将军)
AND (类型 = 3D OR MMD)
AND NOT NTR
```

## 目标模型

`TagGroup` 应逐步包含：

- `id`
- `name`
- `displayName`
- `sortOrder`
- `allowMultiSelect`
- `defaultLogic`：`sameGroupOr` 或 `sameGroupAnd`

`TagItem` 应逐步包含：

- `id`
- `name`
- `displayName`
- `groupId`
- `parentId`
- `color`
- `aliases`
- `usageCount`
- `isFavorite`
- `isHidden`
- `sortOrder`

`FilterQuery` 应逐步包含：

- `keyword`
- `includeTagIds`
- `excludeTagIds`
- `selectedGroupTags`
- `sortRule`
- `favoriteOnly`
- `unplayedOnly`
- `errorOnly`

`PlaybackSession` 应逐步包含：

- `sourceFilter`
- `queue`
- `currentIndex`
- `currentVideoId`
- `createdAt`

## 媒体库首页

媒体库首页是标签发现页，不是扁平标签浏览器。

推荐布局：

```text
顶部：搜索文件名 / 路径 / 标签 / 别名
左侧：分组标签筛选栏
中上：当前筛选 chips + 结果数量 + 清空 + 保存智能列表
中部：视频卡片网格
```

必须支持：

- 分组标签筛选。
- 当前筛选 chips，例如 `[原神 x] [丽莎 x] [3D x] [-NTR x]`。
- 每个标签的数量。
- 清空筛选。
- 排除标签。
- 保存当前筛选为智能列表入口。
- 当前筛选结果作为播放队列。

响应式规则：

```text
expanded：常驻左侧筛选栏
medium：可折叠筛选栏
compact：Drawer / BottomSheet 内筛选
```

## 播放页

播放器消费当前筛选结果，不应优先演变成通用专业播放器。

必须支持：

- 右侧队列绑定当前 `FilterQuery` / `PlaybackSession`。
- 当前序号显示，例如 `1/1661`。
- 队列标题或摘要展示当前筛选。
- 返回媒体库时不丢失筛选状态。
- 从右侧队列切换视频。
- 稳定的视频信息入口。
- 稳定的播放诊断入口。
- 后续可复制诊断信息。
- UI 依赖 `PlayerBackend`，不依赖具体播放器内部实现。

当前不优先：

- 字幕。
- 音轨。
- 逐帧。
- A-B loop。
- 滤镜。
- 复杂画面比例控制。

## 文件夹标签与稳定身份

保留当前文件夹派生的一/二级标签，但把它们视为初始 `folder` 来源标签。

目标身份模型：

```text
videoId = 稳定数据库身份
fingerprint = 文件 / 媒体身份
path = 当前可变位置
```

视频标签、收藏、播放记录和播放进度绑定到 `videoId`，不绑定可变 `path`。

未来 `video_tags` 关系应逐步包含：

```text
videoId
tagId
source: manual / folder / rule / filename / import / auto
locked
createdAt
updatedAt
```

规则：

- 手动标签不能因为文件移动而被删除。
- 文件夹标签可以按路径规则重新计算。
- 规则标签和文件名标签由各自系统重新计算。
- 重要标签可以 locked。
- 文件缺失时标记为 `missing`，不立即删除记录。
- relink 和批量路径替换在稳定身份设计之后推进。

## 新导入流程

推荐流程：

```text
监控文件夹出现新视频
-> 扫描发现它
-> 路径规则尽量派生 folder 标签
-> 无法识别时放入 未分类 / 待整理 / 新导入
-> 用户在应用内批量打标签
-> 未来可选：按标签移动文件
```

按标签移动文件是可选能力，不能成为分类的必要条件。

## Chat 执行计划

### Chat 1：架构与跨平台边界

任务文件：`docs/chat_tasks/CHAT_1_ARCHITECTURE.md`

负责架构、契约、模块边界、路由规则和版本记录。

允许：

- `main.dart`、core/model 边界、未来 import 迁移。
- `FileSystemAdapter`、`PlayerBackend`、`FFmpegBackend`、`DatabaseProvider`。
- repository 接口规划。
- 布局尺寸共享契约。
- 文档和版本记录。

禁止：

- 重写播放器行为。
- 重写 SQLite 查询行为。
- 重写缩略图队列。
- 大范围 UI 重设计。

下一步：

- 推进 `Architecture Baseline 0.4.1`，做低风险 import 迁移或逐步采用 `0.4.0` 契约。

### Chat 2：标签模型、筛选引擎与媒体库

任务文件：`docs/chat_tasks/CHAT_2_MEDIA_LIBRARY.md`

负责 SQLite、扫描、文件夹标签、分组标签模型、别名、筛选引擎和稳定身份规划。

P0：

- 实现分组标签模型。
- 实现别名。
- 实现 `FilterQuery`。
- 实现 AND / OR / NOT 筛选语义。
- 关键字搜索覆盖文件名、路径、标签名、别名。
- 结果数量。
- 把筛选结果传给播放器队列。

P1：

- folder / manual / rule / filename / import / auto 标签来源。
- `video_tags.source` 和 `locked`。
- 稳定 `videoId + fingerprint + mutable path`。
- `missing`。
- relink 和批量路径替换。

### Chat 3：媒体库标签 UI

任务文件：`docs/chat_tasks/CHAT_3_MEDIA_LIBRARY_TAG_UI.md`

负责标签发现功能 UI 和第一轮响应式布局。

P0：

- 分组筛选侧栏。
- 当前筛选 chips。
- 结果数量。
- 清空筛选。
- 排除标签 UI。
- 保存智能列表入口。
- 保持点击播放进入筛选队列。
- expanded / medium / compact 结构。

不要等最终视觉 polish 才建设标签发现 UI。

### Chat 4：播放器筛选队列与 PlayerBackend

任务文件：`docs/chat_tasks/CHAT_4_PLAYER.md`

负责播放稳定性、筛选队列消费、播放器诊断和 `PlayerBackend` 实现。

P0/P1：

- 播放器队列是当前筛选结果。
- 播放器显示类似 `1/1661` 的当前序号。
- 右侧队列标题概括当前筛选。
- 返回媒体库保留筛选状态。
- 右侧队列切换保持稳定。
- 播放页逐步迁移到 `PlayerBackend` 后面，不重写播放器核心。

### Chat 5：缩略图、诊断与 FFmpegBackend

任务文件：`docs/chat_tasks/CHAT_5_THUMBNAIL_DIAGNOSTICS.md`

负责缩略图队列、FFprobe 缓存、缓存诊断、失败、重试和 FFmpeg backend 实现。

P0/P1：

- 播放时保持队列负载保守。
- FFmpeg / FFprobe 通过 `FFmpegBackend` 调用。
- 展示可用性、版本和状态。
- 重试失败的缓存任务。
- 清除失败记录。
- 异常文件列表。
- 卡片式诊断页。

### Chat 6：标签管理器与批量打标

任务文件：`docs/chat_tasks/CHAT_6_TAG_MANAGER.md`

负责长期标签维护 UI 和批量操作。

P1：

- 标签管理页。
- 标签搜索。
- 创建 / 重命名 / 删除标签。
- 合并重复标签。
- 别名。
- 标签组。
- hidden / favorite / sort 标签状态。
- 给当前筛选结果批量打标签。
- 批量移除标签。

### Chat 7：响应式 UI 与平台 polish

任务文件：`docs/chat_tasks/CHAT_7_RESPONSIVE_UI.md`

负责核心标签 UX 可用后的最终视觉一致性和平台 polish。

P1/P2：

- 统一卡片、按钮、弹窗、侧栏风格。
- 媒体库浅色模式和播放器深色模式保持一致。
- 完成 `compact`、`medium`、`expanded` 布局。
- macOS / Linux 适配说明。

## 优先级表

### P0

1. 保持 Windows 桌面稳定。
2. 过渡期保留文件夹派生的一/二级标签。
3. 分组标签模型。
4. `FilterQuery`。
5. 组间 AND、组内 OR、排除 NOT。
6. 按文件名、路径、标签名、别名搜索。
7. 标签结果数量。
8. 当前筛选状态 chips。
9. 筛选结果成为播放队列。
10. 从播放器返回时保留筛选状态。
11. 核心平台边界。

### P1

1. 区分 folder / manual 标签来源。
2. `video_tags.source` 和 `locked`。
3. 稳定身份：`videoId + fingerprint + mutable path`。
4. Missing 状态。
5. Relink。
6. 批量路径替换。
7. 标签管理器。
8. 批量打标。
9. 保存筛选 / 智能列表。
10. 最近播放 / 继续播放。
11. 缓存失败重试。
12. 异常文件列表。
13. 诊断卡片。
14. 初始响应式布局。

### P2

1. 自动标签规则。
2. 标签导入 / 导出。
3. 高级搜索语法。
4. 可选按标签移动文件。
5. 高级指纹去重。
6. 高级播放器功能。
7. macOS / Linux 适配。
8. Android / iOS 探索。
9. Web 探索，低优先级。

## 版本规则

- 每个 Chat 拥有 `docs/chat_tasks/` 下的一个任务文档。
- Chat 文档必须跟随本 roadmap 和外部跨平台规划。
- 如果实现与外部规划冲突，更新实现，或在文档中记录临时偏离原因和 owner。
- 修改 `src/core`、平台边界、schema、身份模型或共享服务契约时，必须更新 `ARCHITECTURE.md`。
- 每个实现 Chat 都运行：

```powershell
flutter analyze
flutter build windows --debug
```

## 新对话规则

新开 Chat 时，使用匹配的 `docs/chat_tasks/CHAT_*` 提示。新对话必须先阅读：

- `PROJECT.md`
- `ARCHITECTURE.md`
- `CURRENT_TASK.md`
- `ROADMAP.md`
- `<private-planning-document>`
- 自己的 `docs/chat_tasks/CHAT_*.md`
