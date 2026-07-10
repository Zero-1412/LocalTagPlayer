## 2026-07-08 播放页面队列 UI 拆分

- `player_page.dart` 保留播放器生命周期、跳转、快捷键、播放诊断采样和页面级状态协调。
- 底部当前视频与筛选上下文摘要迁到 `pages/player_context_panel.dart`。
- 右侧筛选结果队列、队列项、子标签切换、定位按钮和 `playerQueueIndexIsVisible` 测试 helper 迁到 `pages/player_queue_sidebar.dart`。
- 本轮只做 part 文件拆分，不修改 filtered queue 来源、当前 index、右侧二级标签切换语义、`PlayerBackend` 或缩略图/media 队列。

# CHAT_4_PLAYER.md

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
