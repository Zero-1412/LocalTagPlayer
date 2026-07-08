---
name: ltp-log-triage
description: Local Tag Player 日志排查技能。用于长 Flutter/Codex/CI 日志、build 失败、analyzer 输出文件或命令 transcript；只搜索关键错误附近内容，不读取完整日志。
---

# Local Tag Player 日志排查

用于处理长日志、构建失败、analyzer 输出和命令 transcript。

## 方法

- 优先搜索 `ERROR`、`Exception`、`failed`、`exit code`、`undefined symbol`。
- 只读取命中位置附近 30-80 行。
- 不把完整日志贴进上下文。

## 输出

- 关键错误。
- 相关文件和行号。
- 最小复现命令。
- 建议的最小修复范围。
