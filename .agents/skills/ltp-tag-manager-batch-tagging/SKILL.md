---
name: ltp-tag-manager-batch-tagging
description: Local Tag Player 标签管理器技能。用于 tag manager page、create/rename/merge/delete tags、aliases、hidden/favorite/sort order、batch add/remove manual tags 或当前过滤结果的批量操作。
---

# Local Tag Player 标签管理器

用于标签管理页、批量 manual 标签操作、别名、隐藏、收藏、排序、删除和合并边界。

## 上下文

通常是 Level 2；如果涉及 schema、删除 / 合并迁移或共享模型，升级为 Level 3。

读取：

```text
AGENTS.md
PROJECT.md
CURRENT_TASK.md
docs/chat_tasks/CHAT_6_TAG_MANAGER.md
TagManagerPage / LibraryStore / tag model 相关源码
```

## 规则

- 批量添加 / 移除默认只处理 `manual` 来源标签。
- folder 派生标签不允许直接硬删除。
- 删除 / 合并必须先检查引用关系。
- 用户维护数据必须保留。

## 禁止

- 不改播放器 backend。
- 不改缩略图队列。
- 不做无迁移说明的破坏性 schema 变更。
