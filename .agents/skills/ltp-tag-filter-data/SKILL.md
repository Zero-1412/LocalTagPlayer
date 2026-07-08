---
name: ltp-tag-filter-data
description: Local Tag Player 标签数据与过滤引擎技能。用于 TagGroup、TagItem、aliases、FilterQuery、TagQueryService、SQLite tag indexes、folder/manual tag source rules 或 result counts。
---

# Local Tag Player 标签数据与过滤引擎

用于标签模型、过滤语义、SQLite 标签索引、标签来源规则和结果计数。

## 上下文

通常是 Level 3，因为该技能经常触及 schema、`FilterQuery` 或 `TagQueryService`。

读取：

```text
AGENTS.md
PROJECT.md
ARCHITECTURE.md
CURRENT_TASK.md
ROADMAP.md
docs/chat_tasks/CHAT_2_MEDIA_LIBRARY.md
相关模型、store、query service 源码
```

## 语义规则

- 不同组：AND。
- 同组：OR。
- 排除标签：NOT。
- 关键字匹配文件名、路径、标签名和标签别名。
- folder 标签是路径派生初始分类。
- manual 标签是用户维护数据，不能被自动流程静默删除。
- 能使用 tagId 时优先使用 tagId。

## 禁止

- 不在 UI 中复制过滤逻辑。
- 不把 Windows 路径假设写入平台无关查询层。
- 不静默改变 schema 或用户维护数据。
