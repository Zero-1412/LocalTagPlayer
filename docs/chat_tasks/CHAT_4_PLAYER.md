## 2026-07-12 播放器控制层重排

- 自定义 media_kit controls builder 只负责 UI：底部统一进度、播放/暂停、前后项、时间、倍速、音量与全屏，播放中空闲三秒淡化。
- 下方信息区移除大按钮和路径常驻展示，标题单行 tooltip、队列序号醒目，标签紧凑保留，文件位置等低频动作进入更多菜单。
- 右侧队列顶部缩短为筛选摘要与当前序号，不重复展示多套 chips/计数。
- 真实窗口确认 1280×720 下控制条和信息区无溢出；未改变播放器 open、EOF、filtered queue 或快照写入。

## 2026-07-12 继续观看默认行为

- `PlaybackSettings` 新增继续观看默认策略，旧设置缺少字段时默认从上次位置继续，不再逐条弹窗打断。
- 设置页可切换“从上次位置继续 / 从头播放 / 每次询问”；只有每次询问继续复用原恢复弹窗。
- 播放位置、完成阈值、videoId 绑定和快照写入保持不变。

## 2026-07-12 播放器上下文与对比度 P1 修复

- 右侧 filtered queue 使用媒体库生成的同源摘要并显示当前项数；真实窗口确认“原神 / 雷神 + 关键词 raiden”和 41 项一致。
- 底部上一条、编辑标签和打开位置使用高对比度边框样式；下一条使用主色填充；播放模式与倍速菜单改为暗底亮字。
- 未修改队列来源、EOF 策略、schema、标签过滤语义或缓存队列。

## 2026-07-12 第四阶段隔离真实窗口 smoke

- 隔离 profile 扫描两条真实 18 秒 H264/AAC 媒体，点击确认四种播放模式菜单、随机 EOF 队列切换、0.5x 至 2.0x 六档倍速和 1.5x 当前状态。
- 全屏可见 `2 / 2` 队列上下文和“编辑标签”，folder 来源标签保持只读。
- 首轮发现标签弹窗 Escape 冒泡会误退回媒体库；增加标签编辑期间的页面级 Escape 拦截后，复测只关闭弹窗/全屏并继续停留于播放器。
- 未修改 schema、filtered queue 来源、标签过滤语义、缩略图/media queue，也未进入字幕或音轨建设。

## 2026-07-08 播放页面队列 UI 拆分

- `player_page.dart` 保留播放器生命周期、跳转、快捷键、播放诊断采样和页面级状态协调。
- 底部当前视频与筛选上下文摘要迁到 `pages/player_context_panel.dart`。
- 右侧筛选结果队列、队列项、子标签切换、定位按钮和 `playerQueueIndexIsVisible` 测试 helper 迁到 `pages/player_queue_sidebar.dart`。
- 本轮只做 part 文件拆分，不修改 filtered queue 来源、当前 index、右侧二级标签切换语义、`PlayerBackend` 或缩略图/media 队列。

# CHAT_4_PLAYER.md

## 2026-07-12 播放器蓝图双栏比例修正

- 右侧 filtered queue 宽度改为桌面窗口的约 30%，并限制在 360–500px，保持宽屏信息密度与蓝图一致。
- 队列容器顶边与左侧视频画面统一为 18px；focused test 覆盖 960、1280、1600 和 1920 宽度。
- 未修改 filtered queue 来源、当前 index、EOF、PlayerBackend、标签语义或缩略图/media queue。

## 2026-07-11 播放快照串行写入

- `PlaybackSnapshotWriteQueue` 以稳定 videoId 为合并键，同一视频只保留最新待写状态。
- 全部 SQLite upsert 严格串行，播放器返回媒体库前 flush；失败不会阻塞其它视频并显示稳定提示。
- focused test 验证 `1s→2s→3s` 只写入 `1s、3s`，最大并发 writer 为 1。

## 2026-07-11 继续观看与完成态

- 打开有效进度视频时暂停并询问“从上次位置继续 / 从头播放”，选择期间禁止 0 秒事件覆盖旧进度。
- 低频写入、切换、退出和 EOF 统一保存位置、总时长和完成态；最近播放升级为带进度条的继续观看。
- 短视频尾部阈值为 1-2 秒；长视频按 5% 且限制在 5-30 秒，接近结尾不恢复。
- 队列 missing 项显示缺失状态并停止失效路径预取；失败面板支持 Relink 和跳过，不删除稳定记录。

