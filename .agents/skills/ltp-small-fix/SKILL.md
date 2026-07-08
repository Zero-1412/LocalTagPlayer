---
name: ltp-small-fix
description: Local Tag Player 小修复技能。用于 analyzer/build 报错、单文件编译错误、缺失符号、小 UI 溢出和拼写修复；限制读取范围和 diff。
---

# Local Tag Player 小修复

用于只影响少量文件的 Level 1 修复。

## 只读

```text
AGENTS.md
明确报错或 blocker
直接报错文件
必要时只读直接引用文件
```

## 禁止

```text
ROADMAP.md
ARCHITECTURE.md
CHANGELOG.md
全部 chat history
无关源码文件
```

## 输出限制

- 通常最多修改 1-2 个文件。
- 不做重构。
- 不做设计变更。
- 不做无关格式化。

## 意图

用最小上下文修复明确错误，并保持行为不变。
