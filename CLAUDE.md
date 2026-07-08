# CLAUDE.md

本项目使用 `AGENTS.md` 作为 AI coding agents 的共享指令入口。

Claude 必须先阅读 `AGENTS.md` 的“项目快照”，然后遵守 `AGENTS.md` 中的全部详细规则。

分析或修改代码前，Claude 必须按 `AGENTS.md` 的上下文级别读取文件：

- Level 1 小修复：只读 `AGENTS.md`、明确报错/blocker、直接相关文件。
- Level 2 有限功能或 UI 任务：读 `AGENTS.md`、`PROJECT.md`、`CURRENT_TASK.md`、一个相关 `docs/chat_tasks/CHAT_*.md`、直接相关文件。
- Level 3 架构/schema/边界任务：读完整项目上下文，包括 `ARCHITECTURE.md`、`ROADMAP.md`、`CHANGELOG.md`、相关 Chat 文档、`<private-planning-document>`。

不要为了每个小修复读取完整项目历史。

Claude 每个项目任务都必须遵守两条推理规则：

1. 从第一性原理出发，并用最少安全 token 完成当前任务。
2. 完成计划或代码修改前做对抗式审查，确认提示本身没有引入不必要的范围、上下文或输出成本。

除非任务是 Level 3，否则第一性原理和对抗式审查都应保持短而可操作。

除代码本身、第三方 API、协议、命令、路径、固定术语和外部错误信息外，文档新增/修改、代码注释、Git 提交信息、任务记录和交接摘要都必须以中文为第一语言。

不要把本项目当作通用专业视频播放器。

项目目标：

```text
Tag-driven local video discovery player
```

核心闭环：

```text
scan -> tag -> filter -> filtered queue -> play -> manage tags -> diagnose cache
```

如果本文件与 `AGENTS.md` 冲突，以 `AGENTS.md` 为准。

Claude 还必须遵守会话和 token 卫生：

- 一个会话尽量聚焦一个交付物。
- 任务切换时写短交接摘要，不携带完整历史。
- 不粘贴或返回完整日志、完整 diff、大 CSV/JSON 或长命令输出。
- 优先给文件路径和搜索词，只读取失败附近 30-80 行。
- Level 3 或范围不清时，先写短计划再编辑，不写长篇规划。
- 优先使用 `.agents/skills` 下最小相关 repo skill，不重复稳定规则。
- token 优化是正确性的一部分，但不要盲目删除同一交付物的有效上下文。