## 2026-07-11 键盘导航与大队列基准

- manual 标签弹窗支持自动聚焦、Tab/Shift+Tab 候选遍历、Enter 添加、Ctrl+Enter 保存和 Escape 取消。
- 新增 50,000 条 filtered queue 最坏命中基准；本机约 24ms，使用 2 秒宽松上限防止全库访问或超线性退化。
- 基准函数只消费传入队列，不访问媒体库 store、SQLite、缩略图或文件系统。

## 2026-07-11 标签播放器差异化第二阶段

- 播放页提供编辑标签、收藏和打开文件位置，用户无需返回标签中心即可整理当前视频。
- 右侧队列搜索只遍历当前 filtered queue 并直接定位播放，来源队列、当前序号和返回媒体库筛选状态保持不变。
- 收藏和打标只更新当前视频与必要索引；播放器会话中不刷新全库标签计数，返回后只做无计数轻刷新。
- 文件管理器定位通过 platform 边界执行，播放器 UI 不包含 Windows 命令。

## 2026-07-11 稳定身份播放进度

- 播放位置不再按 path 单独记忆，而是保存在稳定 `videoId` 对应的视频记录中；文件移动并自动 relink 后继续沿用原进度。
- 播放中约每 5 秒低频写入，切换或退出时补写；open 成功并确认可播放后恢复位置。
- 距离结尾不足 5 秒的进度不恢复，EOF 后清零，避免自动续播闭环被旧进度重复触发。
- 本轮未改变 filtered queue 来源、连续播放顺序、`PlayerBackend` 或 `FilterQuery` / `TagQueryService` 语义。

## 2026-07-10 隔离坏文件 smoke 与播放器标签入口

- `Player.open` 返回后会检查时长和音视频编码是否至少有一项可用；真实 0-byte MP4 不再停留在假播放状态，而是进入稳定 `unplayable_media` 恢复面板。
- 隔离 profile 的三条队列 smoke 覆盖坏文件诊断与跳过：单条损坏不会阻塞后续正常 H264/AAC 文件。
- 播放器上下文面板新增“编辑手动标签”，保存后刷新当前视频信息但不重建或替换来源 filtered queue。
- 播放进度记忆明确等待 Stable Video Identity 后实施，本轮不新增 path 绑定的进度持久化。
- 本轮未修改 schema、`PlayerBackend`、filtered queue 来源、`FilterQuery` / `TagQueryService` 或缩略图/media 队列。

## 2026-07-10 连续播放与错误恢复闭环

- `PlayerPage` 订阅 `media_kit` 完成事件，只在库页传入的 filtered queue 内顺序推进；队尾停止并持续显示完成提示，不默认循环。
- 播放器上下文面板增加显式上一条/下一条按钮；原有 `PageUp / PageDown` 快捷键保持不变。
- `PlayerOpenRequestController` 增加可恢复失败状态；稳定错误面板提供重试、跳过和诊断详情，同时避免把异常正文和本地路径写入可复制摘要。
- 播放诊断入口移动到顶部，诊断弹窗支持复制不含本地路径的摘要，并显示弹窗内复制完成态。
- focused tests 覆盖顺序队列边界、队尾不循环、快速 open 最新请求和失败重试；真实窗口覆盖 EOF 自动下一条、队尾停止、诊断复制和返回筛选状态。
- 本轮未修改 `PlayerBackend`、filtered queue 来源、SQLite schema、`FilterQuery` / `TagQueryService` 或缩略图/media 队列。

当前版本：`0.3.0`
状态：进行中
负责人：Chat 4 / 播放器筛选队列 + PlayerBackend

## 规划来源

主要来源：

```text
<private-planning-document>
```

如果本文档与该文件冲突，以外部规划为准。

## 范围

负责播放稳定性、筛选播放队列消费、硬解、右侧队列行为、诊断、`PlaybackSession` 和 `PlayerBackend` 实现。

允许：

- `PlayerPage` 和未来 `PlayerService`。
- 右侧队列 / 列表行为。
- 播放诊断。
- `PlaybackSession` 消费。
- 未来 `platform/player`。

禁止：

- 标签数据库 / schema 重设计。
- 缩略图队列内部逻辑。
- 大范围 UI 视觉 polish。
- 当前阶段未明确要求时，不做字幕、音轨、逐帧、A-B loop、滤镜、复杂比例控制等高级播放器功能。

