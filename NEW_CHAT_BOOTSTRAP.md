# NEW_CHAT_BOOTSTRAP.md

Local Tag Player 是标签驱动的本地视频发现播放器，不是通用专业播放器。

## 新会话入口

1. 完整读取 `AGENTS.md`，它是产品边界、安全、验证和 Git 规则的唯一权威来源。
2. 根据任务判断 Level 1 / 2 / 3，只读取该 Level 允许的最小上下文。
3. Level 2 / 3 再读取 `PROJECT.md`、`CURRENT_TASK.md` 和一个直接相关的 Chat 文档；只有触及共享 contract、schema、平台边界或优先级时才读架构与路线图。
4. 需要专门流程时只加载最小相关 repo Skill，不要把所有 Skill 和项目历史一起放入上下文。
5. 较大功能、Level 3 或真实媒体 QA 读取 `docs/agent_harness.md`。
6. 修改 Agent、Skill、prompt 或 trigger 时读取 `docs/agent_eval.md`，更新受影响用例并运行 Eval 验证。

## Skill 组合

```text
ltp-task-router：只分级，完成后退出
领域 Skill：拥有业务语义和不可破坏项
ltp-apple-ui-design：仅在明确视觉任务中作为设计覆盖层
```

视觉任务最多组合一个领域 Skill 与 Apple UI 覆盖层。纯 SQLite、过滤、队列、缓存后端和 stable identity 任务不得触发 Apple UI Skill。

## 开始与结束

开始时使用最短第一性原理确认：

```text
Product goal protected:
Core loop part protected:
Must not change:
Smallest safe change:
Fewest safe tokens:
```

结束时按 `AGENTS.md` 完成对抗式审查、对应验证、任务记录、提交和推送。不要在本文件复制当前验证状态、阶段优先级、完整核心规则或命令清单，避免与权威文件漂移。
