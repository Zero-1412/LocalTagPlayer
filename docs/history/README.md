# 历史资产索引

本目录保存已经完成、被替代或仅用于复现实验的证据。默认任务上下文不得递归读取本目录；只有在确认历史行为、回归来源或实验参数时，才按精确文件路径读取。

| 目录 | 内容 | 当前替代入口 |
| --- | --- | --- |
| `architecture/` | 旧架构全文、完成记录和已执行方案 | 根目录 `ARCHITECTURE.md` |
| `chat/` | Chat 1—7 完整阶段记录 | `docs/chat_tasks/CHAT_*.md` 短契约 |
| `changelog/` | 历史版本日志 | 根目录 `CHANGELOG.md` |
| `experiments/` | 一次性技术实验 | 对应当前架构或 QA gate |
| `governance/` | 被替代的 Agent 治理入口 | 根目录 `AGENTS.md`、`NEW_CHAT_BOOTSTRAP.md` |
| `qa/2026-07/` | 2026-07 的运行证据和研究快照 | `docs/qa/` 当前 gate、`tool/qa/manifest.json` |
| `roadmap/` | 旧路线全文 | 根目录 `ROADMAP.md` |

历史文件可以修正失效链接或补充归档状态，但不得回写成当前事实来源。