## P0 / P1 任务

- 播放器队列必须代表当前筛选结果，而不是无关全局列表。
- 进入和返回播放器时保留筛选上下文。
- 增加或维护当前序号显示，例如 `1/1661`。
- 右侧队列标题应概括当前筛选。
- 支持从右侧队列切换视频。
- 保持视频信息入口稳定。
- 保持播放诊断入口稳定。
- 后续让诊断信息可复制。
- 在不重写播放器核心的前提下，把播放页逐步移到 `PlayerBackend` 后面。
- 添加高级播放器功能前，先修复 async open / jump 竞态风险。

## 新对话提示

```text
这是 Chat 4 / 播放器筛选队列 + PlayerBackend。项目路径：<project-root>。
请先阅读：
- PROJECT.md
- ARCHITECTURE.md
- CURRENT_TASK.md
- ROADMAP.md
- <private-planning-document>
- docs/chat_tasks/CHAT_4_PLAYER.md

职责：播放器消费当前筛选队列、维护右侧队列、播放诊断、PlaybackSession 和 PlayerBackend。
不要修改标签 schema、缩略图队列或无关视觉重构。标签发现闭环稳定前，不优先做专业播放器增强。
修改代码后运行：
- flutter analyze
- flutter build windows --debug
```

## 变更记录

- `0.4.1`：按播放器产品蓝图对齐页面级布局。新增品牌顶栏、当前队列搜索、丰富视频身份卡、队列总数徽标和快捷键提示；排除蓝图右上角“打开文件”，继续由媒体库筛选结果进入播放器。完整测试、analyze 和 Windows debug build 通过；默认大型媒体库启动持续停留加载层，隔离媒体点击复测待补。
- `0.4.0`：完成第四阶段轻量播放增强。新增顺序、随机、单曲循环、列表循环和六档倍速；补充空格、J/L、`[`/`]` 高频快捷键；全屏控制层展示当前 filtered queue 序号、筛选标题和编辑标签入口。未修改 schema、队列来源、标签过滤语义或缓存队列，也未提前建设字幕和音轨能力。

- `0.3.0`：完成第一轮播放器筛选队列：`PlayerPage` 消费安全的筛选队列副本，展示筛选摘要上下文，右侧二级标签切换保持在筛选队列内，并串行化快速 open 请求，让最新 jump 生效。验收修复统一了空筛选标题、序号显示和待处理 open 排空行为。
- `0.2.0`：按外部跨平台规划重定播放器任务，聚焦筛选队列消费和 `PlayerBackend`。
- `0.1.0`：创建任务模板。

## 2026-07-08 播放诊断与播放状态协调拆分

- 新增 `PlayerPlaybackController`，集中维护来源播放队列、当前二级标签、正在播放索引和选中索引；页面仍负责 mpv 打开、快捷键、删除确认和 UI 生命周期。
- 新增 `player_diagnostics_dialog.dart`，承接播放诊断弹窗、连续采样 timer 和播放状态订阅；关闭弹窗时继续释放异步资源。
- 本轮未修改 `PlayerBackend`、filtered queue 来源、当前 index 展示、右侧二级标签切换语义或缩略图/media 队列。

## 2026-07-08 播放 open 请求与删除确认拆分

- 新增 `PlayerOpenRequestController`，集中最新待打开路径、open worker 运行状态和打开中遮罩状态；`PlayerPage` 继续负责实际 `Player.open` 调用和 mpv 参数设置。
- 新增 `player_delete_dialog.dart`，承接删除视频文件确认弹窗，后续可继续扩展删除影响提示。
- 本轮未修改 `PlayerBackend`、filtered queue 来源、当前 index 展示、右侧二级标签切换语义或缩略图/media 队列。

## 2026-07-08 播放状态协调测试补强

- 新增 `PlayerPlaybackController` focused test，覆盖二级标签切换、再次点击取消二级筛选，以及二级标签无结果时回退来源过滤队列。
- 新增 `PlayerOpenRequestController` focused test，覆盖 open worker 运行中失败或结束前仍保留最新待打开请求，避免快速切换时丢失最后一次打开意图。
- 本轮未修改 `PlayerBackend`、filtered queue 来源、当前 index 展示、右侧二级标签切换语义或缩略图/media 队列。
