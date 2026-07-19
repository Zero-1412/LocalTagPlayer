---
name: ltp-session-handoff
description: Local Tag Player 会话交接技能。用于 Codex 会话过长、compact 后恢复、任务切换、或需要用最小上下文移交到新聚焦会话。
---

# Local Tag Player 会话交接

用于会话过长、compact 后恢复、任务切换或把当前工作移交到新对话。

## 触发

- 上下文窗口接近 70%。
- 当前任务要切换到无关领域。
- 需要新会话聚焦一个交付物。
- compact 后需要恢复最小上下文。

## 交接格式

```text
目标：
任务级别 / 验证模式：
当前状态：
已改文件：
剩余 done_when：
验证记录：
晋级状态：promoted / not_promoted / needs_manual_qa
剩余阻塞：
禁止改动：
下一条精确命令或任务：
```

## 规则

- 不复制完整历史。
- 不粘贴完整日志。
- 只保留最近一次失败原因、已确认事实和仍未覆盖的 `done_when`。
- 验证记录必须区分 `passed / failed / blocked / not_run`，未执行项不能写成通过。
- 只保留继续开发所需的最小上下文。
