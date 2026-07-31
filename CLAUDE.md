# CLAUDE.md

本仓库的 AI coding agent 单一权威规则是 `AGENTS.md`。Claude 开始任务时：

1. 完整读取 `AGENTS.md`；
2. 按其中 Level 规则加载最小上下文；
3. 需要领域流程时只选最小 `.agents/skills/ltp-*` Skill；
4. 使用根目录 `NEW_CHAT_BOOTSTRAP.md` 建立第一性原理和结束审查。

本文件只提供兼容入口，不复制产品、Level、验证、token、中文或 Git 规则。
如有冲突，以 `AGENTS.md` 为准。
