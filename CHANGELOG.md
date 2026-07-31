# CHANGELOG.md

本文件只保存未发布变更和版本索引。完整逐项历史位于
`docs/history/changelog/CHANGELOG_HISTORY_THROUGH_2026-07-30.md`；
不要把旧条目复制回根文件。

## Unreleased

### Agent 治理与上下文

- 为 repo Skill 增加严格 UTF-8、frontmatter、Agent UI 元数据和松散 Markdown 校验。
- 为 `AGENTS.md`、`CURRENT_TASK.md`、bootstrap、Project、Claude 和 Harness 增加
  行数/字符预算，并在相关 pull request/push 上运行零模型成本门禁。
- `CURRENT_TASK.md` 收缩为当前任务、最近三项、稳定基线、阻塞和下一步；
  2026-07-20 至 2026-07-30 的原文无损迁入 task history。
- `AGENTS.md`、`PROJECT.md`、`CLAUDE.md` 和 Agent Harness 建立单一事实源，
  默认核心入口收缩到约 4.2k tokens。
- 修复 CI 仓库位于用户目录下时 Trace 路径遮盖顺序错误，并增加跨平台回归。
- 将 Architecture、Roadmap 和 Changelog 的当前合同与时间线历史分离。

### 不受影响的业务边界

- SQLite schema、migration 和用户数据库未修改；
- `FilterQuery` / `TagQueryService` 语义未修改；
- filtered playback queue、PlayerBackend 和缓存队列未修改；
- UI、标签来源、用户媒体和可达功能未修改。

## 发布版本

- [0.2.4](docs/RELEASE_NOTES_0.2.4.md)
- [0.2.3](docs/RELEASE_NOTES_0.2.3.md)
- [0.2.0](docs/RELEASE_NOTES_0.2.0.md)

发布产物和摘要以 [GitHub Releases](https://github.com/Zero-1412/LocalTagPlayer/releases)
为准。历史条目是实现证据，不自动代表当前优先级或当前架构合同。
