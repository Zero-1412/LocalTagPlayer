# CURRENT_TASK.md

> 本文件只保存当前活跃任务、最近稳定基线、已确认阻塞和下一步入口。
> 已完成的详细记录迁入 `docs/task_history/`，新任务默认不读取历史归档。

## 活跃任务

### 2026-07-21 CURRENT_TASK 活跃区 / 历史区拆分

- 目标：把累计任务流水从默认上下文中移出，保留一个短小、可信、可直接路由的新会话入口。
- 范围：仅调整任务记录结构并运行 Agent Eval 的确定性验证；不修改 `AGENTS.md`、Skill、Agent prompt 或 Flutter 业务代码。
- done_when：旧记录无损归档；活跃文件只保留当前事实和索引；归档可被目录检查发现；Agent Eval 目录验证与 scorer 单元测试通过；根据已有 N=5 成本基线明确是否需要继续压缩全局规则。
- 验证模式：Level 2 `structured`，验证阶段停止编辑并逐项记录证据。
- 当前状态：已完成。默认入口由 1,017 行、82,073 字符缩减为 54 行、2,135 字符；旧记录完整归档且索引可达。
- 验证：Agent Eval 目录保持 61 个用例、44/6/11 suite 分布和 11 个 Skill 的 2 正 2 负覆盖；16 项 scorer 单元测试通过；Level 2 结构化回归 N=5 为 5/5、平均 100 分、`stable=true`，零基础设施错误和零隔离文件改动。
- 成本结论：本轮累计输入 746,901 token，高于旧基线 404,105；定向 Trace 显示新运行发生 13 次工具调用、旧基线为 6 次，且单个高探索试次占 348,431 token。没有试次读取历史归档，匹配的常规上下文读取试次由约 167k 降到约 118k。
- 晋级决定：归档结构 `promoted`；全局规则压缩 `not_promoted`。当前没有规则遗漏、冲突或稳定性退化证据，聚合成本上升由探索路径方差主导，不能据此重写 `AGENTS.md`。

## 当前稳定基线

- 产品边界：Tag 驱动的本地视频发现播放器；SQLite schema、标签过滤语义、filtered queue、播放器/缓存后端和用户数据均不在本轮范围。
- 最新应用交付：`c1a63a8`（完成标签维护缩放终态验收）。
- Agent Harness champion：`afc4c14`（固化 Harness champion 基线）。
- 最近完整应用验证：226 项测试通过，3 项显式 benchmark 跳过；`flutter analyze` 与 Windows debug build 通过。
- Agent Eval 基线：61 个用例，11 个 Skill 均保持 2 个正触发与 2 个负触发覆盖；关键 Level 1/2/3 回归均为 N=5、5/5、平均 100 分、`stable=true`。

## 已确认阻塞

- 当前没有与本轮任务相关的实现阻塞。
- 历史记录中的旧“待观察”和“下一步建议”不自动视为当前事实；需要恢复时必须按新任务重新验证。

## 最近交付（最多保留三项）

1. `c1a63a8`：完成 125%/150% 标签维护连续终态验收，修复下拉裁切与高风险弹窗主题。
2. `afc4c14`：固化 Agent Harness champion 基线。
3. `88d9bf8`：完善 Level 1/2/3 分级结构化验证闭环。

## 下一步入口

1. 当前没有未完成的 Agent 文档实现任务。
2. 若要进一步衡量规则文件长度，应先新增固定读取路径的成本用例，隔离“文件体积”和“自主探索次数”两个变量；现有回归不适合仅凭累计 token 判断全局压缩收益。
3. 仅当 Eval 出现规则遗漏、冲突或同工具路径下的可复现成本回升时，再建立全局规则压缩 challenger；不要直接重写 `AGENTS.md`。
4. 新的产品任务从 `NEW_CHAT_BOOTSTRAP.md` 路由，按 Level 读取最小上下文和一个直接相关 Chat 文档。

## 历史归档索引

- [截至 2026-07-19 的完整任务记录](docs/task_history/CURRENT_TASK_HISTORY_THROUGH_2026-07-19.md)
- 产品行为变更摘要：`CHANGELOG.md`
- 分阶段实现记录：`docs/chat_tasks/CHAT_*.md`
- Agent Harness 规则与基线：`docs/agent_harness.md`、`docs/agent_eval.md`

## 新 Chat 启动入口

新会话统一从 `NEW_CHAT_BOOTSTRAP.md` 路由。先按 Level 读取最小上下文；只有 Level 3、共享 contract、schema、平台边界或优先级任务才读取架构、路线图和外部跨平台计划。
