# CURRENT_TASK.md

> 本文件只保存当前活跃任务、最近稳定基线、已确认阻塞和下一步入口。
> 已完成的详细记录迁入 `docs/task_history/`，新任务默认不读取历史归档。

## 活跃任务

### 2026-07-21 播放器 Route、转场与反馈收口

- 目标：修复播放器 Route 语义隔离和返回媒体库的黑帧/重置态闪现；统一列表/详情与设置层级的非重叠转场；补全快捷键和队列搜索状态反馈；完成小范围排版精修。
- 范围：只改媒体库与播放器 Route 协调、播放器页面/侧栏/设置/队列 UI、共享动效 token 和对应测试；不改 SQLite schema、过滤语义、filtered queue 内容/顺序、`PlayerBackend`、缓存队列或用户数据。
- 当前状态：已完成。媒体库在播放器 Route 存续期间先提交语义排除，播放器声明独立 route scope；正常返回只 pause 并保留最后一帧，stop/dispose 延后到反向 Route 启动后，pause 失败才提前 stop。
- P1/P2：列表/详情与设置改为旧层级退出后新层级再进入；播放、暂停、seek、上下条、倍速、音量和全屏快捷键显示短时 HUD 并恢复控制条；队列搜索明确为“查找并播放下一条”并提供成功、无匹配、空查询状态；路径对比度、详情字号和徽标密度完成小幅调整。
- 验证：229 项测试通过，3 项显式 benchmark 跳过；`flutter analyze`、Windows debug build 通过。1249×714 最新 Debug 实窗确认播放器期间 UIA 不再暴露媒体库节点、返回后恢复；70ms 返回中间帧保留真实视频画面和播放时间，没有黑帧或 0:00 重置；快捷键 HUD、两处顺序转场、搜索文案/空查询反馈和详情排版无遮挡、错位或溢出。

## 当前稳定基线

- 产品边界：Tag 驱动的本地视频发现播放器；SQLite schema、标签过滤语义、filtered queue、播放器/缓存后端和用户数据均不在本轮范围。
- 最新应用交付：播放器 Route、非重叠转场与状态反馈收口（本文件所在提交）。
- Agent Harness champion：`afc4c14`（固化 Harness champion 基线）。
- 最近完整应用验证：229 项测试通过，3 项显式 benchmark 跳过；`flutter analyze` 与 Windows debug build 通过。
- Agent Eval 基线：61 个用例，11 个 Skill 均保持 2 个正触发与 2 个负触发覆盖；关键 Level 1/2/3 回归均为 N=5、5/5、平均 100 分、`stable=true`。

## 已确认阻塞

- 当前没有与本轮任务相关的实现阻塞。
- 历史记录中的旧“待观察”和“下一步建议”不自动视为当前事实；需要恢复时必须按新任务重新验证。

## 最近交付（最多保留三项）

1. 播放器 Route、非重叠转场、快捷键/队列搜索反馈与排版收口（本文件所在提交）。
2. `c1a63a8`：完成 125%/150% 标签维护连续终态验收，修复下拉裁切与高风险弹窗主题。
3. `afc4c14`：固化 Agent Harness champion 基线。

## 下一步入口

1. 用真实键盘单独复核队列搜索成功态的中文输入手感；当前自动化输入因 Windows UIA 只暴露播放器通用窗格而未注入文本，成功/无匹配/空查询三态均已有 widget 回归，实窗已覆盖文案与空查询态。
2. 若继续做播放器视觉精修，优先在 125%/150% 文字缩放下复核详情长路径和搜索状态行，不扩展到字幕、音轨或其它高级播放器能力。
3. 新的产品任务从 `NEW_CHAT_BOOTSTRAP.md` 路由，按 Level 读取最小上下文和一个直接相关 Chat 文档。

## 历史归档索引

- [截至 2026-07-19 的完整任务记录](docs/task_history/CURRENT_TASK_HISTORY_THROUGH_2026-07-19.md)
- 产品行为变更摘要：`CHANGELOG.md`
- 分阶段实现记录：`docs/chat_tasks/CHAT_*.md`
- Agent Harness 规则与基线：`docs/agent_harness.md`、`docs/agent_eval.md`

## 新 Chat 启动入口

新会话统一从 `NEW_CHAT_BOOTSTRAP.md` 路由。先按 Level 读取最小上下文；只有 Level 3、共享 contract、schema、平台边界或优先级任务才读取架构、路线图和外部跨平台计划。
