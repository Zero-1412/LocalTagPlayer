---
name: ltp-task-router
description: Local Tag Player 任务路由技能。用于开始新任务、判断 Level 1/2/3、限制上下文读取范围、决定是否需要短计划或会话交接。
---

# Local Tag Player 任务路由

用于在执行前判断任务级别，并限制读取范围。

## 分级规则

```text
语法错误 / analyzer 或 build 单点错误 / 小 UI 溢出 -> Level 1
单个页面、组件、服务的有限功能 -> Level 2
schema / architecture / src/core / platform boundary / stable identity -> Level 3
FilterQuery / TagQueryService / PlayerBackend / player queue / cache queue -> Level 3
生产事故 / 真实窗口发现的未授权功能删除 / 既有行为保护失效 -> Level 3
```

## 输出

只返回：

```text
级别：
允许文件：
禁止文件：
是否需要先写计划：是/否
验证模式：single_agent / structured / independent
```

验证模式与 Level 固定对应：

```text
Level 1 -> single_agent
Level 2 -> structured
Level 3 -> independent
```

`independent` 表示实现结束后进入停止编辑的独立验证阶段；可由独立 Agent，
或上下文重置后的只读验证回合承担，不要求 Level 1 小修复引入多 Agent。

## 约束

- 默认不要全项目扫描。
- 默认不要读取 `ROADMAP.md`、`ARCHITECTURE.md`、`CHANGELOG.md` 或全部 Chat 文档。
- 如果调查中发现需要改 schema、`FilterQuery`、`TagQueryService`、平台边界、stable identity 或 player/cache queue，立即升级为 Level 3。
- 生产或真实窗口已经发生的未授权功能删除必须升级为 Level 3，并使用 `independent` 验证；不能因为修复代码量小而降级为普通 UI 小修。
- 来源 filtered queue、播放器队列回退或缓存队列时序属于共享业务边界，即使任务表面上是只读诊断，也必须按 Level 3 路由；普通页面视觉与不触及队列的缓存有效性 UI 仍可保持 Level 2。
